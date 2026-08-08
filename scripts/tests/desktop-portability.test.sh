#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(CDPATH= cd "${SCRIPT_DIR}/../.." && pwd)
SETTINGS="${REPO_ROOT}/stow/desktop/.config/hypr/hyprland/settings.lua"
ENVIRONMENT="${REPO_ROOT}/stow/desktop/.config/hypr/hyprland/environment.lua"
SHELL_QML="${REPO_ROOT}/stow/desktop/.config/quickshell/zetshell/shell.qml"
DASHBOARD_QML="${REPO_ROOT}/stow/desktop/.config/quickshell/zetshell/modules/dashboard/Dashboard.qml"

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

echo "desktop portability tests passed"
