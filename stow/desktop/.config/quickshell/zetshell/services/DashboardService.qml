import QtQuick

Item {
    id: root

    property QtObject config: null
    property bool open: false
    property string activeTab: "home"
    readonly property var tabs: {
        const items = ["home"];
        if (!config || config.showMedia)
            items.push("media");

        if (!config || config.showPerformance)
            items.push("performance");

        if (!config || config.showWeather)
            items.push("weather");

        if (!config || config.showActions)
            items.push("actions");

        items.push("audio");
        items.push("network");
        items.push("display");
        items.push("wallpaper");
        items.push("system");
        items.push("settings");
        return items;
    }

    function toggle() {
        if (config && !config.dashboardEnabled)
            return ;

        root.open = !root.open;
    }

    function toggleHome() {
        if (config && !config.dashboardEnabled)
            return ;

        if (root.open && root.activeTab === "home") {
            root.open = false;
            return ;
        }
        root.activeTab = "home";
        root.open = true;
    }

    function close() {
        root.open = false;
    }

    function openTab(tab) {
        if (config && !config.dashboardEnabled)
            return ;

        if (root.tabs.indexOf(tab) === -1)
            return ;

        root.activeTab = tab;
        root.open = true;
    }

    function cycleTab(delta) {
        const currentIndex = Math.max(0, root.tabs.indexOf(root.activeTab));
        const count = root.tabs.length;
        root.activeTab = root.tabs[(currentIndex + delta + count) % count];
        root.open = true;
    }

    onTabsChanged: {
        if (tabs.indexOf(activeTab) === -1)
            activeTab = tabs[0] || "home";

    }
}
