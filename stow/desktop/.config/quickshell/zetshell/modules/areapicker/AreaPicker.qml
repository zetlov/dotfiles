import QtQuick
import Quickshell
import Quickshell.Wayland
import "../.." as Shell

PanelWindow {
    id: root

    property string targetMonitor: ""
    property string screenNameHint: ""
    property QtObject pickerService: null
    property QtObject captureService: null
    property QtObject recordService: null

    Shell.Theme {
        id: theme
    }

    color: "transparent"
    exclusiveZone: 0

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true

    readonly property string screenName: screenNameHint
    readonly property bool isTargetMonitor: {
        if (!targetMonitor)
            return true;
        if (!screenName)
            return false;
        return screenName === targetMonitor;
    }

    readonly property bool active: isTargetMonitor && pickerService && pickerService.open
    readonly property bool windowMode: pickerService && pickerService.mode === "window"
    readonly property bool regionMode: pickerService && pickerService.mode === "region"
    readonly property bool recordingTarget: pickerService && pickerService.actionKind === "record"
    readonly property var localClients: {
        if (!pickerService || !pickerService.clients)
            return [];

        const sx = screen ? screen.x : 0;
        const sy = screen ? screen.y : 0;
        const sw = screen ? screen.width : 1920;
        const sh = screen ? screen.height : 1080;

        return pickerService.clients
            .map(client => {
                const x = client.at[0] - sx;
                const y = client.at[1] - sy;
                const width = client.size[0];
                const height = client.size[1];
                return {
                    x,
                    y,
                    width,
                    height,
                    className: client.class || "",
                    title: client.title || ""
                };
            })
            .filter(client => client.width > 0 && client.height > 0 && client.x < sw && client.y < sh && client.x + client.width > 0 && client.y + client.height > 0);
    }

    property real startX: 0
    property real startY: 0
    property real endX: 0
    property real endY: 0
    property bool dragging: false
    property int hoveredClientIndex: -1

    readonly property real rectX: Math.min(startX, endX)
    readonly property real rectY: Math.min(startY, endY)
    readonly property real rectWidth: Math.abs(endX - startX)
    readonly property real rectHeight: Math.abs(endY - startY)

    function resetSelection() {
        dragging = false;
        hoveredClientIndex = -1;
        startX = 0;
        startY = 0;
        endX = 0;
        endY = 0;
    }

    function currentGeometry() {
        if (windowMode && hoveredClientIndex >= 0 && hoveredClientIndex < localClients.length) {
            const client = localClients[hoveredClientIndex];
            const gx = (screen ? screen.x : 0) + client.x;
            const gy = (screen ? screen.y : 0) + client.y;
            return `${Math.round(gx)},${Math.round(gy)} ${Math.round(client.width)}x${Math.round(client.height)}`;
        }

        if (rectWidth < 2 || rectHeight < 2)
            return "";

        const gx = (screen ? screen.x : 0) + rectX;
        const gy = (screen ? screen.y : 0) + rectY;
        return `${Math.round(gx)},${Math.round(gy)} ${Math.round(rectWidth)}x${Math.round(rectHeight)}`;
    }

    function selectHoveredClient(x, y) {
        hoveredClientIndex = -1;
        for (let i = 0; i < localClients.length; i += 1) {
            const client = localClients[i];
            if (x >= client.x && y >= client.y && x <= client.x + client.width && y <= client.y + client.height) {
                hoveredClientIndex = i;
                return;
            }
        }
    }

    function commitSelection() {
        if (!pickerService)
            return;

        const geometry = currentGeometry();
        if (!geometry)
            return;

        const actionKind = pickerService.actionKind;
        const selectionMode = pickerService.mode;
        const destination = pickerService.destination;
        const withAudio = pickerService.withAudio;
        pickerService.close();

        if (actionKind === "record") {
            if (recordService)
                recordService.queueGeometryRecord(selectionMode, geometry, withAudio);
            return;
        }

        if (captureService)
            captureService.queueGeometryCapture(destination, geometry);
    }

    visible: active
    implicitWidth: screen ? screen.width : 1920
    implicitHeight: screen ? screen.height : 1080

    WlrLayershell.namespace: "zetshell-area-picker"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    onVisibleChanged: {
        if (visible) {
            if (pickerService)
                pickerService.refreshClients();
            resetSelection();
            Qt.callLater(() => pickerMouse.forceActiveFocus());
        } else {
            resetSelection();
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "#aa05080c"
    }

    MouseArea {
        id: pickerMouse

        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.CrossCursor
        focus: root.visible

        onPressed: event => {
            if (!regionMode)
                return;

            root.dragging = true;
            root.startX = event.x;
            root.startY = event.y;
            root.endX = event.x;
            root.endY = event.y;
        }

        onPositionChanged: event => {
            if (windowMode) {
                root.selectHoveredClient(event.x, event.y);
                return;
            }

            if (!root.dragging)
                return;

            root.endX = event.x;
            root.endY = event.y;
        }

        onReleased: event => {
            if (windowMode) {
                root.selectHoveredClient(event.x, event.y);
                root.commitSelection();
                return;
            }

            if (!root.dragging)
                return;

            root.endX = event.x;
            root.endY = event.y;
            root.dragging = false;
            root.commitSelection();
        }

        Keys.onEscapePressed: {
            if (pickerService)
                pickerService.close();
        }
    }

    Rectangle {
        visible: windowMode && hoveredClientIndex >= 0
        x: visible ? localClients[hoveredClientIndex].x : 0
        y: visible ? localClients[hoveredClientIndex].y : 0
        width: visible ? localClients[hoveredClientIndex].width : 0
        height: visible ? localClients[hoveredClientIndex].height : 0
        radius: 14
        color: "#2289dceb"
        border.width: 2
        border.color: theme.attentionBorder
    }

    Rectangle {
        visible: regionMode && (dragging || rectWidth >= 2 || rectHeight >= 2)
        x: rectX
        y: rectY
        width: rectWidth
        height: rectHeight
        radius: 14
        color: "#2289dceb"
        border.width: 2
        border.color: theme.attentionBorder
    }

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 28
        implicitWidth: helper.implicitWidth + 28
        implicitHeight: 48
        radius: 24
        color: theme.railBottom
        border.width: 1
        border.color: theme.cardBorder

        Text {
            id: helper
            anchors.centerIn: parent
            text: windowMode
                ? (recordingTarget ? "Window recording picker  click a window  Esc to cancel" : "Window picker  click a window  Esc to cancel")
                : (recordingTarget ? "Region recording picker  drag to select  Esc to cancel" : "Region picker  drag to select  Esc to cancel")
            color: theme.primaryText
            font.pixelSize: theme.fontMd
            font.family: theme.fontFamilyMono
        }
    }
}
