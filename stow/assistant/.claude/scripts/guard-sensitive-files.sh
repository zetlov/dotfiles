#!/bin/bash
# PreToolUse: Block changes to .env and sensitive configuration files
# Input: JSON via stdin (includes tool_input)
# Output: exit 2 to block, message to stderr

input=$(cat)

if command -v jq &>/dev/null; then
  file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
else
  file_path=$(echo "$input" | grep -oP '"file_path"\s*:\s*"\K[^"]+' | head -1)
fi

[ -z "$file_path" ] && exit 0

# Protected files
basename=$(basename "$file_path")
case "$basename" in
  .env|.env.local|.env.production|.env.staging)
    echo "[Hook] Blocked direct edit of $basename. Please edit manually." >&2
    exit 2
    ;;
  *.pem|*.key|*.p12|*.keystore)
    echo "[Hook] Blocked change to key file $basename." >&2
    exit 2
    ;;
esac

# Protect files inside .git/
if echo "$file_path" | grep -qE '(^|/)\.git/'; then
  echo "[Hook] Blocked change to file inside .git/." >&2
  exit 2
fi

exit 0
