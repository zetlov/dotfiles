#!/usr/bin/env bash

set -eu

SCRIPT_DIR=$(CDPATH= cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DOTFILES_DIR=$(CDPATH= cd "${SCRIPT_DIR}/../.." && pwd)
WIN32YANK_VERSION="0.1.1"
WIN32YANK_SHA256="247c9a05b94387a884b49d3db13f806b1677dfc38020f955f719be6902260cd6"

# shellcheck source=scripts/install/windows-components.sh
# shellcheck disable=SC1091
source "${DOTFILES_DIR}/scripts/install/windows-components.sh"
# shellcheck source=scripts/install/packages.sh
# shellcheck disable=SC1091
source "${DOTFILES_DIR}/scripts/install/packages.sh"

# --- 0. 引数パース ---

WITH_TEX=0
MINIMAL=0
WITH_KOMOREBI=0
WITH_GLAZEWM=0
WITH_NVIDIA=0
LINK_ONLY=0
DRY_RUN=0
SYSTEM_UPGRADE=0
CONTAINER_BACKEND=auto
STOW_PROFILE=auto
for arg in "$@"; do
    case "$arg" in
        --with-tex) WITH_TEX=1 ;;
        --minimal) MINIMAL=1 ;;
        --with-komorebi) WITH_KOMOREBI=1 ;;
        --with-glazewm) WITH_GLAZEWM=1 ;;
        --with-nvidia) WITH_NVIDIA=1 ;;
        --link-only) LINK_ONLY=1 ;;
        --dry-run) DRY_RUN=1 ;;
        --system-upgrade) SYSTEM_UPGRADE=1 ;;
        --container-backend=auto) CONTAINER_BACKEND=auto ;;
        --container-backend=desktop) CONTAINER_BACKEND=desktop ;;
        --container-backend=native) CONTAINER_BACKEND=native ;;
        --container-backend=none) CONTAINER_BACKEND=none ;;
        --profile=auto) STOW_PROFILE=auto ;;
        --profile=desktop) STOW_PROFILE=desktop ;;
        --profile=wsl) STOW_PROFILE=wsl ;;
        --profile=*)
            echo "Stow profile must be auto, desktop, or wsl." >&2
            exit 1
            ;;
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
    echo "Validating local configuration and Stow targets..."
    HOME="${HOME}" "${DOTFILES_DIR}/scripts/init-local-config.sh" \
        --dry-run "--profile=${STOW_PROFILE}" >/dev/null
    DOTFILES_DIR="${DOTFILES_DIR}" "${DOTFILES_DIR}/scripts/stow-dotfiles.sh" \
        "--profile=${STOW_PROFILE}" --preflight >/dev/null
    echo "Initializing local configuration..."
    "${DOTFILES_DIR}/scripts/init-local-config.sh" "--profile=${STOW_PROFILE}"
    echo "Linking dotfiles with Stow..."
    DOTFILES_DIR="${DOTFILES_DIR}" "${DOTFILES_DIR}/scripts/stow-dotfiles.sh" \
        "--profile=${STOW_PROFILE}"
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

if [ "${LINK_ONLY}" -eq 1 ] && [ "${STOW_PROFILE}" = "auto" ]; then
    STOW_PROFILE=desktop
fi

if [ "${LINK_ONLY}" -eq 1 ] && [ "${DRY_RUN}" -eq 1 ]; then
    echo "Install plan"
    echo "Mode: link-only"
    echo "Dotfile profile: ${STOW_PROFILE}"
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
if [ "${STOW_PROFILE}" = "auto" ]; then
    STOW_PROFILE="${ENV}"
fi

WINDOWS_ADDITIONAL_COMPONENT=""
if [ "${ENV}" = "wsl" ]; then
    WINDOWS_ADDITIONAL_COMPONENT=$(resolve_windows_components \
        "${WITH_GLAZEWM}" "${WITH_KOMOREBI}")
fi

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
    if [ "${SYSTEM_UPGRADE}" -eq 1 ]; then
        echo "System upgrade: yes"
    else
        echo "System upgrade: no"
    fi
    echo "Dotfile profile: ${STOW_PROFILE}"
    if [ "${ENV}" = "wsl" ]; then
        echo "Windows integration: required catalog components"
        if [ -n "${WINDOWS_ADDITIONAL_COMPONENT}" ]; then
            echo "Additional Windows component: ${WINDOWS_ADDITIONAL_COMPONENT}"
        fi
    fi
    exit 0
fi

if [ "${ENV}" = "wsl" ]; then
    preflight_windows_components \
        "${DOTFILES_DIR}" \
        "${WINDOWS_ADDITIONAL_COMPONENT}"
fi

"${DOTFILES_DIR}/scripts/validate-container-backend.sh" \
    "${ENV}" "${CONTAINER_BACKEND}"

# --- 2. パッケージインストール (common + 環境固有) ---

if ! YAY_BIN=$(command -v yay); then
    echo "The full bootstrap requires an existing yay installation." >&2
    echo "Install and review an AUR helper separately, or use --link-only." >&2
    exit 1
fi
PACMAN_BIN="/usr/bin/pacman"

apply_package_profiles \
    "${DOTFILES_DIR}" \
    "${SYSTEM_UPGRADE}" \
    "${YAY_BIN}" \
    "${PACMAN_BIN}" \
    "${PACKAGE_PROFILES[@]}"

# --- 3. Dotfiles Linking (Stow) ---
link_dotfiles
install_mise_tools
install_herdr_integration

# --- 6. WSL固有設定 ---

if [ "${ENV}" = "wsl" ]; then
    echo "Applying WSL specific settings..."

    apply_windows_components \
        "${DOTFILES_DIR}" \
        "${WINDOWS_ADDITIONAL_COMPONENT}" \
        "${KANATA_ADD_DEFENDER_EXCLUSION:-0}"

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
        "${WINDOWS_PWSH_BIN}" -NoProfile -Command \
            "winget install --id SumatraPDF.SumatraPDF -e --silent --accept-source-agreements --accept-package-agreements" \
            || echo "winget install failed (maybe already installed)"

        WIN_LOCALAPPDATA="$("${WINDOWS_PWSH_BIN}" -NoProfile \
            -Command 'Write-Output $Env:LOCALAPPDATA' | tr -d '\r')"
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

fi

echo "Installation Complete!"
