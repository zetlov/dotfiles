import QtQuick
import Quickshell.Io

Item {
    id: root

    property string osName: "Linux"
    property string wmName: "Hyprland"
    property string uptime: ""
    property string faceUrl: ""

    Timer {
        interval: 60 * 1000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: {
            osRelease.reload();
            if (!uptimeProcess.running)
                uptimeProcess.running = true;
            if (!faceProcess.running)
                faceProcess.running = true;
        }
    }

    FileView {
        id: osRelease

        path: "/etc/os-release"

        onLoaded: {
            const pretty = text().match(/^PRETTY_NAME="?([^"\n]+)"?/m);
            const name = text().match(/^NAME="?([^"\n]+)"?/m);
            root.osName = pretty ? pretty[1] : name ? name[1] : "Linux";
        }
    }

    Process {
        id: uptimeProcess

        command: ["sh", "-c", "uptime -p 2>/dev/null | sed 's/^up //'"]

        stdout: StdioCollector {
            onStreamFinished: root.uptime = text.trim()
        }
    }

    Process {
        id: faceProcess

        command: ["sh", "-c", "test -f \"$HOME/.face\" && printf 'file://%s/.face' \"$HOME\""]

        stdout: StdioCollector {
            onStreamFinished: root.faceUrl = text.trim()
        }

        onExited: exitCode => {
            if (exitCode !== 0)
                root.faceUrl = "";
        }
    }
}
