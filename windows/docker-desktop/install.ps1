[CmdletBinding()]
param(
  [switch]$SkipStart = $false
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($env:OS -ne "Windows_NT") {
  throw "This installer must run on Windows."
}

$packageModule = Join-Path `
  $PSScriptRoot `
  "..\packages\WinGetPackageInstaller.psm1"
Import-Module $packageModule -Force -ErrorAction Stop

$wingetPath = Join-Path `
  $env:LOCALAPPDATA `
  "Microsoft\WindowsApps\winget.exe"
$applicationPaths = @(
  "$env:LOCALAPPDATA\Programs\DockerDesktop\Docker Desktop.exe",
  "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe"
)
$installerOverride = (
  "install --user --quiet --accept-license " +
  "--backend=wsl-2 --no-windows-containers"
)
$application = Install-WinGetPackage `
  -PackageId "Docker.DockerDesktop" `
  -ExpectedPath $applicationPaths `
  -WingetPath $wingetPath `
  -InstallerOverride $installerOverride

$started = $false
$running = Get-Process -Name "Docker Desktop" -ErrorAction SilentlyContinue |
  Select-Object -First 1
if (-not $SkipStart -and $null -eq $running) {
  Start-Process -FilePath $application.Path
  $started = $true
}

[PSCustomObject]@{
  Application = $application
  Started = $started
}
