import QtQuick
import Quickshell.Io

Item {
    id: root

    property int officialCount: 0
    property int aurCount: 0
    property bool running: updateProcess.running
    readonly property int count: officialCount + aurCount
    readonly property bool hasUpdates: count > 0
    readonly property string summary: hasUpdates ? `${officialCount} official  ${aurCount} aur` : "System up to date"
    readonly property string text: hasUpdates ? `${count}` : "0"

    function refresh() {
        if (!updateProcess.running)
            updateProcess.running = true;
    }

    Timer {
        interval: 1800000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Process {
        id: updateProcess

        command: [
            "bash",
            "-lc",
            "if command -v checkupdates >/dev/null 2>&1; then off=$(checkupdates 2>/dev/null | wc -l); else off=0; fi; " +
            "if command -v yay >/dev/null 2>&1; then aur=$(yay -Qua 2>/dev/null | wc -l); else aur=0; fi; " +
            "printf '%s %s\\n' \"$off\" \"$aur\""
        ]

        stdout: StdioCollector {
            onStreamFinished: {
                const parts = this.text.trim().split(/\s+/);
                root.officialCount = parseInt(parts[0], 10) || 0;
                root.aurCount = parseInt(parts[1], 10) || 0;
            }
        }
    }
}
