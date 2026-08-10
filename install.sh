#!/usr/bin/env bash

set -eu

SCRIPT_DIR=$(CDPATH= cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DOTFILES_DIR="${SCRIPT_DIR}"
WIN32YANK_VERSION="0.1.1"
WIN32YANK_SHA256="247c9a05b94387a884b49d3db13f806b1677dfc38020f955f719be6902260cd6"

# --- 0. 引数パース ---

WITH_TEX=0
MINIMAL=0
WITH_KOMOREBI=0
WITH_GLAZEWM=0
WITH_NVIDIA=0
LINK_ONLY=0
DRY_RUN=0
CONTAINER_BACKEND=auto
for arg in "$@"; do
    case "$arg" in
        --with-tex) WITH_TEX=1 ;;
        --minimal) MINIMAL=1 ;;
        --with-komorebi) WITH_KOMOREBI=1 ;;
        --with-glazewm) WITH_GLAZEWM=1 ;;
        --with-nvidia) WITH_NVIDIA=1 ;;
        --link-only) LINK_ONLY=1 ;;
        --dry-run) DRY_RUN=1 ;;
        --container-backend=auto) CONTAINER_BACKEND=auto ;;
        --container-backend=desktop) CONTAINER_BACKEND=desktop ;;
        --container-backend=native) CONTAINER_BACKEND=native ;;
        --container-backend=none) CONTAINER_BACKEND=none ;;
        --container-backend=*)
            echo "Container backend must be auto, desktop, native, or none." >&2
            exit 1
            ;;
        *) echo "Unknown option: $arg" >&2; exit 1 ;;
    esac
done

if [ "${WITH_KOMOREBI}" -eq 1 ] && [ "${WITH_GLAZEWM}" -eq 1 ]; then
    echo "Choose only one Windows window manager." >&2
    exit 1
fi

link_dotfiles() {
    echo "Initializing local configuration..."
    "${DOTFILES_DIR}/scripts/init-local-config.sh"
    echo "Linking dotfiles with Stow..."
    DOTFILES_DIR="${DOTFILES_DIR}" "${DOTFILES_DIR}/scripts/stow-dotfiles.sh"
}

install_mise_tools() {
    echo "Installing mise-managed development tools..."
    (
        cd "${DOTFILES_DIR}"
        mise install
    )
}

install_herdr_integration() {
    echo "Installing the Herdr Codex integration..."
    (
        cd "${DOTFILES_DIR}"
        mise exec -- herdr integration install codex
    )
}

if [ "${LINK_ONLY}" -eq 1 ] && [ "${DRY_RUN}" -eq 1 ]; then
    echo "Install plan"
    echo "Mode: link-only"
    echo "Dotfile linking: base desktop assistant"
    echo "Local configuration: initialize missing files"
    exit 0
fi

if [ "${LINK_ONLY}" -eq 1 ]; then
    link_dotfiles
    echo "Link-only installation complete."
    exit 0
fi

# --- 1. OS判定 (Arch系) + 環境判定 (desktop/wsl) ---

if [ ! -r /etc/os-release ]; then
  echo "Cannot read /etc/os-release"
  exit 1
fi

# shellcheck disable=SC1091
. /etc/os-release

# Arch系判定: 公式Arch(ID=arch) / ALARM(ID=archarm) / ID_LIKE=arch を許可
if [[ "${ID:-}" != "arch" && "${ID:-}" != "archarm" && "${ID_LIKE:-}" != *"arch"* ]]; then
  echo "This script requires an Arch-based Linux (arch/archarm). Detected: ID=${ID:-?}, ID_LIKE=${ID_LIKE:-?}"
  exit 1
fi

# Environment variables are not trusted as platform evidence.
ENV=$("${DOTFILES_DIR}/scripts/detect-install-environment.sh")

echo "Detected environment: ${PRETTY_NAME:-Arch Linux} (${ENV})"

