import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root

    property QtObject theme: null
    property var actions: []
    property int selectedIndex: -1
    property bool expanded: false

    signal runCommand(string command)

    readonly property bool hasTheme: theme !== null

    radius: 20
    color: hasTheme ? theme.cardColor : "transparent"
    border.width: 1
    border.color: hasTheme ? theme.faintBorder : "transparent"
    clip: true

    GridLayout {
        anchors.fill: parent
        anchors.margins: expanded ? 22 : 18
        columns: expanded ? 2 : 1
        rowSpacing: 12
        columnSpacing: 12

        Repeater {
            model: root.actions

            delegate: Rectangle {
                required property var modelData
                required property int index

                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 74
                radius: 18
                color: actionMouse.containsMouse ? root.theme.hoverOverlay : root.theme.darkSurface
                border.width: root.selectedIndex === index ? 2 : 1
                border.color: root.selectedIndex === index ? root.theme.accent : root.theme.faintBorder

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 4

                    Text {
                        Layout.fillWidth: true
                        text: modelData.title
                        color: root.theme.primaryText
                        font.pixelSize: root.theme.fontMd
                        font.bold: true
                        font.family: root.theme.fontFamilyMono
                        elide: Text.ElideRight
                    }

                    Text {
                        Layout.fillWidth: true
                        text: modelData.detail
                        color: root.theme.mutedText
                        font.pixelSize: root.theme.fontSm
                        font.family: root.theme.fontFamilyMono
                        elide: Text.ElideRight
                    }
                }

                MouseArea {
                    id: actionMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.runCommand(modelData.command)
                }
            }
        }
    }
}
