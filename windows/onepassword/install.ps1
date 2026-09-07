[CmdletBinding()]
param()

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
  "$env:LOCALAPPDATA\1Password\app\8\1Password.exe",
  "$env:ProgramFiles\1Password\app\8\1Password.exe"
)
$application = Install-WinGetPackage `
  -PackageId "AgileBits.1Password" `
  -ExpectedPath $applicationPaths `
  -WingetPath $wingetPath

[PSCustomObject]@{
  Application = $application
}
