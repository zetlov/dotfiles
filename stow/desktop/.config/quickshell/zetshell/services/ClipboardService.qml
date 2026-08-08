import QtQuick
import Quickshell.Io

Item {
    id: root

    property var items: []
    property string query: ""
    property int selectedIndex: 0
    property string lastActionLabel: ""
    property string actionMessage: ""
    property bool actionError: false
    readonly property bool busy: listProcess.running || actionProcess.running
    readonly property string normalizedQuery: query.trim().toLowerCase()
    readonly property var filteredItems: {
        const needle = normalizedQuery;
        if (!needle)
            return items;

        return items.filter(item => {
            const title = (item.title || "").toLowerCase();
            const subtitle = (item.subtitle || "").toLowerCase();
            const preview = (item.preview || "").toLowerCase();
            return title.indexOf(needle) !== -1 || subtitle.indexOf(needle) !== -1 || preview.indexOf(needle) !== -1;
        });
    }
    readonly property bool hasItems: filteredItems.length > 0
    readonly property string statusText: actionMessage !== ""
        ? actionMessage
        : hasItems
            ? `${filteredItems.length} clipboard entries`
            : "Clipboard history is empty"

    onFilteredItemsChanged: {
        if (!filteredItems.length) {
            selectedIndex = 0;
            return;
        }

        if (selectedIndex >= filteredItems.length)
            selectedIndex = filteredItems.length - 1;
    }

    function refresh() {
        if (!listProcess.running)
            listProcess.running = true;
    }

    function clearQuery() {
        query = "";
    }

    function appendQuery(text) {
        query += text;
    }

    function backspaceQuery() {
        if (query.length > 0)
            query = query.slice(0, -1);
    }

    function moveSelection(delta) {
        if (!filteredItems.length)
            return;

        selectedIndex = Math.max(0, Math.min(filteredItems.length - 1, selectedIndex + delta));
    }

    function copy(id) {
        if (id === undefined || actionProcess.running)
            return;

        lastActionLabel = `Copied clipboard entry ${id}`;
        actionProcess.command = [
            "bash",
            "-lc",
            `~/.config/hypr/scripts/clipboard_state.sh copy ${Number(id)}`
        ];
        actionProcess.running = true;
    }

    function deleteEntry(id) {
        if (id === undefined || actionProcess.running)
            return;

        lastActionLabel = `Deleted clipboard entry ${id}`;
        actionProcess.command = [
            "bash",
            "-lc",
            `~/.config/hypr/scripts/clipboard_state.sh delete ${Number(id)}`
        ];
        actionProcess.running = true;
    }

    function copySelected() {
        if (!hasItems)
            return;
        copy(filteredItems[selectedIndex].id);
    }

    function deleteSelected() {
        if (!hasItems)
            return;
        deleteEntry(filteredItems[selectedIndex].id);
    }

    Timer {
        interval: 12000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Process {
        id: listProcess

        command: [
            "bash",
            "-lc",
            "~/.config/hypr/scripts/clipboard_state.sh list"
        ]

        stdout: StdioCollector {
            onStreamFinished: {
                const raw = this.text.trim();
                if (!raw) {
                    root.items = [];
                    return;
                }

                try {
                    root.items = JSON.parse(raw);
                } catch (error) {
                    console.warn("Failed to parse clipboard state:", error);
                }
            }
        }
    }

    Process {
        id: actionProcess

        stdout: StdioCollector {}
        stderr: StdioCollector {}

        onExited: exitCode => {
            const stderrText = actionProcess.stderr.text.trim();
            const stdoutText = actionProcess.stdout.text.trim();

            if (exitCode === 0) {
                root.actionError = false;
                root.actionMessage = stdoutText || root.lastActionLabel || "Clipboard updated";
            } else {
                root.actionError = true;
                root.actionMessage = stderrText || stdoutText || "Clipboard action failed";
            }

            root.refresh();
        }
    }
}
