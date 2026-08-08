[CmdletBinding()]
param(
  [string]$SourcePath,
  [string]$UserProfile = $env:USERPROFILE,
  [switch]$SkipFonts = $false
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

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
  Fonts = $fontResults
  Config = $configResult
}
