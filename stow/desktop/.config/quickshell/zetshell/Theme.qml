import QtQuick
import Quickshell.Io

Item {
    id: root

    readonly property string fontFamilyMono: "JetBrainsMono Nerd Font"

    property color railTop: "#ee11161d"
    property color railBottom: "#dd0a0f14"
    property color panelShadow: "#22000000"
    property color cardColor: "#1cffffff"
    property color notificationSurface: "#e6111820"
    property color notificationSurfaceAlt: "#f0141d26"
    property color cardBorder: "#2effffff"
    property color mutedText: "#99eef6ff"
    property color bodyText: "#dff8ff"
    property color primaryText: "#f3fbff"
    property color titleText: "#f5fbff"
    property color brightText: "#e8fbff"
    property color accent: "#7ae7d7"
    property color accentWarm: "#ffbf7a"
    property color darkControl: "#160d13"
    property color darkSurface: "#101820"
    property color hoverOverlay: "#24ffffff"
    property color workspaceHoverFill: "#1ff2f7ff"
    property color workspaceActiveBorder: "#cc071217"
    property color workspaceHoverBorder: "#5affffff"
    property color workspaceIdleBorder: "#42d9e8ff"
    property color workspaceActiveText: "#081015"
    property color dangerText: "#ffb4ab"
    property color attentionBorder: "#66ffbf7a"
    property color attentionTint: "#55ffd9b0"
    property color attentionFill: "#33ffbf7a"
    property color warmBorder: "#55fff1df"
    property color softBorder: "#4dffffff"
    property color faintBorder: "#1cffffff"
    property color subtleLine: "#42ffffff"

    function refresh() {
        if (!themeProcess.running)
            themeProcess.running = true;
    }

    function applyThemeColors(payload) {
        const colorKeys = [
            "railTop",
            "railBottom",
            "panelShadow",
            "cardColor",
            "notificationSurface",
            "notificationSurfaceAlt",
            "cardBorder",
            "mutedText",
            "bodyText",
            "primaryText",
            "titleText",
            "brightText",
            "accent",
            "accentWarm",
            "darkControl",
            "darkSurface",
            "hoverOverlay",
            "workspaceHoverFill",
            "workspaceActiveBorder",
            "workspaceHoverBorder",
            "workspaceIdleBorder",
            "workspaceActiveText",
            "dangerText",
            "attentionBorder",
            "attentionTint",
            "attentionFill",
            "warmBorder",
            "softBorder",
            "faintBorder",
            "subtleLine"
        ];

        for (const key of colorKeys) {
            if (payload[key])
                root[key] = payload[key];
        }
    }

    Timer {
        interval: 2500
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Process {
        id: themeProcess

        command: [
            "bash",
            "-lc",
            "cat ${XDG_STATE_HOME:-$HOME/.local/state}/zetshell/theme.json 2>/dev/null || true"
        ]

        stdout: StdioCollector {
            onStreamFinished: {
                const raw = this.text.trim();
                if (!raw)
                    return;

                try {
                    root.applyThemeColors(JSON.parse(raw));
                } catch (error) {
                    console.warn("Failed to parse dynamic theme:", error);
                }
            }
        }
    }

    readonly property int panelHeight: 66
    readonly property int panelRadius: 29
    readonly property int panelShadowOffset: 6
    readonly property int panelMarginTop: 12
    readonly property int panelMarginX: 18
    readonly property int panelContentMargin: 8
    readonly property int clusterGap: 14
    readonly property int itemGap: 10

    readonly property int cardHeight: 46
    readonly property int cardRadius: 23
    readonly property int workspaceButtonSize: 30
    readonly property int workspaceButtonRadius: 15
    readonly property int workspaceCardExtraWidth: 22
    readonly property int workspaceGap: 7

    readonly property int musicMinWidth: 240
    readonly property int musicPreferredWidth: 340
    readonly property int musicMaxWidth: 380
    readonly property int musicArtSize: 30
    readonly property int musicArtRadius: 12
    readonly property int musicControlSmall: 22
    readonly property int musicControlLarge: 26
    readonly property int musicControlSmallRadius: 11
    readonly property int musicControlLargeRadius: 13

    readonly property int clockWidth: 218
    readonly property int clockHeight: 50
    readonly property int clockRadius: 25

    readonly property int chipHeight: 40
    readonly property int chipRadius: 20
    readonly property int trayButtonSize: 28
    readonly property int trayButtonRadius: 14
    readonly property int trayIconSize: 18
    readonly property int notificationCenterWidth: 420
    readonly property int notificationCenterHeight: 560
    readonly property int notificationActionHeight: 28
    readonly property int notificationActionRadius: 14
    readonly property int notificationPreviewHeight: 148
    readonly property int notificationToastPreviewHeight: 84
    readonly property int controlCenterWidth: 460
    readonly property int controlCenterHeightMin: 540
    readonly property int controlCenterHeightMax: 1320
    readonly property int controlCenterTabHeight: 34
    readonly property int controlCenterTabRadius: 17
    readonly property int sliderHeight: 8
    readonly property int sliderHandleSize: 18
    readonly property int toastWidth: 360
    readonly property int toastGap: 10
    readonly property int captureLauncherWidthMin: 880
    readonly property int captureLauncherWidthMax: 1380
    readonly property int captureLauncherHeightMin: 620
    readonly property int captureLauncherHeightMax: 1100
    readonly property int captureLauncherRowHeight: 72

    readonly property int fontXs: 9
    readonly property int fontSm: 10
    readonly property int fontMd: 12
    readonly property int fontLg: 13
    readonly property int fontClock: 17
    readonly property int fontIcon: 16

    readonly property int animFast: 140
    readonly property int animBase: 160
    readonly property int animScale: 180

    readonly property int barPanelHeight: 42
    readonly property int barPanelRadius: 0
    readonly property int barPanelShadowOffset: 0
    readonly property int barPanelMarginTop: 0
    readonly property int barPanelMarginX: 0
    readonly property int barPanelContentMargin: 4
    readonly property int barChipContentMargin: 5
    readonly property int barClusterGap: 10
    readonly property int barItemGap: 7

    readonly property int barCardHeight: 30
    readonly property int barCardRadius: 8
    readonly property int barWorkspaceButtonSize: 24
    readonly property int barWorkspaceButtonRadius: 6
    readonly property int barWorkspaceCardExtraWidth: 16
    readonly property int barWorkspaceGap: 5

    readonly property int barMusicArtSize: 20
    readonly property int barMusicArtRadius: 5
    readonly property int barMusicTextHeight: 19
    readonly property int barMusicTitleHeight: 11
    readonly property int barMusicArtistHeight: 8
    readonly property int barMusicTitleFont: 10
    readonly property int barMusicArtistFont: 8
    readonly property int barMusicControlSmall: 16
    readonly property int barMusicControlLarge: 20
    readonly property int barMusicControlSmallRadius: 5
    readonly property int barMusicControlLargeRadius: 6

    readonly property int barClockWidth: 190
    readonly property int barClockHeight: 32
    readonly property int barClockRadius: 8

    readonly property int barChipHeight: 30
    readonly property int barChipRadius: 8
    readonly property int barChipFont: 12
    readonly property int barTrayButtonSize: 24
    readonly property int barTrayButtonRadius: 6
    readonly property int barTrayIconSize: 16
    readonly property int barFontClock: 14
}
