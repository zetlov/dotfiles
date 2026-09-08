#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(CDPATH='' cd "$(dirname "${BASH_SOURCE[0]}")/../.." >/dev/null && pwd)
HWORK="${ROOT_DIR}/stow/base/.local/bin/hwork"
HWORK_COMPLETION="${ROOT_DIR}/stow/base/.local/share/zsh/site-functions/_hwork"
ZSHRC="${ROOT_DIR}/stow/base/.zshrc"
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "${TEST_ROOT}"' EXIT

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

assert_file_contains() {
    local path="$1"
    local expected="$2"

    grep -Fq -- "${expected}" "${path}" \
        || fail "${path} does not contain: ${expected}"
}

assert_symlink_target() {
    local path="$1"
    local expected="$2"

    [ -L "${path}" ] || fail "expected symlink: ${path}"
    [ "$(realpath -m -- "${path}")" = "$(realpath -m -- "${expected}")" ] \
        || fail "unexpected symlink target: ${path}"
}

[ -f "${HWORK_COMPLETION}" ] || fail "hwork zsh completion is missing"
zsh -n "${HWORK_COMPLETION}" || fail "hwork zsh completion has invalid syntax"
HWORK_COMPLETION_DIR="${HWORK_COMPLETION%/*}" zsh -f -c '
    fpath=("${HWORK_COMPLETION_DIR}" ${fpath})
    autoload -Uz compinit
    compinit -D
    whence -w _hwork
' | grep -Fqx '_hwork: function' \
    || fail "compinit did not register hwork completion"
assert_file_contains "${ZSHRC}" '.local/share/zsh/site-functions'
assert_file_contains "${HWORK_COMPLETION}" "'-h[show command help]'"

TEST_HOME="${TEST_ROOT}/home"
TEST_DATA="${TEST_ROOT}/data"
TEST_STATE="${TEST_ROOT}/state"
TEST_BIN="${TEST_ROOT}/bin"
SOURCE_REPO="${TEST_ROOT}/project"
WORKTREE_ROOT="${TEST_ROOT}/worktrees"
HERDR_LOG="${TEST_ROOT}/herdr.log"

mkdir -p \
    "${TEST_HOME}" \
    "${TEST_DATA}" \
    "${TEST_STATE}" \
    "${TEST_BIN}" \
    "${WORKTREE_ROOT}"

git init -q -b main "${SOURCE_REPO}"
git -C "${SOURCE_REPO}" config user.name "Hwork Test"
git -C "${SOURCE_REPO}" config user.email "hwork@example.invalid"
printf 'tracked\n' >"${SOURCE_REPO}/README.md"
git -C "${SOURCE_REPO}" add README.md
git -C "${SOURCE_REPO}" commit -qm "test: initialize repository"

git -C "${SOURCE_REPO}" switch -qc tracked-local
printf 'tracked override\n' >"${SOURCE_REPO}/AGENTS.override.md"
git -C "${SOURCE_REPO}" add AGENTS.override.md
git -C "${SOURCE_REPO}" commit -qm "test: add tracked local override"
git -C "${SOURCE_REPO}" switch -q main

for shared_file in \
    .env \
    .env.local \
    mise.local.toml \
    CLAUDE.local.md \
    AGENTS.override.md; do
    printf 'shared:%s\n' "${shared_file}" >"${SOURCE_REPO}/${shared_file}"
done

cat >"${TEST_BIN}/herdr" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%q ' "$@" >>"${FAKE_HERDR_LOG}"
printf '\n' >>"${FAKE_HERDR_LOG}"

if [ "$1 $2" = "worktree create" ]; then
    shift 2
    branch=""
    cwd=""
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --branch) branch="$2"; shift 2 ;;
            --cwd) cwd="$2"; shift 2 ;;
            --base|--label) shift 2 ;;
            --focus|--no-focus) shift ;;
            *) printf 'unexpected create argument: %s\n' "$1" >&2; exit 2 ;;
        esac
    done
    if git -C "${cwd}" show-ref --verify --quiet "refs/heads/${branch}"; then
        git -C "${cwd}" worktree add -q "${FAKE_WORKTREE_PATH}" "${branch}"
    else
        git -C "${cwd}" worktree add -qb "${branch}" "${FAKE_WORKTREE_PATH}"
    fi
    if [ "${FAKE_CREATE_INVALID:-0}" = 1 ]; then
        jq -cn '{result:{type:"unexpected"}}'
        exit 0
    fi
    if [ "${FAKE_CREATE_FAIL_AFTER:-0}" = 1 ]; then
        printf 'fake failure after worktree creation\n' >&2
        exit 1
    fi
    jq -cn \
        --arg path "${FAKE_WORKTREE_PATH}" \
        --arg branch "${branch}" \
        '{result:{type:"worktree_created",workspace:{workspace_id:"w-test"},root_pane:{pane_id:"w-test:p1"},worktree:{path:$path,branch:$branch}}}'
