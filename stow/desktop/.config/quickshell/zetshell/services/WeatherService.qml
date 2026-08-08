import QtQuick
import Quickshell.Io

Item {
    id: root

    property QtObject config: null
    property string location: ""
    property string temperature: "--"
    property string condition: "Unavailable"
    property string status: "Waiting"
    readonly property bool available: temperature !== "--" && condition !== "Unavailable"

    function refresh() {
        if (!weatherProcess.running)
            weatherProcess.running = true;
    }

    Timer {
        interval: config ? config.weatherUpdateInterval : 15 * 60 * 1000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Process {
        id: weatherProcess

        command: [
            "sh",
            "-c",
            "loc=$1; if [ -z \"$loc\" ]; then loc=${ZETSHELL_WEATHER_LOCATION:-}; fi; if [ -n \"$loc\" ]; then curl -fsS --max-time 5 \"https://wttr.in/${loc}?format=%l|%t|%C\"; else curl -fsS --max-time 5 \"https://wttr.in?format=%l|%t|%C\"; fi",
            "weather",
            config ? config.weatherLocation : ""
        ]

        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split("|");
                if (parts.length < 3)
                    return;

                root.location = parts[0] || "";
                root.temperature = parts[1] || "--";
                root.condition = parts.slice(2).join(" | ") || "Unavailable";
                root.status = "Updated";
            }
        }

        onExited: exitCode => {
            if (exitCode !== 0)
                root.status = "Unavailable";
        }
    }
}
