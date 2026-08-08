import QtQuick

Item {
    id: root

    property bool open: false
    property string activeSection: "audio"
    property bool routeToDashboard: true
    property QtObject dashboardService: null
    readonly property var sections: ["audio", "network", "display", "wallpaper", "system"]

    function dashboardTab(section) {
        if (sections.indexOf(section) === -1)
            return "home";
        return section;
    }

    function toggle() {
        if (routeToDashboard && dashboardService) {
            if (dashboardService.open && sections.indexOf(dashboardService.activeTab) !== -1)
                dashboardService.close();
            else
                dashboardService.openTab(dashboardTab(activeSection));
            return;
        }

        root.open = !root.open;
    }

    function close() {
        root.open = false;
        if (routeToDashboard && dashboardService && sections.indexOf(dashboardService.activeTab) !== -1)
            dashboardService.close();
    }

    function openSection(section) {
        if (root.sections.indexOf(section) === -1)
            return;

        root.activeSection = section;
        if (routeToDashboard && dashboardService) {
            root.open = false;
            dashboardService.openTab(dashboardTab(section));
            return;
        }

        root.open = true;
    }

    function cycleSection(delta) {
        const currentIndex = root.sections.indexOf(root.activeSection);
        const count = root.sections.length;
        const nextIndex = (currentIndex + delta + count) % count;
        root.activeSection = root.sections[nextIndex];
        root.open = true;
    }
}
