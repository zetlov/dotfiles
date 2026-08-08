#!/usr/bin/env bash
# Inhibits hypridle while any playerctl-tracked player is in Playing state.
# Uses systemd-inhibit so hypridle itself stays alive (before_sleep_cmd fires normally).

inhibit_pid=""

cleanup() {
    [ -n "$inhibit_pid" ] && kill "$inhibit_pid" 2>/dev/null
    exit 0
}
trap cleanup SIGTERM SIGINT EXIT

while true; do
    if playerctl status 2>/dev/null | grep -q "^Playing$"; then
        if [ -z "$inhibit_pid" ]; then
            systemd-inhibit --what=idle --who="music-inhibit" \
                --why="Music is playing" --mode=block sleep infinity &
            inhibit_pid=$!
        fi
    else
        if [ -n "$inhibit_pid" ]; then
            kill "$inhibit_pid" 2>/dev/null
            inhibit_pid=""
        fi
    fi
    sleep 10
done
