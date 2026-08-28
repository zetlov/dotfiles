#!/usr/bin/env bash

WINDOWS_PWSH_BIN="/mnt/c/Program Files/PowerShell/7/pwsh.exe"

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
        ""|glazewm,monitor-profiles|komorebi) ;;
        *)
            echo "Unsupported additional Windows component: $1" >&2
            return 1
            ;;
    esac
}

resolve_windows_components() {
    if [ "$#" -ne 2 ]; then
        echo "resolve_windows_components requires GlazeWM and Komorebi flags." >&2
        return 1
    fi
    validate_windows_component_flag "GlazeWM flag" "$1" || return 1
    validate_windows_component_flag "Komorebi flag" "$2" || return 1
    if [ "$1" = "1" ] && [ "$2" = "1" ]; then
        echo "GlazeWM and Komorebi cannot be selected together." >&2
        return 1
    fi
    if [ "$1" = "1" ]; then
        printf '%s\n' glazewm,monitor-profiles
    elif [ "$2" = "1" ]; then
        printf '%s\n' komorebi
    fi
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
    if [ "${additional_component}" = "komorebi" ]; then
        argv+=(-AllowRollbackOnly)
    fi
    "${pwsh_bin}" "${argv[@]}"
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
    if [ "${additional_component}" = "komorebi" ]; then
        argv+=(-AllowRollbackOnly)
    fi
    if [ "${add_defender_exclusion}" = "1" ]; then
        argv+=(-AddKanataDefenderExclusion)
    fi
    "${pwsh_bin}" "${argv[@]}"
}
