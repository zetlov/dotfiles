#!/usr/bin/env bash

set -euo pipefail

# shellcheck disable=SC1091
source "$HOME/.config/hypr/scripts/load_zetshell_settings.sh"

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/zetshell"
PID_FILE="$STATE_DIR/recording.pid"
META_FILE="$STATE_DIR/recording-meta.json"
LOG_FILE="$STATE_DIR/recording.log"
RECORDINGS_DIR="$ZETSHELL_RECORDINGS_DIR"
THUMBNAILS_DIR="$STATE_DIR/recording-thumbnails"
RECORDER="gpu-screen-recorder"

mkdir -p "$STATE_DIR"

thumbnail_path_for() {
    local output_path="$1"
    local output_name stem
    output_name="$(basename "$output_path")"
    stem="${output_name%.*}"
    printf '%s/%s.png\n' "$THUMBNAILS_DIR" "$stem"
}

generate_thumbnail() {
    local output_path="$1"
    local thumbnail_path
    thumbnail_path="$(thumbnail_path_for "$output_path")"

    command -v ffmpegthumbnailer >/dev/null 2>&1 || return 1

    mkdir -p "$THUMBNAILS_DIR"
    ffmpegthumbnailer -i "$output_path" -o "$thumbnail_path" -s 512 -q 9 -t 12% -c png >/dev/null 2>&1 || return 1
    [[ -f "$thumbnail_path" ]] || return 1
    printf '%s\n' "$thumbnail_path"
}

is_recording() {
    [[ -f "$PID_FILE" ]] || return 1
    local pid executable
    pid="$(cat "$PID_FILE" 2>/dev/null || true)"
    [[ "$pid" =~ ^[0-9]+$ ]] || return 1
    kill -0 "$pid" 2>/dev/null || return 1
    executable="$(readlink -f "/proc/${pid}/exe" 2>/dev/null || true)"
    [[ "${executable##*/}" == "$RECORDER" ]]
}

cleanup_stale() {
    if ! is_recording; then
        rm -f "$PID_FILE"
        if [[ -f "$META_FILE" ]]; then
            jq '.recording = false | .paused = false' "$META_FILE" >"$META_FILE.tmp" 2>/dev/null && mv "$META_FILE.tmp" "$META_FILE" || true
        fi
    fi
}

post_save_notification() {
    local output_path="$1"
    setsid -f "$0" notify-saved "$output_path" >/dev/null 2>&1 || true
}

handle_saved_notification() {
    local output_path="$1"
    local output_name action thumbnail_path image_hint_args
    output_name="$(basename "$output_path")"
    thumbnail_path="$(generate_thumbnail "$output_path" || true)"
    image_hint_args=()
    if [[ -n "$thumbnail_path" ]]; then
        image_hint_args=(-h "string:image-path:file://$thumbnail_path")
    fi

    action="$(
        notify-send \
            -a "Record" \
            -i "media-record" \
            -t 15000 \
            "${image_hint_args[@]}" \
            -A play="Play" \
            -A folder="Open Folder" \
            -A delete="Delete" \
            "Recording saved" \
            "$output_name"
    )" || {
        notify-send -a "Record" -i "media-record" "${image_hint_args[@]}" "Recording saved" "$output_name" || true
        exit 0
    }

    case "$action" in
        play)
            xdg-open "$output_path" >/dev/null 2>&1 &
            ;;
        folder)
            xdg-open "$(dirname "$output_path")" >/dev/null 2>&1 &
            ;;
        delete)
            if [[ -f "$output_path" ]]; then
                rm -f "$output_path"
                [[ -n "$thumbnail_path" ]] && rm -f "$thumbnail_path"
                notify-send -a "Record" -i "user-trash" "Recording deleted" "$output_name" || true
            fi
            ;;
    esac
}

