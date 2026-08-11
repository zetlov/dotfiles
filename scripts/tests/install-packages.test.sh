#!/usr/bin/env bash

set -euo pipefail

script_dir=$(CDPATH='' cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(CDPATH='' cd "${script_dir}/../.." && pwd)
package_helper="${repo_root}/scripts/install/packages.sh"
test_root=$(mktemp -d)
trap 'rm -rf "${test_root}"' EXIT

# shellcheck source=../install/packages.sh
# shellcheck disable=SC1091
source "${package_helper}"

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

assert_contains() {
    local pattern="$1"
    local file="$2"
    local message="$3"
    if ! rg -q -- "${pattern}" "${file}"; then
        fail "${message}"
    fi
}

count_calls() {
    local log_path="$1"
    local count
    count=$(rg -c '^CALL$' "${log_path}" 2>/dev/null || true)
    printf '%s\n' "${count:-0}"
}

fake_yay="${test_root}/yay"
yay_log="${test_root}/yay.log"
fake_pacman="${test_root}/pacman"
pacman_log="${test_root}/pacman.log"
cat >"${fake_yay}" <<EOF
#!/usr/bin/env bash
printf '%s\n' CALL >>"${yay_log}"
printf '%s\n' "\$@" >>"${yay_log}"
if [ "\${FAIL_UPGRADE:-0}" = "1" ] && [ "\${1:-}" = "-Syu" ]; then
    exit 17
fi
if [ "\${FAIL_INSTALL:-0}" = "1" ] && [ "\${1:-}" = "-S" ]; then
    exit 18
fi
printf '%s\n' STDIN >>"${yay_log}"
cat >>"${yay_log}"
printf '%s\n' END >>"${yay_log}"
EOF
chmod +x "${fake_yay}"
cat >"${fake_pacman}" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" >>"${pacman_log}"
if [ "\${PACMAN_FAIL:-0}" = "1" ]; then
    exit 19
fi
if [ "\${1:-}" = "-Qu" ] && [ -n "\${PACMAN_PENDING_UPDATES:-}" ]; then
    printf '%s\n' "\${PACMAN_PENDING_UPDATES}"
    exit 0
fi
if [ "\${1:-}" = "-Qu" ]; then
    exit 1
fi
EOF
chmod +x "${fake_pacman}"

apply_package_profiles \
    "${repo_root}" 0 "${fake_yay}" "${fake_pacman}" \
    common.txt container-native.txt

if [ "$(count_calls "${yay_log}")" -ne 2 ]; then
    fail "default package apply should invoke yay once per profile"
fi
if rg -q '^-Syu$|^--sysupgrade$' "${yay_log}"; then
    fail "default package apply must not perform a system upgrade"
fi
assert_contains '^-S$' "${yay_log}" \
    "default package apply should use the sync install operation"
assert_contains '^--needed$' "${yay_log}" \
    "default package apply should preserve installed packages"
if [ "$(cat "${pacman_log}")" != $'-Qu\n-Q' ]; then
    fail "default package apply must inspect pending system updates"
fi

: >"${yay_log}"
: >"${pacman_log}"
apply_package_profiles \
    "${repo_root}" 1 "${fake_yay}" "${fake_pacman}" common.txt

if [ "$(count_calls "${yay_log}")" -ne 2 ]; then
    fail "upgrade apply should run one upgrade and one profile install"
fi
first_call=$(sed -n '2p' "${yay_log}")
if [ "${first_call}" != "-Syu" ]; then
    fail "system upgrade must run before profile installation"
fi
if [ -s "${pacman_log}" ]; then
    fail "system upgrade path should not perform a redundant pending check"
fi

: >"${yay_log}"
export FAIL_UPGRADE=1
if apply_package_profiles \
    "${repo_root}" 1 "${fake_yay}" "${fake_pacman}" common.txt \
    >"${test_root}/upgrade-failure.stdout" \
    2>"${test_root}/upgrade-failure.stderr"; then
    fail "package helper continued after a failed system upgrade"
fi
unset FAIL_UPGRADE
if [ "$(count_calls "${yay_log}")" -ne 1 ]; then
    fail "failed system upgrade must stop before profile installation"
fi

: >"${yay_log}"
export FAIL_INSTALL=1
if apply_package_profiles \
    "${repo_root}" 0 "${fake_yay}" "${fake_pacman}" common.txt \
    >"${test_root}/install-failure.stdout" \
    2>"${test_root}/install-failure.stderr"; then
    fail "package helper accepted a failed profile installation"
fi
unset FAIL_INSTALL

call_count_before_missing=$(count_calls "${yay_log}")
if apply_package_profiles \
    "${repo_root}" yes "${fake_yay}" "${fake_pacman}" common.txt \
    >"${test_root}/invalid.stdout" 2>"${test_root}/invalid.stderr"; then
    fail "package helper accepted an invalid upgrade flag"
fi

if apply_package_profiles \
    "${repo_root}" 0 "${fake_yay}" "${fake_pacman}" missing.txt \
    >"${test_root}/missing.stdout" 2>"${test_root}/missing.stderr"; then
    fail "package helper accepted a missing profile"
fi
if [ "$(count_calls "${yay_log}")" -ne "${call_count_before_missing}" ]; then
    fail "missing profile validation reached yay"
fi

fixture_repo="${test_root}/fixture-repo"
mkdir -p "${fixture_repo}/packages"
printf '%s\n' readable-package >"${fixture_repo}/packages/readable.txt"
printf '%s\n' unreadable-package >"${fixture_repo}/packages/unreadable.txt"
chmod 000 "${fixture_repo}/packages/unreadable.txt"
: >"${yay_log}"
if apply_package_profiles \
    "${fixture_repo}" 1 "${fake_yay}" "${fake_pacman}" \
    readable.txt unreadable.txt \
    >"${test_root}/unreadable.stdout" \
    2>"${test_root}/unreadable.stderr"; then
    fail "package helper accepted an unreadable profile"
fi
if [ "$(count_calls "${yay_log}")" -ne 0 ]; then
    fail "unreadable profile validation reached yay"
fi
chmod 600 "${fixture_repo}/packages/unreadable.txt"

: >"${yay_log}"
: >"${pacman_log}"
export PACMAN_PENDING_UPDATES="linux 1.0 -> 1.1"
if apply_package_profiles \
    "${repo_root}" 0 "${fake_yay}" "${fake_pacman}" common.txt \
    >"${test_root}/pending.stdout" 2>"${test_root}/pending.stderr"; then
    fail "package helper installed profiles with pending system updates"
fi
unset PACMAN_PENDING_UPDATES
if [ "$(count_calls "${yay_log}")" -ne 0 ]; then
    fail "pending system updates reached yay"
fi

: >"${yay_log}"
export PACMAN_FAIL=1
if apply_package_profiles \
    "${repo_root}" 0 "${fake_yay}" "${fake_pacman}" common.txt \
    >"${test_root}/pacman-failure.stdout" \
    2>"${test_root}/pacman-failure.stderr"; then
    fail "package helper ignored a failed pending-update probe"
fi
unset PACMAN_FAIL
if [ "$(count_calls "${yay_log}")" -ne 0 ]; then
    fail "failed pending-update probe reached yay"
fi

if rg -q '^[[:space:]]*yay -Syu' \
    "${repo_root}/scripts/install/bootstrap.sh"; then
    fail "bootstrap still performs package upgrades directly"
fi

echo "install package tests passed"
