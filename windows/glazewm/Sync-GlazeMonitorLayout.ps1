[CmdletBinding()]
param(
  [string]$GlazeWMPath = (
    Join-Path $env:ProgramFiles "glzr.io\GlazeWM\cli\glazewm.exe"
  ),

  [string]$ZebarPath = "",

  [switch]$RestartZebar
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($env:OS -ne "Windows_NT") {
  throw "This script must run on Windows."
}
if ([string]::IsNullOrWhiteSpace($ZebarPath)) {
  $zebarCommand = Get-Command "zebar.exe" -ErrorAction SilentlyContinue
  if ($null -eq $zebarCommand) {
    throw "Zebar executable was not found on PATH."
  }
  $ZebarPath = $zebarCommand.Source
}

$modulePath = Join-Path $PSScriptRoot "GlazeWMMonitorSync.psm1"
Import-Module $modulePath -Force -ErrorAction Stop

Invoke-GlazeMonitorProfileRefresh `
  -GlazeWMPath $GlazeWMPath `
  -ZebarPath $ZebarPath `
  -RestartZebar:$RestartZebar
