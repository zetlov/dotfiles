# CLAUDE.md

This file provides repository-local guidance for Claude Code.

## Repository overview

Personal dotfiles managed with GNU Stow. The repository root is not a Stow
package. HOME-facing files are restricted to `stow/base`, `stow/desktop`, and
`stow/assistant` and are deployed with `scripts/stow-dotfiles.sh`.

## Common commands

```bash
./install.sh --link-only
./install.sh
./install.sh --without-tex
./scripts/stow-dotfiles.sh
mise run check
```

## Architecture

- `stow/base`: shell, Git, terminal, Neovim, Herdr, and CLI configuration.
- `stow/desktop`: Hyprland, Quickshell, desktop defaults, and local utilities.
- `stow/assistant`: generic Claude and Codex instructions, agents, and skills.
- `examples/local`: copy-once defaults for mutable or host-specific files.
- `windows`: copied Windows-side deployment for Kanata, Komorebi, and WezTerm.
- `packages`: Arch package profiles consumed by `install.sh`.

Always use `--no-folding`; `~/.config`, `~/.claude`, and `~/.codex` must remain
real directories. Never commit Codex authentication/config state, Claude local
settings/session summaries, shell secrets, GitHub hosts, AtCoder sessions, or
application databases and caches.

## Main configuration entrypoints

- Neovim: `stow/base/.config/nvim/init.lua`
- Hyprland: `stow/desktop/.config/hypr/hyprland.lua`
- Quickshell: `stow/desktop/.config/quickshell/zetshell/shell.qml`
- Shell: `stow/base/.zshrc`
- LaTeX: `stow/base/.latexmkrc`

Use conventional commits with optional scope. Run the relevant tests and the
public boundary check before proposing a commit or publication.
