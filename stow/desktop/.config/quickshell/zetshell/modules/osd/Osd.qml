import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../.." as Shell

PanelWindow {
    id: root

    property string targetMonitor: ""
    property string screenNameHint: ""
    property QtObject osdService: null

    Shell.Theme {
        id: theme
    }

    readonly property string screenName: screenNameHint
    readonly property bool isTargetMonitor: {
        if (!targetMonitor)
            return true;
        if (!screenName)
            return false;
        return screenName === targetMonitor;
    }
    readonly property real shownProgress: osdService ? Math.min(1, Math.max(0, osdService.level / 100)) : 0

    color: "transparent"
    exclusiveZone: 0
    visible: isTargetMonitor && osdService && osdService.open

    anchors {
        bottom: true
        left: true
    }

    implicitWidth: 360
    implicitHeight: 106

    margins {
        bottom: 88
        left: Math.max(24, Math.round(((screen ? screen.width : 1920) - implicitWidth) / 2))
    }

    WlrLayershell.namespace: "zetshell-osd"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Rectangle {
        anchors.fill: panel
        anchors.topMargin: 7
        radius: panel.radius
        color: theme.panelShadow
        opacity: 0.72
    }

    Rectangle {
        id: panel

        anchors.fill: parent
        radius: 24
        color: theme.notificationSurfaceAlt
        border.width: 1
        border.color: osdService ? Qt.alpha(osdService.tone, 0.45) : theme.cardBorder

        RowLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 14

            Rectangle {
                Layout.preferredWidth: 52
                Layout.preferredHeight: 52
                radius: 18
                color: osdService && osdService.muted ? Qt.alpha(theme.dangerText, 0.18) : Qt.alpha(osdService ? osdService.tone : theme.accent, 0.16)
                border.width: 1
                border.color: osdService && osdService.muted ? Qt.alpha(theme.dangerText, 0.45) : Qt.alpha(osdService ? osdService.tone : theme.accent, 0.42)

                Text {
                    anchors.centerIn: parent
                    text: osdService ? osdService.icon : "OSD"
                    color: osdService && osdService.muted ? theme.dangerText : osdService ? osdService.tone : theme.accent
                    font.pixelSize: 12
                    font.bold: true
                    font.family: theme.fontFamilyMono
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 9

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                            Layout.fillWidth: true
                            text: osdService ? osdService.title : "OSD"
                            color: theme.primaryText
                            font.pixelSize: 15
                            font.bold: true
                            font.family: theme.fontFamilyMono
                            elide: Text.ElideRight
                        }

                        Text {
                            Layout.fillWidth: true
                            text: osdService ? osdService.detail : ""
                            color: theme.mutedText
                            font.pixelSize: theme.fontSm
                            font.family: theme.fontFamilyMono
                            elide: Text.ElideRight
                        }
                    }

                    Text {
                        text: osdService && osdService.muted ? "--" : `${osdService ? osdService.level : 0}%`
                        color: osdService && osdService.muted ? theme.dangerText : osdService ? osdService.tone : theme.accent
                        font.pixelSize: 18
                        font.bold: true
                        font.family: theme.fontFamilyMono
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 8
                    radius: 4
                    color: Qt.alpha(theme.darkSurface, 0.86)

                    Rectangle {
                        width: Math.max(parent.height, parent.width * root.shownProgress)
                        height: parent.height
                        radius: parent.radius
                        color: osdService && osdService.muted ? theme.dangerText : osdService ? osdService.tone : theme.accent

                        Behavior on width {
                            NumberAnimation {
                                duration: theme.animBase
                                easing.type: Easing.OutCubic
                            }
                        }
                    }
                }
            }
        }
    }
}
