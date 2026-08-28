# Komorebi

> Status: inactive rollback configuration. GlazeWM is the active window
> manager. Keep this directory only for a bounded rollback period.

This directory installs and manages Komorebi on the Windows side of WSL. The
runtime configuration is copied to `%USERPROFILE%\.config\komorebi`; startup
does not depend on the WSL distribution being available.

The configuration mirrors the active Hyprland setup where Windows allows it:

- BSP layout as the closest equivalent to Hyprland dwindle
- 8 px container gaps, 10 px workspace gaps, and 3 px borders
- twelve named workspaces on the primary monitor and `vert` on the secondary
- untiled floating game workspaces on 11 and 12
- Vim-style focus and move bindings
- keyboard-directed focus without focus-follows-mouse
- a 42 px Catppuccin bar on the primary monitor
- 160 ms window movement animations using Hyprland's EaseOutQuint curve
- initial app routing for managed login apps plus Tana, Vesktop, and Slack
- Catppuccin Mocha borders with opaque windows

Komorebi and whkd permit personal use. Work or other commercial use requires
the appropriate upstream license.

## Install

From WSL:

```bash
./install.sh --with-komorebi
```

This explicit rollback selection replaces the default GlazeWM component for
that bootstrap run.

Or run only the Windows setup through the root orchestrator:

```bash
pwsh.exe -NoProfile -ExecutionPolicy Bypass \
  -File "$(wslpath -w ~/dotfiles/windows/install.ps1)" \
  -Mode Install -Component komorebi -AllowRollbackOnly
```

The root Windows installer requires both the explicit `komorebi` component
selection and `-AllowRollbackOnly`. It refuses to activate this rollback path
while GlazeWM is running or registered for automatic startup. Directly running
`windows/komorebi/install.ps1` is an internal/advanced entrypoint; it enforces
the same GlazeWM inactivity guard before making any component changes.

The installer uses the official WinGet packages `LGUG2Z.komorebi`,
`LGUG2Z.whkd`, and `LGUG2Z.masir`. It also installs the pinned
`AudioDeviceCmdlets` 3.1.0.2 module from PowerShell Gallery for default audio
output switching. It validates the config, starts Komorebi, whkd, Komorebi
Bar, and enables the official Komorebi autostart shortcut. Masir remains
installed for an easy future opt-in, but it is not started because pointer
events can override keyboard-directed focus. The primary-monitor bar shows
workspaces, layout, the focused window, media, system usage, network activity,
keyboard state, date, time, and the system tray. The installer refuses to
overwrite config files modified outside this repository. Use `-ForceConfig`
to make a timestamped backup and replace them. The upstream
`applications.json` database is fetched only when missing, so local changes
are preserved on repeat installs.

## Key bindings

`Ctrl+Alt` is used internally because many `Win` combinations are reserved by
Windows. After swapping the Left Win and Left Alt keycaps, a held Left Super
(the original Left Alt scan code) activates a Kanata layer that emits complete
`Ctrl+Alt` chords for the configured shortcuts. This matches the `Super`-based
Hyprland setup without generating reserved shortcuts such as `Win+L`. The
original Left Win position becomes a normal Left Alt key. Raw `Ctrl+Alt`
bindings remain available as a fallback. Tap Left Super for IME off, or tap
Right Alt for IME on. Right Super remains available for native Windows
shortcuts.

| Physical binding | Raw whkd binding | Action |
| --- | --- | --- |
| `Super+H/J/K/L` | `Ctrl+Alt+H/J/K/L` | Focus left/down/up/right |
| `Super+Ctrl+H/J/K/L` | `Ctrl+Alt+Shift+H/J/K/L` | Move window left/down/up/right |
| `Super+1..0` | `Ctrl+Alt+1..0` | Focus workspace 1..10 |
| `Super+-/=` | `Ctrl+Alt+-/=` | Focus floating game workspace 11/12 |
| Add `Shift` to a workspace binding | Add `Shift` | Move window to that workspace |
| `Super+F` | `Ctrl+Alt+F` | Toggle floating |
| `Super+Shift+F` | `Ctrl+Alt+Shift+F` | Toggle monocle |
| `Super+Shift+J` | `Ctrl+Alt+Shift+;` | Cycle layout |
| `Super+,/.` | `Ctrl+Alt+,/.` | Focus previous/next monitor |
| `Super+Ctrl+,/.` | `Ctrl+Alt+Shift+,/.` | Move window to previous/next monitor |
| `Super+Arrow keys` | `Ctrl+Alt+Arrow keys` | Resize the focused tile |

