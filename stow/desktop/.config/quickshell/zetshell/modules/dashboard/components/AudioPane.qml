import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root

    property QtObject theme: null
    property QtObject volume: null
    property QtObject music: null
    property string currentSelection: ""

    signal setVolume(int value)
    signal toggleMute()
    signal toggleMedia()
    signal selectSink(var sink)
    signal hoverItem(string itemId)

    readonly property bool hasTheme: theme !== null
    readonly property bool hasVolume: volume !== null
    readonly property bool hasMusic: music !== null

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
            implicitHeight: 134
            radius: 18
            color: root.theme.darkSurface
            border.width: 1
            border.color: root.currentSelection === "audio-volume" ? root.theme.attentionBorder : root.theme.faintBorder

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
                            text: root.hasVolume ? root.volume.deviceName || "No output device" : "No output device"
                            color: root.theme.primaryText
                            font.pixelSize: 18
                            font.bold: true
                            font.family: root.theme.fontFamilyMono
                            elide: Text.ElideRight
                        }

                        Text {
                            Layout.fillWidth: true
                            text: root.hasVolume && root.volume.ready ? (root.volume.muted ? "Muted" : `${root.volume.level}%`) : "Audio unavailable"
                            color: root.hasVolume && root.volume.muted ? root.theme.dangerText : root.theme.mutedText
                            font.pixelSize: root.theme.fontSm
                            font.family: root.theme.fontFamilyMono
                            elide: Text.ElideRight
                        }
                    }

                    Rectangle {
                        implicitWidth: 92
                        implicitHeight: 36
                        radius: 18
                        color: root.currentSelection === "audio-mute" ? root.theme.attentionFill : root.theme.darkControl
                        border.width: 1
                        border.color: root.currentSelection === "audio-mute" ? root.theme.attentionBorder : root.theme.faintBorder

                        Text {
                            anchors.centerIn: parent
                            text: root.hasVolume && root.volume.muted ? "Unmute" : "Mute"
                            color: root.theme.primaryText
                            font.pixelSize: root.theme.fontSm
                            font.bold: true
                            font.family: root.theme.fontFamilyMono
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggleMute()
                        }
                    }
                }

                SliderBar {
                    Layout.fillWidth: true
                    theme: root.theme
                    value: root.hasVolume ? root.volume.level : 0
                    accent: root.hasVolume && root.volume.muted ? root.theme.dangerText : root.theme.accent
                    selected: root.currentSelection === "audio-volume"
                    enabled: root.hasVolume && root.volume.ready
                    onSetValue: value => root.setVolume(value)
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 86
            radius: 18
            color: root.theme.cardColor
            border.width: 1
            border.color: root.currentSelection === "audio-media" ? root.theme.attentionBorder : root.theme.cardBorder

            RowLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 12

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: -1

                    Text {
                        Layout.fillWidth: true
                        text: root.hasMusic && root.music.hasPlayer ? root.music.title : "No active player"
                        color: root.theme.primaryText
                        font.pixelSize: root.theme.fontMd
                        font.bold: true
                        font.family: root.theme.fontFamilyMono
                        elide: Text.ElideRight
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root.hasMusic && root.music.hasPlayer ? root.music.artist : "Start playback to control it here"
                        color: root.theme.mutedText
                        font.pixelSize: root.theme.fontSm
                        font.family: root.theme.fontFamilyMono
                        elide: Text.ElideRight
                    }
                }

                Rectangle {
                    implicitWidth: 92
                    implicitHeight: 36
                    radius: 18
                    color: root.hasMusic && root.music.hasPlayer ? root.theme.darkControl : "#10ffffff"
                    border.width: 1
                    border.color: root.currentSelection === "audio-media" && root.hasMusic && root.music.hasPlayer ? root.theme.attentionBorder : root.theme.faintBorder

                    Text {
                        anchors.centerIn: parent
                        text: root.hasMusic && root.music.hasPlayer ? (root.music.isPlaying ? "Pause" : "Play") : "--"
                        color: root.hasMusic && root.music.hasPlayer ? root.theme.primaryText : root.theme.mutedText
                        font.pixelSize: root.theme.fontSm
                        font.bold: true
                        font.family: root.theme.fontFamilyMono
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: root.hasMusic && root.music.hasPlayer
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: root.toggleMedia()
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
                contentHeight: sinkColumn.implicitHeight
                clip: true

                Column {
                    id: sinkColumn

                    width: parent.width
                    spacing: 8

                    Repeater {
                        model: root.hasVolume ? root.volume.sinks : []

                        Rectangle {
                            required property var modelData
                            required property int index

                            readonly property string itemId: `audio-sink-${index}`
                            readonly property bool selected: root.currentSelection === itemId
                            readonly property bool activeSink: root.hasVolume && root.volume.sink && root.volume.sink.id === modelData.id

                            width: sinkColumn.width
                            implicitHeight: 62
                            radius: 18
                            color: selected ? Qt.alpha(root.theme.attentionFill, 0.28) : root.theme.cardColor
                            border.width: selected || activeSink ? 2 : 1
                            border.color: selected || activeSink ? root.theme.attentionBorder : root.theme.cardBorder

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 14
                                spacing: 10

                                Rectangle {
                                    implicitWidth: 10
                                    implicitHeight: 10
                                    radius: 5
                                    color: activeSink ? root.theme.accentWarm : root.theme.mutedText
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: -2

                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.nickname || modelData.description || modelData.name || "Unknown sink"
                                        color: root.theme.primaryText
                                        font.pixelSize: root.theme.fontMd
                                        font.bold: true
                                        font.family: root.theme.fontFamilyMono
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: activeSink ? "Default output" : "Set as default"
                                        color: root.theme.mutedText
                                        font.pixelSize: root.theme.fontSm
                                        font.family: root.theme.fontFamilyMono
                                        elide: Text.ElideRight
                                    }
                                }

                                Text {
                                    text: selected ? "Enter" : `${Math.round((modelData.audio ? modelData.audio.volume : 0) * 100)}%`
                                    color: selected ? root.theme.accentWarm : root.theme.bodyText
                                    font.pixelSize: root.theme.fontSm
                                    font.bold: selected
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
                                    root.selectSink(modelData);
                                }
                            }
                        }
                    }

                    Item {
                        width: sinkColumn.width
                        height: 130
                        visible: !root.hasVolume || root.volume.sinks.length === 0

                        Column {
                            anchors.centerIn: parent
                            spacing: 6

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "No audio sinks"
                                color: root.theme.primaryText
                                font.pixelSize: root.theme.fontMd
                                font.bold: true
                                font.family: root.theme.fontFamilyMono
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "PipeWire outputs will appear here"
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
