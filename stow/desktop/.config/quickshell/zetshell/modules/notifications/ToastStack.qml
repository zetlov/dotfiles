import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Notifications
import Quickshell.Wayland
import Quickshell.Widgets
import "../.." as Shell

PanelWindow {
    id: root

    property string targetMonitor: ""
    property string screenNameHint: ""
    property QtObject notificationService: null

    Shell.Theme {
        id: theme
    }

    color: "transparent"
    exclusiveZone: 0

    anchors {
        top: true
        right: true
    }

    margins {
        top: theme.panelMarginTop + theme.panelHeight + 18
        right: theme.panelMarginX
    }

    implicitWidth: theme.toastWidth
    implicitHeight: toastColumn.implicitHeight

    WlrLayershell.namespace: "zetshell-notifications"
    WlrLayershell.layer: WlrLayer.Overlay

    readonly property string screenName: screenNameHint
    readonly property bool isTargetMonitor: {
        if (!targetMonitor)
            return true;
        if (!screenName)
            return false;

        return screenName === targetMonitor;
    }

    visible: isTargetMonitor && notificationService && notificationService.toasts.length > 0

    function iconSource(icon) {
        if (!icon)
            return "";

        if (icon.startsWith("/") || icon.includes("://"))
            return icon;

        return Quickshell.iconPath(icon);
    }

    function imageSource(image) {
        if (!image)
            return "";

        if (image.startsWith("/") || image.includes("://"))
            return image;

        return `file://${image}`;
    }

    Column {
        id: toastColumn

        width: root.implicitWidth
        spacing: theme.toastGap

        Repeater {
            model: notificationService ? notificationService.toasts : []

            Rectangle {
                required property var modelData
                readonly property var entry: modelData

                width: toastColumn.width
                radius: theme.cardRadius
                color: entry.notification.urgency === NotificationUrgency.Critical ? theme.notificationSurfaceAlt : theme.notificationSurface
                border.width: 1
                border.color: entry.notification.urgency === NotificationUrgency.Critical ? theme.accentWarm : theme.softBorder

                implicitHeight: toastLayout.implicitHeight + 18

                Rectangle {
                    anchors.fill: parent
                    anchors.topMargin: 6
                    radius: parent.radius
                    color: theme.panelShadow
                    opacity: 0.75
                    z: -1
                }

                RowLayout {
                    id: toastLayout

                    anchors.fill: parent
                    anchors.margins: 9
                    spacing: 10

                    Rectangle {
                        Layout.alignment: Qt.AlignTop
                        implicitWidth: 34
                        implicitHeight: 34
                        radius: 17
                        color: theme.darkSurface
                        border.width: 1
                        border.color: theme.subtleLine

                        IconImage {
                            anchors.centerIn: parent
                            implicitSize: 18
                            source: root.iconSource(entry.notification.appIcon)
                            asynchronous: true
                            visible: entry.notification.appIcon !== ""
                        }

                        Text {
                            anchors.centerIn: parent
                            text: "•"
                            color: entry.notification.urgency === NotificationUrgency.Critical ? theme.accentWarm : theme.accent
                            font.pixelSize: 22
                            visible: entry.notification.appIcon === ""
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 5

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                Layout.fillWidth: true
                                text: entry.notification.summary || entry.notification.appName || "Notification"
                                color: theme.titleText
                                font.pixelSize: theme.fontMd
                                font.bold: true
                                font.family: theme.fontFamilyMono
                                elide: Text.ElideRight
                            }

                            Text {
                                text: entry.notification.appName
                                color: theme.mutedText
                                font.pixelSize: theme.fontSm
                                font.family: theme.fontFamilyMono
                                elide: Text.ElideRight
                                visible: text !== ""
                            }

                            Text {
                                text: notificationService ? notificationService.formatTimestamp(entry.timestamp) : ""
                                color: theme.mutedText
                                font.pixelSize: theme.fontSm
                                font.family: theme.fontFamilyMono
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: entry.notification.body
                            color: theme.bodyText
                            font.pixelSize: theme.fontSm
                            wrapMode: Text.Wrap
                            maximumLineCount: 4
                            elide: Text.ElideRight
                            visible: entry.notification.body !== ""
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: theme.notificationToastPreviewHeight
                            radius: 14
                            color: theme.darkSurface
                            border.width: 1
                            border.color: theme.faintBorder
                            visible: entry.notification.image !== ""
                            clip: true

                            Image {
                                anchors.fill: parent
                                source: root.imageSource(entry.notification.image)
                                asynchronous: true
                                cache: false
                                fillMode: Image.PreserveAspectCrop
                            }
                        }

                        Flow {
                            Layout.fillWidth: true
                            spacing: 6
                            visible: entry.notification.actions.length > 0

                            Repeater {
                                model: entry.notification.actions

                                Rectangle {
                                    required property var modelData

                                    implicitWidth: actionText.implicitWidth + 22
                                    implicitHeight: theme.notificationActionHeight
                                    radius: theme.notificationActionRadius
                                    color: theme.darkControl
                                    border.width: 1
                                    border.color: theme.faintBorder

                                    Text {
                                        id: actionText

                                        anchors.centerIn: parent
                                        text: modelData.text || "Open"
                                        color: theme.brightText
                                        font.pixelSize: theme.fontSm
                                        font.bold: true
                                        font.family: theme.fontFamilyMono
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: notificationService.invokeAction(entry.id, modelData.identifier)
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.alignment: Qt.AlignTop
                        implicitWidth: 24
                        implicitHeight: 24
                        radius: 12
                        color: theme.darkControl
                        border.width: 1
                        border.color: theme.faintBorder

                        Text {
                            anchors.centerIn: parent
                            text: "×"
                            color: theme.brightText
                            font.pixelSize: theme.fontMd
                            font.bold: true
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: notificationService.dismissToast(entry.id)
                        }
                    }
                }
            }
        }
    }
}