normalize_region_geometry() {
    local geometry="$1"

    if [[ "$geometry" =~ ^([0-9]+),([0-9]+)\ ([0-9]+)x([0-9]+)$ ]]; then
        local x="${BASH_REMATCH[1]}"
        local y="${BASH_REMATCH[2]}"
        local width="${BASH_REMATCH[3]}"
        local height="${BASH_REMATCH[4]}"
        printf '%sx%s+%s+%s\n' "$width" "$height" "$x" "$y"
        return 0
    fi

    if [[ "$geometry" =~ ^([0-9]+)x([0-9]+)\+([0-9]+)\+([0-9]+)$ ]]; then
        printf '%s\n' "$geometry"
        return 0
    fi

    return 1
}

focused_monitor_json() {
    hyprctl -j monitors | jq -c '.[] | select(.focused == true)' | head -n 1
}

write_meta() {
    local recording="$1"
    local paused="$2"
    local mode="$3"
    local with_audio="$4"
    local output="$5"
    local monitor="$6"

    jq -n \
        --argjson recording "$recording" \
        --argjson paused "$paused" \
        --arg mode "$mode" \
        --arg withAudio "$with_audio" \
        --arg output "$output" \
        --arg monitor "$monitor" \
        '{
            recording: $recording,
            paused: $paused,
            mode: $mode,
            withAudio: ($withAudio == "true"),
            output: $output,
            monitor: $monitor
        }' >"$META_FILE"
}

status_json() {
    cleanup_stale

    if [[ -f "$META_FILE" ]]; then
        cat "$META_FILE"
    else
        jq -n '{recording: false, paused: false, mode: "", withAudio: false, output: "", monitor: ""}'
    fi
}

start_output() {
    local with_audio="${1:-true}"

    cleanup_stale
    if is_recording; then
        echo "Recording is already running" >&2
        exit 1
    fi

    local monitor_json monitor refresh output_path pid
    monitor_json="$(focused_monitor_json)"
    [[ -n "$monitor_json" ]] || {
        echo "Could not determine focused monitor" >&2
        exit 1
    }

    monitor="$(jq -r '.name' <<<"$monitor_json")"
    refresh="$(jq -r '.refreshRate | round' <<<"$monitor_json")"
    mkdir -p "$RECORDINGS_DIR"
    output_path="$RECORDINGS_DIR/recording_$(date +%Y%m%d_%H-%M-%S).mp4"

    local args=(-w "$monitor" -f "$refresh" -o "$output_path")
    if [[ "$with_audio" == "true" ]]; then
        args+=(-a default_output)
    fi

    "$RECORDER" "${args[@]}" >"$LOG_FILE" 2>&1 &
    pid=$!
    echo "$pid" >"$PID_FILE"
    write_meta true false output "$with_audio" "$output_path" "$monitor"

    sleep 0.4
    if ! kill -0 "$pid" 2>/dev/null; then
        rm -f "$PID_FILE"
        write_meta false false output "$with_audio" "$output_path" "$monitor"
        if [[ -s "$LOG_FILE" ]]; then
            tail -n 20 "$LOG_FILE" >&2
        else
            echo "Recorder failed to start" >&2
        fi
        exit 1
    fi

    notify-send "Recording started" "Output: $monitor"
    echo "Recording started on $monitor"
}

start_region() {
    local with_audio="${1:-true}"
    local geometry="${2:-}"
    local label_mode="${3:-region}"

    cleanup_stale
    if is_recording; then
        echo "Recording is already running" >&2
        exit 1
    fi

    [[ -n "$geometry" ]] || {
        echo "Missing region geometry" >&2
        exit 1
    }

    local normalized_geometry output_path pid
    normalized_geometry="$(normalize_region_geometry "$geometry")" || {
        echo "Invalid region geometry: $geometry" >&2
        exit 1
    }

    mkdir -p "$RECORDINGS_DIR"
    output_path="$RECORDINGS_DIR/recording_$(date +%Y%m%d_%H-%M-%S).mp4"

    local args=(-w region -region "$normalized_geometry" -o "$output_path")
    if [[ "$with_audio" == "true" ]]; then
        args+=(-a default_output)
    fi

    "$RECORDER" "${args[@]}" >"$LOG_FILE" 2>&1 &
    pid=$!
    echo "$pid" >"$PID_FILE"
    write_meta true false "$label_mode" "$with_audio" "$output_path" "$normalized_geometry"

    sleep 0.4
    if ! kill -0 "$pid" 2>/dev/null; then
        rm -f "$PID_FILE"
        write_meta false false "$label_mode" "$with_audio" "$output_path" "$normalized_geometry"
        if [[ -s "$LOG_FILE" ]]; then
            tail -n 20 "$LOG_FILE" >&2
        else
            echo "Recorder failed to start" >&2
        fi
        exit 1
    fi

    notify-send "Recording started" "${label_mode^}: $normalized_geometry"
    echo "Recording started for $label_mode $normalized_geometry"
}

