param(
  [string]$GlazeWMPath = (
    Join-Path $env:ProgramFiles "glzr.io\GlazeWM\cli\glazewm.exe"
  ),
  [ValidateRange(250, 10000)][int]$QuietPeriodMilliseconds = 1500
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$modulePath = Join-Path $PSScriptRoot "GlazeSurfaceDisplay.psm1"
Import-Module $modulePath -Force -ErrorAction Stop

function Invoke-SurfaceDisplaySyncSafely {
  try {
    Invoke-GlazeSurfaceWorkspaceSync -GlazeWMPath $GlazeWMPath | Out-Null
    return $true
  } catch {
    Write-Warning "Surface display synchronization failed: $($_.Exception.Message)"
    return $false
  }
}

$sourceIdentifier = "DotfilesSurfaceDisplaySettingsChanged"
$watcherMutex = [Threading.Mutex]::new(
  $false,
  "Local\DotfilesGlazeSurfaceDisplayWatcher"
)
$watcherMutexAcquired = $false
$subscription = $null
try {
  try {
    $watcherMutexAcquired = $watcherMutex.WaitOne(0)
  } catch [Threading.AbandonedMutexException] {
    $watcherMutexAcquired = $true
  }
  if (-not $watcherMutexAcquired) { return }

  $subscription = Register-ObjectEvent `
    -InputObject ([Microsoft.Win32.SystemEvents]) `
    -EventName DisplaySettingsChanged `
    -SourceIdentifier $sourceIdentifier
  $state = New-SurfaceDisplayDebounceState
  $retryAttemptsRemaining = 3
  if (-not (Invoke-SurfaceDisplaySyncSafely)) {
    $state = Update-SurfaceDisplayDebounceState `
      -State $state `
      -NowMilliseconds ([Environment]::TickCount64)
  }
  while ($true) {
    $event = Wait-Event -SourceIdentifier $sourceIdentifier -Timeout 1
    if ($null -ne $event) {
      Remove-Event -EventIdentifier $event.EventIdentifier -ErrorAction SilentlyContinue
      $state = Update-SurfaceDisplayDebounceState `
        -State $state `
        -NowMilliseconds ([Environment]::TickCount64)
      $retryAttemptsRemaining = 3
    }
    if (Test-SurfaceDisplayDebounceReady `
      -State $state `
      -NowMilliseconds ([Environment]::TickCount64) `
      -QuietPeriodMilliseconds $QuietPeriodMilliseconds
    ) {
      if (Invoke-SurfaceDisplaySyncSafely) {
        $state = New-SurfaceDisplayDebounceState
      } else {
        $retryAttemptsRemaining--
        if ($retryAttemptsRemaining -gt 0) {
          $state = Update-SurfaceDisplayDebounceState `
            -State $state `
            -NowMilliseconds ([Environment]::TickCount64)
        } else {
          $state = New-SurfaceDisplayDebounceState
        }
      }
    }
  }
} finally {
  if ($null -ne $subscription) {
    Unregister-Event `
      -SourceIdentifier $sourceIdentifier `
      -ErrorAction SilentlyContinue
    Get-Event -SourceIdentifier $sourceIdentifier -ErrorAction SilentlyContinue |
      Remove-Event -ErrorAction SilentlyContinue
  }
  if ($watcherMutexAcquired) { [void]$watcherMutex.ReleaseMutex() }
  $watcherMutex.Dispose()
}
