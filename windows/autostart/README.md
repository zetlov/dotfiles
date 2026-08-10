# Windows app autostart

This rollback-only component manages per-user Task Scheduler entries for the
GUI apps listed in `apps.json`. It remains paired with the retained Komorebi
rollback configuration and is not part of the active GlazeWM lifecycle.
Windows starts the apps after logon; Komorebi independently routes their
windows according to `windows/komorebi/komorebi.json`.

The tasks use the `Dotfiles App - ` prefix in the Task Scheduler root.
Installation updates that owned set and removes stale root tasks with the same
prefix. Run it only when deliberately restoring the Komorebi rollback path. It
does not change tasks in other folders, Startup shortcuts, or application
preferences outside that prefix.

## Install or update

Install the listed applications first, then run from WSL:

```bash
pwsh.exe -NoProfile -ExecutionPolicy Bypass \
  -File "$(wslpath -w ~/dotfiles/windows/install.ps1)" \
  -Mode Install -ComponentCsv "komorebi,autostart" -AllowRollbackOnly
```

The rollback-only autostart component must be selected together with its
Komorebi companion. The root Windows installer requires explicit component
selection and `-AllowRollbackOnly`, and refuses to proceed while GlazeWM is
running or registered for automatic startup. Directly running
`windows/autostart/install.ps1` is an internal/advanced entrypoint; it enforces
the same GlazeWM inactivity guard before changing scheduled tasks.

The installer fails if a configured executable is missing. Store applications
use their AppUserModelID. Logon actions run only in the interactive user
session, without elevation, and use staggered delays to let Komorebi start
first. The `workspace` values are also checked against the independently
deployed Komorebi configuration by the repository test suite.

Some applications enable their own startup setting. Disable those application
settings or their entries under **Settings > Apps > Startup** to prevent a
second instance from being requested at logon.

## Verify

```powershell
Get-ScheduledTask |
  Where-Object TaskName -Like "Dotfiles App - *" |
  Select-Object TaskName, State
```

Use **Run** on each task in Task Scheduler, then check the live identifiers:

```powershell
komorebic visible-windows
```

If an application executable identifier differs after an update, adjust the
matching rule in `windows/komorebi/komorebi.json` and deploy it with the
Komorebi update script.

## Remove

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass \
  -File "$(wslpath -w ~/dotfiles/windows/autostart/uninstall.ps1)"
```

Removal affects only tasks whose names start with `Dotfiles App - `.
