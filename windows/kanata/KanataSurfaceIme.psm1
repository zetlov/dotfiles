Set-StrictMode -Version Latest

$script:ScancodeMapPath = (
  "HKLM:\SYSTEM\CurrentControlSet\Control\Keyboard Layout"
)
$script:ScancodeMapName = "Scancode Map"

function Test-KanataSurfaceDevice {
  $system = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
  return (
    [string]$system.Manufacturer -eq "Microsoft Corporation" -and
    [string]$system.Model -match '^Surface\b'
  )
}

function ConvertFrom-KanataScancodeMap {
  param([Parameter(Mandatory = $true)][byte[]]$Data)

  if ($Data.Length -lt 16 -or $Data.Length % 4 -ne 0) {
    throw "Scancode Map has an invalid length."
  }
  if (@($Data[0..7] | Where-Object { $_ -ne 0 }).Count -ne 0) {
    throw "Scancode Map has an invalid header."
  }
  $count = [BitConverter]::ToUInt32($Data, 8)
  if ($count -lt 1 -or $Data.Length -ne 12 + (4 * $count)) {
    throw "Scancode Map has an invalid entry count."
  }
  $terminatorOffset = 12 + (4 * ($count - 1))
  if ([BitConverter]::ToUInt32($Data, $terminatorOffset) -ne 0) {
    throw "Scancode Map is missing its terminator."
  }

  return @(
    for ($index = 0; $index -lt $count - 1; $index++) {
      $offset = 12 + (4 * $index)
      [pscustomobject]@{
        Target = [BitConverter]::ToUInt16($Data, $offset)
        Source = [BitConverter]::ToUInt16($Data, $offset + 2)
      }
    }
  )
}

