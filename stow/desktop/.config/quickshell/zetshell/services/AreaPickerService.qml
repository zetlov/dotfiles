import QtQuick
import Quickshell.Io

Item {
    id: root

    property bool open: false
    property bool closing: false
    property string mode: "region"
    property string destination: "clipboard"
    property string actionKind: "screenshot"
    property bool withAudio: true
    property var clients: []

    function refreshClients() {
        if (!clientsProcess.running)
            clientsProcess.running = true;
    }

    function openPicker(nextMode, nextDestination, nextActionKind, nextWithAudio) {
        mode = nextMode || "region";
        destination = nextDestination || "clipboard";
        actionKind = nextActionKind || "screenshot";
        withAudio = nextWithAudio !== false;
        closing = false;
        open = true;
        refreshClients();
    }

    function close() {
        closing = true;
        open = false;
    }

    Process {
        id: clientsProcess

        command: ["bash", "-lc", "hyprctl -j clients"]

        stdout: StdioCollector {
            onStreamFinished: {
                const raw = this.text.trim();
                if (!raw) {
                    root.clients = [];
                    return;
                }

                try {
                    const parsed = JSON.parse(raw);
                    root.clients = parsed.filter(client => client.mapped && !client.hidden && client.workspace && client.workspace.id >= 0);
                } catch (error) {
                    console.warn("Failed to parse picker clients:", error);
                }
            }
        }
    }
}
