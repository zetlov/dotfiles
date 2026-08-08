import QtQuick
import QtQuick.Layouts
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

    implicitWidth: theme.notificationCenterWidth
    implicitHeight: theme.notificationCenterHeight

    WlrLayershell.namespace: "zetshell-notification-center"
    WlrLayershell.layer: WlrLayer.Overlay

    readonly property string screenName: screenNameHint
    readonly property bool isTargetMonitor: {
        if (!targetMonitor)
            return true;
        if (!screenName)
            return false;

        return screenName === targetMonitor;
    }

    visible: isTargetMonitor && notificationService && notificationService.centerOpen

    onVisibleChanged: {
        if (notificationService)
            notificationService.setCenterOpen(visible);
    }

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

    Rectangle {
        anchors.fill: parent
        anchors.topMargin: 10
        radius: theme.panelRadius
        color: theme.panelShadow
        opacity: 0.65
    }

    Rectangle {
        anchors.fill: parent
        radius: theme.panelRadius
        color: theme.notificationSurfaceAlt
        border.width: 1
        border.color: theme.softBorder

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                ColumnLayout {
                    spacing: -2

                    Text {
                        text: "Notifications"
                        color: theme.primaryText
                        font.pixelSize: 16
                        font.bold: true
                        font.family: theme.fontFamilyMono
                    }

                    Text {
                        text: notificationService && notificationService.hasUnread ? `${notificationService.unreadCount} unread` : "All caught up"
                        color: theme.mutedText
                        font.pixelSize: theme.fontSm
                    }
                }

                Rectangle {
                    implicitWidth: statusLabel.implicitWidth + 20
                    implicitHeight: theme.notificationActionHeight
                    radius: theme.notificationActionRadius
                    color: notificationService && notificationService.hasUnread ? theme.attentionFill : theme.darkControl
                    border.width: 1
                    border.color: notificationService && notificationService.hasUnread ? theme.attentionBorder : theme.faintBorder

                    Text {
                        id: statusLabel

                        anchors.centerIn: parent
                        text: notificationService && notificationService.hasUnread ? `${notificationService.unreadCount} unread` : "History"
                        color: theme.brightText
                        font.pixelSize: theme.fontSm
                        font.bold: true
                        font.family: theme.fontFamilyMono
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                Rectangle {
                    implicitWidth: 86
                    implicitHeight: theme.chipHeight
                    radius: theme.chipRadius
                    color: notificationService && notificationService.notifications.length > 0 ? theme.notificationSurface : "#cc111820"
                    border.width: 1
                    border.color: notificationService && notificationService.notifications.length > 0 ? theme.cardBorder : theme.faintBorder

                    Text {
                        anchors.centerIn: parent
                        text: "Clear"
                        color: notificationService && notificationService.notifications.length > 0 ? theme.brightText : theme.mutedText
                        font.pixelSize: theme.fontMd
                        font.bold: true
                        font.family: theme.fontFamilyMono
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (!notificationService || notificationService.notifications.length === 0)
                                return;

                            const ids = notificationService.notifications.map(entry => entry.id);
                            ids.forEach(id => notificationService.dismiss(id));
                        }
                    }
                }

                Rectangle {
                    implicitWidth: 40
                    implicitHeight: theme.chipHeight
                    radius: theme.chipRadius
                    color: theme.notificationSurface
                    border.width: 1
                    border.color: theme.softBorder

                    Text {
                        anchors.centerIn: parent
                        text: "×"
                        color: theme.brightText
                        font.pixelSize: 15
                        font.bold: true
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: notificationService.setCenterOpen(false)
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: theme.cardRadius
                color: "#12000000"
                border.width: 1
                border.color: "#18ffffff"

                Flickable {
                    anchors.fill: parent
                    anchors.margins: 8
                    contentWidth: width
                    contentHeight: historyColumn.implicitHeight
                    clip: true

                    Column {
                        id: historyColumn

                        width: parent.width
                        spacing: 8

                        Repeater {
                            model: notificationService ? notificationService.notifications : []

                            Rectangle {
                                id: entryCard

                                required property var modelData
                                readonly property var entry: modelData
                                property string inlineReplyText: ""

                                width: historyColumn.width
                                radius: theme.cardRadius
                                color: theme.notificationSurface
                                border.width: 1
                                border.color: entry.unread ? theme.attentionTint : theme.softBorder

                                implicitHeight: entryLayout.implicitHeight + 18

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    anchors.margins: 6
                                    width: 3
                                    radius: 2
                                    color: entry.unread ? theme.accentWarm : "transparent"
                                    visible: entry.unread
                                }

                                RowLayout {
                                    id: entryLayout

                                    anchors.fill: parent
                                    anchors.leftMargin: 14
                                    anchors.rightMargin: 9
                                    anchors.topMargin: 9
                                    anchors.bottomMargin: 9
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
                                            visible: entry.notification.body !== ""
                                        }

                                        Rectangle {
                                            Layout.fillWidth: true
                                            implicitHeight: theme.notificationPreviewHeight
                                            radius: 16
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

                                            Rectangle {
                                                anchors.left: parent.left
                                                anchors.right: parent.right
                                                anchors.bottom: parent.bottom
                                                implicitHeight: 28
                                                color: "#42000000"
                                                visible: entry.notification.summary !== ""

                                                Text {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    anchors.left: parent.left
                                                    anchors.leftMargin: 10
                                                    anchors.right: parent.right
                                                    anchors.rightMargin: 10
                                                    text: entry.notification.summary
                                                    color: theme.primaryText
                                                    font.pixelSize: theme.fontSm
                                                    font.family: theme.fontFamilyMono
                                                    elide: Text.ElideRight
                                                }
                                            }
                                        }

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 8
                                            visible: entry.notification.hasInlineReply

                                            Rectangle {
                                                Layout.fillWidth: true
                                                implicitHeight: theme.chipHeight
                                                radius: theme.chipRadius
                                                color: theme.darkSurface
                                                border.width: 1
                                                border.color: replyInput.activeFocus ? theme.attentionBorder : theme.faintBorder

                                                TextInput {
                                                    id: replyInput

                                                    anchors.fill: parent
                                                    anchors.leftMargin: 12
                                                    anchors.rightMargin: 12
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    clip: true
                                                    color: theme.primaryText
                                                    font.pixelSize: theme.fontMd
                                                    font.family: theme.fontFamilyMono
                                                    selectionColor: theme.attentionFill
                                                    selectedTextColor: theme.primaryText
                                                    text: entryCard.inlineReplyText
                                                    verticalAlignment: TextInput.AlignVCenter

                                                    onTextChanged: entryCard.inlineReplyText = text
                                                    Keys.onReturnPressed: {
                                                        if (!notificationService || text.trim() === "")
                                                            return;

                                                        notificationService.sendInlineReply(entry.id, text);
                                                        entryCard.inlineReplyText = "";
                                                    }
                                                }

                                                Text {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 12
                                                    anchors.rightMargin: 12
                                                    verticalAlignment: Text.AlignVCenter
                                                    text: entry.notification.inlineReplyPlaceholder || "Reply"
                                                    color: theme.mutedText
                                                    font.pixelSize: theme.fontMd
                                                    font.family: theme.fontFamilyMono
                                                    visible: replyInput.text === "" && !replyInput.activeFocus
                                                }
                                            }

                                            Rectangle {
                                                implicitWidth: 62
                                                implicitHeight: theme.chipHeight
                                                radius: theme.chipRadius
                                                color: inlineReplyText.trim() !== "" ? theme.attentionFill : theme.darkControl
                                                border.width: 1
                                                border.color: inlineReplyText.trim() !== "" ? theme.attentionBorder : theme.faintBorder

                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "Reply"
                                                    color: theme.brightText
                                                    font.pixelSize: theme.fontSm
                                                    font.bold: true
                                                    font.family: theme.fontFamilyMono
                                                }

                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        if (!notificationService || inlineReplyText.trim() === "")
                                                            return;

                                                        notificationService.sendInlineReply(entry.id, inlineReplyText);
                                                        inlineReplyText = "";
                                                    }
                                                }
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
                                            onClicked: notificationService.dismiss(entry.id)
                                        }
                                    }
                                }
                            }
                        }

                        Item {
                            width: historyColumn.width
                            height: 180
                            visible: notificationService && notificationService.notifications.length === 0

                            Column {
                                anchors.centerIn: parent
                                spacing: 6

                                Text {
                                    text: "No notifications"
                                    color: theme.primaryText
                                    font.pixelSize: 15
                                    font.bold: true
                                    font.family: theme.fontFamilyMono
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }

                                Text {
                                    text: "Incoming notifications will appear here."
                                    color: theme.mutedText
                                    font.pixelSize: theme.fontSm
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
