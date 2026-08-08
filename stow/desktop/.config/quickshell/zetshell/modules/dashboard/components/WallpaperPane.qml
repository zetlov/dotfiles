import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root

    property QtObject theme: null
    property QtObject wallpapers: null
    property string currentSelection: ""

    signal applyRandom()
    signal toggleFavoriteCurrent()
    signal refreshWallpapers()
    signal setMode(string mode)
    signal applyWallpaper(var wallpaper)
    signal hoverItem(string itemId)

    readonly property bool hasTheme: theme !== null
    readonly property bool hasWallpapers: wallpapers !== null

    radius: 20
    color: hasTheme ? theme.cardColor : "transparent"
    border.width: 1
    border.color: hasTheme ? theme.faintBorder : "transparent"
    clip: true

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 22
        spacing: 14

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Text {
                    Layout.fillWidth: true
                    text: root.hasWallpapers ? root.wallpapers.currentName || "No wallpaper selected" : "Wallpaper"
                    color: root.theme.primaryText
                    font.pixelSize: 18
                    font.bold: true
                    font.family: root.theme.fontFamilyMono
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    text: root.hasWallpapers ? `${root.wallpapers.statusText}  mode: ${root.wallpapers.mode}` : ""
                    color: root.hasWallpapers && root.wallpapers.actionError ? root.theme.dangerText : root.theme.mutedText
                    font.pixelSize: root.theme.fontSm
                    font.family: root.theme.fontFamilyMono
                    elide: Text.ElideRight
                }
            }

            Text {
                text: root.hasWallpapers && root.wallpapers.currentFavorite ? "Favorite" : ""
                color: root.theme.accentWarm
                font.pixelSize: root.theme.fontSm
                font.bold: true
                font.family: root.theme.fontFamilyMono
            }
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 5
            rowSpacing: 8
            columnSpacing: 8

            WallpaperChip {
                label: "Random"
                selected: root.currentSelection === "wallpaper-random"
                onClicked: root.applyRandom()
            }

            WallpaperChip {
                label: root.hasWallpapers && root.wallpapers.currentFavorite ? "Unfavorite" : "Favorite"
                selected: root.currentSelection === "wallpaper-favorite"
                onClicked: root.toggleFavoriteCurrent()
            }

            WallpaperChip {
                label: root.hasWallpapers && root.wallpapers.busy ? "Working" : "Refresh"
                selected: root.currentSelection === "wallpaper-refresh"
                onClicked: root.refreshWallpapers()
            }

            WallpaperChip {
                label: "Dark"
                selected: root.currentSelection === "wallpaper-dark" || (root.hasWallpapers && root.wallpapers.mode === "dark")
                onClicked: root.setMode("dark")
            }

            WallpaperChip {
                label: "Light"
                selected: root.currentSelection === "wallpaper-light" || (root.hasWallpapers && root.wallpapers.mode === "light")
                onClicked: root.setMode("light")
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 18
            color: "#12000000"
            border.width: 1
            border.color: root.theme.faintBorder

            ListView {
                id: wallpaperList

                anchors.fill: parent
                anchors.margins: 8
                clip: true
                spacing: 8
                model: root.hasWallpapers ? root.wallpapers.wallpapers : []
                currentIndex: Math.max(-1, root.currentSelection.indexOf("wallpaper-item-") === 0 ? parseInt(root.currentSelection.substring("wallpaper-item-".length), 10) : -1)

                onCurrentIndexChanged: {
                    if (currentIndex >= 0)
                        positionViewAtIndex(currentIndex, ListView.Contain);
                }

                delegate: Rectangle {
                    required property var modelData
                    required property int index

                    readonly property string itemId: `wallpaper-item-${index}`
                    readonly property bool selected: root.currentSelection === itemId

                    width: wallpaperList.width
                    implicitHeight: 82
                    radius: 18
                    color: selected ? Qt.alpha(root.theme.attentionFill, 0.28) : root.theme.cardColor
                    border.width: selected ? 2 : 1
                    border.color: selected || modelData.current ? root.theme.attentionBorder : root.theme.cardBorder

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 12

                        Rectangle {
                            Layout.preferredWidth: 88
                            Layout.preferredHeight: 58
                            radius: 14
                            color: root.theme.darkSurface
                            border.width: 1
                            border.color: root.theme.faintBorder
                            clip: true

                            Image {
                                anchors.fill: parent
                                source: `file://${modelData.path}`
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: false
                                sourceSize.width: 176
                                sourceSize.height: 116
                            }

                            Rectangle {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.margins: 6
                                implicitWidth: badgeText.implicitWidth + 12
                                implicitHeight: 20
                                radius: 10
                                color: modelData.current ? root.theme.attentionFill : "#80000000"
                                border.width: modelData.current ? 1 : 0
                                border.color: modelData.current ? root.theme.attentionBorder : "transparent"
                                visible: modelData.current || modelData.favorite || modelData.recent

                                Text {
                                    id: badgeText

                                    anchors.centerIn: parent
                                    text: modelData.current ? "Current" : modelData.favorite ? "Fav" : "Recent"
                                    color: root.theme.brightText
                                    font.pixelSize: root.theme.fontXs
                                    font.bold: true
                                    font.family: root.theme.fontFamilyMono
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: -1

                            Text {
                                Layout.fillWidth: true
                                text: modelData.name
                                color: root.theme.primaryText
                                font.pixelSize: root.theme.fontMd
                                font.bold: true
                                font.family: root.theme.fontFamilyMono
                                elide: Text.ElideRight
                            }

                            Text {
                                Layout.fillWidth: true
                                text: modelData.current
                                    ? "Current wallpaper"
                                    : modelData.recent
                                        ? "Recent pick"
                                        : modelData.favorite
                                            ? "Favorite"
                                            : "Available"
                                color: root.theme.mutedText
                                font.pixelSize: root.theme.fontSm
                                font.family: root.theme.fontFamilyMono
                                elide: Text.ElideRight
                            }
                        }

                        Text {
                            text: selected ? "Enter" : modelData.favorite ? "Favorite" : ""
                            color: modelData.favorite ? root.theme.accentWarm : root.theme.bodyText
                            font.pixelSize: root.theme.fontSm
                            font.bold: selected || modelData.favorite
                            font.family: root.theme.fontFamilyMono
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: root.hoverItem(itemId)
                        onClicked: {
                            root.hoverItem(itemId);
                            root.applyWallpaper(modelData);
                        }
                    }
                }
            }
        }
    }

    component WallpaperChip: Rectangle {
        property string label: ""
        property bool selected: false
        signal clicked

        implicitHeight: 36
        radius: 18
        color: selected ? root.theme.attentionFill : root.theme.darkControl
        border.width: 1
        border.color: selected ? root.theme.attentionBorder : root.theme.faintBorder

        Text {
            anchors.centerIn: parent
            text: parent.label
            color: root.theme.primaryText
            font.pixelSize: root.theme.fontSm
            font.bold: true
            font.family: root.theme.fontFamilyMono
            elide: Text.ElideRight
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.clicked()
        }
    }
}
