#!/bin/bash

CONTENT=$(rofi -dmenu -p "Todoist" -config ~/.config/rofi/prompt.rasi)

if [ -n "$CONTENT" ]; then
    tod t q -c "$CONTENT" > /dev/null 2>&1
    notify-send "Todoist" "Added: $CONTENT" --icon=todoist
fi
