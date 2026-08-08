#!/bin/bash
# SessionStart hook: Load and display previous session summary if it exists
# Output: Previous summary to stdout (injected into Claude's context)

SUMMARY_FILE=".claude/session-summary.md"

# Check if summary file exists at project root
if [ -f "$SUMMARY_FILE" ]; then
  # Get file modification date
  if [[ "$OSTYPE" == "darwin"* ]]; then
    mod_date=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M" "$SUMMARY_FILE" 2>/dev/null)
  else
    mod_date=$(stat -c "%y" "$SUMMARY_FILE" 2>/dev/null | cut -d'.' -f1)
  fi

  echo "=== Previous Session Summary (${mod_date}) ==="
  echo ""
  cat "$SUMMARY_FILE"
  echo ""
  echo "=== End of Summary ==="
  echo ""
  echo "If continuing from previous work, refer to the content above."
  echo "If starting a new task, you can ignore this."
fi

exit 0