Audio switching remains owned by the active audio component on held
`F13/F15+M`; whkd intentionally has no competing audio binding.

Raw `Ctrl+Alt` bindings for monitor moves, configuration reload, layout
cycling, promotion, and pausing whkd remain available as Windows-only
fallbacks. Hyprland bindings backed by Linux-only tools, such as Quickshell,
Rofi, and Hyprland's special workspace, are not reproduced. Workspace 12 on
`Super+=` is the closest non-toggle replacement for the special workspace.
Window transparency is disabled on every workspace.

## Update

```bash
pwsh.exe -NoProfile -ExecutionPolicy Bypass \
  -File "$(wslpath -w ~/dotfiles/windows/install.ps1)" \
  -Mode Update -Component komorebi -AllowRollbackOnly
```

The normal update uses the root orchestrator and is permitted only when GlazeWM
is inactive and has no automatic startup registration. To preserve an
intentionally edited deployed config by backing it up before replacement, the
internal/advanced direct entrypoint still accepts `-Force` and enforces the
same guard:

```bash
pwsh.exe -NoProfile -ExecutionPolicy Bypass \
  -File "$(wslpath -w ~/dotfiles/windows/komorebi/update-config.ps1)" -Force
```

Configuration updates use the guarded restart path because Komorebi's
`replace-configuration` rebuilds workspace state and can move windows without
an initial rule back to workspace 1. Manual restart is also a guarded
rollback-only operation: use the deployed script only after disabling GlazeWM
and its automatic startup registration, instead of killing `komorebi.exe`:

```bash
pwsh.exe -NoProfile -ExecutionPolicy Bypass \
  -Command '& "$env:KOMOREBI_CONFIG_HOME\restart.ps1"'
```

The deployed script fails closed if it cannot verify that GlazeWM is inactive,
then snapshots the current Komorebi state, waits for a graceful stop, starts
without `--clean-state`, and verifies that the saved windows returned to their
monitor and workspace. A forced process kill can leave a stale state file and
cause existing windows to be discovered on workspace 1.

New windows use Komorebi's `Create` container behaviour. Komorebi inserts the
new container after the focused container, which is the closest automatic BSP
behaviour to Hyprland's dwindle layout. The two layouts are not identical:
Komorebi recomputes a Fibonacci BSP from container order, while Hyprland keeps a
recursive split tree. Use `Ctrl+Alt+Shift+Arrow` before opening a window to
preselect its insertion direction when the automatic BSP placement is not the
desired split.

## Recovery and removal

The immediate escape hatch is:

```powershell
komorebic stop --whkd --bar --masir
komorebic restore-windows
```

To stop Komorebi and disable autostart:

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass \
  -File "$(wslpath -w ~/dotfiles/windows/komorebi/uninstall.ps1)"
```

Config, environment variables, packages, and installer state are kept by
default. The removal switches are `-RemoveManagedConfig`,
`-RestoreEnvironment`, and `-RemovePackages`. User-modified config is never
removed automatically. `AudioDeviceCmdlets` is treated as a shared PowerShell
module and is not removed by this script.

## Notes

- Monitor indices are based on the Windows display order. If they drift after
  sleep or reconnect, inspect `komorebic monitor-information` and update the
  serial numbers in `display_index_preferences`.
- Browser PWAs are not routed by the broad `vivaldi.exe` identifier because
  that would send every PWA to the browser workspace. Add title-based rules
  after checking actual identifiers with `komorebic visible-windows`.
- To refresh the upstream compatibility database, back up any local edits and
  run `komorebic fetch-asc` explicitly; that upstream command replaces the
  existing `applications.json`.
- Komorebi 0.1.41 animates window movement. It does
  not provide Hyprland-equivalent workspace, window-open, or window-close
  animations.
- Komorebi does not reproduce Hyprland blur, rounded corners, gestures, or its
  special scratchpad workspace.
