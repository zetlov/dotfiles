#!/usr/bin/env bash

set -eu

SCRIPT_DIR=$(CDPATH= cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
STOW_SCRIPT="${SCRIPT_DIR}/../stow-dotfiles.sh"
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "${TEST_ROOT}"' EXIT

assert_equal() {
    local actual="$1"
    local expected="$2"
    local message="$3"
    if [ "${actual}" != "${expected}" ]; then
        printf 'FAIL: %s\nexpected: %s\nactual:   %s\n' \
            "${message}" "${expected}" "${actual}" >&2
        exit 1
    fi
}

create_fixture() {
    local fixture_root="$1"
    local repo="${fixture_root}/repo"
    local home="${fixture_root}/home"

    mkdir -p \
        "${repo}/stow/base/.config/herdr" \
        "${repo}/stow/desktop/.config/hypr" \
        "${repo}/stow/assistant/.claude" \
        "${repo}/stow/assistant/.codex" \
        "${repo}/stow/extra" \
        "${repo}/scripts" \
        "${home}/.claude" \
        "${home}/.codex"
    printf 'base zsh\n' > "${repo}/stow/base/.zshrc"
    printf 'herdr\n' > "${repo}/stow/base/.config/herdr/config.toml"
    printf 'desktop\n' > "${repo}/stow/desktop/.config/hypr/hyprland.lua"
    printf 'claude\n' > "${repo}/stow/assistant/.claude/CLAUDE.md"
    printf 'codex\n' > "${repo}/stow/assistant/.codex/AGENTS.md"
    printf 'extra\n' > "${repo}/stow/extra/.extra"
    printf 'operational\n' > "${repo}/scripts/not-a-dotfile"
    printf '%s\n' "${repo}" "${home}"
}

test_links_exact_package_set() {
    local fixture_root="${TEST_ROOT}/packages"
    local paths
    local repo
    local home
    paths=$(create_fixture "${fixture_root}")
    repo=$(printf '%s\n' "${paths}" | sed -n '1p')
    home=$(printf '%s\n' "${paths}" | sed -n '2p')

    printf 'local settings\n' > "${home}/.claude/settings.local.json"
    printf 'session summary\n' > "${home}/.claude/session-summary.md"
    printf 'auth state\n' > "${home}/.codex/auth.json"

    HOME="${home}" DOTFILES_DIR="${repo}" "${STOW_SCRIPT}"
    HOME="${home}" DOTFILES_DIR="${repo}" "${STOW_SCRIPT}"

    assert_equal \
        "$(readlink -f "${home}/.zshrc")" \
        "${repo}/stow/base/.zshrc" \
        "The base package should be linked"
    assert_equal \
        "$(readlink -f "${home}/.config/hypr/hyprland.lua")" \
        "${repo}/stow/desktop/.config/hypr/hyprland.lua" \
        "The desktop package should be linked"
    assert_equal \
        "$(readlink -f "${home}/.claude/CLAUDE.md")" \
        "${repo}/stow/assistant/.claude/CLAUDE.md" \
        "The assistant package should be linked"
    assert_equal \
        "$(test -e "${home}/scripts/not-a-dotfile" && printf present || printf absent)" \
        "absent" \
        "Repository operational files should not be linked"
    assert_equal \
        "$(test -e "${home}/.extra" && printf present || printf absent)" \
        "absent" \
        "Only the fixed package set should be linked"
    assert_equal \
        "$(test -d "${home}/.config" && ! test -L "${home}/.config" && printf directory || printf invalid)" \
        "directory" \
        ".config should remain a real directory"
    assert_equal \
        "$(test -d "${home}/.claude" && ! test -L "${home}/.claude" && printf directory || printf invalid)" \
        "directory" \
        ".claude should remain a real directory"
    assert_equal \
        "$(test -d "${home}/.codex" && ! test -L "${home}/.codex" && printf directory || printf invalid)" \
        "directory" \
        ".codex should remain a real directory"
    assert_equal \
        "$(cat "${home}/.claude/settings.local.json"; cat "${home}/.claude/session-summary.md"; cat "${home}/.codex/auth.json")" \
        "$(printf 'local settings\nsession summary\nauth state')" \
        "Local assistant state should remain unchanged"
}

test_migrates_legacy_absolute_links() {
    local fixture_root="${TEST_ROOT}/migration"
    local paths
    local repo
    local home
    paths=$(create_fixture "${fixture_root}")
    repo=$(printf '%s\n' "${paths}" | sed -n '1p')
    home=$(printf '%s\n' "${paths}" | sed -n '2p')

    mkdir -p "${home}/.config/herdr" "${home}/.config/hypr"
    ln -s "${repo}/.zshrc" "${home}/.zshrc"
    ln -s "${repo}/.config/herdr/config.toml" "${home}/.config/herdr/config.toml"
    ln -s "${repo}/.config/hypr/hyprland.lua" "${home}/.config/hypr/hyprland.lua"
    ln -s "${repo}/.claude/CLAUDE.md" "${home}/.claude/CLAUDE.md"
    ln -s "${repo}/.codex/AGENTS.md" "${home}/.codex/AGENTS.md"

    HOME="${home}" DOTFILES_DIR="${repo}" "${STOW_SCRIPT}"
    HOME="${home}" DOTFILES_DIR="${repo}" "${STOW_SCRIPT}"

    assert_equal \
        "$(readlink -f "${home}/.zshrc")" \
        "${repo}/stow/base/.zshrc" \
        "Zsh config should resolve to the base package"
    assert_equal \
        "$(readlink -f "${home}/.config/herdr/config.toml")" \
        "${repo}/stow/base/.config/herdr/config.toml" \
        "Herdr config should resolve to the base package"
    assert_equal \
        "$(readlink -f "${home}/.config/hypr/hyprland.lua")" \
        "${repo}/stow/desktop/.config/hypr/hyprland.lua" \
        "Hyprland config should resolve to the desktop package"
    assert_equal \
        "$(readlink -f "${home}/.claude/CLAUDE.md")" \
        "${repo}/stow/assistant/.claude/CLAUDE.md" \
        "Claude instructions should resolve to the assistant package"
    assert_equal \
        "$(readlink -f "${home}/.codex/AGENTS.md")" \
        "${repo}/stow/assistant/.codex/AGENTS.md" \
        "Codex instructions should resolve to the assistant package"

    case "$(readlink "${home}/.claude/CLAUDE.md")" in
        /*)
            echo "FAIL: Claude instructions should use a Stow-managed relative link" >&2
            exit 1
            ;;
    esac
    case "$(readlink "${home}/.codex/AGENTS.md")" in
        /*)
            echo "FAIL: Codex instructions should use a Stow-managed relative link" >&2
            exit 1
            ;;
    esac
}

test_preserves_every_target_when_preflight_fails() {
    local fixture_root="${TEST_ROOT}/preflight"
    local paths
    local repo
    local home
    paths=$(create_fixture "${fixture_root}")
    repo=$(printf '%s\n' "${paths}" | sed -n '1p')
    home=$(printf '%s\n' "${paths}" | sed -n '2p')

    printf 'repo\n' > "${repo}/stow/base/.gitconfig"
    printf 'user\n' > "${home}/.gitconfig"
    printf 'user config\n' > "${home}/.codex/config.toml"
    printf 'user zsh\n' > "${home}/.zshrc"
    ln -s "${repo}/.claude/CLAUDE.md" "${home}/.claude/CLAUDE.md"
    ln -s "${repo}/.codex/AGENTS.md" "${home}/.codex/AGENTS.md"

    if HOME="${home}" DOTFILES_DIR="${repo}" "${STOW_SCRIPT}"; then
        echo "FAIL: Stow should fail for an unrelated conflicting file" >&2
        exit 1
    fi

    assert_equal \
        "$(readlink "${home}/.claude/CLAUDE.md")" \
        "${repo}/.claude/CLAUDE.md" \
        "Claude legacy link should remain untouched after preflight failure"
    assert_equal \
        "$(readlink "${home}/.codex/AGENTS.md")" \
        "${repo}/.codex/AGENTS.md" \
        "Codex legacy link should remain untouched after preflight failure"
    assert_equal \
        "$(cat "${home}/.gitconfig")" \
        "user" \
        "Unrelated conflicting files should remain untouched"
    assert_equal \
        "$(cat "${home}/.codex/config.toml")" \
        "user config" \
        "Unmanaged Codex config should remain untouched"
    assert_equal \
        "$(cat "${home}/.zshrc")" \
        "user zsh" \
        "Zsh config should be restored after failure"
    assert_equal \
        "$(find "${home}" -maxdepth 1 -type d -name '.dotfiles-stow-backup.*' | awk 'END { print NR }')" \
        "0" \
        "Empty rollback directories should be removed"
}

test_restores_valid_links_when_stow_fails() {
    local fixture_root="${TEST_ROOT}/rollback"
    local paths
    local repo
    local home
    local fake_bin="${fixture_root}/bin"
    paths=$(create_fixture "${fixture_root}")
    repo=$(printf '%s\n' "${paths}" | sed -n '1p')
    home=$(printf '%s\n' "${paths}" | sed -n '2p')

    mkdir -p "${fake_bin}" "${home}/.config/herdr"
    printf '#!/usr/bin/env bash\nexit 1\n' > "${fake_bin}/stow"
    chmod +x "${fake_bin}/stow"
    ln -s "${repo}/.zshrc" "${home}/.zshrc"
    ln -s "${repo}/.config/herdr/config.toml" "${home}/.config/herdr/config.toml"

    if PATH="${fake_bin}:${PATH}" HOME="${home}" DOTFILES_DIR="${repo}" "${STOW_SCRIPT}"; then
        echo "FAIL: Injected Stow failure should fail the transaction" >&2
        exit 1
    fi

    assert_equal \
        "$(readlink -f "${home}/.zshrc")" \
        "${repo}/stow/base/.zshrc" \
        "Zsh legacy link should recover to a valid package source"
    assert_equal \
        "$(readlink -f "${home}/.config/herdr/config.toml")" \
        "${repo}/stow/base/.config/herdr/config.toml" \
        "Herdr legacy link should recover to a valid package source"
}

test_rejects_duplicate_package_ownership() {
    local fixture_root="${TEST_ROOT}/duplicate"
    local paths
    local repo
    local home
    paths=$(create_fixture "${fixture_root}")
    repo=$(printf '%s\n' "${paths}" | sed -n '1p')
    home=$(printf '%s\n' "${paths}" | sed -n '2p')
    printf 'duplicate\n' > "${repo}/stow/desktop/.zshrc"

    if HOME="${home}" DOTFILES_DIR="${repo}" "${STOW_SCRIPT}" >/dev/null 2>&1; then
        echo "FAIL: Duplicate package ownership should be rejected" >&2
        exit 1
    fi

    assert_equal \
        "$(find "${home}" -mindepth 1 | awk 'END { print NR }')" \
        "2" \
        "Duplicate ownership should fail before changing the target home"
}

test_preserves_conflicting_zsh_config_in_a_unique_backup() {
    local fixture_root="${TEST_ROOT}/backup"
    local paths
    local repo
    local home
    local backup_root
    paths=$(create_fixture "${fixture_root}")
    repo=$(printf '%s\n' "${paths}" | sed -n '1p')
    home=$(printf '%s\n' "${paths}" | sed -n '2p')

    printf 'user config\n' > "${home}/.codex/config.toml"
    printf 'user zsh\n' > "${home}/.zshrc"
    mkdir "${home}/.zshrc.pre-dotfiles-bak"

    HOME="${home}" DOTFILES_DIR="${repo}" "${STOW_SCRIPT}"

    backup_root=$(find \
        "${home}" \
        -maxdepth 1 \
        -type d \
        -name '.dotfiles-stow-backup.*')
    assert_equal \
        "$(find "${home}" -maxdepth 1 -type d -name '.dotfiles-stow-backup.*' | awk 'END { print NR }')" \
        "1" \
        "A single unique backup directory should be retained"
    assert_equal \
        "$(cat "${backup_root}/zshrc")" \
        "user zsh" \
        "The existing Zsh config should be backed up"
    assert_equal \
        "$(cat "${home}/.codex/config.toml")" \
        "user config" \
        "Unmanaged Codex config should not be backed up or replaced"
}

test_rejects_root_equivalent_home_paths() {
    local fixture_root="${TEST_ROOT}/root-validation"
    local paths
    local repo
    local home
    local root_link="${fixture_root}/root-link"
    paths=$(create_fixture "${fixture_root}")
    repo=$(printf '%s\n' "${paths}" | sed -n '1p')
    home=$(printf '%s\n' "${paths}" | sed -n '2p')
    ln -s / "${root_link}"

    if HOME="/tmp/.." DOTFILES_DIR="${repo}" "${STOW_SCRIPT}" >/dev/null 2>&1; then
        echo "FAIL: A lexical path resolving to root should be rejected" >&2
        exit 1
    fi
    if HOME="${root_link}" DOTFILES_DIR="${repo}" "${STOW_SCRIPT}" >/dev/null 2>&1; then
        echo "FAIL: A symlink resolving to root should be rejected" >&2
        exit 1
    fi

    assert_equal \
        "$(find "${home}" -mindepth 1 | awk 'END { print NR }')" \
        "2" \
        "Rejected root-equivalent paths should not alter the fixture home"
}

test_links_exact_package_set
test_migrates_legacy_absolute_links
test_preserves_every_target_when_preflight_fails
test_restores_valid_links_when_stow_fails
test_rejects_duplicate_package_ownership
test_preserves_conflicting_zsh_config_in_a_unique_backup
test_rejects_root_equivalent_home_paths

echo "stow-dotfiles tests passed"
