#!/usr/bin/env bash

set -euo pipefail

script_dir=$(CDPATH='' cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(CDPATH='' cd "${script_dir}/../.." && pwd)
dispatcher="${repo_root}/install.sh"
bootstrap="${repo_root}/scripts/install/bootstrap.sh"
test_root=$(mktemp -d)
trap 'rm -rf "${test_root}"' EXIT

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

if [ ! -x "${bootstrap}" ]; then
    fail "bootstrap implementation is missing or not executable"
fi

if [ "$(wc -l <"${dispatcher}")" -gt 10 ]; then
    fail "root install.sh must remain a thin dispatcher"
fi

if ! rg -q '^exec "\$\{SCRIPT_DIR\}/scripts/install/bootstrap\.sh" "\$@"$' \
    "${dispatcher}"; then
    fail "root install.sh must exec the bootstrap with unchanged arguments"
fi

run_and_capture() {
    local working_dir="$1"
    local command_path="$2"
    local stdout_path="$3"
    local stderr_path="$4"
    shift 4

    local status
    set +e
    (
        cd "${working_dir}"
        HOME="${test_root}/home" "${command_path}" "$@"
    ) >"${stdout_path}" 2>"${stderr_path}"
    status=$?
    set -e
    printf '%s\n' "${status}"
}

mkdir -p "${test_root}/home" "${test_root}/external-cwd"

dispatcher_status=$(run_and_capture \
    "${test_root}/external-cwd" "${dispatcher}" \
    "${test_root}/dispatcher.stdout" "${test_root}/dispatcher.stderr" \
    --link-only --dry-run --profile=wsl)
bootstrap_status=$(run_and_capture \
    "${test_root}/external-cwd" "${bootstrap}" \
    "${test_root}/bootstrap.stdout" "${test_root}/bootstrap.stderr" \
    --link-only --dry-run --profile=wsl)

if [ "${dispatcher_status}" -ne 0 ] || [ "${bootstrap_status}" -ne 0 ]; then
    fail "dispatcher and bootstrap should accept the link-only dry-run plan"
fi
if ! cmp -s "${test_root}/dispatcher.stdout" "${test_root}/bootstrap.stdout" \
    || ! cmp -s "${test_root}/dispatcher.stderr" "${test_root}/bootstrap.stderr"; then
    fail "dispatcher changed bootstrap output"
fi

dispatcher_status=$(run_and_capture \
    "${test_root}/external-cwd" "${dispatcher}" \
    "${test_root}/dispatcher-invalid.stdout" \
    "${test_root}/dispatcher-invalid.stderr" \
    --unsupported-option)
bootstrap_status=$(run_and_capture \
    "${test_root}/external-cwd" "${bootstrap}" \
    "${test_root}/bootstrap-invalid.stdout" \
    "${test_root}/bootstrap-invalid.stderr" \
    --unsupported-option)

if [ "${dispatcher_status}" -eq 0 ] || [ "${bootstrap_status}" -eq 0 ]; then
    fail "dispatcher and bootstrap should reject unknown options"
fi
if [ "${dispatcher_status}" -ne "${bootstrap_status}" ] \
    || ! cmp -s "${test_root}/dispatcher-invalid.stdout" \
        "${test_root}/bootstrap-invalid.stdout" \
    || ! cmp -s "${test_root}/dispatcher-invalid.stderr" \
        "${test_root}/bootstrap-invalid.stderr"; then
    fail "dispatcher changed bootstrap failure behavior"
fi

echo "install dispatcher tests passed"
