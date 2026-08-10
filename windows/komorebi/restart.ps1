param(
  [string]$ConfigHome = $env:KOMOREBI_CONFIG_HOME
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Assert-KomorebiRollbackRestartSafe {
  [CmdletBinding()]
  param()

  try {
    $glazeProcesses = @(
      Get-Process -ErrorAction Stop |
        Where-Object { $_.ProcessName -ieq "glazewm" }
    )
  } catch {
    throw "Unable to inspect GlazeWM processes: $($_.Exception.Message)"
  }
  if ($glazeProcesses.Count -gt 0) {
    throw "GlazeWM is running; stop it before restarting Komorebi."
  }

  $runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
  try {
    $runState = Get-ItemProperty -LiteralPath $runKey -ErrorAction Stop
    $hasGlazeWMRunRegistration = (
      $null -ne $runState.PSObject.Properties["GlazeWM"]
    )
  } catch [System.Management.Automation.ItemNotFoundException] {
    return
  } catch {
    throw "Unable to inspect Windows Run registrations: $($_.Exception.Message)"
  }
  if ($hasGlazeWMRunRegistration) {
    throw (
      "GlazeWM automatic startup is enabled; disable it before restarting " +
      "Komorebi."
    )
  }
}

Assert-KomorebiRollbackRestartSafe

function Invoke-Komorebic {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [Parameter(Mandatory = $true)]
    [string[]]$Arguments
  )

  & $Path @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "komorebic $($Arguments -join ' ') failed with exit code $LASTEXITCODE."
  }
}

function Resolve-KomorebiConfigHome {
  param([Parameter(Mandatory = $true)][string]$Path)

  if ([string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
    throw "USERPROFILE is not set."
  }
  if ([string]::IsNullOrWhiteSpace($Path)) {
    throw "KOMOREBI_CONFIG_HOME is not set."
  }

  $candidate = [System.IO.Path]::GetFullPath($Path)
  $expected = [System.IO.Path]::GetFullPath(
    (Join-Path $env:USERPROFILE ".config\komorebi")
  )
  if (-not $candidate.Equals(
    $expected,
    [System.StringComparison]::OrdinalIgnoreCase
  )) {
    throw "Unexpected Komorebi config home: $candidate"
  }
  return $candidate
}

function Wait-KomorebiProcessSet {
  param(
    [Parameter(Mandatory = $true)][string[]]$Names,
    [ValidateRange(1, 60)][int]$TimeoutSeconds = 10,
    [ValidateRange(0, 10000)][int]$StableMilliseconds = 1000
  )

  $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
  $stableSince = $null
  do {
    $missing = @($Names | Where-Object {
      -not (Get-Process -Name $_ -ErrorAction SilentlyContinue)
    })
    if ($missing.Count -eq 0) {
      if ($null -eq $stableSince) {
        $stableSince = $stopwatch.Elapsed.TotalMilliseconds
      } elseif (
        $stopwatch.Elapsed.TotalMilliseconds - $stableSince -ge
        $StableMilliseconds
      ) {
        return
      }
    } else {
      $stableSince = $null
    }
    if ($stopwatch.Elapsed.TotalSeconds -ge $TimeoutSeconds) {
      throw "Timed out waiting for processes: $($missing -join ', ')"
    }
    Start-Sleep -Milliseconds 100
  } while ($true)
}

function Invoke-KomorebicJson {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [Parameter(Mandatory = $true)]
    [string[]]$Arguments
  )

  $lines = @(& $Path @Arguments)
  if ($LASTEXITCODE -ne 0) {
    throw "komorebic $($Arguments -join ' ') failed with exit code $LASTEXITCODE."
  }
  $json = $lines -join [Environment]::NewLine
  try {
    $value = $json | ConvertFrom-Json
  } catch {
    throw "komorebic $($Arguments -join ' ') returned invalid JSON."
  }
  if ($null -eq $value.PSObject.Properties["monitors"]) {
    throw "Komorebi state does not contain monitors."
  }

  return [pscustomobject]@{
    Json = $json
    Value = $value
  }
}

function Save-KomorebiStateSnapshot {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Json,

    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  $temporaryPath = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
  $encoding = New-Object System.Text.UTF8Encoding($false)
  try {
    [System.IO.File]::WriteAllText($temporaryPath, $Json, $encoding)
    Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
      Remove-Item -LiteralPath $temporaryPath -Force
    }
  }
}

