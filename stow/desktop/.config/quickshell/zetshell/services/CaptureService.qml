import QtQuick
import Quickshell.Io

Item {
    id: root

    property string lastActionLabel: ""
    property string actionMessage: ""
    property bool actionError: false
    property string pendingMode: ""
    property string pendingDestination: ""
    readonly property bool busy: actionProcess.running
    readonly property string statusText: actionMessage !== "" ? actionMessage : "Choose a capture action"

    function queueScreenshot(mode, destination) {
        if (!mode)
            return;

        pendingMode = mode;
        pendingDestination = destination || "clipboard";
        launchDelay.restart();
    }

    function queueGeometryCapture(destination, geometry) {
        if (!geometry)
            return;

        pendingMode = `region:${geometry}`;
        pendingDestination = destination || "clipboard";
        launchDelay.restart();
    }

    function runScreenshot(mode, destination) {
        if (!mode || actionProcess.running)
            return;

        const resolvedDestination = destination || "clipboard";
        let shellMode = mode;
        let geometry = "";
        if (String(mode).startsWith("region:")) {
            shellMode = "region";
            geometry = String(mode).slice("region:".length);
        }

        lastActionLabel = `Captured ${shellMode}`;
        actionProcess.command = [
            "bash",
            "-lc",
            geometry !== ""
                ? `~/.config/hypr/scripts/capture.sh screenshot ${shellMode} ${resolvedDestination} ${JSON.stringify(geometry)}`
                : `~/.config/hypr/scripts/capture.sh screenshot ${shellMode} ${resolvedDestination}`
        ];
        actionProcess.running = true;
    }

    Timer {
        id: launchDelay

        interval: 220
        repeat: false
        onTriggered: {
            if (!root.pendingMode)
                return;

            const mode = root.pendingMode;
            const destination = root.pendingDestination;
            root.pendingMode = "";
            root.pendingDestination = "";
            root.runScreenshot(mode, destination);
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
                root.actionMessage = stdoutText || root.lastActionLabel || "Capture complete";
            } else {
                root.actionError = true;
                root.actionMessage = stderrText || stdoutText || "Capture failed";
            }
        }
    }
}
