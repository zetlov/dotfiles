import "../.." as Shell
import "../../services" as Services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "components" as DashboardComponents

PanelWindow {
    id: root

    property string targetMonitor: ""
    property string screenNameHint: ""
    property QtObject dashboardService: null
    property QtObject configService: null
    property QtObject fileSearchConfigService: null
    readonly property QtObject dashboardTheme: theme
    readonly property QtObject musicService: music
    readonly property QtObject lyricsService: lyrics
    readonly property QtObject statsService: stats
    readonly property QtObject brightnessService: brightness
    readonly property QtObject volumeService: volume
    property QtObject networkService: null
    readonly property QtObject network: networkService
    readonly property string screenName: screenNameHint
    readonly property bool isTargetMonitor: {
        if (!targetMonitor)
            return true;

        if (!screenName)
            return false;

        return screenName === targetMonitor;
    }
    readonly property int panelWidth: {
        const width = screen ? screen.width : 1920;
        return Math.max(980, Math.min(1480, Math.round(width * 0.68)));
    }
    readonly property int panelHeight: {
        const height = screen ? screen.height : 1080;
        return Math.max(640, Math.min(1060, Math.round(height * 0.76)));
    }
    property date calendarDate: new Date()
    property string pendingCommand: ""
    property int selectedIndex: 0
    property bool lyricsVisible: configService ? configService.showLyrics : true
    property bool networkPasswordPromptOpen: false
    property string networkPasswordTargetSsid: ""
    property string networkPasswordValue: ""
    readonly property var tabModel: {
        const items = [{
            "id": "home",
            "label": "Home"
        }];
        if (!configService || configService.showMedia)
            items.push({
            "id": "media",
            "label": "Media"
        });

        if (!configService || configService.showPerformance)
            items.push({
            "id": "performance",
            "label": "Performance"
        });

        if (!configService || configService.showWeather)
            items.push({
            "id": "weather",
            "label": "Weather"
        });

        if (!configService || configService.showActions)
            items.push({
            "id": "actions",
            "label": "Actions"
        });

        items.push({
            "id": "audio",
            "label": "Audio"
        });
        items.push({
            "id": "network",
            "label": "Network"
        });
        items.push({
            "id": "display",
            "label": "Display"
        });
        items.push({
            "id": "wallpaper",
            "label": "Wallpaper"
        });
        items.push({
            "id": "system",
            "label": "System"
        });
        items.push({
            "id": "settings",
            "label": "Settings"
        });
        return items;
    }
    readonly property var quickActions: [{
        "id": "audio",
        "title": "Audio",
        "detail": "Open volume and media controls",
        "command": "qs -c zetshell ipc call controlCenter open audio"
    }, {
        "id": "network",
        "title": "Network",
        "detail": "Open Wi-Fi and connection controls",
        "command": "qs -c zetshell ipc call controlCenter open network"
    }, {
        "id": "wallpaper",
        "title": "Wallpaper",
        "detail": "Open wallpaper launcher",
        "command": "qs -c zetshell ipc call wallpaperLauncher toggle"
    }, {
        "id": "capture",
        "title": "Capture",
        "detail": "Open capture tools",
        "command": "qs -c zetshell ipc call captureLauncher toggle"
    }, {
        "id": "notifications",
        "title": "Notifications",
        "detail": "Open notification center",
        "command": "qs -c zetshell ipc call notifications toggleCenter"
    }, {
        "id": "apps",
        "title": "Apps",
        "detail": "Open app launcher",
        "command": "qs -c zetshell ipc call appLauncher toggle"
    }, {
        "id": "settings",
        "title": "Settings",
        "detail": "Open file search settings",
        "command": "qs -c zetshell ipc call dashboard open settings"
    }]

    function activeTab() {
        return dashboardService ? dashboardService.activeTab : "home";
    }

    function setTab(tab) {
        if (dashboardService) {
            dashboardService.openTab(tab);
            selectedIndex = 0;
        }
    }

    function selectedItems() {
        if (activeTab() === "home")
            return homeSelectableItems();

        if (activeTab() === "performance") {
            const items = ["cpu", "memory", "storage", "network"];
            if (stats.hasGpu)
                items.push("gpu");

            if (stats.hasBattery)
                items.push("battery");

            return items;
        }
        if (activeTab() === "actions")
            return quickActions.map((action) => {
            return action.id;
        });

        if (activeTab() === "audio")
            return audioSelectableItems();

        if (activeTab() === "network")
            return networkSelectableItems();

        if (activeTab() === "display")
            return displaySelectableItems();

        if (activeTab() === "wallpaper")
            return wallpaperSelectableItems();

        if (activeTab() === "system")
            return systemActionItems().map((action) => {
            return action.id;
        });

        if (activeTab() === "settings")
            return [];

        if (isControlTab(activeTab()))
            return controlActions(activeTab()).map((action) => {
            return action.id;
        });

        if (activeTab() === "weather")
            return ["weather"];

        return ["media-prev", "media-play", "media-next", "media-lyrics"];
    }

    function isControlTab(tab) {
        return tab === "audio" || tab === "network" || tab === "display" || tab === "wallpaper" || tab === "system";
    }

    function networkSelectableItems() {
        const items = ["network-toggle", "network-refresh", "network-open"];
        if (network.connected)
            items.push("network-disconnect");

        for (let i = 0; i < network.networks.length; i++) items.push(`network-wifi-${i}`)
        return items;
    }

    function audioSelectableItems() {
        const items = ["audio-volume", "audio-mute", "audio-media"];
        for (let i = 0; i < volume.sinks.length; i++) items.push(`audio-sink-${i}`)
        items.push("audio-open");
        return items;
    }

    function displaySelectableItems() {
        return ["display-brightness", "display-down", "display-up", "display-refresh"];
    }

    function wallpaperSelectableItems() {
        const items = ["wallpaper-random", "wallpaper-favorite", "wallpaper-refresh", "wallpaper-dark", "wallpaper-light"];
        for (let i = 0; i < wallpapers.wallpapers.length; i++) items.push(`wallpaper-item-${i}`)
        return items;
    }

    function systemActionItems() {
        return [{
            "id": "system-refresh",
            "title": "Refresh Updates",
            "detail": updates.summary,
            "tone": updates.hasUpdates ? theme.accentWarm : theme.accent,
            "dangerous": false
        }, {
            "id": "system-lock",
            "title": "Lock",
            "detail": "hyprlock",
            "tone": theme.accent,
            "dangerous": false
        }, {
            "id": "system-suspend",
            "title": "Suspend",
            "detail": "systemctl suspend",
            "tone": theme.accentWarm,
            "dangerous": false
        }, {
            "id": "system-logout",
            "title": "Logout",
            "detail": "Hyprland exit",
            "tone": theme.accentWarm,
            "dangerous": true
        }, {
            "id": "system-reboot",
            "title": "Reboot",
            "detail": "systemctl reboot",
            "tone": theme.dangerText,
            "dangerous": true
        }, {
            "id": "system-shutdown",
            "title": "Shutdown",
            "detail": "systemctl poweroff",
            "tone": theme.dangerText,
            "dangerous": true
        }];
    }

    function controlActions(tab) {
        if (tab === "audio")
            return [{
            "id": "audio-volume",
            "title": volume.muted ? "Muted" : "Volume",
            "detail": volume.ready ? `${volume.level}%  ${volume.deviceName || "Default sink"}` : "Audio unavailable",
            "accent": volume.muted ? theme.dangerText : volume.tone
        }, {
            "id": "audio-mute",
            "title": "Mute",
            "detail": volume.muted ? "Unmute default sink" : "Mute default sink",
            "accent": volume.muted ? theme.dangerText : theme.faintBorder
        }, {
            "id": "audio-media",
            "title": music.hasPlayer ? (music.isPlaying ? "Pause Media" : "Play Media") : "Media",
            "detail": music.hasPlayer ? `${music.title}  ${music.artist}` : "No active player",
            "accent": music.hasPlayer ? theme.accent : theme.faintBorder
        }, {
            "id": "audio-open",
            "title": "Audio Settings",
            "detail": "Open pavucontrol",
            "accent": theme.faintBorder
        }];

        if (tab === "network")
            return [{
            "id": "network-toggle",
            "title": network.wifiEnabled ? "Disable Wi-Fi" : "Enable Wi-Fi",
            "detail": network.text,
            "accent": network.tone
        }, {
            "id": "network-refresh",
            "title": "Refresh",
            "detail": network.statusText,
            "accent": theme.faintBorder
        }, {
            "id": "network-disconnect",
            "title": "Disconnect",
            "detail": network.connected ? network.connectionName || network.label : "No active connection",
            "accent": network.connected ? theme.attentionBorder : theme.faintBorder
        }, {
            "id": "network-open",
            "title": "Network Settings",
            "detail": "Open nm-connection-editor",
            "accent": theme.faintBorder
        }];

        if (tab === "display")
            return [{
            "id": "display-brightness",
            "title": "Brightness",
            "detail": brightness.available ? brightness.text : "Backlight unavailable",
            "accent": brightness.available ? theme.accentWarm : theme.faintBorder
        }, {
            "id": "display-up",
            "title": "Brighter",
            "detail": "Increase by 5%",
            "accent": theme.accentWarm
        }, {
            "id": "display-down",
            "title": "Dimmer",
            "detail": "Decrease by 5%",
            "accent": theme.faintBorder
        }, {
            "id": "display-refresh",
            "title": "Refresh",
            "detail": brightness.deviceName || "brightnessctl",
            "accent": theme.faintBorder
        }];

        if (tab === "wallpaper")
            return [{
            "id": "wallpaper-launcher",
            "title": "Wallpaper Launcher",
            "detail": wallpapers.statusText,
            "accent": theme.accent
        }, {
            "id": "wallpaper-random",
            "title": "Random",
            "detail": wallpapers.currentName || "Pick another wallpaper",
            "accent": theme.accentWarm
        }, {
            "id": "wallpaper-dark",
            "title": "Dark Mode",
            "detail": wallpapers.mode === "dark" ? "Current mode" : "Switch theme mode",
            "accent": wallpapers.mode === "dark" ? theme.accent : theme.faintBorder
        }, {
            "id": "wallpaper-light",
            "title": "Light Mode",
            "detail": wallpapers.mode === "light" ? "Current mode" : "Switch theme mode",
            "accent": wallpapers.mode === "light" ? theme.accentWarm : theme.faintBorder
        }];

        return [{
            "id": "system-refresh",
            "title": "Refresh Updates",
            "detail": updates.summary,
            "accent": updates.hasUpdates ? theme.accentWarm : theme.faintBorder
        }, {
            "id": "system-lock",
            "title": "Lock",
            "detail": "hyprlock",
            "accent": theme.faintBorder
        }, {
            "id": "system-suspend",
            "title": "Suspend",
            "detail": "systemctl suspend",
            "accent": theme.faintBorder
        }, {
            "id": "system-logout",
            "title": "Logout",
            "detail": systemActions.armedAction === "logout" ? "Press again to confirm" : "Hyprland exit",
            "accent": systemActions.armedAction === "logout" ? theme.attentionBorder : theme.faintBorder
        }, {
            "id": "system-reboot",
            "title": "Reboot",
            "detail": systemActions.armedAction === "reboot" ? "Press again to confirm" : "systemctl reboot",
            "accent": systemActions.armedAction === "reboot" ? theme.attentionBorder : theme.faintBorder
        }, {
            "id": "system-shutdown",
            "title": "Shutdown",
            "detail": systemActions.armedAction === "shutdown" ? "Press again to confirm" : "systemctl poweroff",
            "accent": systemActions.armedAction === "shutdown" ? theme.attentionBorder : theme.faintBorder
        }];
    }

    function homeSelectableItems() {
        const items = ["user", "time", "calendar", "resources"];
        if (!configService || configService.showWeather)
            items.push("weather");

        if (!configService || configService.showMedia)
            items.push("media");

        return items;
    }

    function selectedId() {
        const items = selectedItems();
        if (items.length === 0)
            return "";

        return items[Math.max(0, Math.min(selectedIndex, items.length - 1))];
    }

    function moveSelection(delta) {
        const items = selectedItems();
        if (items.length === 0)
            return ;

        selectedIndex = (selectedIndex + delta + items.length) % items.length;
    }

    function moveSelectionGrid(dx, dy, columns) {
        const items = selectedItems();
        if (items.length === 0)
            return ;

        const currentRow = Math.floor(selectedIndex / columns);
        const currentCol = selectedIndex % columns;
        let nextIndex = (currentRow + dy) * columns + currentCol + dx;
        if (nextIndex < 0)
            nextIndex = items.length - 1;

        if (nextIndex >= items.length)
            nextIndex = 0;

        selectedIndex = nextIndex;
    }

    function activateSelected() {
        const id = selectedId();
        if (activeTab() === "actions") {
            const action = quickActions.find((item) => {
                return item.id === id;
            });
            if (action)
                runCommand(action.command);

            return ;
        }
        if (isControlTab(activeTab())) {
            activateControlAction(id);
            return ;
        }
        if (id === "media" || id === "media-play") {
            music.toggle();
            return ;
        }
        if (id === "media-prev") {
            music.previous();
            return ;
        }
        if (id === "media-next") {
            music.next();
            return ;
        }
        if (id === "media-lyrics") {
            lyricsVisible = !lyricsVisible;
            return ;
        }
        if (id === "weather") {
            weather.refresh();
            return ;
        }
        if (id === "calendar")
            calendarDate = new Date();

    }

    function activateControlAction(id) {
        if (id === "audio-volume") {
            volume.stepLevel(5);
            return ;
        }
        if (id === "audio-mute") {
            volume.toggleMute();
            return ;
        }
        if (id === "audio-media") {
            music.toggle();
            return ;
        }
        if (id === "audio-open") {
            runCommand("pavucontrol");
            return ;
        }
        if (id.indexOf("audio-sink-") === 0) {
            const sinkIndex = parseInt(id.substring("audio-sink-".length), 10);
            const sink = volume.sinks[sinkIndex];
            if (sink)
                volume.setDefaultSink(sink);

            return ;
        }
        if (id === "network-toggle") {
            network.toggleWifi();
            return ;
        }
        if (id === "network-refresh") {
            network.refresh();
            return ;
        }
        if (id === "network-open") {
            runCommand("nm-connection-editor");
            return ;
        }
        if (id === "network-disconnect") {
            network.disconnectCurrent();
            return ;
        }
        if (id.indexOf("network-wifi-") === 0) {
            const networkIndex = parseInt(id.substring("network-wifi-".length), 10);
            const entry = network.networks[networkIndex];
            if (!entry)
                return ;

            if (entry.connectable || entry.active || entry.known)
                network.activateNetwork(entry);
            else
                openNetworkPasswordPrompt(entry.ssid);
            return ;
        }
        if (id === "display-brightness" || id === "display-up") {
            brightness.stepLevel(5);
            return ;
        }
        if (id === "display-down") {
            brightness.stepLevel(-5);
            return ;
        }
        if (id === "display-refresh") {
            brightness.refresh();
            return ;
        }
        if (id === "wallpaper-launcher") {
            runCommand("qs -c zetshell ipc call wallpaperLauncher toggle");
            return ;
        }
        if (id === "wallpaper-random") {
            wallpapers.applyRandom();
            return ;
        }
        if (id === "wallpaper-favorite") {
            wallpapers.toggleFavoriteCurrent();
            return ;
        }
        if (id === "wallpaper-refresh") {
            wallpapers.refresh();
            return ;
        }
        if (id === "wallpaper-dark") {
            wallpapers.setMode("dark");
            return ;
        }
        if (id === "wallpaper-light") {
            wallpapers.setMode("light");
            return ;
        }
        if (id.indexOf("wallpaper-item-") === 0) {
            const wallpaperIndex = parseInt(id.substring("wallpaper-item-".length), 10);
            const entry = wallpapers.wallpapers[wallpaperIndex];
            if (entry)
                wallpapers.apply(entry.path);

            return ;
        }
        if (id === "system-refresh") {
            updates.refresh();
            return ;
        }
        if (id.indexOf("system-") === 0)
            systemActions.invoke(id.substring("system-".length));

    }

    function openNetworkPasswordPrompt(ssid) {
        networkPasswordTargetSsid = ssid || "";
        networkPasswordValue = "";
        networkPasswordPromptOpen = true;
        Qt.callLater(() => {
            return networkPasswordInput.forceActiveFocus();
        });
    }

    function closeNetworkPasswordPrompt(restoreFocus) {
        networkPasswordPromptOpen = false;
        networkPasswordTargetSsid = "";
        networkPasswordValue = "";
        if (restoreFocus !== false)
            Qt.callLater(() => {
            return focusRoot.forceActiveFocus();
        });

    }

    function submitNetworkPassword() {
        if (!networkPasswordTargetSsid || networkPasswordValue.trim() === "")
            return ;

        network.connectWithPassword(networkPasswordTargetSsid, networkPasswordValue);
        closeNetworkPasswordPrompt();
    }

    function runCommand(command) {
        if (!command || actionProcess.running)
            return ;

        pendingCommand = command;
        actionProcess.running = true;
    }

    color: "transparent"
    exclusiveZone: 0
    implicitWidth: panelWidth
    implicitHeight: panelHeight
    WlrLayershell.namespace: "zetshell-dashboard"
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    visible: isTargetMonitor && dashboardService && dashboardService.open && (!configService || configService.dashboardEnabled)
    onVisibleChanged: {
        if (visible) {
            selectedIndex = 0;
            Qt.callLater(() => {
                return focusRoot.forceActiveFocus();
            });
        } else {
            closeNetworkPasswordPrompt(false);
        }
    }

    Shell.Theme {
        id: theme
    }

    Services.ClockService {
        id: clock
    }

    Services.MusicService {
        id: music
    }

    Services.LyricsService {
        id: lyrics

        title: music.title
        artist: music.artist
        album: music.album
        duration: Math.round(music.length)
        position: music.position
    }

    Services.SystemStatsService {
        id: stats

        config: root.configService
    }

    Services.WeatherService {
        id: weather

        config: root.configService
    }

    Services.DashboardInfoService {
        id: info
    }

    Services.VolumeService {
        id: volume
    }

    Services.BrightnessService {
        id: brightness
    }

    Services.WallpaperService {
        id: wallpapers
    }

    Services.UpdateService {
        id: updates
    }

    Services.SystemService {
        id: systemActions
    }

    anchors {
        top: true
        left: true
    }

    margins {
        top: Math.max(24, Math.round(((screen ? screen.height : panelHeight) - panelHeight) / 2))
        left: Math.max(24, Math.round(((screen ? screen.width : panelWidth) - panelWidth) / 2))
    }

    Process {
        id: actionProcess

        command: ["bash", "-lc", root.pendingCommand]
        onExited: root.pendingCommand = ""
    }

    Rectangle {
        anchors.fill: parent
        radius: 32
        color: theme.railBottom
        border.width: 1
        border.color: theme.softBorder

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: 31
            color: theme.cardColor
        }

        ColumnLayout {
            id: focusRoot

            anchors.fill: parent
            anchors.margins: 22
            spacing: 16
            focus: true
            Keys.onEscapePressed: {
                if (root.networkPasswordPromptOpen) {
                    root.closeNetworkPasswordPrompt();
                    return ;
                }
                if (dashboardService)
                    dashboardService.close();

            }
            Keys.onPressed: (event) => {
                if (root.networkPasswordPromptOpen)
                    return ;

                if (event.key === Qt.Key_Tab) {
                    if (dashboardService)
                        dashboardService.cycleTab((event.modifiers & Qt.ShiftModifier) !== 0 ? -1 : 1);

                    selectedIndex = 0;
                    event.accepted = true;
                } else if (event.key === Qt.Key_F && activeTab() === "wallpaper") {
                    const id = selectedId();
                    if (id.indexOf("wallpaper-item-") === 0) {
                        const wallpaperIndex = parseInt(id.substring("wallpaper-item-".length), 10);
                        const entry = wallpapers.wallpapers[wallpaperIndex];
                        if (entry)
                            wallpapers.toggleFavorite(entry.path);

                    } else {
                        wallpapers.toggleFavoriteCurrent();
                    }
                    event.accepted = true;
                } else if (event.key === Qt.Key_R && activeTab() === "wallpaper") {
                    wallpapers.applyRandom();
                    event.accepted = true;
                } else if (event.key === Qt.Key_D && activeTab() === "wallpaper") {
                    wallpapers.setMode("dark");
                    event.accepted = true;
                } else if (event.key === Qt.Key_L && (event.modifiers & Qt.ControlModifier) && activeTab() === "wallpaper") {
                    wallpapers.setMode("light");
                    event.accepted = true;
                } else if (event.key === Qt.Key_Left || event.key === Qt.Key_H) {
                    if (selectedId() === "calendar")
                        root.calendarDate = new Date(root.calendarDate.getFullYear(), root.calendarDate.getMonth() - 1, 1);
                    else if (selectedId() === "audio-volume")
                        volume.stepLevel(-5);
                    else if (selectedId() === "display-brightness")
                        brightness.stepLevel(-5);
                    else if (activeTab() === "wallpaper")
                        moveSelection(-1);
                    else if (activeTab() === "media")
                        moveSelection(-1);
                    else if (selectedId() === "media" && music.canGoPrevious)
                        music.previous();
                    else
                        moveSelectionGrid(-1, 0, activeTab() === "actions" || isControlTab(activeTab()) ? 2 : activeTab() === "performance" ? 2 : 3);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Right || event.key === Qt.Key_L) {
                    if (selectedId() === "calendar")
                        root.calendarDate = new Date(root.calendarDate.getFullYear(), root.calendarDate.getMonth() + 1, 1);
                    else if (selectedId() === "audio-volume")
                        volume.stepLevel(5);
                    else if (selectedId() === "display-brightness")
                        brightness.stepLevel(5);
                    else if (activeTab() === "wallpaper")
                        moveSelection(1);
                    else if (activeTab() === "media")
                        moveSelection(1);
                    else if (selectedId() === "media" && music.canGoNext)
                        music.next();
                    else
                        moveSelectionGrid(1, 0, activeTab() === "actions" || isControlTab(activeTab()) ? 2 : activeTab() === "performance" ? 2 : 3);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Up || event.key === Qt.Key_K) {
                    if (activeTab() === "wallpaper")
                        moveSelection(-1);
                    else
                        moveSelectionGrid(0, -1, activeTab() === "actions" || isControlTab(activeTab()) ? 2 : activeTab() === "performance" ? 2 : 3);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Down || event.key === Qt.Key_J) {
                    if (activeTab() === "wallpaper")
                        moveSelection(1);
                    else
                        moveSelectionGrid(0, 1, activeTab() === "actions" || isControlTab(activeTab()) ? 2 : activeTab() === "performance" ? 2 : 3);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                    activateSelected();
                    event.accepted = true;
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 14

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        text: "Dashboard"
                        color: theme.primaryText
                        font.pixelSize: 24
                        font.bold: true
                        font.family: theme.fontFamilyMono
                    }

                    Text {
                        text: `${clock.dateText}  ${clock.timeText}`
                        color: theme.mutedText
                        font.pixelSize: theme.fontMd
                        font.family: theme.fontFamilyMono
                    }

                }

                Row {
                    spacing: 8

                    Repeater {
                        model: root.tabModel

                        delegate: Rectangle {
                            required property var modelData

                            implicitWidth: tabText.implicitWidth + 24
                            implicitHeight: 34
                            radius: 17
                            color: root.activeTab() === modelData.id ? theme.accent : theme.cardColor
                            border.width: 1
                            border.color: root.activeTab() === modelData.id ? theme.accent : theme.faintBorder

                            Text {
                                id: tabText

                                anchors.centerIn: parent
                                text: modelData.label
                                color: root.activeTab() === modelData.id ? theme.workspaceActiveText : theme.bodyText
                                font.pixelSize: theme.fontSm
                                font.bold: true
                                font.family: theme.fontFamilyMono
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.setTab(modelData.id)
                            }

                        }

                    }

                }

            }

            Loader {
                Layout.fillWidth: true
                Layout.fillHeight: true
                sourceComponent: {
                    if (root.activeTab() === "media")
                        return mediaPane;

                    if (root.activeTab() === "performance")
                        return performancePane;

                    if (root.activeTab() === "weather")
                        return weatherPane;

                    if (root.activeTab() === "actions")
                        return actionsPane;

                    if (root.activeTab() === "audio")
                        return audioPane;

                    if (root.activeTab() === "network")
                        return networkPane;

                    if (root.activeTab() === "display")
                        return displayPane;

                    if (root.activeTab() === "wallpaper")
                        return wallpaperPane;

                    if (root.activeTab() === "system")
                        return systemPane;

                    if (root.activeTab() === "settings")
                        return settingsPane;

                    return homePane;
                }
            }

        }

        Rectangle {
            anchors.fill: parent
            radius: 32
            color: "#99000000"
            visible: root.networkPasswordPromptOpen
            z: 20

            MouseArea {
                anchors.fill: parent
                onClicked: root.closeNetworkPasswordPrompt()
            }

            Rectangle {
                anchors.centerIn: parent
                width: Math.min(420, parent.width - 80)
                implicitHeight: passwordLayout.implicitHeight + 32
                radius: 22
                color: theme.notificationSurfaceAlt
                border.width: 1
                border.color: theme.attentionBorder

                ColumnLayout {
                    id: passwordLayout

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 16
                    spacing: 12

                    Text {
                        Layout.fillWidth: true
                        text: "Wi-Fi Password"
                        color: theme.primaryText
                        font.pixelSize: 17
                        font.bold: true
                        font.family: theme.fontFamilyMono
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root.networkPasswordTargetSsid || "Hidden network"
                        color: theme.mutedText
                        font.pixelSize: theme.fontSm
                        font.family: theme.fontFamilyMono
                        elide: Text.ElideRight
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 44
                        radius: 16
                        color: theme.darkSurface
                        border.width: 1
                        border.color: networkPasswordInput.activeFocus ? theme.accent : theme.faintBorder

                        TextInput {
                            id: networkPasswordInput

                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 14
                            verticalAlignment: TextInput.AlignVCenter
                            color: theme.primaryText
                            selectionColor: theme.attentionFill
                            selectedTextColor: theme.primaryText
                            echoMode: TextInput.Password
                            text: root.networkPasswordValue
                            font.pixelSize: theme.fontMd
                            font.family: theme.fontFamilyMono
                            onTextChanged: root.networkPasswordValue = text
                            Keys.onEscapePressed: root.closeNetworkPasswordPrompt()
                            Keys.onReturnPressed: root.submitNetworkPassword()
                            Keys.onEnterPressed: root.submitNetworkPassword()
                        }

                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Item {
                            Layout.fillWidth: true
                        }

                        Rectangle {
                            implicitWidth: 92
                            implicitHeight: 34
                            radius: 17
                            color: theme.darkControl
                            border.width: 1
                            border.color: theme.faintBorder

                            Text {
                                anchors.centerIn: parent
                                text: "Cancel"
                                color: theme.bodyText
                                font.pixelSize: theme.fontSm
                                font.bold: true
                                font.family: theme.fontFamilyMono
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.closeNetworkPasswordPrompt()
                            }

                        }

                        Rectangle {
                            implicitWidth: 92
                            implicitHeight: 34
                            radius: 17
                            color: root.networkPasswordValue.trim() !== "" ? theme.attentionFill : theme.darkControl
                            border.width: 1
                            border.color: root.networkPasswordValue.trim() !== "" ? theme.attentionBorder : theme.faintBorder

                            Text {
                                anchors.centerIn: parent
                                text: "Connect"
                                color: theme.primaryText
                                font.pixelSize: theme.fontSm
                                font.bold: true
                                font.family: theme.fontFamilyMono
                            }

                            MouseArea {
                                anchors.fill: parent
                                enabled: root.networkPasswordValue.trim() !== ""
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.submitNetworkPassword()
                            }

                        }

                    }

                }

            }

        }

    }

    Component {
        id: homePane

        DashboardComponents.HomePane {
            anchors.fill: parent
            theme: root.dashboardTheme
            clockService: clock
            infoService: info
            weatherService: weather
            statsService: stats
            musicService: root.musicService
            lyricsService: root.lyricsService
            config: configService
            calendarDate: root.calendarDate
            currentSelection: root.selectedId()
            lyricsVisible: root.lyricsVisible
            onToggleLyrics: root.lyricsVisible = !root.lyricsVisible
            onChangeCalendarMonth: (delta) => {
                root.calendarDate = new Date(root.calendarDate.getFullYear(), root.calendarDate.getMonth() + delta, 1);
            }
        }

    }

    Component {
        id: mediaPane

        DashboardComponents.MediaCard {
            anchors.fill: parent
            expanded: true
            selectableId: ""
            currentSelection: root.selectedId()
            theme: root.dashboardTheme
            music: root.musicService
            lyrics: root.lyricsService
            showLyrics: !configService || configService.showLyrics
            lyricsVisible: root.lyricsVisible
            onPrevious: music.previous()
            onToggle: music.toggle()
            onNext: music.next()
            onToggleLyrics: root.lyricsVisible = !root.lyricsVisible
        }

    }

    Component {
        id: performancePane

        DashboardComponents.PerformancePane {
            theme: root.dashboardTheme
            stats: root.statsService
            currentSelection: root.selectedId()
        }

    }

    Component {
        id: actionsPane

        DashboardComponents.QuickActionGrid {
            anchors.fill: parent
            theme: root.dashboardTheme
            actions: root.quickActions
            selectedIndex: root.selectedIndex
            expanded: true
            onRunCommand: (command) => {
                return root.runCommand(command);
            }
        }

    }

    Component {
        id: networkPane

        DashboardComponents.NetworkPane {
            anchors.fill: parent
            theme: root.dashboardTheme
            network: root.networkService
            currentSelection: root.selectedId()
            onToggleWifi: network.toggleWifi()
            onRefreshNetwork: network.refresh()
            onDisconnectCurrent: network.disconnectCurrent()
            onOpenSettings: root.runCommand("nm-connection-editor")
            onSelectNetwork: (entry) => {
                if (entry.active || entry.known || entry.connectable)
                    network.activateNetwork(entry);
                else
                    root.openNetworkPasswordPrompt(entry.ssid);
            }
            onRequestPasswordPrompt: (ssid) => {
                return root.openNetworkPasswordPrompt(ssid);
            }
            onHoverItem: (itemId) => {
                return root.selectedIndex = root.selectedItems().indexOf(itemId);
            }
        }

    }

    Component {
        id: audioPane

        DashboardComponents.AudioPane {
            anchors.fill: parent
            theme: root.dashboardTheme
            volume: root.volumeService
            music: root.musicService
            currentSelection: root.selectedId()
            onSetVolume: (value) => {
                return volume.setLevel(value);
            }
            onToggleMute: volume.toggleMute()
            onToggleMedia: music.toggle()
            onSelectSink: (sink) => {
                return volume.setDefaultSink(sink);
            }
            onHoverItem: (itemId) => {
                return root.selectedIndex = root.selectedItems().indexOf(itemId);
            }
        }

    }

    Component {
        id: displayPane

        DashboardComponents.DisplayPane {
            anchors.fill: parent
            theme: root.dashboardTheme
            brightness: root.brightnessService
            currentSelection: root.selectedId()
            onSetBrightness: (value) => {
                return brightness.setLevel(value);
            }
            onStepBrightness: (delta) => {
                return brightness.stepLevel(delta);
            }
            onRefreshBrightness: brightness.refresh()
        }

    }

    Component {
        id: wallpaperPane

        DashboardComponents.WallpaperPane {
            anchors.fill: parent
            theme: root.dashboardTheme
            wallpapers: root.wallpapers
            currentSelection: root.selectedId()
            onApplyRandom: wallpapers.applyRandom()
            onToggleFavoriteCurrent: wallpapers.toggleFavoriteCurrent()
            onRefreshWallpapers: wallpapers.refresh()
            onSetMode: (mode) => {
                return wallpapers.setMode(mode);
            }
            onApplyWallpaper: (wallpaper) => {
                return wallpapers.apply(wallpaper.path);
            }
            onHoverItem: (itemId) => {
                return root.selectedIndex = root.selectedItems().indexOf(itemId);
            }
        }

    }

    Component {
        id: systemPane

        DashboardComponents.SystemPane {
            anchors.fill: parent
            theme: root.dashboardTheme
            updates: root.updates
            systemActions: root.systemActions
            currentSelection: root.selectedId()
            actionItems: root.systemActionItems()
            onRefreshUpdates: updates.refresh()
            onRunAction: (actionId) => {
                return root.activateControlAction(actionId);
            }
            onHoverItem: (itemId) => {
                return root.selectedIndex = root.selectedItems().indexOf(itemId);
            }
        }

    }

    Component {
        id: settingsPane

        DashboardComponents.SettingsPane {
            anchors.fill: parent
            theme: root.dashboardTheme
            fileSearchConfig: root.fileSearchConfigService
        }

    }

    Component {
        id: weatherPane

        DashboardComponents.WeatherCard {
            anchors.fill: parent
            theme: root.dashboardTheme
            weatherService: weather
            currentSelection: root.selectedId()
            expanded: true
            selectableId: "weather"
            onRefreshRequested: weather.refresh()
        }

    }

}
