# Zetshell Zebar

This widget pack adapts the Arch Zetshell Quickshell bar for Windows and
GlazeWM. It uses Zebar's official providers and a bundled SolidJS application,
so the running bar does not load JavaScript from a CDN.

The first version includes:

- GlazeWM workspaces with click-to-focus actions
- a truly centered two-tier date and `HH:mm:ss` clock
- Windows media controls with Lucide icons and playback progress
- system tray icons and native context menus
- CPU and memory usage plus NVIDIA GPU usage and core temperature
- network status and SSID
- output volume with click-to-mute and mouse-wheel adjustment
- three floating 42 px glass islands inspired by the Arch bar, macOS, and
  Seelen UI

Arch-specific package updates and the Quickshell notification center are not
shown. They do not have equivalent Zebar providers.

## Build

Runtime versions are managed by mise. Build and test the static widget assets
from WSL:

```bash
cd windows/zebar
npm ci
mise run check
```

The lockfile pins the dependency graph. The generated `dist/` directory is
tracked because Windows only needs Zebar and the static bundle at runtime.

## Deployment

`windows/glazewm/install.ps1` calls `windows/zebar/install.ps1`, which installs
the official `glzr-io.zebar` 3.3.1 WinGet package when needed and transactionally
deploys the pack to `%USERPROFILE%\.glzr\zebar\zetshell`. GlazeWM then opens the
`primary-monitor` preset during startup. The preset docks a 42 px bar to the top
edge of the primary monitor and reserves that work area. GPU utilization and
core temperature come from one persistent, argument-restricted `nvidia-smi`
process. Before replacing Zebar, the installer stops the current exact managed
process and its utilization-only predecessor so neither can retain the local
asset-server socket across deployment. Installation succeeds only after the
responding `zetshell / bar` widget window is present.
