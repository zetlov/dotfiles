#!/usr/bin/env bash

set -eu

SCRIPT_DIR=$(CDPATH= cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DOTFILES_DIR="${DOTFILES_DIR:-$(CDPATH= cd "${SCRIPT_DIR}/.." && pwd)}"
readonly STOW_PACKAGES=(base desktop assistant)

resolve_root_path() {
    local name="$1"
    local value="$2"
    local resolved

    if [ -z "${value}" ] || [[ "${value}" != /* ]] || [ ! -d "${value}" ]; then
        echo "${name} must be an existing absolute directory." >&2
        return 1
    fi
    if ! resolved=$(readlink -f -- "${value}"); then
        echo "Could not resolve ${name}: ${value}" >&2
        return 1
    fi
    if [ "${resolved}" = "/" ]; then
        echo "${name} must be a non-root absolute path." >&2
        return 1
    fi
    printf '%s\n' "${resolved}"
}

HOME=$(resolve_root_path "HOME" "${HOME}")
DOTFILES_DIR=$(resolve_root_path "DOTFILES_DIR" "${DOTFILES_DIR}")
readonly STOW_ROOT="${DOTFILES_DIR}/stow"

if ! command -v stow >/dev/null 2>&1; then
    echo "GNU Stow is required to link dotfiles." >&2
    exit 1
fi

for package in "${STOW_PACKAGES[@]}"; do
    if [ ! -d "${STOW_ROOT}/${package}" ]; then
        echo "Required Stow package not found: ${STOW_ROOT}/${package}" >&2
        exit 1
    fi
done

declare -A source_by_target=()
declare -a managed_sources=()
declare -a managed_targets=()
declare -a legacy_sources=()
declare -a legacy_targets=()
declare -a removed_legacy_sources=()
declare -a removed_legacy_targets=()

collect_managed_files() {
    local package
    local package_root
    local relative_path
    local source_path
    local target_path

    for package in "${STOW_PACKAGES[@]}"; do
        package_root="${STOW_ROOT}/${package}"
        while IFS= read -r -d '' source_path; do
            relative_path="${source_path#"${package_root}/"}"
            target_path="${HOME}/${relative_path}"
            if [[ -v "source_by_target[${target_path}]" ]]; then
                printf 'Duplicate Stow target %s is owned by both %s and %s.\n' \
                    "${target_path}" \
                    "${source_by_target[${target_path}]}" \
                    "${source_path}" >&2
                return 1
            fi
            source_by_target["${target_path}"]="${source_path}"
            managed_sources+=("${source_path}")
            managed_targets+=("${target_path}")
        done < <(find "${package_root}" -mindepth 1 \
            \( -type f -o -type l \) -print0)
    done
}

validate_target_parents() {
    local target_path="$1"
    local parent_path

    parent_path=$(dirname -- "${target_path}")
    while [ "${parent_path}" != "${HOME}" ]; do
        if [[ "${parent_path}" != "${HOME}/"* ]]; then
            echo "Managed target escapes HOME: ${target_path}" >&2
            return 1
        fi
        if [ -L "${parent_path}" ]; then
            echo "Managed target parent must not be a symlink: ${parent_path}" >&2
            return 1
        fi
        if [ -e "${parent_path}" ] && [ ! -d "${parent_path}" ]; then
            echo "Managed target parent is not a directory: ${parent_path}" >&2
            return 1
        fi
        parent_path=$(dirname -- "${parent_path}")
    done
}

resolve_link_target() {
    local link_path="$1"
    local link_value
    local candidate

    link_value=$(readlink -- "${link_path}")
    if [[ "${link_value}" = /* ]]; then
        candidate="${link_value}"
    else
        candidate="$(dirname -- "${link_path}")/${link_value}"
    fi
    realpath -m -- "${candidate}"
}

is_repository_path() {
    local candidate="$1"
    [[ "${candidate}" = "${DOTFILES_DIR}" \
        || "${candidate}" = "${DOTFILES_DIR}/"* ]]
}

preflight_target() {
    local source_path="$1"
    local target_path="$2"
    local link_value
    local resolved_source
    local resolved_target

    validate_target_parents "${target_path}" || return 1
    if [ ! -e "${target_path}" ] && [ ! -L "${target_path}" ]; then
        return
    fi
    if [ ! -L "${target_path}" ]; then
        if [ "${target_path}" = "${HOME}/.zshrc" ]; then
            return
        fi
        echo "Managed target conflicts with an existing path: ${target_path}" >&2
        return 1
    fi

    link_value=$(readlink -- "${target_path}")
    resolved_source=$(realpath -m -- "${source_path}")
    resolved_target=$(resolve_link_target "${target_path}")
    if [ "${resolved_target}" = "${resolved_source}" ] \
        && [[ "${link_value}" != /* ]]; then
        return
    fi
    if ! is_repository_path "${resolved_target}"; then
        echo "Managed target conflicts with a foreign symlink: ${target_path}" >&2
        return 1
    fi
    legacy_sources+=("${source_path}")
    legacy_targets+=("${target_path}")
}

preflight_managed_files() {
    local index

    for index in "${!managed_sources[@]}"; do
        preflight_target \
            "${managed_sources[${index}]}" \
            "${managed_targets[${index}]}" || return 1
    done
}

transaction_complete=0
backup_root=""
zshrc_backup=""

restore_file() {
    local backup_path="$1"
    local target_path="$2"
    local label="$3"

    if [ -z "${backup_path}" ]; then
        return
    fi
    if [ -e "${target_path}" ] || [ -L "${target_path}" ]; then
        echo "Could not restore ${label}; backup retained at ${backup_path}" >&2
        return
    fi
    if mv -- "${backup_path}" "${target_path}"; then
        echo "Restored ${label} after Stow failed"
    else
        echo "Failed to restore ${label}; backup retained at ${backup_path}" >&2
    fi
}

restore_managed_link() {
    local source_path="$1"
    local target_path="$2"

    if [ -L "${target_path}" ] \
        && [ "$(resolve_link_target "${target_path}")" = \
            "$(realpath -m -- "${source_path}")" ]; then
        return
    fi
    if [ -e "${target_path}" ] || [ -L "${target_path}" ]; then
        echo "Could not restore managed link; target is already present: ${target_path}" >&2
        return
    fi
    mkdir -p -- "$(dirname -- "${target_path}")"
    if ln -s -- "${source_path}" "${target_path}"; then
        echo "Restored managed link after Stow failed: ${target_path}"
    else
        echo "Failed to restore managed link: ${target_path}" >&2
    fi
}

rollback() {
    local exit_status=$?
    local index

    if [ "${transaction_complete}" -eq 1 ]; then
        return
    fi

    set +e
    restore_file "${zshrc_backup}" "${HOME}/.zshrc" "Zsh config"
    for index in "${!removed_legacy_sources[@]}"; do
        restore_managed_link \
            "${removed_legacy_sources[${index}]}" \
            "${removed_legacy_targets[${index}]}"
    done
    if [ -n "${zshrc_backup}" ] && [ -e "${zshrc_backup}" ]; then
        echo "Zsh config backup retained at ${zshrc_backup}" >&2
    fi
    if [ -n "${backup_root}" ] && [ -d "${backup_root}" ]; then
        rmdir -- "${backup_root}" 2>/dev/null || true
    fi
    return "${exit_status}"
}

trap rollback EXIT
trap 'exit 130' HUP INT TERM

ensure_backup_root() {
    if [ -z "${backup_root}" ]; then
        backup_root=$(mktemp -d "${HOME}/.dotfiles-stow-backup.XXXXXXXX")
    fi
}

collect_managed_files
preflight_managed_files

zshrc_source="${STOW_ROOT}/base/.zshrc"
zshrc_target="${HOME}/.zshrc"
if { [ -e "${zshrc_target}" ] || [ -L "${zshrc_target}" ]; } \
    && [ ! -L "${zshrc_target}" ]; then
    ensure_backup_root
    zshrc_backup="${backup_root}/zshrc"
    mv -- "${zshrc_target}" "${zshrc_backup}"
    echo "Backed up existing Zsh config to ${zshrc_backup}"
fi

for index in "${!legacy_targets[@]}"; do
    rm -- "${legacy_targets[${index}]}"
    removed_legacy_sources+=("${legacy_sources[${index}]}")
    removed_legacy_targets+=("${legacy_targets[${index}]}")
    echo "Migrating legacy dotfiles link: ${legacy_targets[${index}]}"
done

if ! stow \
    -v \
    --no-folding \
    --dir "${STOW_ROOT}" \
    --target "${HOME}" \
    "${STOW_PACKAGES[@]}"; then
    exit 1
fi

transaction_complete=1
