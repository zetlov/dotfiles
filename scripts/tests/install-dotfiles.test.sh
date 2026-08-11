#!/usr/bin/env bash

set -euo pipefail

script_dir=$(CDPATH='' cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(CDPATH='' cd "${script_dir}/../.." && pwd)
helper="${repo_root}/scripts/install/dotfiles.sh"
bootstrap="${repo_root}/scripts/install/bootstrap.sh"
test_root=$(mktemp -d)
trap 'rm -rf "${test_root}"' EXIT

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

if [ ! -r "${helper}" ]; then
    fail "dotfiles install helper is missing"
fi

# shellcheck source=../install/dotfiles.sh
# shellcheck disable=SC1091
source "${helper}"

fixture_repo="${test_root}/repo"
call_log="${test_root}/calls.log"
mkdir -p "${fixture_repo}/scripts" "${test_root}/home"

cat >"${fixture_repo}/scripts/init-local-config.sh" <<EOF
#!/usr/bin/env bash
printf 'init:%s\n' "\$*" >>"${call_log}"
if [ "\${FAIL_INIT:-0}" = "1" ]; then
    exit 17
fi
EOF
cat >"${fixture_repo}/scripts/stow-dotfiles.sh" <<EOF
#!/usr/bin/env bash
printf 'stow:%s\n' "\$*" >>"${call_log}"
if [ "\${FAIL_STOW:-0}" = "1" ]; then
    exit 18
fi
EOF
chmod +x \
    "${fixture_repo}/scripts/init-local-config.sh" \
    "${fixture_repo}/scripts/stow-dotfiles.sh"

HOME="${test_root}/home" preflight_dotfiles "${fixture_repo}" wsl
expected_preflight=$'init:--dry-run --profile=wsl\nstow:--profile=wsl --preflight'
if [ "$(cat "${call_log}")" != "${expected_preflight}" ]; then
    fail "dotfiles preflight invoked an unexpected command sequence"
fi

: >"${call_log}"
HOME="${test_root}/home" apply_dotfiles "${fixture_repo}" desktop
expected_apply=$'init:--profile=desktop\nstow:--profile=desktop'
if [ "$(cat "${call_log}")" != "${expected_apply}" ]; then
    fail "dotfiles apply invoked an unexpected command sequence"
fi

: >"${call_log}"
export FAIL_INIT=1
if HOME="${test_root}/home" preflight_dotfiles "${fixture_repo}" desktop \
    >/dev/null 2>&1; then
    fail "dotfiles preflight ignored local configuration validation failure"
fi
unset FAIL_INIT
if rg -q '^stow:' "${call_log}"; then
    fail "dotfiles preflight continued after local configuration failure"
fi

isolated_path="${test_root}/isolated-path"
empty_home="${test_root}/empty-home"
mkdir -p "${isolated_path}" "${empty_home}"
ln -s "$(command -v bash)" "${isolated_path}/bash"
: >"${call_log}"
if PATH="${isolated_path}" HOME="${empty_home}" \
    apply_dotfiles "${fixture_repo}" desktop \
    >"${test_root}/missing-stow.stdout" \
    2>"${test_root}/missing-stow.stderr"; then
    fail "dotfiles apply accepted a missing stow executable"
fi
if find "${empty_home}" -mindepth 1 -print -quit | rg -q .; then
    fail "missing stow must fail before dotfiles apply mutates HOME"
fi
if [ -s "${call_log}" ]; then
    fail "missing stow reached a dotfiles mutation command"
fi

preflight_line=$(rg -n '^preflight_dotfiles ' "${bootstrap}" | cut -d: -f1)
packages_line=$(rg -n '^apply_package_profiles ' "${bootstrap}" | cut -d: -f1)
apply_line=$(rg -n '^apply_dotfiles ' "${bootstrap}" | cut -d: -f1)
if [ -z "${preflight_line}" ] || [ -z "${packages_line}" ] \
    || [ -z "${apply_line}" ]; then
    fail "bootstrap does not expose the dotfiles preflight/apply boundaries"
fi
if [ "${preflight_line}" -ge "${packages_line}" ] \
    || [ "${apply_line}" -le "${packages_line}" ]; then
    fail "dotfiles preflight must precede package mutation and apply must follow it"
fi

echo "install dotfiles tests passed"
