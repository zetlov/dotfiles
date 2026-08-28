[CmdletBinding()]
param(
  [string]$SourcePath,
  [string]$UserProfile = $env:USERPROFILE,
  [switch]$SkipFonts = $false
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$packageModule = Join-Path `
  $PSScriptRoot `
  "..\packages\WinGetPackageInstaller.psm1"
Import-Module $packageModule -Force -ErrorAction Stop

$wingetPath = Join-Path `
  $env:LOCALAPPDATA `
  "Microsoft\WindowsApps\winget.exe"
$weztermPaths = @(
  "$env:ProgramFiles\WezTerm\wezterm.exe",
  "$env:LOCALAPPDATA\Programs\WezTerm\wezterm.exe"
)
$architecture = ""
if ((Resolve-WindowsNativeArchitecture) -eq "arm64") {
  $architecture = "x64"
}
$application = Install-WinGetPackage `
  -PackageId "wez.wezterm" `
  -ExpectedPath $weztermPaths `
  -WingetPath $wingetPath `
  -Architecture $architecture

$fontResults = @()
if (-not $SkipFonts) {
  $fontInstallScript = Join-Path $PSScriptRoot "install-fonts.ps1"
  $fontResults = @(& $fontInstallScript -UserProfile $UserProfile)
}

$updateScript = Join-Path $PSScriptRoot "update-config.ps1"
$configParameters = @{
  UserProfile = $UserProfile
}
if (-not [string]::IsNullOrWhiteSpace($SourcePath)) {
  $configParameters.SourcePath = $SourcePath
}
$configResult = & $updateScript @configParameters

[PSCustomObject]@{
  Application = $application
  Fonts = $fontResults
  Config = $configResult
}
