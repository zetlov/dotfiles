import QtQuick
import Quickshell.Io

Item {
    id: root

    property bool available: false
    property string deviceName: ""
    property string deviceClass: ""
    property int level: 0
    property int rawValue: 0
    property int rawMax: 0
    property string pendingCommand: ""

    readonly property string text: available ? `${level}%` : "Unavailable"

    function refresh() {
        if (!infoProcess.running)
            infoProcess.running = true;
    }

    function setLevel(percent) {
        if (!available)
            return;

        const clamped = Math.max(1, Math.min(100, Math.round(percent)));
        root.pendingCommand = `brightnessctl --class=backlight set ${clamped}%`;
        actionProcess.running = true;
    }

    function stepLevel(delta) {
        if (!available)
            return;

        setLevel(level + delta);
    }

    Timer {
        interval: 10000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: refresh()
    }

    Process {
        id: infoProcess

        command: ["bash", "-lc", "brightnessctl -m --class=backlight info 2>/dev/null || true"]

        stdout: StdioCollector {
            onStreamFinished: {
                const raw = this.text.trim();
                if (!raw) {
                    root.available = false;
                    root.deviceName = "";
                    root.deviceClass = "";
                    root.level = 0;
                    root.rawValue = 0;
                    root.rawMax = 0;
                    return;
                }

                const parts = raw.split(",");
                root.deviceName = parts[0] || "";
                root.deviceClass = parts[1] || "";
                root.rawValue = Number(parts[2] || 0);
                const percentText = (parts[3] || "0%").replace("%", "");
                root.level = Number(percentText || 0);
                root.rawMax = Number(parts[4] || 0);
                root.available = root.deviceClass === "backlight";
            }
        }
    }

    Process {
        id: actionProcess

        command: ["bash", "-lc", root.pendingCommand]
        onExited: refresh()
    }
}
