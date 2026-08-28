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
$application = Install-WinGetPackage `
  -PackageId "AgileBits.1Password" `
  -ExpectedAppxPackageName "Agilebits.1Password" `
  -WingetPath $wingetPath

[PSCustomObject]@{
  Application = $application
}
