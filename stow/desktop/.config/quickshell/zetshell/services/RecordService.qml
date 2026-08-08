import QtQuick
import Quickshell.Io

Item {
    id: root

    property bool recording: false
    property bool paused: false
    property bool withAudio: false
    property string mode: ""
    property string outputPath: ""
    property string monitor: ""
    property string pendingMode: ""
    property string pendingGeometry: ""
    property bool pendingWithAudio: true
    property string lastActionLabel: ""
    property string actionMessage: ""
    property bool actionError: false
    readonly property bool busy: statusProcess.running || actionProcess.running
    readonly property string modeLabel: mode === "output" ? monitor : (mode !== "" ? `${mode}  ${monitor}` : "")
    readonly property string statusText: actionMessage !== ""
        ? actionMessage
        : recording
            ? `${paused ? "Paused" : "Recording"}  ${modeLabel}${withAudio ? "  audio" : "  silent"}`
            : "Recorder idle"

    function refresh() {
        if (!statusProcess.running)
            statusProcess.running = true;
    }

    function startOutput(withAudioEnabled) {
        if (actionProcess.running)
            return;

        const useAudio = withAudioEnabled !== false;
        lastActionLabel = useAudio ? "Recording started" : "Recording started without audio";
        actionProcess.command = [
            "bash",
            "-lc",
            `~/.config/hypr/scripts/record.sh start output ${useAudio ? "true" : "false"}`
        ];
        actionProcess.running = true;
    }

    function queueGeometryRecord(mode, geometry, withAudioEnabled) {
        if (!geometry)
            return;

        pendingMode = mode || "region";
        pendingGeometry = geometry;
        pendingWithAudio = withAudioEnabled !== false;
        launchDelay.restart();
    }

    function startRegion(geometry, withAudioEnabled, mode) {
        if (actionProcess.running || !geometry)
            return;

        const useAudio = withAudioEnabled !== false;
        const resolvedMode = mode || "region";
        lastActionLabel = useAudio
            ? `Recording started for ${resolvedMode}`
            : `Recording started for ${resolvedMode} without audio`;
        actionProcess.command = [
            "bash",
            "-lc",
            `~/.config/hypr/scripts/record.sh start region ${useAudio ? "true" : "false"} ${JSON.stringify(geometry)} ${JSON.stringify(resolvedMode)}`
        ];
        actionProcess.running = true;
    }

    function toggleOutput(withAudioEnabled) {
        if (actionProcess.running)
            return;

        const useAudio = withAudioEnabled !== false;
        lastActionLabel = recording ? "Recording stopped" : (useAudio ? "Recording started" : "Recording started without audio");
        actionProcess.command = [
            "bash",
            "-lc",
            `~/.config/hypr/scripts/record.sh toggle output ${useAudio ? "true" : "false"}`
        ];
        actionProcess.running = true;
    }

    function stop() {
        if (actionProcess.running || !recording)
            return;

        lastActionLabel = "Recording stopped";
        actionProcess.command = [
            "bash",
            "-lc",
            "~/.config/hypr/scripts/record.sh stop"
        ];
        actionProcess.running = true;
    }

    function togglePause() {
        if (actionProcess.running || !recording)
            return;

        lastActionLabel = paused ? "Recording resumed" : "Recording paused";
        actionProcess.command = [
            "bash",
            "-lc",
            "~/.config/hypr/scripts/record.sh pause"
        ];
        actionProcess.running = true;
    }

    Timer {
        id: launchDelay

        interval: 220
        repeat: false
        onTriggered: {
            if (!root.pendingGeometry)
                return;

            const geometry = root.pendingGeometry;
            const mode = root.pendingMode;
            const withAudioEnabled = root.pendingWithAudio;
            root.pendingGeometry = "";
            root.pendingMode = "";
            root.startRegion(geometry, withAudioEnabled, mode);
        }
    }

    Timer {
        interval: 1500
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Process {
        id: statusProcess

        command: [
            "bash",
            "-lc",
            "~/.config/hypr/scripts/record.sh status"
        ]

        stdout: StdioCollector {
            onStreamFinished: {
                const raw = this.text.trim();
                if (!raw)
                    return;

                try {
                    const parsed = JSON.parse(raw);
                    root.recording = !!parsed.recording;
                    root.paused = !!parsed.paused;
                    root.withAudio = !!parsed.withAudio;
                    root.mode = parsed.mode || "";
                    root.outputPath = parsed.output || "";
                    root.monitor = parsed.monitor || "";
                } catch (error) {
                    console.warn("Failed to parse record status:", error);
                }
            }
        }
    }

    Process {
        id: actionProcess

        stdout: StdioCollector {}
        stderr: StdioCollector {}

        onExited: exitCode => {
            const stderrText = actionProcess.stderr.text.trim();
            const stdoutText = actionProcess.stdout.text.trim();

            if (exitCode === 0) {
                root.actionError = false;
                root.actionMessage = stdoutText || root.lastActionLabel || "Recorder updated";
            } else {
                root.actionError = true;
                root.actionMessage = stderrText || stdoutText || "Recorder action failed";
            }

            root.refresh();
        }
    }
}
