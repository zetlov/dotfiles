[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$modulePath = Join-Path $PSScriptRoot "AppAutostart.psm1"
$configPath = Join-Path $PSScriptRoot "apps.json"

Import-Module $modulePath -Force
Install-AppAutostartTasks -ConfigPath $configPath

Write-Host "Windows app autostart tasks are installed."
