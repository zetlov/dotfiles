---
name: save
description: Save current session state. Automatically loaded at next session start.
---

## Instructions

Summarize the current work state and save it to `.claude/session-summary.md`.

## Content to Save

Write in the following format:

```markdown
---
saved_at: YYYY-MM-DD HH:MM
directory: /path/to/project
branch: branch-name
---

# Session Summary

## What I Was Working On
[Overview of the task this session was focused on. 1-3 sentences.]

## Completed
- [List of completed changes]

## Incomplete / In Progress
- [Work that was interrupted. How far it got and what to do next]

## Key Decisions and Discoveries
- [Design decisions made or issues discovered during this session]

## Next Steps
1. [Highest priority task]
2. [Next priority]

## Notes
- [Things to watch out for in the next session. Known bugs, fragile areas, etc.]
```

## Principles

- Be concise. Each section should be 2-5 lines
- Be specific. Not "fixed various things" but "fixed token refresh logic in auth.py"
- For incomplete tasks, include enough info to resume (filenames, line numbers, what was tried)
- Always save to `.claude/session-summary.md` at the project root
