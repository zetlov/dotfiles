#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(CDPATH= cd "${SCRIPT_DIR}/.." && pwd)
DRY_RUN=0
PROFILE=desktop

for arg in "$@"; do
    case "${arg}" in
        --dry-run) DRY_RUN=1 ;;
        --profile=desktop) PROFILE=desktop ;;
        --profile=wsl) PROFILE=wsl ;;
        --profile=*) echo "Local config profile must be desktop or wsl." >&2; exit 2 ;;
        *) echo "Unknown option: ${arg}" >&2; exit 2 ;;
    esac
done
if [ -z "${HOME:-}" ] || [[ "${HOME}" != /* ]] || [ ! -d "${HOME}" ]; then
    echo "HOME must be an existing absolute directory." >&2
    exit 1
fi
HOME=$(readlink -f -- "${HOME}")
if [ "${HOME}" = "/" ]; then
    echo "HOME must be a non-root absolute directory." >&2
    exit 1
fi

declare -a local_sources=(
    "codex/config.toml"
    "claude/settings.json"
    "gitconfig.local"
    "atcoder-cli-nodejs/config.json"
)
declare -a local_targets=(
    ".codex/config.toml"
    ".claude/settings.json"
    ".gitconfig.local"
    ".config/atcoder-cli-nodejs/config.json"
)

if [ "${PROFILE}" = "desktop" ]; then
    local_sources+=(
        "hypr/settings.local.lua"
        "switch-audio/config.env"
        "zetshell/dashboard.json"
        "zetshell/file_search.json"
        "zetshell/launcher.json"
        "zetshell/quicklinks.json"
        "zetshell/settings.env"
    )
    local_targets+=(
        ".config/hypr/settings.local.lua"
        ".config/switch-audio/config.env"
        ".config/zetshell/dashboard.json"
        ".config/zetshell/file_search.json"
        ".config/zetshell/launcher.json"
        ".config/zetshell/quicklinks.json"
        ".config/zetshell/settings.env"
    )
fi

validate_target_parent() {
    local target_path="$1"
    local parent_path

    parent_path=$(dirname -- "${target_path}")
    while [ "${parent_path}" != "${HOME}" ]; do
        if [[ "${parent_path}" != "${HOME}/"* ]]; then
            echo "Local config target escapes HOME: ${target_path}" >&2
            return 1
        fi
        if [ -L "${parent_path}" ]; then
            echo "Local config target parent must not be a symlink: ${parent_path}" >&2
            return 1
        fi
        if [ -e "${parent_path}" ] && [ ! -d "${parent_path}" ]; then
            echo "Local config target parent is not a directory: ${parent_path}" >&2
            return 1
        fi
        parent_path=$(dirname -- "${parent_path}")
    done
}

for index in "${!local_sources[@]}"; do
    source_path="${REPO_ROOT}/examples/local/${local_sources[${index}]}"
    target_path="${HOME}/${local_targets[${index}]}"
    if [ ! -f "${source_path}" ]; then
        echo "Missing local configuration example: ${source_path}" >&2
        exit 1
    fi
    validate_target_parent "${target_path}"
done

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

for index in "${!local_sources[@]}"; do
    copy_if_missing \
        "${local_sources[${index}]}" \
        "${local_targets[${index}]}"
done
