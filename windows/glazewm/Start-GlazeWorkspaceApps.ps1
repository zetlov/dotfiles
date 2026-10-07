param(
  [string]$ConfigPath = (Join-Path $PSScriptRoot "startup-apps.json"),
  [string]$GlazeWMPath = (
    Join-Path $env:ProgramFiles "glzr.io\GlazeWM\cli\glazewm.exe"
  )
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$errorLogPath = Join-Path $PSScriptRoot "startup-apps-error.log"
$statePath = Join-Path $PSScriptRoot "startup-apps-state.json"
Remove-Item -LiteralPath $errorLogPath -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $statePath -Force -ErrorAction SilentlyContinue
trap {
  $_ | Out-String | Set-Content -LiteralPath $errorLogPath -Encoding UTF8
  exit 1
}

function Get-OptionalAppProperty {
  param(
    [Parameter(Mandatory = $true)][object]$Application,
    [Parameter(Mandatory = $true)][string]$Name
  )

  $property = $Application.PSObject.Properties[$Name]
  if ($null -eq $property) {
    return $null
  }
  return $property.Value
}

if ($env:OS -ne "Windows_NT") {
  throw "This startup launcher must run on Windows."
}
if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
  throw "GlazeWM startup configuration is missing: $ConfigPath"
}

try {
  $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
} catch {
  throw "Cannot parse GlazeWM startup configuration: $($_.Exception.Message)"
}

$modulePath = Join-Path $PSScriptRoot "GlazeWMAutoTile.psm1"
$monitorSyncModulePath = Join-Path $PSScriptRoot "GlazeWMMonitorSync.psm1"
foreach ($requiredModulePath in @($modulePath, $monitorSyncModulePath)) {
  if (-not (Test-Path -LiteralPath $requiredModulePath -PathType Leaf)) {
    throw "GlazeWM helper module is missing: $requiredModulePath"
  }
}
Import-Module $modulePath -Force -ErrorAction Stop
Import-Module $monitorSyncModulePath -Force -ErrorAction Stop

$waitSeconds = [int]$config.managerWaitSeconds
$intervalMilliseconds = [int]$config.launchIntervalMilliseconds
$workspacePlacementWaitSeconds = [int]$config.workspacePlacementWaitSeconds
if ($waitSeconds -lt 1 -or $waitSeconds -gt 300) {
  throw "managerWaitSeconds must be between 1 and 300."
}
if ($intervalMilliseconds -lt 0 -or $intervalMilliseconds -gt 10000) {
  throw "launchIntervalMilliseconds must be between 0 and 10000."
}
if (
  $workspacePlacementWaitSeconds -lt 1 -or
  $workspacePlacementWaitSeconds -gt 300
) {
  throw "workspacePlacementWaitSeconds must be between 1 and 300."
}

$applications = @($config.applications)
if ($applications.Count -eq 0) {
  throw "At least one startup application is required."
}

$seenProcesses = @{}
foreach ($app in $applications) {
  $processName = [string]$app.processName
  $launchType = [string](Get-OptionalAppProperty `
    -Application $app `
    -Name "launchType")
  if ([string]::IsNullOrWhiteSpace($launchType)) {
    $launchType = "start-app"
  }
  if ($processName -notmatch '^[A-Za-z0-9._ -]+$') {
    throw "Invalid startup process name: $processName"
  }
  if ($launchType -eq "executable") {
    $pathCandidates = @(Get-OptionalAppProperty `
      -Application $app `
      -Name "pathCandidates")
    if ($pathCandidates.Count -eq 0) {
      throw "A startup executable has no path candidates: $($app.name)"
    }
  } elseif ($launchType -eq "start-app") {
    $startAppName = [string](Get-OptionalAppProperty `
      -Application $app `
      -Name "startAppName")
    if ([string]::IsNullOrWhiteSpace($startAppName)) {
      throw "A startup application has an empty Start Apps name."
    }
  } else {
    throw "Unsupported launch type for $($app.name): $launchType"
  }
  if ($app.PSObject.Properties.Name -contains "startupWorkspace") {
    $startupWorkspace = [string](Get-OptionalAppProperty `
      -Application $app `
      -Name "startupWorkspace")
    if (
      [string]::IsNullOrWhiteSpace($startupWorkspace) -or
      $startupWorkspace -notmatch '^[A-Za-z0-9._ -]+$'
    ) {
      throw "Invalid startup workspace for $($app.name): $startupWorkspace"
    }
  }

  $processCommandLinePattern = [string](Get-OptionalAppProperty `
    -Application $app `
    -Name "processCommandLinePattern")
  $matchKey = $processName.ToLowerInvariant() + "|" + $processCommandLinePattern
  $normalized = $matchKey
  if ($seenProcesses.ContainsKey($normalized)) {
    throw "Duplicate startup process name: $processName"
  }
  $seenProcesses[$normalized] = $true
}

