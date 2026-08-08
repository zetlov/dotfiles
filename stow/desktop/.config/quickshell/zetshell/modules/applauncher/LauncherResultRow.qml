import QtQuick
import QtQuick.Layouts
import Quickshell

Rectangle {
    id: root

    required property var entry
    required property int index
    required property bool selected
    required property QtObject launcherService
    required property QtObject palette
    readonly property var aliases: launcherService ? launcherService.resultAliases(entry) : []
    readonly property bool favorite: launcherService ? launcherService.resultIsFavorite(entry) : false
    readonly property string typeLabel: launcherService ? launcherService.resultTypeLabel(entry) : ""

    signal launchRequested(var entry)

    width: ListView.view ? ListView.view.width : implicitWidth
    implicitHeight: 62
    radius: 8
    color: selected ? Qt.rgba(1, 1, 1, 0.12) : "transparent"
    border.width: 0

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 14
        spacing: 10

        Rectangle {
            implicitWidth: 34
            implicitHeight: 34
            radius: 9
            color: root.selected ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.06)
            border.width: 0
            clip: true

            Image {
                id: appIcon

                anchors.centerIn: parent
                width: 22
                height: 22
                source: {
                    const icon = root.entry.icon;
                    if (!icon || !root.launcherService.availableIcons)
                        return "";

                    if (icon.startsWith("/"))
                        return icon;

                    return root.launcherService.availableIcons.has(icon) ? Quickshell.iconPath(icon) : "";
                }
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                visible: status === Image.Ready
            }

            Text {
                anchors.centerIn: parent
                text: root.launcherService.initials(root.entry.title)
                color: root.palette.primaryText
                font.pixelSize: root.palette.fontSm
                font.bold: true
                font.family: root.palette.fontFamilyMono
                visible: appIcon.status !== Image.Ready
            }

        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            RowLayout {
                Layout.fillWidth: true

                Text {
                    Layout.fillWidth: true
                    text: root.entry.title || ""
                    color: root.palette.primaryText
                    font.pixelSize: root.palette.fontMd
                    font.bold: root.selected
                    font.family: root.palette.fontFamilyMono
                    elide: Text.ElideRight
                }

                Rectangle {
                    visible: root.favorite
                    implicitWidth: 34
                    implicitHeight: 18
                    radius: 9
                    color: Qt.alpha(root.palette.accentWarm, 0.14)
                    border.width: 0

                    Text {
                        anchors.centerIn: parent
                        text: "FAV"
                        color: root.palette.primaryText
                        font.pixelSize: root.palette.fontXs
                        font.bold: true
                        font.family: root.palette.fontFamilyMono
                    }

                }

            }

            Text {
                Layout.fillWidth: true
                text: root.entry.subtitle || ""
                color: root.palette.mutedText
                font.pixelSize: root.palette.fontXs
                font.family: root.palette.fontFamilyMono
                elide: Text.ElideRight
                visible: text.length > 0
            }

        }

        ColumnLayout {
            spacing: 4

            Rectangle {
                implicitWidth: Math.max(48, typeText.implicitWidth + 18)
                implicitHeight: 20
                radius: 10
                color: "transparent"
                border.width: 0

                Text {
                    id: typeText

                    anchors.centerIn: parent
                    text: root.typeLabel
                    color: root.selected ? root.palette.bodyText : root.palette.mutedText
                    font.pixelSize: root.palette.fontXs
                    font.bold: true
                    font.family: root.palette.fontFamilyMono
                }

            }

            Rectangle {
                visible: root.selected
                implicitWidth: 52
                implicitHeight: 20
                radius: 10
                color: "transparent"
                border.width: 0

                Text {
                    anchors.centerIn: parent
                    text: "Enter"
                    color: root.palette.bodyText
                    font.pixelSize: root.palette.fontXs
                    font.bold: true
                    font.family: root.palette.fontFamilyMono
                }

            }

            Rectangle {
                visible: !root.selected && root.aliases.length > 0
                implicitWidth: Math.max(44, aliasText.implicitWidth + 18)
                implicitHeight: 20
                radius: 10
                color: "transparent"
                border.width: 0

                Text {
                    id: aliasText

                    anchors.centerIn: parent
                    text: root.aliases.length > 0 ? root.aliases[0] : ""
                    color: root.palette.mutedText
                    font.pixelSize: root.palette.fontXs
                    font.family: root.palette.fontFamilyMono
                }

            }

        }

    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: root.launcherService.selectedIndex = root.index
        onClicked: root.launchRequested(root.entry)
    }

}
