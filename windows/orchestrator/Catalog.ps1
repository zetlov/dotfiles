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
