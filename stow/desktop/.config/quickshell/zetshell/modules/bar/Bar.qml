import "../.." as Shell
import "../../services" as Services
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.SystemTray
import Quickshell.Wayland
import Quickshell.Widgets

PanelWindow {
    id: root

    property string targetMonitor: ""
    property string screenNameHint: ""
    property QtObject notificationService: null
    property QtObject controlCenterService: null
    property QtObject networkService: null
    readonly property QtObject network: networkService
    readonly property color railTop: theme.railTop
    readonly property color railBottom: theme.railBottom
    readonly property color cardColor: theme.cardColor
    readonly property color cardBorder: theme.cardBorder
    readonly property color mutedText: theme.mutedText
    readonly property color accent: theme.accent
    readonly property color accentWarm: theme.accentWarm
    readonly property color shellTopColor: Qt.alpha(root.railTop, 0.46)
    readonly property color shellBottomColor: Qt.alpha(root.railBottom, 0.4)
    readonly property color shellBorderColor: Qt.rgba(1, 1, 1, 0.14)
    readonly property var monitorObject: Hyprland.monitorFor(screen)
    readonly property var trayItems: SystemTray.items.values
    readonly property int trayCount: trayItems.length
    readonly property string screenName: screenNameHint
    readonly property bool isTargetMonitor: {
        if (!targetMonitor)
            return true;

        if (!screenName)
            return false;

        return screenName === targetMonitor;
    }
    readonly property var workspaceList: {
        const monitor = monitorObject;
        const monitorName = monitor ? monitor.name : "";
        return Hyprland.workspaces.values.filter((ws) => {
            return ws.id > 0 && ws.monitor && ws.monitor.name === monitorName;
        }).sort((a, b) => {
            return a.id - b.id;
        });
    }

    function trayIconSource(icon) {
        if (!icon)
            return "";

        if (icon === "input-keyboard-symbolic")
            return "file:///usr/share/icons/Adwaita/symbolic/devices/input-keyboard-symbolic.svg";

        if (icon.includes("?path=")) {
            const parts = icon.split("?path=");
            if (parts.length === 2) {
                const iconName = parts[0].replace("image://icon/", "");
                return `file://${parts[1]}/${iconName}.png`;
            }
        }
        if (icon.startsWith("/") || icon.includes("://"))
            return icon;

        return Quickshell.iconPath(icon);
    }

    color: "transparent"
    implicitHeight: theme.barPanelHeight
    exclusiveZone: isTargetMonitor ? implicitHeight + margins.top : 0
    WlrLayershell.namespace: "zetshell-bar"
    visible: isTargetMonitor

    anchors {
        top: true
        left: true
        right: true
    }

    margins {
        top: theme.barPanelMarginTop
        left: theme.barPanelMarginX
        right: theme.barPanelMarginX
    }

    Shell.Theme {
        id: theme
    }

    Services.ClockService {
        id: clock
    }

    Services.SystemStatsService {
        id: stats
    }

    Services.VolumeService {
        id: volume
    }

    Services.UpdateService {
        id: updates
    }

    Services.MusicService {
        id: music
    }

    Services.ImeService {
        id: ime
    }

    Rectangle {
        anchors.fill: parent
        anchors.topMargin: theme.barPanelShadowOffset
        radius: theme.barPanelRadius
        color: theme.panelShadow
        opacity: 0.12
    }

    Rectangle {
        anchors.fill: parent
        radius: theme.barPanelRadius
        border.width: 1
        border.color: root.shellBorderColor

        Item {
            anchors.fill: parent
            anchors.margins: theme.barPanelContentMargin

            Item {
                id: leftCluster

                anchors.left: parent.left
                anchors.right: clockCard.left
                anchors.rightMargin: theme.barClusterGap
                anchors.verticalCenter: parent.verticalCenter
                height: theme.barCardHeight

                RowLayout {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: theme.barItemGap

                    Rectangle {
                        id: workspaceCard

                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: workspaceRow.implicitWidth + theme.barWorkspaceCardExtraWidth
                        implicitHeight: theme.barCardHeight
                        radius: theme.barCardRadius
                        color: root.cardColor
                        border.width: 0

                        Row {
                            id: workspaceRow

                            anchors.centerIn: parent
                            spacing: theme.barWorkspaceGap

                            Repeater {
                                model: root.workspaceList

                                Rectangle {
                                    required property var modelData
                                    property bool hovered: false

                                    width: theme.barWorkspaceButtonSize
                                    height: theme.barWorkspaceButtonSize
                                    radius: theme.barWorkspaceButtonRadius
                                    color: modelData.active ? root.accent : hovered ? theme.workspaceHoverFill : "transparent"
                                    border.width: 0
                                    scale: modelData.active ? 1.06 : hovered ? 1.02 : 1

                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.id
                                        color: modelData.active ? theme.workspaceActiveText : theme.bodyText
                                        font.pixelSize: theme.fontMd
                                        font.bold: true
                                        font.family: theme.fontFamilyMono
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onEntered: parent.hovered = true
                                        onExited: parent.hovered = false
                                        onClicked: modelData.activate()
                                    }

                                    Behavior on color {
                                        ColorAnimation {
                                            duration: theme.animBase
                                        }

                                    }

                                    Behavior on scale {
                                        NumberAnimation {
                                            duration: theme.animScale
                                            easing.type: Easing.OutCubic
                                        }

                                    }

                                }

                            }

                        }

                    }

                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        Layout.preferredWidth: theme.musicPreferredWidth
                        Layout.maximumWidth: theme.musicMaxWidth
                        Layout.minimumWidth: theme.musicMinWidth
                        implicitHeight: theme.barCardHeight
                        radius: theme.barCardRadius
                        color: root.cardColor
                        border.width: 0
                        visible: music.hasPlayer

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: theme.barPanelContentMargin
                            spacing: theme.barPanelContentMargin

                            Rectangle {
                                Layout.alignment: Qt.AlignVCenter
                                implicitWidth: theme.barMusicArtSize
                                implicitHeight: theme.barMusicArtSize
                                radius: theme.barMusicArtRadius
                                color: theme.darkSurface
                                border.width: 0
                                visible: music.artUrl === ""

                                Text {
                                    anchors.centerIn: parent
                                    text: "♪"
                                    color: root.accent
                                    font.pixelSize: theme.fontIcon
                                }

                            }

                            Image {
                                Layout.alignment: Qt.AlignVCenter
                                Layout.preferredWidth: theme.barMusicArtSize
                                Layout.preferredHeight: theme.barMusicArtSize
                                source: music.artUrl
                                visible: music.artUrl !== ""
                                asynchronous: true
                                cache: true
                                fillMode: Image.PreserveAspectCrop
                                clip: true
                                sourceSize.width: 96
                                sourceSize.height: 96
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                Layout.preferredHeight: theme.barMusicTextHeight
                                spacing: 0

                                Item {
                                    id: musicTitleViewport

                                    Layout.fillWidth: true
                                    Layout.preferredHeight: theme.barMusicTitleHeight
                                    clip: true

                                    Text {
                                        id: musicTitleText

                                        anchors.verticalCenter: parent.verticalCenter
                                        height: parent.height
                                        x: 0
                                        text: music.title
                                        color: theme.titleText
                                        font.pixelSize: theme.barMusicTitleFont
                                        font.bold: true
                                        font.family: theme.fontFamilyMono
                                        verticalAlignment: Text.AlignVCenter
                                    }

                                    SequentialAnimation {
                                        id: titleMarquee

                                        running: music.hasPlayer && musicTitleText.contentWidth > musicTitleViewport.width
                                        loops: Animation.Infinite
                                        onRunningChanged: {
                                            if (!running)
                                                musicTitleText.x = 0;

                                        }

                                        PauseAnimation {
                                            duration: 1100
                                        }

                                        NumberAnimation {
                                            target: musicTitleText
                                            property: "x"
                                            from: 0
                                            to: -(musicTitleText.contentWidth - musicTitleViewport.width)
                                            duration: Math.max(2600, (musicTitleText.contentWidth - musicTitleViewport.width) * 22)
                                            easing.type: Easing.InOutSine
                                        }

                                        PauseAnimation {
                                            duration: 700
                                        }

                                        NumberAnimation {
                                            target: musicTitleText
                                            property: "x"
                                            to: 0
                                            duration: 900
                                            easing.type: Easing.InOutSine
                                        }

                                    }

                                }

                                Text {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: theme.barMusicArtistHeight
                                    text: music.artist
                                    color: root.mutedText
                                    font.pixelSize: theme.barMusicArtistFont
                                    verticalAlignment: Text.AlignVCenter
                                    elide: Text.ElideRight
                                }

                            }

                            RowLayout {
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 4

                                Rectangle {
                                    implicitWidth: theme.barMusicControlSmall
                                    implicitHeight: theme.barMusicControlSmall
                                    radius: theme.barMusicControlSmallRadius
                                    color: theme.darkControl
                                    border.width: 0
                                    opacity: music.canGoPrevious ? 1 : 0.45

                                    Text {
                                        anchors.centerIn: parent
                                        text: "⏮"
                                        color: theme.brightText
                                        font.pixelSize: theme.fontSm
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        enabled: music.canGoPrevious
                                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                        onClicked: music.previous()
                                    }

                                }

                                Rectangle {
                                    implicitWidth: theme.barMusicControlLarge
                                    implicitHeight: theme.barMusicControlLarge
                                    radius: theme.barMusicControlLargeRadius
                                    color: root.accentWarm
                                    border.width: 0
                                    opacity: music.canToggle ? 1 : 0.45

                                    Text {
                                        anchors.centerIn: parent
                                        text: music.isPlaying ? "⏸" : "▶"
                                        color: "#1c130c"
                                        font.pixelSize: theme.fontMd
                                        font.bold: true
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        enabled: music.canToggle
                                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                        onClicked: music.toggle()
                                    }

                                }

                                Rectangle {
                                    implicitWidth: theme.barMusicControlSmall
                                    implicitHeight: theme.barMusicControlSmall
                                    radius: theme.barMusicControlSmallRadius
                                    color: theme.darkControl
                                    border.width: 0
                                    opacity: music.canGoNext ? 1 : 0.45

                                    Text {
                                        anchors.centerIn: parent
                                        text: "⏭"
                                        color: theme.brightText
                                        font.pixelSize: theme.fontSm
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        enabled: music.canGoNext
                                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                        onClicked: music.next()
                                    }

                                }

                            }

                        }

                    }

                }

            }

            Rectangle {
                id: clockCard

                anchors.centerIn: parent
                width: theme.barClockWidth
                height: theme.barClockHeight
                radius: theme.barClockRadius
                color: root.cardColor
                border.width: 0

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 0

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: clock.timeText
                        color: theme.primaryText
                        font.pixelSize: theme.barFontClock
                        font.bold: true
                        font.family: theme.fontFamilyMono
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: clock.dateText
                        color: root.mutedText
                        font.pixelSize: theme.fontSm
                    }

                }

            }

            Item {
                id: rightCluster

                anchors.left: clockCard.right
                anchors.leftMargin: theme.barClusterGap
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: theme.barCardHeight

                RowLayout {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: theme.barPanelContentMargin

                    Rectangle {
                        id: trayCard

                        implicitWidth: trayRow.implicitWidth + theme.barPanelContentMargin * 2
                        implicitHeight: theme.barChipHeight
                        radius: theme.barChipRadius
                        color: root.cardColor
                        border.width: 0
                        visible: trayCount > 0

                        Row {
                            id: trayRow

                            anchors.centerIn: parent
                            spacing: 4

                            Repeater {
                                model: root.trayItems

                                Rectangle {
                                    id: trayButton

                                    required property var modelData
                                    readonly property string trayMetaText: `${modelData.id || ""} ${modelData.title || ""} ${modelData.tooltipTitle || ""} ${modelData.tooltipDescription || ""}`.toLowerCase()
                                    readonly property bool isFcitxItem: trayMetaText.includes("input method") || trayMetaText.includes("keyboard") || trayMetaText.includes("fcitx")
                                    readonly property bool showFcitxFallback: isFcitxItem && (modelData.icon === "input-keyboard-symbolic" || trayMetaText.includes("keyboard") || trayMetaText.includes("english") || trayMetaText.includes("hiragana") || trayMetaText.includes("japanese") || trayMetaText.includes("mozc"))
                                    readonly property string fcitxBadgeText: ime.badgeText
                                    readonly property bool useSymbolicTint: modelData.icon.includes("symbolic")

                                    width: theme.barTrayButtonSize
                                    height: theme.barTrayButtonSize
                                    radius: theme.barTrayButtonRadius
                                    color: trayMouseArea.containsMouse ? theme.hoverOverlay : "transparent"
                                    border.width: 0
                                    opacity: modelData.status === Status.Passive ? 0.72 : 1

                                    Item {
                                        anchors.centerIn: parent
                                        width: theme.barTrayIconSize
                                        height: theme.barTrayIconSize

                                        Loader {
                                            anchors.fill: parent
                                            sourceComponent: trayButton.showFcitxFallback ? fcitxBadge : trayIconComponent
                                        }

                                        Component {
                                            id: fcitxBadge

                                            Text {
                                                anchors.centerIn: parent
                                                text: trayButton.fcitxBadgeText
                                                color: ime.active ? root.accentWarm : theme.brightText
                                                font.pixelSize: theme.fontLg
                                                font.bold: true
                                                font.family: theme.fontFamilyMono
                                            }

                                        }

                                        Component {
                                            id: trayIconComponent

                                            Item {
                                                anchors.fill: parent

                                                IconImage {
                                                    id: trayIconBase

                                                    anchors.fill: parent
                                                    implicitSize: theme.barTrayIconSize
                                                    source: root.trayIconSource(modelData.icon)
                                                    asynchronous: true
                                                    opacity: trayButton.useSymbolicTint ? 0 : 1
                                                }

                                                ColorOverlay {
                                                    anchors.fill: trayIconBase
                                                    source: trayIconBase
                                                    color: modelData.status === Status.NeedsAttention ? theme.accentWarm : theme.brightText
                                                    visible: trayButton.useSymbolicTint
                                                }

                                            }

                                        }

                                    }

                                    MouseArea {
                                        id: trayMouseArea

                                        anchors.fill: parent
                                        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: (mouse) => {
                                            const popupX = trayCard.x + trayRow.x + trayButton.x + Math.round(trayButton.width / 2);
                                            if (mouse.button === Qt.RightButton && modelData.hasMenu) {
                                                modelData.display(root, popupX, root.height - 4);
                                                return ;
                                            }
                                            if (mouse.button === Qt.MiddleButton) {
                                                modelData.secondaryActivate();
                                                return ;
                                            }
                                            if (modelData.onlyMenu && modelData.hasMenu) {
                                                modelData.display(root, popupX, root.height - 4);
                                                return ;
                                            }
                                            modelData.activate();
                                        }
                                        onWheel: (wheel) => {
                                            const delta = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.angleDelta.x;
                                            if (delta !== 0)
                                                modelData.scroll(delta, wheel.angleDelta.x !== 0);

                                        }
                                    }

                                    Behavior on color {
                                        ColorAnimation {
                                            duration: theme.animFast
                                        }

                                    }

                                }

                            }

                        }

                    }

                    Rectangle {
                        implicitWidth: 78
                        implicitHeight: theme.barChipHeight
                        radius: theme.barChipRadius
                        color: updates.hasUpdates ? theme.attentionFill : root.cardColor
                        border.width: 0

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 3

                            Text {
                                Layout.alignment: Qt.AlignVCenter
                                text: "UPD:"
                                color: updates.hasUpdates ? "#fff1df" : root.mutedText
                                font.pixelSize: theme.barChipFont
                                font.bold: true
                                font.family: theme.fontFamilyMono
                                verticalAlignment: Text.AlignVCenter
                            }

                            Text {
                                Layout.alignment: Qt.AlignVCenter
                                text: updates.text
                                color: updates.hasUpdates ? "#fff8ef" : "#d6eef5"
                                font.pixelSize: theme.barChipFont
                                font.bold: true
                                font.family: theme.fontFamilyMono
                                verticalAlignment: Text.AlignVCenter
                            }

                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: updates.refresh()
                        }

                    }

                    Rectangle {
                        implicitWidth: 82
                        implicitHeight: theme.barChipHeight
                        radius: theme.barChipRadius
                        color: notificationService && notificationService.hasUnread ? theme.attentionFill : root.cardColor
                        border.width: 0

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 3

                            Text {
                                Layout.alignment: Qt.AlignVCenter
                                text: "NOTI:"
                                color: notificationService && notificationService.hasUnread ? "#fff1df" : root.mutedText
                                font.pixelSize: theme.barChipFont
                                font.bold: true
                                font.family: theme.fontFamilyMono
                                verticalAlignment: Text.AlignVCenter
                            }

                            Text {
                                Layout.alignment: Qt.AlignVCenter
                                text: notificationService ? notificationService.badgeText : "0"
                                color: notificationService && notificationService.hasUnread ? "#fff8ef" : "#d6eef5"
                                font.pixelSize: theme.barChipFont
                                font.bold: true
                                font.family: theme.fontFamilyMono
                                verticalAlignment: Text.AlignVCenter
                            }

                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (notificationService)
                                    notificationService.toggleCenter();

                            }
                        }

                    }

                    Rectangle {
                        implicitWidth: 138
                        implicitHeight: theme.barChipHeight
                        radius: theme.barChipRadius
                        color: root.cardColor
                        border.width: 0

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: theme.barChipContentMargin
                            spacing: 8

                            RowLayout {
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 3

                                Text {
                                    Layout.alignment: Qt.AlignVCenter
                                    text: "CPU:"
                                    color: theme.bodyText
                                    font.pixelSize: theme.barChipFont
                                    font.bold: true
                                    font.family: theme.fontFamilyMono
                                    verticalAlignment: Text.AlignVCenter
                                }

                                Text {
                                    Layout.alignment: Qt.AlignVCenter
                                    text: `${stats.cpuPercent}%`
                                    color: root.accent
                                    font.pixelSize: theme.barChipFont
                                    font.bold: true
                                    font.family: theme.fontFamilyMono
                                    verticalAlignment: Text.AlignVCenter
                                }

                            }

                            RowLayout {
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 3

                                Text {
                                    Layout.alignment: Qt.AlignVCenter
                                    text: "RAM:"
                                    color: theme.bodyText
                                    font.pixelSize: theme.barChipFont
                                    font.bold: true
                                    font.family: theme.fontFamilyMono
                                    verticalAlignment: Text.AlignVCenter
                                }

                                Text {
                                    Layout.alignment: Qt.AlignVCenter
                                    text: `${stats.ramPercent}%`
                                    color: root.mutedText
                                    font.pixelSize: theme.barChipFont
                                    font.bold: true
                                    font.family: theme.fontFamilyMono
                                    verticalAlignment: Text.AlignVCenter
                                }

                            }

                        }

                    }

                    Rectangle {
                        implicitWidth: 148
                        implicitHeight: theme.barChipHeight
                        radius: theme.barChipRadius
                        color: root.cardColor
                        border.width: 0

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: theme.barChipContentMargin
                            spacing: 5

                            Rectangle {
                                Layout.alignment: Qt.AlignVCenter
                                implicitWidth: 7
                                implicitHeight: 7
                                radius: 4
                                color: network.tone
                            }

                            Text {
                                Layout.alignment: Qt.AlignVCenter
                                text: `${network.state === "wifi" ? "Wi-Fi" : network.state === "ethernet" ? "LAN" : "NET"}:`
                                color: theme.bodyText
                                font.pixelSize: theme.barChipFont
                                font.bold: true
                                font.family: theme.fontFamilyMono
                                verticalAlignment: Text.AlignVCenter
                            }

                            Text {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                text: network.label
                                color: root.mutedText
                                font.pixelSize: theme.barChipFont
                                verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideRight
                            }

                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (controlCenterService)
                                    controlCenterService.openSection("network");

                            }
                        }

                    }

                    Rectangle {
                        implicitWidth: 102
                        implicitHeight: theme.barChipHeight
                        radius: theme.barChipRadius
                        color: root.cardColor
                        border.width: 0

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 3

                            Text {
                                Layout.alignment: Qt.AlignVCenter
                                text: "VOL:"
                                color: theme.bodyText
                                font.pixelSize: theme.barChipFont
                                font.bold: true
                                font.family: theme.fontFamilyMono
                                verticalAlignment: Text.AlignVCenter
                            }

                            Text {
                                Layout.alignment: Qt.AlignVCenter
                                text: volume.text
                                color: volume.muted ? theme.dangerText : volume.tone
                                font.pixelSize: theme.barChipFont
                                font.bold: true
                                font.family: theme.fontFamilyMono
                                verticalAlignment: Text.AlignVCenter
                            }

                        }

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: (mouse) => {
                                if (mouse.button === Qt.MiddleButton) {
                                    volume.toggleMute();
                                    return ;
                                }
                                if (controlCenterService)
                                    controlCenterService.openSection("audio");

                            }
                            onWheel: (wheel) => {
                                const delta = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.angleDelta.x;
                                if (delta !== 0)
                                    volume.stepLevel(delta > 0 ? 5 : -5);

                            }
                        }

                    }

                }

            }

        }

        gradient: Gradient {
            GradientStop {
                position: 0
                color: root.shellTopColor
            }

            GradientStop {
                position: 1
                color: root.shellBottomColor
            }

        }

    }

}
