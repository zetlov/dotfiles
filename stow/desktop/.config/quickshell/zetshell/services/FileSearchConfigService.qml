import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    property var roots: ["~/Desktop", "~/Documents", "~/Downloads"]
    property bool includeQuicklinkDirectories: true
    property var exclude: [".git", ".cache", ".direnv", ".next", ".nuxt", ".pytest_cache", ".mypy_cache", "__pycache__", "node_modules", ".venv", "venv", "build", "dist", "target"]
    property var excludeExtensions: []
    property int maxItems: 15000
    property int rootSearchMinQuery: 2
    property bool saveBusy: saveProcess.running
    property string saveMessage: ""
    property bool saveError: false

    function defaultConfig() {
        return {
            "roots": ["~/Desktop", "~/Documents", "~/Downloads"],
            "includeQuicklinkDirectories": true,
            "exclude": [".git", ".cache", ".direnv", ".next", ".nuxt", ".pytest_cache", ".mypy_cache", "__pycache__", "node_modules", ".venv", "venv", "build", "dist", "target"],
            "excludeExtensions": [],
            "maxItems": 15000,
            "rootSearchMinQuery": 2
        };
    }

    function normalizeStringList(values) {
        if (!Array.isArray(values))
            return [];

        const normalized = [];
        for (const value of values) {
            const text = String(value || "").trim();
            if (!text || normalized.indexOf(text) !== -1)
                continue;

            normalized.push(text);
        }
        return normalized;
    }

    function normalizedConfig(payload) {
        const defaults = defaultConfig();
        const roots = normalizeStringList(payload && payload.roots);
        const excludeList = normalizeStringList(payload && payload.exclude);
        const excludeExtensionList = normalizeExtensionList(payload && payload.excludeExtensions);
        return {
            "roots": roots.length > 0 ? roots : defaults.roots,
            "includeQuicklinkDirectories": payload && typeof payload.includeQuicklinkDirectories === "boolean" ? payload.includeQuicklinkDirectories : defaults.includeQuicklinkDirectories,
            "exclude": excludeList,
            "excludeExtensions": excludeExtensionList,
            "maxItems": payload && Number.isInteger(payload.maxItems) && payload.maxItems > 0 ? payload.maxItems : defaults.maxItems,
            "rootSearchMinQuery": payload && Number.isInteger(payload.rootSearchMinQuery) && payload.rootSearchMinQuery >= 0 ? payload.rootSearchMinQuery : defaults.rootSearchMinQuery
        };
    }

    function normalizeExtensionList(values) {
        const normalized = [];
        for (const value of normalizeStringList(values)) {
            let text = value.toLowerCase();
            if (!text.startsWith("."))
                text = "." + text;

            if (normalized.indexOf(text) !== -1)
                continue;

            normalized.push(text);
        }
        return normalized;
    }

    function applyConfig(payload) {
        const next = normalizedConfig(payload);
        root.roots = next.roots;
        root.includeQuicklinkDirectories = next.includeQuicklinkDirectories;
        root.exclude = next.exclude;
        root.excludeExtensions = next.excludeExtensions;
        root.maxItems = next.maxItems;
        root.rootSearchMinQuery = next.rootSearchMinQuery;
    }

    function saveConfig(payload) {
        const next = normalizedConfig(payload);
        root.saveMessage = "Saving...";
        root.saveError = false;
        saveProcess.command = ["python", `${Quickshell.env("HOME")}/.config/quickshell/zetshell/scripts/save_file_search_config.py`, JSON.stringify(next)];
        saveProcess.running = true;
    }

    function reload() {
        configFile.reload();
    }

    Timer {
        interval: 2500
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: configFile.reload()
    }

    Process {
        id: saveProcess

        command: ["bash", "-lc", "true"]
        onExited: {
            if (exitCode === 0) {
                root.saveMessage = "Saved";
                root.saveError = false;
                configFile.reload();
            } else {
                root.saveError = true;
                if (!root.saveMessage)
                    root.saveMessage = "Failed to save";

            }
        }

        stdout: StdioCollector {
        }

        stderr: StdioCollector {
            onStreamFinished: {
                const raw = this.text.trim();
                if (raw.length > 0) {
                    root.saveMessage = raw;
                    root.saveError = true;
                }
            }
        }

    }

    FileView {
        id: configFile

        path: `${Quickshell.env("HOME")}/.config/zetshell/file_search.json`
        onLoaded: {
            const raw = text().trim();
            if (!raw) {
                root.applyConfig(root.defaultConfig());
                return ;
            }
            try {
                root.applyConfig(JSON.parse(raw));
            } catch (error) {
                root.saveMessage = "Failed to parse file search config";
                root.saveError = true;
                console.warn("Failed to parse file search config:", error);
            }
        }
    }

}
