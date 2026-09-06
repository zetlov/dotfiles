[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') {
  throw 'This updater must run on Windows.'
}
Import-Module (Join-Path $PSScriptRoot 'FlowLauncherConfig.psm1') -Force
$executable = Join-Path $env:LOCALAPPDATA 'FlowLauncher/Flow.Launcher.exe'
if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) {
  throw 'Install Flow Launcher before updating its settings.'
}
$settingsPath = Join-Path $env:APPDATA 'FlowLauncher/Settings/Settings.json'
$installRoot = Split-Path -Parent $executable
$portablePaths = @((Join-Path $installRoot 'UserData')) + @(
  Get-ChildItem -LiteralPath $installRoot -Directory -Filter 'app-*' |
    ForEach-Object { Join-Path $_.FullName 'UserData' }
)
if (@($portablePaths | Where-Object { Test-Path -LiteralPath $_ }).Count -gt 0) {
  throw 'Portable Flow Launcher data detected; roaming settings were not changed.'
}
$existing = if (Test-Path -LiteralPath $settingsPath) {
  Get-Content -LiteralPath $settingsPath -Raw
} else { '{}' }
$merged = Merge-FlowLauncherSettings -ExistingJson $existing `
  -ManagedJson (Get-Content (Join-Path $PSScriptRoot 'settings.json') -Raw)
$sessionId = (Get-Process -Id $PID).SessionId
$processes = @(
  Get-Process -Name 'Flow.Launcher' -ErrorAction SilentlyContinue |
    Where-Object {
      $_.SessionId -eq $sessionId -and $_.Path -and
      $_.Path.StartsWith($installRoot + '\', [StringComparison]::OrdinalIgnoreCase)
    }
)
$backupPath = $null
if ($merged.Changed) {
  foreach ($process in $processes) {
    Stop-FlowLauncherProcess -Process $process
  }
  # Re-read after normal exit so the final application save is preserved.
  $existing = if (Test-Path -LiteralPath $settingsPath) {
    Get-Content -LiteralPath $settingsPath -Raw
  } else { '{}' }
  $merged = Merge-FlowLauncherSettings -ExistingJson $existing `
    -ManagedJson (Get-Content (Join-Path $PSScriptRoot 'settings.json') -Raw)
  $directory = Split-Path -Parent $settingsPath
  New-Item -ItemType Directory -Path $directory -Force | Out-Null
  $temporaryPath = Join-Path $directory ([guid]::NewGuid().ToString() + '.tmp')
  try {
    [IO.File]::WriteAllText($temporaryPath, $merged.Json, [Text.UTF8Encoding]::new($false))
    if (Test-Path -LiteralPath $settingsPath) {
      $backupPath = $settingsPath + '.' + [guid]::NewGuid().ToString() + '.bak'
      [IO.File]::Replace($temporaryPath, $settingsPath, $backupPath)
    } else {
      [IO.File]::Move($temporaryPath, $settingsPath)
    }
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) {
      Remove-Item -LiteralPath $temporaryPath -Force
    }
  }
}
if ($merged.Changed -or $processes.Count -eq 0 -or
    @($processes | Where-Object { $_.HasExited }).Count -gt 0) {
  Start-Process -FilePath $executable | Out-Null
}
[PSCustomObject]@{
  Changed = $merged.Changed
  SettingsPath = $settingsPath
  BackupPath = $backupPath
}
