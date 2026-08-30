# Windows monitor profiles

This component installs the pinned DisplayConfig PowerShell module under
`%LOCALAPPDATA%\dotfiles\monitor-profiles` and manages three machine-local
profiles:

- `all`: left, center, and right displays; the center 4K display is primary.
- `left-center`: left and center displays; the center 4K display is primary.
- `right-only`: only the right display; that display is primary.

The first installation must run while all three displays are active and arranged
as follows:

```text
left  1920x1080 at (-1920, 495)
center 3840x2160 at (0, 0), primary
right 1920x1080 at (3840, 430)
```

The installer captures EDID serial numbers and generates complete CCD topology
profiles. Machine-specific monitor identifiers and generated profile files stay
under LocalAppData and are not tracked in this repository.

Install or update it from WSL through the Windows component orchestrator:

```bash
./install.sh --with-monitor-profiles
```

It can be combined with GlazeWM on the managed three-display workstation:

```bash
./install.sh --with-monitor-profiles
```

GlazeWM is part of the default WSL bootstrap. To install only the monitor
profiles without GlazeWM, add `--without-glazewm`.

Or invoke only the Windows component directly:

```bash
/init /mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe \
  -NoProfile -ExecutionPolicy Bypass \
  -File "$(wslpath -w "$PWD/windows/install.ps1")" \
  -Mode Install -Component monitor-profiles
```

Validate a profile without changing the desktop:

```powershell
& "$env:LOCALAPPDATA\dotfiles\monitor-profiles\Switch-MonitorProfile.ps1" `
  -Name all -ValidateOnly
```

Apply a profile:

```powershell
& "$env:LOCALAPPDATA\dotfiles\monitor-profiles\Switch-MonitorProfile.ps1" `
  -Name right-only
```

Profiles are applied from PowerShell with the commands above. After a verified
apply or explicit recovery, an installed GlazeWM runtime is synchronized:
workspaces 1 through 12 return to the Windows primary display, `left` and
`vert` follow the active outer displays, and the existing primary Zebar preset
is preserved when it still reserves the primary display. GlazeWM is reloaded
once when its monitor topology is stale and can take up to 30 seconds to
observe a display removal. A missing primary reservation triggers an orderly
AppBar position refresh on the existing Zebar window, followed by verification
that the primary work area again reserves 42 px. A widget relaunch is only a
fallback and requires the explicit `-AllowZebarWidgetRelaunch` switch after user
approval. The Zebar runtime is never force-stopped during a profile change
because Zebar 3.3.1 can leave port 6124 orphaned after process exit. If that
desktop refresh fails, the already verified Windows display profile remains
applied and the command reports the refresh error instead of silently hiding it.

Every switch validates the saved topology with Windows, captures the current
configuration, applies without persistence, verifies active displays, primary,
positions, and resolutions by EDID serial, then persists the verified result.
An apply failure automatically restores the captured configuration.

Explicitly restore the configuration captured before the most recent switch:

```powershell
& "$env:LOCALAPPDATA\dotfiles\monitor-profiles\Switch-MonitorProfile.ps1" `
  -Recover
```

The dependency is pinned by version and SHA-256. It is installed locally rather
than into a global PowerShell module path, and it is never updated implicitly.
