#!/usr/bin/env bash

validate_package_upgrade_flag() {
    case "$1" in
        0|1) ;;
        *)
            echo "Package upgrade flag must be 0 or 1." >&2
            return 1
            ;;
    esac
}

validate_package_profiles() {
    local dotfiles_dir="$1"
    local yay_bin="$2"
    local pacman_bin="$3"
    local upgrade="$4"
    shift 4

    if [ ! -x "${yay_bin}" ]; then
        echo "The package phase requires an executable yay binary." >&2
        return 1
    fi
    if [ "${upgrade}" = "0" ] && [ ! -x "${pacman_bin}" ]; then
        echo "The package phase requires an executable pacman binary." >&2
        return 1
    fi
    if [ "$#" -eq 0 ]; then
        echo "The package phase requires at least one profile." >&2
        return 1
    fi
    local profile
    for profile in "$@"; do
        if [ ! -f "${dotfiles_dir}/packages/${profile}" ] \
            || [ ! -r "${dotfiles_dir}/packages/${profile}" ]; then
            echo "Required package profile is missing or unreadable: ${dotfiles_dir}/packages/${profile}" >&2
            return 1
        fi
    done
}

read_package_profile() {
    local profile_path="$1"
    sed \
        -e '/^[[:space:]]*#/d' \
        -e '/^[[:space:]]*$/d' \
        "${profile_path}"
}

apply_package_profiles() {
    local dotfiles_dir="$1"
    local upgrade="$2"
    local yay_bin="$3"
    local pacman_bin="$4"
    shift 4

    validate_package_upgrade_flag "${upgrade}" || return 1
    validate_package_profiles \
        "${dotfiles_dir}" "${yay_bin}" "${pacman_bin}" "${upgrade}" "$@" \
        || return 1

    local -a profile_names=()
    local -a profile_packages=()
    local profile
    local profile_path
    local packages
    for profile in "$@"; do
        profile_path="${dotfiles_dir}/packages/${profile}"
        if ! packages=$(read_package_profile "${profile_path}"); then
            echo "Unable to read package profile: ${profile_path}" >&2
            return 1
        fi
        profile_names+=("${profile}")
        profile_packages+=("${packages}")
    done

    if [ "${upgrade}" = "1" ]; then
        if ! "${yay_bin}" -Syu; then
            echo "System package upgrade failed." >&2
            return 1
        fi
    else
        local pending_updates
        local pending_status
        if pending_updates=$("${pacman_bin}" -Qu 2>&1); then
            pending_status=0
        else
            pending_status=$?
        fi
        if [ "${pending_status}" -eq 1 ] && [ -z "${pending_updates}" ]; then
            if ! "${pacman_bin}" -Q >/dev/null 2>&1; then
                echo "Unable to validate the local package database." >&2
                return 1
            fi
        elif [ "${pending_status}" -ne 0 ]; then
            echo "Unable to inspect pending system package updates." >&2
            return 1
        fi
        if [ -n "${pending_updates}" ]; then
            printf '%s\n' \
                "Pending system package updates were detected. Re-run with --system-upgrade before installing package profiles." \
                >&2
            return 1
        fi
    fi

    local index
    for index in "${!profile_names[@]}"; do
        profile="${profile_names[${index}]}"
        profile_path="${dotfiles_dir}/packages/${profile}"
        packages="${profile_packages[${index}]}"
        if [ -z "${packages}" ]; then
            echo "No packages listed in ${profile_path}, skipping."
            continue
        fi
        if [ "${profile}" = "tex.txt" ]; then
            echo "Installing TeX Live packages..."
        fi
        if ! printf '%s\n' "${packages}" | "${yay_bin}" -S --needed -; then
            echo "Package profile installation failed: ${profile}" >&2
            return 1
        fi
    done
}
