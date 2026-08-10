#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
INSTALL_SCRIPT="${SCRIPT_DIR}/../../install.sh"
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "${TEST_ROOT}"' EXIT

if rg -q 'releases/latest|curl[^\n]*\|\s*(sh|bash)|wget[^\n]*-O\s*-|git clone' "${INSTALL_SCRIPT}"; then
    echo "FAIL: install.sh must not execute mutable or unverified remote content" >&2
    exit 1
fi

if ! rg -q 'WIN32YANK_SHA256=' "${INSTALL_SCRIPT}" \
    || ! rg -q 'sha256sum --check' "${INSTALL_SCRIPT}"; then
    echo "FAIL: downloaded executable archives must use a pinned SHA-256" >&2
    exit 1
fi

if rg -q 'uses:\s*[^#[:space:]]+@v[0-9]' "${SCRIPT_DIR}/../../.github/workflows"; then
    echo "FAIL: GitHub Actions must be pinned to full commit SHAs" >&2
    exit 1
fi
if ! rg -U -q 'uses:\s*gitleaks/gitleaks-action@[0-9a-f]{40}.*\n\s*env:\n\s*GITHUB_TOKEN:' \
    "${SCRIPT_DIR}/../../.github/workflows/check.yaml"; then
    echo "FAIL: the Gitleaks action requires the workflow-scoped GitHub token" >&2
    exit 1
fi
if rg -q ':latest([[:space:]\\]|$)' \
    "${SCRIPT_DIR}/../../.github/workflows/check.yaml"; then
    echo "FAIL: CI container images must not use mutable latest tags" >&2
    exit 1
fi
if rg -q 'runs-on:\s*(ubuntu|windows)-latest' \
    "${SCRIPT_DIR}/../../.github/workflows/check.yaml"; then
    echo "FAIL: CI runner versions must use explicit labels" >&2
    exit 1
fi
workflow_path="${SCRIPT_DIR}/../../.github/workflows/check.yaml"
if ! rg -q 'Install-Module Pester -RequiredVersion [0-9]+\.[0-9]+\.[0-9]+' \
    "${workflow_path}" \
    && ! rg -U -q 'Name\s*=\s*"Pester".*\n\s*RequiredVersion\s*=\s*"[0-9]+\.[0-9]+\.[0-9]+"' \
        "${workflow_path}"; then
    echo "FAIL: Pester must use an exact version" >&2
    exit 1
fi
if ! rg -q 'jdx/mise-action@[0-9a-f]{40}' \
    "${SCRIPT_DIR}/../../.github/workflows/check.yaml"; then
    echo "FAIL: CI lint tools should use the mise lock from this repository" >&2
    exit 1
fi
if rg -q 'jdx/mise-action@5228313ee0372e111a38da051671ca30fc5a96db' \
    "${SCRIPT_DIR}/../../.github/workflows/check.yaml"; then
    echo "FAIL: mise-action v3 uses the retired Node 20 runtime" >&2
    exit 1
fi
if ! rg -U -q 'jdx/mise-action@7e36c90d9ab29c415a2384db3006f3ec8a8cc654.*\n\s*with:\n\s*version: 2026\.8\.3\n\s*sha256: [0-9a-f]{64}' \
    "${SCRIPT_DIR}/../../.github/workflows/check.yaml"; then
    echo "FAIL: mise-action v4 must pin the mise binary version and checksum" >&2
    exit 1
fi
if rg -q 'DOTFILES_DIR="\$\{DOTFILES_DIR:-|DOTFILES_(OS_RELEASE|ARCH|ENV)' "${INSTALL_SCRIPT}"; then
    echo "FAIL: install trust boundaries must not be replaceable through environment variables" >&2
    exit 1
fi
if ! rg -q 'run:\s*mise run test' \
    "${SCRIPT_DIR}/../../.github/workflows/check.yaml"; then
    echo "FAIL: CI should run the complete test task so new tests are not skipped" >&2
    exit 1
fi

conflict_home="${TEST_ROOT}/conflict-home"
mkdir -p "${conflict_home}"
printf 'user git config\n' >"${conflict_home}/.gitconfig"
if HOME="${conflict_home}" "${INSTALL_SCRIPT}" --link-only \
    >"${TEST_ROOT}/conflict-stdout" 2>"${TEST_ROOT}/conflict-stderr"; then
    echo "FAIL: link-only install should reject Stow conflicts" >&2
    exit 1
fi
if [ -e "${conflict_home}/.codex/config.toml" ] \
    || [ -e "${conflict_home}/.gitconfig.local" ]; then
    echo "FAIL: all link preflights must finish before local config mutation" >&2
    exit 1
fi

echo "install security tests passed"
