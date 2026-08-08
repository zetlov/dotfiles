# dotfiles

Public-safe personal dotfiles for Arch Linux, WSL, and selected Windows tools.
GNU Stow deploys only the explicit packages under `stow/`; repository metadata,
tests, Windows installers, and local examples are never treated as dotfiles.

## Quick start

Link the managed configuration without installing packages:

```bash
git clone <repository-url> ~/dotfiles
cd ~/dotfiles
./install.sh --link-only
```

On an Arch-based system, the full bootstrap remains available after installing
and reviewing `yay` separately:

```bash
./install.sh
./install.sh --with-tex
./install.sh --with-komorebi
./install.sh --with-nvidia
```

The full bootstrap upgrades packages and installs official/AUR packages. It
does not bootstrap an AUR helper or execute remote installer scripts. Review
the AUR packages in `packages/` before running it. Use `--link-only` when
preparing an existing machine or reviewing a clone.

Native ARM systems support `--link-only`; the full desktop bootstrap is
limited to x86_64. NVIDIA packages are isolated in an explicit
`--with-nvidia` profile and are never installed by the portable desktop
profile.

## Layout

```text
stow/
├── base/       # shell, terminal, editor, Git, and CLI configuration
├── desktop/    # Hyprland, Quickshell, desktop defaults, and local utilities
└── assistant/  # generic Claude and Codex instructions, agents, and skills
```

The wrapper always uses `--no-folding`, so directories such as `~/.config`,
`~/.claude`, and `~/.codex` remain real directories.

```bash
./scripts/stow-dotfiles.sh
stow --restow --dir "$PWD/stow" --target "$HOME" --no-folding base desktop assistant
stow --delete --dir "$PWD/stow" --target "$HOME" base desktop assistant
```

Do not run `stow .` from the repository root; the root is intentionally not a
Stow package.

## Local configuration

Machine-specific and mutable files are copied once from `examples/local/` and
are not managed by Stow:

- `~/.codex/config.toml`
- `~/.gitconfig.local`
- `~/.config/hypr/settings.local.lua`
- `~/.config/atcoder-cli-nodejs/config.json`
- `~/.config/switch-audio/config.env`
- `~/.config/zetshell/*`

Initialize missing files without replacing existing values:

```bash
./scripts/init-local-config.sh
./scripts/init-local-config.sh --dry-run
```

The Git example uses the public GitHub noreply address for `zetlov`. Edit
`~/.gitconfig.local` if a machine or repository needs a different verified
address; the local file is copied once and is never managed by Stow.

Monitor connector names, modes, positions, scaling, and the NVIDIA-specific
Hyprland environment are configured in `~/.config/hypr/settings.local.lua`.
Empty monitor names use the compositor's preferred automatic layout.

Secrets belong in `~/.zsh_secrets`; machine-only shell configuration belongs
in `~/.zshrc.local`. Neither file is tracked.

## Key entrypoints

- Neovim: `stow/base/.config/nvim/init.lua`
- Hyprland: `stow/desktop/.config/hypr/hyprland.lua`
- Quickshell: `stow/desktop/.config/quickshell/zetshell/shell.qml`
- Shell: `stow/base/.zshrc`
- Windows deployment: `windows/`

Wallpaper assets are local. The default directory is
`${XDG_DATA_HOME:-$HOME/.local/share}/wallpapers`; override it with
`WALLPAPER_DIR`.

## Windows and WSL

The WSL bootstrap can deploy WezTerm, Kanata, and optionally Komorebi to the
Windows side. Component-specific installation, update, rollback, and recovery
instructions live under `windows/<component>/README.md`.

Windows host values can use ignored `*.local.json` files. For example,
`windows/komorebi/audio-output.local.json` overrides the generic checked-in
audio device patterns during install and update.

## Validation

```bash
mise run check

# Or run the repository tests without mise-managed audit tools:
for test_file in scripts/tests/*.test.sh; do "$test_file"; done
scripts/security/check-public-tree.sh
```

The public boundary check rejects credential filenames, private assistant
state, personal home paths, common personal email addresses, and symlinks that
escape the repository. An optional private denylist can be supplied through
`DOTFILES_DENYLIST` for host-specific names and identifiers.
