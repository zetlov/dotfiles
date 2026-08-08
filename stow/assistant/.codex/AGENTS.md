# AGENTS.md

Global instructions for Codex and other coding agents. This is the Codex
counterpart of the Claude `CLAUDE.md` + `~/.claude/rules/*` set, adapted to
Codex's capabilities (custom agents in `~/.codex/agents/*.toml`, skills in
`~/.codex/skills/`, MCP servers, and execpolicy `.rules`).

## Core Principles

1. Plan before executing non-trivial work, and keep the plan current.
2. Reuse before writing: prefer proven libraries and existing patterns.
3. Test-driven: write tests first for new features and bug fixes.
4. Security-first: never compromise on security.
5. Run independent reads and checks in parallel when the tool supports it.

## Personal Preferences

- Chat responses to the user should be in Japanese.
- Code, comments, docstrings, commit messages, and PR descriptions should be in English.
- Do not use emojis in code, comments, documentation, commit messages, or PR text.
- Redact logs before sharing output. Never paste secrets, tokens, passwords, API keys, JWTs, or private credentials.
- Capture durable project knowledge in the existing docs structure. Do not create a new top-level doc unless there is no obvious location. Do not duplicate knowledge the task's own docs, comments, or examples already capture.

## Development Workflow

### 0. Research and Reuse (before any new implementation)

- Search for existing implementations first (e.g. `gh search repos`, `gh search code`) before writing anything new.
- Confirm API behavior against primary documentation (vendor docs) for the package and version in use.
- Check package registries (npm, PyPI, crates.io, etc.) before hand-rolling utilities. Prefer battle-tested libraries.
- Look for open-source projects that solve 80%+ of the problem and can be adapted, ported, or wrapped.

### 1. Plan First

- For substantial work, produce a clear plan: requirements, affected components, dependencies, risks, and phased steps.
- Break large features into independently deliverable phases.

### 2. TDD Approach

1. Write a failing test that describes the expected behavior (RED).
2. Run it and confirm it fails.
3. Write the minimal implementation to pass (GREEN).
4. Run it and confirm it passes.
5. Refactor while keeping tests green (IMPROVE).
6. Verify coverage (target 80%+).

### 3. Code Review

- Review your own changes for quality and security immediately after writing them.
- Address CRITICAL and HIGH issues before proceeding; fix MEDIUM issues when practical.

### 4. Commit and Push

- Use conventional commits and keep changes small and focused.
- Test locally before committing. Commit or push only when explicitly asked.

## Code Style

- Prefer immutable data updates over in-place mutation. Create new objects/arrays; never mutate existing ones.
- Many small, focused files over few large ones: 200-400 lines typical, 800 lines maximum unless the local codebase clearly differs.
- Keep functions small (under ~50 lines) and avoid nesting deeper than 4 levels.
- Handle errors explicitly at every boundary. Never silently swallow failures.
- UI-facing errors should be understandable to users; internal logs should carry enough context to debug without leaking secrets.
- Validate data at system boundaries (user input, API responses, file content). Use schema-based validation where the project already has it. Fail fast with clear messages.
- Avoid hardcoded values when constants or configuration would be clearer. Never hardcode secrets; use environment variables or a secret manager.
- Match the surrounding code's style, naming, and comment density.

### Quality checklist (before marking work complete)

- [ ] Readable and well-named
- [ ] Functions small, files focused, no deep nesting
- [ ] Errors handled; no silent failures
- [ ] No hardcoded values or secrets
- [ ] Immutable patterns used
- [ ] Relevant tests and formatters run (or a clear reason why not)

## Tooling

Runtime versions (node, python, ruby, etc.) are managed by **mise**.