stop_recording() {
    cleanup_stale
    if ! is_recording; then
        echo "Recording is not running" >&2
        exit 1
    fi

    local pid output_path
    pid="$(cat "$PID_FILE")"
    output_path="$(jq -r '.output // ""' "$META_FILE" 2>/dev/null || true)"

    kill "$pid" 2>/dev/null || true
    for _ in $(seq 1 100); do
        if ! kill -0 "$pid" 2>/dev/null; then
            break
        fi
        sleep 0.1
    done

    rm -f "$PID_FILE"
    if [[ -f "$META_FILE" ]]; then
        jq '.recording = false | .paused = false' "$META_FILE" >"$META_FILE.tmp" 2>/dev/null && mv "$META_FILE.tmp" "$META_FILE" || true
    fi

    if [[ -n "$output_path" ]]; then
        post_save_notification "$output_path"
        echo "Recording saved to $output_path"
    else
        notify-send "Recording stopped" "Recording finished"
        echo "Recording stopped"
    fi
}

toggle_pause() {
    cleanup_stale
    if ! is_recording; then
        echo "Recording is not running" >&2
        exit 1
    fi

    local pid paused next_state
    pid="$(cat "$PID_FILE")"
    kill -USR2 "$pid"
    paused="$(jq -r '.paused // false' "$META_FILE" 2>/dev/null || echo false)"
    if [[ "$paused" == "true" ]]; then
        next_state=false
        notify-send "Recording resumed" "Recording continued"
        echo "Recording resumed"
    else
        next_state=true
        notify-send "Recording paused" "Recording paused"
        echo "Recording paused"
    fi

    jq --argjson paused "$next_state" '.paused = $paused' "$META_FILE" >"$META_FILE.tmp" 2>/dev/null && mv "$META_FILE.tmp" "$META_FILE" || true
}

toggle_output() {
    local with_audio="${1:-true}"
    cleanup_stale
    if is_recording; then
        stop_recording
    else
        start_output "$with_audio"
    fi
}

toggle_region() {
    local with_audio="${1:-true}"
    local geometry="${2:-}"
    local label_mode="${3:-region}"

    cleanup_stale
    if is_recording; then
        stop_recording
    else
        start_region "$with_audio" "$geometry" "$label_mode"
    fi
}

case "${1:-status}" in
    status)
        status_json
        ;;
    start)
        case "${2:-}" in
            output)
                start_output "${3:-true}"
                ;;
            region)
                start_region "${3:-true}" "${4:-}" "${5:-region}"
                ;;
            *)
                echo "Usage: $0 start {output [true|false]|region [true|false] geometry [region|window]}" >&2
                exit 2
                ;;
        esac
        ;;
    stop)
        stop_recording
        ;;
    notify-saved)
        handle_saved_notification "${2:-}"
        ;;
    pause)
        toggle_pause
        ;;
    toggle)
        case "${2:-}" in
            output)
                toggle_output "${3:-true}"
                ;;
            region)
                toggle_region "${3:-true}" "${4:-}" "${5:-region}"
                ;;
            *)
                echo "Usage: $0 toggle {output [true|false]|region [true|false] geometry [region|window]}" >&2
                exit 2
                ;;
        esac
        ;;
    *)
        echo "Usage: $0 {status|start|stop|notify-saved|pause|toggle}" >&2
        exit 2
        ;;
esac
