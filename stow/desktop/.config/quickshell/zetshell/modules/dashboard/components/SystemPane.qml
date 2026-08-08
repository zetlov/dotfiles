import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root

    property QtObject theme: null
    property QtObject updates: null
    property QtObject systemActions: null
    property string currentSelection: ""
    property var actionItems: []

    signal refreshUpdates()
    signal runAction(string actionId)
    signal hoverItem(string itemId)

    readonly property bool hasTheme: theme !== null
    readonly property bool hasUpdates: updates !== null
    readonly property bool hasSystemActions: systemActions !== null

    radius: 20
    color: hasTheme ? theme.cardColor : "transparent"
    border.width: 1
    border.color: hasTheme ? theme.faintBorder : "transparent"
    clip: true

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 22
        spacing: 14

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 114
            radius: 18
            color: root.theme.darkSurface
            border.width: 1
            border.color: root.currentSelection === "system-refresh" ? root.theme.attentionBorder : root.theme.faintBorder

            RowLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 14

                Rectangle {
                    implicitWidth: 58
                    implicitHeight: 58
                    radius: 20
                    color: Qt.alpha(root.hasUpdates && root.updates.hasUpdates ? root.theme.accentWarm : root.theme.accent, 0.16)
                    border.width: 1
                    border.color: Qt.alpha(root.hasUpdates && root.updates.hasUpdates ? root.theme.accentWarm : root.theme.accent, 0.5)

                    Text {
                        anchors.centerIn: parent
                        text: root.hasUpdates && root.updates.hasUpdates ? root.updates.text : "OK"
                        color: root.hasUpdates && root.updates.hasUpdates ? root.theme.accentWarm : root.theme.accent
                        font.pixelSize: root.hasUpdates && root.updates.hasUpdates ? 18 : 15
                        font.bold: true
                        font.family: root.theme.fontFamilyMono
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 3

                    Text {
                        Layout.fillWidth: true
                        text: root.hasUpdates && root.updates.hasUpdates ? `${root.updates.count} updates pending` : "System up to date"
                        color: root.theme.primaryText
                        font.pixelSize: 18
                        font.bold: true
                        font.family: root.theme.fontFamilyMono
                        elide: Text.ElideRight
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root.hasUpdates && root.updates.running ? "Checking updates..." : root.hasUpdates ? root.updates.summary : ""
                        color: root.hasUpdates && root.updates.hasUpdates ? root.theme.accentWarm : root.theme.mutedText
                        font.pixelSize: root.theme.fontSm
                        font.family: root.theme.fontFamilyMono
                        elide: Text.ElideRight
                    }
                }

                Rectangle {
                    implicitWidth: 104
                    implicitHeight: 36
                    radius: 18
                    color: root.currentSelection === "system-refresh" ? root.theme.attentionFill : root.theme.darkControl
                    border.width: 1
                    border.color: root.currentSelection === "system-refresh" ? root.theme.attentionBorder : root.theme.faintBorder

                    Text {
                        anchors.centerIn: parent
                        text: root.hasUpdates && root.updates.running ? "Working" : "Refresh"
                        color: root.theme.primaryText
                        font.pixelSize: root.theme.fontSm
                        font.bold: true
                        font.family: root.theme.fontFamilyMono
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.refreshUpdates()
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 54
            radius: 18
            color: "#12000000"
            border.width: 1
            border.color: root.hasSystemActions && root.systemActions.armedAction ? root.theme.attentionBorder : root.theme.faintBorder

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 10

                Text {
                    text: root.hasSystemActions && root.systemActions.armedAction ? "Confirm" : "Status"
                    color: root.hasSystemActions && root.systemActions.armedAction ? root.theme.accentWarm : root.theme.bodyText
                    font.pixelSize: root.theme.fontSm
                    font.bold: true
                    font.family: root.theme.fontFamilyMono
                }

                Text {
                    Layout.fillWidth: true
                    text: root.hasSystemActions && root.systemActions.armedAction
                        ? `Press Enter again to confirm ${root.systemActions.armedAction}.`
                        : root.hasSystemActions
                            ? root.systemActions.statusText
                            : ""
                    color: root.hasSystemActions && root.systemActions.armedAction ? root.theme.accentWarm : root.theme.mutedText
                    font.pixelSize: root.theme.fontSm
                    font.family: root.theme.fontFamilyMono
                    elide: Text.ElideRight
                }
            }
        }

        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: 2
            rowSpacing: 12
            columnSpacing: 12

            Repeater {
                model: root.actionItems

                delegate: Rectangle {
                    required property var modelData
                    required property int index

                    readonly property bool armed: root.hasSystemActions && root.systemActions.armedAction === modelData.id.substring("system-".length)
                    readonly property bool selected: root.currentSelection === modelData.id

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 96
                    radius: 18
                    color: selected ? Qt.alpha(root.theme.attentionFill, 0.28) : root.theme.cardColor
                    border.width: selected || armed ? 2 : 1
                    border.color: armed ? root.theme.accentWarm : selected ? modelData.tone : root.theme.cardBorder

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 7

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Rectangle {
                                implicitWidth: 10
                                implicitHeight: 10
                                radius: 5
                                color: armed ? root.theme.accentWarm : modelData.tone
                            }

                            Text {
                                Layout.fillWidth: true
                                text: modelData.title
                                color: root.theme.primaryText
                                font.pixelSize: root.theme.fontMd
                                font.bold: true
                                font.family: root.theme.fontFamilyMono
                                elide: Text.ElideRight
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: armed ? "Press again to confirm" : modelData.detail
                            color: armed ? root.theme.accentWarm : root.theme.mutedText
                            font.pixelSize: root.theme.fontSm
                            font.family: root.theme.fontFamilyMono
                            elide: Text.ElideRight
                        }

                        Text {
                            Layout.fillWidth: true
                            text: selected ? (armed ? "Enter confirms" : modelData.dangerous ? "Enter arms confirmation" : "Enter runs") : ""
                            color: modelData.dangerous ? root.theme.accentWarm : root.theme.bodyText
                            font.pixelSize: root.theme.fontXs
                            font.bold: true
                            font.family: root.theme.fontFamilyMono
                            elide: Text.ElideRight
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: root.hoverItem(modelData.id)
                        onClicked: root.runAction(modelData.id)
                    }
                }
            }
        }
    }
}
