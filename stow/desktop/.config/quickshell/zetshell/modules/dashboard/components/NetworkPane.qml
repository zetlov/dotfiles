import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root

    property QtObject theme: null
    property QtObject network: null
    property string currentSelection: ""

    signal toggleWifi()
    signal refreshNetwork()
    signal disconnectCurrent()
    signal openSettings()
    signal selectNetwork(var network)
    signal requestPasswordPrompt(string ssid)
    signal hoverItem(string itemId)

    readonly property bool hasTheme: theme !== null
    readonly property bool hasNetwork: network !== null

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
                    text: root.hasNetwork ? root.network.text : "Network"
                    color: root.theme.primaryText
                    font.pixelSize: 18
                    font.bold: true
                    font.family: root.theme.fontFamilyMono
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    text: root.hasNetwork ? root.network.statusText : ""
                    color: root.hasNetwork && root.network.actionError ? root.theme.dangerText : root.theme.mutedText
                    font.pixelSize: root.theme.fontSm
                    font.family: root.theme.fontFamilyMono
                    elide: Text.ElideRight
                }
            }

            NetworkChip {
                label: root.hasNetwork && root.network.wifiEnabled ? "Wi-Fi On" : "Wi-Fi Off"
                selected: root.currentSelection === "network-toggle"
                onClicked: root.toggleWifi()
            }

            NetworkChip {
                label: root.hasNetwork && root.network.busy ? "Working" : "Refresh"
                selected: root.currentSelection === "network-refresh"
                onClicked: root.refreshNetwork()
            }

            NetworkChip {
                label: "Settings"
                selected: root.currentSelection === "network-open"
                onClicked: root.openSettings()
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 76
            radius: 18
            color: root.theme.darkSurface
            border.width: 1
            border.color: root.currentSelection === "network-disconnect" ? root.theme.attentionBorder : root.theme.faintBorder

            RowLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 12

                Rectangle {
                    implicitWidth: 10
                    implicitHeight: 10
                    radius: 5
                    color: root.hasNetwork ? root.network.tone : root.theme.mutedText
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: -1

                    Text {
                        Layout.fillWidth: true
                        text: root.hasNetwork && root.network.connected ? root.network.label : "No active connection"
                        color: root.theme.primaryText
                        font.pixelSize: root.theme.fontMd
                        font.bold: true
                        font.family: root.theme.fontFamilyMono
                        elide: Text.ElideRight
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root.hasNetwork && root.network.connected
                            ? (root.network.deviceName || root.network.connectionName || root.network.statusText)
                            : root.hasNetwork
                                ? root.network.statusText
                                : ""
                        color: root.theme.mutedText
                        font.pixelSize: root.theme.fontSm
                        font.family: root.theme.fontFamilyMono
                        elide: Text.ElideRight
                    }
                }

                Rectangle {
                    implicitWidth: 112
                    implicitHeight: 34
                    radius: 17
                    visible: root.hasNetwork && root.network.connected
                    color: root.currentSelection === "network-disconnect" ? root.theme.attentionFill : root.theme.darkControl
                    border.width: 1
                    border.color: root.currentSelection === "network-disconnect" ? root.theme.attentionBorder : root.theme.faintBorder

                    Text {
                        anchors.centerIn: parent
                        text: "Disconnect"
                        color: root.theme.primaryText
                        font.pixelSize: root.theme.fontSm
                        font.bold: true
                        font.family: root.theme.fontFamilyMono
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.disconnectCurrent()
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 18
            color: "#12000000"
            border.width: 1
            border.color: root.theme.faintBorder

            Flickable {
                anchors.fill: parent
                anchors.margins: 8
                contentWidth: width
                contentHeight: wifiColumn.implicitHeight
                clip: true

                Column {
                    id: wifiColumn

                    width: parent.width
                    spacing: 8

                    Repeater {
                        model: root.hasNetwork ? root.network.networks : []

                        Rectangle {
                            required property var modelData
                            required property int index

                            readonly property string itemId: `network-wifi-${index}`
                            readonly property bool current: modelData.active
                            readonly property bool selected: root.currentSelection === itemId

                            width: wifiColumn.width
                            implicitHeight: 64
                            radius: 18
                            color: selected ? Qt.alpha(root.theme.attentionFill, 0.28) : root.theme.cardColor
                            border.width: selected ? 2 : 1
                            border.color: selected || current ? root.theme.attentionBorder : root.theme.cardBorder

                            Rectangle {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                anchors.margins: 6
                                width: 4
                                radius: 2
                                color: selected ? root.theme.accentWarm : "transparent"
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 16
                                anchors.rightMargin: 12
                                anchors.topMargin: 12
                                anchors.bottomMargin: 12
                                spacing: 10

                                Rectangle {
                                    implicitWidth: 10
                                    implicitHeight: 10
                                    radius: 5
                                    color: current ? root.theme.accentWarm : modelData.signal >= 70 ? root.theme.accent : root.theme.mutedText
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: -2

                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.ssid || "Hidden network"
                                        color: root.theme.primaryText
                                        font.pixelSize: root.theme.fontMd
                                        font.bold: true
                                        font.family: root.theme.fontFamilyMono
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: current
                                            ? "Connected"
                                            : modelData.known
                                                ? "Saved network"
                                                : modelData.connectable
                                                    ? "Open network"
                                                    : "Password required"
                                        color: root.theme.mutedText
                                        font.pixelSize: root.theme.fontSm
                                        font.family: root.theme.fontFamilyMono
                                        elide: Text.ElideRight
                                    }
                                }

                                ColumnLayout {
                                    spacing: -2

                                    Text {
                                        text: selected ? "Enter" : `${modelData.signal}%`
                                        color: selected ? root.theme.accentWarm : root.theme.bodyText
                                        font.pixelSize: root.theme.fontSm
                                        font.bold: selected
                                        font.family: root.theme.fontFamilyMono
                                        horizontalAlignment: Text.AlignRight
                                    }

                                    Text {
                                        text: modelData.security || "--"
                                        color: root.theme.mutedText
                                        font.pixelSize: root.theme.fontXs
                                        font.family: root.theme.fontFamilyMono
                                        horizontalAlignment: Text.AlignRight
                                    }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                hoverEnabled: true
                                onEntered: root.hoverItem(itemId)
                                onClicked: {
                                    root.hoverItem(itemId);
                                    root.selectNetwork(modelData);
                                }
                            }
                        }
                    }

                    Item {
                        width: wifiColumn.width
                        height: 150
                        visible: !root.hasNetwork || root.network.networks.length === 0

                        Column {
                            anchors.centerIn: parent
                            spacing: 6

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: root.hasNetwork && root.network.wifiEnabled ? "No networks found" : "Wi-Fi is turned off"
                                color: root.theme.primaryText
                                font.pixelSize: root.theme.fontMd
                                font.bold: true
                                font.family: root.theme.fontFamilyMono
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: root.hasNetwork && root.network.wifiEnabled ? "Refresh to scan again" : "Turn Wi-Fi on to scan"
                                color: root.theme.mutedText
                                font.pixelSize: root.theme.fontSm
                                font.family: root.theme.fontFamilyMono
                            }
                        }
                    }
                }
            }
        }
    }

    component NetworkChip: Rectangle {
        property string label: ""
        property bool selected: false
        signal clicked

        implicitWidth: labelText.implicitWidth + 28
        implicitHeight: 36
        radius: 18
        color: selected ? root.theme.attentionFill : root.theme.darkControl
        border.width: 1
        border.color: selected ? root.theme.attentionBorder : root.theme.faintBorder

        Text {
            id: labelText

            anchors.centerIn: parent
            text: parent.label
            color: root.theme.primaryText
            font.pixelSize: root.theme.fontSm
            font.bold: true
            font.family: root.theme.fontFamilyMono
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.clicked()
        }
    }
}
