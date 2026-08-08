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

## Development tools

Tool ownership follows the runtime boundary:

- yay/pacman owns OS-integrated commands and desktop runtime dependencies,
  including Git, GitHub CLI, jq, Python, Neovim, ripgrep, fd, fzf, and lazygit.
- mise owns language runtimes and version-sensitive development tools. The
  shared global defaults live in
  `stow/base/.config/mise/conf.d/dotfiles.toml`; repository-only audit tools
  live in `mise.toml`.
- mise itself is installed by yay/pacman so a fresh machine has a stable
  bootstrap path. A full `install.sh` run links the shared configuration and
  then runs `mise install`.

The global Node.js entry tracks a major release so compatible updates arrive
without jumping to a new major. Codex CLI, Herdr, and AWS CLI track their latest
releases because they are interactive user tools, while repository audit tools
use exact versions for reproducible checks. Herdr's official installation
documentation supports mise; using that path avoids executing a mutable remote
installer during bootstrap. A full bootstrap also installs Herdr's Codex
integration after the local Codex configuration has been initialized. AWS
credentials and configuration remain local and are never managed by this
repository. Run `mise upgrade` to update the global tools. Keep
machine- or project-specific overrides in an untracked
`~/.config/mise/config.toml` or project `mise.local.toml` rather than adding
them to the shared global file. The unmanaged global file has higher priority
than `conf.d`, so avoid redefining shared tools there unless an override is
intentional.

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
