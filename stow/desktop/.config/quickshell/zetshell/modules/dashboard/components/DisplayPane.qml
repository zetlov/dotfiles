import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root

    property QtObject theme: null
    property QtObject brightness: null
    property string currentSelection: ""

    signal setBrightness(int value)
    signal stepBrightness(int delta)
    signal refreshBrightness()

    readonly property bool hasTheme: theme !== null
    readonly property bool hasBrightness: brightness !== null

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
            implicitHeight: 150
            radius: 18
            color: root.theme.darkSurface
            border.width: 1
            border.color: root.currentSelection === "display-brightness" ? root.theme.attentionBorder : root.theme.faintBorder

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Text {
                            Layout.fillWidth: true
                            text: root.hasBrightness && root.brightness.available ? (root.brightness.deviceName || "Built-in panel") : "No backlight device"
                            color: root.theme.primaryText
                            font.pixelSize: 18
                            font.bold: true
                            font.family: root.theme.fontFamilyMono
                            elide: Text.ElideRight
                        }

                        Text {
                            Layout.fillWidth: true
                            text: root.hasBrightness && root.brightness.available ? root.brightness.text : "Brightness control unavailable"
                            color: root.hasBrightness && root.brightness.available ? root.theme.mutedText : root.theme.dangerText
                            font.pixelSize: root.theme.fontSm
                            font.family: root.theme.fontFamilyMono
                            elide: Text.ElideRight
                        }
                    }

                    Text {
                        text: root.hasBrightness && root.brightness.available ? `${root.brightness.level}%` : "--"
                        color: root.hasBrightness && root.brightness.available ? root.theme.accentWarm : root.theme.mutedText
                        font.pixelSize: 24
                        font.bold: true
                        font.family: root.theme.fontFamilyMono
                    }
                }

                SliderBar {
                    Layout.fillWidth: true
                    theme: root.theme
                    value: root.hasBrightness ? root.brightness.level : 0
                    accent: root.theme.accentWarm
                    selected: root.currentSelection === "display-brightness"
                    enabled: root.hasBrightness && root.brightness.available
                    onSetValue: value => root.setBrightness(value)
                }
            }
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 3
            rowSpacing: 10
            columnSpacing: 10

            DisplayButton {
                Layout.fillWidth: true
                theme: root.theme
                label: "Dimmer"
                selected: root.currentSelection === "display-down"
                enabled: root.hasBrightness && root.brightness.available
                onClicked: root.stepBrightness(-5)
            }

            DisplayButton {
                Layout.fillWidth: true
                theme: root.theme
                label: "Brighter"
                selected: root.currentSelection === "display-up"
                enabled: root.hasBrightness && root.brightness.available
                onClicked: root.stepBrightness(5)
            }

            DisplayButton {
                Layout.fillWidth: true
                theme: root.theme
                label: "Refresh"
                selected: root.currentSelection === "display-refresh"
                onClicked: root.refreshBrightness()
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 18
            color: "#12000000"
            border.width: 1
            border.color: root.theme.faintBorder

            Column {
                anchors.centerIn: parent
                spacing: 8

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.hasBrightness && root.brightness.available ? "Display controls ready" : "No backlight detected"
                    color: root.theme.primaryText
                    font.pixelSize: 16
                    font.bold: true
                    font.family: root.theme.fontFamilyMono
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.hasBrightness && root.brightness.available
                        ? "Use Left/Right on the brightness row or drag the slider"
                        : "brightnessctl did not expose a backlight device"
                    color: root.theme.mutedText
                    font.pixelSize: root.theme.fontSm
                    font.family: root.theme.fontFamilyMono
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }
    }

    component DisplayButton: Rectangle {
        property QtObject theme: null
        property string label: ""
        property bool selected: false
        readonly property bool hasTheme: theme !== null
        signal clicked

        implicitHeight: 40
        radius: 20
        color: hasTheme ? selected ? theme.attentionFill : enabled ? theme.darkControl : "#10ffffff" : "transparent"
        border.width: 1
        border.color: hasTheme ? selected ? theme.attentionBorder : theme.faintBorder : "transparent"

        Text {
            anchors.centerIn: parent
            text: parent.label
            color: parent.hasTheme ? parent.enabled ? parent.theme.primaryText : parent.theme.mutedText : "white"
            font.pixelSize: parent.hasTheme ? parent.theme.fontSm : 10
            font.bold: true
            font.family: parent.hasTheme ? parent.theme.fontFamilyMono : "monospace"
        }

        MouseArea {
            anchors.fill: parent
            enabled: parent.enabled
            cursorShape: parent.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: parent.clicked()
        }
    }

    component SliderBar: Item {
        property QtObject theme: null
        property int value: 0
        property color accent: theme ? theme.accent : "white"
        property bool selected: false
        readonly property bool hasTheme: theme !== null
        signal setValue(int value)

        implicitHeight: hasTheme ? Math.max(theme.sliderHandleSize + 6, 24) : 24

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: parent.hasTheme ? parent.theme.sliderHeight : 8
            radius: Math.round(height / 2)
            color: parent.hasTheme ? parent.theme.darkSurface : "transparent"
            border.width: 1
            border.color: parent.hasTheme ? parent.selected ? parent.theme.attentionBorder : parent.theme.faintBorder : "transparent"
        }

        Rectangle {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max((parent.hasTheme ? parent.theme.sliderHandleSize : 18) / 2, parent.width * Math.min(1, parent.value / 100))
            height: parent.hasTheme ? parent.theme.sliderHeight : 8
            radius: Math.round(height / 2)
            color: parent.enabled ? parent.accent : parent.hasTheme ? parent.theme.mutedText : "white"
        }

        Rectangle {
            x: Math.max(0, Math.min(parent.width - width, parent.width * Math.min(1, parent.value / 100) - width / 2))
            anchors.verticalCenter: parent.verticalCenter
            width: parent.hasTheme ? parent.theme.sliderHandleSize : 18
            height: width
            radius: Math.round(width / 2)
            color: parent.enabled && parent.hasTheme ? parent.theme.primaryText : parent.hasTheme ? parent.theme.mutedText : "white"
            border.width: 1
            border.color: parent.hasTheme ? parent.selected ? parent.theme.attentionBorder : parent.theme.workspaceActiveBorder : "transparent"
        }

        MouseArea {
            anchors.fill: parent
            enabled: parent.enabled
            cursorShape: parent.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor

            function updateValue(mouseX) {
                const ratio = Math.max(0, Math.min(1, mouseX / width));
                parent.setValue(Math.round(ratio * 100));
            }

            onPressed: mouse => updateValue(mouse.x)
            onPositionChanged: mouse => {
                if (pressed)
                    updateValue(mouse.x);
            }
        }
    }
}
