function Resolve-WindowsComponentPlan {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [object[]]$Catalog,

    [Parameter(Mandatory = $true)]
    [ValidateSet("Install", "Update")]
    [string]$Mode,

    [string[]]$Component,

    [switch]$AllowRollbackOnly = $false,

    [Parameter(Mandatory = $true)]
    [string]$WindowsRoot
  )

  $catalogByName = @{}
  foreach ($item in $Catalog) {
    $catalogByName[[string]$item.Name] = $item
  }

  $selectedNames = if ($null -eq $Component -or $Component.Count -eq 0) {
    @(
      $Catalog |
        Where-Object { $_.SelectionPolicy -eq "required" } |
        ForEach-Object { $_.Name }
    )
  } else {
    $seen = @{}
    foreach ($requestedName in $Component) {
      if ([string]::IsNullOrWhiteSpace($requestedName)) {
        throw "Unknown Windows component: '$requestedName'."
      }
      if ($seen.ContainsKey($requestedName)) {
        throw "Windows component selection contains duplicate '$requestedName'."
      }
      $seen[$requestedName] = $true
    }
    @($Component)
  }

  $selected = @()
  foreach ($name in $selectedNames) {
    if (-not $catalogByName.ContainsKey($name)) {
      throw "Unknown Windows component: '$name'."
    }
    $item = $catalogByName[$name]
    if ($item.SelectionPolicy -eq "managed") {
      $owners = @($item.ManagedBy) -join ", "
      throw "Windows component '$name' is managed by: $owners."
    }
    if (
      $item.Lifecycle -eq "rollback-only" -and
      -not $AllowRollbackOnly
    ) {
      throw "Windows component '$name' requires -AllowRollbackOnly."
    }
    $selected += $item
  }

  $selectedNameSet = @{}
  foreach ($item in $selected) {
    $selectedNameSet[$item.Name] = $true
  }
  foreach ($item in $selected) {
    foreach ($conflictName in @($item.ConflictsWith)) {
      if ($selectedNameSet.ContainsKey([string]$conflictName)) {
        throw (
          "Windows component conflict: '$($item.Name)' cannot be selected " +
          "with '$conflictName'."
        )
      }
    }
    foreach ($requiredName in @($item.RequiresSelection)) {
      if (-not $selectedNameSet.ContainsKey([string]$requiredName)) {
        throw (
          "Windows component '$($item.Name)' requires selection of " +
          "'$requiredName'."
        )
      }
    }
  }

  $modeKey = $Mode.ToLowerInvariant()
  $plan = foreach ($item in ($selected | Sort-Object Order, Name)) {
    if (-not $item.Entrypoints.ContainsKey($modeKey)) {
      throw "Windows component '$($item.Name)' has no $Mode entrypoint."
    }
    $entrypoint = [string]$item.Entrypoints[$modeKey]
    [PSCustomObject]@{
      Name = $item.Name
      Mode = $Mode
      Entrypoint = $entrypoint
      EntrypointPath = [IO.Path]::GetFullPath(
        (Join-Path $WindowsRoot $entrypoint)
      )
      Order = $item.Order
      Lifecycle = $item.Lifecycle
      SelectionPolicy = $item.SelectionPolicy
    }
  }

  return @($plan)
}

function Assert-WindowsComponentPlan {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [object[]]$Plan,

    [Parameter(Mandatory = $true)]
    [object[]]$Catalog,

    [Parameter(Mandatory = $true)]
    [string]$WindowsRoot
  )

  $catalogByName = @{}
  foreach ($item in $Catalog) {
    $catalogByName[[string]$item.Name] = $item
  }

  $seenNames = @{}
  foreach ($component in $Plan) {
    foreach ($propertyName in @("Name", "Mode", "Entrypoint", "EntrypointPath")) {
      if ($null -eq $component.PSObject.Properties[$propertyName]) {
        throw "Windows component plan is missing '$propertyName'."
      }
    }

    $name = [string]$component.Name
    if ($seenNames.ContainsKey($name)) {
      throw "Windows component plan contains duplicate '$name'."
    }
    $seenNames[$name] = $true
    if (-not $catalogByName.ContainsKey($name)) {
      throw "Windows component plan '$name' does not match the catalog."
    }

    $catalogItem = $catalogByName[$name]
    $mode = [string]$component.Mode
    if ($mode -notin @("Install", "Update")) {
      throw "Windows component plan '$name' has an invalid mode."
    }
    $modeKey = $mode.ToLowerInvariant()
    if (-not $catalogItem.Entrypoints.ContainsKey($modeKey)) {
      throw "Windows component plan '$name' does not match the catalog."
    }

    $expectedEntrypoint = [string]$catalogItem.Entrypoints[$modeKey]
    $expectedPath = Assert-WindowsTrustedEntrypoint `
      -Entrypoint $expectedEntrypoint `
      -WindowsRoot $WindowsRoot `
      -RequireLeaf
    $actualPath = try {
      [IO.Path]::GetFullPath([string]$component.EntrypointPath)
    } catch {
      ""
    }
    if (
      -not ([string]$component.Entrypoint).Equals(
        $expectedEntrypoint,
        [StringComparison]::Ordinal
      ) -or
      -not $actualPath.Equals(
        $expectedPath,
        [StringComparison]::Ordinal
      )
    ) {
      throw (
        "Windows component plan '$name' entrypoint does not match the " +
        "catalog."
      )
    }
  }

  $actualOrder = @($Plan | ForEach-Object { $_.Name }) -join "`n"
  $expectedOrder = @(
    $Plan |
      Sort-Object {
        $catalogByName[[string]$_.Name].Order
      }, Name |
      ForEach-Object { $_.Name }
  ) -join "`n"
  if ($actualOrder -ne $expectedOrder) {
    throw "Windows component plan is not in canonical order."
  }
}

function Assert-WindowsSelectionPolicy {
  param(
    [Parameter(Mandatory = $true)][object[]]$Plan,
    [Parameter(Mandatory = $true)][object[]]$Catalog,
    [switch]$AllowRollbackOnly = $false
  )

  $catalogByName = @{}
  foreach ($item in $Catalog) {
    $catalogByName[[string]$item.Name] = $item
  }
  $selectedNames = @{}
  foreach ($component in $Plan) {
    $selectedNames[[string]$component.Name] = $true
  }

  foreach ($component in $Plan) {
    $catalogItem = $catalogByName[[string]$component.Name]
    if (
      $catalogItem.Lifecycle -eq "rollback-only" -and
      -not $AllowRollbackOnly
    ) {
      throw (
        "Windows component '$($component.Name)' requires " +
        "-AllowRollbackOnly."
      )
    }
    foreach ($conflictName in @($catalogItem.ConflictsWith)) {
      if ($selectedNames.ContainsKey([string]$conflictName)) {
        throw (
          "Windows component conflict: '$($component.Name)' cannot be " +
          "selected with '$conflictName'."
        )
      }
    }
    foreach ($requiredName in @($catalogItem.RequiresSelection)) {
      if (-not $selectedNames.ContainsKey([string]$requiredName)) {
        throw (
          "Windows component '$($component.Name)' requires selection of " +
          "'$requiredName'."
        )
      }
    }
  }
}
