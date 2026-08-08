#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
RECORD_SCRIPT="${SCRIPT_DIR}/../../stow/desktop/.config/hypr/scripts/record.sh"
TEST_ROOT=$(mktemp -d)
sleep_pid=""
cleanup() {
    if [ -n "${sleep_pid}" ]; then
        kill "${sleep_pid}" 2>/dev/null || true
    fi
    rm -rf "${TEST_ROOT}"
}
trap cleanup EXIT

mkdir -p "${TEST_ROOT}/user-home/.config/hypr/scripts" "${TEST_ROOT}/state/zetshell"
printf '%s\n' \
    'ZETSHELL_RECORDINGS_DIR="$HOME/Videos"' \
    'export ZETSHELL_RECORDINGS_DIR' \
    > "${TEST_ROOT}/user-home/.config/hypr/scripts/load_zetshell_settings.sh"

sleep 30 &
sleep_pid=$!
printf '%s\n' "${sleep_pid}" > "${TEST_ROOT}/state/zetshell/recording.pid"

status=$(HOME="${TEST_ROOT}/user-home" XDG_STATE_HOME="${TEST_ROOT}/state" \
    "${RECORD_SCRIPT}" status)

if [ -e "${TEST_ROOT}/state/zetshell/recording.pid" ]; then
    echo "FAIL: a reused PID for another executable must be treated as stale" >&2
    exit 1
fi
if ! jq -e '.recording == false' <<<"${status}" >/dev/null; then
    echo "FAIL: stale recorder state should report recording=false" >&2
    exit 1
fi

echo "recording process tests passed"
