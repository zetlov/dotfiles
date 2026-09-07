#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(CDPATH= cd "${SCRIPT_DIR}/../.." && pwd)

deny_path_pattern='(^|/)(\.env($|\.)|\.zsh_secrets$|\.netrc$|\.npmrc$|\.pypirc$|hosts\.yml$|session\.json$|credentials$|\.refresh_token[^/]*$|\.user_cache[^/]*$|cloud\.settings$|\.server\.lock$|\.session\.ipc$|id_(rsa|ed25519)$|[^/]*\.(pem|key|p12|pfx|kdbx)$)|(^|/)\.(aws|azure|kube)(/|$)|(^|/)\.config/(TabNine|mozc|gcloud)(/|$)|(^|/)\.docker/config\.json$|(^|/)\.gem/credentials$|(^|/)\.codex/(auth\.json|config\.toml)$|(^|/)\.claude/settings(\.local)?\.json$|(^|/)\.claude-work(/|$)'

list_public_files() {
    find "${REPO_ROOT}" \
        -path "${REPO_ROOT}/.git" -prune -o \
        -type f -printf '%P\n'
}

if denied_paths=$(list_public_files | LC_ALL=C sort | rg -i "${deny_path_pattern}"); then
    printf 'Denied sensitive path in public tree:\n%s\n' "${denied_paths}" >&2
    exit 1
fi

check_content() {
    local label="$1"
    shift
    local matches
    local status

    if matches=$(rg --no-config --hidden -I -l "$@" "${REPO_ROOT}" \
        --glob '!.git/**'); then
        printf '%s in public tree:\n%s\n' "${label}" "${matches}" >&2
        return 1
    else
        status=$?
    fi
    if [ "${status}" -ne 1 ]; then
        printf 'Unable to scan public tree for %s.\n' "${label}" >&2
        return 1
    fi
}

check_content 'Absolute home path' '/home/[A-Za-z0-9._-]+/' \
    --glob '!scripts/security/check-public-tree.sh'
check_content 'Personal email address' \
    '[A-Za-z0-9._%+-]+@(gmail|outlook|hotmail|icloud)\.com'

if [ -n "${DOTFILES_DENYLIST:-}" ]; then
    if [ ! -r "${DOTFILES_DENYLIST}" ]; then
        echo "DOTFILES_DENYLIST must point to a readable file." >&2
        exit 1
    fi
    check_content 'Private local identifier' -F -f "${DOTFILES_DENYLIST}"
fi

while IFS= read -r -d '' link; do
    resolved=$(realpath -m -- "${link}")
    case "${resolved}" in
        "${REPO_ROOT}"/*) ;;
        *)
            printf 'Symlink escapes repository: %s\n' "${link#"${REPO_ROOT}/"}" >&2
            exit 1
            ;;
    esac
done < <(find "${REPO_ROOT}" -path "${REPO_ROOT}/.git" -prune -o -type l -print0)

if git -C "${REPO_ROOT}" rev-parse --verify HEAD >/dev/null 2>&1; then
    if denied_history=$(git -C "${REPO_ROOT}" log --all --format= --name-only \
        | LC_ALL=C sort -u \
        | rg -i "${deny_path_pattern}"); then
        printf 'Denied sensitive path in Git history:\n%s\n' "${denied_history}" >&2
        exit 1
    fi
fi

echo "public tree boundary check passed"
