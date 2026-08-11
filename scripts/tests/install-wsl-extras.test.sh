#!/usr/bin/env bash

set -euo pipefail

script_dir=$(CDPATH='' cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(CDPATH='' cd "${script_dir}/../.." && pwd)
helper="${repo_root}/scripts/install/wsl-extras.sh"
bootstrap="${repo_root}/scripts/install/bootstrap.sh"
test_root=$(mktemp -d)
trap 'rm -rf "${test_root}"' EXIT

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

if [ ! -r "${helper}" ]; then
    fail "WSL extras helper is missing"
fi

# shellcheck source=../install/wsl-extras.sh
# shellcheck disable=SC1091
source "${helper}"

if ! rg -q '^readonly WIN32YANK_SHA256="[0-9a-f]{64}"$' "${helper}" \
    || ! rg -q 'sha256sum.*--check' "${helper}"; then
    fail "win32yank download must retain a pinned SHA-256 check"
fi
if rg -q 'win32yank|SumatraPDF|winget install' "${bootstrap}"; then
    fail "bootstrap still owns WSL extras implementation details"
fi
if [ "$(rg -c '^    apply_wsl_extras ' "${bootstrap}")" -ne 1 ]; then
    fail "bootstrap must invoke the WSL extras boundary exactly once"
fi

home="${test_root}/home"
fake_bin="${test_root}/bin"
curl_log="${test_root}/curl.log"
mkdir -p "${home}/bin" "${fake_bin}"
printf 'existing executable\n' >"${home}/bin/win32yank.exe"

cat >"${fake_bin}/curl" <<EOF
#!/usr/bin/env bash
printf 'called\n' >>"${curl_log}"
exit 19
EOF
chmod +x "${fake_bin}/curl"

install_win32yank "${home}" "${fake_bin}/curl"
if [ -e "${curl_log}" ]; then
    fail "existing win32yank should skip the download"
fi

rm "${home}/bin/win32yank.exe"
tmp_dir="${test_root}/tmp"
mkdir -p "${tmp_dir}"
if TMPDIR="${tmp_dir}" install_win32yank "${home}" "${fake_bin}/curl" \
    >"${test_root}/failure.stdout" 2>"${test_root}/failure.stderr"; then
    fail "win32yank installation accepted a failed download"
fi
if find "${tmp_dir}" -mindepth 1 -print -quit | rg -q .; then
    fail "failed win32yank download left temporary files"
fi

echo "install WSL extras tests passed"
