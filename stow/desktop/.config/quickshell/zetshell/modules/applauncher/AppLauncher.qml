import "../.." as Shell
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: root

    property string targetMonitor: ""
    property string screenNameHint: ""
    property QtObject launcherService: null
    readonly property int launcherRadius: 18
    readonly property string screenName: screenNameHint
    readonly property bool isTargetMonitor: {
        if (!targetMonitor)
            return true;

        if (!screenName)
            return false;

        return screenName === targetMonitor;
    }
    readonly property int panelWidth: {
        const w = screen ? screen.width : 1920;
        return Math.max(640, Math.min(780, Math.round(w * 0.38)));
    }
    readonly property int panelHeight: {
        const h = screen ? screen.height : 1080;
        return Math.max(460, Math.min(640, Math.round(h * 0.54)));
    }
    readonly property var results: launcherService ? launcherService.results : []
    readonly property int resultCount: launcherService ? launcherService.resultCount : 0
    readonly property int selectedIndex: launcherService ? launcherService.selectedIndex : 0
    readonly property string queryText: launcherService ? launcherService.query : ""
    readonly property string statusText: launcherService ? launcherService.statusText : ""
    readonly property string emptyStateText: launcherService ? launcherService.emptyStateText : "Start typing to search"

    function closeLauncher() {
        if (launcherService)
            launcherService.close();

    }

    function clearSearchFocus() {
        searchBox.forceInputFocus();
    }

    function runResult(result) {
        if (launcherService)
            launcherService.runResult(result);

    }

    function emptyText() {
        return emptyStateText;
    }

    color: "transparent"
    exclusiveZone: 0
    implicitWidth: panelWidth
    implicitHeight: panelHeight
    WlrLayershell.namespace: "zetshell-app-launcher"
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    visible: isTargetMonitor && launcherService && launcherService.open
    onVisibleChanged: {
        if (visible) {
            launcherService.prepare();
            Qt.callLater(() => {
                focusRoot.forceActiveFocus();
                searchBox.forceInputFocus();
            });
        }
    }
    onResultCountChanged: {
        if (resultsList.count > 0)
            resultsList.positionViewAtIndex(0, ListView.Beginning);

    }

    Shell.Theme {
        id: theme
    }

    anchors {
        top: true
        left: true
    }

    margins {
        top: Math.max(24, Math.round(((screen ? screen.height : panelHeight) - panelHeight) / 2))
        left: Math.max(24, Math.round(((screen ? screen.width : panelWidth) - panelWidth) / 2))
    }

    Connections {
        function onQueryChanged() {
            if (resultsList.count > 0)
                resultsList.positionViewAtIndex(0, ListView.Beginning);

        }

        function onSelectedIndexChanged() {
            if (resultsList.count > 0)
                resultsList.positionViewAtIndex(launcherService.selectedIndex, ListView.Contain);

        }

        target: launcherService
    }

    Rectangle {
        anchors.fill: parent
        anchors.topMargin: 12
        radius: root.launcherRadius
        color: theme.panelShadow
        opacity: 0.48
    }

    Rectangle {
        anchors.fill: parent
        radius: root.launcherRadius
        color: Qt.rgba(0.06, 0.07, 0.09, 0.62)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.1)

        FocusScope {
            id: focusRoot

            anchors.fill: parent
            focus: root.visible

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 10

                LauncherSearchBox {
                    id: searchBox

                    launcherService: root.launcherService
                    palette: theme
                    onFocusRequested: root.clearSearchFocus()
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 12
                    color: "transparent"
                    border.width: 0

                    ListView {
                        id: resultsList

                        anchors.fill: parent
                        anchors.topMargin: 4
                        anchors.bottomMargin: 4
                        model: root.results
                        currentIndex: root.selectedIndex
                        spacing: 2
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        highlightMoveDuration: 0

                        Item {
                            anchors.fill: parent
                            visible: root.resultCount === 0

                            Text {
                                anchors.centerIn: parent
                                text: root.emptyText()
                                color: theme.mutedText
                                font.pixelSize: theme.fontMd
                                font.family: theme.fontFamilyMono
                            }

                        }

                        delegate: LauncherResultRow {
                            required property var modelData

                            entry: modelData
                            selected: root.selectedIndex === index
                            launcherService: root.launcherService
                            palette: theme
                            onLaunchRequested: (entry) => {
                                return root.runResult(entry);
                            }
                        }

                    }

                    LauncherActionPanel {
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: 6
                        width: Math.max(240, Math.min(parent.width * 0.42, 320))
                        launcherService: root.launcherService
                        palette: theme
                    }

                }

                LauncherFooter {
                    launcherService: root.launcherService
                    palette: theme
                }

            }

        }

    }

}
