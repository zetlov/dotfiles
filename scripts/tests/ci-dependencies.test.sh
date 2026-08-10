#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(CDPATH= cd "${SCRIPT_DIR}/../.." && pwd)
WORKFLOW="${REPO_ROOT}/.github/workflows/check.yaml"
MISE_CONFIG="${REPO_ROOT}/mise.toml"
PESTER_RUNNER="${REPO_ROOT}/windows/tests/Invoke-PesterSuite.ps1"
PESTER_MANIFEST="${REPO_ROOT}/windows/tests/pester-suites.txt"

failures=0

fail() {
    echo "FAIL: $1" >&2
    failures=$((failures + 1))
}

if ! rg -q 'apt-get install -y .*\bzsh\b' "${WORKFLOW}"; then
    fail "Ubuntu test job should install zsh explicitly"
fi

arch_install_lines=$(rg 'pacman -Syu --noconfirm --needed' "${WORKFLOW}")
if [ "$(printf '%s\n' "${arch_install_lines}" | wc -l)" -ne 2 ]; then
    fail "expected dependency installation in both Arch jobs"
fi
if printf '%s\n' "${arch_install_lines}" | rg -v -q '\bstow\b'; then
    fail "every Arch link-only job should install Stow explicitly"
fi

if ! rg -q 'windows/tests/Invoke-PesterSuite\.ps1' "${MISE_CONFIG}"; then
    fail "Windows mise tasks should delegate to the shared Pester runner"
fi
tracked_pester_tests=$(git -C "${REPO_ROOT}" ls-files \
    'windows/*/tests/*.Tests.ps1' | sort)
manifest_pester_tests=$(
    if [ -f "${PESTER_MANIFEST}" ]; then
        sort "${PESTER_MANIFEST}"
    fi
)
if [ -z "${tracked_pester_tests}" ] \
    || [ "${manifest_pester_tests}" != "${tracked_pester_tests}" ]; then
    fail "the Pester suite manifest should list every tracked component test"
fi
if [ ! -f "${PESTER_RUNNER}" ] \
    || ! rg -q 'pester-suites\.txt' "${PESTER_RUNNER}"; then
    fail "the shared Pester runner should use the reviewed suite manifest"
fi
if ! rg -q 'Get-AuthenticodeSignature' "${PESTER_RUNNER}" \
    || ! rg -q 'Get-ChildItem.+-Recurse.+-File' "${PESTER_RUNNER}" \
    || ! rg -q '"\.dll"' "${PESTER_RUNNER}" \
    || ! rg -q '"\.ps1xml"' "${PESTER_RUNNER}" \
    || ! rg -q '147C2FD397677DC76DD198E83E7D9D234AA59D1A' "${PESTER_RUNNER}" \
    || ! rg -q 'Import-Module.+\$pesterModule\.Path' "${PESTER_RUNNER}"; then
    fail "the shared Pester runner should verify and directly import the pinned signer"
fi

if ! rg -q '^[[:space:]]*matrix:' "${WORKFLOW}"; then
    fail "Windows Pester tests should use a PowerShell runtime matrix"
fi
if ! rg -q '\bpwsh\b' "${WORKFLOW}"; then
    fail "Windows Pester tests should run on PowerShell 7 via pwsh"
fi
if ! rg -q '\bpowershell\b' "${WORKFLOW}"; then
    fail "Windows Pester tests should retain Windows PowerShell 5.1 compatibility"
fi
if rg -q 'shell:[[:space:]]*\$\{\{[[:space:]]*matrix\.' "${WORKFLOW}"; then
    fail "GitHub Actions does not allow the matrix context in step shell"
fi
runtime_conditions=$(rg -c 'if:[[:space:]]*matrix\.runtime' "${WORKFLOW}")
if [ "${runtime_conditions}" -lt 2 ]; then
    fail "PowerShell editions should use conditional steps with static shells"
fi
if ! rg -q 'SkipPublisherCheck' "${WORKFLOW}"; then
    fail "Windows PowerShell 5.1 should handle the built-in Pester publisher mismatch"
fi
if ! rg -U -q '(?s)originalInstallationPolicy.+?try \{.+?Set-PSRepository.+?Trusted.+?finally \{.+?Set-PSRepository.+?originalInstallationPolicy' \
    "${WORKFLOW}"; then
    fail "CI should restore the PowerShell Gallery trust policy after installing Pester"
fi
if ! rg -U -q '(?s)name: Test Windows configuration.*?install: false.*?cache: false' \
    "${WORKFLOW}"; then
    fail "Windows Pester jobs should install mise without unrelated project tools"
fi

if ! rg -q 'mise run check:configs' "${WORKFLOW}"; then
    fail "CI configuration validation should call the root check:configs mise task"
fi
if rg -q 'find (examples|stow|windows).*\.(lua|json)' "${WORKFLOW}"; then
    fail "CI configuration validation should not duplicate Lua or JSON checks"
fi

if [ "${failures}" -ne 0 ]; then
    exit 1
fi

echo "CI dependency tests passed"
