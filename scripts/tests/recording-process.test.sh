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

mkdir -p "${TEST_ROOT}/bin"
cat > "${TEST_ROOT}/bin/gpu-screen-recorder" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "${RECORDER_ARGS_FILE}"
echo "Mock recorder intentionally stopped before capture" >&2
exit 17
EOF
chmod +x "${TEST_ROOT}/bin/gpu-screen-recorder"

assert_region_arguments() {
    local geometry="$1"
    local expected="$2"
    local args_file="${TEST_ROOT}/recorder.args"
    local -a arguments=()

    rm -f "${args_file}"
    if HOME="${TEST_ROOT}/user-home" XDG_STATE_HOME="${TEST_ROOT}/state" \
        PATH="${TEST_ROOT}/bin:${PATH}" RECORDER_ARGS_FILE="${args_file}" \
        "${RECORD_SCRIPT}" start region false "${geometry}" \
        >"${TEST_ROOT}/start.stdout" 2>"${TEST_ROOT}/start.stderr"; then
        echo "FAIL: mock recorder must fail before starting capture" >&2
        exit 1
    fi
    if [ ! -f "${args_file}" ]; then
        echo "FAIL: valid region was rejected: ${geometry}" >&2
        exit 1
    fi
    mapfile -t arguments < "${args_file}"
    if [ "${arguments[2]}" != "-region" ] || [ "${arguments[3]}" != "${expected}" ]; then
        echo "FAIL: incorrect recorder region for ${geometry}" >&2
        exit 1
    fi
}

# The recorder parses WxH+X+Y with signed offsets after literal plus separators.
assert_region_arguments "10,20 800x600" "800x600+10+20"
assert_region_arguments "-1900,20 800x600" "800x600+-1900+20"
assert_region_arguments "10,-1000 800x600" "800x600+10+-1000"
assert_region_arguments "-1900,-1000 800x600" "800x600+-1900+-1000"
assert_region_arguments "800x600+-1900+-1000" "800x600+-1900+-1000"

for geometry in "10,20 -800x600" "10,20 800x-600" "800x600-1900+20" "invalid"; do
    rm -f "${TEST_ROOT}/recorder.args"
    if HOME="${TEST_ROOT}/user-home" XDG_STATE_HOME="${TEST_ROOT}/state" \
        PATH="${TEST_ROOT}/bin:${PATH}" RECORDER_ARGS_FILE="${TEST_ROOT}/recorder.args" \
        "${RECORD_SCRIPT}" start region false "${geometry}" \
        >"${TEST_ROOT}/start.stdout" 2>"${TEST_ROOT}/start.stderr"; then
        echo "FAIL: malformed region was accepted: ${geometry}" >&2
        exit 1
    fi
    if [ -f "${TEST_ROOT}/recorder.args" ]; then
        echo "FAIL: malformed region reached the recorder: ${geometry}" >&2
        exit 1
    fi
done

echo "recording process tests passed"
