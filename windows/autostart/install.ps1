[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$rollbackSafetyModule = Join-Path $PSScriptRoot "..\rollback\RollbackSafety.psm1"
Import-Module $rollbackSafetyModule -Force -ErrorAction Stop
Assert-GlazeWMInactive

$modulePath = Join-Path $PSScriptRoot "AppAutostart.psm1"
$configPath = Join-Path $PSScriptRoot "apps.json"

Import-Module $modulePath -Force -ErrorAction Stop
Install-AppAutostartTasks -ConfigPath $configPath

Write-Host "Windows app autostart tasks are installed."
