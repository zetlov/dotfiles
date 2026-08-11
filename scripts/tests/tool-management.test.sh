#!/usr/bin/env bash

set -eu

SCRIPT_DIR=$(CDPATH= cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(CDPATH= cd "${SCRIPT_DIR}/../.." && pwd)
COMMON_PACKAGES="${REPO_ROOT}/packages/common.txt"
GLOBAL_MISE_CONFIG="${REPO_ROOT}/stow/base/.config/mise/conf.d/dotfiles.toml"
BOOTSTRAP_SCRIPT="${REPO_ROOT}/scripts/install/bootstrap.sh"
DOTFILES_HELPER="${REPO_ROOT}/scripts/install/dotfiles.sh"

assert_package_present() {
    local package="$1"
    if ! rg -x -q "${package}" "${COMMON_PACKAGES}"; then
        echo "FAIL: ${package} should remain an OS-managed package" >&2
        exit 1
    fi
}

assert_package_absent() {
    local package="$1"
    if rg -x -q "${package}" "${COMMON_PACKAGES}"; then
        echo "FAIL: ${package} should be managed by mise, not yay/pacman" >&2
        exit 1
    fi
}

if [ ! -f "${GLOBAL_MISE_CONFIG}" ]; then
    echo "FAIL: the shared global mise configuration is missing" >&2
    exit 1
fi

if [ -e "${REPO_ROOT}/stow/base/.config/mise/config.toml" ]; then
    echo "FAIL: machine-wide mise overrides should remain unmanaged" >&2
    exit 1
fi

if ! rg -q '^node = "26"$' "${GLOBAL_MISE_CONFIG}"; then
    echo "FAIL: Node.js should track the shared major version in mise" >&2
    exit 1
fi

if ! rg -q '^"npm:@openai/codex" = "latest"$' "${GLOBAL_MISE_CONFIG}"; then
    echo "FAIL: Codex CLI should track the latest mise-managed version" >&2
    exit 1
fi

for tool in herdr aws; do
    if ! rg -q "^${tool} = \"latest\"$" "${GLOBAL_MISE_CONFIG}"; then
        echo "FAIL: ${tool} should be installed through the shared mise configuration" >&2
        exit 1
    fi
done

for package in mise python github-cli jq neovim ripgrep fd fzf lazygit; do
    assert_package_present "${package}"
done

for package in nodejs npm shellcheck gitleaks herdr aws-cli; do
    assert_package_absent "${package}"
done

if ! rg -q '^[[:space:]]*mise install$' "${DOTFILES_HELPER}"; then
    echo "FAIL: the mise installation helper should install configured tools" >&2
    exit 1
fi

if ! rg -q 'mise exec -- herdr integration install codex' \
    "${DOTFILES_HELPER}"; then
    echo "FAIL: full bootstrap should install the managed Herdr Codex integration" >&2
    exit 1
fi

link_line=$(rg -n '^apply_dotfiles ' "${BOOTSTRAP_SCRIPT}" | tail -n 1 | cut -d: -f1)
mise_line=$(rg -n '^install_mise_tools ' "${BOOTSTRAP_SCRIPT}" | tail -n 1 | cut -d: -f1)
if [ -z "${link_line}" ] || [ -z "${mise_line}" ] || [ "${mise_line}" -le "${link_line}" ]; then
    echo "FAIL: full bootstrap should install mise tools after linking global config" >&2
    exit 1
fi

echo "Tool management tests passed"