elif [ "$1 $2" = "agent start" ]; then
    if [ "${FAKE_AGENT_FAIL:-0}" = 1 ]; then
        printf 'fake agent startup failure\n' >&2
        exit 1
    fi
    agent_name="$3"
    pane_id=""
    shift 3
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --kind) shift 2 ;;
            --pane) pane_id="$2"; shift 2 ;;
            --) shift; break ;;
            *) shift ;;
        esac
    done
    jq -cn --arg name "${agent_name}" --arg pane "${pane_id}" \
        '{result:{type:"agent_started",agent:{name:$name,pane_id:$pane},argv:[]}}'
elif [ "$1 $2" = "agent list" ]; then
    if [ "${FAKE_AGENT_ACTIVE:-0}" = 1 ]; then
        jq -cn \
            --arg name "${FAKE_ACTIVE_AGENT_NAME:-codex-alpha}" \
            --arg pane "${FAKE_ACTIVE_PANE_ID:-w-test:p1}" \
            '{result:{type:"agent_list",agents:[{name:$name,pane_id:$pane}]}}'
    else
        jq -cn '{result:{type:"agent_list",agents:[]}}'
    fi
elif [ "$1 $2" = "workspace get" ]; then
    jq -cn --arg path "${FAKE_WORKSPACE_PATH:-${FAKE_WORKTREE_PATH}}" \
        '{result:{type:"workspace_info",workspace:{workspace_id:"w-test",worktree:{checkout_path:$path}}}}'
elif [ "$1 $2" = "workspace focus" ]; then
    jq -cn '{result:{type:"workspace_focused"}}'
elif [ "$1 $2" = "worktree remove" ]; then
    if [ "${FAKE_REMOVE_FAIL:-0}" = 1 ]; then
        printf 'fake worktree removal failure\n' >&2
        exit 1
    fi
    git -C "${FAKE_SOURCE_REPO}" worktree remove "${FAKE_WORKTREE_PATH}"
    jq -cn '{result:{type:"worktree_removed"}}'
else
    printf 'unexpected herdr command: %s\n' "$*" >&2
    exit 2
fi
EOF
chmod +x "${TEST_BIN}/herdr"

run_hwork() {
    HOME="${TEST_HOME}" \
    XDG_DATA_HOME="${TEST_DATA}" \
    XDG_STATE_HOME="${TEST_STATE}" \
    PATH="${TEST_BIN}:${PATH}" \
    HERDR_ENV=1 \
    FAKE_HERDR_LOG="${HERDR_LOG}" \
    FAKE_SOURCE_REPO="${SOURCE_REPO}" \
    FAKE_WORKTREE_PATH="${FAKE_WORKTREE_PATH:-${WORKTREE_ROOT}/unused}" \
        "${HWORK}" "$@"
}

cd "${SOURCE_REPO}"
run_hwork init

if HWORK_DATA_HOME=relative run_hwork init \
    >"${TEST_ROOT}/relative-root.stdout" 2>"${TEST_ROOT}/relative-root.stderr"; then
    fail "init must reject a relative data root"
fi

shared_repo=$(find "${TEST_DATA}/hwork/repos" -mindepth 1 -maxdepth 1 -type d -print -quit)
[ -n "${shared_repo}" ] || fail "init did not create the shared repository directory"

for shared_file in \
    .env \
    .env.local \
    mise.local.toml \
    CLAUDE.local.md \
    AGENTS.override.md; do
    assert_symlink_target \
        "${SOURCE_REPO}/${shared_file}" \
        "${shared_repo}/files/${shared_file}"
    assert_file_contains "${shared_repo}/files/${shared_file}" "shared:${shared_file}"
done

run_hwork init

FAKE_WORKTREE_PATH="${WORKTREE_ROOT}/alpha"
export FAKE_WORKTREE_PATH
run_hwork start alpha --agent codex -- --model test-model

completion_tasks=$(run_hwork __complete tasks)
[ "${completion_tasks}" = alpha ] \
    || fail "task completion did not return the saved task"

for shared_file in \
    .env \
    .env.local \
    mise.local.toml \
    CLAUDE.local.md \
    AGENTS.override.md; do
    assert_symlink_target \
        "${FAKE_WORKTREE_PATH}/${shared_file}" \
        "${shared_repo}/files/${shared_file}"
done
if [ "$(stat -c '%a' "${shared_repo}/files/.env")" != 600 ]; then
    fail "init must restrict shared-file permissions"
