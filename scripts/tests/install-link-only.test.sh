#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(CDPATH= cd "${SCRIPT_DIR}/../.." && pwd)
TEST_HOME=$(mktemp -d)
trap 'rm -rf "${TEST_HOME}"' EXIT

HOME="${TEST_HOME}" DOTFILES_DIR="${REPO_ROOT}" \
    "${REPO_ROOT}/install.sh" --link-only

if [ ! -L "${TEST_HOME}/.zshrc" ]; then
    echo "FAIL: link-only install should Stow .zshrc" >&2
    exit 1
fi
if [ ! -f "${TEST_HOME}/.codex/config.toml" ] \
    || [ -L "${TEST_HOME}/.codex/config.toml" ]; then
    echo "FAIL: local Codex config should be an unmanaged regular file" >&2
    exit 1
fi

shell_output=$(mktemp)
trap 'rm -rf "${TEST_HOME}"; rm -f "${shell_output}"' EXIT
if ! HOME="${TEST_HOME}" PATH="/usr/bin:/bin" \
    /usr/bin/zsh -f -c 'source "$HOME/.zshrc"' >"${shell_output}" 2>&1; then
    echo "FAIL: linked .zshrc should load without optional shell tools" >&2
    exit 1
fi
if rg -q 'command not found|no such file or directory' "${shell_output}"; then
    echo "FAIL: linked .zshrc should not report missing optional shell tools" >&2
    sed -n '1,20p' "${shell_output}" >&2
    exit 1
fi

echo "install --link-only tests passed"
