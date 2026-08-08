#!/bin/bash
# PostToolUse: Warn about remaining debug statements after editing source files
# Input: JSON via stdin (includes tool_input)
# Output: Warning message to stderr (non-blocking)

input=$(cat)

# Extract tool_input.file_path (fall back to grep if jq is unavailable)
if command -v jq &>/dev/null; then
  file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
else
  file_path=$(echo "$input" | grep -oP '"file_path"\s*:\s*"\K[^"]+' | head -1)
fi

[ -z "$file_path" ] && exit 0
[ ! -f "$file_path" ] && exit 0

# Debug statement patterns by language
patterns=""
case "$file_path" in
  *.py)
    patterns='^\s*(print\(|breakpoint\(\)|import pdb|pdb\.set_trace)'
    ;;
  *.ts|*.tsx|*.js|*.jsx)
    patterns='^\s*(console\.(log|debug|warn|error)\(|debugger)'
    ;;
  *.go)
    patterns='^\s*fmt\.Print'
    ;;
  *.dart)
    patterns='^\s*(print\(|debugPrint\()'
    ;;
  *.cpp|*.cc|*.cxx|*.c)
    patterns='^\s*(std::cout|printf\(.*debug|fprintf\(stderr)'
    ;;
  *)
    exit 0
    ;;
esac

# Search for debug statements
matches=$(grep -nE "$patterns" "$file_path" 2>/dev/null)

if [ -n "$matches" ]; then
  echo "[Hook] Debug statements remaining:" >&2
  echo "$matches" | head -5 | while read -r line; do
    echo "  $line" >&2
  done
  count=$(echo "$matches" | wc -l)
  if [ "$count" -gt 5 ]; then
    echo "  ... and $((count - 5)) more" >&2
  fi
fi

exit 0
