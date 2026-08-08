import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "." as DashboardComponents

Item {
    id: root

    property QtObject theme: null
    property QtObject clockService: null
    property QtObject infoService: null
    property QtObject weatherService: null
    property QtObject statsService: null
    property QtObject musicService: null
    property QtObject lyricsService: null
    property QtObject config: null
    property date calendarDate: new Date()
    property string currentSelection: ""
    property bool lyricsVisible: false

    signal toggleLyrics()
    signal changeCalendarMonth(int delta)

    readonly property bool showWeather: !config || config.showWeather
    readonly property bool showMedia: !config || config.showMedia
    readonly property bool showLyrics: !config || config.showLyrics

    GridLayout {
        anchors.fill: parent
        columns: 6
        rowSpacing: 14
        columnSpacing: 14

        UserCard {
            Layout.columnSpan: 3
            Layout.fillWidth: true
            Layout.fillHeight: true
            selectableId: "user"
        }

        InfoCard {
            Layout.columnSpan: 3
            Layout.fillWidth: true
            Layout.fillHeight: true
            selectableId: "time"
            title: "Time"
            value: root.clockService.timeText.slice(0, 5)
            detail: root.clockService.dateText
            accent: root.theme.accent
        }

        CalendarCard {
            Layout.columnSpan: 2
            Layout.fillWidth: true
            Layout.fillHeight: true
            selectableId: "calendar"
        }

        ResourceCard {
            Layout.columnSpan: 2
            Layout.fillWidth: true
            Layout.fillHeight: true
            selectableId: "resources"
        }

        DashboardComponents.WeatherCard {
            Layout.columnSpan: 2
            Layout.fillWidth: true
            Layout.fillHeight: true
            selectableId: "weather"
            theme: root.theme
            weatherService: root.weatherService
            currentSelection: root.currentSelection
            visible: root.showWeather
            onRefreshRequested: root.weatherService.refresh()
        }

        DashboardComponents.MediaCard {
            Layout.columnSpan: 6
            Layout.fillWidth: true
            Layout.fillHeight: true
            selectableId: "media"
            currentSelection: root.currentSelection
            theme: root.theme
            music: root.musicService
            lyrics: root.lyricsService
            showLyrics: root.showLyrics
            lyricsVisible: root.lyricsVisible
            visible: root.showMedia
            onPrevious: music.previous()
            onToggle: music.toggle()
            onNext: music.next()
            onToggleLyrics: root.toggleLyrics()
        }
    }

    component DashboardCard: Rectangle {
        property string title: ""
        property string selectableId: ""
        readonly property bool selected: selectableId !== "" && root.currentSelection === selectableId

        radius: 20
        color: root.theme.cardColor
        border.width: selected ? 2 : 1
        border.color: selected ? root.theme.accent : root.theme.faintBorder
        clip: true
    }

    component UserCard: DashboardCard {
        title: "User"

        RowLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 16

            Rectangle {
                    Layout.preferredWidth: 88
                    Layout.preferredHeight: 88
                    radius: 22
                    color: root.theme.darkSurface
                    border.width: 1
                    border.color: root.theme.faintBorder
                    clip: true

                Image {
                    anchors.fill: parent
                    source: root.infoService.faceUrl
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    visible: root.infoService.faceUrl !== ""
                    sourceSize.width: 256
                    sourceSize.height: 256
                }

                Text {
                    anchors.centerIn: parent
                    text: "USER"
                    color: root.theme.mutedText
                    font.pixelSize: root.theme.fontSm
                    font.bold: true
                    font.family: root.theme.fontFamilyMono
                    visible: root.infoService.faceUrl === ""
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    Layout.fillWidth: true
                    text: root.infoService.osName
                    color: root.theme.primaryText
                    font.pixelSize: root.theme.fontLg
                    font.bold: true
                    font.family: root.theme.fontFamilyMono
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    text: root.infoService.wmName
                    color: root.theme.bodyText
                    font.pixelSize: root.theme.fontMd
                    font.family: root.theme.fontFamilyMono
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    text: root.infoService.uptime ? `up ${root.infoService.uptime}` : "up ..."
                    color: root.theme.mutedText
                    font.pixelSize: root.theme.fontSm
                    font.family: root.theme.fontFamilyMono
                    elide: Text.ElideRight
                }
            }
        }
    }

    component InfoCard: DashboardCard {
        property string value: ""
        property string detail: ""
        property color accent: root.theme.accent

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 8

            Text {
                text: title
                color: root.theme.mutedText
                font.pixelSize: root.theme.fontSm
                font.bold: true
                font.family: root.theme.fontFamilyMono
            }

            Item {
                Layout.fillHeight: true
            }

            Text {
                text: value
                color: accent
                font.pixelSize: 44
                font.bold: true
                font.family: root.theme.fontFamilyMono
            }

            Text {
                Layout.fillWidth: true
                text: detail
                color: root.theme.bodyText
                font.pixelSize: root.theme.fontMd
                font.family: root.theme.fontFamilyMono
                elide: Text.ElideRight
            }
        }
    }

    component CalendarCard: DashboardCard {
        title: "Calendar"

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 8

            RowLayout {
                Layout.fillWidth: true

                TextButton {
                    label: "<"
                    onClicked: root.changeCalendarMonth(-1)
                }

                Text {
                    Layout.fillWidth: true
                    text: Qt.formatDateTime(root.calendarDate, "MMMM yyyy")
                    horizontalAlignment: Text.AlignHCenter
                    color: root.theme.primaryText
                    font.pixelSize: root.theme.fontLg
                    font.bold: true
                    font.family: root.theme.fontFamilyMono
                }

                TextButton {
                    label: ">"
                    onClicked: root.changeCalendarMonth(1)
                }
            }

            DayOfWeekRow {
                Layout.fillWidth: true
                locale: monthGrid.locale

                delegate: Text {
                    required property var model

                    text: model.shortName
                    color: root.theme.mutedText
                    horizontalAlignment: Text.AlignHCenter
                    font.pixelSize: root.theme.fontXs
                    font.bold: true
                    font.family: root.theme.fontFamilyMono
                }
            }

            MonthGrid {
                id: monthGrid

                Layout.fillWidth: true
                Layout.fillHeight: true
                month: root.calendarDate.getMonth()
                year: root.calendarDate.getFullYear()
                locale: Qt.locale()
                spacing: 3

                delegate: Rectangle {
                    required property var model

                    radius: 10
                    color: model.today ? root.theme.accent : "transparent"
                    opacity: model.month === monthGrid.month || model.today ? 1 : 0.35

                    Text {
                        anchors.centerIn: parent
                        text: model.day
                        color: model.today ? root.theme.workspaceActiveText : root.theme.bodyText
                        font.pixelSize: root.theme.fontSm
                        font.bold: model.today
                        font.family: root.theme.fontFamilyMono
                    }
                }
            }
        }
    }

    component ResourceCard: DashboardCard {
        title: "Resources"

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            Text {
                text: title
                color: root.theme.mutedText
                font.pixelSize: root.theme.fontSm
                font.bold: true
                font.family: root.theme.fontFamilyMono
            }

            Meter {
                Layout.fillWidth: true
                Layout.fillHeight: true
                label: "CPU"
                value: root.statsService.cpuPercent
                accent: root.theme.accent
            }

            Meter {
                Layout.fillWidth: true
                Layout.fillHeight: true
                label: "RAM"
                value: root.statsService.ramPercent
                accent: root.theme.accentWarm
            }

            Meter {
                Layout.fillWidth: true
                Layout.fillHeight: true
                label: "DISK"
                value: root.statsService.storagePercent
                accent: root.theme.brightText
            }
        }
    }

    component Meter: Item {
        property string label: ""
        property int value: 0
        property color accent: root.theme.accent

        implicitHeight: 96

        ColumnLayout {
            anchors.fill: parent
            spacing: 7

            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: label
                    color: root.theme.bodyText
                    font.pixelSize: root.theme.fontSm
                    font.bold: true
                    font.family: root.theme.fontFamilyMono
                }

                Item {
                    Layout.fillWidth: true
                }

                Text {
                    text: `${Math.max(0, Math.min(100, Math.round(value)))}%`
                    color: accent
                    font.pixelSize: root.theme.fontSm
                    font.bold: true
                    font.family: root.theme.fontFamilyMono
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 12
                color: root.theme.darkSurface

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: parent.height * Math.max(0, Math.min(1, value / 100))
                    radius: 12
                    color: accent
                }
            }
        }
    }

    component TextButton: Rectangle {
        property string label: ""
        signal clicked

        implicitWidth: Math.max(42, buttonLabel.implicitWidth + 18)
        implicitHeight: 32
        radius: 16
        color: enabled ? root.theme.darkSurface : Qt.alpha(root.theme.darkSurface, 0.45)
        border.width: 1
        border.color: enabled ? root.theme.faintBorder : "transparent"

        Text {
            id: buttonLabel

            anchors.centerIn: parent
            text: label
            color: enabled ? root.theme.bodyText : root.theme.mutedText
            font.pixelSize: root.theme.fontSm
            font.bold: true
            font.family: root.theme.fontFamilyMono
        }

        MouseArea {
            anchors.fill: parent
            enabled: parent.enabled
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.clicked()
        }
    }
}
