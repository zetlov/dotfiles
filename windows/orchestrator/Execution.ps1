function Invoke-WindowsComponentEntrypoint {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [object]$Component,

    [switch]$AddKanataDefenderExclusion = $false
  )

  $parameters = if (
    $AddKanataDefenderExclusion -and
    $Component.Name -eq "kanata" -and
    $Component.Mode -eq "Install"
  ) {
    @{ AddDefenderExclusion = $true }
  } else {
    @{}
  }

  & $Component.EntrypointPath @parameters
}

function Assert-WindowsComponentExecutionPreflight {
  param(
    [Parameter(Mandatory = $true)][object[]]$Plan,
    [Parameter(Mandatory = $true)][object[]]$Catalog,
    [Parameter(Mandatory = $true)][string]$WindowsRoot,
    [switch]$AllowRollbackOnly = $false
  )

  if ($env:OS -ne "Windows_NT") {
    throw "Windows component installation must run on Windows."
  }
  Assert-WindowsComponentPlan `
    -Plan $Plan `
    -Catalog $Catalog `
    -WindowsRoot $WindowsRoot
  Assert-WindowsSelectionPolicy `
    -Plan $Plan `
    -Catalog $Catalog `
    -AllowRollbackOnly:$AllowRollbackOnly
  Assert-WindowsRuntimeCompatibility -Plan $Plan -Catalog $Catalog
}

function Invoke-WindowsComponentPlan {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [object[]]$Plan,

    [Parameter(Mandatory = $true)]
    [object[]]$Catalog,

    [Parameter(Mandatory = $true)]
    [string]$WindowsRoot,

    [switch]$AllowRollbackOnly = $false,

    [switch]$AddKanataDefenderExclusion = $false
  )

  Assert-WindowsComponentExecutionPreflight `
    -Plan $Plan `
    -Catalog $Catalog `
    -WindowsRoot $WindowsRoot `
    -AllowRollbackOnly:$AllowRollbackOnly

  foreach ($component in $Plan) {
    try {
      $trustedPath = Assert-WindowsTrustedEntrypoint `
        -Entrypoint $component.Entrypoint `
        -WindowsRoot $WindowsRoot `
        -RequireLeaf
      $trustedComponent = $component.PSObject.Copy()
      $trustedComponent.EntrypointPath = $trustedPath
      if (
        $AddKanataDefenderExclusion -and
        $component.Name -eq "kanata" -and
        $component.Mode -eq "Install"
      ) {
        Invoke-WindowsComponentEntrypoint `
          -Component $trustedComponent `
          -AddKanataDefenderExclusion
      } else {
        Invoke-WindowsComponentEntrypoint -Component $trustedComponent
      }
    } catch {
      throw (
        "Windows component '$($component.Name)' failed: " +
        $_.Exception.Message
      )
    }
  }
}

function Invoke-WindowsComponentSelection {
  [CmdletBinding()]
  param(
    [ValidateSet("Install", "Update")]
    [string]$Mode = "Install",

    [string[]]$Component,

    [string[]]$AdditionalComponent,

    [switch]$AllowRollbackOnly = $false,

    [switch]$PlanOnly = $false,

    [switch]$Preflight = $false,

    [switch]$AddKanataDefenderExclusion = $false
  )

  $windowsRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
  if ($PlanOnly -and $Preflight) {
    throw "-PlanOnly and -Preflight cannot be used together."
  }
  $manifestPath = Join-Path $windowsRoot "components.json"
  $catalog = @(
    Import-WindowsComponentCatalog `
      -Path $manifestPath `
      -WindowsRoot $windowsRoot
  )
  if (
    $null -ne $Component -and
    $Component.Count -gt 0 -and
    $null -ne $AdditionalComponent -and
    $AdditionalComponent.Count -gt 0
  ) {
    throw "-Component and -AdditionalComponent cannot be used together."
  }
  $resolvedComponent = if (
    $null -ne $AdditionalComponent -and
    $AdditionalComponent.Count -gt 0
  ) {
    @(
      $catalog |
        Where-Object { $_.SelectionPolicy -eq "required" } |
        Sort-Object Order, Name |
        ForEach-Object { $_.Name }
    ) + @($AdditionalComponent)
  } else {
    $Component
  }
  $plan = @(
    Resolve-WindowsComponentPlan `
      -Catalog $catalog `
      -Mode $Mode `
      -Component $resolvedComponent `
      -AllowRollbackOnly:$AllowRollbackOnly `
      -WindowsRoot $windowsRoot
  )
  Assert-WindowsComponentPlan `
    -Plan $plan `
    -Catalog $catalog `
    -WindowsRoot $windowsRoot

  $hasKanataInstall = @(
    $plan |
      Where-Object { $_.Name -eq "kanata" -and $_.Mode -eq "Install" }
  ).Count -gt 0
  if ($AddKanataDefenderExclusion -and -not $hasKanataInstall) {
    throw (
      "-AddKanataDefenderExclusion requires Kanata in an Install plan."
    )
  }
  if ($PlanOnly) {
    return $plan
  }
  if ($Preflight) {
    Assert-WindowsComponentExecutionPreflight `
      -Plan $plan `
      -Catalog $catalog `
      -WindowsRoot $windowsRoot `
      -AllowRollbackOnly:$AllowRollbackOnly
    return $plan
  }

  Invoke-WindowsComponentPlan `
    -Plan $plan `
    -Catalog $catalog `
    -WindowsRoot $windowsRoot `
    -AllowRollbackOnly:$AllowRollbackOnly `
    -AddKanataDefenderExclusion:$AddKanataDefenderExclusion
}