function ConvertTo-KanataScancodeMap {
  param([Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Mappings)

  $seenSources = @{}
  foreach ($mapping in $Mappings) {
    $source = [uint16]$mapping.Source
    if ($source -eq 0 -or $seenSources.ContainsKey($source)) {
      throw "Scancode Map contains an invalid or duplicate source."
    }
    $seenSources[$source] = $true
  }

  $count = $Mappings.Count + 1
  $data = [byte[]]::new(12 + (4 * $count))
  [Buffer]::BlockCopy([BitConverter]::GetBytes([uint32]$count), 0, $data, 8, 4)
  for ($index = 0; $index -lt $Mappings.Count; $index++) {
    $offset = 12 + (4 * $index)
    [Buffer]::BlockCopy(
      [BitConverter]::GetBytes([uint16]$Mappings[$index].Target),
      0,
      $data,
      $offset,
      2
    )
    [Buffer]::BlockCopy(
      [BitConverter]::GetBytes([uint16]$Mappings[$index].Source),
      0,
      $data,
      $offset + 2,
      2
    )
  }
  return ,$data
}

function Get-KanataSurfaceImeMappings {
  return @(
    [pscustomobject]@{ Source = [uint16]0x0079; Target = [uint16]0x0066 }
  )
}

function Get-KanataLegacySurfaceImeMappings {
  return @(
    [pscustomobject]@{ Source = [uint16]0xE0F1; Target = [uint16]0x0064 }
  )
}

function Get-KanataCurrentScancodeMap {
  $property = Get-ItemProperty `
    -LiteralPath $script:ScancodeMapPath `
    -Name $script:ScancodeMapName `
    -ErrorAction SilentlyContinue
  if ($null -eq $property) {
    return $null
  }
  return ,([byte[]]$property.PSObject.Properties[
    $script:ScancodeMapName
  ].Value)
}

function Get-KanataSurfaceImeScancodeMapUpdate {
  param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("Add", "Remove")]
    [string]$Action,

    [AllowNull()][byte[]]$CurrentData
  )

  $currentMappings = if ($null -eq $CurrentData) {
    @()
  } else {
    @(ConvertFrom-KanataScancodeMap -Data $CurrentData)
  }
  $managedMappings = @(Get-KanataSurfaceImeMappings)
  $legacyMappings = @(Get-KanataLegacySurfaceImeMappings)
  $desiredMappings = [Collections.Generic.List[object]]::new()
  foreach ($mapping in $currentMappings) {
    $legacy = $legacyMappings | Where-Object {
      $_.Source -eq $mapping.Source -and $_.Target -eq $mapping.Target
    } | Select-Object -First 1
    if ($null -eq $legacy) {
      $desiredMappings.Add($mapping)
    }
  }

  if ($Action -eq "Add") {
    foreach ($managed in $managedMappings) {
      $existing = @(
        $currentMappings | Where-Object { $_.Source -eq $managed.Source }
      )
      if ($existing.Count -eq 1) {
        if ($existing[0].Target -ne $managed.Target) {
          throw (
            "Scancode 0x$($managed.Source.ToString('X4')) is already " +
            "mapped to 0x$($existing[0].Target.ToString('X4'))."
          )
        }
        continue
      }
      $desiredMappings.Add($managed)
    }
  } else {
    $desiredMappings = [Collections.Generic.List[object]]::new()
    foreach ($mapping in $currentMappings) {
      $managed = @($managedMappings + $legacyMappings) | Where-Object {
        $_.Source -eq $mapping.Source -and $_.Target -eq $mapping.Target
      } | Select-Object -First 1
      if ($null -eq $managed) {
        $desiredMappings.Add($mapping)
      }
    }
  }

  $desiredData = if ($desiredMappings.Count -eq 0) {
    $null
  } else {
    ConvertTo-KanataScancodeMap -Mappings @($desiredMappings)
  }
  $currentSignature = if ($null -eq $CurrentData) { "" } else {
    [Convert]::ToBase64String($CurrentData)
  }
  $desiredSignature = if ($null -eq $desiredData) { "" } else {
    [Convert]::ToBase64String($desiredData)
  }
  return [pscustomobject]@{
    Changed = (
      ($null -eq $CurrentData) -ne ($null -eq $desiredData) -or
      $currentSignature -ne $desiredSignature
    )
    CurrentData = $CurrentData
    DesiredData = $desiredData
  }
}

function Invoke-KanataScancodeMapUpdate {
  param([Parameter(Mandatory = $true)][object]$Update)

  if (-not $Update.Changed) {
    return $false
  }
  $currentPresent = $null -ne $Update.CurrentData
  $desiredPresent = $null -ne $Update.DesiredData
  $currentBase64 = if ($currentPresent) {
    [Convert]::ToBase64String([byte[]]$Update.CurrentData)
  } else { "" }
  $desiredBase64 = if ($desiredPresent) {
    [Convert]::ToBase64String([byte[]]$Update.DesiredData)
  } else { "" }
  $elevatedCommand = @"
`$ErrorActionPreference = "Stop"
`$path = "$script:ScancodeMapPath"
`$name = "$script:ScancodeMapName"
`$property = Get-ItemProperty -LiteralPath `$path -Name `$name -ErrorAction SilentlyContinue
`$current = if (`$null -eq `$property) { `$null } else { [byte[]]`$property.`$name }
if ((`$null -ne `$current) -ne `$$($currentPresent.ToString().ToLowerInvariant())) { exit 21 }
if (`$null -ne `$current) {
  `$expected = [Convert]::FromBase64String("$currentBase64")
  if ((`$current -join ',') -ne (`$expected -join ',')) { exit 21 }
}
if (`$$($desiredPresent.ToString().ToLowerInvariant())) {
  `$desired = [Convert]::FromBase64String("$desiredBase64")
  New-ItemProperty -LiteralPath `$path -Name `$name -PropertyType Binary -Value `$desired -Force | Out-Null
} else {
  Remove-ItemProperty -LiteralPath `$path -Name `$name -ErrorAction Stop
}
"@
  $encodedCommand = [Convert]::ToBase64String(
    [Text.Encoding]::Unicode.GetBytes($elevatedCommand)
  )
  $powerShell = Join-Path $env:WINDIR (
    "System32\WindowsPowerShell\v1.0\powershell.exe"
  )
  $process = Start-Process `
    -FilePath $powerShell `
    -Verb RunAs `
    -ArgumentList @("-NoProfile", "-EncodedCommand", $encodedCommand) `
    -Wait `
    -PassThru
  if ($process.ExitCode -eq 21) {
    throw "Scancode Map changed while the elevated update was pending."
  }
  if ($process.ExitCode -ne 0) {
    throw "The elevated Scancode Map update failed with exit code $($process.ExitCode)."
  }
  return $true
}

function Add-KanataSurfaceImeScancodeMap {
  $current = Get-KanataCurrentScancodeMap
  $update = Get-KanataSurfaceImeScancodeMapUpdate `
    -Action Add `
    -CurrentData $current
  return Invoke-KanataScancodeMapUpdate -Update $update
}

function Remove-KanataSurfaceImeScancodeMap {
  $current = Get-KanataCurrentScancodeMap
  $update = Get-KanataSurfaceImeScancodeMapUpdate `
    -Action Remove `
    -CurrentData $current
  return Invoke-KanataScancodeMapUpdate -Update $update
}

Export-ModuleMember -Function `
  Test-KanataSurfaceDevice, `
  ConvertFrom-KanataScancodeMap, `
  ConvertTo-KanataScancodeMap, `
  Get-KanataSurfaceImeMappings, `
  Get-KanataSurfaceImeScancodeMapUpdate, `
  Add-KanataSurfaceImeScancodeMap, `
  Remove-KanataSurfaceImeScancodeMap
