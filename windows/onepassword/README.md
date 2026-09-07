# 1Password for Windows

The WSL bootstrap installs the official `AgileBits.1Password` WinGet package
as a required Windows component. WinGet selects the applicable installer for
the Windows host architecture.

The installer verifies the 1Password executable in its supported per-user or
system install location before and after installation. Re-running the installer
does not start the application, modify vaults, or change account settings. An
existing Win32 installation is accepted even when a newer WinGet manifest uses
a different installer technology. 1Password manages application updates after
installation.

Install or verify the application from WSL:

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass \
  -File "$(wslpath -w "$PWD/windows/onepassword/install.ps1")"
```

Account sign-in, browser integration, Windows Hello, and SSH agent settings
remain explicit user actions. The 1Password CLI is not installed by this
component.
