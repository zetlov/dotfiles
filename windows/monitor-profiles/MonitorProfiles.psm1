Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:MonitorRoles = @("left", "center", "right")

function Get-DisplayConfigReleaseSpec {
  [CmdletBinding()]
  param()

  [pscustomobject]@{
    Version = "6.0.0"
    Uri = [uri]"https://www.powershellgallery.com/api/v2/package/DisplayConfig/6.0.0"
    Sha256 = "816c17b0be5678197b0dc8c7ebd898f5f4cfdab1fe0ec768c7c25bd66a45f879"
  }
}

function Assert-MonitorProfileFileHash {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-fA-F0-9]{64}$')]
    [string]$ExpectedSha256
  )

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "Dependency package not found: $Path"
  }
  $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
  if (-not $actual.Equals($ExpectedSha256, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Dependency package SHA-256 mismatch."
  }
}

function Get-MonitorProfileCatalog {
  [CmdletBinding()]
  param()

  @(
    [pscustomobject]@{ Name = "all"; FileName = "all.clixml" },
    [pscustomobject]@{ Name = "left-center"; FileName = "left-center.clixml" },
    [pscustomobject]@{ Name = "right-only"; FileName = "right-only.clixml" }
  )
}

function Resolve-MonitorProfileFileName {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string]$Name
  )

  $match = @(Get-MonitorProfileCatalog | Where-Object Name -CEQ $Name)
  if ($match.Count -ne 1) {
    throw "Unknown monitor profile: $Name"
  }
  return $match[0].FileName
}

function Resolve-MonitorProfileInstallRoot {
  [CmdletBinding()]
  param(
    [string]$Path = (
      Join-Path $env:LOCALAPPDATA "dotfiles\monitor-profiles"
    )
  )

  $expected = [IO.Path]::GetFullPath(
    (Join-Path $env:LOCALAPPDATA "dotfiles\monitor-profiles")
  )
  $resolved = [IO.Path]::GetFullPath($Path)
  if (-not $resolved.Equals($expected, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Monitor profiles must be installed at: $expected"
  }
  return $resolved
}

function New-MonitorDisplayDefinition {
  param(
    [string]$Role,
    [bool]$Active,
    [bool]$Primary,
    [int]$X,
    [int]$Y,
    [int]$Width,
    [int]$Height
  )

  [pscustomobject]@{
    Role = $Role
    Active = $Active
    Primary = $Primary
    X = $X
    Y = $Y
    Width = $Width
    Height = $Height
  }
}

function Get-MonitorProfileDefinition {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("all", "left-center", "right-only")]
    [string]$Name
  )

  $leftActive = $Name -ne "right-only"
  $centerActive = $Name -ne "right-only"
  $rightActive = $Name -ne "left-center"
  $rightPrimary = $Name -eq "right-only"
  $rightX = if ($rightPrimary) { 0 } else { 3840 }
  $rightY = if ($rightPrimary) { 0 } else { 430 }

  [pscustomobject]@{
    Name = $Name
    Displays = @(
      New-MonitorDisplayDefinition "left" $leftActive $false -1920 495 1920 1080
      New-MonitorDisplayDefinition "center" $centerActive (-not $rightPrimary) 0 0 3840 2160
      New-MonitorDisplayDefinition "right" $rightActive $rightPrimary $rightX $rightY 1920 1080
    )
  }
}


function Resolve-MonitorRoleMap {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [object[]]$ConfiguredMonitors,

    [Parameter(Mandatory = $true)]
    [object[]]$Inventory
  )

  $resolved = @{}
  foreach ($configured in $ConfiguredMonitors) {
    $role = [string]$configured.Role
    $serial = [string]$configured.Serial
    $matches = @($Inventory | Where-Object { [string]$_.Serial -ieq $serial })
    if ($matches.Count -eq 0) {
      throw "Configured monitor is not connected: $role ($serial)"
    }
    if ($matches.Count -gt 1) {
      throw "Monitor identity is ambiguous: $role ($serial)"
    }
    $resolved[$role] = $matches[0]
  }
  return $resolved
}

