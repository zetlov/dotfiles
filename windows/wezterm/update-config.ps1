[CmdletBinding()]
param(
  [string]$SourcePath,
  [string]$UserProfile = $env:USERPROFILE
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($SourcePath)) {
  $SourcePath = Join-Path $PSScriptRoot "..\..\stow\base\.config\wezterm\wezterm.lua"
}
if ([string]::IsNullOrWhiteSpace($UserProfile)) {
  throw "UserProfile is required."
}

$resolvedSourcePath = [System.IO.Path]::GetFullPath($SourcePath)
if (-not (Test-Path -LiteralPath $resolvedSourcePath -PathType Leaf)) {
  throw "Managed WezTerm config not found: $resolvedSourcePath"
}

$resolvedUserProfile = [System.IO.Path]::GetFullPath($UserProfile)
$configHome = Join-Path $resolvedUserProfile ".config\wezterm"
$destinationPath = Join-Path $configHome "wezterm.lua"

if (Test-Path -LiteralPath $destinationPath -PathType Container) {
  throw "WezTerm config destination is a directory: $destinationPath"
}

New-Item -ItemType Directory -Path $configHome -Force | Out-Null

if (Test-Path -LiteralPath $destinationPath -PathType Leaf) {
  $sourceHash = (Get-FileHash -LiteralPath $resolvedSourcePath -Algorithm SHA256).Hash
  $destinationHash = (Get-FileHash -LiteralPath $destinationPath -Algorithm SHA256).Hash
  if ($sourceHash -eq $destinationHash) {
    return [PSCustomObject]@{
      Changed = $false
      DestinationPath = $destinationPath
      BackupPath = $null
    }
  }
}

$backupPath = $null
if (Test-Path -LiteralPath $destinationPath -PathType Leaf) {
  $timestamp = Get-Date -Format "yyyyMMdd-HHmmssfff"
  $backupPath = "$destinationPath.before-update-$timestamp"
  Copy-Item -LiteralPath $destinationPath -Destination $backupPath
}

$temporaryPath = "$destinationPath.tmp-$([guid]::NewGuid().ToString('N'))"
try {
  Copy-Item -LiteralPath $resolvedSourcePath -Destination $temporaryPath
  if (Test-Path -LiteralPath $destinationPath -PathType Leaf) {
    if ($null -eq $backupPath) {
      $timestamp = Get-Date -Format "yyyyMMdd-HHmmssfff"
      $backupPath = "$destinationPath.before-update-$timestamp"
    }
    [System.IO.File]::Replace($temporaryPath, $destinationPath, $backupPath)
  } else {
    [System.IO.File]::Move($temporaryPath, $destinationPath)
  }
} finally {
  if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
    Remove-Item -LiteralPath $temporaryPath -Force
  }
}

[PSCustomObject]@{
  Changed = $true
  DestinationPath = $destinationPath
  BackupPath = $backupPath
}
