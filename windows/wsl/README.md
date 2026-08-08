# Windows WSL configuration

The affected Windows host temporarily disables WSLg because WSL 2.7.11 and
WSLg 1.0.73.2 can restart an invisible MSRDC window after Weston crashes in
`rdp-backend.so`. That restart can steal keyboard focus from the active Windows
application.

Merge the setting from `wslconfig.ini` into `%USERPROFILE%\.wslconfig` without
replacing unrelated host-specific settings:

```ini
[wsl2]
guiApplications=false
```

The setting is global and disables WSLg for every WSL 2 distribution on the
host. See Microsoft's [advanced WSL configuration documentation][wsl-config]
for the supported `.wslconfig` options.

Save active WSL work, then apply the change from Windows PowerShell:

```powershell
wsl.exe --shutdown
```

This disables Linux GUI application windows, including direct `plt.show()`
windows. CLI programs, saved plots, Jupyter browser output, and editor-hosted
inline plots remain available.

To restore WSLg, remove `guiApplications=false` from `%USERPROFILE%\.wslconfig`
and run `wsl.exe --shutdown` again. Before editing, save a dated backup of the
existing file so unrelated host settings can be restored.

[wsl-config]: https://learn.microsoft.com/windows/wsl/wsl-config
