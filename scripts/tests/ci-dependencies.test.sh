#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(CDPATH= cd "${SCRIPT_DIR}/../.." && pwd)
WORKFLOW="${REPO_ROOT}/.github/workflows/check.yaml"

if ! rg -q 'apt-get install -y .*\bzsh\b' "${WORKFLOW}"; then
    echo "FAIL: Ubuntu test job should install zsh explicitly" >&2
    exit 1
fi

arch_install_lines=$(rg 'pacman -Syu --noconfirm --needed' "${WORKFLOW}")
if [ "$(printf '%s\n' "${arch_install_lines}" | wc -l)" -ne 2 ]; then
    echo "FAIL: expected dependency installation in both Arch jobs" >&2
    exit 1
fi
if printf '%s\n' "${arch_install_lines}" | rg -v -q '\bstow\b'; then
    echo "FAIL: every Arch link-only job should install Stow explicitly" >&2
    exit 1
fi

echo "CI dependency tests passed"
