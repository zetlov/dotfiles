#!/bin/bash
# PreCompact (matcher: auto): defer auto-compaction to a task boundary.
#
# The model touches "$cwd/.claude/compact-ok" at every task boundary (after
# persisting state: roadmap / session summary). Auto-compact is allowed when
# that flag is fresh (< FLAG_MAX_AGE_MIN). Otherwise it is blocked with a
# reason instructing the model to checkpoint; after MAX_BLOCKS consecutive
# blocks it fails open so the context can never overflow.
# Manual /compact is never gated (matcher is "auto" in settings.json; the
# trigger field is re-checked here as a second guard).

FLAG_MAX_AGE_MIN=30
MAX_BLOCKS=3

input=$(cat)

if command -v jq &>/dev/null; then
  trigger=$(echo "$input" | jq -r '.trigger // empty' 2>/dev/null)
  cwd=$(echo "$input" | jq -r '.cwd // empty' 2>/dev/null)
else
  trigger=""
  cwd=""
fi

# Only gate automatic compaction; anything unclear -> allow (fail-open).
[ "$trigger" = "auto" ] || exit 0
[ -n "$cwd" ] && [ -d "$cwd" ] || exit 0

flag="$cwd/.claude/compact-ok"
counter="$cwd/.claude/.compact-block-count"
mkdir -p "$cwd/.claude" 2>/dev/null

# Fresh checkpoint -> allow compaction now.
if [ -f "$flag" ]; then
  age_min=$(( ( $(date +%s) - $(stat -c %Y "$flag" 2>/dev/null || echo 0) ) / 60 ))
  if [ "$age_min" -lt "$FLAG_MAX_AGE_MIN" ]; then
    rm -f "$counter"
    exit 0
  fi
fi

# Stale/no checkpoint: block, but fail open after MAX_BLOCKS consecutive blocks.
blocks=$(cat "$counter" 2>/dev/null || echo 0)
case "$blocks" in (*[!0-9]*|'') blocks=0;; esac
if [ "$blocks" -ge $((MAX_BLOCKS - 1)) ]; then
  rm -f "$counter"
  exit 0
fi
echo $((blocks + 1)) > "$counter"

cat <<EOF
{"decision": "block", "reason": "Auto-compact deferred (no recent task-boundary checkpoint). Reach a stopping point NOW: finish only the current atomic step, persist state (update the product roadmap.md and/or session summary with in-flight work, PR/CI state, and next steps), then run: touch $flag . Compaction will be allowed at the next trigger. This defers at most $MAX_BLOCKS times, then compaction proceeds regardless."}
EOF
exit 0
