[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$modulePath = Join-Path $PSScriptRoot "AppAutostart.psm1"

Import-Module $modulePath -Force
Uninstall-AppAutostartTasks

Write-Host "Windows app autostart tasks are removed."
