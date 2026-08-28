#!/usr/bin/env bash

parse_install_options() {
    WITH_TEX=1
    MINIMAL=0
    WITH_GLAZEWM=1
    WITH_KOMOREBI=0
    WITH_MONITOR_PROFILES=0
    WITH_NVIDIA=0
    LINK_ONLY=0
    DRY_RUN=0
    SYSTEM_UPGRADE=0
    CONTAINER_BACKEND=auto
    STOW_PROFILE=auto

    local enable_tex=0
    local disable_tex=0
    local enable_glazewm=0
    local disable_glazewm=0
    local arg
    for arg in "$@"; do
        case "${arg}" in
            --with-tex) enable_tex=1 ;;
            --without-tex) disable_tex=1 ;;
            --minimal) MINIMAL=1 ;;
            --with-glazewm) enable_glazewm=1 ;;
            --without-glazewm) disable_glazewm=1 ;;
            --with-komorebi) WITH_KOMOREBI=1 ;;
            --with-monitor-profiles) WITH_MONITOR_PROFILES=1 ;;
            --with-nvidia) WITH_NVIDIA=1 ;;
            --link-only) LINK_ONLY=1 ;;
            --dry-run) DRY_RUN=1 ;;
            --system-upgrade) SYSTEM_UPGRADE=1 ;;
            --container-backend=auto) CONTAINER_BACKEND=auto ;;
            --container-backend=desktop) CONTAINER_BACKEND=desktop ;;
            --container-backend=native) CONTAINER_BACKEND=native ;;
            --container-backend=none) CONTAINER_BACKEND=none ;;
            --profile=auto) STOW_PROFILE=auto ;;
            --profile=desktop) STOW_PROFILE=desktop ;;
            --profile=wsl) STOW_PROFILE=wsl ;;
            --profile=*)
                echo "Stow profile must be auto, desktop, or wsl." >&2
                return 1
                ;;
            --container-backend=*)
                echo "Container backend must be auto, desktop, native, or none." >&2
                return 1
                ;;
            *)
                echo "Unknown option: ${arg}" >&2
                return 1
                ;;
        esac
    done

    if [ "${enable_tex}" -eq 1 ] && [ "${disable_tex}" -eq 1 ]; then
        echo "Choose only one of --with-tex and --without-tex." >&2
        return 1
    fi
    if [ "${enable_glazewm}" -eq 1 ] && [ "${disable_glazewm}" -eq 1 ]; then
        echo "Choose only one of --with-glazewm and --without-glazewm." >&2
        return 1
    fi
    if [ "${enable_glazewm}" -eq 1 ] && [ "${WITH_KOMOREBI}" -eq 1 ]; then
        echo "Choose only one Windows window manager." >&2
        return 1
    fi

    if [ "${MINIMAL}" -eq 1 ]; then
        WITH_TEX=0
        WITH_GLAZEWM=0
    fi
    if [ "${enable_tex}" -eq 1 ]; then
        WITH_TEX=1
    elif [ "${disable_tex}" -eq 1 ]; then
        WITH_TEX=0
    fi
    if [ "${WITH_KOMOREBI}" -eq 1 ]; then
        WITH_GLAZEWM=0
    elif [ "${enable_glazewm}" -eq 1 ]; then
        WITH_GLAZEWM=1
    elif [ "${disable_glazewm}" -eq 1 ]; then
        WITH_GLAZEWM=0
    fi
}
