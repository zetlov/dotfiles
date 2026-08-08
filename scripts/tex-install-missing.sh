#!/usr/bin/env bash
#
# tex-install-missing.sh
#
# Build a LaTeX document with latexmk, detect missing packages from the log,
# reverse-lookup the owning Arch package via `pacman -F`, install it with yay,
# and retry. Optionally append newly-installed packages to packages/tex.txt.
#
# Usage:
#   tex-install-missing.sh <file.tex>
#   tex-install-missing.sh --from-log <file.log>
#   tex-install-missing.sh <file.tex> --update-list
#   tex-install-missing.sh <file.tex> --dry-run
#   tex-install-missing.sh <file.tex> --yes          # auto-pick first candidate
#
# Safety:
#   - Only installs packages whose name starts with "texlive-".
#   - Aborts if the missing-file set does not shrink between retries.
#   - Retry cap: 5.

set -eu

MAX_RETRIES=5
DOTFILES_DIR="${DOTFILES_DIR:-${HOME}/dotfiles}"
TEX_LIST="${DOTFILES_DIR}/packages/tex.txt"

DRY_RUN=0
UPDATE_LIST=0
AUTO_YES=0
FROM_LOG=""
TEX_FILE=""
FALLBACK_LOG=""

cleanup_fallback_log() {
    if [ -n "$FALLBACK_LOG" ]; then
        rm -f -- "$FALLBACK_LOG"
    fi
}
trap cleanup_fallback_log EXIT

# --- arg parse ---

while [ $# -gt 0 ]; do
    case "$1" in
        --from-log)    FROM_LOG="$2"; shift 2 ;;
        --update-list) UPDATE_LIST=1; shift ;;
        --dry-run)     DRY_RUN=1; shift ;;
        --yes)         AUTO_YES=1; shift ;;
        -h|--help)
            sed -n '3,20p' "$0"; exit 0 ;;
        -*)
            echo "unknown option: $1" >&2; exit 1 ;;
        *)
            TEX_FILE="$1"; shift ;;
    esac
done

if [ -z "$TEX_FILE" ] && [ -z "$FROM_LOG" ]; then
    echo "error: specify a .tex file or --from-log <file.log>" >&2
    exit 1
fi

# --- helpers ---

log()  { printf '[tex-install] %s\n' "$*"; }
warn() { printf '[tex-install] WARN: %s\n' "$*" >&2; }

sync_files_db() {
    if [ "$DRY_RUN" -eq 1 ]; then
        log "[dry-run] would sync pacman files database when stale"
        return 0
    fi

    # Sync pacman files DB at most once per day.
    local marker="${XDG_CACHE_HOME:-$HOME/.cache}/tex-install-missing.fy"
    mkdir -p "$(dirname "$marker")"
    if [ ! -f "$marker" ] || [ -n "$(find "$marker" -mtime +1 2>/dev/null)" ]; then
        log "syncing pacman files database (pacman -Fy)..."
        sudo pacman -Fy >/dev/null
        touch "$marker"
    fi
}

run_latexmk() {
    local tex="$1"
    latexmk -interaction=nonstopmode -file-line-error "$tex" 2>&1 || true
}

# Extract missing file names from a latexmk/latex log.
# Prints one filename per line (deduped).
extract_missing() {
    local log_file="$1"
    {
        grep -oP "File \`\K[^']+(?=' not found)" "$log_file" || true
        grep -oP "LaTeX Error: File \`\K[^']+(?=')" "$log_file" || true
        grep -oP "kpathsea: Running mktextfm \K\S+" "$log_file" \
            | sed 's/$/.tfm/' || true
    } | sort -u
}

# Reverse-lookup a file to a texlive-* package. Echoes chosen package or empty.
lookup_package() {
    local fname="$1"
    local matches
    matches=$(pacman -Fq "$fname" 2>/dev/null | grep '^texlive-' | sort -u || true)
    if [ -z "$matches" ]; then
        return 0
    fi
    local count
    count=$(printf '%s\n' "$matches" | wc -l)
    if [ "$count" -eq 1 ]; then
        printf '%s\n' "$matches"
        return 0
    fi
    if [ "$AUTO_YES" -eq 1 ]; then
        printf '%s\n' "$matches" | head -n1
        return 0
    fi
    # interactive pick
    echo "multiple candidates for '$fname':" >&2
    local i=1
    local opts=()
    while IFS= read -r p; do
        echo "  [$i] $p" >&2
        opts+=("$p")
        i=$((i+1))
    done <<< "$matches"
    printf 'pick [1-%d] (empty=skip): ' "${#opts[@]}" >&2
    read -r choice </dev/tty || choice=""
    if [ -z "$choice" ]; then
        return 0
    fi
    printf '%s\n' "${opts[$((choice-1))]}"
}