fi
assert_file_contains "${HERDR_LOG}" "worktree create"
assert_file_contains "${HERDR_LOG}" "--branch work/alpha"
assert_file_contains "${HERDR_LOG}" "agent start"
assert_file_contains "${HERDR_LOG}" "--kind codex"
assert_file_contains "${HERDR_LOG}" "--model test-model"

if HERDR_WORKSPACE_ID=w-test run_hwork finish alpha \
    >"${TEST_ROOT}/self-finish.stdout" 2>"${TEST_ROOT}/self-finish.stderr"; then
    fail "finish must reject removal from the target workspace"
fi
[ -d "${FAKE_WORKTREE_PATH}" ] || fail "self-removal refusal removed the worktree"

if FAKE_WORKSPACE_PATH="${SOURCE_REPO}" run_hwork finish alpha \
    >"${TEST_ROOT}/wrong-workspace.stdout" 2>"${TEST_ROOT}/wrong-workspace.stderr"; then
    fail "finish must reject a workspace ID that resolves to another checkout"
fi
[ -d "${FAKE_WORKTREE_PATH}" ] || fail "workspace mismatch removed the worktree"

alpha_state=$(find "${TEST_STATE}/hwork/repos" -name 'alpha.json' -type f -print -quit)
alpha_agent_name=$(jq -r '.agent_name' "${alpha_state}")
if FAKE_AGENT_ACTIVE=1 \
    FAKE_ACTIVE_AGENT_NAME="${alpha_agent_name}" \
    FAKE_ACTIVE_PANE_ID="w-other:p9" \
    run_hwork finish alpha \
    >"${TEST_ROOT}/active.stdout" 2>"${TEST_ROOT}/active.stderr"; then
    fail "finish must reject an active agent"
fi
[ -d "${FAKE_WORKTREE_PATH}" ] || fail "active-agent refusal removed the worktree"

printf 'dirty\n' >>"${FAKE_WORKTREE_PATH}/README.md"
if run_hwork finish alpha \
    >"${TEST_ROOT}/dirty.stdout" 2>"${TEST_ROOT}/dirty.stderr"; then
    fail "finish must reject a dirty worktree"
fi
[ -d "${FAKE_WORKTREE_PATH}" ] || fail "dirty-worktree refusal removed the worktree"
git -C "${FAKE_WORKTREE_PATH}" restore README.md

run_hwork finish alpha
[ ! -e "${FAKE_WORKTREE_PATH}" ] || fail "finish did not remove the worktree"
git -C "${SOURCE_REPO}" show-ref --verify --quiet refs/heads/work/alpha \
    || fail "finish must preserve the branch"
if [ -n "$(run_hwork __complete tasks)" ]; then
    fail "task completion returned a finished task"
fi

git -C "${SOURCE_REPO}" branch work/suffix-test
FAKE_WORKTREE_PATH="${WORKTREE_ROOT}/suffix-test"
export FAKE_WORKTREE_PATH
run_hwork start suffix-test --agent claude
assert_file_contains "${HERDR_LOG}" "--branch work/suffix-test-2"
run_hwork finish suffix-test

repo_key="${shared_repo##*/}"
lock_path="${TEST_STATE}/hwork/repos/${repo_key}/locks/locked-task.lock"
mkdir -p "$(dirname "${lock_path}")"
exec 9>"${lock_path}"
flock -n 9
FAKE_WORKTREE_PATH="${WORKTREE_ROOT}/locked-task"
export FAKE_WORKTREE_PATH
if run_hwork start locked-task --agent codex \
    >"${TEST_ROOT}/locked.stdout" 2>"${TEST_ROOT}/locked.stderr"; then
    fail "start must reject a concurrently locked task"
fi
[ ! -e "${FAKE_WORKTREE_PATH}" ] || fail "locked task created a worktree"
flock -u 9
exec 9>&-

FAKE_WORKTREE_PATH="${WORKTREE_ROOT}/remove-fail"
export FAKE_WORKTREE_PATH
run_hwork start remove-fail --agent claude
if FAKE_REMOVE_FAIL=1 run_hwork finish remove-fail \
    >"${TEST_ROOT}/remove-fail.stdout" 2>"${TEST_ROOT}/remove-fail.stderr"; then
    fail "finish must report a Herdr removal failure"
fi
assert_symlink_target \
    "${FAKE_WORKTREE_PATH}/AGENTS.override.md" \
    "${shared_repo}/files/AGENTS.override.md"
[ -f "${TEST_STATE}/hwork/repos/${repo_key}/remove-fail.json" ] \
    || fail "failed removal discarded task state"
run_hwork finish remove-fail

FAKE_WORKTREE_PATH="${WORKTREE_ROOT}/invalid-response"
export FAKE_WORKTREE_PATH
if FAKE_CREATE_INVALID=1 run_hwork start invalid-response --agent codex \
    >"${TEST_ROOT}/invalid-response.stdout" 2>"${TEST_ROOT}/invalid-response.stderr"; then
    fail "start must reject an invalid Herdr worktree response"