- Execute through mise: do not assume a globally installed runtime. mise is activated in interactive shells via `eval "$(mise activate zsh)"`, but non-interactive/agent shells may not source `.zshrc`. If a tool or version is missing or looks wrong, run it through `mise exec -- <cmd>` (or `mise x -- <cmd>`).
- Pin versions with mise: pin project tool versions in `mise.toml` (or `.tool-versions`). Never install runtimes globally; add them with `mise use <tool>@<version>`.
- Tasks via `mise run`: define repeated project commands as mise tasks and run them with `mise run <task>` instead of ad-hoc scripts.

## Testing

- Minimum coverage target: 80%.
- Required test types: unit (functions, utilities), integration (API endpoints, database operations), and E2E for critical user flows.
- Fix the implementation, not the tests, unless the tests are demonstrably wrong.
- Check test isolation and mock correctness when diagnosing failures.

## Security

Before commits or PRs, check:

- No hardcoded secrets (API keys, passwords, tokens, connection strings).
- All user inputs validated.
- SQL queries parameterized where relevant.
- HTML output sanitized where relevant; XSS prevented.
- CSRF protection and rate limiting considered for web endpoints.
- Authentication and authorization changes reviewed.
- Error messages do not expose sensitive data.

Secret management:

- Never hardcode secrets. Use environment variables or a secret manager.
- Validate that required secrets are present at startup.
- Rotate any secret that may have been exposed.

If a security issue is found: stop feature work, fix CRITICAL issues first, rotate exposed secrets, and review the surrounding code for similar problems.

## Git Workflow

- Conventional commits with optional scope: `feat:`, `fix:`, `refactor:`, `docs:`, `test:`, `chore:`, `perf:`, `ci:` (e.g. `feat(scope): message`).
- Keep commits small and focused. Test locally before committing.
- For PRs: review the full branch diff (`git diff <base>...HEAD`), not only the latest commit. Include a concise summary and a test plan in the description.

## Custom Agents

Project- and user-scoped subagents are defined as TOML files in `~/.codex/agents/*.toml`
(personal) or `.codex/agents/*.toml` (project). Codex may spawn specialized subagents proactively
without an explicit user request when delegation materially improves quality, verification, or
latency. Keep simple or tightly coupled work in the main agent, and do not delegate merely because
a matching role exists. Available roles:

| Agent | Purpose | When to use |
|-------|---------|-------------|
| planner | Implementation planning | Complex features, refactors |
| architect | System design and architecture | Architectural decisions |
| implementer | Writes production code from a plan/spec | Coding a feature/fix after planning |
| tdd-guide | Test-driven development | New features, bug fixes |
| code-reviewer | Quality and security review | After writing or modifying code |
| security-reviewer | Vulnerability analysis | Before commits, on input/auth/API/data code |
| build-error-resolver | Build and compile error resolution | When the build fails |
| refactor-cleaner | Dead code cleanup and consolidation | Code maintenance |
| researcher | Research and deep analysis | Investigating tech, comparing approaches |

Orchestration guidance:

- Run independent agent tasks in parallel rather than sequentially.
- Automatically select the smallest useful set of specialized agents based on the task and each
  role's description; explicit user requests for an agent take precedence.
- Keep edits with one owner. Use read-only roles for parallel research, planning, and review, and
  avoid assigning overlapping file changes to multiple agents.
- For complex problems, use multiple perspectives (factual reviewer, senior engineer, security expert, consistency reviewer, redundancy checker).
- Use specialized agents only when the current environment supports them and the task benefits from delegation.

## Skills

User skills live in `~/.codex/skills/<name>/SKILL.md` and are loaded on demand:

- `obsidian-note` — convert a handwritten note image into atomic Zettelkasten notes in the Obsidian vault.

## Model and Effort

- Match reasoning effort to task difficulty. Use higher `model_reasoning_effort` (e.g. `high`/`xhigh`) for architecture, planning, research, and complex debugging; lower effort is fine for single-file edits, simple fixes, and documentation.
- Avoid the last portion of the context window for large refactors and multi-file features; prefer focused, incremental steps.