$deadline = (Get-Date).AddSeconds($waitSeconds)
while (
  -not (Get-Process -Name "glazewm" -ErrorAction SilentlyContinue) -and
  (Get-Date) -lt $deadline
) {
  Start-Sleep -Milliseconds 500
}
if (-not (Get-Process -Name "glazewm" -ErrorAction SilentlyContinue)) {
  throw "GlazeWM did not start within $waitSeconds seconds."
}

$safeRestartToken = [string]$env:DOTFILES_GLAZE_SAFE_RESTART
$safeRestartMarkerPath = if ($safeRestartToken -match '^[a-f0-9]{32}$') {
  Join-Path $PSScriptRoot "safe-restart-$safeRestartToken.pending"
} else {
  ""
}
if (
  -not [string]::IsNullOrWhiteSpace($safeRestartMarkerPath) -and
  (Test-Path -LiteralPath $safeRestartMarkerPath -PathType Leaf) -and
  (Get-Content -LiteralPath $safeRestartMarkerPath -Raw) -eq $safeRestartToken
) {
  Remove-Item -LiteralPath $safeRestartMarkerPath -Force
  [pscustomobject]@{
    CompletedAt = (Get-Date).ToString("o")
    ApplicationCount = 0
    WorkspaceSynchronized = $false
    SafeRestartDeferred = $true
  } | ConvertTo-Json | Set-Content -LiteralPath $statePath -Encoding UTF8
  exit 0
}

$monitorSyncScript = Join-Path $PSScriptRoot "Sync-GlazeMonitorLayout.ps1"
if (-not (Test-Path -LiteralPath $monitorSyncScript -PathType Leaf)) {
  throw "GlazeWM monitor sync script is missing: $monitorSyncScript"
}
$initialMonitorSyncError = ""
try {
  & $monitorSyncScript -RestartZebar | Out-Null
} catch {
  $initialMonitorSyncError = $_.Exception.Message
  Write-Warning (
    "Initial monitor and Zebar sync failed; continuing startup application " +
    "placement: $initialMonitorSyncError"
  )
}

$startApps = @(Get-StartApps)
$launchedApplications = @()
$failures = @()
foreach ($app in $applications) {
  $processName = [string]$app.processName
  try {
    $existing = @(Get-CimInstance Win32_Process -Filter "Name = '$processName.exe'" |
      Where-Object {
        $pattern = [string](Get-OptionalAppProperty `
          -Application $app `
          -Name "processCommandLinePattern")
        [string]::IsNullOrWhiteSpace($pattern) -or
          ([string]$_.CommandLine -match $pattern)
      })
    if ($existing.Count -eq 0) {
      $launchType = [string](Get-OptionalAppProperty `
        -Application $app `
        -Name "launchType")
      if ([string]::IsNullOrWhiteSpace($launchType)) {
        $launchType = "start-app"
      }
      if ($launchType -eq "executable") {
        $pathCandidates = @(Get-OptionalAppProperty `
          -Application $app `
          -Name "pathCandidates")
        $path = @($pathCandidates | ForEach-Object {
          [Environment]::ExpandEnvironmentVariables([string]$_)
        } | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1)
        if ($path.Count -ne 1) {
          throw "No executable candidate is installed."
        }
        $arguments = [string](Get-OptionalAppProperty `
          -Application $app `
          -Name "arguments")
        Start-Process -FilePath $path[0] -ArgumentList $arguments | Out-Null
      } else {
        $startAppName = [string](Get-OptionalAppProperty `
          -Application $app `
          -Name "startAppName")
        $matches = @(
          $startApps | Where-Object { $_.Name -eq $startAppName }
        )
        if ($matches.Count -ne 1) {
          throw "Start Apps entry is missing or ambiguous."
        }
        Start-Process `
          -FilePath "explorer.exe" `
          -ArgumentList "shell:AppsFolder\$($matches[0].AppID)" |
          Out-Null
      }
    }
  } catch {
    $failures += [string]$app.name
  }

  if ($intervalMilliseconds -gt 0) {
    Start-Sleep -Milliseconds $intervalMilliseconds
  }
  $launchedApplications += [pscustomobject]@{
    Config = $app
    ProcessId = 0
  }
}

