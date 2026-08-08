#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(CDPATH= cd "${SCRIPT_DIR}/../.." && pwd)
SETTINGS="${REPO_ROOT}/stow/desktop/.config/hypr/hyprland/settings.lua"
ENVIRONMENT="${REPO_ROOT}/stow/desktop/.config/hypr/hyprland/environment.lua"
SHELL_QML="${REPO_ROOT}/stow/desktop/.config/quickshell/zetshell/shell.qml"
DASHBOARD_QML="${REPO_ROOT}/stow/desktop/.config/quickshell/zetshell/modules/dashboard/Dashboard.qml"
BAR_QML="${REPO_ROOT}/stow/desktop/.config/quickshell/zetshell/modules/bar/Bar.qml"
WALLPAPER_LAUNCHER_QML="${REPO_ROOT}/stow/desktop/.config/quickshell/zetshell/modules/wallpaperlauncher/WallpaperLauncher.qml"
QUICKSHELL_ROOT="${REPO_ROOT}/stow/desktop/.config/quickshell/zetshell"

qml_component_block() {
    local component="$1"
    local file="$2"

    awk -v component="${component}" '
        $0 ~ "^[[:space:]]*" component "[[:space:]]*\\{" {
            inside = 1
        }
        inside {
            print
            opens = gsub(/\{/, "{")
            closes = gsub(/\}/, "}")
            depth += opens - closes
            if (depth == 0) {
                exit
            }
        }
    ' "${file}"
}

if rg -q 'main_monitor\s*=\s*"DP-|sub_monitor\s*=\s*"HDMI-' "${SETTINGS}"; then
    echo "FAIL: public Hyprland defaults must not require specific monitor connectors" >&2
    exit 1
fi
if ! rg -q 'settings\.nvidia' "${ENVIRONMENT}"; then
    echo "FAIL: NVIDIA environment variables should be opt-in" >&2
    exit 1
fi
if rg -q 'mainMonitorName:\s*"DP-' "${SHELL_QML}"; then
    echo "FAIL: Quickshell should choose an available monitor dynamically" >&2
    exit 1
fi
if ! rg -q 'Quickshell\.screens' "${SHELL_QML}"; then
    echo "FAIL: Quickshell should fall back to a detected screen" >&2
    exit 1
fi
network_service_count=$(rg -l 'Services\.NetworkService\s*\{' \
    "${REPO_ROOT}/stow/desktop/.config/quickshell/zetshell" | wc -l)
if [ "${network_service_count}" -ne 1 ]; then
    echo "FAIL: Quickshell should share exactly one NetworkService instance" >&2
    exit 1
fi
if ! rg -q 'readonly property QtObject network:\s*networkService' "${DASHBOARD_QML}"; then
    echo "FAIL: Dashboard network references should resolve to the shared service" >&2
    exit 1
fi

session_services=(
    Clock
    Music
    Lyrics
    SystemStats
    Weather
    DashboardInfo
    Volume
    Brightness
    Wallpaper
    Update
    System
    Ime
)
for service in "${session_services[@]}"; do
    service_count=$(rg -n "Services\\.${service}Service\\s*\\{" "${QUICKSHELL_ROOT}" | wc -l)
    if [ "${service_count}" -ne 1 ]; then
        echo "FAIL: Quickshell should declare exactly one ${service}Service instance" >&2
        exit 1
    fi
    if ! rg -q "Services\\.${service}Service\\s*\\{" "${SHELL_QML}"; then
        echo "FAIL: ${service}Service should be owned by shell.qml" >&2
        exit 1
    fi
done

bar_delegate=$(qml_component_block "BarModule.Bar" "${SHELL_QML}")
dashboard_delegate=$(qml_component_block "DashboardModule.Dashboard" "${SHELL_QML}")
wallpaper_delegate=$(qml_component_block \
    "WallpaperLauncherModule.WallpaperLauncher" \
    "${SHELL_QML}")

bar_services=(clock stats volume updates music ime)
for service in "${bar_services[@]}"; do
    if ! printf '%s\n' "${bar_delegate}" \
        | rg -q "^[[:space:]]*${service}:[[:space:]]*${service}State$"; then
        echo "FAIL: Bar should receive the shared ${service} service" >&2
        exit 1
    fi
    if ! rg -q "required property QtObject ${service}" "${BAR_QML}"; then
        echo "FAIL: Bar should declare an injectable ${service} service property" >&2
        exit 1
    fi
done

dashboard_services=(clock music lyrics stats weather info volume brightness wallpapers updates systemActions)
for service in "${dashboard_services[@]}"; do
    if ! printf '%s\n' "${dashboard_delegate}" \
        | rg -q "^[[:space:]]*${service}:[[:space:]]*${service}State$"; then
        echo "FAIL: Dashboard should receive the shared ${service} service" >&2
        exit 1
    fi
    if ! rg -q "required property QtObject ${service}" "${DASHBOARD_QML}"; then
        echo "FAIL: Dashboard should declare an injectable ${service} service property" >&2
        exit 1
    fi
done

if ! printf '%s\n' "${wallpaper_delegate}" \
    | rg -q '^[[:space:]]*wallpapers:[[:space:]]*wallpapersState$'; then
    echo "FAIL: WallpaperLauncher should receive the shared wallpaper service" >&2
    exit 1
fi
if ! rg -q 'required property QtObject wallpapers' "${WALLPAPER_LAUNCHER_QML}"; then
    echo "FAIL: WallpaperLauncher should declare an injectable wallpaper service property" >&2
    exit 1
fi

echo "desktop portability tests passed"
