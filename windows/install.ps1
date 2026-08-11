[CmdletBinding()]
param(
  [ValidateSet("Install", "Update")]
  [string]$Mode = "Install",

  [string[]]$Component,

  [string]$ComponentCsv,

  [string]$AdditionalComponentCsv,

  [switch]$AllowRollbackOnly = $false,

  [switch]$PlanOnly = $false,

  [switch]$Preflight = $false,

  [switch]$ListComponents = $false,

  [switch]$AddKanataDefenderExclusion = $false
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$modulePath = Join-Path `
  $PSScriptRoot `
  "orchestrator\WindowsOrchestrator.psm1"

Import-Module $modulePath -Force -ErrorAction Stop

if ($ListComponents) {
  $conflictingOptions = @(
    "Mode",
    "Component",
    "ComponentCsv",
    "AdditionalComponentCsv",
    "AllowRollbackOnly",
    "PlanOnly",
    "Preflight",
    "AddKanataDefenderExclusion"
  ) | Where-Object { $PSBoundParameters.ContainsKey($_) }
  if ($conflictingOptions.Count -gt 0) {
    throw (
      "-ListComponents cannot be combined with execution options: " +
      ($conflictingOptions -join ", ")
    )
  }

  $manifestPath = Join-Path $PSScriptRoot "components.json"
  Import-WindowsComponentCatalog `
    -Path $manifestPath `
    -WindowsRoot $PSScriptRoot |
    Sort-Object Order, Name |
    Select-Object `
      Name, `
      Lifecycle, `
      SelectionPolicy, `
      Order, `
      ManagedBy, `
      ConflictsWith, `
      RequiresSelection
  return
}

if (
  $PSBoundParameters.ContainsKey("AdditionalComponentCsv") -and
  (
    $PSBoundParameters.ContainsKey("Component") -or
    $PSBoundParameters.ContainsKey("ComponentCsv")
  )
) {
  throw (
    "-AdditionalComponentCsv cannot be used with -Component or " +
    "-ComponentCsv."
  )
}
if (
  $PSBoundParameters.ContainsKey("ComponentCsv") -and
  $PSBoundParameters.ContainsKey("Component")
) {
  throw "-Component and -ComponentCsv cannot be used together."
}
foreach ($csvParameter in @(
  @{ Name = "ComponentCsv"; Value = $ComponentCsv },
  @{ Name = "AdditionalComponentCsv"; Value = $AdditionalComponentCsv }
)) {
  if (-not $PSBoundParameters.ContainsKey($csvParameter.Name)) {
    continue
  }
  if (
    [string]::IsNullOrWhiteSpace($csvParameter.Value) -or
    $csvParameter.Value -cnotmatch `
      '^[a-z][a-z0-9-]*(,[a-z][a-z0-9-]*)*$'
  ) {
    throw (
      "-$($csvParameter.Name) must contain exact comma-separated lower-case " +
      "component names."
    )
  }
}

$resolvedComponent = if ($PSBoundParameters.ContainsKey("ComponentCsv")) {
  @($ComponentCsv.Split([char]","))
} else {
  $Component
}
$resolvedAdditionalComponent = if (
  $PSBoundParameters.ContainsKey("AdditionalComponentCsv")
) {
  @($AdditionalComponentCsv.Split([char]","))
} else {
  $null
}
$invokeParameters = @{
  Mode = $Mode
  Component = $resolvedComponent
  AdditionalComponent = $resolvedAdditionalComponent
  AllowRollbackOnly = $AllowRollbackOnly
  PlanOnly = $PlanOnly
  Preflight = $Preflight
  AddKanataDefenderExclusion = $AddKanataDefenderExclusion
}

Invoke-WindowsComponentSelection @invokeParameters
