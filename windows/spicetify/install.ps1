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
  (Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links\spicetify.exe"),
  (Join-Path $env:LOCALAPPDATA "spicetify\spicetify.exe")
)
$application = Install-WinGetPackage `
  -PackageId "Spicetify.Spicetify" `
  -ExpectedPath $applicationPaths `
  -WingetPath $wingetPath

$configPath = Join-Path $env:APPDATA "spicetify\config-xpui.ini"
if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
  & $application.Path
  if ($LASTEXITCODE -ne 0) {
    throw "Spicetify failed to create its configuration (exit code $LASTEXITCODE)."
  }
}

$settingsPath = Join-Path $PSScriptRoot "settings.psd1"
$settings = Import-PowerShellDataFile -LiteralPath $settingsPath
$configArguments = @("config")
foreach ($entry in @($settings.GetEnumerator() | Sort-Object Key)) {
  $configArguments += @([string]$entry.Key, [string]$entry.Value)
}

& $application.Path @configArguments
if ($LASTEXITCODE -ne 0) {
  throw "Spicetify failed to apply managed settings (exit code $LASTEXITCODE)."
}
if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
  throw "Spicetify did not create the expected configuration: $configPath"
}

[PSCustomObject]@{
  Application = $application
  ConfigPath = $configPath
  SettingsPath = $settingsPath
}
