#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(CDPATH= cd "${SCRIPT_DIR}/../.." && pwd)
VALIDATOR="${REPO_ROOT}/scripts/validate-install-target.sh"
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "${TEST_ROOT}"' EXIT

if "${VALIDATOR}" desktop aarch64 0 0 \
    >"${TEST_ROOT}/stdout" 2>"${TEST_ROOT}/stderr"; then
    echo "FAIL: native ARM full bootstrap should be rejected" >&2
    exit 1
fi
if ! rg -q 'native ARM.*link-only' "${TEST_ROOT}/stderr"; then
    echo "FAIL: native ARM rejection should recommend link-only mode" >&2
    exit 1
fi

for package in libva-nvidia-driver nvidia-open nvidia-settings nvidia-utils ollama-cuda; do
    if rg -x -q "${package}" "${REPO_ROOT}/packages/desktop.txt"; then
        echo "FAIL: ${package} must not be installed by the portable desktop profile" >&2
        exit 1
    fi
    if ! rg -x -q "${package}" "${REPO_ROOT}/packages/desktop-nvidia.txt"; then
        echo "FAIL: ${package} should be isolated in the NVIDIA opt-in profile" >&2
        exit 1
    fi
done
if ! rg -q -- '--with-nvidia' "${REPO_ROOT}/install.sh"; then
    echo "FAIL: NVIDIA packages should require an explicit install flag" >&2
    exit 1
fi
if ! rg -q -- '--with-glazewm' "${REPO_ROOT}/install.sh"; then
    echo "FAIL: GlazeWM should require an explicit install flag" >&2
    exit 1
fi
if ! rg -q 'Choose only one Windows window manager' "${REPO_ROOT}/install.sh"; then
    echo "FAIL: the installer should reject selecting both window managers" >&2
    exit 1
fi

for component in glazewm zebar; do
    if [ ! -d "${REPO_ROOT}/windows/${component}" ]; then
        echo "FAIL: ${component} must be managed by the public repository" >&2
        exit 1
    fi
done

echo "install profile tests passed"
