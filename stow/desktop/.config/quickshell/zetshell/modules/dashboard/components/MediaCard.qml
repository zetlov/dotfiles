import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root

    property QtObject theme: null
    property QtObject music: null
    property QtObject lyrics: null
    property bool expanded: false
    property string selectableId: ""
    property string currentSelection: ""
    property bool showLyrics: true
    property bool lyricsVisible: true
    readonly property bool selected: selectableId !== "" && currentSelection === selectableId

    signal previous()
    signal toggle()
    signal next()
    signal toggleLyrics()

    radius: 20
    color: theme ? theme.cardColor : "#1cffffff"
    border.width: selected ? 2 : 1
    border.color: selected ? theme.accent : theme.faintBorder
    clip: true

    GridLayout {
        anchors.fill: parent
        anchors.margins: root.expanded ? 28 : 18
        columns: root.expanded ? 2 : 1
        rowSpacing: root.expanded ? 18 : 10
        columnSpacing: root.expanded ? 28 : 16

        Rectangle {
            Layout.preferredWidth: root.expanded ? 260 : 142
            Layout.preferredHeight: width
            radius: root.expanded ? 34 : 22
            color: root.theme.darkSurface
            border.width: 1
            border.color: root.theme.faintBorder
            clip: true

            Canvas {
                id: mediaProgress

                anchors.fill: parent
                anchors.margins: -10
                visible: root.expanded

                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();

                    const size = Math.min(width, height);
                    const center = size / 2;
                    const radius = center - 8;
                    ctx.lineWidth = 6;
                    ctx.lineCap = "round";

                    ctx.beginPath();
                    ctx.strokeStyle = root.theme.faintBorder;
                    ctx.arc(center, center, radius, -Math.PI / 2, Math.PI * 1.5);
                    ctx.stroke();

                    ctx.beginPath();
                    ctx.strokeStyle = root.theme.accent;
                    ctx.arc(center, center, radius, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * root.music.progress);
                    ctx.stroke();
                }

                Connections {
                    target: root.music

                    function onProgressChanged() {
                        mediaProgress.requestPaint();
                    }

                    function onHasPlayerChanged() {
                        mediaProgress.requestPaint();
                    }
                }
            }

            Image {
                anchors.fill: parent
                source: root.music.artUrl
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                visible: root.music.artUrl !== ""
                sourceSize.width: 256
                sourceSize.height: 256
            }

            Text {
                anchors.centerIn: parent
                text: "MEDIA"
                color: root.theme.mutedText
                font.pixelSize: root.theme.fontSm
                font.bold: true
                font.family: root.theme.fontFamilyMono
                visible: root.music.artUrl === ""
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: root.expanded ? 14 : 9

            Text {
                Layout.fillWidth: true
                text: root.music.hasPlayer ? root.music.title : "No media"
                color: root.theme.primaryText
                font.pixelSize: root.expanded ? 28 : 17
                font.bold: true
                font.family: root.theme.fontFamilyMono
                elide: Text.ElideRight
            }

            Text {
                Layout.fillWidth: true
                text: root.music.hasPlayer ? root.music.artist : "Start a player to show controls here"
                color: root.theme.mutedText
                font.pixelSize: root.expanded ? root.theme.fontLg : root.theme.fontMd
                font.family: root.theme.fontFamilyMono
                elide: Text.ElideRight
            }

            Text {
                Layout.fillWidth: true
                text: root.music.hasPlayer ? root.music.album : ""
                color: root.theme.bodyText
                font.pixelSize: root.expanded ? root.theme.fontMd : root.theme.fontSm
                font.family: root.theme.fontFamilyMono
                elide: Text.ElideRight
                visible: root.expanded && root.music.album !== ""
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 8
                radius: 4
                color: root.theme.darkSurface

                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: parent.width * root.music.progress
                    radius: 4
                    color: root.theme.accent
                }
            }

            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: root.music.currentText
                    color: root.theme.mutedText
                    font.pixelSize: root.theme.fontXs
                    font.family: root.theme.fontFamilyMono
                }

                Item {
                    Layout.fillWidth: true
                }

                Text {
                    text: root.music.totalText
                    color: root.theme.mutedText
                    font.pixelSize: root.theme.fontXs
                    font.family: root.theme.fontFamilyMono
                }
            }

            Row {
                spacing: 10

                MediaControlButton {
                    theme: root.theme
                    currentSelection: root.currentSelection
                    selectableId: "media-prev"
                    label: "Prev"
                    enabled: root.music.canGoPrevious
                    onClicked: root.previous()
                }

                MediaControlButton {
                    theme: root.theme
                    currentSelection: root.currentSelection
                    selectableId: "media-play"
                    label: root.music.isPlaying ? "Pause" : "Play"
                    enabled: root.music.canToggle
                    onClicked: root.toggle()
                }

                MediaControlButton {
                    theme: root.theme
                    currentSelection: root.currentSelection
                    selectableId: "media-next"
                    label: "Next"
                    enabled: root.music.canGoNext
                    onClicked: root.next()
                }
            }
        }

        Rectangle {
            Layout.columnSpan: root.expanded ? 2 : 1
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: root.expanded ? 150 : 0
            visible: root.expanded && root.lyricsVisible && root.showLyrics
            radius: 18
            color: root.theme.darkSurface
            border.width: root.currentSelection === "media-lyrics" ? 2 : 1
            border.color: root.currentSelection === "media-lyrics" ? root.theme.accent : root.theme.faintBorder

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 8

                Text {
                    text: "Lyrics"
                    color: root.theme.mutedText
                    font.pixelSize: root.theme.fontSm
                    font.bold: true
                    font.family: root.theme.fontFamilyMono
                }

                Text {
                    Layout.fillWidth: true
                    text: root.lyrics.currentLine
                    color: root.theme.accent
                    font.pixelSize: root.theme.fontLg
                    font.bold: true
                    font.family: root.theme.fontFamilyMono
                    elide: Text.ElideRight
                    visible: root.lyrics.currentLine !== ""
                }

                Flickable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentWidth: width
                    contentHeight: lyricsText.implicitHeight
                    clip: true

                    Text {
                        id: lyricsText

                        width: parent.width
                        text: root.music.hasPlayer ? root.lyrics.displayText : "No media"
                        color: root.theme.bodyText
                        font.pixelSize: root.theme.fontMd
                        font.family: root.theme.fontFamilyMono
                        wrapMode: Text.WordWrap
                        verticalAlignment: root.lyrics.hasLyrics ? Text.AlignTop : Text.AlignVCenter
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggleLyrics()
            }
        }
    }

    component MediaControlButton: TextButton {
        property string selectableId: ""
        property string currentSelection: ""

        border.width: currentSelection === selectableId ? 2 : 1
        border.color: hasTheme ? currentSelection === selectableId ? theme.accent : enabled ? theme.faintBorder : "transparent" : "transparent"
    }

    component TextButton: Rectangle {
        property QtObject theme: null
        property string label: ""
        readonly property bool hasTheme: theme !== null
        signal clicked

        implicitWidth: Math.max(42, buttonLabel.implicitWidth + 18)
        implicitHeight: 32
        radius: 16
        color: hasTheme ? enabled ? theme.darkSurface : Qt.alpha(theme.darkSurface, 0.45) : "transparent"
        border.width: 1
        border.color: hasTheme && enabled ? theme.faintBorder : "transparent"

        Text {
            id: buttonLabel

            anchors.centerIn: parent
            text: label
            color: buttonLabel.parent.hasTheme ? enabled ? theme.bodyText : theme.mutedText : "white"
            font.pixelSize: buttonLabel.parent.hasTheme ? theme.fontSm : 10
            font.bold: true
            font.family: buttonLabel.parent.hasTheme ? theme.fontFamilyMono : "monospace"
        }

        MouseArea {
            anchors.fill: parent
            enabled: parent.enabled
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.clicked()
        }
    }
}
