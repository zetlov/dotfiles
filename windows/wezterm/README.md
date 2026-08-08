# WezTerm configuration

The managed configuration lives in `.config/wezterm/wezterm.lua`. GNU Stow
links that file into the Linux home directory. Windows uses a copied deployment
because loading a config through a WSL UNC path would make WezTerm startup
depend on the WSL distribution that it may need to launch.

The initial appearance matches the version-controlled Kitty baseline:
JetBrainsMono Nerd Font at 13 pt, Catppuccin Mocha, 70% background opacity,
zero padding, a steady bar cursor, a bottom tab bar, and no title bar. Windows
Acrylic blur is intentionally disabled so unfocused windows retain the same
background opacity. Zsh switches the cursor to a steady block in vi command
mode and back to a bar in insert mode. New windows open in the `archlinux` WSL
domain by default. On Arch,
Zetshell can override Kitty colors with a generated host-local theme. That file
is not currently present and is not loaded by the Windows WezTerm config;
dynamic theme synchronization can be added separately.

Japanese glyphs use `Noto Sans Mono CJK JP`, matching the monospace fallback
configured for Arch. `install.ps1` installs the required Windows user fonts and
deploys the managed config. It installs these faces only when their Windows
font registrations are missing:

- JetBrains Mono Nerd Font Regular, Bold, Italic, and Bold Italic
- Noto Sans Mono CJK JP Regular and Bold

The installer downloads pinned official archives for Nerd Fonts 3.5.0 and Noto
Sans CJK 2.004, verifies their SHA-256 hashes, and copies only the listed font
files into `%LOCALAPPDATA%\Microsoft\Windows\Fonts`. It registers them under
`HKCU`, so it does not require administrator privileges. Existing valid user or
system registrations are preserved. The WSL branch of the repository-level
`install.sh` runs this setup automatically.

The Kitty keyboard protocol remains disabled because the installed Windows
WezTerm version disrupts Shift and IME confirmation input when it is enabled.
The Codex keymap keeps Enter for submission. WezTerm maps only Shift+Enter to
Ctrl+J, which Codex uses for newlines without changing other Shift or IME input.

Install missing fonts and deploy the managed config to
`%USERPROFILE%\.config\wezterm\wezterm.lua` from WSL:

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass \
  -File "$(wslpath -w "$PWD/windows/wezterm/install.ps1")"
```

Exit all WezTerm windows and start WezTerm again after the script installs any
font so DirectWrite refreshes its font list. A second run skips registered
fonts and returns `Changed=False` for an unchanged config.

To deploy only the managed config without checking fonts, run:

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass \
  -File "$(wslpath -w "$PWD/windows/wezterm/update-config.ps1")"
```

The update is idempotent. If the destination differs, the script saves the
previous file beside it with a `.before-update-<timestamp>` suffix before
replacing it.

Run setup and updates as the normal Windows user, not from an elevated shell.
WezTerm configuration is executable Lua and backups are retained, so do not
store secrets in the config.

Validate the deployed config with the installed WezTerm executable:

```powershell
& "$env:ProgramFiles\WezTerm\wezterm.exe" `
  --config-file "$env:USERPROFILE\.config\wezterm\wezterm.lua" `
  show-keys --lua
```

Confirm the resolved Japanese fallback with:

```powershell
& "$env:ProgramFiles\WezTerm\wezterm.exe" `
  --config-file "$env:USERPROFILE\.config\wezterm\wezterm.lua" `
  ls-fonts --text "日本語"

& "$env:ProgramFiles\WezTerm\wezterm.exe" `
  --config-file "$env:USERPROFILE\.config\wezterm\wezterm.lua" `
  ls-fonts | Select-String "Noto Sans Mono CJK JP|NotoSansMonoCJKjp-Bold.otf"
```

The first command should resolve each Japanese glyph to the
`Noto Sans Mono CJK JP` family using `NotoSansMonoCJKjp-Regular.otf`. The
second command should also list `NotoSansMonoCJKjp-Bold.otf` for the bold font
rule.
