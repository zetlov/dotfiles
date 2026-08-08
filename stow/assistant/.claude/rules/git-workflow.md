# Git & Development Workflow

## Before writing new code
- Search for existing implementations first: GitHub code search (`gh search repos` / `gh search code`), package registries (npm, PyPI, crates.io), and primary library docs. Prefer adopting or porting a proven approach over net-new code.
- For complex features: plan (planner agent) → TDD (tdd-guide) → implement → code review (code-reviewer) → commit.

## Commits
- Conventional commits: `<type>: <description>` — feat, fix, refactor, docs, test, chore, perf, ci.
- Small, focused commits; test locally before committing.
- No AI attribution in commit messages or PR bodies (no Co-Authored-By / "Generated with" footers).

## Pull Requests
- Review the full branch diff (`git diff <base>...HEAD`), not just the latest commit.
- Comprehensive summary + test plan; push new branches with `-u`.

## Worktrees (working in another repo / delegating to agents)
- **One agent = one PR = one worktree.** Never let two agents (or an agent and the main session) share a checkout.
- **Create manually**, not via the Agent tool's `isolation: "worktree"` — that fails when the orchestrating session's cwd is not a git repo (e.g. assistant-home). Put the exact commands in the agent's prompt:
  `git fetch origin && git worktree add ../<repo>-wt-<name> origin/<base> -b <type>/<name>` (base = develop unless stated otherwise), then install deps inside the worktree (e.g. `pnpm install --prefer-offline`).
- **Naming**: sibling directory `../<repo>-wt-<name>`, matching the branch topic.
- **Cleanup after merge**: from the main checkout, `git worktree remove ../<repo>-wt-<name>`, then delete the branch. Check for uncommitted/unpushed work before removing — never remove a dirty worktree.
- **Parallelism cap**: at most 2 concurrent agents whose work needs Docker/e2e (shared port 5432 / CPU); pure-code agents are not capped.
- **Repo-specific gates win**: each code repo's own `CLAUDE.md` defines its base branch, CI gate, and worktree details — read it before creating worktrees there.