ARCHITECTURE=$(uname -m)
"${DOTFILES_DIR}/scripts/validate-install-target.sh" \
    "${ENV}" "${ARCHITECTURE}" "${WITH_NVIDIA}" "${MINIMAL}"

CONTAINER_BACKEND=$("${DOTFILES_DIR}/scripts/resolve-container-backend.sh" \
    "${ENV}" "${CONTAINER_BACKEND}")

profile_output=$("${DOTFILES_DIR}/scripts/resolve-package-profiles.sh" \
    "${ENV}" "${MINIMAL}" "${CONTAINER_BACKEND}" \
    "${WITH_NVIDIA}" "${WITH_TEX}")
mapfile -t PACKAGE_PROFILES <<<"${profile_output}"

for profile in "${PACKAGE_PROFILES[@]}"; do
    if [ ! -f "${DOTFILES_DIR}/packages/${profile}" ]; then
        echo "Required package profile is missing: ${DOTFILES_DIR}/packages/${profile}" >&2
        exit 1
    fi
done

if [ "${DRY_RUN}" -eq 1 ]; then
    echo "Install plan"
    echo "Environment: ${ENV}"
    echo "Architecture: ${ARCHITECTURE}"
    echo "Container backend: ${CONTAINER_BACKEND}"
    for profile in "${PACKAGE_PROFILES[@]}"; do
        echo "Package profile: ${profile}"
    done
    echo "System upgrade: yes"
    echo "Dotfile linking: base desktop assistant"
    if [ "${ENV}" = "wsl" ]; then
        echo "Windows integration: wezterm kanata"
    fi
    exit 0
fi

"${DOTFILES_DIR}/scripts/validate-container-backend.sh" \
    "${ENV}" "${CONTAINER_BACKEND}"

# --- 2. パッケージインストール (common + 環境固有) ---

if ! command -v yay &>/dev/null; then
    echo "The full bootstrap requires an existing yay installation." >&2
    echo "Install and review an AUR helper separately, or use --link-only." >&2
    exit 1
fi

install_packages() {
    local file="$1"
    local pkgs
    if [ ! -f "$file" ]; then
        echo "Required package profile is missing: ${file}" >&2
        return 1
    fi
    pkgs=$(grep -v '^\s*#' "$file" | grep -v '^\s*$' || true)
    if [ -n "$pkgs" ]; then
        printf '%s\n' "$pkgs" | yay -S --needed -
    else
        echo "No packages listed in ${file}, skipping."
    fi
}

yay -Syu

for profile in "${PACKAGE_PROFILES[@]}"; do
    if [ "${profile}" = "tex.txt" ]; then
        echo "Installing TeX Live packages..."
    fi
    install_packages "${DOTFILES_DIR}/packages/${profile}"
done

# --- 3. Dotfiles Linking (Stow) ---
link_dotfiles
install_mise_tools
install_herdr_integration

# --- 6. WSL固有設定 ---

