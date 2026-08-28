#!/usr/bin/env bash

set -eu

SCRIPT_DIR=$(CDPATH= cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DOTFILES_DIR=$(CDPATH= cd "${SCRIPT_DIR}/../.." && pwd)

# shellcheck source=scripts/install/windows-components.sh
# shellcheck disable=SC1091
source "${DOTFILES_DIR}/scripts/install/windows-components.sh"
# shellcheck source=scripts/install/packages.sh
# shellcheck disable=SC1091
source "${DOTFILES_DIR}/scripts/install/packages.sh"
# shellcheck source=scripts/install/dotfiles.sh
# shellcheck disable=SC1091
source "${DOTFILES_DIR}/scripts/install/dotfiles.sh"
# shellcheck source=scripts/install/wsl-extras.sh
# shellcheck disable=SC1091
source "${DOTFILES_DIR}/scripts/install/wsl-extras.sh"
# shellcheck source=scripts/install/options.sh
# shellcheck disable=SC1091
source "${DOTFILES_DIR}/scripts/install/options.sh"

# --- 0. 引数パース ---

parse_install_options "$@"

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
    preflight_dotfiles "${DOTFILES_DIR}" "${STOW_PROFILE}"
    apply_dotfiles "${DOTFILES_DIR}" "${STOW_PROFILE}"
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
        "${WITH_GLAZEWM}" "${WITH_KOMOREBI}" \
        "${WITH_MONITOR_PROFILES}")
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
preflight_dotfiles "${DOTFILES_DIR}" "${STOW_PROFILE}"

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
apply_dotfiles "${DOTFILES_DIR}" "${STOW_PROFILE}"
install_mise_tools "${DOTFILES_DIR}"
install_herdr_integration "${DOTFILES_DIR}"

# --- 6. WSL固有設定 ---

if [ "${ENV}" = "wsl" ]; then
    apply_windows_components \
        "${DOTFILES_DIR}" \
        "${WINDOWS_ADDITIONAL_COMPONENT}" \
        "${KANATA_ADD_DEFENDER_EXCLUSION:-0}"
    apply_wsl_extras "${HOME}" "${WINDOWS_PWSH_BIN}"
fi

echo "Installation Complete!"