function Compare-MonitorProfileState {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [object[]]$Expected,

    [Parameter(Mandatory = $true)]
    [object[]]$Actual
  )

  $problems = [Collections.Generic.List[string]]::new()
  foreach ($wanted in $Expected) {
    $serial = [string]$wanted.Serial
    $matches = @($Actual | Where-Object { [string]$_.Serial -ieq $serial })
    if ($matches.Count -ne 1) {
      $problems.Add("$($wanted.Role) identity mismatch for serial $serial")
      continue
    }
    $live = $matches[0]
    if ([bool]$live.Active -ne [bool]$wanted.Active) {
      $problems.Add("$($wanted.Role) active state mismatch")
      continue
    }
    if ([bool]$live.Primary -ne [bool]$wanted.Primary) {
      $problems.Add("$($wanted.Role) primary state mismatch")
    }
    if (-not [bool]$wanted.Active) {
      continue
    }
    if ([int]$live.X -ne [int]$wanted.X -or [int]$live.Y -ne [int]$wanted.Y) {
      $problems.Add("$($wanted.Role) position mismatch")
    }
    if (
      [int]$live.Width -ne [int]$wanted.Width -or
      [int]$live.Height -ne [int]$wanted.Height
    ) {
      $problems.Add("$($wanted.Role) resolution mismatch")
    }
  }

  [pscustomobject]@{
    Succeeded = $problems.Count -eq 0
    Problems = @($problems)
  }
}

function Import-MonitorProfileDependency {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string]$InstallRoot
  )

  $spec = Get-DisplayConfigReleaseSpec
  $manifest = Join-Path $InstallRoot (
    "dependencies\DisplayConfig\$($spec.Version)\DisplayConfig.psd1"
  )
  if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) {
    throw "DisplayConfig dependency is not installed: $manifest"
  }
  Import-Module $manifest -Force -ErrorAction Stop
}

function Get-MonitorInventory {
  [CmdletBinding()]
  param(
    [object]$DisplayConfig
  )

  $config = $DisplayConfig
  if ($null -eq $config) {
    $config = Get-DisplayConfig
  }
  foreach ($display in @(Get-DisplayInfo -DisplayConfig $config)) {
    $serial = if ($null -eq $display.EdidData) {
      ""
    } else {
      [string]$display.EdidData.SerialNumber
    }
    [pscustomobject]@{
      DisplayId = [uint32]$display.DisplayId
      DisplayName = [string]$display.DisplayName
      Serial = $serial
      DevicePath = [string]$display.DevicePath
      Active = [bool]$display.Active
      Primary = [bool]$display.Primary
      X = if ($display.Active) { [int]$display.Position.x } else { 0 }
      Y = if ($display.Active) { [int]$display.Position.y } else { 0 }
      Width = if ($display.Active) { [int]$display.Mode.Width } else { 0 }
      Height = if ($display.Active) { [int]$display.Mode.Height } else { 0 }
    }
  }
}

function Get-MonitorProfileConfiguration {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string]$InstallRoot
  )

  $path = Join-Path $InstallRoot "config.json"
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "Monitor profile configuration is missing: $path"
  }
  $configuration = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
  if ([int]$configuration.schemaVersion -ne 1) {
    throw "Unsupported monitor profile configuration schema."
  }
  $roles = @($configuration.monitors | ForEach-Object { [string]$_.role })
  if (($roles -join "|") -cne ($script:MonitorRoles -join "|")) {
    throw "Monitor profile configuration must define left, center, and right."
  }
  $serials = @($configuration.monitors | ForEach-Object { [string]$_.serial })
  if (@($serials | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) {
    throw "Every configured monitor must have an EDID serial."
  }
  if (@($serials | Select-Object -Unique).Count -ne 3) {
    throw "Configured monitor EDID serials must be unique."
  }
  return $configuration
}

function Get-MonitorProfileExpectedState {
  param(
    [string]$Name,
    [object[]]$ConfiguredMonitors
  )

  $definition = Get-MonitorProfileDefinition -Name $Name
  foreach ($display in $definition.Displays) {
    $configured = @(
      $ConfiguredMonitors | Where-Object { [string]$_.role -ceq $display.Role }
    )
    if ($configured.Count -ne 1) {
      throw "Missing configured monitor role: $($display.Role)"
    }
    [pscustomobject]@{
      Role = $display.Role
      Serial = [string]$configured[0].serial
      Active = $display.Active
      Primary = $display.Primary
      X = $display.X
      Y = $display.Y
      Width = $display.Width
      Height = $display.Height
    }
  }
}

