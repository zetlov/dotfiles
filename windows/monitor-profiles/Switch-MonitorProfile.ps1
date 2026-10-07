[CmdletBinding(DefaultParameterSetName = "Apply")]
param(
  [Parameter(Mandatory = $true, ParameterSetName = "Apply")]
  [ValidateSet("all", "left-center", "right-only")]
  [string]$Name,

  [Parameter(Mandatory = $true, ParameterSetName = "Recover")]
  [switch]$Recover,

  [Parameter(ParameterSetName = "Apply")]
  [switch]$ValidateOnly,

  [string]$InstallRoot = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($env:OS -ne "Windows_NT") {
  throw "This script must run on Windows."
}

$modulePath = Join-Path $PSScriptRoot "MonitorProfiles.psm1"
Import-Module $modulePath -Force -ErrorAction Stop
if ([string]::IsNullOrWhiteSpace($InstallRoot)) {
  $InstallRoot = $PSScriptRoot
}
$InstallRoot = Resolve-MonitorProfileInstallRoot -Path $InstallRoot

$glazeRuntimeRoot = Join-Path $env:LOCALAPPDATA "dotfiles\glazewm"
$glazeModulePath = Join-Path $glazeRuntimeRoot "GlazeWMMonitorSync.psm1"
$glazeSafeRestartModulePath = Join-Path `
  $glazeRuntimeRoot `
  "GlazeWMSafeRestart.psm1"
$glazeCliPath = Join-Path $env:ProgramFiles "glzr.io\GlazeWM\cli\glazewm.exe"
$glazeManagerPath = Join-Path $env:ProgramFiles "glzr.io\GlazeWM\glazewm.exe"
$glazeConfigPath = Join-Path $env:USERPROFILE ".glzr\glazewm\config.yaml"

function Test-ManagedGlazeActive {
  if (-not (Test-Path -LiteralPath $glazeCliPath -PathType Leaf)) {
    return $false
  }
  & $glazeCliPath query app-metadata 2>$null | Out-Null
  return $LASTEXITCODE -eq 0
}

function Get-ActiveWindowsMonitorCount {
  Add-Type -AssemblyName System.Windows.Forms
  return @([System.Windows.Forms.Screen]::AllScreens).Count
}

function Set-ManagedGlazeWorkspaceBindings {
  param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("all", "left-center", "right-only")]
    [string]$ProfileName
  )

  if (
    -not (Test-Path -LiteralPath $glazeModulePath -PathType Leaf) -or
    -not (Test-Path -LiteralPath $glazeCliPath -PathType Leaf)
  ) {
    return
  }
  Import-Module $glazeModulePath -Force -ErrorAction Stop
  Set-GlazeWorkspaceBindingsForProfile `
    -GlazeWMPath $glazeCliPath `
    -ProfileName $ProfileName |
    Out-Null
}

function Invoke-ManagedDesktopRefresh {
  $syncScript = Join-Path `
    $env:LOCALAPPDATA `
    "dotfiles\glazewm\Sync-GlazeMonitorLayout.ps1"
  if (Test-Path -LiteralPath $syncScript -PathType Leaf) {
    & $syncScript `
      -RestartZebar `
      -AllowZebarWidgetRelaunch |
      Out-Null
  }
}

$profileMutex = New-Object System.Threading.Mutex `
  -ArgumentList $false, "Local\DotfilesMonitorProfileSwitch"
$mutexAcquired = $false
try {
  try {
    $mutexAcquired = $profileMutex.WaitOne([TimeSpan]::FromSeconds(30))
  } catch [Threading.AbandonedMutexException] {
    $mutexAcquired = $true
  }
  if (-not $mutexAcquired) {
    throw "Another monitor profile switch is still running."
  }

  if ($Recover) {
    $result = Invoke-MonitorProfileRollback `
      -InstallRoot $InstallRoot
    Invoke-ManagedDesktopRefresh
    $result
    return
  }

  if ($ValidateOnly) {
    $result = Invoke-MonitorProfile `
      -Name $Name `
      -InstallRoot $InstallRoot `
      -ValidateOnly
  } else {
    $currentMonitorCount = Get-ActiveWindowsMonitorCount
    $targetMonitorCount = switch ($Name) {
      "all" { 3; break }
      "left-center" { 2; break }
      "right-only" { 1; break }
    }
    $requiresSafeExpansion = (
      $currentMonitorCount -eq 1 -and
      $targetMonitorCount -gt 1
    )

    if ($requiresSafeExpansion -and (Test-ManagedGlazeActive)) {
      $requiredPaths = @(
        $glazeSafeRestartModulePath,
        $glazeModulePath,
        $glazeManagerPath,
        $glazeConfigPath
      )
      $missingPaths = @($requiredPaths | Where-Object {
        -not (Test-Path -LiteralPath $_ -PathType Leaf)
      })
      if ($missingPaths.Count -gt 0) {
        throw (
          "Safe GlazeWM expansion support is missing: " +
          ($missingPaths -join ", ")
        )
      }
      Import-Module $glazeSafeRestartModulePath -Force -ErrorAction Stop
      if (-not (Test-GlazeMonitorExpansion `
        -CurrentMonitorCount $currentMonitorCount `
        -ProfileName $Name
      )) {
        throw "GlazeWM safe expansion classification was inconsistent."
      }
      $profileName = $Name
      $profileInstallRoot = $InstallRoot
      $applyProfile = {
        Invoke-MonitorProfile `
          -Name $profileName `
          -InstallRoot $profileInstallRoot
      }.GetNewClosure()
      $result = Invoke-GlazeSafeMonitorExpansion `
        -GlazeWMPath $glazeCliPath `
        -ManagerPath $glazeManagerPath `
        -ConfigPath $glazeConfigPath `
        -MonitorSyncModulePath $glazeModulePath `
        -ApplyProfile $applyProfile
    } else {
      Set-ManagedGlazeWorkspaceBindings -ProfileName $Name
      $result = Invoke-MonitorProfile `
        -Name $Name `
        -InstallRoot $InstallRoot
    }
  }
  if (-not $ValidateOnly) {
    Invoke-ManagedDesktopRefresh
  }
  $result
} finally {
  if ($mutexAcquired) {
    $profileMutex.ReleaseMutex()
  }
  $profileMutex.Dispose()
}
