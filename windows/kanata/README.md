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

- Swap the physical Left Win and Left Alt keycaps.
- The original Left Alt position becomes Left Super: tap for IME off, or hold
  it to activate the dedicated window-manager shortcut layer.
- `Left Super+Space` from that position emits the native Windows `Alt+Space`
  shortcut.
- `Left Super+S` emits the native Windows `Win+Shift+S` shortcut for selecting
  a screenshot region.
- `Left Super+P` emits the standard media Play/Pause key.
- The original Left Win position becomes a normal Left Alt key.
- Tap Right Alt to turn the IME on, or hold it as a normal Alt key.
- Right Super remains a native Windows key for shortcuts such as `Win+E` and
  `Win+L`.
- Tap Space for Space, or hold it to activate the navigation layer.
- `Space+Q` sends Escape and then turns the IME off.

The dual-role keys use `tap-hold-press`, so pressing another key selects the
hold action immediately rather than waiting for the hold timeout. The
window-manager layer emits complete `Ctrl+Alt` output chords only for configured
shortcuts and blocks other keys. Because the Left Super keycap now uses the
physical Left Alt scan code, reserved shortcuts such as `Win+L` never reach
Windows.

## Game mode

The installer starts a user-level watcher alongside Kanata. By default, Kanata
is stopped completely only while the foreground window belongs to an
executable under a detected Steam `steamapps\common` directory. It starts again
750 ms after focus leaves the game, which avoids restart churn during brief
focus changes. Explicit executable-name fallbacks cover Street Fighter 6,
Satisfactory, Shadowverse: Worlds Beyond, and Aimlabs when a process path
cannot be read.

Valorant is also detected by executable name in `game-mode.json`. Add other
non-Steam games to `hard_off_executables` using executable file names only. Set
`disable_only_when_game_foreground` to `false` to keep Kanata disabled for the
entire game process lifetime. The watcher polls four times per second, runs
without administrator privileges, and replaces the direct Kanata login entry.

Long-running Steam utilities can be excluded with `steam_ignore_executables`.
Wallpaper Engine's renderer, service, UI, web wallpaper, and application
injection processes are excluded by default so they do not keep Kanata
disabled after a game exits.

Entire Steam application directories can be excluded with
`steam_ignore_directories`. The default `wallpaper_engine` entry also covers
helper executables such as `winrtutil64.exe`, while Steam itself remains
outside `steamapps\common` and is never classified as a game.

Stopping the user-mode Kanata process avoids remapping while a detected game is
focused, but it does not guarantee compatibility with every anti-cheat system.
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
