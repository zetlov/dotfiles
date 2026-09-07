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

refspec_targets_main() {
  local destination="${1#+}"
  destination="${destination##*:}"
  case "$destination" in
    main|refs/heads/main|""|*\**) return 0 ;;
    HEAD) [ "$current_branch" = main ]; return ;;
    *) return 1 ;;
  esac
}

implicit_push_targets_main() {
  local remote="$1" configured_refs refspec push_default
  if [ -z "$remote" ]; then
    remote=$(git -C "$repo_dir" config --get "branch.${current_branch}.pushRemote" 2>/dev/null \
      || git -C "$repo_dir" config --get remote.pushDefault 2>/dev/null \
      || git -C "$repo_dir" config --get "branch.${current_branch}.remote" 2>/dev/null \
      || printf origin)
  fi
  [ "$(git -C "$repo_dir" config --bool --get "remote.${remote}.mirror" 2>/dev/null)" = true ] && return 0
  configured_refs=$(git -C "$repo_dir" config --get-all "remote.${remote}.push" 2>/dev/null)
  if [ -n "$configured_refs" ]; then
    while IFS= read -r refspec; do
      refspec_targets_main "$refspec" && return 0
    done <<< "$configured_refs"
    return 1
  fi
  push_default=$(git -C "$repo_dir" config --get push.default 2>/dev/null || printf simple)
  case "$push_default" in
    nothing) return 1 ;;
    matching) return 0 ;;
    upstream|tracking)
      refspec=$(git -C "$repo_dir" config --get "branch.${current_branch}.merge" 2>/dev/null)
      refspec_targets_main "$refspec" && return 0
      ;;
  esac
  [ "$current_branch" = main ]
}

push_targets_main() {
  local push_arguments remote="" argument expect_value="" explicit_refs=0 tags_only=0
  local configured_refs refspec
  local -a arguments=()
  [[ "$cmd" == *$'\n'* || "$cmd" =~ [\;\&\|] ]] && return 0
  push_arguments=$(printf '%s\n' "$cmd" | grep -oP 'git\s+(?:-C\s+\S+\s+)?push\K(?:\s.*)?$')
  # Inspect simple literal arguments only; never evaluate shell syntax from a hook.
  [[ "$push_arguments" =~ ^[[:alnum:][:space:]_./:@=,+%*-]*$ ]] || return 0
  read -r -a arguments <<< "$push_arguments"
  for argument in "${arguments[@]}"; do
    if [ -n "$expect_value" ]; then
      [ "$expect_value" = remote ] && remote="$argument"
      expect_value=""
      continue
    fi
    case "$argument" in
      --all|--branches|--mirror) return 0 ;;
      --tags) tags_only=1 ;;
      --repo) expect_value=remote ;;
      --repo=*) remote="${argument#--repo=}" ;;
      -o|--push-option|--receive-pack|--exec) expect_value=ignored ;;
      --push-option=*|--receive-pack=*|--exec=*) ;;
      -f|-u|-n|-q|-v|-d|--force|--set-upstream|--dry-run|--quiet|--verbose|--delete|--porcelain|--atomic|--no-verify|--follow-tags|--prune|--force-with-lease|--force-with-lease=*|--force-if-includes) ;;
      -*) return 0 ;;
      *)
        if [ -z "$remote" ]; then
          remote="$argument"
        else
          explicit_refs=1
          refspec_targets_main "$argument" && return 0
          if [[ "$argument" != *:* ]]; then
            configured_refs=$(git -C "$repo_dir" config --get-all "remote.${remote}.push" 2>/dev/null)
            while IFS= read -r refspec; do
              [ -n "$refspec" ] && refspec_targets_main "$refspec" && return 0
            done <<< "$configured_refs"
          fi
        fi
        ;;
    esac
  done
  if [ "$explicit_refs" -eq 1 ] || [ "$tags_only" -eq 1 ]; then
    return 1
  fi
  implicit_push_targets_main "$remote"
}

# Owner-gated repos: main branch is owner-only when a local pattern is set.
owner_gated_pattern="${OWNER_GATED_REPO_PATTERN:-}"
if [ -n "$owner_gated_pattern" ] \
  && echo "$origin" | grep -qiE -- "$owner_gated_pattern"; then
  current_branch=$(git -C "$repo_dir" branch --show-current 2>/dev/null)
  if echo "$cmd" | grep -qE 'git\s+(-C\s+\S+\s+)?push([[:space:]]|$)' && push_targets_main; then
      echo "[Hook] BLOCKED: pushing to 'main' in this owner-gated repository is disabled. Create a promotion PR instead." >&2
    exit 2
  fi
  # writing to local main
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
