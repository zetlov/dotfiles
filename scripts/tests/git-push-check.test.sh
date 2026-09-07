#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
HOOK="${SCRIPT_DIR}/../../stow/assistant/.claude/scripts/git-push-check.sh"
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "${TEST_ROOT}"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
git init -q -b main "${TEST_ROOT}/repo"
git -C "${TEST_ROOT}/repo" remote add origin https://example.invalid/owner/repo.git

assert_hook() {
    local expected="$1" command_text="$2" status=0
    jq -cn --arg command "${command_text}" '{tool_input:{command:$command}}' \
        | (cd "${TEST_ROOT}/repo" && OWNER_GATED_REPO_PATTERN=example.invalid bash "${HOOK}") \
        >"${TEST_ROOT}/stdout" 2>"${TEST_ROOT}/stderr" || status=$?
    if [ "${status}" -ne "${expected}" ]; then
        printf 'FAIL: hook returned %s instead of %s for %s\n' "${status}" "${expected}" "${command_text}" >&2
        exit 1
    fi
}

assert_hook 2 'git push'
assert_hook 2 'git push origin'
assert_hook 2 'git push -u origin'
assert_hook 2 'git push origin main'
assert_hook 2 'git push origin HEAD'
assert_hook 2 'git push origin HEAD:refs/heads/main'
assert_hook 2 'git push origin --delete main'
assert_hook 2 'git push --all origin'
assert_hook 2 'git push --mirror origin'
assert_hook 2 'git push origin :'
assert_hook 0 'git push origin feature'
assert_hook 0 'git push origin HEAD:feature'
assert_hook 0 'git push origin main:feature'
assert_hook 0 'git push -o ci.skip origin HEAD:feature'
assert_hook 0 'git push --repo=origin HEAD:feature'
assert_hook 0 'git push --tags origin'
assert_hook 0 'OWNER_PUSH_OK=1 git push'
assert_hook 0 'OWNER_PUSH_OK=1 git push --mirror origin'

git -C "${TEST_ROOT}/repo" symbolic-ref HEAD refs/heads/feature
assert_hook 0 'git push'
assert_hook 2 'git push --all origin'
git -C "${TEST_ROOT}/repo" config push.default matching
assert_hook 2 'git push'
git -C "${TEST_ROOT}/repo" config push.default current
git -C "${TEST_ROOT}/repo" config remote.origin.push HEAD:refs/heads/main
assert_hook 2 'git push origin'
assert_hook 2 'git push origin HEAD'
assert_hook 0 'git push origin HEAD:feature'
git -C "${TEST_ROOT}/repo" config remote.origin.push HEAD:refs/heads/feature
assert_hook 0 'git push origin'
git -C "${TEST_ROOT}/repo" config --unset remote.origin.push
git -C "${TEST_ROOT}/repo" config push.default upstream
git -C "${TEST_ROOT}/repo" config branch.feature.remote origin
git -C "${TEST_ROOT}/repo" config branch.feature.merge refs/heads/main
assert_hook 2 'git push'
git -C "${TEST_ROOT}/repo" config push.default current
assert_hook 2 'git switch main && git push'
assert_hook 2 $'git push origin feature\ngit push origin main'

echo "git push hook tests passed"
