import QtQuick
import Quickshell.Services.Pipewire

Item {
    id: root

    readonly property var sinks: Pipewire.nodes.values.filter(node => node && node.isSink && node.audio !== null && node.ready)
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property bool ready: Pipewire.ready && sink !== null && sink.audio !== null && sink.ready
    readonly property int level: ready ? Math.max(0, Math.round(sink.audio.volume * 100)) : 0
    readonly property bool muted: ready ? sink.audio.muted : false
    readonly property string deviceName: {
        if (!sink)
            return "";

        return sink.nickname || sink.description || sink.name || "";
    }
    readonly property string text: {
        if (!ready)
            return "Audio --";

        return muted ? "Muted" : `${level}%`;
    }
    readonly property string tone: {
        if (!ready)
            return "#8aa0b3";
        if (muted)
            return "#ff9e9e";
        if (level >= 70)
            return "#ffbf7a";

        return "#7ae7d7";
    }

    function setLevel(percent) {
        if (!ready)
            return;

        const normalized = Math.max(0, Math.min(1.25, percent / 100));
        sink.audio.volume = normalized;
    }

    function stepLevel(deltaPercent) {
        setLevel(level + deltaPercent);
    }

    function toggleMute() {
        if (ready)
            sink.audio.muted = !sink.audio.muted;
    }

    function setDefaultSink(node) {
        if (node)
            Pipewire.preferredDefaultAudioSink = node;
    }

    PwObjectTracker {
        objects: root.sink ? [root.sink, ...root.sinks] : root.sinks
    }
}
