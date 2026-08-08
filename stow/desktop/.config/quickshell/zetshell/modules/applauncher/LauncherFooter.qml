import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root

    required property QtObject palette
    required property QtObject launcherService

    Layout.fillWidth: true
    implicitHeight: 30
    radius: 0
    color: "transparent"
    border.width: 0

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 4
        anchors.rightMargin: 4
        spacing: 14

        Repeater {
            model: root.launcherService && root.launcherService.systemConfirmationPending ? [{
                "key": "Enter",
                "label": `Confirm ${root.launcherService.systemConfirmationAction}`
            }, {
                "key": "Esc",
                "label": "Cancel"
            }] : [{
                "key": "clip",
                "label": "Clipboard"
            }, {
                "key": "sys",
                "label": "System"
            }, {
                "key": "file",
                "label": "Files"
            }, {
                "key": "emo",
                "label": "Emoji"
            }, {
                "key": "Enter",
                "label": "Open"
            }, {
                "key": "Ctrl K",
                "label": "Actions"
            }, {
                "key": "Esc",
                "label": "Back"
            }]

            RowLayout {
                spacing: 8

                Rectangle {
                    implicitWidth: Math.max(38, chipText.implicitWidth + 16)
                    implicitHeight: 22
                    radius: 11
                    color: Qt.rgba(1, 1, 1, 0.04)
                    border.width: 1
                    border.color: root.palette.faintBorder

                    Text {
                        id: chipText

                        anchors.centerIn: parent
                        text: modelData.key
                        color: root.palette.primaryText
                        font.pixelSize: root.palette.fontXs
                        font.bold: true
                        font.family: root.palette.fontFamilyMono
                    }

                }

                Text {
                    text: modelData.label
                    color: root.palette.bodyText
                    font.pixelSize: root.palette.fontSm
                    font.family: root.palette.fontFamilyMono
                }

            }

        }

    }

}
