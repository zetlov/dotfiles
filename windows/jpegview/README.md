# JPEGView

This optional component installs `sylikc.JPEGView` from the official WinGet
source and deploys the managed per-user configuration to
`%APPDATA%\JPEGView`.

The configuration keeps filename-ordered, wraparound folder navigation and
maps `Q` to quit and `F` to fullscreen. Arrow keys navigate adjacent images,
matching the everyday controls used with `imv` on Arch.

Install from a Windows PowerShell prompt at the repository root:

```powershell
& .\windows\install.ps1 -Component jpegview
```

Yazi on WSL opens `image/*` files with this installed executable directly;
other files continue to use their Windows default application. To make
JPEGView the default also for Explorer or other Windows applications, use
Windows Settings > Apps > Default apps after installation.