function Get-KomorebiWorkspaceWindows {
  param([Parameter(Mandatory = $true)][object]$Workspace)

  $windows = @()
  foreach ($container in @($Workspace.containers.elements)) {
    $windows += @($container.windows.elements)
  }
  $windows += @($Workspace.floating_windows.elements)
  if ($null -ne $Workspace.maximized_window) {
    $windows += $Workspace.maximized_window
  }
  if ($null -ne $Workspace.monocle_container) {
    $windows += @($Workspace.monocle_container.windows.elements)
  }
  return $windows
}

function Get-KomorebiWindowPlacement {
  param([Parameter(Mandatory = $true)][object]$State)

  $placements = @{}
  $monitors = @($State.monitors.elements)
  for ($monitorIndex = 0; $monitorIndex -lt $monitors.Count; $monitorIndex++) {
    $workspaces = @($monitors[$monitorIndex].workspaces.elements)
    for ($workspaceIndex = 0; $workspaceIndex -lt $workspaces.Count; $workspaceIndex++) {
      foreach ($window in @(Get-KomorebiWorkspaceWindows $workspaces[$workspaceIndex])) {
        $placements[[string]$window.hwnd] = "$monitorIndex/$workspaceIndex"
      }
    }
  }
  return $placements
}

function Test-KomorebiWindowPlacementRestored {
  param(
    [Parameter(Mandatory = $true)][hashtable]$Expected,
    [Parameter(Mandatory = $true)][hashtable]$Actual
  )

  foreach ($handle in $Expected.Keys) {
    if (-not $Actual.ContainsKey($handle)) {
      return $false
    }
    if ($Actual[$handle] -ne $Expected[$handle]) {
      return $false
    }
  }
  return $true
}

function Wait-KomorebiProcessExit {
  param([ValidateRange(1, 60)][int]$TimeoutSeconds = 10)

  $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
  while (Get-Process -Name "komorebi" -ErrorAction SilentlyContinue) {
    if ($stopwatch.Elapsed.TotalSeconds -ge $TimeoutSeconds) {
      throw "Timed out waiting for Komorebi to stop gracefully."
    }
    Start-Sleep -Milliseconds 100
  }
}

$komorebicPath = Join-Path $env:ProgramFiles "komorebi\bin\komorebic.exe"
if (-not (Test-Path -LiteralPath $komorebicPath -PathType Leaf)) {
  throw "The official Komorebi executable is missing: $komorebicPath"
}
if (-not (Get-Process -Name "komorebi" -ErrorAction SilentlyContinue)) {
  throw "Komorebi is not running; use update-config.ps1 to start it."
}

$configHome = Resolve-KomorebiConfigHome -Path $ConfigHome
$env:KOMOREBI_CONFIG_HOME = $configHome
$env:WHKD_CONFIG_HOME = $configHome
$configPath = Join-Path $configHome "komorebi.json"
if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
  throw "Managed Komorebi configuration is missing: $configPath"
}
$statePath = Join-Path $env:TEMP "komorebi.state.json"

$snapshot = Invoke-KomorebicJson -Path $komorebicPath -Arguments @("state")
$expectedPlacements = Get-KomorebiWindowPlacement -State $snapshot.Value
Save-KomorebiStateSnapshot -Json $snapshot.Json -Path $statePath

Invoke-Komorebic `
  -Path $komorebicPath `
  -Arguments @("stop", "--whkd", "--bar", "--masir")
Wait-KomorebiProcessExit

Invoke-Komorebic `
  -Path $komorebicPath `
  -Arguments @("start", "-c", $configPath, "--whkd", "--bar")
Wait-KomorebiProcessSet `
  -Names @("komorebi", "whkd", "komorebi-bar") `
  -StableMilliseconds 1000

$restored = $false
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
do {
  $current = Invoke-KomorebicJson -Path $komorebicPath -Arguments @("state")
  $actualPlacements = Get-KomorebiWindowPlacement -State $current.Value
  $restored = Test-KomorebiWindowPlacementRestored `
    -Expected $expectedPlacements `
    -Actual $actualPlacements
  if (-not $restored) {
    Start-Sleep -Milliseconds 200
  }
} while (-not $restored -and $stopwatch.Elapsed.TotalSeconds -lt 10)

if (-not $restored) {
  throw "Komorebi restarted, but one or more window workspace placements were not restored."
}

Write-Host "Komorebi restarted with window workspace placements restored."
