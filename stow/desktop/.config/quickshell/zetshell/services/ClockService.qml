import QtQuick
import Quickshell

Item {
    id: root

    readonly property string dateText: Qt.formatDateTime(clock.date, "yyyy/MM/dd (ddd)")
    readonly property string timeText: Qt.formatDateTime(clock.date, "HH:mm:ss")

    SystemClock {
        id: clock

        precision: SystemClock.Seconds
    }
}
