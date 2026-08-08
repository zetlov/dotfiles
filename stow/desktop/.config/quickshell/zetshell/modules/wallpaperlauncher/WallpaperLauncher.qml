import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../.." as Shell
import "../../services" as Services

PanelWindow {
    id: root

    property string targetMonitor: ""
    property string screenNameHint: ""
    property QtObject launcherService: null

    Shell.Theme {
        id: theme
    }

    Services.WallpaperService {
        id: wallpapers
    }

    color: "transparent"
    exclusiveZone: 0

    anchors {
        top: true
        left: true
    }

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
        return Math.max(920, Math.min(1540, Math.round(width * 0.62)));
    }
    readonly property int panelHeight: {
        const height = screen ? screen.height : 1080;
        return Math.max(620, Math.min(1420, Math.round(height * 0.76)));
    }

    margins {
        top: Math.max(24, Math.round(((screen ? screen.height : panelHeight) - panelHeight) / 2))
        left: Math.max(24, Math.round(((screen ? screen.width : panelWidth) - panelWidth) / 2))
    }

    implicitWidth: panelWidth
    implicitHeight: panelHeight

    WlrLayershell.namespace: "zetshell-wallpaper-launcher"
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    property int selectedIndex: 0

    readonly property var filteredWallpapers: {
        const items = wallpapers.wallpapers || [];
        if (!launcherService)
            return items;

        if (launcherService.filter === "recent")
            return items.filter(item => item.current || item.recent);
        if (launcherService.filter === "favorites")
            return items.filter(item => item.favorite);

        return items;
    }

    visible: isTargetMonitor && launcherService && launcherService.open

    onVisibleChanged: {
        if (visible) {
            wallpapers.refresh();
            selectedIndex = 0;
            Qt.callLater(() => focusRoot.forceActiveFocus());
        }
    }

    Connections {
        target: launcherService

        function onFilterChanged() {
            root.selectedIndex = 0;
            Qt.callLater(() => focusRoot.forceActiveFocus());
        }
    }

    function currentFilter() {
        return launcherService ? launcherService.filter : "all";
    }

    function columnCount() {
        return width >= 1380 ? 4 : width >= 1120 ? 3 : 2;
    }

    function applySelected() {
        if (selectedIndex < 0 || selectedIndex >= filteredWallpapers.length)
            return;
        wallpapers.apply(filteredWallpapers[selectedIndex].path);
    }

    function toggleFavoriteSelected() {
        if (selectedIndex < 0 || selectedIndex >= filteredWallpapers.length)
            return;
        wallpapers.toggleFavorite(filteredWallpapers[selectedIndex].path);
    }

    function moveSelection(dx, dy) {
        if (filteredWallpapers.length === 0)
            return;

        const cols = columnCount();
        const currentRow = Math.floor(selectedIndex / cols);
        const currentCol = selectedIndex % cols;
        let nextRow = currentRow + dy;
        let nextCol = currentCol + dx;

        if (dy === 0) {
            const rowStart = currentRow * cols;
            const rowEnd = Math.min(filteredWallpapers.length - 1, rowStart + cols - 1);
            const nextIndex = Math.max(rowStart, Math.min(rowEnd, selectedIndex + dx));
            selectedIndex = nextIndex;
            return;
        }

        nextRow = Math.max(0, nextRow);
        nextCol = Math.max(0, nextCol);
        const nextIndex = Math.min(filteredWallpapers.length - 1, nextRow * cols + Math.min(cols - 1, nextCol));
        selectedIndex = nextIndex;
    }

    Rectangle {
        anchors.fill: parent
        anchors.topMargin: 12
        radius: theme.panelRadius
        color: theme.panelShadow
        opacity: 0.7
    }

    Rectangle {
        anchors.fill: parent
        radius: theme.panelRadius
        color: theme.railBottom
        border.width: 1
        border.color: theme.cardBorder

        FocusScope {
            id: focusRoot

            anchors.fill: parent
            focus: root.visible

            Keys.onPressed: event => {
                if (!launcherService)
                    return;

                if (event.key === Qt.Key_Escape) {
                    launcherService.close();
                    event.accepted = true;
                    return;
                }

                if (event.key === Qt.Key_Left || event.key === Qt.Key_H) {
                    moveSelection(-1, 0);
                    event.accepted = true;
                    return;
                }

                if (event.key === Qt.Key_Right || event.key === Qt.Key_L) {
                    moveSelection(1, 0);
                    event.accepted = true;
                    return;
                }

                if (event.key === Qt.Key_Up || event.key === Qt.Key_K) {
                    moveSelection(0, -1);
                    event.accepted = true;
                    return;
                }

                if (event.key === Qt.Key_Down || event.key === Qt.Key_J) {
                    moveSelection(0, 1);
                    event.accepted = true;
                    return;
                }

                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                    applySelected();
                    event.accepted = true;
                    return;
                }

                if (event.key === Qt.Key_F) {
                    toggleFavoriteSelected();
                    event.accepted = true;
                    return;
                }

                if (event.key === Qt.Key_R) {
                    wallpapers.applyRandom();
                    event.accepted = true;
                    return;
                }

                if (event.key === Qt.Key_D) {
                    wallpapers.setMode("dark");
                    event.accepted = true;
                    return;
                }

                if (event.key === Qt.Key_L && (event.modifiers & Qt.ControlModifier)) {
                    wallpapers.setMode("light");
                    event.accepted = true;
                    return;
                }

                if (event.key === Qt.Key_Tab) {
                    launcherService.cycleFilter(event.modifiers & Qt.ShiftModifier ? -1 : 1);
                    event.accepted = true;
                }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 18
                spacing: 14

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    ColumnLayout {
                        spacing: -2

                        Text {
                            text: "Wallpaper Launcher"
                            color: theme.primaryText
                            font.pixelSize: 18
                            font.bold: true
                            font.family: theme.fontFamilyMono
                        }

                        Text {
                            text: wallpapers.currentName ? `${wallpapers.currentName}  ${wallpapers.mode}` : "Browse wallpapers"
                            color: theme.mutedText
                            font.pixelSize: theme.fontSm
                            font.family: theme.fontFamilyMono
                            elide: Text.ElideRight
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    Rectangle {
                        implicitWidth: 94
                        implicitHeight: theme.chipHeight
                        radius: theme.chipRadius
                        color: theme.darkControl
                        border.width: 1
                        border.color: theme.faintBorder

                        Text {
                            anchors.centerIn: parent
                            text: "Random"
                            color: theme.brightText
                            font.pixelSize: theme.fontMd
                            font.bold: true
                            font.family: theme.fontFamilyMono
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: wallpapers.applyRandom()
                        }
                    }

                    Rectangle {
                        implicitWidth: 40
                        implicitHeight: theme.chipHeight
                        radius: theme.chipRadius
                        color: theme.cardColor
                        border.width: 1
                        border.color: theme.cardBorder

                        Text {
                            anchors.centerIn: parent
                            text: "×"
                            color: theme.brightText
                            font.pixelSize: 15
                            font.bold: true
                            font.family: theme.fontFamilyMono
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: launcherService.close()
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Repeater {
                        model: [
                            { id: "all", label: "All" },
                            { id: "recent", label: "Recent" },
                            { id: "favorites", label: "Favorites" }
                        ]

                        Rectangle {
                            required property var modelData

                            implicitWidth: filterLabel.implicitWidth + 28
                            implicitHeight: theme.chipHeight
                            radius: theme.chipRadius
                            color: currentFilter() === modelData.id ? theme.attentionFill : theme.darkControl
                            border.width: 1
                            border.color: currentFilter() === modelData.id ? theme.attentionBorder : theme.faintBorder

                            Text {
                                id: filterLabel

                                anchors.centerIn: parent
                                text: modelData.label
                                color: theme.brightText
                                font.pixelSize: theme.fontMd
                                font.bold: currentFilter() === modelData.id
                                font.family: theme.fontFamilyMono
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: launcherService.setFilter(modelData.id)
                            }
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    Rectangle {
                        implicitWidth: 82
                        implicitHeight: theme.chipHeight
                        radius: theme.chipRadius
                        color: wallpapers.mode === "dark" ? theme.attentionFill : theme.darkControl
                        border.width: 1
                        border.color: wallpapers.mode === "dark" ? theme.attentionBorder : theme.faintBorder

                        Text {
                            anchors.centerIn: parent
                            text: "Dark"
                            color: theme.brightText
                            font.pixelSize: theme.fontMd
                            font.bold: true
                            font.family: theme.fontFamilyMono
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: wallpapers.setMode("dark")
                        }
                    }

                    Rectangle {
                        implicitWidth: 82
                        implicitHeight: theme.chipHeight
                        radius: theme.chipRadius
                        color: wallpapers.mode === "light" ? theme.attentionFill : theme.darkControl
                        border.width: 1
                        border.color: wallpapers.mode === "light" ? theme.attentionBorder : theme.faintBorder

                        Text {
                            anchors.centerIn: parent
                            text: "Light"
                            color: theme.brightText
                            font.pixelSize: theme.fontMd
                            font.bold: true
                            font.family: theme.fontFamilyMono
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: wallpapers.setMode("light")
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: theme.cardRadius
                    color: "#12000000"
                    border.width: 1
                    border.color: theme.faintBorder

                    GridView {
                        id: grid

                        anchors.fill: parent
                        anchors.margins: 10
                        clip: true
                        cellWidth: Math.floor((width - (columnCount() - 1) * 12) / columnCount())
                        cellHeight: 214
                        model: filteredWallpapers

                        onCountChanged: {
                            if (count === 0)
                                root.selectedIndex = 0;
                            else if (root.selectedIndex >= count)
                                root.selectedIndex = count - 1;
                        }

                        onMovementEnded: {
                            if (root.selectedIndex >= 0 && root.selectedIndex < count)
                                positionViewAtIndex(root.selectedIndex, GridView.Contain);
                        }

                        delegate: Rectangle {
                            required property var modelData
                            required property int index

                            width: grid.cellWidth - 6
                            height: grid.cellHeight - 10
                            radius: theme.cardRadius
                            color: root.selectedIndex === index ? Qt.alpha(theme.attentionFill, 0.28) : theme.cardColor
                            border.width: 1
                            border.color: root.selectedIndex === index || modelData.current ? theme.attentionBorder : theme.cardBorder

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 8

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 138
                                    radius: 16
                                    color: theme.darkSurface
                                    border.width: 1
                                    border.color: theme.faintBorder
                                    clip: true

                                    Image {
                                        anchors.fill: parent
                                        source: `file://${modelData.path}`
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                        cache: false
                                        sourceSize.width: 320
                                        sourceSize.height: 200
                                    }

                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.top: parent.top
                                        anchors.margins: 8
                                        implicitWidth: badgeLabel.implicitWidth + 18
                                        implicitHeight: 24
                                        radius: 12
                                        color: modelData.current ? theme.attentionFill : "#70000000"
                                        border.width: modelData.current ? 1 : 0
                                        border.color: modelData.current ? theme.attentionBorder : "transparent"
                                        visible: modelData.current || modelData.favorite || modelData.recent

                                        Text {
                                            id: badgeLabel

                                            anchors.centerIn: parent
                                            text: modelData.current ? "Current" : modelData.favorite ? "★ Favorite" : "Recent"
                                            color: theme.brightText
                                            font.pixelSize: theme.fontSm
                                            font.bold: true
                                            font.family: theme.fontFamilyMono
                                        }
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.name
                                    color: theme.primaryText
                                    font.pixelSize: theme.fontMd
                                    font.bold: true
                                    font.family: theme.fontFamilyMono
                                    elide: Text.ElideRight
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: root.selectedIndex === index ? "Enter apply  F favorite" : (modelData.current ? "Active" : "Ready")
                                    color: modelData.favorite ? theme.accentWarm : theme.mutedText
                                    font.pixelSize: theme.fontSm
                                    font.family: theme.fontFamilyMono
                                    elide: Text.ElideRight
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: root.selectedIndex = index
                                onClicked: {
                                    root.selectedIndex = index;
                                    wallpapers.apply(modelData.path);
                                }
                            }
                        }

                        Item {
                            anchors.fill: parent
                            visible: filteredWallpapers.length === 0

                            Column {
                                anchors.centerIn: parent
                                spacing: 6

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: currentFilter() === "favorites" ? "No favorites yet" : currentFilter() === "recent" ? "No recent wallpapers yet" : "No wallpapers found"
                                    color: theme.primaryText
                                    font.pixelSize: 16
                                    font.bold: true
                                    font.family: theme.fontFamilyMono
                                }

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: currentFilter() === "favorites" ? "Press F on a wallpaper to save it here" : "Add images under ~/.local/share/wallpapers"
                                    color: theme.mutedText
                                    font.pixelSize: theme.fontSm
                                    font.family: theme.fontFamilyMono
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 42
                    radius: 18
                    color: "#12000000"
                    border.width: 1
                    border.color: theme.faintBorder

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 10

                        Text {
                            text: "Esc close"
                            color: theme.bodyText
                            font.pixelSize: theme.fontSm
                            font.family: theme.fontFamilyMono
                        }

                        Text {
                            text: "Tab filter"
                            color: theme.bodyText
                            font.pixelSize: theme.fontSm
                            font.family: theme.fontFamilyMono
                        }

                        Text {
                            text: "hjkl / arrows move"
                            color: theme.bodyText
                            font.pixelSize: theme.fontSm
                            font.family: theme.fontFamilyMono
                        }

                        Text {
                            text: "Enter apply"
                            color: theme.bodyText
                            font.pixelSize: theme.fontSm
                            font.family: theme.fontFamilyMono
                        }

                        Text {
                            text: "F favorite"
                            color: theme.bodyText
                            font.pixelSize: theme.fontSm
                            font.family: theme.fontFamilyMono
                        }

                        Text {
                            text: "R random"
                            color: theme.bodyText
                            font.pixelSize: theme.fontSm
                            font.family: theme.fontFamilyMono
                        }
                    }
                }
            }
        }
    }
}
