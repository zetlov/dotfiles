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
./install.sh --dry-run
./install.sh
./install.sh --with-tex
./install.sh --with-komorebi
./install.sh --with-glazewm
./install.sh --with-nvidia
./install.sh --system-upgrade
```

The full bootstrap installs missing official/AUR packages without upgrading
unrelated installed packages. Add `--system-upgrade` to run a full system and
AUR upgrade before installing the selected profiles. This flag does not update
mise tools or Windows components beyond the normal bootstrap behavior. The
installer does not bootstrap an AUR helper or execute remote installer scripts.
Review the AUR packages in `packages/` before running it. Use `--link-only`
when preparing an existing machine or reviewing a clone.

To avoid an unsupported Arch partial upgrade, the default package phase checks
the current sync database with `pacman -Qu` and stops before mutation when
system updates are pending. In that state, review the update and rerun with
`--system-upgrade`; the installer never refreshes the package database without
performing the matching full upgrade.

`--dry-run` validates the target and prints the detected environment,
container backend, and package profiles without changing the system or HOME.
Native Linux desktops use the `native` container backend by default. WSL uses
Docker Desktop integration by default and does not install a second Docker
daemon inside the distribution. Override this explicitly when needed:

```bash
./install.sh --dry-run --container-backend=native
./install.sh --container-backend=none
```

Accepted container backends are `auto`, `desktop`, `native`, and `none`.
`desktop` is valid only under WSL; `native` installs the reviewed packages in
`packages/container-native.txt`. Before a full WSL bootstrap uses `desktop`,
Docker Desktop must be running with integration enabled for that distribution;
the installer verifies the Docker client/server connection before upgrading or
installing Linux packages. Following Docker's WSL guidance, distro-managed
Docker Engine, Docker-compatible CLI providers, and `docker-compose` must be
removed before using this backend; the preflight rejects them instead of
silently using a native daemon.

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

The `desktop` Stow profile links `base`, `desktop`, and `assistant`; the `wsl`
profile links only `base` and `assistant`. A full bootstrap selects the profile
from kernel-backed environment detection. Standalone and `--link-only` runs
retain the `desktop` default for compatibility, with an explicit WSL override:

```bash
./scripts/stow-dotfiles.sh
./scripts/stow-dotfiles.sh --profile=wsl
./scripts/stow-dotfiles.sh --profile=wsl --preflight
./install.sh --link-only --profile=wsl
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

The WSL profile initializes only Codex, Claude, Git, and AtCoder CLI local
files. Hyprland, switch-audio, and Zetshell local files belong to the desktop
profile. All source and target parents are validated before any file is copied.

Initialize missing files without replacing existing values:

```bash
./scripts/init-local-config.sh
./scripts/init-local-config.sh --dry-run
./scripts/init-local-config.sh --profile=wsl
```

The Git example uses the public GitHub noreply address for `zetlov`. Edit
`~/.gitconfig.local` if a machine or repository needs a different verified
address; the local file is copied once and is never managed by Stow.

Monitor connector names, modes, positions, scaling, and the NVIDIA-specific
Hyprland environment are configured in `~/.config/hypr/settings.local.lua`.
Empty monitor names use the compositor's preferred automatic layout.

Secrets belong in `~/.zsh_secrets`; machine-only shell configuration belongs
in `~/.zshrc.local`. Neither file is tracked.

The managed Zsh configuration loads Oh My Zsh from `~/.oh-my-zsh` when it is
installed, with the Git, autosuggestions, and syntax-highlighting plugins.
Starship remains the prompt renderer. Portable installs without Oh My Zsh fall
back to the system Arch plugin scripts when available.

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

The WSL bootstrap can deploy WezTerm, Kanata, and one explicitly selected
Windows window manager. GlazeWM is the active configuration; Komorebi is kept
temporarily as rollback material while the GlazeWM setup proves stable. Do not
select both window-manager flags in one run. GlazeWM owns active login-app
startup and workspace placement. The standalone Task Scheduler component under
`windows/autostart` remains paired with the Komorebi rollback path and is not
part of the active GlazeWM lifecycle.

| Component | Status | Ownership and deployment |
| --- | --- | --- |
| glazewm | active | Window manager, login-app startup, runtime helpers, and deployment through `windows/glazewm/install.ps1` |
| zebar | active | Bar source and tracked bundle; deployed by the GlazeWM installer through `windows/zebar/install.ps1` |
| audio | shared | Hash-pinned `AudioDeviceCmdlets` dependency shared by the GlazeWM and Komorebi configurations |
| wezterm | active | Terminal configuration and user-scoped fonts through `windows/wezterm/install.ps1` |
| kanata | active | Keyboard service configuration and lifecycle through `windows/kanata/install.ps1` |
| komorebi | rollback-only | Previous window-manager configuration retained for a bounded rollback period |
| autostart | rollback-only | Per-user scheduled tasks retained with the Komorebi rollback path |

