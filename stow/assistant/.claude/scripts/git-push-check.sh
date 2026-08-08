#!/bin/bash
# PreToolUse (Bash): git push safety checks.
# 1) BLOCK (exit 2): pushing to main / merging into main in owner-gated repos.
#    Configure matching repositories with OWNER_GATED_REPO_PATTERN.
#    Bypass ONLY on explicit owner instruction: prefix command with OWNER_PUSH_OK=1
# 2) WARN (stderr, exit 0): uncommitted changes / commits-ahead summary before any push.

input=$(cat)

# Extract bash command
if command -v jq &>/dev/null; then
  cmd=$(echo "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
else
  cmd=$(echo "$input" | grep -oP '"command"\s*:\s*"\K[^"]+' | head -1)
fi

[ -z "$cmd" ] && exit 0

# Explicit owner bypass (use only when the owner asked for this exact push)
if echo "$cmd" | grep -q 'OWNER_PUSH_OK=1'; then
  exit 0
fi

# Determine target repo: honor `git -C <path>` / leading `cd <path>`; else hook cwd.
repo_dir=$(echo "$cmd" | grep -oP '(?:git\s+-C\s+|^\s*cd\s+)\K[^\s;&|]+' | head -1)
repo_dir=${repo_dir/#\~/$HOME}
[ -d "$repo_dir" ] || repo_dir="."

origin=$(git -C "$repo_dir" remote get-url origin 2>/dev/null)

# Owner-gated repos: main branch is owner-only when a local pattern is set.
owner_gated_pattern="${OWNER_GATED_REPO_PATTERN:-}"
if [ -n "$owner_gated_pattern" ] \
  && echo "$origin" | grep -qiE -- "$owner_gated_pattern"; then
  # git push touching main (push origin main / HEAD:main / --delete main ...)
  if echo "$cmd" | grep -qE 'git\s+(-C\s+\S+\s+)?push' && echo "$cmd" | grep -qE '(^|[[:space:]:/])main([[:space:];&|"'"'"']|$)'; then
      echo "[Hook] BLOCKED: pushing to 'main' in this owner-gated repository is disabled. Create a promotion PR instead." >&2
    exit 2
  fi
  # writing to local main
  current_branch=$(git -C "$repo_dir" branch --show-current 2>/dev/null)
  if [ "$current_branch" = "main" ] && echo "$cmd" | grep -qE 'git\s+(-C\s+\S+\s+)?(merge|rebase|commit|cherry-pick|reset)'; then
      echo "[Hook] BLOCKED: writing to local 'main' in this owner-gated repository is disabled. Switch to a feature branch." >&2
    exit 2
  fi
  # gh pr merge: verify the PR base is not main (fail-closed if base unknown)
  if echo "$cmd" | grep -qE 'gh\s+pr\s+merge'; then
    pr=$(echo "$cmd" | grep -oP 'gh\s+pr\s+merge\s+\K[0-9]+' | head -1)
    base=""
    if [ -n "$pr" ]; then
      base=$(cd "$repo_dir" 2>/dev/null && gh pr view "$pr" --json baseRefName -q .baseRefName 2>/dev/null)
    fi
    if [ "$base" = "main" ] || [ -z "$base" ]; then
      echo "[Hook] BLOCKED: 'gh pr merge' requires a verified non-main base (got: '${base:-unknown}'). Pass an explicit PR number so the base can be verified." >&2
      exit 2
    fi
  fi
fi

# Non-blocking pre-push summary (all repos)
if echo "$cmd" | grep -qE 'git\s+(-C\s+\S+\s+)?push'; then
  if git -C "$repo_dir" rev-parse --is-inside-work-tree &>/dev/null; then
    unstaged=$(git -C "$repo_dir" diff --stat 2>/dev/null)
    staged=$(git -C "$repo_dir" diff --cached --stat 2>/dev/null)

    if [ -n "$unstaged" ] || [ -n "$staged" ]; then
      echo "[Hook] Uncommitted changes detected before git push:" >&2
      [ -n "$staged" ] && echo "  Staged: $(echo "$staged" | tail -1)" >&2
      [ -n "$unstaged" ] && echo "  Unstaged: $(echo "$unstaged" | tail -1)" >&2
    fi

    branch=$(git -C "$repo_dir" branch --show-current 2>/dev/null)
    ahead=$(git -C "$repo_dir" rev-list --count "@{upstream}..HEAD" 2>/dev/null)
    if [ -n "$ahead" ] && [ "$ahead" -gt 0 ]; then
      echo "[Hook] $branch: pushing $ahead commit(s)" >&2
    fi
  fi
fi

exit 0
