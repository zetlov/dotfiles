param(
  [switch]$Restart = $true,
  [string]$InstallDir = "$env:LOCALAPPDATA\kanata"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$gameModeModule = Join-Path $PSScriptRoot "KanataGameMode.psm1"
Import-Module $gameModeModule -Force -ErrorAction Stop
$InstallDir = Resolve-KanataInstallDir -Path $InstallDir

function Resolve-DotfilesRoot {
  return (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
}

$dot = Resolve-DotfilesRoot
$sourceDir = Join-Path $dot "windows\kanata"
$cfgDst = Join-Path $InstallDir "kanata.kbd"
$exeDst = Join-Path $InstallDir "kanata.exe"
$managedFiles = @(
  "kanata.kbd",
  "kanata-game.kbd",
  "KanataGameMode.psm1",
  "game-mode.ps1",
  "game-mode.json"
)

foreach ($name in $managedFiles) {
  $sourcePath = Join-Path $sourceDir $name
  if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
    throw "Kanata file not found: $sourcePath"
  }
}
[void](Get-KanataGameModeSettings `
  -Path (Join-Path $sourceDir "game-mode.json"))
if (-not (Test-Path -LiteralPath $exeDst -PathType Leaf)) {
  throw "kanata.exe not found: $exeDst (run install.ps1 first)"
}

$watcherWasRunning = Test-KanataGameModeWatcher -InstallDir $InstallDir
$kanataWasRunning = @(
  Get-KanataManagedProcesses -ExePath $exeDst
).Count -gt 0
$backupDir = Join-Path $env:TEMP (
  "kanata_update_" + [guid]::NewGuid().ToString("N")
)
$previousFiles = @{}
foreach ($name in $managedFiles) {
  $previousFiles[$name] = Test-Path `
    -LiteralPath (Join-Path $InstallDir $name) `
    -PathType Leaf
}
$runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
$runProperties = if (Test-Path -LiteralPath $runKey) {
  Get-ItemProperty -LiteralPath $runKey
} else {
  $null
}
$previousRunValues = @{}
foreach ($name in @("DotfilesKanataGameMode", "Kanata")) {
  $property = if ($runProperties) {
    $runProperties.PSObject.Properties[$name]
  } else {
    $null
  }
  $previousRunValues[$name] = [pscustomobject]@{
    Existed = $null -ne $property
    Value = if ($property) { [string]$property.Value } else { "" }
  }
}
$updated = $false
$rollbackSucceeded = $false
$updateError = $null
$changesStarted = $false

try {
  New-Item -ItemType Directory -Path $backupDir | Out-Null
  foreach ($name in $managedFiles) {
    $destinationPath = Join-Path $InstallDir $name
    if ([bool]$previousFiles[$name]) {
      Copy-Item `
        -LiteralPath $destinationPath `
        -Destination (Join-Path $backupDir $name)
    }
  }

  $changesStarted = $true
  if ($watcherWasRunning) {
    Stop-KanataGameModeWatcher -InstallDir $InstallDir
  }
  if ($Restart -or $watcherWasRunning) {
    Stop-KanataManagedProcesses -ExePath $exeDst
  }
  foreach ($name in $managedFiles) {
    Copy-Item `
      -LiteralPath (Join-Path $sourceDir $name) `
      -Destination (Join-Path $InstallDir $name) `
      -Force
  }
  Set-KanataGameModeRunEntry -InstallDir $InstallDir

  if ($Restart -or $watcherWasRunning) {
    Start-KanataGameModeWatcher -InstallDir $InstallDir
    Write-Host "Started Kanata game mode watcher."
  }
  Write-Host "Updated Kanata configuration and game mode files."
  $updated = $true
} catch {
  $updateError = $_
} finally {
  if (-not $updated -and $changesStarted) {
    try {
      Stop-KanataGameModeWatcher -InstallDir $InstallDir
      Stop-KanataManagedProcesses -ExePath $exeDst
      foreach ($name in $managedFiles) {
        $backupPath = Join-Path $backupDir $name
        $destinationPath = Join-Path $InstallDir $name
        if (Test-Path -LiteralPath $backupPath -PathType Leaf) {
          Copy-Item `
            -LiteralPath $backupPath `
            -Destination $destinationPath `
            -Force
        } elseif (
          -not [bool]$previousFiles[$name] -and
          (Test-Path -LiteralPath $destinationPath -PathType Leaf)
        ) {
          Remove-Item -LiteralPath $destinationPath -Force
        }
      }
      if (-not (Test-Path -LiteralPath $runKey)) {
        New-Item -Path $runKey | Out-Null
      }
      foreach ($name in @("DotfilesKanataGameMode", "Kanata")) {
        $state = $previousRunValues[$name]
        if ($state.Existed) {
          New-ItemProperty `
            -LiteralPath $runKey `
            -Name $name `
            -Value $state.Value `
            -PropertyType String `
            -Force | Out-Null
        } else {
          Remove-ItemProperty `
            -LiteralPath $runKey `
            -Name $name `
            -ErrorAction SilentlyContinue
        }
      }
      if ($watcherWasRunning) {
        Start-KanataGameModeWatcher -InstallDir $InstallDir
      } elseif ($kanataWasRunning) {
        Start-KanataManagedProcess `
          -ExePath $exeDst `
          -ConfigPath $cfgDst | Out-Null
      }
      $rollbackSucceeded = $true
    } catch {
      Write-Warning (
        "Failed to restore the previous Kanata files. Recovery files remain " +
        "at ${backupDir}: $($_.Exception.Message)"
      )
    }
  } elseif (-not $changesStarted) {
    $rollbackSucceeded = $true
  }
  if (
    (Test-Path -LiteralPath $backupDir) -and
    ($updated -or $rollbackSucceeded)
  ) {
    try {
      Remove-Item -LiteralPath $backupDir -Recurse -Force
    } catch {
      Write-Warning (
        "Failed to remove temporary Kanata backup ${backupDir}: " +
        "$($_.Exception.Message)"
      )
    }
  }
}

if ($updateError) {
  throw $updateError
}
