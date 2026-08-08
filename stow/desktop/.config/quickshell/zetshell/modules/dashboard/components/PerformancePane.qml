import QtQuick
import QtQuick.Layouts

GridLayout {
    id: root

    property QtObject theme: null
    property QtObject stats: null
    property string currentSelection: ""

    columns: 2
    rowSpacing: 14
    columnSpacing: 14

    function formatPercent(value) {
        return `${Math.max(0, Math.min(100, Math.round(value)))}%`;
    }

    GaugePanel {
        Layout.fillWidth: true
        Layout.fillHeight: true
        selectableId: "cpu"
        title: "CPU"
        subtitle: root.stats.cpuName || "Processor"
        value: root.stats.cpuPercent
        secondary: root.stats.cpuTemp > 0 ? `${Math.round(root.stats.cpuTemp)}°C` : ""
        accent: root.theme.accent
    }

    GaugePanel {
        Layout.fillWidth: true
        Layout.fillHeight: true
        selectableId: "memory"
        title: "Memory"
        subtitle: "System memory"
        value: root.stats.ramPercent
        accent: root.theme.accentWarm
    }

    GaugePanel {
        Layout.fillWidth: true
        Layout.fillHeight: true
        selectableId: "storage"
        title: "Storage"
        subtitle: "Root filesystem"
        value: root.stats.storagePercent
        accent: root.theme.brightText
    }

    NetworkPanel {
        Layout.fillWidth: true
        Layout.fillHeight: true
        selectableId: "network"
    }

    GaugePanel {
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: root.stats.hasGpu
        selectableId: "gpu"
        title: "GPU"
        subtitle: root.stats.gpuName || "Graphics"
        value: root.stats.gpuPercent
        secondary: root.stats.gpuTemp > 0 ? `${Math.round(root.stats.gpuTemp)}°C` : ""
        accent: root.theme.attentionTint
    }

    BatteryPanel {
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: root.stats.hasBattery
        selectableId: "battery"
    }

    component Card: Rectangle {
        property string title: ""
        property string selectableId: ""
        readonly property bool selected: selectableId !== "" && root.currentSelection === selectableId

        radius: 20
        color: root.theme.cardColor
        border.width: selected ? 2 : 1
        border.color: selected ? root.theme.accent : root.theme.faintBorder
        clip: true
    }

    component GaugePanel: Card {
        property int value: 0
        property color accent: root.theme.accent
        property string subtitle: ""
        property string secondary: ""

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 26
            spacing: 10

            Text {
                text: title
                color: root.theme.mutedText
                font.pixelSize: root.theme.fontLg
                font.bold: true
                font.family: root.theme.fontFamilyMono
            }

            Text {
                Layout.fillWidth: true
                text: subtitle
                color: root.theme.bodyText
                font.pixelSize: root.theme.fontSm
                font.family: root.theme.fontFamilyMono
                elide: Text.ElideRight
                visible: subtitle !== ""
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                Item {
                    id: gauge

                    anchors.centerIn: parent
                    width: Math.min(parent.width, parent.height)
                    height: width

                    Canvas {
                        id: gaugeCanvas

                        anchors.fill: parent
                        antialiasing: true

                        readonly property real clampedValue: Math.max(0, Math.min(100, value))

                        onClampedValueChanged: requestPaint()
                        onWidthChanged: requestPaint()
                        onHeightChanged: requestPaint()
                        onPaint: {
                            const ctx = getContext("2d");
                            const size = Math.min(width, height);
                            const center = size / 2;
                            const line = Math.max(8, Math.round(size * 0.085));
                            const radius = Math.max(1, center - line / 2 - 2);
                            const start = -Math.PI / 2;
                            const end = start + Math.PI * 2 * clampedValue / 100;

                            ctx.reset();
                            ctx.clearRect(0, 0, width, height);
                            ctx.lineCap = "round";
                            ctx.lineWidth = line;
                            ctx.beginPath();
                            ctx.strokeStyle = root.theme.faintBorder;
                            ctx.arc(width / 2, height / 2, radius, 0, Math.PI * 2);
                            ctx.stroke();

                            if (clampedValue > 0) {
                                ctx.beginPath();
                                ctx.strokeStyle = accent;
                                ctx.arc(width / 2, height / 2, radius, start, end);
                                ctx.stroke();
                            }
                        }
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width * 0.68
                        height: width
                        radius: width / 2
                        color: Qt.alpha(accent, value / 220)
                        border.width: 1
                        border.color: accent

                        Text {
                            anchors.centerIn: parent
                            text: root.formatPercent(value)
                            color: accent
                            font.pixelSize: 36
                            font.bold: true
                            font.family: root.theme.fontFamilyMono
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                text: secondary
                color: accent
                font.pixelSize: root.theme.fontLg
                font.bold: true
                font.family: root.theme.fontFamilyMono
                horizontalAlignment: Text.AlignHCenter
                visible: secondary !== ""
            }
        }
    }

    component BatteryPanel: Card {
        title: "Battery"

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 26
            spacing: 12

            Text {
                text: title
                color: root.theme.mutedText
                font.pixelSize: root.theme.fontLg
                font.bold: true
                font.family: root.theme.fontFamilyMono
            }

            Text {
                Layout.fillWidth: true
                text: root.stats.batteryStatus
                color: root.theme.bodyText
                font.pixelSize: root.theme.fontSm
                font.family: root.theme.fontFamilyMono
                elide: Text.ElideRight
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 22
                color: root.theme.darkSurface
                border.width: 1
                border.color: root.theme.faintBorder
                clip: true

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: parent.height * Math.max(0, Math.min(1, root.stats.batteryPercent / 100))
                    color: Qt.alpha(root.theme.accent, 0.5)
                }

                Text {
                    anchors.centerIn: parent
                    text: root.formatPercent(root.stats.batteryPercent)
                    color: root.theme.primaryText
                    font.pixelSize: 36
                    font.bold: true
                    font.family: root.theme.fontFamilyMono
                }
            }

            Text {
                Layout.fillWidth: true
                text: root.stats.batteryTime
                color: root.theme.mutedText
                font.pixelSize: root.theme.fontSm
                font.family: root.theme.fontFamilyMono
                horizontalAlignment: Text.AlignHCenter
                visible: root.stats.batteryTime !== ""
            }
        }
    }

    component NetworkPanel: Card {
        title: "Network"

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 8

            Text {
                text: title
                color: root.theme.mutedText
                font.pixelSize: root.theme.fontLg
                font.bold: true
                font.family: root.theme.fontFamilyMono
            }

            NetworkSpeedRow {
                Layout.fillWidth: true
                label: "Download"
                value: root.stats.downloadText
                accent: root.theme.accent
            }

            NetworkSpeedRow {
                Layout.fillWidth: true
                label: "Upload"
                value: root.stats.uploadText
                accent: root.theme.accentWarm
            }

            NetworkSpeedRow {
                Layout.fillWidth: true
                label: "Session"
                value: `↓ ${root.stats.downloadTotalText}   ↑ ${root.stats.uploadTotalText}`
                accent: root.theme.bodyText
            }
        }
    }

    component NetworkSpeedRow: Rectangle {
        property string label: ""
        property string value: ""
        property color accent: root.theme.accent

        implicitHeight: 50
        radius: 18
        color: root.theme.darkSurface
        border.width: 1
        border.color: root.theme.faintBorder

        RowLayout {
            anchors.fill: parent
            anchors.margins: 12

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                Text {
                    Layout.fillWidth: true
                    text: label
                    color: root.theme.mutedText
                    font.pixelSize: root.theme.fontSm
                    font.bold: true
                    font.family: root.theme.fontFamilyMono
                }

                Text {
                    Layout.fillWidth: true
                    text: value
                    color: accent
                    font.pixelSize: 18
                    font.bold: true
                    font.family: root.theme.fontFamilyMono
                    elide: Text.ElideRight
                }
            }
        }
    }
}
