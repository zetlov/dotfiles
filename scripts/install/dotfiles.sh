#!/usr/bin/env bash

preflight_dotfiles() {
    local dotfiles_dir="$1"
    local profile="$2"

    echo "Validating local configuration and Stow targets..."
    if ! HOME="${HOME}" "${dotfiles_dir}/scripts/init-local-config.sh" \
        --dry-run "--profile=${profile}" >/dev/null; then
        echo "Local configuration validation failed." >&2
        return 1
    fi
    if ! LC_ALL=C DOTFILES_DIR="${dotfiles_dir}" \
        "${dotfiles_dir}/scripts/stow-dotfiles.sh" \
        "--profile=${profile}" --preflight >/dev/null; then
        echo "Stow preflight failed for profile: ${profile}" >&2
        return 1
    fi
}

apply_dotfiles() {
    local dotfiles_dir="$1"
    local profile="$2"

    if ! command -v stow >/dev/null 2>&1; then
        echo "GNU Stow is required to apply dotfiles." >&2
        return 1
    fi
    echo "Initializing local configuration..."
    if ! "${dotfiles_dir}/scripts/init-local-config.sh" \
        "--profile=${profile}"; then
        echo "Local configuration initialization failed." >&2
        return 1
    fi
    echo "Linking dotfiles with Stow..."
    if ! LC_ALL=C DOTFILES_DIR="${dotfiles_dir}" \
        "${dotfiles_dir}/scripts/stow-dotfiles.sh" \
        "--profile=${profile}"; then
        echo "Stow apply failed for profile: ${profile}" >&2
        return 1
    fi
}

install_mise_tools() {
    local dotfiles_dir="$1"
    local mise_bin="/usr/bin/mise"

    if [ ! -x "${mise_bin}" ]; then
        echo "The OS-managed mise executable was not found: ${mise_bin}" >&2
        return 1
    fi

    echo "Installing mise-managed development tools..."
    if ! (
        cd "${dotfiles_dir}"
        "${mise_bin}" install
    ); then
        echo "mise tool installation failed." >&2
        return 1
    fi
}

install_herdr_integration() {
    local dotfiles_dir="$1"
    local mise_bin="/usr/bin/mise"

    if [ ! -x "${mise_bin}" ]; then
        echo "The OS-managed mise executable was not found: ${mise_bin}" >&2
        return 1
    fi

    echo "Installing the Herdr Codex integration..."
    if ! (
        cd "${dotfiles_dir}"
        "${mise_bin}" exec -- herdr integration install codex
    ); then
        echo "Herdr Codex integration installation failed." >&2
        return 1
    fi

    echo "Linking the Herdr numbered-workspaces plugin..."
    if ! (
        cd "${dotfiles_dir}"
        "${mise_bin}" exec -- herdr plugin link \
            "${dotfiles_dir}/scripts/herdr/numbered-workspaces" --enabled
    ); then
        echo "Herdr numbered-workspaces plugin linking failed." >&2
        return 1
    fi
}