function ConvertTo-MonitorRoleState {
  param(
    [object[]]$ConfiguredMonitors,
    [object[]]$Inventory
  )

  $roleMap = Resolve-MonitorRoleMap `
    -ConfiguredMonitors $ConfiguredMonitors `
    -Inventory $Inventory
  foreach ($role in $script:MonitorRoles) {
    $display = $roleMap[$role]
    [pscustomobject]@{
      Role = $role
      Serial = [string]$display.Serial
      Active = [bool]$display.Active
      Primary = [bool]$display.Primary
      X = [int]$display.X
      Y = [int]$display.Y
      Width = [int]$display.Width
      Height = [int]$display.Height
    }
  }
}

function Write-MonitorProfileJson {
  param(
    [object]$Value,
    [string]$Path
  )

  $parent = Split-Path -Parent $Path
  New-Item -ItemType Directory -Path $parent -Force | Out-Null
  $temporaryPath = "$Path.new"
  $Value | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $temporaryPath -Encoding UTF8
  Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
}

function Read-MonitorProfileJsonArray {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "JSON state file is missing: $Path"
  }
  $decoded = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
  foreach ($item in $decoded) {
    Write-Output $item
  }
}

function Invoke-DisplayConfigValidation {
  param(
    [object]$DisplayConfig
  )

  $flagType = [MartinGC94.DisplayConfig.Native.Enums.SetDisplayConfigFlags]
  $flags = $flagType::SDC_VALIDATE -bor
    $flagType::SDC_USE_SUPPLIED_DISPLAY_CONFIG -bor
    $flagType::SDC_VIRTUAL_MODE_AWARE
  Use-DisplayConfig `
    -DisplayConfig $DisplayConfig `
    -UpdateAdapterIds `
    -Flags $flags `
    -ErrorAction Stop
}

function New-MonitorDisplayConfig {
  param(
    [string]$BaseProfilePath,
    [object]$Definition,
    [hashtable]$RoleMap
  )

  $profile = Import-Clixml -LiteralPath $BaseProfilePath
  $disabledIds = @(
    $Definition.Displays |
      Where-Object { -not $_.Active } |
      ForEach-Object { [uint32]$RoleMap[$_.Role].DisplayId }
  )
  $primary = @($Definition.Displays | Where-Object Primary)
  $profile = Set-DisplayPrimary `
    -DisplayId $RoleMap[$primary[0].Role].DisplayId `
    -DisplayConfig $profile `
    -ErrorAction Stop
  if ($disabledIds.Count -gt 0) {
    $profile = Disable-Display `
      -DisplayId $disabledIds `
      -DisplayConfig $profile `
      -ErrorAction Stop
  }
  foreach ($display in @($Definition.Displays | Where-Object Active)) {
    $profile = Set-DisplayPosition `
      -DisplayId $RoleMap[$display.Role].DisplayId `
      -XPosition $display.X `
      -YPosition $display.Y `
      -DisplayConfig $profile `
      -ErrorAction Stop
  }
  return $profile
}

function New-MonitorProfileFiles {
  param(
    [string]$InstallRoot,
    [object]$CurrentConfig,
    [hashtable]$RoleMap
  )

  $profileRoot = Join-Path $InstallRoot "profiles"
  New-Item -ItemType Directory -Path $profileRoot -Force | Out-Null
  $basePath = Join-Path $profileRoot "base.new.clixml"
  $CurrentConfig | Export-Clixml -LiteralPath $basePath -Depth 10
  try {
    foreach ($catalogEntry in Get-MonitorProfileCatalog) {
      $definition = Get-MonitorProfileDefinition -Name $catalogEntry.Name
      $profile = New-MonitorDisplayConfig `
        -BaseProfilePath $basePath `
        -Definition $definition `
        -RoleMap $RoleMap
      Invoke-DisplayConfigValidation -DisplayConfig $profile
      $target = Join-Path $profileRoot $catalogEntry.FileName
      $staged = "$target.new"
      $profile | Export-Clixml -LiteralPath $staged -Depth 10
      Move-Item -LiteralPath $staged -Destination $target -Force
    }
  } finally {
    Remove-Item -LiteralPath $basePath -Force -ErrorAction SilentlyContinue
  }
}

