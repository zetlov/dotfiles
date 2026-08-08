#!/usr/bin/env bash

set -euo pipefail

config_file="${SWITCH_AUDIO_CONFIG:-${HOME}/.config/switch-audio/config.env}"
if [ ! -r "${config_file}" ]; then
    echo "Audio switch configuration is missing: ${config_file}" >&2
    exit 1
fi

# shellcheck disable=SC1090
source "${config_file}"

for required_name in SINK_A DISPLAY_A SINK_B DISPLAY_B; do
    if [ -z "${!required_name:-}" ]; then
        echo "${required_name} must be set in ${config_file}" >&2
        exit 1
    fi
done

current_sink=$(pactl get-default-sink)
if [ "${current_sink}" = "${SINK_A}" ]; then
    next_sink="${SINK_B}"
    display_name="${DISPLAY_B}"
else
    next_sink="${SINK_A}"
    display_name="${DISPLAY_A}"
fi

pactl set-default-sink "${next_sink}"
while IFS=$'\t' read -r input_id _; do
    if [ -n "${input_id}" ]; then
        pactl move-sink-input "${input_id}" "${next_sink}"
    fi
done < <(pactl list short sink-inputs)

notify-send "Audio Switched" "To: ${display_name}" -i audio-speakers
