# Zetshell Zebar

> Status: active shared component managed by the GlazeWM installer.

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

The GlazeWM installer calls `windows/zebar/install.ps1` and starts the
`primary-monitor` preset. The preset docks a 42 px bar to the top
edge of the primary monitor and reserves that work area. Its normal z-order
keeps the reserved bar visible beside ordinary windows while allowing a
fullscreen window to cover it. GPU utilization and core temperature come from
one persistent, argument-restricted `nvidia-smi` process. Before replacing
Zebar assets, the installer stops the current exact managed process and its
utilization-only predecessor. Installation succeeds only after the responding
`zetshell / bar` widget window is present. Monitor-profile changes preserve a
responding bar because Zebar 3.3.1 can orphan its local asset-server socket
during an otherwise normal restart. If port 6124 is already orphaned, monitor
sync keeps an existing reserved bar running and refuses a new start with an
explicit sign-out or reboot requirement.
