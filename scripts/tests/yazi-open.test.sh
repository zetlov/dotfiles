#!/usr/bin/env bash

set -eu

ROOT_DIR=$(CDPATH= cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
OPEN_SCRIPT="${ROOT_DIR}/stow/base/.local/bin/yazi-open"
IMAGE_OPEN_SCRIPT="${ROOT_DIR}/stow/base/.local/bin/yazi-open-image"
YAZI_CONFIG="${ROOT_DIR}/stow/base/.config/yazi/yazi.toml"
YAZI_KEYMAP="${ROOT_DIR}/stow/base/.config/yazi/keymap.toml"
YAZI_PACKAGES="${ROOT_DIR}/stow/base/.config/yazi/package.toml"
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
[ -x "${IMAGE_OPEN_SCRIPT}" ] || fail "Yazi image opener must be executable"
[ -f "${YAZI_CONFIG}" ] || fail "Yazi config is missing"
[ -f "${YAZI_KEYMAP}" ] || fail "Yazi keymap is missing"
[ -f "${YAZI_PACKAGES}" ] || fail "Yazi package lock is missing"

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

if config.get("opener", {}).get("jpegview") != [
    {
        "run": "yazi-open-image %s1",
        "desc": "Open image with JPEGView on WSL",
        "orphan": True,
        "for": "linux",
    }
]:
    raise SystemExit("unexpected JPEGView opener")

if config.get("open", {}).get("prepend_rules") != [
    {"mime": "image/*", "use": "jpegview"}
]:
    raise SystemExit("images must use JPEGView on WSL")

if config.get("mgr", {}).get("show_hidden") is not True:
    raise SystemExit("hidden files must be visible")
PY

mise exec -- python - "${YAZI_KEYMAP}" <<'PY'
import sys
import tomllib
from pathlib import Path

config = tomllib.loads(Path(sys.argv[1]).read_text())
bindings = config.get("mgr", {}).get("prepend_keymap")
if bindings != [
    {"on": "l", "run": "plugin smart-enter", "desc": "Enter the directory or open the file"}
]:
    raise SystemExit("l must enter directories and open files")
PY

mise exec -- python - "${YAZI_PACKAGES}" <<'PY'
import sys
import tomllib
from pathlib import Path

config = tomllib.loads(Path(sys.argv[1]).read_text())
dependencies = config.get("plugin", {}).get("deps")
if dependencies != [{
    "use": "yazi-rs/plugins:smart-enter",
    "rev": "4dc7f1b",
    "hash": "187cc58ba7ac3befd49c342129e6f1b6",
}]:
    raise SystemExit("smart-enter must be installed from the locked official source")
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

image_log="${TEST_ROOT}/image.log"
expected_image_command="Start-Process -FilePath 'C:\\Program Files\\JPEGView\\JPEGView.exe' -ArgumentList 'C:\\WSL/data/Alice''s Picture.png'"
CALL_LOG="${image_log}" \
    EXPECTED_COMMAND="${expected_image_command}" \
    WSL_DISTRO_NAME=Arch \
    YAZI_OPEN_WSL_INIT="${TEST_ROOT}/bin/init" \
    PATH="${TEST_ROOT}/bin:/usr/bin" \
    "${IMAGE_OPEN_SCRIPT}" "/data/Alice's Picture.png"
printf '<%s>\n' "${expected_image_command}" \
    >"${TEST_ROOT}/expected-image.log"
assert_file_equals "${TEST_ROOT}/expected-image.log" "${image_log}"

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
