param(
  [string]$GlazeWMPath = (
    Join-Path $env:ProgramFiles "glzr.io\GlazeWM\cli\glazewm.exe"
  )
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$modulePath = Join-Path $PSScriptRoot "GlazeWMAutoTile.psm1"
Import-Module $modulePath -Force -ErrorAction Stop

Start-GlazeAutoTile -GlazeWMPath $GlazeWMPath
