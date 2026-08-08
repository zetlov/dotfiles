import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root

    required property QtObject launcherService
    required property QtObject palette
    property Item focusTarget: null
    readonly property bool hasText: launcherService.query.length > 0
    readonly property string placeholderText: "Search apps, links, files, calc, emoji, or type clip/file/sys/emo"

    signal focusRequested()

    function forceInputFocus() {
        searchInput.forceActiveFocus();
    }

    function syncFromService() {
        const nextText = root.launcherService ? root.launcherService.query : "";
        if (searchInput.text !== nextText)
            searchInput.text = nextText;

    }

    Layout.fillWidth: true
    implicitHeight: 52
    radius: 0
    color: "transparent"
    border.width: 0

    Connections {
        function onQueryChanged() {
            root.syncFromService();
        }

        target: root.launcherService
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        spacing: 12

        Rectangle {
            implicitWidth: 24
            implicitHeight: 24
            radius: 12
            color: "transparent"
            border.width: 0

            Text {
                anchors.centerIn: parent
                text: "|"
                color: searchInput.activeFocus ? root.palette.primaryText : root.palette.mutedText
                font.pixelSize: 22
                font.family: root.palette.fontFamilyMono
            }

        }

        Item {
            Layout.fillWidth: true
            implicitHeight: 32

            TextInput {
                id: searchInput

                anchors.fill: parent
                focus: true
                color: root.palette.primaryText
                selectionColor: Qt.alpha(root.palette.accent, 0.3)
                selectedTextColor: root.palette.primaryText
                font.pixelSize: root.palette.fontLg
                font.family: root.palette.fontFamilyMono
                verticalAlignment: TextInput.AlignVCenter
                text: root.launcherService.query
                inputMethodHints: Qt.ImhNoPredictiveText
                Keys.onUpPressed: {
                    if (root.launcherService.actionPanelOpen)
                        root.launcherService.moveActionSelection(-1);
                    else
                        root.launcherService.moveSelection(-1);
                    event.accepted = true;
                }
                Keys.onDownPressed: {
                    if (root.launcherService.actionPanelOpen)
                        root.launcherService.moveActionSelection(1);
                    else
                        root.launcherService.moveSelection(1);
                    event.accepted = true;
                }
                Keys.onReturnPressed: {
                    if (root.launcherService.actionPanelOpen)
                        root.launcherService.runSelectedAction();
                    else
                        root.launcherService.runSelected();
                    event.accepted = true;
                }
                Keys.onEscapePressed: {
                    if (root.launcherService.systemConfirmationPending) {
                        root.launcherService.clearPendingConfirmation();
                    } else if (root.launcherService.actionPanelOpen) {
                        root.launcherService.closeActionPanel();
                    } else if (root.launcherService.query.length > 0) {
                        root.launcherService.clearQuery();
                        searchInput.text = "";
                    } else {
                        root.launcherService.close();
                    }
                    event.accepted = true;
                }
                Keys.onPressed: (event) => {
                    if (event.key === Qt.Key_K && (event.modifiers & Qt.ControlModifier)) {
                        root.launcherService.toggleActionPanel();
                        event.accepted = true;
                    }
                }
                onTextChanged: {
                    root.launcherService.query = text;
                }
            }

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                visible: !root.hasText
                text: root.placeholderText
                color: root.palette.mutedText
                font.pixelSize: root.palette.fontMd
                font.family: root.palette.fontFamilyMono
            }

        }

        Rectangle {
            implicitWidth: hasText ? 28 : 64
            implicitHeight: 28
            radius: 14
            color: "transparent"
            border.width: hasText ? 1 : 0
            border.color: hasText ? root.palette.faintBorder : "transparent"

            Text {
                anchors.centerIn: parent
                text: hasText ? "x" : "Ctrl K"
                color: hasText ? root.palette.bodyText : root.palette.mutedText
                font.pixelSize: root.palette.fontSm
                font.family: root.palette.fontFamilyMono
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                enabled: hasText
                onClicked: {
                    root.launcherService.clearQuery();
                    searchInput.text = "";
                    root.focusRequested();
                }
            }

        }

    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        implicitHeight: 1
        color: searchInput.activeFocus || hasText ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.08)
    }

}
