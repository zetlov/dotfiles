#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(CDPATH= cd "${SCRIPT_DIR}/../.." && pwd)
VALIDATOR="${REPO_ROOT}/scripts/validate-install-target.sh"
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "${TEST_ROOT}"' EXIT

assert_contains() {
    local pattern="$1"
    local file="$2"
    local message="$3"

    if ! rg -q -- "${pattern}" "${file}"; then
        echo "FAIL: ${message}" >&2
        sed -n '1,120p' "${file}" >&2
        exit 1
    fi
}

assert_not_contains() {
    local pattern="$1"
    local file="$2"
    local message="$3"

    if rg -q -- "${pattern}" "${file}"; then
        echo "FAIL: ${message}" >&2
        sed -n '1,120p' "${file}" >&2
        exit 1
    fi
}

assert_backend() {
    local environment="$1"
    local requested="$2"
    local expected="$3"
    local actual

    actual=$("${REPO_ROOT}/scripts/resolve-container-backend.sh" \
        "${environment}" "${requested}")
    if [ "${actual}" != "${expected}" ]; then
        echo "FAIL: ${environment}/${requested} should resolve to ${expected}, got ${actual}" >&2
        exit 1
    fi
}

assert_profile_plan() {
    local environment="$1"
    local backend="$2"
    local output="$3"

    "${REPO_ROOT}/scripts/resolve-package-profiles.sh" \
        "${environment}" 0 "${backend}" 0 0 >"${output}"
}

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

for package in docker docker-compose; do
    if rg -x -q "${package}" "${REPO_ROOT}/packages/common.txt"; then
        echo "FAIL: ${package} must not be part of the cross-platform common profile" >&2
        exit 1
    fi
    if ! rg -x -q "${package}" "${REPO_ROOT}/packages/container-native.txt"; then
        echo "FAIL: ${package} should be isolated in the native container profile" >&2
        exit 1
    fi
done

assert_backend wsl auto desktop
assert_backend desktop auto native
assert_backend wsl none none
assert_backend desktop none none

printf '%s\n' '6.12.0-arch1-1' >"${TEST_ROOT}/native-osrelease"
if [ "$(WSL_DISTRO_NAME=Arch \
    "${REPO_ROOT}/scripts/detect-install-environment.sh" \
    "${TEST_ROOT}/native-osrelease")" != "desktop" ]; then
    echo "FAIL: WSL environment variables must not override kernel evidence" >&2
    exit 1
fi
printf '%s\n' '5.15.167.4-microsoft-standard-WSL2' \
    >"${TEST_ROOT}/wsl-osrelease"
if [ "$("${REPO_ROOT}/scripts/detect-install-environment.sh" \
    "${TEST_ROOT}/wsl-osrelease")" != "wsl" ]; then
    echo "FAIL: Microsoft WSL kernel evidence should select the WSL environment" >&2
    exit 1
fi

assert_profile_plan wsl desktop "${TEST_ROOT}/wsl-plan"
assert_contains '^common.txt$' "${TEST_ROOT}/wsl-plan" \
    "WSL plan should include the common profile"
assert_contains '^wsl.txt$' "${TEST_ROOT}/wsl-plan" \
    "WSL plan should include the WSL profile"
assert_not_contains 'container-native.txt' "${TEST_ROOT}/wsl-plan" \
    "WSL Docker Desktop mode must not install a Linux Docker daemon"

dry_run_home="${TEST_ROOT}/dry-run-home"
mkdir -p "${dry_run_home}"
HOME="${dry_run_home}" "${REPO_ROOT}/install.sh" \
    --dry-run --container-backend=none >"${TEST_ROOT}/dry-run-plan"
assert_contains '^Container backend: none$' "${TEST_ROOT}/dry-run-plan" \
    "dry-run should report an explicit container opt-out"
if find "${dry_run_home}" -mindepth 1 -print -quit | rg -q .; then
    echo "FAIL: install --dry-run must not mutate HOME" >&2
    exit 1
fi

