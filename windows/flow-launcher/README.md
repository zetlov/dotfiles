# Flow Launcher

Install Flow Launcher and apply the shared preferences from PowerShell:

```powershell
.\windows\install.ps1 -Component flow-launcher
```

Edit `windows/flow-launcher/settings.json`, then apply it:

```powershell
.\windows\install.ps1 -Mode Update -Component flow-launcher
```

The optional component uses the official `Flow-Launcher.Flow-Launcher` WinGet
package. An existing installation is reused. The launcher opens with `Alt+Space`,
uses the system language and Win11Light theme, and starts hidden at Windows login.

Only the preferences in `settings.json` are managed. They are merged into
`%APPDATA%\FlowLauncher\Settings\Settings.json`; other settings, plugin credentials,
and history stay on Windows. GUI changes to managed preferences are overwritten
on the next update; edit the repository file to keep those changes.

An update validates JSON first, closes Flow normally only when preferences change,
re-reads its saved settings, and
atomically replaces the settings file with a uniquely named `.bak` alongside it.
Flow is then started. Matching preferences are not rewritten or restarted.
Backups contain local settings and must not be committed. Portable installations
with a `UserData` directory are rejected by this roaming-settings installer.

Settings and startup behavior were checked against the official
[Flow Launcher v2.1.3 source](https://github.com/Flow-Launcher/Flow.Launcher/tree/v2.1.3).
