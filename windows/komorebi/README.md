# Komorebi

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

Or run only the Windows setup:

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass \
  -File "$(wslpath -w ~/dotfiles/windows/komorebi/install.ps1)"
```

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
| `Super+M` | `Ctrl+Alt+M` | Cycle the configured audio outputs |
| `Super+,/.` | `Ctrl+Alt+,/.` | Focus previous/next monitor |
| `Super+Ctrl+,/.` | `Ctrl+Alt+Shift+,/.` | Move window to previous/next monitor |
| `Super+Arrow keys` | `Ctrl+Alt+Arrow keys` | Resize the focused tile |

Raw `Ctrl+Alt` bindings for monitor moves, configuration reload, layout
cycling, promotion, and pausing whkd remain available as Windows-only
fallbacks. Hyprland bindings backed by Linux-only tools, such as Quickshell,
Rofi, and Hyprland's special workspace, are not reproduced. Workspace 12 on
`Super+=` is the closest non-toggle replacement for the special workspace.
Window transparency is disabled on every workspace.

## Update

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass \
  -File "$(wslpath -w ~/dotfiles/windows/komorebi/update-config.ps1)"
```

Use `-Force` only when the deployed config was intentionally edited and should
be backed up and replaced.

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
