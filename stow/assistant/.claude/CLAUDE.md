# Global Working Rules

Detailed rules in `~/.claude/rules/` (auto-loaded): coding-style, testing, git-workflow, security, tooling.

## Language
- Code (identifiers, comments, docstrings), commit messages, PR descriptions → English
- Chat responses to the user → Japanese (日本語)

## Workflow
- Plan first (planner agent / Plan Mode) when a change is a new feature OR touches 3+ files. Then TDD → code review → commit.
- When orchestrating product work, delegate multi-file implementation to background agents (one PR per task, isolated git worktree, CI-green gate) and stay available for conversation; do light ops (small edits, git, status checks) directly.
- Run independent agents and tool calls in parallel, not sequentially.
- Custom agents live in `~/.claude/agents/`. Mechanical triggers (no judgment call — if the condition holds, run the agent):
  - code-reviewer: any commit changing 2+ files or >50 changed lines of non-test code.
  - security-reviewer: any commit touching auth, session, user input parsing, payment/Stripe, or new public endpoints.

## Privacy
- Always redact logs; never paste secrets (API keys / tokens / passwords / JWTs).
- Review output before sharing; remove sensitive data.

## Knowledge Capture
- Personal debugging notes, preferences, temporary context → auto memory.
- Team/project knowledge (architecture decisions, API changes, runbooks) → the project's existing docs structure; don't duplicate knowledge the current task already documents.
- No obvious doc location → ask before creating a new top-level doc.

## Session Continuity
- On session start, if `.claude/session-summary.md` exists, read it to restore context.
- When pausing or ending a session, run `/save`; if forgotten, the Stop hook auto-generates a minimal summary.
- **Compaction checkpoints**: at every task boundary (subtask done, PR merged, report delivered, batch item finished) persist state (roadmap / session summary), then run `touch .claude/compact-ok`. Auto-compact is hook-gated on this flag being <30 min old; if a compaction attempt is deferred with instructions to checkpoint, do it immediately.