function Initialize-MonitorProfileConfiguration {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string]$InstallRoot
  )

  Import-MonitorProfileDependency -InstallRoot $InstallRoot
  $currentConfig = Get-DisplayConfig
  $active = @(Get-MonitorInventory -DisplayConfig $currentConfig | Where-Object Active)
  if ($active.Count -ne 3) {
    throw "Initialization requires exactly three active displays."
  }
  $ordered = @($active | Sort-Object X)
  $configured = for ($index = 0; $index -lt 3; $index++) {
    $display = $ordered[$index]
    if ([string]::IsNullOrWhiteSpace([string]$display.Serial)) {
      throw "Every display must expose a non-empty EDID serial."
    }
    [pscustomobject]@{
      role = $script:MonitorRoles[$index]
      serial = [string]$display.Serial
      displayName = [string]$display.DisplayName
      devicePath = [string]$display.DevicePath
    }
  }
  $expected = @(Get-MonitorProfileExpectedState -Name all -ConfiguredMonitors $configured)
  $comparison = Compare-MonitorProfileState -Expected $expected -Actual $active
  if (-not $comparison.Succeeded) {
    throw "Current three-display layout is not the required baseline: $($comparison.Problems -join '; ')"
  }
  $roleMap = Resolve-MonitorRoleMap -ConfiguredMonitors $configured -Inventory $active
  New-MonitorProfileFiles -InstallRoot $InstallRoot -CurrentConfig $currentConfig -RoleMap $roleMap
  Write-MonitorProfileJson -Path (Join-Path $InstallRoot "config.json") -Value ([ordered]@{
    schemaVersion = 1
    initializedAt = (Get-Date).ToString("o")
    monitors = $configured
  })
  Set-Content -LiteralPath (Join-Path $InstallRoot "current-profile.txt") -Value "all" -Encoding ASCII
  [pscustomobject]@{ Initialized = $true; ProfileCount = 3; Monitors = $configured }
}

function Wait-MonitorProfileState {
  param(
    [object[]]$Expected,
    [int]$TimeoutSeconds = 8
  )

  $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
  do {
    $inventory = @(Get-MonitorInventory)
    $comparison = Compare-MonitorProfileState -Expected $Expected -Actual $inventory
    if ($comparison.Succeeded) {
      return $comparison
    }
    Start-Sleep -Milliseconds 200
  } while ([DateTime]::UtcNow -lt $deadline)
  return $comparison
}


function Save-MonitorProfileRollbackState {
  param(
    [string]$InstallRoot,
    [object]$CurrentConfig,
    [object[]]$ConfiguredMonitors,
    [object[]]$Inventory
  )

  $stateRoot = Join-Path $InstallRoot "state"
  New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null
  $CurrentConfig | Export-Clixml -LiteralPath (Join-Path $stateRoot "rollback.clixml") -Depth 10
  $state = @(ConvertTo-MonitorRoleState -ConfiguredMonitors $ConfiguredMonitors -Inventory $Inventory)
  Write-MonitorProfileJson -Value $state -Path (Join-Path $stateRoot "rollback-state.json")
  $currentProfilePath = Join-Path $InstallRoot "current-profile.txt"
  if (Test-Path -LiteralPath $currentProfilePath -PathType Leaf) {
    Copy-Item -LiteralPath $currentProfilePath -Destination (
      Join-Path $stateRoot "rollback-profile.txt"
    ) -Force
  }
}

function Invoke-MonitorProfileRollback {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string]$InstallRoot
  )

  Import-MonitorProfileDependency -InstallRoot $InstallRoot
  $stateRoot = Join-Path $InstallRoot "state"
  $profilePath = Join-Path $stateRoot "rollback.clixml"
  $statePath = Join-Path $stateRoot "rollback-state.json"
  if (-not (Test-Path -LiteralPath $profilePath -PathType Leaf)) {
    throw "Rollback display configuration is unavailable."
  }
  $expected = @(Read-MonitorProfileJsonArray -Path $statePath)
  $profile = Import-Clixml -LiteralPath $profilePath
  try {
    Invoke-DisplayConfigValidation -DisplayConfig $profile
    Use-DisplayConfig -DisplayConfig $profile -UpdateAdapterIds -DontSave -ErrorAction Stop
  } catch {
    Undo-DisplayConfigChanges -ErrorAction SilentlyContinue
    Use-DisplayConfig `
      -DisplayConfig $profile `
      -UpdateAdapterIds `
      -DontSave `
      -AllowChanges `
      -ErrorAction Stop
  }
  $comparison = Wait-MonitorProfileState -Expected $expected
  if (-not $comparison.Succeeded) {
    throw "Rollback could not be verified: $($comparison.Problems -join '; ')"
  }
  $profile = Import-Clixml -LiteralPath $profilePath
  Use-DisplayConfig -DisplayConfig $profile -UpdateAdapterIds -ErrorAction Stop
  $rollbackNamePath = Join-Path $stateRoot "rollback-profile.txt"
  $rollbackName = $null
  if (Test-Path -LiteralPath $rollbackNamePath -PathType Leaf) {
    $rollbackName = (Get-Content -LiteralPath $rollbackNamePath -Raw).Trim()
    Set-Content -LiteralPath (Join-Path $InstallRoot "current-profile.txt") `
      -Value $rollbackName -Encoding ASCII
  }
  [pscustomobject]@{ Recovered = $true; Profile = $rollbackName }
}

