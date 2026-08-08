import QtQuick
import Quickshell.Io

Item {
    id: root

    property string currentPath: ""
    property string currentName: ""
    property string mode: "dark"
    property var wallpapers: []
    property var favorites: []
    property var recent: []
    property string lastActionLabel: ""
    property string actionMessage: ""
    property bool actionError: false
    property string pendingCommand: ""
    readonly property bool busy: listProcess.running || actionProcess.running
    readonly property bool hasWallpapers: wallpapers.length > 0
    readonly property bool currentFavorite: currentPath !== "" && favorites.indexOf(currentPath) !== -1
    readonly property bool isLightMode: mode === "light"
    readonly property string statusText: actionMessage !== ""
        ? actionMessage
        : hasWallpapers
            ? `${wallpapers.length} wallpapers  ${mode}`
            : "No wallpapers found"

    function shellEscape(value) {
        return `'${String(value).replace(/'/g, `'\"'\"'`)}'`;
    }

    function refresh() {
        if (!listProcess.running)
            listProcess.running = true;
    }

    function apply(path) {
        if (!path || actionProcess.running)
            return;

        root.pendingCommand = path;
        root.lastActionLabel = `Applied ${path.split("/").pop()}`;
        actionProcess.command = [
            "bash",
            "-lc",
            `~/.config/hypr/scripts/wallpaper_state.sh apply ${shellEscape(path)}`
        ];
        actionProcess.running = true;
    }

    function applyRandom() {
        if (!hasWallpapers)
            return;

        const pool = wallpapers.filter(item => item.path !== currentPath);
        const source = pool.length > 0 ? pool : wallpapers;
        const selected = source[Math.floor(Math.random() * source.length)];
        if (selected)
            apply(selected.path);
    }

    function toggleFavorite(path) {
        if (!path || actionProcess.running)
            return;

        root.pendingCommand = path;
        root.lastActionLabel = "Updated favorites";
        actionProcess.command = [
            "bash",
            "-lc",
            `~/.config/hypr/scripts/wallpaper_state.sh toggle-favorite ${shellEscape(path)}`
        ];
        actionProcess.running = true;
    }

    function toggleFavoriteCurrent() {
        if (currentPath)
            toggleFavorite(currentPath);
    }

    function setMode(nextMode) {
        if (!nextMode || (nextMode !== "dark" && nextMode !== "light") || actionProcess.running)
            return;

        root.pendingCommand = nextMode;
        root.lastActionLabel = `Theme mode ${nextMode}`;
        actionProcess.command = [
            "bash",
            "-lc",
            `~/.config/hypr/scripts/wallpaper_state.sh set-mode ${shellEscape(nextMode)}`
        ];
        actionProcess.running = true;
    }

    Timer {
        interval: 15000
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
            "~/.config/hypr/scripts/wallpaper_state.sh list"
        ]

        stdout: StdioCollector {
            onStreamFinished: {
                const raw = this.text.trim();
                if (!raw)
                    return;

                try {
                    const parsed = JSON.parse(raw);
                    root.currentPath = parsed.currentPath || "";
                    root.currentName = parsed.currentName || "";
                    root.mode = parsed.mode || "dark";
                    root.wallpapers = parsed.wallpapers || [];
                    root.favorites = parsed.favorites || [];
                    root.recent = parsed.recent || [];
                } catch (error) {
                    console.warn("Failed to parse wallpaper state:", error);
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
                root.actionMessage = stdoutText || root.lastActionLabel || "Wallpaper updated";
            } else {
                root.actionError = true;
                root.actionMessage = stderrText || stdoutText || "Wallpaper action failed";
            }

            root.pendingCommand = "";
            root.refresh();
        }
    }
}
