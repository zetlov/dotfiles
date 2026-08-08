#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(CDPATH= cd "${SCRIPT_DIR}/../.." && pwd)
POMODORO_SCRIPT="${REPO_ROOT}/stow/desktop/.config/hypr/scripts/pomodoro.sh"
TEX_SCRIPT="${REPO_ROOT}/scripts/tex-install-missing.sh"
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "${TEST_ROOT}"' EXIT

if rg -q '/tmp/(pomodoro|tex-install)' "${POMODORO_SCRIPT}" "${TEX_SCRIPT}"; then
    echo "FAIL: runtime state must not use predictable shared /tmp paths" >&2
    exit 1
fi

initial_output=$(HOME="${TEST_ROOT}/fresh-home" XDG_STATE_HOME="${TEST_ROOT}/fresh-state" \
    "${POMODORO_SCRIPT}" get)
if ! jq -e '.time == "25:00" and .status == "STOPPED"' <<< "${initial_output}" >/dev/null; then
    echo "FAIL: Pomodoro should start with a 25-minute work interval" >&2
    exit 1
fi

HOME="${TEST_ROOT}/user-home" XDG_STATE_HOME="${TEST_ROOT}/state" \
    "${POMODORO_SCRIPT}" reset

state_file="${TEST_ROOT}/state/zetshell/pomodoro"
if [ ! -f "${state_file}" ]; then
    echo "FAIL: Pomodoro state should use XDG_STATE_HOME" >&2
    exit 1
fi
if ! rg -q '^STOPPED work 1500 [0-9]+$' "${state_file}"; then
    echo "FAIL: Pomodoro state should be written atomically in the expected format" >&2
    exit 1
fi

echo "runtime state tests passed"
