import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    property bool dashboardEnabled: true
    property bool showMedia: true
    property bool showPerformance: true
    property bool showWeather: true
    property bool showActions: true
    property bool showLyrics: true
    property int resourceUpdateInterval: 2000
    property int detailUpdateInterval: 10000
    property int weatherUpdateInterval: 15 * 60 * 1000
    property string weatherLocation: ""

    function applyConfig(payload) {
        const dashboard = payload.dashboard || payload;
        if (dashboard.enabled !== undefined)
            dashboardEnabled = !!dashboard.enabled;
        if (dashboard.showMedia !== undefined)
            showMedia = !!dashboard.showMedia;
        if (dashboard.showPerformance !== undefined)
            showPerformance = !!dashboard.showPerformance;
        if (dashboard.showWeather !== undefined)
            showWeather = !!dashboard.showWeather;
        if (dashboard.showActions !== undefined)
            showActions = !!dashboard.showActions;
        if (dashboard.showLyrics !== undefined)
            showLyrics = !!dashboard.showLyrics;
        if (dashboard.resourceUpdateInterval)
            resourceUpdateInterval = Math.max(500, parseInt(dashboard.resourceUpdateInterval, 10));
        if (dashboard.detailUpdateInterval)
            detailUpdateInterval = Math.max(2000, parseInt(dashboard.detailUpdateInterval, 10));
        if (dashboard.weatherUpdateInterval)
            weatherUpdateInterval = Math.max(60000, parseInt(dashboard.weatherUpdateInterval, 10));
        if (dashboard.weatherLocation !== undefined)
            weatherLocation = String(dashboard.weatherLocation);
    }

    Timer {
        interval: 2500
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: configFile.reload()
    }

    FileView {
        id: configFile

        path: `${Quickshell.env("HOME")}/.config/zetshell/dashboard.json`

        onLoaded: {
            const raw = text().trim();
            if (!raw)
                return;

            try {
                root.applyConfig(JSON.parse(raw));
            } catch (error) {
                console.warn("Failed to parse dashboard config:", error);
            }
        }
    }
}
