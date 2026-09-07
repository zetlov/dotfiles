# Spicetify for Windows

This optional component installs the official `Spicetify.Spicetify` WinGet
package and applies the stable settings in `settings.psd1`. It does not execute
the mutable remote installation scripts published for Spicetify or Marketplace.

Spotify must already be installed and must have been opened long enough to
create its local preferences. Both the normal desktop client and the Microsoft
Store client are supported by Spicetify, subject to the compatibility range of
the installed Spicetify release.

Inspect and install the component from a Windows PowerShell prompt at the
repository root:

```powershell
& .\windows\install.ps1 -Component spicetify -PlanOnly
& .\windows\install.ps1 -Component spicetify
```

The installer creates `%APPDATA%\spicetify\config-xpui.ini` through the CLI and
then writes only the keys declared in `settings.psd1`. The generated file is
not tracked directly because it contains host-specific paths and mutable backup
metadata. Themes, extensions, custom apps, credentials, and Marketplace state
remain untouched unless they are explicitly added to this component later.

Patching Spotify is a separate, explicit operation. Close Spotify first, check
that the installed Spotify version is within Spicetify's published
compatibility range, and run:

```powershell
& .\windows\spicetify\apply.ps1
```

After a compatible Spotify update, rerun `apply.ps1`. If patching fails, use
`spicetify restore` before reopening Spotify and check the current Spicetify
release notes before retrying.
