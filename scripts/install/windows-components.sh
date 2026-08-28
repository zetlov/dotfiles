#!/usr/bin/env bash

WINDOWS_PWSH_BIN="/mnt/c/Program Files/PowerShell/7/pwsh.exe"
WINDOWS_POWERSHELL_BIN="/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"

ensure_windows_powershell() {
    if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
        echo "ensure_windows_powershell received an invalid argument count." >&2
        return 1
    fi
    local pwsh_bin="$1"
    local powershell_bin="${2:-${WINDOWS_POWERSHELL_BIN}}"
    if [ -f "${pwsh_bin}" ]; then
        return 0
    fi
    if [ ! -f "${powershell_bin}" ]; then
        echo "Windows PowerShell was not found: ${powershell_bin}" >&2
        return 1
    fi

    echo "Installing PowerShell 7 via WinGet..."
    if ! "${powershell_bin}" \
        -NoProfile -NonInteractive -ExecutionPolicy Bypass \
        -Command '& "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe" install --id Microsoft.PowerShell --exact --source winget --installer-type wix --silent --disable-interactivity --accept-source-agreements --accept-package-agreements'; then
        echo "WinGet failed to install PowerShell 7." >&2
        return 1
    fi
    if [ ! -f "${pwsh_bin}" ]; then
        echo "PowerShell 7 was not installed at the expected path: ${pwsh_bin}" >&2
        return 1
    fi
}

validate_windows_component_flag() {
    local name="$1"
    local value="$2"
    if [ "${value}" != "0" ] && [ "${value}" != "1" ]; then
        echo "${name} must be 0 or 1." >&2
        return 1
    fi
}

validate_windows_additional_component() {
    case "$1" in
        ""|glazewm|monitor-profiles|glazewm,monitor-profiles|komorebi|komorebi,monitor-profiles) ;;
        *)
            echo "Unsupported additional Windows component: $1" >&2
            return 1
            ;;
    esac
}

is_windows_rollback_component_selected() {
    case "$1" in
        komorebi|komorebi,monitor-profiles) return 0 ;;
        *) return 1 ;;
    esac
}

resolve_windows_components() {
    if [ "$#" -ne 3 ]; then
        echo "resolve_windows_components requires GlazeWM, Komorebi, and monitor profile flags." >&2
        return 1
    fi
    validate_windows_component_flag "GlazeWM flag" "$1" || return 1
    validate_windows_component_flag "Komorebi flag" "$2" || return 1
    validate_windows_component_flag "Monitor profile flag" "$3" || return 1
    if [ "$1" = "1" ] && [ "$2" = "1" ]; then
        echo "GlazeWM and Komorebi cannot be selected together." >&2
        return 1
    fi
    local window_manager=""
    if [ "$1" = "1" ]; then
        window_manager="glazewm"
    elif [ "$2" = "1" ]; then
        window_manager="komorebi"
    fi
    if [ "$3" = "1" ]; then
        if [ -n "${window_manager}" ]; then
            printf '%s\n' "${window_manager},monitor-profiles"
        else
            printf '%s\n' monitor-profiles
        fi
    elif [ -n "${window_manager}" ]; then
        printf '%s\n' "${window_manager}"
    fi
}

resolve_windows_prerequisite_component() {
    if [ "$#" -ne 1 ]; then
        echo "resolve_windows_prerequisite_component requires a container backend." >&2
        return 1
    fi
    case "$1" in
        desktop) printf '%s\n' docker-desktop ;;
        native|none) ;;
        *)
            echo "Unsupported container backend for Windows prerequisites: $1" >&2
            return 1
            ;;
    esac
}

validate_windows_prerequisite_component() {
    case "$1" in
        docker-desktop) ;;
        *)
            echo "Unsupported Windows prerequisite component: $1" >&2
            return 1
            ;;
    esac
}

resolve_windows_installer_path() {
    local dotfiles_dir="$1"
    local wslpath_bin="$2"
    local pwsh_bin="$3"
    local installer="${dotfiles_dir}/windows/install.ps1"
    if [ ! -f "${installer}" ]; then
        echo "Windows root installer not found: ${installer}" >&2
        return 1
    fi
    if [ ! -x "${wslpath_bin}" ]; then
        echo "Trusted wslpath executable not found: ${wslpath_bin}" >&2
        return 1
    fi
    if [ ! -f "${pwsh_bin}" ]; then
        echo "Trusted PowerShell 7 executable not found: ${pwsh_bin}" >&2
        echo "Install it on Windows with: winget install --id Microsoft.PowerShell --source winget --installer-type wix" >&2
        return 1
    fi
    local windows_installer
    windows_installer=$("${wslpath_bin}" -w "${installer}")
    if [ -z "${windows_installer}" ]; then
        echo "wslpath returned an empty Windows installer path." >&2
        return 1
    fi
    printf '%s\n' "${windows_installer}"
}

