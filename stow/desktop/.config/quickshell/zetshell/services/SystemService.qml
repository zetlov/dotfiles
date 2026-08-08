import QtQuick
import Quickshell.Io

Item {
    id: root

    property string pendingCommand: ""
    property string armedAction: ""
    property string lastAction: ""

    readonly property bool busy: actionProcess.running
    readonly property string statusText: {
        if (busy)
            return `Running ${lastAction || "action"}...`;
        if (armedAction)
            return `Press again to confirm ${armedAction}.`;

        return "Lock, suspend, logout, reboot, or power off.";
    }

    function clearArmedAction() {
        root.armedAction = "";
    }

    function run(label, command) {
        if (busy)
            return;

        root.lastAction = label;
        root.pendingCommand = command;
        actionProcess.running = true;
    }

    function invoke(actionId) {
        if (actionId === "lock") {
            clearArmedAction();
            run("lock", "pidof hyprlock >/dev/null 2>&1 || hyprlock");
            return;
        }

        if (actionId === "suspend") {
            clearArmedAction();
            run("suspend", "systemctl suspend");
            return;
        }

        if (actionId === "logout") {
            if (armedAction === actionId) {
                clearArmedAction();
                run("logout", "hyprctl dispatch exit");
            } else {
                armedAction = actionId;
                armTimer.restart();
            }
            return;
        }

        if (actionId === "reboot") {
            if (armedAction === actionId) {
                clearArmedAction();
                run("reboot", "systemctl reboot");
            } else {
                armedAction = actionId;
                armTimer.restart();
            }
            return;
        }

        if (actionId === "shutdown") {
            if (armedAction === actionId) {
                clearArmedAction();
                run("shutdown", "systemctl poweroff");
            } else {
                armedAction = actionId;
                armTimer.restart();
            }
        }
    }

    Timer {
        id: armTimer

        interval: 4000
        repeat: false
        onTriggered: root.clearArmedAction()
    }

    Process {
        id: actionProcess

        command: ["bash", "-lc", root.pendingCommand]

        onExited: {
            root.pendingCommand = "";
            root.clearArmedAction();
        }
    }
}
