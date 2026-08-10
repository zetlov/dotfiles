# GlazeWM

This directory installs and manages the Windows GlazeWM configuration. It
uses the official `glzr-io.glazewm` WinGet package pinned to 3.10.1 and a
small PowerShell automatic-tiling helper that follows the same width/height policy as
GlazeTiler. The helper uses only GlazeWM's local IPC CLI.

## Install

From WSL:

```bash
./install.sh --with-glazewm
```

Or run only the Windows setup through the root orchestrator:

```bash
pwsh.exe -NoProfile -ExecutionPolicy Bypass \
  -File "$(wslpath -w ~/dotfiles/windows/install.ps1)" \
  -Mode Install -Component glazewm
```

Directly running `windows/glazewm/install.ps1` is an internal/advanced
entrypoint. It enforces the same guard as the root orchestrator and refuses to
make changes while Komorebi, whkd, Komorebi Bar, or masir is running, the
Komorebi Startup shortcut exists, or rollback app scheduled tasks remain.

```bash
pwsh.exe -NoProfile -ExecutionPolicy Bypass \
  -File "$(wslpath -w ~/dotfiles/windows/glazewm/install.ps1)"
```

The installer deploys the configuration to `%USERPROFILE%\.glzr\glazewm`,
deploys helper scripts under `%LOCALAPPDATA%\dotfiles\glazewm`, registers the
official manager in the current user's Run key, and restarts GlazeWM. Existing
live configuration is timestamp-backed up before replacement. GlazeWM may
show a UAC prompt when it starts.

The managed configuration keeps the Komorebi-era 8 px inner gaps, 10 px outer
gaps, Catppuccin borders, opaque windows, keyboard focus, twelve primary
workspaces, and a secondary `vert` workspace. Workspace 11 and 12 use the
managed automatic-floating policy for games.

## Automatic layout

The helper listens for focus, move, window-managed, and workspace-updated
events. It also reconciles the game workspaces once before waiting for the
first event. A wider focused tile sets a horizontal next insertion and a taller tile sets a
vertical next insertion. On the tested GlazeWM 3.10.1 runtime this reproduces
the important dwindle sequence: a tall tile splits top/bottom, then the wide
bottom tile splits left/right. Closing a window may temporarily leave a
single-child split; restarting GlazeWM rebuilds a clean tree.

The same helper reconciles every tiling window in workspace 11 or 12 to
non-centered floating. This includes unfocused windows and windows that were
already present when the helper started. Fullscreen and already-floating
windows are left unchanged.

## Bar

The installer deploys the custom `windows/zebar` widget pack and GlazeWM starts
its `primary-monitor` preset. It is a Windows adaptation of the Arch Zetshell bar:
42 px glass rail, workspace buttons, media, tray, CPU/GPU/RAM, network, volume, and
a centered clock with seconds. See `windows/zebar/README.md` for build and
provider details.

## Application workspaces

- Workspace 1: Zen Browser
- Workspace 2: Zotero, Raindrop.io, Todoist, and Notion Calendar
- Workspace 3: Spotify and Discord
- Workspace 4: Obsidian

At startup, the four managed workspace 2 windows are converted from a single
horizontal row into two equal vertical pairs that fill the workspace. A hidden
workspace with a stale or unbalanced 2x2 tree is rebuilt from only those four
managed windows. The guarded conversion is skipped when the target window set
is incomplete, duplicated, unsafe, or already balanced.

The startup helper launches only missing applications through their exact
Start Apps entries. GlazeWM window rules perform the workspace routing.

## Key bindings

Kanata translates the physical Super layer to the `Ctrl+Alt` bindings below.

| Physical binding | Action |
| --- | --- |
| `Super+H/J/K/L` | Focus left/down/up/right |
| `Super+Ctrl+H/J/K/L` | Move the focused window |
| `Super+1..0` | Focus workspace 1..10 |
| `Super+-/=` | Focus workspace 11/12 |
| Add `Shift` to a workspace binding | Move and follow the window |
| `Super+Enter` | Start WezTerm directly through `wezterm-gui` |
| `Super+B` | Start Zen Browser |
| `Super+F` | Toggle floating |
| `Super+Shift+F` | Toggle fullscreen |
| `Super+Arrow` | Resize the focused tile |
| `Super+M` | Cycle audio outputs and show the selected device |
| `Super+,/.` | Focus the monitor to the left/right |

GlazeWM can move a whole workspace between monitors but does not expose the
same direct single-window monitor command as Komorebi. The shifted monitor
bindings therefore move the current workspace.

## Rollback

Komorebi's repository configuration and disabled Startup shortcut are kept as
rollback material. Stop GlazeWM with its tray menu or:

```powershell
& "$env:ProgramFiles\glzr.io\GlazeWM\cli\glazewm.exe" command wm-exit
Remove-ItemProperty `
  "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" `
  -Name "GlazeWM"
```

Then restore the preserved Komorebi shortcut only if returning to Komorebi.
