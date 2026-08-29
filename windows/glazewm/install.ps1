[CmdletBinding()]
param(
  [string]$ManagerPath = (
    Join-Path $env:ProgramFiles "glzr.io\GlazeWM\glazewm.exe"
  ),

  [string]$GlazeWMPath = (
    Join-Path $env:ProgramFiles "glzr.io\GlazeWM\cli\glazewm.exe"
  ),

  [string]$ConfigRoot = (
    Join-Path $env:USERPROFILE ".glzr\glazewm"
  ),

  [string]$RuntimeRoot = (
    Join-Path $env:LOCALAPPDATA "dotfiles\glazewm"
  ),

  [ValidatePattern('^\d+\.\d+\.\d+$')]
  [string]$RequiredVersion = "3.10.1",

  [ValidateRange(1, 60)]
  [int]$StartupTimeoutSeconds = 15,

  [ValidateRange(1, 120)]
  [int]$ZebarStartupTimeoutSeconds = 30,

  [ValidateRange(1, 300)]
  [int]$StartupAppsTimeoutSeconds = 150,

  [switch]$PreserveZebarRuntime
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$rollbackSafetyModule = Join-Path $PSScriptRoot "..\rollback\RollbackSafety.psm1"
Import-Module $rollbackSafetyModule -Force -ErrorAction Stop
Assert-KomorebiInactive

$processModule = Join-Path $PSScriptRoot "GlazeWMProcess.psm1"
Import-Module $processModule -Force -ErrorAction Stop

if ($env:OS -ne "Windows_NT") {
  throw "This script must run on Windows."
}

if (
  -not (Test-Path -LiteralPath $ManagerPath -PathType Leaf) -or
  -not (Test-Path -LiteralPath $GlazeWMPath -PathType Leaf)
) {
  & winget.exe install `
    --id "glzr-io.glazewm" `
    --exact `
    --version $RequiredVersion `
    --silent `
    --accept-source-agreements `
    --accept-package-agreements
  if ($LASTEXITCODE -ne 0) {
    throw "WinGet could not install glzr-io.glazewm."
  }
}

foreach ($executable in @($ManagerPath, $GlazeWMPath)) {
  if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) {
    throw "GlazeWM executable not found: $executable"
  }
}
$versionOutput = (& $GlazeWMPath --version 2>&1 | Out-String).Trim()
if (
  $LASTEXITCODE -ne 0 -or
  $versionOutput -ne "glazewm $RequiredVersion"
) {
  throw (
    "Unexpected GlazeWM version. Expected $RequiredVersion, got: " +
    $versionOutput
  )
}

function Get-GlazeHelperProcess {
  param([Parameter(Mandatory = $true)][string]$ScriptPath)

  return Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
    Where-Object {
      $null -ne $_.CommandLine -and
      $_.CommandLine.IndexOf(
        $ScriptPath,
        [StringComparison]::OrdinalIgnoreCase
      ) -ge 0
    } |
    Select-Object -First 1
}

function Wait-GlazeHelperExit {
  param(
    [Parameter(Mandatory = $true)][int]$ProcessId,
    [Parameter(Mandatory = $true)][int]$TimeoutSeconds
  )

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  do {
    $process = Get-CimInstance `
      Win32_Process `
      -Filter "ProcessId = $ProcessId" `
      -ErrorAction SilentlyContinue
    if ($null -eq $process) {
      return
    }
    Start-Sleep -Milliseconds 250
  } while ((Get-Date) -lt $deadline)

  throw "GlazeWM helper PID $ProcessId did not stop."
}

function Get-ZetshellZebarProcess {
  return Get-Process -Name "zebar" -ErrorAction SilentlyContinue |
    Where-Object {
      $_.Responding -and
      $_.MainWindowTitle -eq "Zebar - zetshell / bar"
    } |
    Select-Object -First 1
}

function Start-HiddenPowerShellScript {
  param([Parameter(Mandatory = $true)][string]$ScriptPath)

  return Start-Process `
    -FilePath "powershell.exe" `
    -ArgumentList @(
      "-NoProfile",
      "-ExecutionPolicy", "Bypass",
      "-WindowStyle", "Hidden",
      "-File", "`"$ScriptPath`""
    ) `
    -WindowStyle Hidden `
    -PassThru
}

