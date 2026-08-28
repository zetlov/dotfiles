Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

& (Join-Path $PSScriptRoot "Switch-MonitorProfile.ps1") -Name left-center
