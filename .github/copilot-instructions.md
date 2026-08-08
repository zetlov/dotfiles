# GitHub Copilot Instructions

## Repository Context

This repository contains public-safe personal dotfiles for Arch Linux, WSL,
and selected Windows tools. GNU Stow deploys only the explicit packages under
`stow/`; the repository root is not a Stow package.

Use the checked-in wrappers:

```bash
./install.sh --link-only
./scripts/stow-dotfiles.sh
./scripts/init-local-config.sh
```

Never run `stow .`, `stow -D .`, or `stow -R .` from the repository root.
When a direct Stow command is necessary, use `--dir "$PWD/stow"`, target
`$HOME`, and the explicit `base desktop assistant` package list.

## Response And Writing Preferences

- Respond to the user in Japanese.
- Write code, comments, docstrings, commit messages, and PR descriptions in English.
- Do not use emojis in code, comments, documentation, commits, or PR text.
- Never include secrets, credentials, tokens, API keys, passwords, JWTs, or private config in generated output.
- Redact sensitive values when summarizing logs.

## Coding Standards

- Prefer immutable updates over in-place mutation.
- Keep files focused and functions small.
- Validate input and external data at system boundaries.
- Handle errors explicitly and avoid silently swallowing failures.
- Follow existing project structure and local conventions before introducing new abstractions.

## Testing And Workflow

- Use TDD for new features and bug fixes when practical.
- Add or update tests with behavior changes.
- Run relevant tests and formatters before considering work complete.
- Run `scripts/security/check-public-tree.sh` before publication.
- Security-sensitive work must be reviewed for secrets, injection risks, data leakage, and unsafe error messages.

## Git

- Use conventional commits: `feat:`, `fix:`, `refactor:`, `docs:`, `test:`, `chore:`, `perf:`, `ci:`.
- Keep commits small and focused.
- PR descriptions should include a concise summary and test plan.

## Project Notes

- `stow/base` contains shell, terminal, editor, Git, and CLI configuration.
- `stow/desktop` contains Hyprland, Quickshell, and Rofi configuration.
- `stow/assistant` contains generic Codex and Claude instructions.
- Secrets are sourced from `~/.zsh_secrets` and are never tracked.
- Machine-specific files are initialized from `examples/local/` and remain unmanaged.
- LaTeX builds use LuaLaTeX via `.latexmkrc`.