function Wait-GlazeWMReady {
  param(
    [Parameter(Mandatory = $true)][string]$CliPath,
    [Parameter(Mandatory = $true)][int]$TimeoutSeconds
  )

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  do {
    Start-Sleep -Milliseconds 250
    try {
      & $CliPath query app-metadata 2>$null | Out-Null
      if ($LASTEXITCODE -eq 0) {
        return $true
      }
    } catch {
      # Retry until the bounded deadline while the IPC server initializes.
    }
  } while ((Get-Date) -lt $deadline)

  return $false
}

function Start-ManagedZebar {
  param([Parameter(Mandatory = $true)][object]$ZebarState)

  Start-Process `
    -FilePath $ZebarState.ZebarPath `
    -ArgumentList @(
      "start-widget-preset",
      "--pack", $ZebarState.Pack,
      "--widget-name", "bar",
      "--preset", "primary-monitor"
    ) `
    -WindowStyle Hidden |
    Out-Null
}

$startupDirectory = [Environment]::GetFolderPath("Startup")
$komorebiShortcut = Join-Path $startupDirectory "komorebi.lnk"
if (Test-Path -LiteralPath $komorebiShortcut -PathType Leaf) {
  throw (
    "Disable Komorebi autostart before installing GlazeWM: " +
    $komorebiShortcut
  )
}

$sourceConfig = Join-Path $PSScriptRoot "config.yaml"
$sourceModule = Join-Path $PSScriptRoot "GlazeWMAutoTile.psm1"
$sourceWorkspaceHelpers = Join-Path `
  $PSScriptRoot `
  "GlazeWMWorkspaceHelpers.ps1"
$sourceDaemon = Join-Path $PSScriptRoot "autotile.ps1"
$sourceMonitorSyncModule = Join-Path `
  $PSScriptRoot `
  "GlazeWMMonitorSync.psm1"
$sourceMonitorSyncScript = Join-Path `
  $PSScriptRoot `
  "Sync-GlazeMonitorLayout.ps1"
$sourceStartupScript = Join-Path $PSScriptRoot "Start-GlazeWorkspaceApps.ps1"
$sourceStartupConfig = Join-Path $PSScriptRoot "startup-apps.json"
$sourceZebarInstaller = Join-Path $PSScriptRoot "..\zebar\install.ps1"

foreach ($sourcePath in @(
  $sourceConfig,
  $sourceModule,
  $sourceWorkspaceHelpers,
  $sourceDaemon,
  $sourceMonitorSyncModule,
  $sourceMonitorSyncScript,
  $sourceStartupScript,
  $sourceStartupConfig,
  $sourceZebarInstaller
)) {
  if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
    throw "Required GlazeWM file not found: $sourcePath"
  }
}

New-Item -ItemType Directory -Path $ConfigRoot -Force | Out-Null
New-Item -ItemType Directory -Path $RuntimeRoot -Force | Out-Null

$liveConfig = Join-Path $ConfigRoot "config.yaml"
$runtimeDeployments = @(
  [pscustomobject]@{
    Source = $sourceModule
    Destination = Join-Path $RuntimeRoot "GlazeWMAutoTile.psm1"
  },
  [pscustomobject]@{
    Source = $sourceWorkspaceHelpers
    Destination = Join-Path $RuntimeRoot "GlazeWMWorkspaceHelpers.ps1"
  },
  [pscustomobject]@{
    Source = $sourceDaemon
    Destination = Join-Path $RuntimeRoot "autotile.ps1"
  },
  [pscustomobject]@{
    Source = $sourceMonitorSyncModule
    Destination = Join-Path $RuntimeRoot "GlazeWMMonitorSync.psm1"
  },
  [pscustomobject]@{
    Source = $sourceMonitorSyncScript
    Destination = Join-Path $RuntimeRoot "Sync-GlazeMonitorLayout.ps1"
  },
  [pscustomobject]@{
    Source = $sourceStartupScript
    Destination = Join-Path $RuntimeRoot "Start-GlazeWorkspaceApps.ps1"
  },
  [pscustomobject]@{
    Source = $sourceStartupConfig
    Destination = Join-Path $RuntimeRoot "startup-apps.json"
  }
)

$existingManagers = @(
  Get-Process -Name "glazewm" -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -ne $GlazeWMPath }
)
if ($existingManagers.Count -gt 1) {
  throw "Multiple GlazeWM manager processes are running."
}
$manager = $existingManagers | Select-Object -First 1
$managerWasRunning = $null -ne $manager
if ($managerWasRunning) {
  & $GlazeWMPath query app-metadata 2>$null | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "The running GlazeWM manager is not reachable through IPC."
  }
}

$rollbackRoot = Join-Path (
  [IO.Path]::GetTempPath()
) ("glazewm-install-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $rollbackRoot -Force | Out-Null
$runtimeSnapshots = @(
  foreach ($deployment in $runtimeDeployments) {
    $destinationExisted = Test-Path `
      -LiteralPath $deployment.Destination `
      -PathType Leaf
    $snapshotPath = Join-Path $rollbackRoot (
      [guid]::NewGuid().ToString("N") + ".bak"
    )
    if ($destinationExisted) {
      Copy-Item `
        -LiteralPath $deployment.Destination `
        -Destination $snapshotPath `
        -Force
    }
    [pscustomobject]@{
      Destination = $deployment.Destination
      Existed = $destinationExisted
      Snapshot = $snapshotPath
    }
  }
)

$runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
$runProperty = $null
if (Test-Path -LiteralPath $runKey) {
  $runProperty = (
    Get-ItemProperty -LiteralPath $runKey -ErrorAction SilentlyContinue
  ).PSObject.Properties["GlazeWM"]
}
$runValueExisted = $null -ne $runProperty
$previousRunValue = if ($runValueExisted) {
  [string]$runProperty.Value
} else {
  $null
}

$liveConfigExisted = Test-Path -LiteralPath $liveConfig -PathType Leaf
$backupPath = $null
if (
  $liveConfigExisted -and
  (Get-FileHash -LiteralPath $liveConfig -Algorithm SHA256).Hash -ne
    (Get-FileHash -LiteralPath $sourceConfig -Algorithm SHA256).Hash
) {
  $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $backupPath = Join-Path $ConfigRoot "config.before-dotfiles-$timestamp.yaml"
  Copy-Item -LiteralPath $liveConfig -Destination $backupPath -Force
}

$deployedDaemon = Join-Path $RuntimeRoot "autotile.ps1"
$deployedMonitorSyncScript = Join-Path `
  $RuntimeRoot `
  "Sync-GlazeMonitorLayout.ps1"
$deployedStartupScript = Join-Path $RuntimeRoot "Start-GlazeWorkspaceApps.ps1"
$startupStatePath = Join-Path $RuntimeRoot "startup-apps-state.json"
$startupErrorPath = Join-Path $RuntimeRoot "startup-apps-error.log"
$daemon = $null
$zebarState = $null
$state = $null
$installationSucceeded = $false
$managerStartedByInstaller = $false
$preserveStartedRuntime = $false
$startedRuntimeAutostartRegistered = $false
$daemonWasRunning = $false
$startedDaemonProcess = $null
$startupAppsProcess = $null
try {
  if ($PreserveZebarRuntime -and -not $managerWasRunning) {
    throw (
      "Preserving Zebar requires an already-running GlazeWM manager because " +
      "manager startup executes configured startup commands."
    )
  }
  if ($PreserveZebarRuntime) {
    $zebarState = $null
  } else {
    $zebarState = & $sourceZebarInstaller | Select-Object -Last 1
  }
  Copy-Item -LiteralPath $sourceConfig -Destination $liveConfig -Force
  foreach ($deployment in $runtimeDeployments) {
    Copy-Item `
      -LiteralPath $deployment.Source `
      -Destination $deployment.Destination `
      -Force
  }
  $existingStartupHelper = Get-GlazeHelperProcess `
    -ScriptPath $deployedStartupScript
  if ($null -ne $existingStartupHelper) {
    Stop-GlazeProcessTree -ProcessId $existingStartupHelper.ProcessId
    Wait-GlazeHelperExit `
      -ProcessId $existingStartupHelper.ProcessId `
      -TimeoutSeconds $StartupTimeoutSeconds
  }

  $existingDaemon = Get-GlazeHelperProcess -ScriptPath $deployedDaemon
  $daemonWasRunning = $null -ne $existingDaemon
  if ($daemonWasRunning) {
    Stop-GlazeProcessTree -ProcessId $existingDaemon.ProcessId
    Wait-GlazeHelperExit `
      -ProcessId $existingDaemon.ProcessId `
      -TimeoutSeconds $StartupTimeoutSeconds
  }

  Remove-Item `
    -LiteralPath $startupStatePath `
    -Force `
    -ErrorAction SilentlyContinue
  Remove-Item `
    -LiteralPath $startupErrorPath `
    -Force `
    -ErrorAction SilentlyContinue

  if ($managerWasRunning) {
    & $GlazeWMPath command wm-reload-config 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
      throw "GlazeWM could not reload the deployed config."
    }
  } else {
    $manager = Start-Process `
      -FilePath $ManagerPath `
      -ArgumentList @("start", "--config=$liveConfig") `
      -PassThru
    $managerStartedByInstaller = $true
    $preserveStartedRuntime = $true

    if (-not (Test-Path -LiteralPath $runKey)) {
      New-Item -Path $runKey | Out-Null
    }
    Set-ItemProperty `
      -Path $runKey `
      -Name "GlazeWM" `
      -Value "`"$ManagerPath`"" `
      -Type String
    $startedRuntimeAutostartRegistered = $true
  }

  if (-not (Wait-GlazeWMReady `
    -CliPath $GlazeWMPath `
    -TimeoutSeconds $StartupTimeoutSeconds
  )) {
    throw "GlazeWM did not become ready within $StartupTimeoutSeconds seconds."
  }

  if ($managerWasRunning) {
    $startedDaemonProcess = Start-HiddenPowerShellScript `
      -ScriptPath $deployedDaemon
    $startupAppsProcess = Start-HiddenPowerShellScript `
      -ScriptPath $deployedStartupScript
    if ($PreserveZebarRuntime) {
      & $deployedMonitorSyncScript `
        -GlazeWMPath $GlazeWMPath | Out-Null
    } else {
      & $deployedMonitorSyncScript `
        -GlazeWMPath $GlazeWMPath `
        -ZebarPath $zebarState.ZebarPath `
        -RestartZebar | Out-Null
    }
  }

  $daemonDeadline = (Get-Date).AddSeconds($StartupTimeoutSeconds)
  $daemon = $null
  do {
    Start-Sleep -Milliseconds 250
    $daemon = Get-GlazeHelperProcess -ScriptPath $deployedDaemon
    if (
      $null -ne $startedDaemonProcess -and
      $null -ne $daemon -and
      $daemon.ProcessId -ne $startedDaemonProcess.Id
    ) {
      $daemon = $null
    }
  } while ($null -eq $daemon -and (Get-Date) -lt $daemonDeadline)

  if ($null -eq $daemon) {
    throw "GlazeWM started, but the automatic tiling helper did not."
  }
  Start-Sleep -Seconds 1
  if ($null -eq (Get-CimInstance `
    Win32_Process `
    -Filter "ProcessId = $($daemon.ProcessId)" `
    -ErrorAction SilentlyContinue
  )) {
    throw "The automatic tiling helper exited during startup."
  }

  if (-not $PreserveZebarRuntime) {
    $zebarDeadline = (Get-Date).AddSeconds($ZebarStartupTimeoutSeconds)
    $zebarProcess = $null
    do {
      Start-Sleep -Milliseconds 250
      $zebarProcess = Get-ZetshellZebarProcess
    } while ($null -eq $zebarProcess -and (Get-Date) -lt $zebarDeadline)
    if ($null -eq $zebarProcess) {
      throw "Zebar did not start within $ZebarStartupTimeoutSeconds seconds."
    }
  }

  $startupAppsDeadline = (Get-Date).AddSeconds($StartupAppsTimeoutSeconds)
  do {
    Start-Sleep -Milliseconds 250
    if (Test-Path -LiteralPath $startupErrorPath -PathType Leaf) {
      throw "The startup application helper failed. See: $startupErrorPath"
    }
  } while (
    -not (Test-Path -LiteralPath $startupStatePath -PathType Leaf) -and
    (Get-Date) -lt $startupAppsDeadline
  )

  if (-not (Test-Path -LiteralPath $startupStatePath -PathType Leaf)) {
    throw (
      "Startup applications did not complete within " +
      "$StartupAppsTimeoutSeconds seconds."
    )
  }

  try {
    $startupState = Get-Content -LiteralPath $startupStatePath -Raw |
      ConvertFrom-Json
  } catch {
    throw "The startup application state is invalid: $startupStatePath"
  }
  if ([int]$startupState.ApplicationCount -lt 1) {
    throw "The startup application state contains no applications."
  }

  if (-not (Test-Path -LiteralPath $runKey)) {
    New-Item -Path $runKey | Out-Null
  }
  Set-ItemProperty `
    -Path $runKey `
    -Name "GlazeWM" `
    -Value "`"$ManagerPath`"" `
    -Type String

  $state = [pscustomobject]@{
    ConfigPath = $liveConfig
    ManagerProcessId = $manager.Id
    AutoTileProcessId = $daemon.ProcessId
  }
  $state | ConvertTo-Json | Set-Content `
    -LiteralPath (Join-Path $RuntimeRoot "managed-state.json") `
    -Encoding UTF8
  $installationSucceeded = $true
} finally {
  if (-not $installationSucceeded -and $preserveStartedRuntime) {
    if (-not (Wait-GlazeWMReady `
      -CliPath $GlazeWMPath `
      -TimeoutSeconds $StartupTimeoutSeconds
    )) {
      if ($null -ne $manager -and -not $manager.HasExited) {
        throw (
          "The newly started GlazeWM manager is alive but its IPC server " +
          "is unreachable. Runtime files were preserved for recovery."
        )
      }
      $manager = Start-Process `
        -FilePath $ManagerPath `
        -ArgumentList @("start", "--config=$liveConfig") `
        -PassThru
      if (-not (Wait-GlazeWMReady `
        -CliPath $GlazeWMPath `
        -TimeoutSeconds $StartupTimeoutSeconds
      )) {
        throw (
          "GlazeWM recovery failed after installation validation failed. " +
          "Runtime files were preserved."
        )
      }
    }
    if (-not $startedRuntimeAutostartRegistered) {
      try {
        if (-not (Test-Path -LiteralPath $runKey)) {
          New-Item -Path $runKey | Out-Null
        }
        Set-ItemProperty `
          -Path $runKey `
          -Name "GlazeWM" `
          -Value "`"$ManagerPath`"" `
          -Type String
        $startedRuntimeAutostartRegistered = $true
      } catch {
        Write-Warning (
          "GlazeWM is preserved for this session, but autostart could not " +
          "be registered: " + $_.Exception.Message
        )
      }
    }
    $preservedScope = if ($startedRuntimeAutostartRegistered) {
      "config, runtime files, and autostart entry were"
    } else {
      "config and runtime files were"
    }
    Write-Warning (
      "GlazeWM started before installation failed. Its $preservedScope " +
      "preserved to avoid orphaning cloaked windows. Run this installer " +
      "again to finish validation."
    )
  } elseif (-not $installationSucceeded) {
    if ($null -ne $startupAppsProcess -and -not $startupAppsProcess.HasExited) {
      Stop-Process `
        -Id $startupAppsProcess.Id `
        -Force `
        -ErrorAction SilentlyContinue
    }
    if (
      $null -ne $startedDaemonProcess -and
      -not $startedDaemonProcess.HasExited
    ) {
      try {
      Stop-GlazeProcessTree -ProcessId $startedDaemonProcess.Id
        Wait-GlazeHelperExit `
          -ProcessId $startedDaemonProcess.Id `
          -TimeoutSeconds $StartupTimeoutSeconds
      } catch {
        Write-Warning (
          "Rollback could not stop the new automatic tiling helper: " +
          $_.Exception.Message
        )
      }
    }
    if (
      $null -ne $daemon -and
      (
        $null -eq $startedDaemonProcess -or
        $daemon.ProcessId -ne $startedDaemonProcess.Id
      )
    ) {
      try {
        Stop-GlazeProcessTree -ProcessId $daemon.ProcessId
      } catch {
        # The rollback error below reports the complete recovery failure.
      }
    }
    if ($null -ne $backupPath) {
      Copy-Item -LiteralPath $backupPath -Destination $liveConfig -Force
    } elseif (-not $liveConfigExisted) {
      Remove-Item -LiteralPath $liveConfig -Force -ErrorAction SilentlyContinue
    }

    foreach ($snapshot in $runtimeSnapshots) {
      if ($snapshot.Existed) {
        Copy-Item `
          -LiteralPath $snapshot.Snapshot `
          -Destination $snapshot.Destination `
          -Force
      } else {
        Remove-Item `
          -LiteralPath $snapshot.Destination `
          -Force `
          -ErrorAction SilentlyContinue
      }
    }

    if ($runValueExisted) {
      if (-not (Test-Path -LiteralPath $runKey)) {
        New-Item -Path $runKey | Out-Null
      }
      Set-ItemProperty `
        -Path $runKey `
        -Name "GlazeWM" `
        -Value $previousRunValue `
        -Type String
    } elseif (Test-Path -LiteralPath $runKey) {
      Remove-ItemProperty `
        -LiteralPath $runKey `
        -Name "GlazeWM" `
        -Force `
        -ErrorAction SilentlyContinue
    }
    if ($managerWasRunning -or $managerStartedByInstaller) {
      try {
        & $GlazeWMPath command wm-reload-config 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) {
          throw "GlazeWM rejected the restored config."
        }
      } catch {
        Write-Warning (
          "Rollback could not reload the previous GlazeWM config: " +
          $_.Exception.Message
        )
      }
    }
    if ($daemonWasRunning) {
      try {
        $restoredDaemonDeadline = (Get-Date).AddSeconds(
          $StartupTimeoutSeconds
        )
        do {
          $restoredDaemon = Get-GlazeHelperProcess `
            -ScriptPath $deployedDaemon
          if ($null -ne $restoredDaemon) {
            break
          }
          Start-Sleep -Milliseconds 250
        } while ((Get-Date) -lt $restoredDaemonDeadline)
        if ($null -eq $restoredDaemon) {
          [void](Start-HiddenPowerShellScript -ScriptPath $deployedDaemon)
        }
      } catch {
        Write-Warning (
          "Rollback could not restart the automatic tiling helper: " +
          $_.Exception.Message
        )
      }
    }
    if ($null -ne $zebarState -and $null -eq (Get-ZetshellZebarProcess)) {
      Start-ManagedZebar -ZebarState $zebarState
    }
  }
  Remove-Item `
    -LiteralPath $rollbackRoot `
    -Recurse `
    -Force `
    -ErrorAction SilentlyContinue
}
$state
