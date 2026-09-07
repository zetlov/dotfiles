#!/usr/bin/env bash

set -eu

ROOT_DIR=$(CDPATH= cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
OPEN_SCRIPT="${ROOT_DIR}/stow/base/.local/bin/yazi-open"
YAZI_CONFIG="${ROOT_DIR}/stow/base/.config/yazi/yazi.toml"
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "${TEST_ROOT}"' EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

assert_file_equals() {
    local expected="$1"
    local actual="$2"

    cmp -s "${expected}" "${actual}" \
        || fail "files differ: ${expected} ${actual}"
}

[ -x "${OPEN_SCRIPT}" ] || fail "Yazi opener must be executable"
[ -f "${YAZI_CONFIG}" ] || fail "Yazi config is missing"

mise exec -- python - "${YAZI_CONFIG}" <<'PY'
import sys
import tomllib
from pathlib import Path

config = tomllib.loads(Path(sys.argv[1]).read_text())
for name in ("open", "play"):
    rules = config.get("opener", {}).get(name)
    if rules != [
        {
            "run": "yazi-open %s1",
            "desc": "Open with the system default",
            "orphan": True,
            "for": "linux",
        }
    ]:
        raise SystemExit(f"unexpected {name} opener: {rules!r}")
PY

mkdir -p "${TEST_ROOT}/bin"

cat >"${TEST_ROOT}/bin/wslpath" <<'EOF'
#!/usr/bin/env bash
set -eu
[ "$1" = "-w" ] && [ "$2" = "--" ] || exit 91
printf 'C:\\WSL%s\n' "$3"
EOF

cat >"${TEST_ROOT}/bin/powershell.exe" <<'EOF'
#!/usr/bin/env bash
set -eu
[ "${VIA_WSL_INIT:-}" = 1 ] || exit 92
[ "$1" = "-NoProfile" ] || exit 93
[ "$2" = "-NonInteractive" ] || exit 94
[ "$3" = "-Command" ] || exit 95
[ "$4" = "${EXPECTED_COMMAND}" ] || exit 96
printf '<%s>\n' "$4" >>"${CALL_LOG}"
EOF

cat >"${TEST_ROOT}/bin/init" <<'EOF'
#!/usr/bin/env bash
set -eu
launcher="$1"
shift
VIA_WSL_INIT=1 "${launcher}" "$@"
EOF

cat >"${TEST_ROOT}/bin/uname" <<'EOF'
#!/usr/bin/env bash
printf '6.12.0-arch1-1\n'
EOF

cat >"${TEST_ROOT}/bin/xdg-open" <<'EOF'
#!/usr/bin/env bash
set -eu
printf '<%s>\n' "$@" >>"${CALL_LOG}"
EOF

chmod +x "${TEST_ROOT}/bin/"*

windows_log="${TEST_ROOT}/windows.log"
expected_command="Start-Process -FilePath 'C:\\WSL/data/Alice''s Picture & Notes.png'"
CALL_LOG="${windows_log}" \
    EXPECTED_COMMAND="${expected_command}" \
    WSL_DISTRO_NAME=Arch \
    YAZI_OPEN_WSL_INIT="${TEST_ROOT}/bin/init" \
    PATH="${TEST_ROOT}/bin:/usr/bin" \
    "${OPEN_SCRIPT}" "/data/Alice's Picture & Notes.png"
printf '<%s>\n' "${expected_command}" \
    >"${TEST_ROOT}/expected-windows.log"
assert_file_equals "${TEST_ROOT}/expected-windows.log" "${windows_log}"

linux_log="${TEST_ROOT}/linux.log"
CALL_LOG="${linux_log}" \
    WSL_DISTRO_NAME= \
    WSL_INTEROP= \
    PATH="${TEST_ROOT}/bin:/usr/bin" \
    "${OPEN_SCRIPT}" '/data/My Picture & Notes.png'
printf '</data/My Picture & Notes.png>\n' \
    >"${TEST_ROOT}/expected-linux.log"
assert_file_equals "${TEST_ROOT}/expected-linux.log" "${linux_log}"

if "${OPEN_SCRIPT}" >"${TEST_ROOT}/no-args.stdout" 2>"${TEST_ROOT}/no-args.stderr"; then
    fail "Yazi opener accepted an empty path list"
fi
grep -Fq 'Usage:' "${TEST_ROOT}/no-args.stderr" \
    || fail "empty path list must produce usage guidance"

echo "yazi-open tests passed"
