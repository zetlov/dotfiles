#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CHECK_SCRIPT="${SCRIPT_DIR}/../security/check-public-tree.sh"

if [ ! -x "${CHECK_SCRIPT}" ]; then
    echo "FAIL: public boundary checker must be executable" >&2
    exit 1
fi

output_file=$(mktemp)
fixture_root=$(mktemp -d)
auth_fixture_root=$(mktemp -d)
trap 'rm -f "${output_file}"; rm -rf "${fixture_root}" "${auth_fixture_root}"' EXIT

"${CHECK_SCRIPT}" >/dev/null

mkdir -p "${fixture_root}/scripts/security" "${fixture_root}/.codex"
cp -- "${CHECK_SCRIPT}" "${fixture_root}/scripts/security/check-public-tree.sh"
printf 'private\n' > "${fixture_root}/.codex/config.toml"

if "${fixture_root}/scripts/security/check-public-tree.sh" >"${output_file}" 2>&1; then
    echo "FAIL: a sensitive path should fail the public boundary check" >&2
    exit 1
fi

if ! rg -q 'Denied sensitive path' "${output_file}"; then
    echo "FAIL: boundary failure should explain the public-data violation" >&2
    exit 1
fi

mkdir -p "${auth_fixture_root}/scripts/security" "${auth_fixture_root}/stow/base"
cp -- "${CHECK_SCRIPT}" "${auth_fixture_root}/scripts/security/check-public-tree.sh"
printf '//registry.example/:_authToken=example-secret\n' > "${auth_fixture_root}/stow/base/.npmrc"

if "${auth_fixture_root}/scripts/security/check-public-tree.sh" >"${output_file}" 2>&1; then
    echo "FAIL: a package-manager credential file should fail the public boundary check" >&2
    exit 1
fi

if ! rg -q 'Denied sensitive path' "${output_file}"; then
    echo "FAIL: credential-file failure should explain the public-data violation" >&2
    exit 1
fi

content_fixture_root="${fixture_root}/content"
mkdir -p "${content_fixture_root}/scripts/security" \
    "${content_fixture_root}/stow/base/.config/example"
cp -- "${CHECK_SCRIPT}" "${content_fixture_root}/scripts/security/check-public-tree.sh"
hidden_config="${content_fixture_root}/stow/base/.config/example/settings"

assert_content_rejected() {
    local label="$1"
    shift
    if "$@" >"${output_file}" 2>&1; then
        echo "FAIL: ${label} should fail the public boundary check" >&2
        exit 1
    fi
    if ! rg -q "${label}" "${output_file}"; then
        echo "FAIL: content failure should explain ${label}" >&2
        exit 1
    fi
}

printf '/%s/%s/config\n' home fixture-user >"${hidden_config}"
assert_content_rejected 'Absolute home path' \
    "${content_fixture_root}/scripts/security/check-public-tree.sh"
printf '%s@%s.com\n' fixture-user gmail >"${hidden_config}"
assert_content_rejected 'Personal email address' \
    "${content_fixture_root}/scripts/security/check-public-tree.sh"
printf 'fixture-private-identifier\n' >"${hidden_config}"
printf 'fixture-private-identifier\n' >"${fixture_root}/denylist"
assert_content_rejected 'Private local identifier' env \
    DOTFILES_DENYLIST="${fixture_root}/denylist" \
    "${content_fixture_root}/scripts/security/check-public-tree.sh"

printf 'public fixture\n' >"${hidden_config}"
assert_content_rejected 'Unable to scan' env \
    DOTFILES_DENYLIST="${content_fixture_root}" \
    "${content_fixture_root}/scripts/security/check-public-tree.sh"

echo "public boundary tests passed"
