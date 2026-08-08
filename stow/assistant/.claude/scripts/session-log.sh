#!/bin/bash
# Stop hook: Record work activity at session end
# Foundation for the Continuous Learning system

LOG_DIR="$HOME/.claude/learnings/sessions"
mkdir -p "$LOG_DIR"

DATE=$(date +%Y-%m-%d)
TIME=$(date +%H:%M:%S)
LOG_FILE="$LOG_DIR/$DATE.md"
WORK_DIR=$(pwd)

# Add header if this is a new file
if [ ! -f "$LOG_FILE" ]; then
  echo "# Session Log: $DATE" > "$LOG_FILE"
  echo "" >> "$LOG_FILE"
fi

cat >> "$LOG_FILE" << HEADER

---

## $TIME — $(basename "$WORK_DIR")

- **Directory**: $WORK_DIR
HEADER

# Record git info (if inside a git repository)
if git rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
  BRANCH=$(git branch --show-current 2>/dev/null)
  echo "- **Branch**: ${BRANCH:-detached}" >> "$LOG_FILE"

  # Recent commits from this session (last 30 minutes)
  RECENT_COMMITS=$(git log --oneline --since="30 minutes ago" 2>/dev/null)
  if [ -n "$RECENT_COMMITS" ]; then
    echo "" >> "$LOG_FILE"
    echo "### Commits" >> "$LOG_FILE"
    echo '```' >> "$LOG_FILE"
    echo "$RECENT_COMMITS" >> "$LOG_FILE"
    echo '```' >> "$LOG_FILE"
  fi

  # Uncommitted changes
  DIFF_STAT=$(git diff --stat 2>/dev/null)
  STAGED_STAT=$(git diff --cached --stat 2>/dev/null)
  if [ -n "$DIFF_STAT" ] || [ -n "$STAGED_STAT" ]; then
    echo "" >> "$LOG_FILE"
    echo "### Uncommitted Changes" >> "$LOG_FILE"
    echo '```' >> "$LOG_FILE"
    [ -n "$STAGED_STAT" ] && echo "$STAGED_STAT" >> "$LOG_FILE"
    [ -n "$DIFF_STAT" ] && echo "$DIFF_STAT" >> "$LOG_FILE"
    echo '```' >> "$LOG_FILE"
  fi
fi

echo "" >> "$LOG_FILE"

exit 0
