#!/usr/bin/env bash

readonly WIN32YANK_VERSION="0.1.1"
readonly WIN32YANK_SHA256="247c9a05b94387a884b49d3db13f806b1677dfc38020f955f719be6902260cd6"

install_win32yank() {
    local home_dir="$1"
    local curl_bin="${2:-}"
    local target_path="${home_dir}/bin/win32yank.exe"
    local archive_path
    local status=0

    if [ -f "${target_path}" ]; then
        return
    fi
    if [ -z "${curl_bin}" ]; then
        curl_bin=$(command -v curl || true)
    fi
    if [ ! -d "${home_dir}" ]; then
        echo "WSL HOME must be an existing directory: ${home_dir}" >&2
        return 1
    fi
    if [ ! -x "${curl_bin}" ]; then
        echo "win32yank installation requires an executable curl binary." >&2
        return 1
    fi
    if ! archive_path=$(mktemp --suffix=.zip); then
        echo "Unable to create a temporary win32yank archive." >&2
        return 1
    fi

    echo "Installing win32yank.exe to ${home_dir}/bin"
    if ! "${curl_bin}" -fsSL -o "${archive_path}" \
        "https://github.com/equalsraf/win32yank/releases/download/v${WIN32YANK_VERSION}/win32yank-x64.zip"; then
        echo "win32yank download failed." >&2
        status=1
    elif ! printf '%s  %s\n' "${WIN32YANK_SHA256}" "${archive_path}" \
        | sha256sum --check --status; then
        echo "win32yank archive integrity check failed." >&2
        status=1
    elif ! mkdir -p "${home_dir}/bin"; then
        echo "Unable to create the WSL user bin directory." >&2
        status=1
    elif ! unzip -o "${archive_path}" win32yank.exe -d "${home_dir}/bin"; then
        echo "win32yank extraction failed." >&2
        status=1
    elif ! chmod +x "${target_path}"; then
        echo "Unable to mark win32yank as executable." >&2
        status=1
    fi

    if ! rm -f -- "${archive_path}"; then
        echo "Unable to remove the temporary win32yank archive." >&2
        return 1
    fi
    return "${status}"
}

install_sumatra_pdf() {
    local home_dir="$1"
    local pwsh_bin="$2"
    local wslpath_bin="${3:-/usr/bin/wslpath}"
    local windows_local_app_data
    local local_app_data_wsl
    local sumatra_executable

    if command -v SumatraPDF.exe >/dev/null 2>&1; then
        return
    fi
    if [ ! -x "${pwsh_bin}" ] || [ ! -x "${wslpath_bin}" ]; then
        echo "SumatraPDF integration requires PowerShell 7 and wslpath." >&2
        return 1
    fi

    echo "Installing SumatraPDF via winget..."
    if ! "${pwsh_bin}" -NoProfile -Command \
        "winget install --id SumatraPDF.SumatraPDF -e --silent --accept-source-agreements --accept-package-agreements"; then
        echo "winget install failed; checking for an existing installation." >&2
    fi
    if ! windows_local_app_data=$("${pwsh_bin}" -NoProfile \
        -Command 'Write-Output $Env:LOCALAPPDATA'); then
        echo "Unable to resolve Windows LOCALAPPDATA." >&2
        return 1
    fi
    windows_local_app_data=${windows_local_app_data//$'\r'/}
    if ! local_app_data_wsl=$("${wslpath_bin}" "${windows_local_app_data}"); then
        echo "Unable to convert Windows LOCALAPPDATA to a WSL path." >&2
        return 1
    fi
    sumatra_executable="${local_app_data_wsl}/Programs/SumatraPDF/SumatraPDF.exe"

    if [ ! -f "${sumatra_executable}" ]; then
        echo "warning: SumatraPDF.exe not found at ${sumatra_executable}" >&2
        return
    fi
    if ! mkdir -p "${home_dir}/bin" \
        || ! ln -sf "${sumatra_executable}" "${home_dir}/bin/SumatraPDF.exe"; then
        echo "Unable to link SumatraPDF.exe into the WSL user bin directory." >&2
        return 1
    fi
    echo "Linked SumatraPDF.exe to ${home_dir}/bin"
}

apply_wsl_extras() {
    local home_dir="$1"
    local pwsh_bin="$2"

    echo "Applying WSL specific settings..."
    install_win32yank "${home_dir}" || return 1
    install_sumatra_pdf "${home_dir}" "${pwsh_bin}" || return 1
}
