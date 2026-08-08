import QtQuick

Item {
    id: root

    property bool open: false
    property string activeSection: "screenshot"
    readonly property var sections: ["screenshot", "record"]

    function normalizeSection(section) {
        if (sections.indexOf(section) !== -1)
            return section;

        return "screenshot";
    }

    function toggle() {
        open = !open;
    }

    function close() {
        open = false;
    }

    function openLauncher(section) {
        activeSection = normalizeSection(section || activeSection);
        open = true;
    }

    function openScreenshot() {
        openLauncher("screenshot");
    }

    function openRecord() {
        openLauncher("record");
    }

    function cycleSection(delta) {
        const currentIndex = sections.indexOf(activeSection);
        const nextIndex = (currentIndex + delta + sections.length) % sections.length;
        activeSection = sections[nextIndex];
    }

}
