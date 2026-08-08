#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(CDPATH= cd "${SCRIPT_DIR}/.." && pwd)
DRY_RUN=0

if [ "${1:-}" = "--dry-run" ]; then
    DRY_RUN=1
    shift
fi
if [ "$#" -ne 0 ]; then
    echo "Usage: $0 [--dry-run]" >&2
    exit 1
fi
if [ -z "${HOME:-}" ] || [[ "${HOME}" != /* ]] || [ ! -d "${HOME}" ]; then
    echo "HOME must be an existing absolute directory." >&2
    exit 1
fi

copy_if_missing() {
    local relative_source="$1"
    local relative_target="$2"
    local source_path="${REPO_ROOT}/examples/local/${relative_source}"
    local target_path="${HOME}/${relative_target}"

    if [ ! -f "${source_path}" ]; then
        echo "Missing local configuration example: ${source_path}" >&2
        return 1
    fi
    if [ -e "${target_path}" ] || [ -L "${target_path}" ]; then
        printf 'keep %s\n' "${target_path}"
        return
    fi
    if [ "${DRY_RUN}" -eq 1 ]; then
        printf 'create %s\n' "${target_path}"
        return
    fi

    install -D -m 0600 -- "${source_path}" "${target_path}"
    printf 'created %s\n' "${target_path}"
}

copy_if_missing "codex/config.toml" ".codex/config.toml"
copy_if_missing "claude/settings.json" ".claude/settings.json"
copy_if_missing "gitconfig.local" ".gitconfig.local"
copy_if_missing "hypr/settings.local.lua" ".config/hypr/settings.local.lua"
copy_if_missing "atcoder-cli-nodejs/config.json" ".config/atcoder-cli-nodejs/config.json"
copy_if_missing "switch-audio/config.env" ".config/switch-audio/config.env"
copy_if_missing "zetshell/dashboard.json" ".config/zetshell/dashboard.json"
copy_if_missing "zetshell/file_search.json" ".config/zetshell/file_search.json"
copy_if_missing "zetshell/launcher.json" ".config/zetshell/launcher.json"
copy_if_missing "zetshell/quicklinks.json" ".config/zetshell/quicklinks.json"
copy_if_missing "zetshell/settings.env" ".config/zetshell/settings.env"