fi
[ -d "${FAKE_WORKTREE_PATH}" ] || fail "invalid response test did not create its worktree fixture"
invalid_state="${TEST_STATE}/hwork/repos/${repo_key}/invalid-response.json"
[ -f "${invalid_state}" ] || fail "invalid Herdr response left no recovery state"
[ "$(jq -r '.status' "${invalid_state}")" = creating ] \
    || fail "invalid Herdr response did not preserve creating state"

FAKE_WORKTREE_PATH="${WORKTREE_ROOT}/create-failed"
export FAKE_WORKTREE_PATH
if FAKE_CREATE_FAIL_AFTER=1 run_hwork start create-failed --agent claude \
    >"${TEST_ROOT}/create-failed.stdout" 2>"${TEST_ROOT}/create-failed.stderr"; then
    fail "start must report failure after Herdr creates a checkout"
fi
create_failed_state="${TEST_STATE}/hwork/repos/${repo_key}/create-failed.json"
[ -f "${create_failed_state}" ] || fail "post-create failure left no recovery state"
[ "$(jq -r '.status' "${create_failed_state}")" = create_failed ] \
    || fail "post-create failure did not save create_failed state"
[ "$(jq -r '.worktree_path' "${create_failed_state}")" = "${FAKE_WORKTREE_PATH}" ] \
    || fail "post-create failure did not save the checkout path"

FAKE_WORKTREE_PATH="${WORKTREE_ROOT}/shared-change"
export FAKE_WORKTREE_PATH
run_hwork start shared-change --agent codex
printf 'changed by task\n' >>"${shared_repo}/files/AGENTS.override.md"
if run_hwork finish shared-change \
    >"${TEST_ROOT}/shared-change.stdout" 2>"${TEST_ROOT}/shared-change.stderr"; then
    fail "finish must reject an unreviewed shared-file change"
fi
[ -d "${FAKE_WORKTREE_PATH}" ] || fail "shared-file change refusal removed the worktree"
run_hwork finish shared-change --accept-shared-changes
printf 'shared:AGENTS.override.md\n' >"${shared_repo}/files/AGENTS.override.md"

FAKE_WORKTREE_PATH="${WORKTREE_ROOT}/agent-failure"
export FAKE_WORKTREE_PATH
if FAKE_AGENT_FAIL=1 run_hwork start agent-failure --agent codex \
    >"${TEST_ROOT}/agent-failure.stdout" \
    2>"${TEST_ROOT}/agent-failure.stderr"; then
    fail "start must report agent startup failure"
fi
[ -d "${FAKE_WORKTREE_PATH}" ] \
    || fail "agent startup failure must preserve the worktree"
find "${TEST_STATE}/hwork/repos" -name 'agent-failure.json' -type f -print -quit \
    | grep -q . || fail "agent startup failure must preserve state"

FAKE_WORKTREE_PATH="${WORKTREE_ROOT}/collision"
export FAKE_WORKTREE_PATH
if run_hwork start collision --agent codex --branch tracked-local \
    >"${TEST_ROOT}/collision.stdout" 2>"${TEST_ROOT}/collision.stderr"; then
    fail "start must reject a shared-file destination collision"
fi
[ -f "${FAKE_WORKTREE_PATH}/AGENTS.override.md" ] \
    || fail "collision handling removed the tracked destination"
grep -Fqx 'tracked override' "${FAKE_WORKTREE_PATH}/AGENTS.override.md" \
    || fail "collision handling overwrote the tracked destination"

TRACKED_REPO="${TEST_ROOT}/tracked-project"
git init -q -b main "${TRACKED_REPO}"
git -C "${TRACKED_REPO}" config user.name "Hwork Test"
git -C "${TRACKED_REPO}" config user.email "hwork@example.invalid"
printf 'tracked override\n' >"${TRACKED_REPO}/AGENTS.override.md"
git -C "${TRACKED_REPO}" add AGENTS.override.md
git -C "${TRACKED_REPO}" commit -qm "test: track an override file"
printf 'must remain local\n' >"${TRACKED_REPO}/.env"
cd "${TRACKED_REPO}"
if run_hwork init \
    >"${TEST_ROOT}/tracked-init.stdout" 2>"${TEST_ROOT}/tracked-init.stderr"; then
    fail "init must reject a tracked shared file"
fi
if [ ! -f "${TRACKED_REPO}/.env" ] || [ -L "${TRACKED_REPO}/.env" ]; then
    fail "failed init partially migrated an untracked file"
fi
assert_file_contains "${TRACKED_REPO}/.env" "must remain local"

printf 'hwork tests passed\n'