link_home="${TEST_ROOT}/link-home"
mkdir -p "${link_home}"
HOME="${link_home}" "${REPO_ROOT}/install.sh" --link-only --dry-run \
    >"${TEST_ROOT}/link-plan"
assert_contains '^Mode: link-only$' "${TEST_ROOT}/link-plan" \
    "link-only dry-run should report its mode"
if find "${link_home}" -mindepth 1 -print -quit | rg -q .; then
    echo "FAIL: link-only dry-run must not mutate HOME" >&2
    exit 1
fi

assert_profile_plan wsl native "${TEST_ROOT}/wsl-native-plan"
assert_contains '^container-native.txt$' "${TEST_ROOT}/wsl-native-plan" \
    "WSL native container mode should install the native container profile"

if "${REPO_ROOT}/scripts/resolve-container-backend.sh" desktop desktop \
    >"${TEST_ROOT}/desktop-stdout" 2>"${TEST_ROOT}/desktop-stderr"; then
    echo "FAIL: Docker Desktop backend should be rejected outside WSL" >&2
    exit 1
fi
assert_contains 'Docker Desktop backend is supported only in WSL' \
    "${TEST_ROOT}/desktop-stderr" \
    "invalid Docker Desktop usage should fail with a clear message"

empty_path="${TEST_ROOT}/empty-path"
empty_pacman_db="${TEST_ROOT}/empty-pacman-db"
mkdir -p "${empty_path}"
mkdir -p "${empty_pacman_db}"
printf '#!/bin/sh\nexit 1\n' >"${empty_path}/docker"
chmod +x "${empty_path}/docker"
if PATH="${empty_path}:/usr/bin:/bin" /usr/bin/bash \
    "${REPO_ROOT}/scripts/validate-container-backend.sh" \
    wsl desktop "${empty_pacman_db}" \
    >"${TEST_ROOT}/missing-docker-stdout" \
    2>"${TEST_ROOT}/missing-docker-stderr"; then
    echo "FAIL: Docker Desktop backend should require an integrated Docker CLI" >&2
    exit 1
fi
assert_contains 'Docker Desktop WSL integration is unavailable' \
    "${TEST_ROOT}/missing-docker-stderr" \
    "missing Docker Desktop integration should fail with recovery guidance"

fake_path="${TEST_ROOT}/fake-path"
mkdir -p "${fake_path}"
printf '#!/bin/sh\nexit 0\n' >"${fake_path}/docker"
chmod +x "${fake_path}/docker"
PATH="${fake_path}:/usr/bin:/bin" /usr/bin/bash \
    "${REPO_ROOT}/scripts/validate-container-backend.sh" \
    wsl desktop "${empty_pacman_db}"

native_pacman_db="${TEST_ROOT}/native-pacman-db"
mkdir -p "${native_pacman_db}/podman-docker-5.6.0-1"
printf '%%NAME%%\npodman-docker\n' \
    >"${native_pacman_db}/podman-docker-5.6.0-1/desc"
printf '%%FILES%%\nusr/bin/docker\n' \
    >"${native_pacman_db}/podman-docker-5.6.0-1/files"
if PATH="${fake_path}:/usr/bin:/bin" /usr/bin/bash \
    "${REPO_ROOT}/scripts/validate-container-backend.sh" \
    wsl desktop "${native_pacman_db}" \
    >"${TEST_ROOT}/native-docker-stdout" \
    2>"${TEST_ROOT}/native-docker-stderr"; then
    echo "FAIL: Docker Desktop backend must reject distro-managed Docker packages" >&2
    exit 1
fi
assert_contains 'Distro-managed Docker packages conflict with Docker Desktop' \
    "${TEST_ROOT}/native-docker-stderr" \
    "native Docker packages should fail with migration guidance"

for component in glazewm zebar; do
    if [ ! -d "${REPO_ROOT}/windows/${component}" ]; then
        echo "FAIL: ${component} must be managed by the public repository" >&2
        exit 1
    fi
done

echo "install profile tests passed"
