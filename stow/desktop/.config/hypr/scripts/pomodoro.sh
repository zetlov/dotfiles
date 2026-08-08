#!/bin/bash

WORK_TIME=25
BREAK_TIME=5
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/zetshell"
STATE_FILE="$STATE_DIR/pomodoro"
SOUND_FILE="/usr/share/sounds/freedesktop/stereo/complete.oga"

umask 077
mkdir -p "$STATE_DIR"

get_state() {
    if [ -f "$STATE_FILE" ]; then
        cat "$STATE_FILE"
    else
        echo "STOPPED work $((WORK_TIME * 60)) 0"
    fi
}

save_state() {
    local temporary_state
    temporary_state=$(mktemp "${STATE_FILE}.tmp.XXXXXX") || return 1
    if ! printf '%s %s %s %s\n' "$1" "$2" "$3" "$(date +%s)" > "$temporary_state"; then
        rm -f -- "$temporary_state"
        return 1
    fi
    mv -f -- "$temporary_state" "$STATE_FILE"
}

send_notification() {
    notify-send "Pomodoro" "$1" -i clock
    paplay "$SOUND_FILE" &>/dev/null &
}

case "${1:-}" in
    start)
        read status mode duration last_update <<< "$(get_state)"

        if [ "$status" = "STOPPED" ]; then
            if [ "$mode" = "work" ]; then
                mins=$WORK_TIME
            else
                mins=$BREAK_TIME
            fi
            current_seconds=$((mins * 60))
        else
            current_seconds=$duration
        fi

        end_time=$(($(date +%s) + current_seconds))
        save_state "RUNNING" "$mode" "$end_time"
        ;;

    toggle)
        read status mode val last_update <<< "$(get_state)"
        if [ "$status" = "RUNNING" ]; then
            remaining=$((val - $(date +%s)))
            save_state "PAUSED" "$mode" "$remaining"
        else
            "$0" start
        fi
        ;;

    reset)
        save_state "STOPPED" "work" $((WORK_TIME * 60))
        ;;

    cycle)
        read status mode val last_update <<< "$(get_state)"
        if [ "$mode" = "work" ]; then
            new_mode="break"
            new_time=$BREAK_TIME
        else
            new_mode="work"
            new_time=$WORK_TIME
        fi
        save_state "STOPPED" "$new_mode" $((new_time * 60))
        ;;

    get)
        read status mode val last_update <<< "$(get_state)"

        if [ "$status" = "RUNNING" ]; then
            remaining=$((val - $(date +%s)))

            if [ "$remaining" -le 0 ]; then
                if [ "$mode" = "work" ]; then
                    send_notification "作業終了。休憩しましょう"
                    new_mode="break"
                    new_time=$BREAK_TIME
                else
                    send_notification "休憩終了。作業に戻りましょう"
                    new_mode="work"
                    new_time=$WORK_TIME
                fi

                save_state "STOPPED" "$new_mode" $((new_time * 60))
                remaining=$((new_time * 60))
                mode=$new_mode
                status="STOPPED"
            fi
        else
            remaining=$val
        fi

        mins=$((remaining / 60))
        secs=$((remaining % 60))
        pretty_time=$(printf "%02d:%02d" "$mins" "$secs")

        if [ "$mode" = "work" ]; then
            icon="󱎫"
            class="work"
        else
            icon=""
            class="break"
        fi

        if [ "$status" = "PAUSED" ]; then
            pretty_time="${pretty_time} (P)"
            class="${class} paused"
        fi

        echo "{\"time\": \"$pretty_time\", \"icon\": \"$icon\", \"class\": \"$class\", \"status\": \"$status\"}"
        ;;
esac
