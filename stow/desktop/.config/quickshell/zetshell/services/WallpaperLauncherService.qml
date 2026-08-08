import QtQuick

Item {
    id: root

    property bool open: false
    property string filter: "all"
    readonly property var filters: ["all", "recent", "favorites"]

    function toggle() {
        root.open = !root.open;
    }

    function close() {
        root.open = false;
    }

    function openLauncher(nextFilter) {
        if (nextFilter && filters.indexOf(nextFilter) !== -1)
            root.filter = nextFilter;
        root.open = true;
    }

    function setFilter(nextFilter) {
        if (filters.indexOf(nextFilter) === -1)
            return;

        root.filter = nextFilter;
    }

    function cycleFilter(delta) {
        const currentIndex = filters.indexOf(root.filter);
        const count = filters.length;
        const nextIndex = (currentIndex + delta + count) % count;
        root.filter = filters[nextIndex];
    }
}