function Invoke-MonitorProfile {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("all", "left-center", "right-only")]
    [string]$Name,

    [Parameter(Mandatory = $true)]
    [string]$InstallRoot,

    [switch]$ValidateOnly
  )

  Import-MonitorProfileDependency -InstallRoot $InstallRoot
  $configuration = Get-MonitorProfileConfiguration -InstallRoot $InstallRoot
  $currentConfig = Get-DisplayConfig
  $inventory = @(Get-MonitorInventory -DisplayConfig $currentConfig)
  Resolve-MonitorRoleMap -ConfiguredMonitors $configuration.monitors -Inventory $inventory | Out-Null
  $expected = @(Get-MonitorProfileExpectedState -Name $Name -ConfiguredMonitors $configuration.monitors)
  $profilePath = Join-Path (Join-Path $InstallRoot "profiles") (
    Resolve-MonitorProfileFileName -Name $Name
  )
  if (-not (Test-Path -LiteralPath $profilePath -PathType Leaf)) {
    throw "Monitor profile is missing: $profilePath"
  }
  $profile = Import-Clixml -LiteralPath $profilePath
  Invoke-DisplayConfigValidation -DisplayConfig $profile
  if ($ValidateOnly) {
    return [pscustomobject]@{ Name = $Name; Valid = $true; Applied = $false }
  }

  Save-MonitorProfileRollbackState `
    -InstallRoot $InstallRoot `
    -CurrentConfig $currentConfig `
    -ConfiguredMonitors $configuration.monitors `
    -Inventory $inventory
  try {
    Use-DisplayConfig -DisplayConfig $profile -UpdateAdapterIds -DontSave -ErrorAction Stop
    $comparison = Wait-MonitorProfileState -Expected $expected
    if (-not $comparison.Succeeded) {
      throw "Applied monitor profile did not match: $($comparison.Problems -join '; ')"
    }
    $profile = Import-Clixml -LiteralPath $profilePath
    Use-DisplayConfig -DisplayConfig $profile -UpdateAdapterIds -ErrorAction Stop
    $comparison = Wait-MonitorProfileState -Expected $expected
    if (-not $comparison.Succeeded) {
      throw "Persisted monitor profile did not match: $($comparison.Problems -join '; ')"
    }
    Set-Content -LiteralPath (Join-Path $InstallRoot "current-profile.txt") `
      -Value $Name -Encoding ASCII
  } catch {
    $applyError = $_
    try {
      Undo-DisplayConfigChanges -ErrorAction SilentlyContinue
      Invoke-MonitorProfileRollback -InstallRoot $InstallRoot | Out-Null
    } catch {
      throw "Profile apply failed: $($applyError.Exception.Message); rollback also failed: $($_.Exception.Message)"
    }
    throw "Profile apply failed and was rolled back: $($applyError.Exception.Message)"
  }

  [pscustomobject]@{ Name = $Name; Valid = $true; Applied = $true }
}

Export-ModuleMember -Function @(
  "Get-DisplayConfigReleaseSpec",
  "Assert-MonitorProfileFileHash",
  "Get-MonitorProfileCatalog",
  "Resolve-MonitorProfileFileName",
  "Resolve-MonitorProfileInstallRoot",
  "Get-MonitorProfileDefinition",
  "Resolve-MonitorRoleMap",
  "Compare-MonitorProfileState",
  "Read-MonitorProfileJsonArray",
  "Initialize-MonitorProfileConfiguration",
  "Invoke-MonitorProfile",
  "Invoke-MonitorProfileRollback"
)
