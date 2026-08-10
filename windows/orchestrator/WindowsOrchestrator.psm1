Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Test-WindowsEntrypointPath {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Entrypoint,

    [Parameter(Mandatory = $true)]
    [string]$WindowsRoot
  )

  if (
    [string]::IsNullOrWhiteSpace($Entrypoint) -or
    [IO.Path]::IsPathRooted($Entrypoint) -or
    -not $Entrypoint.EndsWith(".ps1", [StringComparison]::OrdinalIgnoreCase)
  ) {
    return $false
  }

  try {
    $root = [IO.Path]::GetFullPath($WindowsRoot)
    $rootSeparators = [char[]]@(
      [IO.Path]::DirectorySeparatorChar,
      [IO.Path]::AltDirectorySeparatorChar
    )
    $rootPrefix = $root.TrimEnd($rootSeparators) +
      [IO.Path]::DirectorySeparatorChar
    $candidate = [IO.Path]::GetFullPath((Join-Path $root $Entrypoint))
  } catch {
    return $false
  }

  return $candidate.StartsWith(
    $rootPrefix,
    [StringComparison]::OrdinalIgnoreCase
  )
}

function Assert-WindowsTrustedEntrypoint {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Entrypoint,

    [Parameter(Mandatory = $true)]
    [string]$WindowsRoot,

    [switch]$RequireLeaf = $false
  )

  if (-not (Test-WindowsEntrypointPath $Entrypoint $WindowsRoot)) {
    throw (
      "Entrypoint must be a safe relative PowerShell script within the " +
      "Windows root: $Entrypoint"
    )
  }

  $currentPath = [IO.Path]::GetFullPath($WindowsRoot)
  foreach ($segment in @($Entrypoint -split '[\\/]')) {
    if ($segment -in @("", ".", "..")) {
      throw "Entrypoint contains an unsafe path segment: $Entrypoint"
    }
    $currentPath = Join-Path $currentPath $segment
    if (Test-Path -LiteralPath $currentPath) {
      $item = Get-Item -LiteralPath $currentPath -Force -ErrorAction Stop
      if (
        ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
      ) {
        throw "Entrypoint path contains a reparse point: $currentPath"
      }
    }
  }

  if (
    $RequireLeaf -and
    -not (Test-Path -LiteralPath $currentPath -PathType Leaf)
  ) {
    throw "Windows component entrypoint is missing: $currentPath"
  }

  return [IO.Path]::GetFullPath($currentPath)
}

function Get-RequiredProperty {
  param(
    [Parameter(Mandatory = $true)]
    [object]$InputObject,

    [Parameter(Mandatory = $true)]
    [string]$Name,

    [Parameter(Mandatory = $true)]
    [string]$Context
  )

  if ($null -eq $InputObject.PSObject.Properties[$Name]) {
    throw "$Context is missing the required '$Name' property."
  }
  return $InputObject.$Name
}

