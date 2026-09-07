#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CLIPBOARD_SCRIPT="${SCRIPT_DIR}/../../stow/desktop/.config/hypr/scripts/clipboard_state.sh"
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "${TEST_ROOT}"' EXIT
mkdir -p "${TEST_ROOT}/bin" "${TEST_ROOT}/tmp"

cat >"${TEST_ROOT}/bin/cliphist" <<'EOF'
#!/usr/bin/env bash
case "$1" in
    list) printf '1\tFixture clipboard text\n' ;;
    decode)
        cat >/dev/null
        printf 'Fixture decoded content'
        if [ "${CLIPBOARD_SCENARIO}" = decode-failure ]; then
            exit 7
        fi
        ;;
    *) exit 2 ;;
esac
EOF
cat >"${TEST_ROOT}/bin/wl-copy" <<'EOF'
#!/usr/bin/env bash
cat >"${CLIPBOARD_COPY_LOG}"
if [ "${CLIPBOARD_SCENARIO}" = copy-failure ]; then
    exit 8
fi
EOF
cat >"${TEST_ROOT}/bin/mktemp" <<'EOF'
#!/usr/bin/env bash
if [ "${CLIPBOARD_SCENARIO}" = allocation-failure ]; then
    if [ -f "${CLIPBOARD_ALLOCATION_LOG}" ]; then
        exit 9
    fi
    touch "${CLIPBOARD_ALLOCATION_LOG}"
fi
exec /usr/bin/mktemp "$@"
EOF
chmod +x "${TEST_ROOT}/bin/cliphist" "${TEST_ROOT}/bin/wl-copy" "${TEST_ROOT}/bin/mktemp"

for scenario in success decode-failure copy-failure allocation-failure; do
    case "${scenario}" in
        success) expected_status=0 ;;
        decode-failure) expected_status=7 ;;
        copy-failure) expected_status=8 ;;
        allocation-failure) expected_status=9 ;;
    esac
    status=0
    PATH="${TEST_ROOT}/bin:/usr/bin:/bin" TMPDIR="${TEST_ROOT}/tmp" \
        CLIPBOARD_SCENARIO="${scenario}" \
        CLIPBOARD_COPY_LOG="${TEST_ROOT}/${scenario}.copy" \
        CLIPBOARD_ALLOCATION_LOG="${TEST_ROOT}/allocation.log" \
        bash "${CLIPBOARD_SCRIPT}" copy 1 >"${TEST_ROOT}/${scenario}.output" 2>&1 || status=$?
    if [ "${status}" -ne "${expected_status}" ]; then
        echo "FAIL: ${scenario} should preserve exit status ${expected_status}, got ${status}" >&2
        exit 1
    fi
    if [ -n "$(find "${TEST_ROOT}/tmp" -mindepth 1 -print -quit)" ]; then
        echo "FAIL: ${scenario} left clipboard content in temporary files" >&2
        exit 1
    fi
    if [ "${scenario}" = success ] \
        && [ "$(cat "${TEST_ROOT}/${scenario}.copy")" != 'Fixture decoded content' ]; then
        echo "FAIL: successful copy should forward the decoded content" >&2
        exit 1
    fi
    if [ "${scenario}" = decode-failure ] && [ -e "${TEST_ROOT}/${scenario}.copy" ]; then
        echo "FAIL: decoding failure must not update the clipboard" >&2
        exit 1
    fi
done

echo "clipboard state tests passed"