preflight_windows_components() {
    if [ "$#" -lt 2 ] || [ "$#" -gt 4 ]; then
        echo "preflight_windows_components received an invalid argument count." >&2
        return 1
    fi
    local dotfiles_dir="$1"
    local additional_component="$2"
    local wslpath_bin="${3:-/usr/bin/wslpath}"
    local pwsh_bin="${4:-${WINDOWS_PWSH_BIN}}"
    validate_windows_additional_component "${additional_component}" || return 1
    local windows_installer
    windows_installer=$(resolve_windows_installer_path \
        "${dotfiles_dir}" "${wslpath_bin}" "${pwsh_bin}") || return 1
    local -a argv=(
        -NoProfile -ExecutionPolicy Bypass -File "${windows_installer}"
        -Mode Install -Preflight
    )
    if [ -n "${additional_component}" ]; then
        argv+=(-AdditionalComponentCsv "${additional_component}")
    fi
    if is_windows_rollback_component_selected "${additional_component}"; then
        argv+=(-AllowRollbackOnly)
    fi
    "${pwsh_bin}" "${argv[@]}"
}

preflight_windows_prerequisite_component() {
    if [ "$#" -lt 2 ] || [ "$#" -gt 4 ]; then
        echo "preflight_windows_prerequisite_component received an invalid argument count." >&2
        return 1
    fi
    local dotfiles_dir="$1"
    local component="$2"
    local wslpath_bin="${3:-/usr/bin/wslpath}"
    local pwsh_bin="${4:-${WINDOWS_PWSH_BIN}}"
    validate_windows_prerequisite_component "${component}" || return 1
    local windows_installer
    windows_installer=$(resolve_windows_installer_path \
        "${dotfiles_dir}" "${wslpath_bin}" "${pwsh_bin}") || return 1
    "${pwsh_bin}" \
        -NoProfile -ExecutionPolicy Bypass -File "${windows_installer}" \
        -Mode Install -Preflight -ComponentCsv "${component}"
}

apply_windows_prerequisite_component() {
    if [ "$#" -lt 2 ] || [ "$#" -gt 4 ]; then
        echo "apply_windows_prerequisite_component received an invalid argument count." >&2
        return 1
    fi
    local dotfiles_dir="$1"
    local component="$2"
    local wslpath_bin="${3:-/usr/bin/wslpath}"
    local pwsh_bin="${4:-${WINDOWS_PWSH_BIN}}"
    validate_windows_prerequisite_component "${component}" || return 1
    local windows_installer
    windows_installer=$(resolve_windows_installer_path \
        "${dotfiles_dir}" "${wslpath_bin}" "${pwsh_bin}") || return 1
    "${pwsh_bin}" \
        -NoProfile -ExecutionPolicy Bypass -File "${windows_installer}" \
        -Mode Install -ComponentCsv "${component}"
}

apply_windows_components() {
    if [ "$#" -lt 3 ] || [ "$#" -gt 5 ]; then
        echo "apply_windows_components received an invalid argument count." >&2
        return 1
    fi
    local dotfiles_dir="$1"
    local additional_component="$2"
    local add_defender_exclusion="$3"
    local wslpath_bin="${4:-/usr/bin/wslpath}"
    local pwsh_bin="${5:-${WINDOWS_PWSH_BIN}}"
    validate_windows_additional_component "${additional_component}" || return 1
    validate_windows_component_flag \
        "Defender exclusion flag" "${add_defender_exclusion}" || return 1
    local windows_installer
    windows_installer=$(resolve_windows_installer_path \
        "${dotfiles_dir}" "${wslpath_bin}" "${pwsh_bin}") || return 1
    local -a argv=(
        -NoProfile -ExecutionPolicy Bypass -File "${windows_installer}"
        -Mode Install
    )
    if [ -n "${additional_component}" ]; then
        argv+=(-AdditionalComponentCsv "${additional_component}")
    fi
    if is_windows_rollback_component_selected "${additional_component}"; then
        argv+=(-AllowRollbackOnly)
    fi
    if [ "${add_defender_exclusion}" = "1" ]; then
        argv+=(-AddKanataDefenderExclusion)
    fi
    "${pwsh_bin}" "${argv[@]}"
}
