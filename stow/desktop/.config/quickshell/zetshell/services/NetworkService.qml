import QtQuick
import Quickshell.Io

Item {
    id: root

    property string state: "unknown"
    property string label: "Scanning"
    property string deviceName: ""
    property string connectionName: ""
    property string vpnName: ""
    property bool wifiEnabled: true
    property int signal: 0
    property string security: ""
    property var networks: []
    property var pendingCommand: []
    property string pendingInput: ""
    property string pendingActionLabel: ""
    property string lastActionLabel: ""
    property string actionMessage: ""
    property bool actionError: false

    readonly property bool connected: state === "wifi" || state === "ethernet"
    readonly property bool hasVpn: vpnName !== ""
    readonly property bool busy: actionProcess.running
    readonly property string statusText: {
        if (busy)
            return `${pendingActionLabel || "Working"}...`;
        if (actionMessage)
            return actionMessage;
        if (hasVpn)
            return `VPN ${vpnName}`;
        if (state === "wifi")
            return signal > 0 ? `${signal}% signal` : "Connected";
        if (state === "ethernet")
            return connectionName || "Wired connected";
        if (state === "disabled")
            return "Wi-Fi radio disabled";
        if (state === "offline")
            return "No active network";

        return "Scanning";
    }
    readonly property string text: {
        if (state === "wifi")
            return `Wi-Fi ${label}`;
        if (state === "ethernet")
            return `Ethernet ${label}`;
        if (state === "disabled")
            return "Wi-Fi Off";
        if (state === "offline")
            return "Offline";

        return "Scanning";
    }
    readonly property color tone: {
        if (state === "wifi")
            return "#7ae7d7";
        if (state === "ethernet")
            return "#9fd6ff";
        if (state === "disabled")
            return "#8aa0b3";
        if (state === "offline")
            return "#ff9e9e";

        return "#8aa0b3";
    }

    function refresh() {
        if (busy)
            return;
        if (!networkProcess.running)
            networkProcess.running = true;
    }

    function toggleWifi() {
        root.pendingActionLabel = wifiEnabled ? "Turning Wi-Fi off" : "Turning Wi-Fi on";
        root.actionError = false;
        root.actionMessage = "";
        root.pendingCommand = ["nmcli", "radio", "wifi", wifiEnabled ? "off" : "on"];
        actionProcess.running = true;
    }

    function disconnectCurrent() {
        if (!deviceName)
            return;

        root.pendingActionLabel = "Disconnecting";
        root.actionError = false;
        root.actionMessage = "";
        root.pendingCommand = ["nmcli", "device", "disconnect", deviceName];
        actionProcess.running = true;
    }

    function activateNetwork(network) {
        if (!network || !network.ssid)
            return;

        if (network.active) {
            refresh();
            return;
        }

        if (network.known && network.profileUuid) {
            root.pendingActionLabel = `Connecting ${network.ssid}`;
            root.pendingCommand = ["nmcli", "connection", "up", "uuid", network.profileUuid];
        } else if (network.connectable) {
            root.pendingActionLabel = `Connecting ${network.ssid}`;
            root.pendingCommand = ["nmcli", "dev", "wifi", "connect", network.ssid];
        } else {
            return;
        }

        root.actionError = false;
        root.actionMessage = "";
        actionProcess.running = true;
    }

    function connectWithPassword(ssid, password) {
        if (!ssid || !password || password.length === 0)
            return;

        root.pendingActionLabel = `Connecting ${ssid}`;
        root.actionError = false;
        root.actionMessage = "";
        root.pendingInput = `${password}\n`;
        root.pendingCommand = ["nmcli", "--ask", "dev", "wifi", "connect", ssid];
        actionProcess.running = true;
    }

    Timer {
        interval: 7000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: refresh()
    }

    Process {
        id: networkProcess

        command: [
            "bash",
            "-lc",
            "exec \"$HOME/.local/bin/zetshell-network-status.sh\""
        ]

        stdout: StdioCollector {
            onStreamFinished: {
                const raw = this.text.trim();
                if (!raw) {
                    root.state = "unknown";
                    root.label = "Scanning";
                    root.networks = [];
                    return;
                }

                const parsed = JSON.parse(raw);
                root.state = parsed.state || "unknown";
                root.label = parsed.label || "Unknown";
                root.deviceName = parsed.deviceName || "";
                root.connectionName = parsed.connectionName || "";
                root.vpnName = parsed.vpnName || "";
                root.wifiEnabled = parsed.wifiEnabled !== false;
                root.signal = parsed.signal || 0;
                root.security = parsed.security || "";
                root.networks = parsed.networks || [];
            }
        }
    }

    Process {
        id: actionProcess

        command: root.pendingCommand
        stdinEnabled: true
        stdout: StdioCollector {}

        stderr: StdioCollector {}

        onStarted: {
            if (root.pendingInput) {
                actionProcess.write(root.pendingInput);
                root.pendingInput = "";
            }
        }

        onExited: exitCode => {
            root.lastActionLabel = root.pendingActionLabel;

            const stderrText = actionProcess.stderr.text.trim();
            const stdoutText = actionProcess.stdout.text.trim();
            const details = stderrText || stdoutText;

            if (exitCode === 0) {
                root.actionError = false;
                root.actionMessage = root.lastActionLabel ? `${root.lastActionLabel} complete.` : "";
                profileCacheProcess.running = true;
            } else {
                root.actionError = true;
                root.actionMessage = details || `${root.lastActionLabel || "Network action"} failed.`;
            }

            root.pendingActionLabel = "";
            root.pendingCommand = [];
            root.pendingInput = "";
            if (exitCode !== 0)
                refresh();
        }
    }

    Process {
        id: profileCacheProcess

        command: [
            "bash",
            "-lc",
            "exec \"$HOME/.local/bin/zetshell-network-status.sh\" --invalidate"
        ]
        onExited: refresh()
    }
}
