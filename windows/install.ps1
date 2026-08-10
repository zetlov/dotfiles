[CmdletBinding()]
param(
  [ValidateSet("Install", "Update")]
  [string]$Mode = "Install",

  [string[]]$Component,

  [switch]$AllowRollbackOnly = $false,

  [switch]$PlanOnly = $false,

  [switch]$AddKanataDefenderExclusion = $false
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$modulePath = Join-Path `
  $PSScriptRoot `
  "orchestrator\WindowsOrchestrator.psm1"

Import-Module $modulePath -Force -ErrorAction Stop
Invoke-WindowsComponentSelection @PSBoundParameters
