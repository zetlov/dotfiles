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
if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) {
  throw "GlazeWM layout module is missing: $modulePath"
}
Import-Module $modulePath -Force -ErrorAction Stop

$waitSeconds = [int]$config.managerWaitSeconds
$intervalMilliseconds = [int]$config.launchIntervalMilliseconds
if ($waitSeconds -lt 1 -or $waitSeconds -gt 300) {
  throw "managerWaitSeconds must be between 1 and 300."
}
if ($intervalMilliseconds -lt 0 -or $intervalMilliseconds -gt 10000) {
  throw "launchIntervalMilliseconds must be between 0 and 10000."
}

$applications = @($config.applications)
if ($applications.Count -eq 0) {
  throw "At least one startup application is required."
}

$seenProcesses = @{}
foreach ($app in $applications) {
  $processName = [string]$app.processName
  $startAppName = [string]$app.startAppName
  if ($processName -notmatch '^[A-Za-z0-9._ -]+$') {
    throw "Invalid startup process name: $processName"
  }
  if ([string]::IsNullOrWhiteSpace($startAppName)) {
    throw "A startup application has an empty Start Apps name."
  }

  $normalized = $processName.ToLowerInvariant()
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

$startApps = @(Get-StartApps)
$failures = @()
foreach ($app in $applications) {
  $processName = [string]$app.processName
  if (Get-Process -Name $processName -ErrorAction SilentlyContinue) {
    continue
  }

  $matches = @(
    $startApps | Where-Object { $_.Name -eq [string]$app.startAppName }
  )
  if ($matches.Count -ne 1) {
    $failures += [string]$app.name
    continue
  }

  try {
    Start-Process `
      -FilePath "explorer.exe" `
      -ArgumentList "shell:AppsFolder\$($matches[0].AppID)" |
      Out-Null
  } catch {
    $failures += [string]$app.name
  }

  if ($intervalMilliseconds -gt 0) {
    Start-Sleep -Milliseconds $intervalMilliseconds
  }
}

if ($failures.Count -gt 0) {
  $failedNames = @($failures | Sort-Object -Unique)
  throw "Could not start: $($failedNames -join ', ')"
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

[pscustomobject]@{
  CompletedAt = (Get-Date).ToString("o")
  ApplicationCount = $applications.Count
} | ConvertTo-Json | Set-Content -LiteralPath $statePath -Encoding UTF8