function Import-WindowsComponentCatalog {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [Parameter(Mandatory = $true)]
    [string]$WindowsRoot
  )

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "Windows component manifest not found: $Path"
  }

  try {
    $manifest = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
  } catch {
    throw "Invalid Windows component manifest '$Path': $($_.Exception.Message)"
  }

  if (
    $null -eq $manifest.PSObject.Properties["schemaVersion"] -or
    $manifest.schemaVersion -ne 1
  ) {
    throw "Unsupported Windows component manifest schema version."
  }
  if ($null -eq $manifest.PSObject.Properties["components"]) {
    throw "Windows component manifest is missing the components property."
  }
  if (@($manifest.components).Count -eq 0) {
    throw "Windows component manifest components must not be empty."
  }

  $catalog = @()
  $knownNames = @{}
  foreach ($definition in @($manifest.components)) {
    $context = "Windows component definition"
    $name = [string](Get-RequiredProperty $definition "name" $context)
    if ($name -notmatch '^[a-z][a-z0-9-]*$') {
      throw "Windows component name '$name' is invalid."
    }
    if ($knownNames.ContainsKey($name)) {
      throw "Windows component manifest contains duplicate component '$name'."
    }

    $lifecycle = [string](Get-RequiredProperty $definition "lifecycle" $name)
    if ($lifecycle -notin @("active", "shared", "rollback-only")) {
      throw "Windows component '$name' has an invalid lifecycle."
    }
    $selectionPolicy = [string](
      Get-RequiredProperty $definition "selectionPolicy" $name
    )
    if (
      $selectionPolicy -notin @(
        "required",
        "optional",
        "managed",
        "rollback-only"
      )
    ) {
      throw "Windows component '$name' has an invalid selection policy."
    }

    $order = Get-RequiredProperty $definition "order" $name
    if ($order -isnot [ValueType] -or [int]$order -ne $order) {
      throw "Windows component '$name' has an invalid order."
    }
    $managedBy = @(
      Get-RequiredProperty $definition "managedBy" $name
    )
    $conflictsWith = @(
      Get-RequiredProperty $definition "conflictsWith" $name
    )
    $requiresSelection = @(
      Get-RequiredProperty $definition "requiresSelection" $name
    )
    $entrypointDefinitions = Get-RequiredProperty `
      $definition `
      "entrypoints" `
      $name
    $entrypoints = @{}
    foreach ($modeName in @("install", "update")) {
      if ($null -ne $entrypointDefinitions.PSObject.Properties[$modeName]) {
        $entrypoint = [string]$entrypointDefinitions.$modeName
        try {
          [void](Assert-WindowsTrustedEntrypoint `
            -Entrypoint $entrypoint `
            -WindowsRoot $WindowsRoot `
            -RequireLeaf)
        } catch {
          throw "Windows component '$name': $($_.Exception.Message)"
        }
        $entrypoints[$modeName] = $entrypoint
      }
    }

    if (
      ($lifecycle -eq "rollback-only") -ne
      ($selectionPolicy -eq "rollback-only")
    ) {
      throw (
        "Windows component '$name' must use rollback-only lifecycle and " +
        "selection policy together."
      )
    }
    if ($selectionPolicy -eq "managed") {
      if ($managedBy.Count -eq 0) {
        throw "Managed Windows component '$name' requires at least one owner."
      }
      if ($entrypoints.Count -ne 0) {
        throw "Managed Windows component '$name' cannot expose entrypoints."
      }
    } else {
      foreach ($modeName in @("install", "update")) {
        if (-not $entrypoints.ContainsKey($modeName)) {
          throw "Windows component '$name' requires a $modeName entrypoint."
        }
      }
      if ($managedBy.Count -ne 0) {
        throw "Direct Windows component '$name' cannot declare an owner."
      }
    }

    $knownNames[$name] = $true
    $catalog += [PSCustomObject]@{
      Name = $name
      Lifecycle = $lifecycle
      SelectionPolicy = $selectionPolicy
      Order = [int]$order
      ManagedBy = $managedBy
      ConflictsWith = $conflictsWith
      RequiresSelection = $requiresSelection
      Entrypoints = $entrypoints
    }
  }

  $catalogByName = @{}
  foreach ($item in $catalog) {
    $catalogByName[$item.Name] = $item
  }
  foreach ($item in $catalog) {
    foreach ($ownerName in @($item.ManagedBy)) {
      if (
        [string]::IsNullOrWhiteSpace([string]$ownerName) -or
        -not $catalogByName.ContainsKey([string]$ownerName)
      ) {
        throw (
          "Windows component '$($item.Name)' references unknown owner " +
          "'$ownerName'."
        )
      }
      if ($item.Name -eq $ownerName) {
        throw "Windows component '$($item.Name)' cannot manage itself."
      }
    }
    foreach ($conflictName in @($item.ConflictsWith)) {
      if (
        [string]::IsNullOrWhiteSpace([string]$conflictName) -or
        -not $catalogByName.ContainsKey([string]$conflictName)
      ) {
        throw (
          "Windows component '$($item.Name)' references unknown conflict " +
          "'$conflictName'."
        )
      }
      if ($item.Name -eq $conflictName) {
        throw "Windows component '$($item.Name)' cannot conflict with itself."
      }
      $other = $catalogByName[[string]$conflictName]
      if (@($other.ConflictsWith) -notcontains $item.Name) {
        throw (
          "Windows component conflict '$($item.Name)' and '$conflictName' " +
          "must be reciprocal."
        )
      }
    }
    foreach ($requiredName in @($item.RequiresSelection)) {
      if (
        [string]::IsNullOrWhiteSpace([string]$requiredName) -or
        -not $catalogByName.ContainsKey([string]$requiredName)
      ) {
        throw (
          "Windows component '$($item.Name)' references unknown required " +
          "selection '$requiredName'."
        )
      }
      if ($item.Name -eq $requiredName) {
        throw "Windows component '$($item.Name)' cannot require itself."
      }
    }
  }

  return $catalog
}

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

