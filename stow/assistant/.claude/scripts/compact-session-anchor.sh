#!/bin/bash
# SessionStart (matcher: compact): re-anchor the model after compaction by
# injecting the saved session summary plus standing operating reminders.

MAX_CHARS=6000

input=$(cat)

if command -v jq &>/dev/null; then
  cwd=$(echo "$input" | jq -r '.cwd // empty' 2>/dev/null)
else
  cwd=""
fi

summary=""
if [ -n "$cwd" ] && [ -f "$cwd/.claude/session-summary.md" ]; then
  summary=$(head -c "$MAX_CHARS" "$cwd/.claude/session-summary.md")
fi

context="[Post-compaction re-anchor]
Rules that survive compaction:
- Before continuing product work, re-read products/<name>/roadmap.md (living tracker; keep it updated).
- Owner-only, never do: merge/push to main, Stripe/auth/pricing/legal/signup-switch, destructive migrations, external posting.
- Overnight loop: one loop in this session only; follow the numbered procedure in CLAUDE.md exactly.
- At every task boundary: persist state, then touch .claude/compact-ok (compaction gate).
${summary:+
Saved session summary (may predate recent work — trust the roadmap over this):
$summary}"

if command -v jq &>/dev/null; then
  jq -n --arg ctx "$context" '{"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": $ctx}}'
fi
exit 0