install_pkgs() {
    local pkgs=("$@")
    [ "${#pkgs[@]}" -eq 0 ] && return 0
    if [ "$DRY_RUN" -eq 1 ]; then
        log "[dry-run] would install: ${pkgs[*]}"
        return 0
    fi
    log "installing: ${pkgs[*]}"
    yay -S --needed --noconfirm "${pkgs[@]}"
}

append_to_tex_list() {
    local date_str pkgs
    date_str=$(date +%F)
    pkgs=("$@")
    [ "${#pkgs[@]}" -eq 0 ] && return 0
    [ "$UPDATE_LIST" -eq 0 ] && return 0
    if [ "$DRY_RUN" -eq 1 ]; then
        log "[dry-run] would append to $TEX_LIST: ${pkgs[*]}"
        return 0
    fi
    if [ ! -f "$TEX_LIST" ]; then
        warn "$TEX_LIST not found, skipping --update-list"
        return 0
    fi
    if ! grep -q '^# === auto-added' "$TEX_LIST"; then
        printf '\n# === auto-added (review and promote above) ===\n' >> "$TEX_LIST"
    fi
    for p in "${pkgs[@]}"; do
        if ! grep -qxF "$p" "$TEX_LIST" \
            && ! grep -qE "^${p}\b" "$TEX_LIST"; then
            printf '%s    # %s\n' "$p" "$date_str" >> "$TEX_LIST"
        fi
    done
    log "appended ${#pkgs[@]} package(s) to $TEX_LIST (review before commit)"
}

# --- main ---

sync_files_db

prev_missing=""
retry=0
all_installed=()

if [ -n "$FROM_LOG" ]; then
    # one-shot analysis mode
    missing=$(extract_missing "$FROM_LOG")
    if [ -z "$missing" ]; then
        log "no missing files detected in $FROM_LOG"
        exit 0
    fi
    log "missing files:"; printf '  - %s\n' $missing
    to_install=()
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        pkg=$(lookup_package "$f")
        [ -n "$pkg" ] && to_install+=("$pkg")
    done <<< "$missing"
    # dedupe
    if [ "${#to_install[@]}" -gt 0 ]; then
        mapfile -t to_install < <(printf '%s\n' "${to_install[@]}" | sort -u)
        install_pkgs "${to_install[@]}"
        append_to_tex_list "${to_install[@]}"
    fi
    exit 0
fi

# build-retry loop
while [ "$retry" -lt "$MAX_RETRIES" ]; do
    log "latexmk attempt $((retry+1))/${MAX_RETRIES}: $TEX_FILE"
    output=$(run_latexmk "$TEX_FILE")
    log_file="${TEX_FILE%.tex}.log"
    if [ ! -f "$log_file" ]; then
        if [ -z "$FALLBACK_LOG" ]; then
            FALLBACK_LOG=$(mktemp)
        fi
        printf '%s\n' "$output" > "$FALLBACK_LOG"
        log_file="$FALLBACK_LOG"
    fi

    missing=$(extract_missing "$log_file")
    if [ -z "$missing" ]; then
        if echo "$output" | grep -q '^Latexmk: All targets .* up-to-date\|^Latexmk: Getting log file'; then
            log "build finished with no missing files."
        else
            log "no missing files detected; build may still have other errors."
        fi
        break
    fi

    log "missing files detected:"; printf '  - %s\n' $missing

    if [ "$missing" = "$prev_missing" ]; then
        warn "missing-file set did not shrink; aborting to avoid loop."
        exit 2
    fi
    prev_missing="$missing"

    to_install=()
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        pkg=$(lookup_package "$f")
        if [ -n "$pkg" ]; then
            to_install+=("$pkg")
        else
            warn "no texlive-* package provides '$f' (CTAN/manual install?)"
        fi
    done <<< "$missing"

    if [ "${#to_install[@]}" -eq 0 ]; then
        warn "nothing resolvable; aborting."
        exit 3
    fi

    mapfile -t to_install < <(printf '%s\n' "${to_install[@]}" | sort -u)
    install_pkgs "${to_install[@]}"
    all_installed+=("${to_install[@]}")
    retry=$((retry+1))
done

if [ "$retry" -ge "$MAX_RETRIES" ]; then
    warn "hit retry cap ($MAX_RETRIES); giving up."
fi

if [ "${#all_installed[@]}" -gt 0 ]; then
    mapfile -t all_installed < <(printf '%s\n' "${all_installed[@]}" | sort -u)
    append_to_tex_list "${all_installed[@]}"
fi
