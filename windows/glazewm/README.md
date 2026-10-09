# GlazeWM

This directory installs and manages the Windows GlazeWM configuration. It
uses the official `glzr-io.glazewm` WinGet package pinned to 3.10.1 and a
small PowerShell automatic-tiling helper that follows the same width/height policy as
GlazeTiler. The helper uses only GlazeWM's local IPC CLI.

## Install

From WSL:

```bash
./install.sh
```

For the managed Surface profile:

```bash
./install.sh --windows-device-profile=surface
```

This explicit profile keeps workspaces 1 through 5 alive on the built-in
panel. Workspaces 6 through 12 remain dynamic; one attached external display
activates workspace 6, while workspaces 7 through 12 are never moved by the
topology synchronizer. `left`, `vert`, workstation startup applications, and
monitor-profile controls are omitted. More than one external display fails
closed.

If Zebar is already running with the desktop pack, perform the first switch
with `--allow-zebar-runtime-stop`. Reapplying an unchanged Surface pack does
not need that authorization.

The Surface watcher coalesces Windows display-change events for 1.5 seconds.
It identifies the built-in panel through DisplayConfig output technology, so a
portrait rotation does not change workspace ownership. It updates GlazeWM
bindings without restarting GlazeWM or Zebar, then refreshes the existing
Surface bar's AppBar reservation against the internal-panel rectangle.

Add `--with-monitor-profiles` only on the machine with the managed three-display
topology. Zebar hides its monitor-profile selector when that component is not
installed. Use `--without-glazewm` when the WSL bootstrap should omit both
GlazeWM and its managed Zebar bar.

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

For a configuration-only update that must not install, validate, stop, start,
or relaunch Zebar, use an already-running GlazeWM manager:

```bash
pwsh.exe -NoProfile -ExecutionPolicy Bypass \
  -File "$(wslpath -w ~/dotfiles/windows/glazewm/install.ps1)" \
  -PreserveZebarRuntime \
  -SkipStartupApps
```

`-SkipStartupApps` is limited to this live, runtime-preserving update mode. It
keeps current application workspace placement unchanged while the installer
reloads the managed config and reconciles workspace monitors.

The installer deploys the configuration to `%USERPROFILE%\.glzr\glazewm`,
deploys helper scripts under `%LOCALAPPDATA%\dotfiles\glazewm`, registers the
official manager in the current user's Run key, and reloads an existing manager
or starts it when absent. Existing live configuration is timestamp-backed up
before replacement. GlazeWM may show a UAC prompt when it starts.

The managed configuration keeps the Komorebi-era 8 px inner gaps, 10 px outer
gaps, Catppuccin borders, opaque windows, keyboard focus, twelve primary
workspaces, and auxiliary `left` and `vert` workspaces. Registered games are
moved to workspace 11 and made non-centered floating windows.

## Automatic layout

The helper listens for focus, move, window-managed, and workspace-updated
events. It also reconciles the game workspaces once before waiting for the
first event. A wider focused tile sets a horizontal next insertion and a taller tile sets a
vertical next insertion. On the tested GlazeWM 3.10.1 runtime this reproduces
the important dwindle sequence: a tall tile splits top/bottom, then the wide
bottom tile splits left/right. Closing a window may temporarily leave a
single-child split; restarting GlazeWM rebuilds a clean tree.

The same helper reconciles every tiling window in workspace 11 to
non-centered floating. This includes unfocused windows and windows that were
already present when the helper started. Fullscreen and already-floating
windows are left unchanged.

## Bar

The installer deploys the custom `windows/zebar` widget pack and GlazeWM starts
its `primary-monitor` preset. It is a Windows adaptation of the Arch Zetshell bar:
42 px glass rail, workspace buttons, media, tray, CPU/GPU/RAM, network, volume, and
a centered clock with seconds. See `windows/zebar/README.md` for build and
provider details.

GlazeWM does not use static monitor indexes. At startup and after every managed
display-profile change, the synchronization helper waits until GlazeWM sees the
same display bounds as Windows, then routes workspaces 1 through 12 to the
Windows primary display, `left` to the leftmost display, and `vert` to the
rightmost display. All managed workspaces remain active when empty, so a
numeric workspace cannot be destroyed and recreated on whichever monitor was
focused later. The synchronization pass activates every managed workspace
before assigning live monitor bindings and routing it, including workspaces
that were inactive before a config reload. The base config intentionally omits
topology-specific bindings so every keep-alive workspace can be created when a
reduced display profile is active. With fewer displays, auxiliary workspaces
collapse onto the available edge or the sole primary display. Zebar is ensured
before workspace reconciliation so a routing error cannot suppress the bar.
An existing Zebar process is kept
alive across profile changes to avoid Zebar 3.3.1's orphaned-port bug. The
helper verifies the visible managed bar, live listener ownership, and the 42 px
primary-display top reservation. If a display-profile change clears the Windows
work area while the bar remains healthy and correctly positioned, the helper
reasserts `ABM_QUERYPOS` and `ABM_SETPOS` on the existing bar window. It verifies
the live primary work area and requires the Shell-approved rectangle to match the
actual widget rectangle. It never closes a stale widget unless the caller
supplies `-AllowZebarWidgetRelaunch`. The managed monitor-profile switch
supplies this flag when a widget rectangle still belongs to the previous
primary display. It orderly recreates only that widget from the
`primary-monitor` preset while preserving the healthy Zebar process and its
asset-server listener.
Replacing a widget pack while Zebar is running likewise requires the explicit
`-AllowRuntimeStop` installer switch.

