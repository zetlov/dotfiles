[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') {
  throw 'This installer must run on Windows.'
}

Import-Module (Join-Path $PSScriptRoot '../packages/WinGetPackageInstaller.psm1') -Force
$application = Install-WinGetPackage `
  -PackageId 'Flow-Launcher.Flow-Launcher' `
  -ExpectedPath (Join-Path $env:LOCALAPPDATA 'FlowLauncher/Flow.Launcher.exe') `
  -WingetPath (Join-Path $env:LOCALAPPDATA 'Microsoft/WindowsApps/winget.exe')
$configuration = & (Join-Path $PSScriptRoot 'update-config.ps1')
[PSCustomObject]@{ Application = $application; Configuration = $configuration }
