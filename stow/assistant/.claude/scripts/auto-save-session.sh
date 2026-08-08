#!/bin/bash
# Stop hook: Fallback when /save is forgotten
# If .claude/session-summary.md does not exist, generate a minimal summary from git state
# If already saved via /save, do nothing

SUMMARY_FILE=".claude/session-summary.md"

# Exit if not inside a git repository
git rev-parse --is-inside-work-tree &>/dev/null 2>&1 || exit 0

# Check if already saved via /save (skip if updated within the last 10 minutes)
if [ -f "$SUMMARY_FILE" ]; then
  if [[ "$OSTYPE" == "darwin"* ]]; then
    mod_epoch=$(stat -f "%m" "$SUMMARY_FILE" 2>/dev/null)
  else
    mod_epoch=$(stat -c "%Y" "$SUMMARY_FILE" 2>/dev/null)
  fi
  now_epoch=$(date +%s)
  diff=$(( now_epoch - mod_epoch ))
  # Skip if updated within 10 minutes (600 seconds)
  if [ "$diff" -lt 600 ]; then
    exit 0
  fi
fi

# Fallback: generate minimal summary from git state
mkdir -p .claude

BRANCH=$(git branch --show-current 2>/dev/null)
DATE=$(date +"%Y-%m-%d %H:%M")
DIR=$(pwd)

cat > "$SUMMARY_FILE" << EOF
---
saved_at: $DATE
directory: $DIR
branch: ${BRANCH:-detached}
auto_generated: true
---

# Session Summary (auto-generated)

> This summary was auto-generated at session end.
> Use the /save command to replace it with a more detailed summary.

## Git Status
- **Branch**: ${BRANCH:-detached}
EOF

# Recent commits
RECENT=$(git log --oneline -5 --since="1 hour ago" 2>/dev/null)
if [ -n "$RECENT" ]; then
  cat >> "$SUMMARY_FILE" << EOF

## Recent Commits
\`\`\`
$RECENT
\`\`\`
EOF
fi

# Uncommitted changes
CHANGES=$(git diff --stat 2>/dev/null)
STAGED=$(git diff --cached --stat 2>/dev/null)
if [ -n "$CHANGES" ] || [ -n "$STAGED" ]; then
  cat >> "$SUMMARY_FILE" << EOF

## Uncommitted Changes
\`\`\`
EOF
  [ -n "$STAGED" ] && echo "Staged:" >> "$SUMMARY_FILE" && echo "$STAGED" >> "$SUMMARY_FILE"
  [ -n "$CHANGES" ] && echo "Unstaged:" >> "$SUMMARY_FILE" && echo "$CHANGES" >> "$SUMMARY_FILE"
  echo '```' >> "$SUMMARY_FILE"
fi

exit 0
