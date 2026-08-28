[CmdletBinding(DefaultParameterSetName = "Apply")]
param(
  [Parameter(Mandatory = $true, ParameterSetName = "Apply")]
  [ValidateSet("all", "left-center", "right-only")]
  [string]$Name,

  [Parameter(Mandatory = $true, ParameterSetName = "Recover")]
  [switch]$Recover,

  [Parameter(ParameterSetName = "Apply")]
  [switch]$ValidateOnly,

  [string]$InstallRoot = $PSScriptRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($env:OS -ne "Windows_NT") {
  throw "This script must run on Windows."
}

$modulePath = Join-Path $PSScriptRoot "MonitorProfiles.psm1"
Import-Module $modulePath -Force -ErrorAction Stop
$InstallRoot = Resolve-MonitorProfileInstallRoot -Path $InstallRoot

function Invoke-ManagedDesktopRefresh {
  $syncScript = Join-Path `
    $env:LOCALAPPDATA `
    "dotfiles\glazewm\Sync-GlazeMonitorLayout.ps1"
  if (Test-Path -LiteralPath $syncScript -PathType Leaf) {
    & $syncScript -RestartZebar | Out-Null
  }
}

if ($Recover) {
  $result = Invoke-MonitorProfileRollback `
    -InstallRoot $InstallRoot
  Invoke-ManagedDesktopRefresh
  $result
  return
}

$result = Invoke-MonitorProfile `
  -Name $Name `
  -InstallRoot $InstallRoot `
  -ValidateOnly:$ValidateOnly
if (-not $ValidateOnly) {
  Invoke-ManagedDesktopRefresh
}
$result