Component-specific installation, update, rollback, and recovery instructions
live under `windows/<component>/README.md`. A component README is authoritative
for its deployed paths and host-runtime verification. The table above is a
human-readable summary derived from `windows/components.json`; the catalog is
the only authoritative source for lifecycle and selection policy.

`windows/components.json` is the machine-readable lifecycle and entrypoint
catalog. The root `windows/install.ps1` validates that catalog, resolves a
deterministic plan, preflights every selected entrypoint, and then runs the
existing component installers sequentially. Its default plan contains only
the required WezTerm and Kanata components; select GlazeWM explicitly when a
window-manager deployment is intended.

The WSL bootstrap resolves that selection once and applies it through a single
PowerShell 7 orchestrator invocation. It uses scalar CSV parameters because
native `pwsh -File` callers cannot bind an array-valued script parameter. The
wrapper validates and converts the comma-separated lower-case names before
calling the orchestrator module. Windows PowerShell 5.1 remains a supported
compatibility and component-runtime target.

PowerShell 7 is therefore a WSL bootstrap prerequisite. Install it on the
Windows host with WinGet before running the full bootstrap:

```powershell
winget install --id Microsoft.PowerShell --source winget --installer-type wix
```

After dry-run planning, the bootstrap performs an early Windows `-Preflight`
before container validation, package upgrades, or other mutations.
Unlike pure `-PlanOnly`, `-Preflight` also checks the Windows host, selection
policy, running processes, startup registrations, and scheduled-task probes
without invoking component entrypoints.
The later apply remains a separate single orchestrator invocation. Required
components and their order are read from `windows/components.json`; the Bash
bridge passes only the optional window-manager addition.

From a PowerShell prompt at the repository root, inspect a plan before applying
it:

```powershell
& .\windows\install.ps1 -ListComponents
& .\windows\install.ps1 -PlanOnly
& .\windows\install.ps1 `
  -Component @("wezterm", "kanata", "glazewm") `
  -PlanOnly

# Apply the reviewed plan.
& .\windows\install.ps1 `
  -Component @("wezterm", "kanata", "glazewm")
```

Zebar and audio remain managed dependencies and cannot be selected directly.
Komorebi and standalone autostart require both explicit selection and
`-AllowRollbackOnly`; conflicting active and rollback paths fail before any
component runs. The root script is not a cross-component transaction: it stops
at the first failure and preserves each component installer's own rollback and
recovery contract. Use the component-specific CLI for advanced arguments.

Windows host values can use ignored `*.local.json` files. For example,
`windows/komorebi/audio-output.local.json` overrides the generic checked-in
audio device patterns during install and update.

## Validation

The default check is intentionally portable: it covers repository shell tests,
shell lint, Lua/JSON syntax, and the public-tree security boundary. It does not
run the Zebar toolchain, Windows Pester suites, or host-runtime checks.

```bash
mise run check
mise run check:zebar
mise run check:windows
mise run check:windows-compat
mise run check:all-local

# Or run the repository tests without mise-managed audit tools:
for test_file in scripts/tests/*.test.sh; do "$test_file"; done
scripts/security/check-public-tree.sh
```

| Task | Boundary | Requirements |
| --- | --- | --- |
| `mise run check` | Portable repository tests, lint, config syntax, and security | Bootstrapped Linux/WSL checkout with `bash`, Git, jq, ripgrep, Stow, Zsh, and mise |
| `mise run check:zebar` | Lockfile install, Zebar tests, type checking, production build, and tracked `dist/` drift check | mise-managed Node toolchain and npm registry access |
| `mise run check:windows` | All Windows Pester suites under PowerShell 7 | Windows bridge and Pester 5.7.1 |
| `mise run check:windows-compat` | The same suites under Windows PowerShell 5.1 | Windows bridge and Pester 5.7.1 |
| `mise run check:all-local` | All four source-verification boundaries above | Every prerequisite in the rows above |

PowerShell 7 is the primary Windows validation runtime; Windows PowerShell 5.1
remains a compatibility target because deployed hotkeys and helpers still use
`powershell.exe`. CI runs each boundary independently. Host-runtime checks such
as process lifecycle, window preservation, scheduled tasks, font resolution,
and actual configuration loading remain explicit post-deployment checks and
are not implied by any source-verification task.

The public boundary check rejects credential filenames, private assistant
state, personal home paths, common personal email addresses, and symlinks that
escape the repository. An optional private denylist can be supplied through
`DOTFILES_DENYLIST` for host-specific names and identifiers.
