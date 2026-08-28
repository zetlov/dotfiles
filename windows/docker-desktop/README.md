# Docker Desktop installation

The WSL bootstrap installs Docker Desktop when the resolved container backend
is `desktop`. The installer uses the official `Docker.DockerDesktop` WinGet
package, accepts the package agreements noninteractively, and starts Docker
Desktop when it is not already running. It uses Docker's recommended per-user
installation mode, so the application itself does not require administrator
rights after WSL has already been enabled for the machine.

WinGet selects Docker's native x64 or ARM64 installer for the Windows host. The
installer accepts both the current per-user location under
`%LOCALAPPDATA%\Programs\DockerDesktop` and the machine-wide location under
`%ProgramFiles%\Docker\Docker`.

Docker Desktop integration is enabled automatically only for the default WSL
distribution. If the bootstrap reports that integration is unavailable after
installation, open Docker Desktop, enable the current distribution under
Settings > Resources > WSL Integration, and rerun `./install.sh`. Do not install
a second Docker daemon inside that distribution.

Select `--container-backend=native` to use the distro-managed Docker Engine, or
`--container-backend=none` to omit container tooling and Docker Desktop.

Install or start only this component from Windows PowerShell:

```powershell
& .\windows\install.ps1 -Component docker-desktop
```
