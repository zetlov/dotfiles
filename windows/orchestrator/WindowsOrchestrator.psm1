Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "Catalog.ps1")
. (Join-Path $PSScriptRoot "Planning.ps1")
. (Join-Path $PSScriptRoot "Runtime.ps1")
. (Join-Path $PSScriptRoot "Execution.ps1")

Export-ModuleMember -Function @(
  "Import-WindowsComponentCatalog",
  "Resolve-WindowsComponentPlan",
  "Assert-WindowsComponentPlan",
  "Invoke-WindowsComponentSelection"
)
