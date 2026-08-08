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
    property QtObject captureService: null
    property QtObject pickerService: null
    property QtObject recordService: null
    readonly property string screenName: screenNameHint
    readonly property bool isTargetMonitor: {
        if (!targetMonitor)
            return true;

        if (!screenName)
            return false;

        return screenName === targetMonitor;
    }
    readonly property int panelWidth: {
        const width = screen ? screen.width : 1920;
        return Math.max(theme.captureLauncherWidthMin, Math.min(theme.captureLauncherWidthMax, Math.round(width * 0.54)));
    }
    readonly property int panelHeight: {
        const height = screen ? screen.height : 1080;
        return Math.max(theme.captureLauncherHeightMin, Math.min(theme.captureLauncherHeightMax, Math.round(height * 0.68)));
    }
    property int selectedActionIndex: 0
    property int selectedRecordIndex: 0
    readonly property var screenshotActions: [{
        "title": "Region Copy",
        "subtitle": "Select an area and copy it",
        "mode": "region",
        "destination": "clipboard",
        "badge": "REG"
    }, {
        "title": "Window Copy",
        "subtitle": "Choose a window rectangle and copy it",
        "mode": "window",
        "destination": "clipboard",
        "badge": "WIN"
    }, {
        "title": "Output Copy",
        "subtitle": "Capture a monitor to clipboard",
        "mode": "output",
        "destination": "clipboard",
        "badge": "OUT"
    }, {
        "title": "Region Save",
        "subtitle": "Select an area, save it, then open swappy when available",
        "mode": "region",
        "destination": "save",
        "badge": "REG"
    }, {
        "title": "Window Save",
        "subtitle": "Choose a window rectangle, save it, then open swappy when available",
        "mode": "window",
        "destination": "save",
        "badge": "WIN"
    }, {
        "title": "Output Save",
        "subtitle": "Capture a monitor, save it, then open swappy when available",
        "mode": "output",
        "destination": "save",
        "badge": "OUT"
    }]
    readonly property var recordActions: {
        if (recordService && recordService.recording)
            return [{
                "title": recordService.paused ? "Resume Recording" : "Pause Recording",
                "subtitle": recordService.paused ? "Continue the active recording session" : "Temporarily pause the active recording",
                "action": "pause",
                "badge": recordService.paused ? "RES" : "PAU"
            }, {
                "title": "Stop Recording",
                "subtitle": recordService.outputPath ? `Save to ${recordService.outputPath.split("/").pop()}` : "Stop and save the current recording",
                "action": "stop",
                "badge": "STP"
            }];

        return [{
            "title": "Start Output Recording",
            "subtitle": "Record the focused monitor with default output audio",
            "action": "start-audio",
            "badge": "REC"
        }, {
            "title": "Start Silent Recording",
            "subtitle": "Record the focused monitor without audio",
            "action": "start-silent",
            "badge": "MUT"
        }, {
            "title": "Start Region Recording",
            "subtitle": "Pick an area and record it with default output audio",
            "action": "start-region",
            "badge": "REG"
        }, {
            "title": "Start Silent Region",
            "subtitle": "Pick an area and record it without audio",
            "action": "start-region-silent",
            "badge": "RGM"
        }, {
            "title": "Start Window Recording",
            "subtitle": "Pick a window rectangle and record it with default output audio",
            "action": "start-window",
            "badge": "WIN"
        }, {
            "title": "Start Silent Window",
            "subtitle": "Pick a window rectangle and record it without audio",
            "action": "start-window-silent",
            "badge": "WNM"
        }];
    }

    function activeSection() {
        return launcherService ? launcherService.activeSection : "screenshot";
    }

    function screenshotColumns() {
        return width >= 1180 ? 3 : 2;
    }

    function moveScreenshotSelection(dx, dy) {
        const cols = screenshotColumns();
        const row = Math.floor(selectedActionIndex / cols);
        const col = selectedActionIndex % cols;
        const nextRow = Math.max(0, row + dy);
        const nextCol = Math.max(0, col + dx);
        selectedActionIndex = Math.min(screenshotActions.length - 1, nextRow * cols + Math.min(cols - 1, nextCol));
    }

    function moveRecordSelection(delta) {
        if (!recordActions.length)
            return ;

        selectedRecordIndex = Math.max(0, Math.min(recordActions.length - 1, selectedRecordIndex + delta));
    }

    function runSelectedScreenshotAction() {
        if (selectedActionIndex < 0 || selectedActionIndex >= screenshotActions.length)
            return ;

        const action = screenshotActions[selectedActionIndex];
        launcherService.close();
        if (action.mode === "output") {
            if (captureService)
                captureService.queueScreenshot(action.mode, action.destination);

            return ;
        }
        if (pickerService)
            pickerService.openPicker(action.mode, action.destination);

    }

    function focusRootLater() {
        Qt.callLater(() => {
            return focusRoot.forceActiveFocus();
        });
    }

    function runSelectedRecordAction() {
        if (!recordService || selectedRecordIndex < 0 || selectedRecordIndex >= recordActions.length)
            return ;

        const action = recordActions[selectedRecordIndex];
        launcherService.close();
        if (action.action === "pause") {
            recordService.togglePause();
        } else if (action.action === "stop") {
            recordService.stop();
        } else if (action.action === "start-region" || action.action === "start-region-silent") {
            if (pickerService)
                pickerService.openPicker("region", "", "record", action.action === "start-region");

        } else if (action.action === "start-window" || action.action === "start-window-silent") {
            if (pickerService)
                pickerService.openPicker("window", "", "record", action.action === "start-window");

        } else if (action.action === "start-silent") {
            recordService.startOutput(false);
        } else {
            recordService.startOutput(true);
        }
    }

    color: "transparent"
    exclusiveZone: 0
    implicitWidth: panelWidth
    implicitHeight: panelHeight
    WlrLayershell.namespace: "zetshell-capture-launcher"
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    visible: isTargetMonitor && launcherService && launcherService.open
    onVisibleChanged: {
        if (visible)
            focusRootLater();

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
        function onActiveSectionChanged() {
            root.selectedActionIndex = 0;
            root.selectedRecordIndex = 0;
            focusRootLater();
        }

        target: launcherService
    }

    Rectangle {
        anchors.fill: parent
        anchors.topMargin: 12
        radius: theme.panelRadius
        color: theme.panelShadow
        opacity: 0.72
    }

    Rectangle {
        anchors.fill: parent
        radius: theme.panelRadius
        color: theme.railBottom
        border.width: 1
        border.color: theme.cardBorder

        FocusScope {
            id: focusRoot

            anchors.fill: parent
            focus: root.visible
            Keys.onPressed: (event) => {
                if (!launcherService)
                    return ;

                const section = activeSection();
                if (event.key === Qt.Key_Escape) {
                    launcherService.close();
                    event.accepted = true;
                    return ;
                }
                if (event.key === Qt.Key_Tab) {
                    launcherService.cycleSection(event.modifiers & Qt.ShiftModifier ? -1 : 1);
                    event.accepted = true;
                    return ;
                }
                if (section === "screenshot") {
                    if (event.key === Qt.Key_Left || event.key === Qt.Key_H) {
                        moveScreenshotSelection(-1, 0);
                        event.accepted = true;
                        return ;
                    }
                    if (event.key === Qt.Key_Right || event.key === Qt.Key_L) {
                        moveScreenshotSelection(1, 0);
                        event.accepted = true;
                        return ;
                    }
                    if (event.key === Qt.Key_Up || event.key === Qt.Key_K) {
                        moveScreenshotSelection(0, -1);
                        event.accepted = true;
                        return ;
                    }
                    if (event.key === Qt.Key_Down || event.key === Qt.Key_J) {
                        moveScreenshotSelection(0, 1);
                        event.accepted = true;
                        return ;
                    }
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                        runSelectedScreenshotAction();
                        event.accepted = true;
                    }
                }
                if (section === "record") {
                    if (event.key === Qt.Key_Down || event.key === Qt.Key_J) {
                        moveRecordSelection(1);
                        event.accepted = true;
                        return ;
                    }
                    if (event.key === Qt.Key_Up || event.key === Qt.Key_K) {
                        moveRecordSelection(-1);
                        event.accepted = true;
                        return ;
                    }
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                        runSelectedRecordAction();
                        event.accepted = true;
                    }
                }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 18
                spacing: 14

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    ColumnLayout {
                        spacing: -2

                        Text {
                            text: "Capture Launcher"
                            color: theme.primaryText
                            font.pixelSize: 18
                            font.bold: true
                            font.family: theme.fontFamilyMono
                        }

                        Text {
                            text: activeSection() === "screenshot" ? "Screenshot actions backed by grim and the shell picker" : "Focused output recording powered by gpu-screen-recorder"
                            color: theme.mutedText
                            font.pixelSize: theme.fontSm
                            font.family: theme.fontFamilyMono
                        }

                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    Rectangle {
                        radius: theme.chipRadius
                        color: theme.cardColor
                        border.width: 1
                        border.color: theme.softBorder
                        implicitHeight: theme.chipHeight
                        implicitWidth: row.implicitWidth + 18

                        RowLayout {
                            id: row

                            anchors.centerIn: parent
                            spacing: 8

                            Repeater {
                                model: [{
                                    "id": "screenshot",
                                    "label": "Screenshot"
                                }, {
                                    "id": "record",
                                    "label": "Record"
                                }]

                                delegate: Rectangle {
                                    required property var modelData

                                    radius: theme.chipRadius - 5
                                    implicitWidth: label.implicitWidth + 22
                                    implicitHeight: theme.chipHeight - 10
                                    color: activeSection() === modelData.id ? theme.attentionFill : "transparent"
                                    border.width: activeSection() === modelData.id ? 1 : 0
                                    border.color: theme.attentionBorder

                                    Text {
                                        id: label

                                        anchors.centerIn: parent
                                        text: modelData.label
                                        color: activeSection() === modelData.id ? theme.primaryText : theme.mutedText
                                        font.pixelSize: theme.fontMd
                                        font.bold: activeSection() === modelData.id
                                        font.family: theme.fontFamilyMono
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: launcherService.openLauncher(modelData.id)
                                    }

                                }

                            }

                        }

                    }

                }

                Loader {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    sourceComponent: activeSection() === "screenshot" ? screenshotComponent : recordComponent
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 44
                    radius: theme.cardRadius
                    color: theme.cardColor
                    border.width: 1
                    border.color: (activeSection() === "screenshot" ? (captureService ? captureService.actionError : false) : (recordService ? recordService.actionError : false)) ? theme.attentionBorder : theme.faintBorder

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        spacing: 10

                        Text {
                            text: "Actions"
                            color: theme.mutedText
                            font.pixelSize: theme.fontSm
                            font.family: theme.fontFamilyMono
                        }

                        Text {
                            Layout.fillWidth: true
                            text: activeSection() === "screenshot" ? "Tab switch section  Enter run  HJKL move  Esc close" : "Tab switch section  Enter run  J/K move  Esc close"
                            color: theme.primaryText
                            font.pixelSize: theme.fontSm
                            font.family: theme.fontFamilyMono
                            elide: Text.ElideRight
                        }

                        Text {
                            text: activeSection() === "screenshot" ? (captureService ? captureService.statusText : "Choose a capture action") : (recordService ? recordService.statusText : "Recorder idle")
                            color: (activeSection() === "screenshot" ? (captureService ? captureService.actionError : false) : (recordService ? recordService.actionError : false)) ? theme.dangerText : theme.bodyText
                            font.pixelSize: theme.fontSm
                            font.family: theme.fontFamilyMono
                            elide: Text.ElideLeft
                        }

                    }

                }

            }

        }

    }

    Component {
        id: screenshotComponent

        Rectangle {
            color: "transparent"

            Rectangle {
                anchors.fill: parent
                radius: theme.panelRadius - 6
                color: theme.cardColor
                border.width: 1
                border.color: theme.faintBorder
            }

            GridLayout {
                anchors.fill: parent
                anchors.margins: 12
                columns: screenshotColumns()
                columnSpacing: 10
                rowSpacing: 10

                Repeater {
                    model: screenshotActions

                    delegate: Rectangle {
                        required property var modelData
                        required property int index

                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: theme.panelRadius - 8
                        color: root.selectedActionIndex === index ? theme.attentionFill : theme.darkControl
                        border.width: 1
                        border.color: root.selectedActionIndex === index ? theme.attentionBorder : theme.faintBorder

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 14
                            spacing: 8

                            Rectangle {
                                implicitWidth: 56
                                implicitHeight: 30
                                radius: 15
                                color: theme.workspaceHoverFill
                                border.width: 1
                                border.color: theme.softBorder

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.badge
                                    color: theme.primaryText
                                    font.pixelSize: theme.fontSm
                                    font.bold: true
                                    font.family: theme.fontFamilyMono
                                }

                            }

                            Text {
                                Layout.fillWidth: true
                                text: modelData.title
                                color: theme.primaryText
                                font.pixelSize: 16
                                font.bold: true
                                font.family: theme.fontFamilyMono
                                elide: Text.ElideRight
                            }

                            Text {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                text: modelData.subtitle
                                color: theme.mutedText
                                font.pixelSize: theme.fontMd
                                font.family: theme.fontFamilyMono
                                wrapMode: Text.WordWrap
                            }

                            Text {
                                text: root.selectedActionIndex === index ? "Enter to run" : (modelData.destination === "clipboard" ? "Clipboard" : "Save")
                                color: root.selectedActionIndex === index ? theme.primaryText : theme.mutedText
                                font.pixelSize: theme.fontSm
                                font.bold: root.selectedActionIndex === index
                                font.family: theme.fontFamilyMono
                            }

                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: root.selectedActionIndex = index
                            onClicked: {
                                root.selectedActionIndex = index;
                                launcherService.close();
                                if (modelData.mode === "output") {
                                    if (captureService)
                                        captureService.queueScreenshot(modelData.mode, modelData.destination);

                                } else if (pickerService) {
                                    pickerService.openPicker(modelData.mode, modelData.destination);
                                }
                            }
                        }

                    }

                }

            }

        }

    }

    Component {
        id: recordComponent

        Rectangle {
            color: "transparent"

            Rectangle {
                anchors.fill: parent
                radius: theme.panelRadius - 6
                color: theme.cardColor
                border.width: 1
                border.color: theme.faintBorder
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 10

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: theme.cardHeight + 4
                    radius: theme.cardRadius - 4
                    color: theme.darkControl
                    border.width: 1
                    border.color: recordService && recordService.recording ? theme.attentionBorder : theme.faintBorder

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        spacing: 10

                        Text {
                            text: recordService && recordService.recording ? (recordService.paused ? "Paused" : "Live") : "Idle"
                            color: recordService && recordService.recording ? theme.primaryText : theme.mutedText
                            font.pixelSize: theme.fontMd
                            font.bold: recordService && recordService.recording
                            font.family: theme.fontFamilyMono
                        }

                        Text {
                            Layout.fillWidth: true
                            text: recordService && recordService.recording ? `${recordService.mode === "output" ? recordService.monitor : recordService.mode}${recordService.withAudio ? "  audio" : "  silent"}` : "Focused output recording"
                            color: theme.bodyText
                            font.pixelSize: theme.fontSm
                            font.family: theme.fontFamilyMono
                            elide: Text.ElideRight
                        }

                        Text {
                            text: recordService && recordService.outputPath ? recordService.outputPath.split("/").pop() : ""
                            color: theme.mutedText
                            font.pixelSize: theme.fontSm
                            font.family: theme.fontFamilyMono
                            elide: Text.ElideLeft
                        }

                    }

                }

                Repeater {
                    model: recordActions

                    delegate: Rectangle {
                        required property var modelData
                        required property int index

                        Layout.fillWidth: true
                        implicitHeight: theme.captureLauncherRowHeight + 2
                        radius: theme.cardRadius - 6
                        color: root.selectedRecordIndex === index ? theme.attentionFill : theme.darkControl
                        border.width: 1
                        border.color: root.selectedRecordIndex === index ? theme.attentionBorder : theme.faintBorder

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 14
                            spacing: 12

                            Rectangle {
                                implicitWidth: 56
                                implicitHeight: 34
                                radius: 17
                                color: theme.workspaceHoverFill
                                border.width: 1
                                border.color: theme.softBorder

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.badge
                                    color: theme.primaryText
                                    font.pixelSize: theme.fontSm
                                    font.bold: true
                                    font.family: theme.fontFamilyMono
                                }

                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1

                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.title
                                    color: theme.primaryText
                                    font.pixelSize: theme.fontMd
                                    font.bold: root.selectedRecordIndex === index
                                    font.family: theme.fontFamilyMono
                                    elide: Text.ElideRight
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.subtitle
                                    color: theme.mutedText
                                    font.pixelSize: theme.fontSm
                                    font.family: theme.fontFamilyMono
                                    elide: Text.ElideRight
                                }

                            }

                            Text {
                                text: root.selectedRecordIndex === index ? "Enter" : ""
                                color: theme.primaryText
                                font.pixelSize: theme.fontSm
                                font.bold: true
                                font.family: theme.fontFamilyMono
                            }

                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: root.selectedRecordIndex = index
                            onClicked: {
                                root.selectedRecordIndex = index;
                                root.runSelectedRecordAction();
                            }
                        }

                    }

                }

                Item {
                    Layout.fillHeight: true
                }

            }

        }

    }

}
