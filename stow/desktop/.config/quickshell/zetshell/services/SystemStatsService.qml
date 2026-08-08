import QtQuick
import Quickshell.Io

Item {
    id: root

    property QtObject config: null
    property int cpuPercent: 0
    property string cpuName: ""
    property real cpuTemp: 0
    property int ramPercent: 0
    property int storagePercent: 0
    property string gpuName: ""
    property int gpuPercent: 0
    property real gpuTemp: 0
    property bool hasGpu: false
    property bool hasBattery: false
    property int batteryPercent: 0
    property string batteryStatus: ""
    property string batteryTime: ""
    property real downloadBytesPerSec: 0
    property real uploadBytesPerSec: 0
    property real downloadTotalBytes: 0
    property real uploadTotalBytes: 0
    property int previousIdle: 0
    property int previousTotal: 0
    property real initialRxBytes: 0
    property real initialTxBytes: 0
    property real previousRxBytes: 0
    property real previousTxBytes: 0
    property real previousNetTimestamp: 0
    property bool networkInitialized: false
    property int storageRefreshTick: 0
    property int detailRefreshTick: 0

    readonly property string downloadText: formatBytes(downloadBytesPerSec)
    readonly property string uploadText: formatBytes(uploadBytesPerSec)
    readonly property string downloadTotalText: formatBytesTotal(downloadTotalBytes)
    readonly property string uploadTotalText: formatBytesTotal(uploadTotalBytes)

    function formatBytes(bytes) {
        if (!bytes || bytes < 0 || !isFinite(bytes))
            return "0 B/s";

        if (bytes < 1024)
            return `${Math.round(bytes)} B/s`;
        if (bytes < 1024 * 1024)
            return `${(bytes / 1024).toFixed(1)} KB/s`;
        if (bytes < 1024 * 1024 * 1024)
            return `${(bytes / (1024 * 1024)).toFixed(1)} MB/s`;

        return `${(bytes / (1024 * 1024 * 1024)).toFixed(1)} GB/s`;
    }

    function formatBytesTotal(bytes) {
        if (!bytes || bytes < 0 || !isFinite(bytes))
            return "0 B";

        if (bytes < 1024)
            return `${Math.round(bytes)} B`;
        if (bytes < 1024 * 1024)
            return `${(bytes / 1024).toFixed(1)} KB`;
        if (bytes < 1024 * 1024 * 1024)
            return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;

        return `${(bytes / (1024 * 1024 * 1024)).toFixed(1)} GB`;
    }

    function cleanCpuName(name) {
        return name.replace(/\(R\)|\(TM\)|CPU|Processor/gi, "").replace(/\s+/g, " ").trim();
    }

    function cleanGpuName(name) {
        return name.replace(/\(R\)|\(TM\)|Graphics/gi, "").replace(/\s+/g, " ").trim();
    }

    function parseNetworkTotals(content) {
        const lines = content.split("\n");
        let rx = 0;
        let tx = 0;

        for (let i = 2; i < lines.length; i++) {
            const line = lines[i].trim();
            if (!line)
                continue;

            const parts = line.split(/\s+/);
            if (parts.length < 10)
                continue;

            const iface = parts[0].replace(":", "");
            if (iface === "lo")
                continue;

            rx += parseFloat(parts[1]) || 0;
            tx += parseFloat(parts[9]) || 0;
        }

        return { rx, tx };
    }

    Timer {
        interval: config ? config.resourceUpdateInterval : 2000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: {
            cpuStat.reload();
            memInfo.reload();
            netDev.reload();

            root.storageRefreshTick += 1;
            if (root.storageRefreshTick === 1 || root.storageRefreshTick >= 15) {
                root.storageRefreshTick = 1;
                if (!storageProcess.running)
                    storageProcess.running = true;
            }

            root.detailRefreshTick += 1;
            const detailTicks = Math.max(1, Math.round((config ? config.detailUpdateInterval : 10000) / interval));
            if (root.detailRefreshTick === 1 || root.detailRefreshTick >= detailTicks) {
                root.detailRefreshTick = 1;
                if (!sensorsProcess.running)
                    sensorsProcess.running = true;
                if (!gpuProcess.running)
                    gpuProcess.running = true;
                if (!batteryProcess.running)
                    batteryProcess.running = true;
            }
        }
    }

    FileView {
        id: cpuInfo

        path: "/proc/cpuinfo"

        onLoaded: {
            const match = text().match(/model name\s*:\s*(.+)/);
            if (match)
                root.cpuName = root.cleanCpuName(match[1]);
        }
    }

    FileView {
        id: cpuStat

        path: "/proc/stat"

        onLoaded: {
            const match = text().match(/^cpu\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)/);
            if (!match)
                return;

            const values = match.slice(1).map(value => parseInt(value, 10));
            const total = values.reduce((sum, value) => sum + value, 0);
            const idle = values[3] + values[4];

            if (root.previousTotal === 0) {
                root.previousTotal = total;
                root.previousIdle = idle;
                root.cpuPercent = 0;
                return;
            }

            const totalDiff = total - root.previousTotal;
            const idleDiff = idle - root.previousIdle;

            root.previousTotal = total;
            root.previousIdle = idle;

            if (totalDiff <= 0) {
                root.cpuPercent = 0;
                return;
            }

            root.cpuPercent = Math.max(0, Math.round((1 - idleDiff / totalDiff) * 100));
        }
    }

    FileView {
        id: memInfo

        path: "/proc/meminfo"

        onLoaded: {
            const totalMatch = text().match(/^MemTotal:\s+(\d+)/m);
            const availableMatch = text().match(/^MemAvailable:\s+(\d+)/m);
            if (!totalMatch || !availableMatch)
                return;

            const total = parseInt(totalMatch[1], 10);
            const available = parseInt(availableMatch[1], 10);

            if (total <= 0) {
                root.ramPercent = 0;
                return;
            }

            root.ramPercent = Math.max(0, Math.round(((total - available) / total) * 100));
        }
    }

    FileView {
        id: netDev

        path: "/proc/net/dev"

        onLoaded: {
            const totals = root.parseNetworkTotals(text());
            const now = Date.now();

            if (!root.networkInitialized) {
                root.initialRxBytes = totals.rx;
                root.initialTxBytes = totals.tx;
                root.previousRxBytes = totals.rx;
                root.previousTxBytes = totals.tx;
                root.previousNetTimestamp = now;
                root.networkInitialized = true;
                return;
            }

            const seconds = (now - root.previousNetTimestamp) / 1000;
            if (seconds <= 0)
                return;

            root.downloadBytesPerSec = Math.max(0, (totals.rx - root.previousRxBytes) / seconds);
            root.uploadBytesPerSec = Math.max(0, (totals.tx - root.previousTxBytes) / seconds);
            root.downloadTotalBytes = Math.max(0, totals.rx - root.initialRxBytes);
            root.uploadTotalBytes = Math.max(0, totals.tx - root.initialTxBytes);

            root.previousRxBytes = totals.rx;
            root.previousTxBytes = totals.tx;
            root.previousNetTimestamp = now;
        }
    }

    Process {
        id: storageProcess

        command: ["sh", "-c", "df -k --output=used,size / 2>/dev/null | tail -n 1"]

        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split(/\s+/);
                if (parts.length < 2)
                    return;

                const used = parseInt(parts[0], 10);
                const total = parseInt(parts[1], 10);
                if (!total || total <= 0)
                    return;

                root.storagePercent = Math.max(0, Math.min(100, Math.round((used / total) * 100)));
            }
        }
    }

    Process {
        id: sensorsProcess

        command: ["sh", "-c", "sensors 2>/dev/null || true"]

        stdout: StdioCollector {
            onStreamFinished: {
                let match = text.match(/(?:Package id [0-9]+|Tdie|Tctl):\s+\+?([0-9.]+)(?:°| )C/);
                if (match)
                    root.cpuTemp = parseFloat(match[1]) || 0;
            }
        }
    }

    Process {
        id: gpuProcess

        command: [
            "sh",
            "-c",
            "if command -v nvidia-smi >/dev/null 2>&1; then nvidia-smi --query-gpu=name,utilization.gpu,temperature.gpu --format=csv,noheader,nounits 2>/dev/null | head -n 1; else busy=$(cat /sys/class/drm/card*/device/gpu_busy_percent 2>/dev/null | head -n 1); name=$(lspci 2>/dev/null | grep -Ei 'vga|3d controller|display' | head -n 1 | sed 's/.*: //'); [ -n \"$busy$name\" ] && printf '%s,%s,0\\n' \"$name\" \"${busy:-0}\"; fi"
        ]

        stdout: StdioCollector {
            onStreamFinished: {
                const raw = text.trim();
                if (!raw) {
                    root.hasGpu = false;
                    return;
                }

                const parts = raw.split(",");
                root.gpuName = root.cleanGpuName(parts[0] || "GPU");
                root.gpuPercent = Math.max(0, Math.min(100, parseInt(parts[1], 10) || 0));
                root.gpuTemp = parseFloat(parts[2]) || 0;
                root.hasGpu = true;
            }
        }
    }

    Process {
        id: batteryProcess

        command: [
            "sh",
            "-c",
            "bat=$(find /sys/class/power_supply -maxdepth 1 -type l -name 'BAT*' | head -n 1); [ -z \"$bat\" ] && exit 1; cap=$(cat \"$bat/capacity\" 2>/dev/null); status=$(cat \"$bat/status\" 2>/dev/null); now=$(cat \"$bat/energy_now\" \"$bat/charge_now\" 2>/dev/null | head -n 1); power=$(cat \"$bat/power_now\" \"$bat/current_now\" 2>/dev/null | head -n 1); time=''; if [ -n \"$now\" ] && [ -n \"$power\" ] && [ \"$power\" -gt 0 ] 2>/dev/null; then mins=$((now * 60 / power)); time=$(printf '%dh %02dm' $((mins / 60)) $((mins % 60))); fi; printf '%s|%s|%s\\n' \"${cap:-0}\" \"${status:-Unknown}\" \"$time\""
        ]

        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split("|");
                if (parts.length < 2)
                    return;

                root.batteryPercent = Math.max(0, Math.min(100, parseInt(parts[0], 10) || 0));
                root.batteryStatus = parts[1] || "Unknown";
                root.batteryTime = parts[2] || "";
                root.hasBattery = true;
            }
        }

        onExited: exitCode => {
            if (exitCode !== 0)
                root.hasBattery = false;
        }
    }
}
