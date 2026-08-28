# AGENTS.md

Repository-local instructions for Codex and other coding agents working in this
dotfiles repository.

Global Codex preferences live in `stow/assistant/.codex/AGENTS.md` and are linked to
`~/.codex/AGENTS.md` by `install.sh`. This file stays repository-local and is
ignored by Stow.

## Repository Overview

This is a personal dotfiles repository managed with three explicit GNU Stow
packages. Use `scripts/stow-dotfiles.sh`; the repository root is not a Stow
package.

Common commands:

```bash
./install.sh
./install.sh --link-only
./install.sh --without-tex
./scripts/tex-install-missing.sh paper.tex [--update-list] [--dry-run] [--yes]
./scripts/stow-dotfiles.sh
mise run check
```

## Repository Notes

- `.gitignore` uses a top-level allowlist and explicit credential/state deny rules.
- Only `stow/{base,desktop,assistant}` contains HOME-facing managed files.
- `~/.config` should remain a real directory; tracked config files are linked below it with `stow --no-folding`.
- `stow/assistant/.codex/AGENTS.md` is linked to `~/.codex/AGENTS.md`.
- Neovim config starts at `stow/base/.config/nvim/init.lua`.
- Hyprland starts at `stow/desktop/.config/hypr/hyprland.lua`.
- Quickshell starts at `stow/desktop/.config/quickshell/zetshell/shell.qml`.
- Shell config is in `stow/base/.zshrc`; sensitive shell config is sourced from `~/.zsh_secrets` and is not tracked.
- Desktop environment configs include Hyprland, Quickshell, and Rofi.
- Wallpaper image assets are local and are not tracked.
- LaTeX builds use LuaLaTeX via `stow/base/.latexmkrc` with output in `out/`.

## Assistant Instruction Layout

- Repo-local Claude instructions: `CLAUDE.md`
- Global Claude instructions: `stow/assistant/.claude/CLAUDE.md`
- Repo-local Codex instructions: `AGENTS.md`
- Global Codex instructions: `stow/assistant/.codex/AGENTS.md`
- Repo-local Copilot instructions: `.github/copilot-instructions.md`

Keep reusable global preferences in `.codex/AGENTS.md` and `.claude/CLAUDE.md`.
Keep dotfiles-specific details in this file and `CLAUDE.md`.
