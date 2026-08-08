#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
INIT_SCRIPT="${SCRIPT_DIR}/../init-local-config.sh"
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "${TEST_ROOT}"' EXIT

test_home="${TEST_ROOT}/home"
mkdir -p "${test_home}/.codex"

HOME="${test_home}" "${INIT_SCRIPT}" --dry-run
if find "${test_home}" -type f | grep -q .; then
    echo "FAIL: dry-run must not create local configuration" >&2
    exit 1
fi

HOME="${test_home}" "${INIT_SCRIPT}"
for expected in \
    .codex/config.toml \
    .claude/settings.json \
    .gitconfig.local \
    .config/hypr/settings.local.lua \
    .config/atcoder-cli-nodejs/config.json \
    .config/switch-audio/config.env \
    .config/zetshell/dashboard.json \
    .config/zetshell/file_search.json \
    .config/zetshell/launcher.json \
    .config/zetshell/quicklinks.json \
    .config/zetshell/settings.env; do
    if [ ! -f "${test_home}/${expected}" ]; then
        echo "FAIL: missing initialized local file: ${expected}" >&2
        exit 1
    fi
done

for hook in PreToolUse PostToolUse PreCompact Stop SessionStart; do
    if ! jq -e --arg hook "${hook}" '.hooks[$hook] | length > 0' \
        "${test_home}/.claude/settings.json" >/dev/null; then
        echo "FAIL: initialized Claude settings should register ${hook}" >&2
        exit 1
    fi
done
if jq -e '.hooks.PostCompact' "${test_home}/.claude/settings.json" >/dev/null; then
    echo "FAIL: PostCompact must not return unsupported context output" >&2
    exit 1
fi
if ! jq -e '
    .hooks.SessionStart[]
    | select(.matcher == "compact")
    | .hooks[]
    | select(.command == "bash ~/.claude/scripts/compact-session-anchor.sh")
' "${test_home}/.claude/settings.json" >/dev/null; then
    echo "FAIL: compaction re-anchor should run from SessionStart(compact)" >&2
    exit 1
fi

git_config="${test_home}/.gitconfig.local"
if [ "$(git config --file "${git_config}" user.name)" != "zetlov" ]; then
    echo "FAIL: initialized Git name should be zetlov" >&2
    exit 1
fi
if [ "$(git config --file "${git_config}" user.email)" != "90176249+zetlov@users.noreply.github.com" ]; then
    echo "FAIL: initialized Git email should use the GitHub noreply address" >&2
    exit 1
fi
if grep -Eqi '@(gmail|outlook|hotmail|icloud|yahoo)\.' "${git_config}"; then
    echo "FAIL: initialized Git config must not contain a personal email domain" >&2
    exit 1
fi

printf 'keep me\n' > "${test_home}/.codex/config.toml"
cat > "${test_home}/.gitconfig.local" <<'EOF'
[user]
	name = Local Override
	email = local@example.invalid
EOF
HOME="${test_home}" "${INIT_SCRIPT}"
if [ "$(cat "${test_home}/.codex/config.toml")" != "keep me" ]; then
    echo "FAIL: existing local configuration must not be overwritten" >&2
    exit 1
fi
if [ "$(git config --file "${git_config}" user.name)" != "Local Override" ] || \
    [ "$(git config --file "${git_config}" user.email)" != "local@example.invalid" ]; then
    echo "FAIL: existing local Git identity must not be overwritten" >&2
    exit 1
fi

echo "local config tests passed"
