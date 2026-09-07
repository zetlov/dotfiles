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
  "$env:ProgramFiles\JPEGView\JPEGView.exe",
  "${env:ProgramFiles(x86)}\JPEGView\JPEGView.exe"
)
$application = Install-WinGetPackage `
  -PackageId "sylikc.JPEGView" `
  -ExpectedPath $applicationPaths `
  -WingetPath $wingetPath

$configurationDirectory = Join-Path $env:APPDATA "JPEGView"
New-Item -ItemType Directory -Path $configurationDirectory -Force | Out-Null
foreach ($configurationFile in @("JPEGView.ini", "KeyMap.txt")) {
  Copy-Item `
    -LiteralPath (Join-Path $PSScriptRoot $configurationFile) `
    -Destination (Join-Path $configurationDirectory $configurationFile) `
    -Force
}

[PSCustomObject]@{
  Application = $application
  ConfigurationDirectory = $configurationDirectory
}