## Application workspaces

- Workspace 1 at login: Zen Browser (Personal profile)
- Workspace 2: Discord and Spotify
- Workspace 3: Todoist and Notion Calendar
- Workspace 4: Obsidian and Notion
- Workspace 7: Zen Browser (MadoriLABO profile) and Slack
- Workspace 9: Zen Browser (University profile) and Zotero
- Workspace 11: registered games, floating and not centered

The startup helper launches only missing applications and places each listed
application on its corresponding workspace. Zen is launched three times with
the named Firefox-compatible profiles. None of these startup applications has
a persistent window rule, so windows and dialogs opened later stay on the
currently active workspace. Persistent GlazeWM routing is reserved for games.

After startup placement and workspace-grid reconciliation finish, the same
helper reruns workspace-to-monitor synchronization without invoking Zebar.
This final pass prevents a numeric workspace created during startup from
remaining on whichever monitor happened to be focused during app placement.

## Key bindings

Kanata translates either held physical `F13`/`F15` key to the private bindings
below. Native Win and Alt are not used as GlazeWM modifiers.

| Physical binding | Action |
| --- | --- |
| `F13/F15+H/J/K/L` | Focus left/down/up/right |
| `F13/F15+Ctrl+H/J/K/L` | Move the focused window; keep the mods held to repeat |
| `F13/F15+1..0` | Focus workspace 1..10 |
| `F13/F15+-/=` | Focus workspace 11/12 |
| Add `Shift` to a workspace binding | Move and follow the window |
| `F13/F15+Enter` | Start WezTerm directly through `wezterm-gui` |
| `F13/F15+B` | Start Zen Browser |
| `F13/F15+F` | Toggle floating |
| `F13/F15+Shift+F` | Toggle fullscreen |
| `F13/F15+Arrow` | Resize the focused tile |
| `F13/F15+M` | Cycle audio outputs and show the selected device |
| `F13/F15+,` / `/` / `.` | Focus left/primary/right monitor index |
| `F13/F15+Shift+A` | Enable all three displays |
| `F13/F15+Shift+C` | Enable the left and center displays |
| `F13/F15+Shift+R` | Enable only the right display |

Monitor navigation only changes the focused monitor. Physical Ctrl does not
change this action, and the shifted fallback bindings also focus a monitor
instead of moving the current workspace. This preserves the invariant that
numeric workspaces 1 through 12 stay on the primary monitor.

The synchronization helper first activates all keep-alive workspaces, then
assigns live bindings for the current topology. Numeric workspaces bind to the
current primary display; `left` and `vert` bind to their active outer displays
or collapse onto primary in a reduced profile. This avoids referring to a
missing monitor while GlazeWM is still creating startup workspaces and prevents
an empty reconnected monitor from rejecting `move-workspace` with
`No displayed workspace`.

The managed profile switch changes live bindings before DisplayConfig disables
a monitor. A named mutex serializes profile switches, and an unreachable
GlazeWM IPC endpoint aborts before Windows display state changes. Expanding from
`right-only` takes a separate fail-closed path: it snapshots workspace and
window state by HWND, verifies every window is shell-uncloaked, exits GlazeWM
gracefully, applies the display profile, restarts the manager, and restores the
snapshot after directly synchronizing the new monitor topology. The restarted
manager defers its normal startup-app placement once by consuming a one-time
token. This avoids exposing GlazeWM 3.10.1 to an empty newly enabled monitor or
letting startup placement overwrite the snapshot. Any uncloak verification
failure leaves the manager running and prevents DisplayConfig changes.

## Safe recovery

Do not terminate or force-stop GlazeWM while it uses `hide_method: cloak`.
Stopping the manager first can leave application windows shell-cloaked and
absent from ordinary window enumeration. Use this order:

1. If IPC responds, run `wm-reload-config`, then the managed monitor sync.
2. If IPC does not respond, leave the manager running and restore every
   shell-cloaked application view with `IApplicationView.SetCloak(Default, 0)`.
3. Verify with `DwmGetWindowAttribute(DWMWA_CLOAKED)` that every recovered
   application window reports zero.
4. Only after that verification may the manager be restarted from its tray UI
   or by signing out and back in.
5. Run `Start-GlazeWorkspaceApps.ps1` to register surviving windows and restore
   the configured workspace placement. It launches only applications that are
   still missing.

If step 2 or 3 fails for any window, stop the recovery and keep GlazeWM alive.
Never use `Stop-Process -Force`, `taskkill /F`, or `wm-exit` as the first repair
step.

## Rollback

Komorebi's repository configuration and disabled Startup shortcut are kept as
rollback material. Before returning to Komorebi, first close application
windows normally or complete the safe recovery procedure above. Then exit
GlazeWM from its tray menu and remove its autostart entry:

```powershell
Remove-ItemProperty `
  "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" `
  -Name "GlazeWM"
```

Then restore the preserved Komorebi shortcut only if returning to Komorebi.
