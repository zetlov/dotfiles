//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1

import QtQuick
import Quickshell
import Quickshell.Io
import "modules/applauncher" as AppLauncherModule
import "modules/areapicker" as AreaPickerModule
import "modules/bar" as BarModule
import "modules/dashboard" as DashboardModule
import "modules/launcher" as LauncherModule
import "modules/notifications" as NotificationModule
import "modules/osd" as OsdModule
import "modules/wallpaperlauncher" as WallpaperLauncherModule
import "services" as Services

ShellRoot {
    id: root

    readonly property string mainMonitorName: Quickshell.screens.length > 0
        ? Quickshell.screens[0].name
        : ""

    Services.NotificationService {
        id: notificationsState
    }

    Services.NetworkService {
        id: networkState
    }

    Services.ControlCenterService {
        id: controlCenterState

        dashboardService: dashboardState
    }

    Services.DashboardConfigService {
        id: dashboardConfig
    }

    Services.FileSearchConfigService {
        id: fileSearchConfig
    }

    Services.DashboardService {
        id: dashboardState

        config: dashboardConfig
    }

    Services.AppLauncherService {
        id: appLauncherState
    }

    Services.WallpaperLauncherService {
        id: wallpaperLauncherState
    }

    Services.CaptureLauncherService {
        id: captureLauncherState
    }

    Services.CaptureService {
        id: captureState
    }

    Services.RecordService {
        id: recordState
    }

    Services.AreaPickerService {
        id: pickerState
    }

    Services.VolumeService {
        id: osdVolume
    }

    Services.BrightnessService {
        id: osdBrightness
    }

    Services.OsdService {
        id: osdState

        volume: osdVolume
        brightness: osdBrightness
    }

    IpcHandler {
        readonly property bool openState: appLauncherState.open

        function toggle() {
            appLauncherState.toggle();
        }

        function close() {
            appLauncherState.close();
        }

        function show() {
            appLauncherState.show();
        }

        function open(provider: string) {
            appLauncherState.openLauncher(provider);
        }

        target: "appLauncher"
    }

    IpcHandler {
        readonly property bool centerOpen: notificationsState.centerOpen

        function toggleCenter() {
            notificationsState.toggleCenter();
        }

        function closeCenter() {
            notificationsState.setCenterOpen(false);
        }

        target: "notifications"
    }

    IpcHandler {
        readonly property bool openState: controlCenterState.open
        readonly property string activeSection: controlCenterState.activeSection

        function toggle() {
            controlCenterState.toggle();
        }

        function close() {
            controlCenterState.close();
        }

        function open(section: string) {
            controlCenterState.openSection(section);
        }

        target: "controlCenter"
    }

    IpcHandler {
        readonly property bool openState: dashboardState.open
        readonly property string activeTab: dashboardState.activeTab

        function toggle() {
            dashboardState.toggle();
        }

        function toggleHome() {
            dashboardState.toggleHome();
        }

        function close() {
            dashboardState.close();
        }

        function open(tab: string) {
            dashboardState.openTab(tab);
        }

        target: "dashboard"
    }

    IpcHandler {
        readonly property bool openState: wallpaperLauncherState.open
        readonly property string filter: wallpaperLauncherState.filter

        function toggle() {
            wallpaperLauncherState.toggle();
        }

        function close() {
            wallpaperLauncherState.close();
        }

        function open(filter: string) {
            wallpaperLauncherState.openLauncher(filter);
        }

        target: "wallpaperLauncher"
    }

    IpcHandler {
        readonly property bool openState: captureLauncherState.open
        readonly property string activeSection: captureLauncherState.activeSection

        function toggle() {
            captureLauncherState.toggle();
        }

        function close() {
            captureLauncherState.close();
        }

        function open(section: string) {
            captureLauncherState.openLauncher(section);
        }

        target: "captureLauncher"
    }

    IpcHandler {
        readonly property bool openState: pickerState.open
        readonly property string mode: pickerState.mode
        readonly property string destination: pickerState.destination

        function close() {
            pickerState.close();
        }

        function open(mode: string, destination: string) {
            pickerState.openPicker(mode, destination);
        }

        target: "picker"
    }

    IpcHandler {
        readonly property bool recording: recordState.recording
        readonly property bool paused: recordState.paused

        function toggle(withAudio: bool) {
            recordState.toggleOutput(withAudio !== false);
        }

        function pause() {
            recordState.togglePause();
        }

        function stop() {
            recordState.stop();
        }

        function openLauncher() {
            captureLauncherState.openLauncher("record");
        }

        target: "record"
    }

    IpcHandler {
        readonly property bool openState: osdState.open
        readonly property string kind: osdState.kind
        readonly property int level: osdState.level

        function volumeStep(delta: int) {
            osdState.volumeStep(delta);
        }

        function volumeMute() {
            osdState.volumeMute();
        }

        function brightnessStep(delta: int) {
            osdState.brightnessStep(delta);
        }

        function showVolume() {
            osdState.showVolume();
        }

        function showBrightness() {
            osdState.showBrightness();
        }

        function close() {
            osdState.close();
        }

        target: "osd"
    }

    Variants {
        model: Quickshell.screens

        BarModule.Bar {
            required property var modelData

            screen: modelData
            screenNameHint: modelData.name
            targetMonitor: mainMonitorName
            notificationService: notificationsState
            controlCenterService: controlCenterState
            networkService: networkState
        }

    }

    Variants {
        model: Quickshell.screens

        OsdModule.Osd {
            required property var modelData

            screen: modelData
            screenNameHint: modelData.name
            targetMonitor: mainMonitorName
            osdService: osdState
        }

    }

    Variants {
        model: Quickshell.screens

        NotificationModule.ToastStack {
            required property var modelData

            screen: modelData
            screenNameHint: modelData.name
            targetMonitor: mainMonitorName
            notificationService: notificationsState
        }

    }

    Variants {
        model: Quickshell.screens

        DashboardModule.Dashboard {
            required property var modelData

            screen: modelData
            screenNameHint: modelData.name
            targetMonitor: mainMonitorName
            dashboardService: dashboardState
            configService: dashboardConfig
            fileSearchConfigService: fileSearchConfig
            networkService: networkState
        }

    }

    Variants {
        model: Quickshell.screens

        NotificationModule.NotificationCenter {
            required property var modelData

            screen: modelData
            screenNameHint: modelData.name
            targetMonitor: mainMonitorName
            notificationService: notificationsState
        }

    }

    Variants {
        model: Quickshell.screens

        AppLauncherModule.AppLauncher {
            required property var modelData

            screen: modelData
            screenNameHint: modelData.name
            targetMonitor: mainMonitorName
            launcherService: appLauncherState
        }

    }

    Variants {
        model: Quickshell.screens

        WallpaperLauncherModule.WallpaperLauncher {
            required property var modelData

            screen: modelData
            screenNameHint: modelData.name
            targetMonitor: mainMonitorName
            launcherService: wallpaperLauncherState
        }

    }

    Variants {
        model: Quickshell.screens

        LauncherModule.CaptureLauncher {
            required property var modelData

            screen: modelData
            screenNameHint: modelData.name
            targetMonitor: mainMonitorName
            launcherService: captureLauncherState
            captureService: captureState
            pickerService: pickerState
            recordService: recordState
        }

    }

    Variants {
        model: Quickshell.screens

        AreaPickerModule.AreaPicker {
            required property var modelData

            screen: modelData
            screenNameHint: modelData.name
            targetMonitor: ""
            pickerService: pickerState
            captureService: captureState
            recordService: recordState
        }

    }

}
