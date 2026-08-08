import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root

    required property QtObject launcherService
    required property QtObject palette
    readonly property string typeLabel: launcherService ? launcherService.resultTypeLabel(launcherService.selectedResult) : ""

    visible: launcherService.actionPanelOpen && launcherService.selectedResult
    radius: palette.cardRadius
    color: Qt.rgba(0.07, 0.09, 0.12, 0.96)
    border.width: 1
    border.color: palette.attentionBorder

    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        color: "transparent"
        border.width: 0
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 10

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6

            Rectangle {
                implicitWidth: Math.max(56, actionTypeText.implicitWidth + 18)
                implicitHeight: 22
                radius: 11
                color: Qt.alpha(root.palette.accent, 0.18)
                border.width: 1
                border.color: Qt.alpha(root.palette.accent, 0.42)

                Text {
                    id: actionTypeText

                    anchors.centerIn: parent
                    text: root.typeLabel
                    color: root.palette.primaryText
                    font.pixelSize: root.palette.fontXs
                    font.bold: true
                    font.family: root.palette.fontFamilyMono
                }

            }

            Text {
                Layout.fillWidth: true
                text: launcherService.selectedResult ? launcherService.selectedResult.title : "Actions"
                color: root.palette.primaryText
                font.pixelSize: root.palette.fontMd
                font.bold: true
                font.family: root.palette.fontFamilyMono
                elide: Text.ElideRight
            }

            Text {
                Layout.fillWidth: true
                text: launcherService.selectedResult ? launcherService.selectedResult.subtitle || "Actions" : "Actions"
                color: root.palette.mutedText
                font.pixelSize: root.palette.fontSm
                font.family: root.palette.fontFamilyMono
                elide: Text.ElideRight
            }

        }

        ListView {
            id: actionsList

            Layout.fillWidth: true
            Layout.fillHeight: true
            model: launcherService.selectedActions
            currentIndex: launcherService.selectedActionIndex
            spacing: 6
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
                required property var modelData
                required property int index

                width: actionsList.width
                implicitHeight: index === 0 ? 52 : 46
                radius: root.palette.cardRadius - 6
                color: launcherService.selectedActionIndex === index ? Qt.alpha(root.palette.accent, 0.14) : Qt.rgba(1, 1, 1, 0.03)
                border.width: 1
                border.color: launcherService.selectedActionIndex === index ? root.palette.attentionBorder : root.palette.faintBorder

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 10

                    Text {
                        Layout.fillWidth: true
                        text: modelData.title || modelData.id || ""
                        color: root.palette.primaryText
                        font.pixelSize: root.palette.fontMd
                        font.bold: launcherService.selectedActionIndex === index || index === 0
                        font.family: root.palette.fontFamilyMono
                        elide: Text.ElideRight
                    }

                    Text {
                        text: modelData.shortcut || (launcherService.selectedActionIndex === index ? "Enter" : "")
                        color: launcherService.selectedActionIndex === index ? root.palette.primaryText : root.palette.mutedText
                        font.pixelSize: root.palette.fontSm
                        font.bold: launcherService.selectedActionIndex === index
                        font.family: root.palette.fontFamilyMono
                    }

                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: launcherService.selectedActionIndex = index
                    onClicked: {
                        launcherService.selectedActionIndex = index;
                        launcherService.runSelectedAction();
                    }
                }

            }

        }

    }

}
