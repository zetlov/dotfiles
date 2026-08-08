import QtQuick

Item {
    id: root

    property QtObject volume: null
    property QtObject brightness: null
    property bool open: false
    property string kind: "volume"
    property string title: "Volume"
    property string detail: ""
    property string icon: "VOL"
    property int level: 0
    property bool muted: false
    property color tone: "#7ae7d7"
    property int hideDelay: 1400

    readonly property bool isVolume: kind === "volume" || kind === "mute"
    readonly property bool isBrightness: kind === "brightness"

    function show(nextKind, nextTitle, nextDetail, nextIcon, nextLevel, nextMuted, nextTone) {
        kind = nextKind;
        title = nextTitle;
        detail = nextDetail;
        icon = nextIcon;
        level = Math.max(0, Math.min(125, Math.round(nextLevel)));
        muted = !!nextMuted;
        tone = nextTone || "#7ae7d7";
        open = true;
        hideTimer.restart();
    }

    function showVolume() {
        if (!volume || !volume.ready) {
            show("volume", "Volume", "Audio unavailable", "VOL", 0, false, "#8aa0b3");
            return;
        }

        show(
            volume.muted ? "mute" : "volume",
            volume.muted ? "Muted" : "Volume",
            volume.deviceName || "Default sink",
            volume.muted ? "MUTE" : "VOL",
            volume.level,
            volume.muted,
            volume.tone
        );
    }

    function showBrightness(nextLevel) {
        if (!brightness || !brightness.available) {
            show("brightness", "Brightness", "Backlight unavailable", "SUN", 0, false, "#8aa0b3");
            return;
        }

        const value = nextLevel !== undefined ? nextLevel : brightness.level;
        show("brightness", "Brightness", brightness.deviceName || "Backlight", "SUN", value, false, "#ffbf7a");
    }

    function volumeStep(delta) {
        if (!volume || !volume.ready) {
            showVolume();
            return;
        }

        volume.stepLevel(delta);
        Qt.callLater(showVolume);
    }

    function volumeMute() {
        if (volume && volume.ready)
            volume.toggleMute();
        Qt.callLater(showVolume);
    }

    function brightnessStep(delta) {
        if (!brightness || !brightness.available) {
            showBrightness();
            return;
        }

        const nextLevel = Math.max(1, Math.min(100, brightness.level + delta));
        brightness.setLevel(nextLevel);
        showBrightness(nextLevel);
    }

    function close() {
        hideTimer.stop();
        open = false;
    }

    Timer {
        id: hideTimer

        interval: root.hideDelay
        repeat: false
        onTriggered: root.open = false
    }
}
