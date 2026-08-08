import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    property bool open: false
    property string query: ""
    property string preferredProvider: ""
    readonly property string clipboardKeyword: "clip"
    readonly property string emojiKeyword: "emo"
    readonly property string fileKeyword: "file"
    readonly property string systemKeyword: "sys"
    property int selectedIndex: 0
    property bool actionPanelOpen: false
    property int selectedActionIndex: 0
    property var availableIcons: null
    property var emojiItems: []
    property bool emojiIndexLoaded: false
    property var fileItems: []
    property bool fileIndexLoaded: false
    property string quicklinksConfigText: ""
    property string fileSearchConfigText: ""
    property var fileSearchConfig: ({
        "roots": ["~/Desktop", "~/Documents", "~/Downloads"],
        "includeQuicklinkDirectories": true,
        "exclude": [".git", ".cache", ".direnv", ".next", ".nuxt", ".pytest_cache", ".mypy_cache", "__pycache__", "node_modules", ".venv", "venv", "build", "dist", "target"],
        "maxItems": 15000,
        "rootSearchMinQuery": 2
    })
    property var quicklinks: []
    property var launcherConfig: ({
        "apps": {
            "favorites": [],
            "aliases": {
            }
        },
        "quicklinks": {
            "favorites": [],
            "aliases": {
            }
        }
    })
    readonly property bool systemConfirmationPending: systemActions.armedAction.length > 0
    readonly property string systemConfirmationAction: systemActions.armedAction
    readonly property var providerOrder: preferredProvider === "clipboard" ? ["clipboard"] : preferredProvider === "system" ? ["system"] : preferredProvider === "emoji" ? ["emoji"] : preferredProvider === "files" ? ["files"] : ["apps", "quicklinks", "files", "calculator", "emoji", "system", "clipboard"]
    readonly property var allApps: {
        const entries = DesktopEntries.applications;
        if (!entries)
            return [];

        return (entries.values || []).filter((app) => {
            return !app.noDisplay;
        });
    }
    readonly property var results: {
        const rawQuery = root.query.trim();
        const q = rawQuery.toLowerCase();
        const clipboardQuery = root.clipboardSearchQuery(rawQuery, q);
        const clipboardOnly = clipboardQuery !== null;
        const providerIds = clipboardOnly ? ["clipboard"] : root.providerOrder;
        let items = [];
        for (const providerId of providerIds) {
            if (providerId === "clipboard")
                items = items.concat(root.searchClipboard(clipboardQuery));
            else
                items = items.concat(root.searchProvider(providerId, rawQuery, q));
        }
        return items.sort((a, b) => {
            const appPriority = compareAppsFirst(a, b);
            if (appPriority !== 0)
                return appPriority;

            const filePriority = compareFilesLast(a, b);
            if (filePriority !== 0)
                return filePriority;

            return b.score - a.score || a.title.localeCompare(b.title);
        });
    }
    readonly property int resultCount: results ? results.length : 0
    readonly property var selectedResult: selectedIndex >= 0 && selectedIndex < resultCount ? results[selectedIndex] : null
    readonly property var selectedActions: selectedResult && selectedResult.actions ? selectedResult.actions : []
    readonly property string emptyStateText: query.length > 0 ? "No matches" : preferredProvider === "clipboard" ? "Clipboard history is empty" : "Start typing to search"
    readonly property string statusText: resultCount > 0 ? `${resultCount} result${resultCount !== 1 ? "s" : ""}` : query.length > 0 ? "No results" : `${allApps.length + quicklinks.length + systemCommands().length} items`

    function clipboardSearchQuery(rawQuery, normalizedQuery) {
        if (preferredProvider === "clipboard")
            return rawQuery.trim();

        if (normalizedQuery === clipboardKeyword)
            return "";

        if (normalizedQuery.startsWith(`${clipboardKeyword} `))
            return rawQuery.slice(clipboardKeyword.length).trim();

        return null;
    }

    function emojiSearchQuery(rawQuery, normalizedQuery) {
        if (preferredProvider === "emoji")
            return rawQuery.trim();

        if (normalizedQuery === emojiKeyword)
            return "";

        if (normalizedQuery.startsWith(`${emojiKeyword} `))
            return rawQuery.slice(emojiKeyword.length).trim();

        return rawQuery.trim();
    }

    function fileSearchQuery(rawQuery, normalizedQuery) {
        if (preferredProvider === "files")
            return rawQuery.trim();

        if (normalizedQuery === fileKeyword)
            return "";

        if (normalizedQuery.startsWith(`${fileKeyword} `))
            return rawQuery.slice(fileKeyword.length).trim();

        return rawQuery.trim();
    }

    function systemSearchQuery(rawQuery, normalizedQuery) {
        if (preferredProvider === "system")
            return rawQuery.trim();

        if (normalizedQuery === systemKeyword)
            return "";

        if (normalizedQuery.startsWith(`${systemKeyword} `))
            return rawQuery.slice(systemKeyword.length).trim();

        return rawQuery.trim();
    }

    function searchProvider(providerId, rawQuery, normalizedQuery) {
        if (providerId === "apps")
            return searchApps(normalizedQuery);

        if (providerId === "quicklinks")
            return searchQuicklinks(rawQuery, normalizedQuery);

        if (providerId === "files")
            return searchFiles(rawQuery, normalizedQuery);

        if (providerId === "calculator")
            return searchCalculator(rawQuery);

        if (providerId === "emoji")
            return searchEmoji(rawQuery, normalizedQuery);

        if (providerId === "system")
            return searchSystem(rawQuery, normalizedQuery);

        return [];
    }

    function searchApps(normalizedQuery) {
        const all = root.allApps;
        if (!normalizedQuery)
            return all.slice().sort((a, b) => {
            return compareByFavoriteThenTitle(a, b, "apps", appConfigKeys(a), appConfigKeys(b), appTitle);
        }).map((app, index) => {
            return createAppResult(app, 10 + favoriteBoost("apps", appConfigKeys(app)) - index * 0.001);
        });

        return all.map((app) => {
            const name = (app.name || "").toLowerCase();
            const generic = (app.genericName || "").toLowerCase();
            const comment = (app.comment || "").toLowerCase();
            const aliases = aliasesFor("apps", appConfigKeys(app), []);
            let score = aliasScore(normalizedQuery, aliases);
            if (score === 0) {
                if (name.startsWith(normalizedQuery))
                    score = 4;
                else if (name.includes(normalizedQuery))
                    score = 3;
                else if (generic.startsWith(normalizedQuery))
                    score = 2;
                else if (generic.includes(normalizedQuery) || comment.includes(normalizedQuery))
                    score = 1;
            }
            if (score === 0)
                return null;

            return createAppResult(app, score + favoriteBoost("apps", appConfigKeys(app)));
        }).filter((x) => {
            return x !== null;
        });
    }

    function createAppResult(app, score) {
        const title = appTitle(app);
        const aliases = aliasesFor("apps", appConfigKeys(app), []);
        const favorite = isFavorite("apps", appConfigKeys(app));
        return {
            "id": `app:${app.id || title}`,
            "provider": "apps",
            "type": "application",
            "title": title,
            "subtitle": resultSubtitle(app.genericName || app.comment || "", aliases),
            "icon": app.icon || "",
            "keywords": [app.genericName || "", app.comment || ""].concat(aliases).filter((value) => {
                return value.length > 0;
            }),
            "score": score,
            "primaryAction": "launch",
            "actions": [{
                "id": "launch",
                "title": "Launch",
                "shortcut": "Enter"
            }, {
                "id": "copy-name",
                "title": "Copy App Name"
            }, {
                "id": "copy-id",
                "title": "Copy Desktop Entry ID"
            }],
            "payload": {
                "desktopEntry": app,
                "aliases": aliases,
                "favorite": favorite
            }
        };
    }

    function applyQuicklinksConfig(payload) {
        const links = Array.isArray(payload) ? payload : payload.quicklinks || [];
        root.quicklinks = links.map((item, index) => {
            const name = String(item.name || item.title || item.id || `Quicklink ${index + 1}`);
            const aliases = normalizeAliasList([item.alias].concat(Array.isArray(item.aliases) ? item.aliases : []));
            return {
                "id": String(item.id || name.toLowerCase().replace(/\s+/g, "-")),
                "name": name,
                "url": String(item.url || item.path || ""),
                "aliases": aliases,
                "openWith": String(item.openWith || ""),
                "tags": Array.isArray(item.tags) ? item.tags.map((tag) => {
                    return String(tag);
                }) : [],
                "icon": String(item.icon || "")
            };
        }).filter((item) => {
            return item.url.length > 0;
        });
    }

    function applyLauncherConfig(payload) {
        const apps = payload && payload.apps ? payload.apps : {
        };
        const quicklinks = payload && payload.quicklinks ? payload.quicklinks : {
        };
        root.launcherConfig = {
            "apps": {
                "favorites": normalizeConfigKeys(Array.isArray(apps.favorites) ? apps.favorites : []),
                "aliases": normalizeAliasConfigMap(apps.aliases)
            },
            "quicklinks": {
                "favorites": normalizeConfigKeys(Array.isArray(quicklinks.favorites) ? quicklinks.favorites : []),
                "aliases": normalizeAliasConfigMap(quicklinks.aliases)
            }
        };
    }

    function defaultFileSearchConfig() {
        return {
            "roots": ["~/Desktop", "~/Documents", "~/Downloads"],
            "includeQuicklinkDirectories": true,
            "exclude": [".git", ".cache", ".direnv", ".next", ".nuxt", ".pytest_cache", ".mypy_cache", "__pycache__", "node_modules", ".venv", "venv", "build", "dist", "target"],
            "maxItems": 15000,
            "rootSearchMinQuery": 2
        };
    }

    function applyFileSearchConfig(payload) {
        const defaults = defaultFileSearchConfig();
        const nextRoots = Array.isArray(payload && payload.roots) ? payload.roots.map((value) => {
            return String(value);
        }).filter((value) => {
            return value.trim().length > 0;
        }) : defaults.roots;
        const nextExclude = Array.isArray(payload && payload.exclude) ? payload.exclude.map((value) => {
            return String(value);
        }).filter((value) => {
            return value.trim().length > 0;
        }) : defaults.exclude;
        const nextMaxItems = payload && Number.isInteger(payload.maxItems) && payload.maxItems > 0 ? payload.maxItems : defaults.maxItems;
        const nextRootSearchMinQuery = payload && Number.isInteger(payload.rootSearchMinQuery) && payload.rootSearchMinQuery >= 0 ? payload.rootSearchMinQuery : defaults.rootSearchMinQuery;
        const nextIncludeQuicklinkDirectories = payload && typeof payload.includeQuicklinkDirectories === "boolean" ? payload.includeQuicklinkDirectories : defaults.includeQuicklinkDirectories;
        root.fileSearchConfig = {
            "roots": nextRoots,
            "includeQuicklinkDirectories": nextIncludeQuicklinkDirectories,
            "exclude": nextExclude,
            "maxItems": nextMaxItems,
            "rootSearchMinQuery": nextRootSearchMinQuery
        };
    }

    function normalizeConfigKey(value) {
        return String(value || "").trim().toLowerCase();
    }

    function normalizeConfigKeys(values) {
        return uniqueStrings(values.map((value) => {
            return normalizeConfigKey(value);
        }).filter((value) => {
            return value.length > 0;
        }));
    }

    function normalizeAliasList(values) {
        return uniqueStrings(values.map((value) => {
            return normalizeConfigKey(value);
        }).filter((value) => {
            return value.length > 0;
        }));
    }

    function normalizeAliasConfigMap(input) {
        const output = {
        };
        if (!input || typeof input !== "object")
            return output;

        for (const [key, value] of Object.entries(input)) {
            const normalizedKey = normalizeConfigKey(key);
            if (!normalizedKey)
                continue;

            const aliases = normalizeAliasList(Array.isArray(value) ? value : [value]);
            if (aliases.length > 0)
                output[normalizedKey] = aliases;

        }
        return output;
    }

    function uniqueStrings(values) {
        const result = [];
        for (const value of values) {
            if (result.indexOf(value) === -1)
                result.push(value);

        }
        return result;
    }

    function appConfigKeys(app) {
        return normalizeConfigKeys([app && app.id ? app.id : "", appTitle(app), slugifyConfigKey(appTitle(app))]);
    }

    function quicklinkConfigKeys(link) {
        return normalizeConfigKeys([link && link.id ? link.id : "", link && link.name ? link.name : "", slugifyConfigKey(link && link.name ? link.name : "")]);
    }

    function slugifyConfigKey(value) {
        return String(value || "").trim().toLowerCase().replace(/\s+/g, "-");
    }

    function aliasesFor(scope, keys, fallbackAliases) {
        const config = launcherConfig[scope] || {
        };
        const aliasMap = config.aliases || {
        };
        const merged = normalizeAliasList(fallbackAliases || []);
        for (const key of keys) {
            const values = aliasMap[key] || [];
            for (const alias of values) {
                if (merged.indexOf(alias) === -1)
                    merged.push(alias);

            }
        }
        return merged;
    }

    function isFavorite(scope, keys) {
        const config = launcherConfig[scope] || {
        };
        const favorites = config.favorites || [];
        return keys.some((key) => {
            return favorites.indexOf(key) !== -1;
        });
    }

    function favoriteBoost(scope, keys) {
        return isFavorite(scope, keys) ? 40 : 0;
    }

    function compareByFavoriteThenTitle(a, b, scope, aKeys, bKeys, titleFn) {
        const aFav = isFavorite(scope, aKeys);
        const bFav = isFavorite(scope, bKeys);
        if (aFav !== bFav)
            return aFav ? -1 : 1;

        return titleFn(a).localeCompare(titleFn(b));
    }

    function compareAppsFirst(a, b) {
        const aIsApp = a && a.provider === "apps";
        const bIsApp = b && b.provider === "apps";
        if (aIsApp === bIsApp)
            return 0;

        return aIsApp ? -1 : 1;
    }

    function compareFilesLast(a, b) {
        const aIsFile = a && a.provider === "files";
        const bIsFile = b && b.provider === "files";
        if (aIsFile === bIsFile)
            return 0;

        return aIsFile ? 1 : -1;
    }

    function aliasScore(normalizedQuery, aliases) {
        if (!normalizedQuery)
            return 0;

        for (const alias of aliases) {
            if (normalizedQuery === alias)
                return 90;

        }
        for (const alias of aliases) {
            if (alias.startsWith(normalizedQuery))
                return 85;

        }
        for (const alias of aliases) {
            if (alias.includes(normalizedQuery))
                return 80;

        }
        return 0;
    }

    function matchAliasWithQuery(rawQuery, normalizedQuery, aliases) {
        for (const alias of aliases) {
            if (normalizedQuery === alias)
                return {
                "score": 100,
                "queryText": ""
            };

        }
        for (const alias of aliases) {
            if (normalizedQuery.startsWith(`${alias} `))
                return {
                "score": 95,
                "queryText": rawQuery.slice(alias.length).trim()
            };

        }
        return null;
    }

    function resultSubtitle(baseText, aliases) {
        if (!aliases || aliases.length === 0)
            return baseText;

        const aliasText = `alias:${aliases.join(",")}`;
        return baseText ? `${baseText}  ${aliasText}` : aliasText;
    }

    function resultAliases(result) {
        const aliases = result && result.payload ? result.payload.aliases : [];
        return Array.isArray(aliases) ? aliases : [];
    }

    function resultIsFavorite(result) {
        return !!(result && result.payload && result.payload.favorite);
    }

    function resultTypeLabel(result) {
        if (!result)
            return "";

        if (result.provider === "apps")
            return "APP";

        if (result.provider === "quicklinks")
            return "LINK";

        if (result.provider === "files")
            return "FILE";

        if (result.provider === "calculator")
            return "CALC";

        if (result.provider === "emoji")
            return "EMO";

        if (result.provider === "clipboard")
            return "CLIP";

        if (result.provider === "system")
            return "SYS";

        return String(result.type || "").toUpperCase();
    }

    function ensureFileIndex() {
        if (!root.fileIndexLoaded && !fileIndexProcess.running)
            fileIndexProcess.running = true;

    }

    function searchFiles(rawQuery, normalizedQuery) {
        const fileQuery = root.fileSearchQuery(rawQuery, normalizedQuery);
        const fileOnly = preferredProvider === "files" || normalizedQuery === fileKeyword || normalizedQuery.startsWith(`${fileKeyword} `);
        const minQueryLength = fileSearchConfig && Number.isInteger(fileSearchConfig.rootSearchMinQuery) ? fileSearchConfig.rootSearchMinQuery : 2;
        if (!fileOnly && fileQuery.length < minQueryLength)
            return [];

        ensureFileIndex();
        if (!fileIndexLoaded)
            return [];

        const scopedQuery = fileQuery.toLowerCase();
        if (!scopedQuery)
            return fileItems.slice(0, 120).map((item, index) => {
            return createFileResult(item, 14 - index * 0.001);
        });

        return fileItems.map((item) => {
            const name = String(item.name || "").toLowerCase();
            const relativePath = String(item.relativePath || "").toLowerCase();
            const displayPath = String(item.displayPath || "").toLowerCase();
            const keywords = Array.isArray(item.keywords) ? item.keywords : [];
            let score = 0;
            if (name === scopedQuery)
                score = 70;
            else if (name.startsWith(scopedQuery))
                score = 58;
            else if (name.includes(scopedQuery))
                score = 48;
            else if (relativePath.startsWith(scopedQuery))
                score = 40;
            else if (relativePath.includes(scopedQuery))
                score = 34;
            else if (displayPath.includes(scopedQuery))
                score = 28;
            else if (keywords.some((keyword) => {
                return keyword === scopedQuery;
            }))
                score = 24;
            else if (keywords.some((keyword) => {
                return keyword.startsWith(scopedQuery);
            }))
                score = 20;
            else if (keywords.some((keyword) => {
                return keyword.includes(scopedQuery);
            }))
                score = 16;
            if (score === 0)
                return null;

            return createFileResult(item, score);
        }).filter((item) => {
            return item !== null;
        }).slice(0, 140);
    }

    function createFileResult(item, score) {
        const path = String(item.path || "");
        const displayPath = String(item.displayPath || path);
        const isDirectory = !!item.isDirectory;
        return {
            "id": `file:${path}`,
            "provider": "files",
            "type": isDirectory ? "directory" : "file",
            "title": String(item.name || path),
            "subtitle": displayPath,
            "icon": isDirectory ? "folder" : "text-x-generic",
            "keywords": item.keywords || [],
            "score": score,
            "primaryAction": "open",
            "actions": [{
                "id": "open",
                "title": isDirectory ? "Open Directory" : "Open",
                "shortcut": "Enter"
            }, {
                "id": "copy-path",
                "title": "Copy Path"
            }, {
                "id": "open-parent",
                "title": "Open Parent"
            }],
            "payload": {
                "path": path,
                "parentPath": String(item.parentPath || ""),
                "isDirectory": isDirectory
            }
        };
    }

    function ensureEmojiIndex() {
        if (!root.emojiIndexLoaded && !emojiIndexProcess.running)
            emojiIndexProcess.running = true;

    }

    function searchEmoji(rawQuery, normalizedQuery) {
        const emojiQuery = root.emojiSearchQuery(rawQuery, normalizedQuery);
        const emojiOnly = preferredProvider === "emoji" || normalizedQuery === emojiKeyword || normalizedQuery.startsWith(`${emojiKeyword} `);
        if (!emojiOnly && emojiQuery.length < 2)
            return [];

        ensureEmojiIndex();
        if (!emojiIndexLoaded)
            return [];

        const scopedQuery = emojiQuery.toLowerCase();
        if (!scopedQuery)
            return emojiItems.slice(0, 80).map((item, index) => {
            return createEmojiResult(item, 16 - index * 0.001);
        });

        return emojiItems.map((item) => {
            const name = item.name.toLowerCase();
            const keywords = Array.isArray(item.keywords) ? item.keywords : [];
            let score = 0;
            if (item.emoji === scopedQuery)
                score = 120;
            else if (name === scopedQuery)
                score = 60;
            else if (name.startsWith(scopedQuery))
                score = 48;
            else if (name.includes(scopedQuery))
                score = 36;
            else if (keywords.some((keyword) => {
                return keyword === scopedQuery;
            }))
                score = 32;
            else if (keywords.some((keyword) => {
                return keyword.startsWith(scopedQuery);
            }))
                score = 28;
            else if (keywords.some((keyword) => {
                return keyword.includes(scopedQuery);
            }))
                score = 24;
            if (score === 0)
                return null;

            return createEmojiResult(item, score);
        }).filter((item) => {
            return item !== null;
        }).slice(0, 120);
    }

    function createEmojiResult(item, score) {
        return {
            "id": `emoji:${item.emoji}`,
            "provider": "emoji",
            "type": "emoji",
            "title": item.emoji,
            "subtitle": item.name,
            "icon": "",
            "keywords": item.keywords || [],
            "score": score,
            "primaryAction": "copy",
            "actions": [{
                "id": "copy",
                "title": "Copy Emoji",
                "shortcut": "Enter"
            }, {
                "id": "copy-name",
                "title": "Copy Name"
            }],
            "payload": {
                "emoji": item.emoji,
                "name": item.name
            }
        };
    }

    function systemCommands() {
        return [{
            "id": "file-search-settings",
            "title": "Settings",
            "subtitle": "Open file search settings",
            "icon": "preferences-system",
            "keywords": ["settings", "config", "preferences", "files", "launcher", "dashboard"]
        }, {
            "id": "lock",
            "title": "Lock",
            "subtitle": "hyprlock",
            "icon": "system-lock-screen",
            "keywords": ["screen", "secure", "hyprlock"]
        }, {
            "id": "suspend",
            "title": "Suspend",
            "subtitle": "systemctl suspend",
            "icon": "system-suspend",
            "keywords": ["sleep", "standby", "systemctl"]
        }, {
            "id": "logout",
            "title": "Logout",
            "subtitle": "Hyprland exit",
            "icon": "system-log-out",
            "keywords": ["sign out", "exit", "session", "hyprctl"]
        }, {
            "id": "reboot",
            "title": "Reboot",
            "subtitle": "systemctl reboot",
            "icon": "system-reboot",
            "keywords": ["restart", "systemctl"]
        }, {
            "id": "shutdown",
            "title": "Shutdown",
            "subtitle": "systemctl poweroff",
            "icon": "system-shutdown",
            "keywords": ["poweroff", "power off", "halt", "systemctl"]
        }];
    }

    function searchSystem(rawQuery, normalizedQuery) {
        const systemQuery = root.systemSearchQuery(rawQuery, normalizedQuery);
        const scopedQuery = systemQuery.toLowerCase();
        const commands = systemCommands();
        if (!scopedQuery)
            return commands.map((command, index) => {
            return createSystemResult(command, 18 - index * 0.001);
        });

        return commands.map((command) => {
            const title = command.title.toLowerCase();
            const subtitle = command.subtitle.toLowerCase();
            const keywordMatch = command.keywords.some((keyword) => {
                const candidate = String(keyword).toLowerCase();
                return candidate === scopedQuery || candidate.includes(scopedQuery);
            });
            let score = 0;
            if (title === scopedQuery)
                score = 36;
            else if (title.startsWith(scopedQuery))
                score = 34;
            else if (title.includes(scopedQuery))
                score = 30;
            else if (subtitle.includes(scopedQuery))
                score = 24;
            else if (keywordMatch)
                score = 18;
            if (score === 0)
                return null;

            return createSystemResult(command, score);
        }).filter((item) => {
            return item !== null;
        });
    }

    function createSystemResult(command, score) {
        const waitingConfirmation = systemActions.armedAction === command.id;
        return {
            "id": `system:${command.id}`,
            "provider": "system",
            "type": "system",
            "title": command.title,
            "subtitle": waitingConfirmation ? "Press Enter again to confirm" : command.subtitle,
            "icon": command.icon,
            "keywords": command.keywords,
            "score": waitingConfirmation ? 400 : score,
            "primaryAction": "run",
            "actions": [{
                "id": "run",
                "title": waitingConfirmation ? "Confirm" : "Run",
                "shortcut": "Enter"
            }],
            "payload": {
                "systemAction": command.id,
                "waitingConfirmation": waitingConfirmation
            }
        };
    }

    function searchQuicklinks(rawQuery, normalizedQuery) {
        if (!normalizedQuery)
            return quicklinks.slice().sort((a, b) => {
            return compareByFavoriteThenTitle(a, b, "quicklinks", quicklinkConfigKeys(a), quicklinkConfigKeys(b), (link) => {
                return link.name;
            });
        }).map((link, index) => {
            return createQuicklinkResult(link, 8 + favoriteBoost("quicklinks", quicklinkConfigKeys(link)) - index * 0.001, "");
        });

        return quicklinks.map((link) => {
            const match = matchQuicklink(link, rawQuery, normalizedQuery);
            if (!match)
                return null;

            return createQuicklinkResult(link, match.score + favoriteBoost("quicklinks", quicklinkConfigKeys(link)), match.queryText);
        }).filter((item) => {
            return item !== null;
        });
    }

    function matchQuicklink(link, rawQuery, normalizedQuery) {
        const aliases = aliasesFor("quicklinks", quicklinkConfigKeys(link), link.aliases || []);
        const name = link.name.toLowerCase();
        const tags = link.tags.map((tag) => {
            return tag.toLowerCase();
        });
        const aliasMatch = matchAliasWithQuery(rawQuery, normalizedQuery, aliases);
        if (aliasMatch)
            return aliasMatch;

        if (name === normalizedQuery)
            return {
            "score": 30,
            "queryText": ""
        };

        if (name.startsWith(normalizedQuery))
            return {
            "score": 20,
            "queryText": ""
        };

        if (name.includes(normalizedQuery))
            return {
            "score": 12,
            "queryText": ""
        };

        if (tags.some((tag) => {
            return tag.includes(normalizedQuery);
        }))
            return {
            "score": 8,
            "queryText": ""
        };

        return null;
    }

    function createQuicklinkResult(link, score, queryText) {
        const hasTemplate = link.url.indexOf("{query}") !== -1;
        const aliases = aliasesFor("quicklinks", quicklinkConfigKeys(link), link.aliases || []);
        const subtitleBase = resultSubtitle(link.url, aliases);
        const favorite = isFavorite("quicklinks", quicklinkConfigKeys(link));
        return {
            "id": `quicklink:${link.id}`,
            "provider": "quicklinks",
            "type": "quicklink",
            "title": link.name,
            "subtitle": hasTemplate && queryText ? `${subtitleBase}  query:${queryText}` : subtitleBase,
            "icon": link.icon,
            "keywords": link.tags,
            "score": score,
            "primaryAction": "open",
            "actions": [{
                "id": "open",
                "title": "Open",
                "shortcut": "Enter"
            }, {
                "id": "copy-url",
                "title": "Copy URL"
            }, {
                "id": "copy-name",
                "title": "Copy Name"
            }],
            "payload": {
                "quicklink": link,
                "queryText": queryText,
                "aliases": aliases,
                "favorite": favorite
            }
        };
    }

    function resolveQuicklinkUrl(link, queryText) {
        if (!link || !link.url)
            return "";

        let resolvedUrl = link.url;
        if (resolvedUrl.indexOf("{query}") !== -1)
            resolvedUrl = resolvedUrl.split("{query}").join(encodeURIComponent(queryText || ""));

        const home = Quickshell.env("HOME");
        if (resolvedUrl === "~")
            return home;
        if (resolvedUrl.indexOf("~/") === 0)
            return `${home}${resolvedUrl.slice(1)}`;

        return resolvedUrl;
    }

    function searchCalculator(rawQuery) {
        const expression = rawQuery.trim();
        if (!isCalculatorCandidate(expression))
            return [];

        const evaluation = evaluateCalculatorExpression(expression);
        if (!evaluation || !evaluation.valid)
            return [];

        return [createCalculatorResult(expression, evaluation.value)];
    }

    function isCalculatorCandidate(expression) {
        if (!expression)
            return false;

        if (!/[0-9]/.test(expression))
            return false;

        return /^[0-9+\-*/^().\s]+$/.test(expression);
    }

    function evaluateCalculatorExpression(expression) {
        const tokens = tokenizeCalculatorExpression(expression);
        if (!tokens.length)
            return {
            "valid": false
        };

        const state = {
            "tokens": tokens,
            "index": 0
        };
        const value = parseCalculatorAddSub(state);
        if (value === null || state.index !== tokens.length || !Number.isFinite(value))
            return {
            "valid": false
        };

        return {
            "valid": true,
            "value": Object.is(value, -0) ? 0 : value
        };
    }

    function tokenizeCalculatorExpression(expression) {
        const tokens = [];
        let i = 0;
        while (i < expression.length) {
            const ch = expression[i];
            if (/\s/.test(ch)) {
                i += 1;
                continue;
            }
            if (/[0-9.]/.test(ch)) {
                let j = i;
                let dots = 0;
                while (j < expression.length && /[0-9.]/.test(expression[j])) {
                    if (expression[j] === ".")
                        dots += 1;

                    j += 1;
                }
                const raw = expression.slice(i, j);
                if (dots > 1 || raw === ".")
                    return [];

                tokens.push({
                    "kind": "number",
                    "value": Number(raw)
                });
                i = j;
                continue;
            }
            if ("+-*/^()".indexOf(ch) !== -1) {
                tokens.push({
                    "kind": ch
                });
                i += 1;
                continue;
            }
            return [];
        }
        return tokens;
    }

    function parseCalculatorAddSub(state) {
        let value = parseCalculatorMulDiv(state);
        if (value === null)
            return null;

        while (state.index < state.tokens.length) {
            const token = state.tokens[state.index];
            if (token.kind !== "+" && token.kind !== "-")
                break;

            state.index += 1;
            const rhs = parseCalculatorMulDiv(state);
            if (rhs === null)
                return null;

            value = token.kind === "+" ? value + rhs : value - rhs;
        }
        return value;
    }

    function parseCalculatorMulDiv(state) {
        let value = parseCalculatorUnary(state);
        if (value === null)
            return null;

        while (state.index < state.tokens.length) {
            const token = state.tokens[state.index];
            if (token.kind !== "*" && token.kind !== "/")
                break;

            state.index += 1;
            const rhs = parseCalculatorUnary(state);
            if (rhs === null)
                return null;

            value = token.kind === "*" ? value * rhs : value / rhs;
        }
        return value;
    }

    function parseCalculatorPower(state) {
        const value = parseCalculatorPrimary(state);
        if (value === null)
            return null;

        if (state.index < state.tokens.length && state.tokens[state.index].kind === "^") {
            state.index += 1;
            const rhs = parseCalculatorUnary(state);
            if (rhs === null)
                return null;

            return Math.pow(value, rhs);
        }
        return value;
    }

    function parseCalculatorUnary(state) {
        if (state.index >= state.tokens.length)
            return null;

        const token = state.tokens[state.index];
        if (token.kind === "+") {
            state.index += 1;
            return parseCalculatorUnary(state);
        }
        if (token.kind === "-") {
            state.index += 1;
            const value = parseCalculatorUnary(state);
            return value === null ? null : -value;
        }
        return parseCalculatorPower(state);
    }

    function parseCalculatorPrimary(state) {
        if (state.index >= state.tokens.length)
            return null;

        const token = state.tokens[state.index];
        if (token.kind === "number") {
            state.index += 1;
            return token.value;
        }
        if (token.kind !== "(")
            return null;

        state.index += 1;
        const value = parseCalculatorAddSub(state);
        if (value === null || state.index >= state.tokens.length || state.tokens[state.index].kind !== ")")
            return null;

        state.index += 1;
        return value;
    }

    function formatCalculatorValue(value) {
        if (!Number.isFinite(value))
            return "";

        if (Object.is(value, -0))
            return "0";

        if (Number.isInteger(value))
            return String(value);

        return String(Number(value.toFixed(12)));
    }

    function createCalculatorResult(expression, value) {
        const formattedValue = formatCalculatorValue(value);
        if (!formattedValue)
            return null;

        return {
            "id": `calculator:${expression}`,
            "provider": "calculator",
            "type": "calculator",
            "title": formattedValue,
            "subtitle": expression,
            "icon": "",
            "keywords": [],
            "score": 150,
            "primaryAction": "copy-result",
            "actions": [{
                "id": "copy-result",
                "title": "Copy Result",
                "shortcut": "Enter"
            }, {
                "id": "copy-expression",
                "title": "Copy Expression"
            }],
            "payload": {
                "expression": expression,
                "result": formattedValue
            }
        };
    }

    function searchClipboard(queryText) {
        const items = clipboardState.items || [];
        if (queryText === null)
            return [];

        const normalizedQuery = queryText.toLowerCase();
        if (!normalizedQuery)
            return items.map((item, index) => {
            return createClipboardResult(item, 220 - index * 0.001);
        });

        return items.map((item, index) => {
            const match = matchClipboardItem(item, normalizedQuery, index);
            if (!match)
                return null;

            return createClipboardResult(item, match.score);
        }).filter((item) => {
            return item !== null;
        });
    }

    function matchClipboardItem(item, normalizedQuery, index) {
        const title = String(item.title || "").toLowerCase();
        const subtitle = String(item.subtitle || "").toLowerCase();
        const preview = String(item.preview || "").toLowerCase();
        if (title.startsWith(normalizedQuery))
            return {
            "score": 220 - index * 0.001
        };

        if (title.includes(normalizedQuery))
            return {
            "score": 210 - index * 0.001
        };

        if (subtitle.includes(normalizedQuery))
            return {
            "score": 200 - index * 0.001
        };

        if (preview.includes(normalizedQuery))
            return {
            "score": 190 - index * 0.001
        };

        return null;
    }

    function createClipboardResult(item, score) {
        const title = String(item.title || item.preview || `Clipboard #${item.id}`);
        const preview = String(item.preview || "");
        const subtitle = String(item.subtitle || "").trim();
        return {
            "id": `clipboard:${item.id}`,
            "provider": "clipboard",
            "type": "clipboard",
            "title": title,
            "subtitle": subtitle || preview || `#${item.id}`,
            "icon": "",
            "keywords": [],
            "score": score,
            "primaryAction": "copy",
            "actions": [{
                "id": "copy",
                "title": "Copy",
                "shortcut": "Enter"
            }, {
                "id": "delete",
                "title": "Delete"
            }],
            "payload": {
                "clipboardItem": item
            }
        };
    }

    function appTitle(app) {
        return app && app.name ? app.name : "";
    }

    function shellEscape(value) {
        return `'${String(value).replace(/'/g, `'\"'\"'`)}'`;
    }

    function toggle() {
        if (root.open)
            close();
        else
            show();
    }

    function close() {
        root.open = false;
        root.query = "";
        root.preferredProvider = "";
        root.selectedIndex = 0;
        clearPendingConfirmation();
        closeActionPanel();
    }

    function show() {
        openLauncher("");
    }

    function openLauncher(providerId) {
        prepare(providerId || "");
        root.open = true;
    }

    function prepare(providerId) {
        root.query = "";
        root.preferredProvider = providerId || "";
        root.selectedIndex = 0;
        clearPendingConfirmation();
        closeActionPanel();
        clipboardState.refresh();
        if (preferredProvider === "files")
            ensureFileIndex();

        if (preferredProvider === "emoji")
            ensureEmojiIndex();

        if (!root.availableIcons && !iconScanProcess.running)
            iconScanProcess.running = true;

    }

    function moveSelection(delta) {
        if (root.resultCount === 0)
            return ;

        root.selectedIndex = Math.max(0, Math.min(root.resultCount - 1, root.selectedIndex + delta));
    }

    function moveActionSelection(delta) {
        if (!root.selectedActions.length)
            return ;

        root.selectedActionIndex = Math.max(0, Math.min(root.selectedActions.length - 1, root.selectedActionIndex + delta));
    }

    function clearQuery() {
        root.query = "";
    }

    function clearPendingConfirmation() {
        systemActions.clearArmedAction();
    }

    function openActionPanel() {
        if (!root.selectedActions.length)
            return ;

        root.actionPanelOpen = true;
        root.selectedActionIndex = 0;
    }

    function closeActionPanel() {
        root.actionPanelOpen = false;
        root.selectedActionIndex = 0;
    }

    function toggleActionPanel() {
        if (root.actionPanelOpen)
            closeActionPanel();
        else
            openActionPanel();
    }

    function runResult(result, actionId) {
        if (!result)
            return ;

        const action = actionId || result.primaryAction || "launch";
        if (result.provider === "apps")
            runAppResult(result, action);
        else if (result.provider === "quicklinks")
            runQuicklinkResult(result, action);
        else if (result.provider === "files")
            runFileResult(result, action);
        else if (result.provider === "calculator")
            runCalculatorResult(result, action);
        else if (result.provider === "emoji")
            runEmojiResult(result, action);
        else if (result.provider === "clipboard")
            runClipboardResult(result, action);
        else if (result.provider === "system")
            runSystemResult(result, action);
    }

    function runAppResult(result, actionId) {
        const entry = result.payload ? result.payload.desktopEntry : null;
        if (!entry)
            return ;

        if (actionId === "copy-name") {
            copyText(result.title);
            return ;
        }
        if (actionId === "copy-id") {
            if (entry.id)
                copyText(entry.id);

            return ;
        }
        if (actionId !== "launch" || !entry.id)
            return ;

        close();
        if (entry.runInTerminal && entry.command && entry.command.length > 0) {
            const command = ["kitty"];
            if (entry.workingDirectory)
                command.push("--working-directory", entry.workingDirectory);

            Quickshell.execDetached(command.concat(["--"]).concat(entry.command));
            return ;
        }
        Quickshell.execDetached(["gtk-launch", entry.id]);
    }

    function runQuicklinkResult(result, actionId) {
        const quicklink = result.payload ? result.payload.quicklink : null;
        if (!quicklink)
            return ;

        if (actionId === "copy-url") {
            copyText(resolveQuicklinkUrl(quicklink, result.payload.queryText || ""));
            return ;
        }
        if (actionId === "copy-name") {
            copyText(result.title);
            return ;
        }
        if (actionId !== "open")
            return ;

        const target = resolveQuicklinkUrl(quicklink, result.payload.queryText || "");
        if (!target)
            return ;

        close();
        if (quicklink.openWith === "terminal") {
            Quickshell.execDetached(["kitty", "--working-directory", target]);
            return ;
        }
        Quickshell.execDetached(["xdg-open", target]);
    }

    function runFileResult(result, actionId) {
        const path = result.payload ? result.payload.path : "";
        const parentPath = result.payload ? result.payload.parentPath : "";
        if (!path)
            return ;

        if (actionId === "copy-path") {
            copyText(path);
            return ;
        }
        if (actionId === "open-parent") {
            if (!parentPath)
                return ;

            Quickshell.execDetached(["xdg-open", parentPath]);
            return ;
        }
        if (actionId !== "open")
            return ;

        close();
        Quickshell.execDetached(["xdg-open", path]);
    }

    function runCalculatorResult(result, actionId) {
        const expression = result.payload ? result.payload.expression : "";
        const value = result.payload ? result.payload.result : "";
        if (actionId === "copy-expression") {
            copyText(expression);
            return ;
        }
        if (actionId !== "copy-result")
            return ;

        copyText(value);
    }

    function runEmojiResult(result, actionId) {
        const emoji = result.payload ? result.payload.emoji : "";
        const name = result.payload ? result.payload.name : "";
        if (actionId === "copy-name") {
            copyText(name);
            return ;
        }
        if (actionId !== "copy")
            return ;

        copyText(emoji);
    }

    function runClipboardResult(result, actionId) {
        const item = result.payload ? result.payload.clipboardItem : null;
        if (!item || item.id === undefined)
            return ;

        if (actionId === "delete") {
            clipboardState.deleteEntry(item.id);
            closeActionPanel();
            return ;
        }
        if (actionId !== "copy")
            return ;

        close();
        clipboardState.copy(item.id);
    }

    function runSystemResult(result, actionId) {
        const systemAction = result.payload ? result.payload.systemAction : "";
        if (actionId !== "run" || !systemAction)
            return ;

        if (systemAction === "file-search-settings") {
            close();
            Quickshell.execDetached(["qs", "-c", "zetshell", "ipc", "call", "dashboard", "open", "settings"]);
            return ;
        }
        systemActions.invoke(systemAction);
        closeActionPanel();
        if (!systemActions.armedAction)
            close();

    }

    function runSelected() {
        if (root.selectedIndex >= 0 && root.selectedIndex < root.results.length)
            runResult(root.results[root.selectedIndex], root.results[root.selectedIndex].primaryAction);

    }

    function runSelectedAction() {
        if (!root.selectedResult || !root.selectedActions.length)
            return ;

        const action = root.selectedActions[root.selectedActionIndex];
        if (!action || !action.id)
            return ;

        runResult(root.selectedResult, action.id);
    }

    function initials(name) {
        if (!name)
            return "?";

        const words = name.trim().split(/\s+/);
        if (words.length >= 2)
            return (words[0][0] + words[1][0]).toUpperCase();

        return name.substring(0, 2).toUpperCase();
    }

    function copyText(value) {
        if (value === undefined || value === null)
            return ;

        clipboardCopyProcess.command = ["bash", "-lc", `printf '%s' ${shellEscape(String(value))} | wl-copy`];
        clipboardCopyProcess.running = true;
        closeActionPanel();
    }

    onQueryChanged: {
        selectedIndex = 0;
        closeActionPanel();
    }
    onResultCountChanged: {
        if (resultCount === 0) {
            selectedIndex = 0;
            closeActionPanel();
            return ;
        }
        selectedIndex = Math.max(0, Math.min(resultCount - 1, selectedIndex));
        const actions = selectedActions || [];
        if (selectedActionIndex >= actions.length)
            selectedActionIndex = Math.max(0, actions.length - 1);

    }
    onSelectedIndexChanged: {
        if (actionPanelOpen)
            selectedActionIndex = 0;

    }

    Process {
        id: iconScanProcess

        command: ["bash", "-c", "find /usr/share/icons /usr/share/pixmaps -type f \\( -name '*.png' -o -name '*.svg' -o -name '*.xpm' \\) | sed 's|.*/||' | sed 's|\\.[^.]*$||' | sort -u"]

        stdout: StdioCollector {
            onStreamFinished: {
                const names = this.text.trim().split("\n").filter((n) => {
                    return n.length > 0;
                });
                root.availableIcons = new Set(names);
            }
        }

    }

    Process {
        id: emojiIndexProcess

        command: ["python", `${Quickshell.env("HOME")}/.config/quickshell/zetshell/scripts/build_emoji_index.py`]
        onExited: {
            if (exitCode !== 0)
                root.emojiItems = [];

        }

        stdout: StdioCollector {
            onStreamFinished: {
                const raw = this.text.trim();
                if (!raw)
                    return ;

                try {
                    const parsed = JSON.parse(raw);
                    root.emojiItems = Array.isArray(parsed) ? parsed : [];
                    root.emojiIndexLoaded = true;
                } catch (error) {
                    console.warn("Failed to parse emoji index:", error);
                }
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                const raw = this.text.trim();
                if (raw.length > 0)
                    console.warn("Emoji index generation failed:", raw);

            }
        }

    }

    Process {
        id: fileIndexProcess

        command: ["python", `${Quickshell.env("HOME")}/.config/quickshell/zetshell/scripts/build_file_index.py`]
        onExited: {
            if (exitCode !== 0)
                root.fileItems = [];

        }

        stdout: StdioCollector {
            onStreamFinished: {
                const raw = this.text.trim();
                if (!raw)
                    return ;

                try {
                    const parsed = JSON.parse(raw);
                    root.fileItems = Array.isArray(parsed) ? parsed : [];
                    root.fileIndexLoaded = true;
                } catch (error) {
                    console.warn("Failed to parse file index:", error);
                }
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                const raw = this.text.trim();
                if (raw.length > 0)
                    console.warn("File index generation failed:", raw);

            }
        }

    }

    Process {
        id: clipboardCopyProcess

        command: ["bash", "-lc", "true"]

        stdout: StdioCollector {
        }

        stderr: StdioCollector {
        }

    }

    ClipboardService {
        id: clipboardState
    }

    SystemService {
        id: systemActions
    }

    Timer {
        interval: 2500
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: {
            quicklinksFile.reload();
            fileSearchConfigFile.reload();
            launcherConfigFile.reload();
        }
    }

    FileView {
        id: quicklinksFile

        path: `${Quickshell.env("HOME")}/.config/zetshell/quicklinks.json`
        onLoaded: {
            const raw = text().trim();
            if (raw === root.quicklinksConfigText)
                return ;

            root.quicklinksConfigText = raw;
            if (!raw) {
                root.quicklinks = [];
                root.fileItems = [];
                root.fileIndexLoaded = false;
                return ;
            }
            try {
                root.applyQuicklinksConfig(JSON.parse(raw));
            } catch (error) {
                console.warn("Failed to parse quicklinks config:", error);
            }
        }
    }

    FileView {
        id: fileSearchConfigFile

        path: `${Quickshell.env("HOME")}/.config/zetshell/file_search.json`
        onLoaded: {
            const raw = text().trim();
            if (raw === root.fileSearchConfigText)
                return ;

            root.fileSearchConfigText = raw;
            if (!raw) {
                root.applyFileSearchConfig({
                });
                root.fileItems = [];
                root.fileIndexLoaded = false;
                return ;
            }
            try {
                root.applyFileSearchConfig(JSON.parse(raw));
                root.fileItems = [];
                root.fileIndexLoaded = false;
            } catch (error) {
                console.warn("Failed to parse file search config:", error);
            }
        }
    }

    FileView {
        id: launcherConfigFile

        path: `${Quickshell.env("HOME")}/.config/zetshell/launcher.json`
        onLoaded: {
            const raw = text().trim();
            if (!raw) {
                root.applyLauncherConfig({
                });
                return ;
            }
            try {
                root.applyLauncherConfig(JSON.parse(raw));
            } catch (error) {
                console.warn("Failed to parse launcher config:", error);
            }
        }
    }

}