if [ "${ENV}" = "wsl" ]; then
    echo "Applying WSL specific settings..."

    # install Windows-side terminal fonts and deploy the managed WezTerm config
    WEZTERM_INSTALLER="${DOTFILES_DIR}/windows/wezterm/install.ps1"
    if [ -f "${WEZTERM_INSTALLER}" ]; then
        WIN_PS="$(wslpath -w "${WEZTERM_INSTALLER}")"
        powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$WIN_PS"
    fi

    # install win32yank to home/bin (clipboard bridge for neovim)
    if [ ! -f "${HOME}/bin/win32yank.exe" ]; then
        echo "installing win32yank.exe to ${HOME}/bin"
        mkdir -p "${HOME}/bin"
        win32yank_zip=$(mktemp --suffix=.zip)
        curl -fsSL -o "$win32yank_zip" \
            "https://github.com/equalsraf/win32yank/releases/download/v${WIN32YANK_VERSION}/win32yank-x64.zip"
        printf '%s  %s\n' "${WIN32YANK_SHA256}" "${win32yank_zip}" \
            | sha256sum --check --status
        unzip -o "$win32yank_zip" win32yank.exe -d "${HOME}/bin"
        chmod +x "${HOME}/bin/win32yank.exe"
        rm -f "$win32yank_zip"
    fi

    # SumatraPDF (vimtex viewer)
    if ! command -v SumatraPDF.exe &>/dev/null; then
        echo "installing SumatraPDF via winget..."
        powershell.exe -NoProfile -Command \
            "winget install --id SumatraPDF.SumatraPDF -e --silent --accept-source-agreements --accept-package-agreements" \
            || echo "winget install failed (maybe already installed)"

        WIN_LOCALAPPDATA="$(powershell.exe -NoProfile -Command 'Write-Output $Env:LOCALAPPDATA' | tr -d '\r')"
        LOCALAPPDATA_WSL="$(wslpath "$WIN_LOCALAPPDATA")"
        SUMATRA_EXE="${LOCALAPPDATA_WSL}/Programs/SumatraPDF/SumatraPDF.exe"

        if [ -f "$SUMATRA_EXE" ]; then
            mkdir -p "${HOME}/bin"
            ln -sf "$SUMATRA_EXE" "${HOME}/bin/SumatraPDF.exe"
            echo "linked SumatraPDF.exe to ~/bin"
        else
            echo "warning: SumatraPDF.exe not found at $SUMATRA_EXE" >&2
        fi
    fi

    # install kanata (keyboard remapper on the Windows side)
    if [ -f "${DOTFILES_DIR}/windows/kanata/install.ps1" ]; then
        WIN_PS="$(wslpath -w "${DOTFILES_DIR}/windows/kanata/install.ps1")"
        KANATA_ARGS=()
        if [ "${KANATA_ADD_DEFENDER_EXCLUSION:-0}" = "1" ]; then
            KANATA_ARGS+=("-AddDefenderExclusion")
        fi
        powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$WIN_PS" "${KANATA_ARGS[@]}"
    fi

    # install Komorebi only when explicitly requested
    if [ "${WITH_KOMOREBI}" -eq 1 ]; then
        KOMOREBI_INSTALLER="${DOTFILES_DIR}/windows/komorebi/install.ps1"
        if [ ! -f "${KOMOREBI_INSTALLER}" ]; then
            echo "Komorebi installer not found: ${KOMOREBI_INSTALLER}" >&2
            exit 1
        fi
        WSLPATH_BIN="/usr/bin/wslpath"
        WINDOWS_POWERSHELL="/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
        if [ ! -x "${WSLPATH_BIN}" ] || [ ! -f "${WINDOWS_POWERSHELL}" ]; then
            echo "Trusted WSL/PowerShell bridge not found." >&2
            exit 1
        fi
        WIN_PS="$("${WSLPATH_BIN}" -w "${KOMOREBI_INSTALLER}")"
        "${WINDOWS_POWERSHELL}" -NoProfile -ExecutionPolicy Bypass -File "$WIN_PS"
    fi

    # install GlazeWM only when explicitly requested
    if [ "${WITH_GLAZEWM}" -eq 1 ]; then
        GLAZEWM_INSTALLER="${DOTFILES_DIR}/windows/glazewm/install.ps1"
        if [ ! -f "${GLAZEWM_INSTALLER}" ]; then
            echo "GlazeWM installer not found: ${GLAZEWM_INSTALLER}" >&2
            exit 1
        fi
        WSLPATH_BIN="/usr/bin/wslpath"
        WINDOWS_POWERSHELL="/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
        if [ ! -x "${WSLPATH_BIN}" ] || [ ! -f "${WINDOWS_POWERSHELL}" ]; then
            echo "Trusted WSL/PowerShell bridge not found." >&2
            exit 1
        fi
        WIN_PS="$("${WSLPATH_BIN}" -w "${GLAZEWM_INSTALLER}")"
        "${WINDOWS_POWERSHELL}" -NoProfile -ExecutionPolicy Bypass -File "$WIN_PS"
    fi
fi

echo "Installation Complete!"
