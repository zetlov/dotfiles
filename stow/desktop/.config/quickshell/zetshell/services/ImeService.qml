import QtQuick
import Quickshell.Io

Item {
    id: root

    property string methodName: ""
    readonly property bool active: methodName !== "" && !methodName.toLowerCase().includes("keyboard")
    readonly property string badgeText: {
        const name = methodName.toLowerCase();
        if (name.includes("mozc") || name.includes("hiragana") || name.includes("japanese"))
            return "あ";
        if (name.length === 0 || name.includes("keyboard") || name.includes("english"))
            return "A";

        return "A";
    }

    function refresh() {
        if (!imeProcess.running)
            imeProcess.running = true;
    }

    Timer {
        interval: 1000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Process {
        id: imeProcess

        command: ["fcitx5-remote", "-n"]

        stdout: StdioCollector {
            onStreamFinished: root.methodName = this.text.trim()
        }
    }
}
