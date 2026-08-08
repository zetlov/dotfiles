import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root

    property QtObject theme: null
    property QtObject weatherService: null
    property string selectableId: ""
    property bool expanded: false
    property string currentSelection: ""

    signal refreshRequested()

    readonly property bool hasWeather: weatherService !== null
    readonly property bool selected: selectableId !== "" && currentSelection === selectableId

    radius: 20
    color: theme.cardColor
    border.width: selected ? 2 : 1
    border.color: selected ? theme.accent : theme.faintBorder
    clip: true

    RowLayout {
        anchors.fill: parent
        anchors.margins: expanded ? 34 : 22
        spacing: expanded ? 30 : 18

        Rectangle {
            Layout.preferredWidth: expanded ? 220 : 130
            Layout.preferredHeight: width
            radius: expanded ? 44 : 28
            color: Qt.alpha(root.theme.accent, root.hasWeather && root.weatherService.available ? 0.18 : 0.08)
            border.width: 1
            border.color: root.hasWeather && root.weatherService.available ? root.theme.attentionBorder : root.theme.faintBorder

            Text {
                anchors.centerIn: parent
                text: root.hasWeather && root.weatherService.available ? root.weatherService.temperature : "--"
                color: root.hasWeather && root.weatherService.available ? root.theme.accent : root.theme.mutedText
                font.pixelSize: expanded ? 42 : 30
                font.bold: true
                font.family: root.theme.fontFamilyMono
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: expanded ? 12 : 8

            Text {
                Layout.fillWidth: true
                text: root.hasWeather ? (root.weatherService.location || "Weather") : "Weather"
                color: root.theme.primaryText
                font.pixelSize: expanded ? 28 : 18
                font.bold: true
                font.family: root.theme.fontFamilyMono
                elide: Text.ElideRight
            }

            Text {
                Layout.fillWidth: true
                text: root.hasWeather ? root.weatherService.condition : ""
                color: root.theme.bodyText
                font.pixelSize: expanded ? root.theme.fontLg : root.theme.fontMd
                font.family: root.theme.fontFamilyMono
                elide: Text.ElideRight
            }

            Text {
                Layout.fillWidth: true
                text: root.hasWeather ? root.weatherService.status : ""
                color: root.theme.mutedText
                font.pixelSize: root.theme.fontSm
                font.family: root.theme.fontFamilyMono
                elide: Text.ElideRight
            }

            Item {
                Layout.fillHeight: true
            }

            Rectangle {
                implicitWidth: 102
                implicitHeight: 32
                radius: 16
                color: root.theme.darkSurface
                border.width: 1
                border.color: root.theme.faintBorder

                Text {
                    anchors.centerIn: parent
                    text: "Refresh"
                    color: root.theme.bodyText
                    font.pixelSize: root.theme.fontSm
                    font.bold: true
                    font.family: root.theme.fontFamilyMono
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.refreshRequested()
                }
            }
        }
    }
}