function Test-WindowsRunValue {
  param([Parameter(Mandatory = $true)][string]$Name)

  $runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
  try {
    $state = Get-ItemProperty -LiteralPath $runKey -ErrorAction Stop
  } catch [System.Management.Automation.ItemNotFoundException] {
    return $false
  } catch {
    throw "Unable to inspect Windows Run registrations: $($_.Exception.Message)"
  }
  return $null -ne $state.PSObject.Properties[$Name]
}

function Test-KomorebiStartupShortcut {
  $startupShortcut = Join-Path `
    ([Environment]::GetFolderPath("Startup")) `
    "komorebi.lnk"
  return Test-Path -LiteralPath $startupShortcut -PathType Leaf
}

function Get-RollbackAutostartTasks {
  if ($null -eq (Get-Command -Name "Get-ScheduledTask" -ErrorAction SilentlyContinue)) {
    throw "Get-ScheduledTask is required for Windows runtime preflight."
  }
  try {
    $allTasks = @(Get-ScheduledTask -ErrorAction Stop)
  } catch {
    throw "Unable to inspect scheduled tasks: $($_.Exception.Message)"
  }
  return @(
    $allTasks | Where-Object { $_.TaskName -like "Dotfiles App - *" }
  )
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

function Assert-WindowsRuntimeCompatibility {
  param(
    [Parameter(Mandatory = $true)][object[]]$Plan,
    [Parameter(Mandatory = $true)][object[]]$Catalog
  )

  $selectedNames = @($Plan | ForEach-Object { $_.Name })
  $catalogByName = @{}
  foreach ($item in $Catalog) {
    $catalogByName[[string]$item.Name] = $item
  }
  $selectsRollback = @(
    $selectedNames |
      Where-Object { $catalogByName[[string]$_].Lifecycle -eq "rollback-only" }
  ).Count -gt 0
  if ($selectsRollback) {
    $glazeProcesses = @(
      Get-Process -Name "glazewm" -ErrorAction SilentlyContinue
    )
    if ($glazeProcesses.Count -gt 0) {
      throw "GlazeWM is running; stop it before applying rollback components."
    }
    if (Test-WindowsRunValue -Name "GlazeWM") {
      throw (
        "GlazeWM automatic startup is enabled; disable it before applying " +
        "rollback components."
      )
    }
  }

  if ($selectedNames -contains "glazewm") {
    $komorebiProcesses = @(
      Get-Process `
        -Name @("komorebi", "whkd", "komorebi-bar", "masir") `
        -ErrorAction SilentlyContinue
    )
    if ($komorebiProcesses.Count -gt 0) {
      throw "Komorebi rollback processes are running; stop them first."
    }

    if (Test-KomorebiStartupShortcut) {
      throw "Komorebi automatic startup is enabled."
    }

    $rollbackTasks = @(Get-RollbackAutostartTasks)
    if ($rollbackTasks.Count -gt 0) {
      throw "Rollback-only app autostart tasks are still registered."
    }
  }
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

    [switch]$AllowRollbackOnly = $false,

    [switch]$PlanOnly = $false,

    [switch]$AddKanataDefenderExclusion = $false
  )

  $windowsRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
  $manifestPath = Join-Path $windowsRoot "components.json"
  $catalog = @(
    Import-WindowsComponentCatalog `
      -Path $manifestPath `
      -WindowsRoot $windowsRoot
  )
  $plan = @(
    Resolve-WindowsComponentPlan `
      -Catalog $catalog `
      -Mode $Mode `
      -Component $Component `
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
  if ($env:OS -ne "Windows_NT") {
    throw "Windows component installation must run on Windows."
  }

  Invoke-WindowsComponentPlan `
    -Plan $plan `
    -Catalog $catalog `
    -WindowsRoot $windowsRoot `
    -AllowRollbackOnly:$AllowRollbackOnly `
    -AddKanataDefenderExclusion:$AddKanataDefenderExclusion
}

Export-ModuleMember -Function @(
  "Import-WindowsComponentCatalog",
  "Resolve-WindowsComponentPlan",
  "Assert-WindowsComponentPlan",
  "Invoke-WindowsComponentSelection"
)