if ($failures.Count -gt 0) {
  $failedNames = @($failures | Sort-Object -Unique)
  throw "Could not start: $($failedNames -join ', ')"
}

foreach ($entry in $launchedApplications) {
  $app = $entry.Config
  if (-not ($app.PSObject.Properties.Name -contains "startupWorkspace")) {
    continue
  }
  $processName = [string]$app.processName
  $processCommandLinePattern = [string](Get-OptionalAppProperty `
    -Application $app `
    -Name "processCommandLinePattern")
  if (-not [string]::IsNullOrWhiteSpace($processCommandLinePattern)) {
    $deadline = (Get-Date).AddSeconds($workspacePlacementWaitSeconds)
    do {
      $process = @(Get-CimInstance Win32_Process -Filter "Name = '$processName.exe'" |
        Where-Object {
          [string]$_.CommandLine -match $processCommandLinePattern
        } | Select-Object -First 1)
      if ($process.Count -eq 1) {
        $entry.ProcessId = [int]$process[0].ProcessId
        break
      }
      Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)
  }
  Invoke-GlazeStartupWorkspacePlacement `
    -GlazeWMPath $GlazeWMPath `
    -ProcessName ([string]$app.processName) `
    -ProcessId ([int]$entry.ProcessId) `
    -WorkspaceName ([string](Get-OptionalAppProperty `
      -Application $app `
      -Name "startupWorkspace")) `
    -WaitSeconds $workspacePlacementWaitSeconds
}

$workspaceGridWaitSeconds = [int]$config.workspaceGridWaitSeconds
if ($workspaceGridWaitSeconds -lt 1 -or $workspaceGridWaitSeconds -gt 300) {
  throw "workspaceGridWaitSeconds must be between 1 and 300."
}
foreach ($grid in @($config.workspaceGrids)) {
  $workspaceName = [string]$grid.workspaceName
  $processNames = @($grid.processNames | ForEach-Object { [string]$_ })
  if ([string]::IsNullOrWhiteSpace($workspaceName)) {
    throw "A workspace grid has an empty workspace name."
  }
  if ($processNames.Count -ne 4) {
    throw "Workspace grid $workspaceName must define exactly four processes."
  }
  Invoke-GlazeWorkspaceGrid `
    -GlazeWMPath $GlazeWMPath `
    -WorkspaceName $workspaceName `
    -ProcessNames $processNames `
    -WaitSeconds $workspaceGridWaitSeconds
}

# Startup app placement can activate a workspace on whichever monitor is
# focused at that moment. Reconcile only the workspace-to-monitor mapping after
# every placement has finished; this path intentionally does not touch Zebar.
Invoke-GlazeWorkspaceMonitorSync -GlazeWMPath $GlazeWMPath | Out-Null

[pscustomobject]@{
  CompletedAt = (Get-Date).ToString("o")
  ApplicationCount = $applications.Count
  WorkspaceSynchronized = $true
  InitialMonitorSyncError = $initialMonitorSyncError
} | ConvertTo-Json | Set-Content -LiteralPath $statePath -Encoding UTF8
