# Kanata on Windows from WSL

Kanata runs on the Windows side. The installer pins an official Kanata release,
verifies the published SHA-256 digest, and registers Kanata in the current
user's `Run` registry key.

Microsoft Defender may quarantine the unsigned Kanata binary. Defender changes
are opt-in. To allow only the final `kanata.exe` path while running the main
dotfiles installer:

```bash
KANATA_ADD_DEFENDER_EXCLUSION=1 ./install.sh
```

The UAC prompt applies only the exact
`%LOCALAPPDATA%\kanata\kanata.exe` exclusion. The download, configuration copy,
registry update, and Kanata process run with normal user privileges.

## Key behavior

- Configure the two physical keys beside Space in the keyboard firmware: the
  left key must emit `F13`, and the right key must emit `F15`.
- Tap `F13` for IME off or `F15` for IME on. Hold either key to activate the
  GlazeWM shortcut layer.
- Left/Right Win and Left/Right Alt remain native Windows keys.
- Tap Space for Space, or hold it to activate the navigation layer.
- `Space+Q` sends Escape and then turns the IME off.

| Shortcut | Action |
| --- | --- |
| `F13/F15+H/J/K/L` | Focus the GlazeWM window left/down/up/right |
| `F13/F15+Ctrl+H/J/K/L` | Move the focused window; keep the mods held to repeat |
| `F13/F15+1..0,-,=` | Focus workspace 1..12 |
| Add `Shift` to a workspace binding | Move and follow the active window |
| `F13/F15+Q` | Close the active window |
| `F13/F15+M` | Switch to the next configured audio output |
| `F13/F15+Tab` | Switch windows with `Alt+Tab` |
| `F13/F15+Space` | Open the launcher bound to `Alt+Space` |
| `F13/F15+F / Shift+F` | Toggle floating/fullscreen |
| `F13/F15+Shift+A` | Enable all managed displays |
| `F13/F15+Shift+C` | Enable the left and center displays |
| `F13/F15+Shift+R` | Enable only the right display |

The firmware mapping is outside this repository. Kanata can validate and use
`F13`/`F15`, but it cannot make a different hardware scancode become those
keys without adding that original key to `defsrc`.

## Game mode

The installer starts a user-level watcher alongside Kanata. Kanata listens only
on loopback TCP port `5829`, and the watcher presses or releases its private
`game-mode` virtual key when a detected game gains or loses foreground focus.
Kanata is not restarted on focus changes, which prevents synthesized modifiers
from being left pressed during a profile restart.

While game mode is active, Space is a plain Space key: holding it does not open
the navigation layer, so `Space+Q` and the other Space-layer shortcuts are
disabled. The physical `F13`/`F15` keys still provide IME Off/On on tap and the
full GlazeWM shortcut layer on hold. Native Win and Alt remain unchanged.

Every executable under a detected Steam `steamapps\common` directory is
detected. Executable-name fallbacks cover Street Fighter 6, Satisfactory,
Shadowverse: Worlds Beyond, Aimlabs, Valorant, Genshin Impact, Honkai: Star Rail,
and Escape from Tarkov when a process path cannot be read. Because
`disable_only_when_game_foreground` is `true`, the game profile is active only
while a detected game's window owns the foreground. The normal profile returns
750 ms after focus leaves the game. The watcher
polls four times per second, runs without administrator privileges, and replaces
the direct Kanata login entry.

Long-running Steam utilities can be excluded with `steam_ignore_executables`.
Wallpaper Engine's renderer, service, UI, web wallpaper, and application
injection processes are excluded by default so they do not keep the game
profile active after a game exits.

Entire Steam application directories can be excluded with
`steam_ignore_directories`. The default `wallpaper_engine` entry also covers
helper executables such as `winrtutil64.exe`, while Steam itself remains
outside `steamapps\common` and is never classified as a game.

Kanata remains active while games are running, and compatibility with every
anti-cheat system is not guaranteed.
Follow each game's anti-cheat policy; driver and input-tool restrictions may
change independently of this configuration.

To install Kanata directly from WSL:

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass \
  -File "$(wslpath -w "$PWD/windows/kanata/install.ps1")" \
  -AddDefenderExclusion
```

`uninstall.ps1` removes the Defender exclusion only when the install metadata
records that this installer created it. Use `-KeepDefenderExclusion` to preserve
an installer-owned exclusion during uninstall.
