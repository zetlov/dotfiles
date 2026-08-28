param(
  [switch]$NoRun = $false,
  [switch]$ValidateOnly = $false,
  [string]$DocumentsPath = [Environment]::GetFolderPath("MyDocuments")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-AudioOutputPatterns {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "Audio output configuration is missing: $Path"
  }

  try {
    $config = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
  } catch {
    throw "Cannot parse the audio output configuration: $Path"
  }
  $property = $config.PSObject.Properties["playback_device_patterns"]
  if (-not $property) {
    throw "Audio output configuration must define playback_device_patterns."
  }

  $patterns = @($property.Value)
  if ($patterns.Count -lt 2) {
    throw "At least two playback device patterns are required."
  }
  foreach ($pattern in $patterns) {
    if ($pattern -isnot [string] -or [string]::IsNullOrWhiteSpace($pattern)) {
      throw "Playback device patterns must be non-empty strings."
    }
  }

  $normalized = @(
    $patterns |
      ForEach-Object { $_.Trim().ToLowerInvariant() } |
      Select-Object -Unique
  )
  if ($normalized.Count -ne $patterns.Count) {
    throw "Playback device patterns must be unique."
  }

  return $patterns
}

function Resolve-AudioOutputDevices {
  param(
    [Parameter(Mandatory = $true)]
    [object[]]$Devices,

    [Parameter(Mandatory = $true)]
    [string[]]$Patterns
  )

  if ($Patterns.Count -lt 2) {
    throw "At least two playback device patterns are required."
  }

  $resolved = @()
  foreach ($pattern in $Patterns) {
    if ([string]::IsNullOrWhiteSpace($pattern)) {
      throw "Playback device patterns cannot be empty."
    }

    $matches = @(
      $Devices | Where-Object {
        $_.Type -eq "Playback" -and
        $_.Name.IndexOf(
          $pattern,
          [System.StringComparison]::OrdinalIgnoreCase
        ) -ge 0
      }
    )
    if ($matches.Count -ne 1) {
      throw (
        "Playback device pattern '{0}' matched {1} devices; expected exactly one." -f
        $pattern,
        $matches.Count
      )
    }
    if (@($resolved | Where-Object { $_.ID -eq $matches[0].ID }).Count -gt 0) {
      throw "Playback device patterns must resolve to different devices."
    }

    $resolved += $matches[0]
  }

  return $resolved
}

function Select-NextAudioOutputDevice {
  param(
    [Parameter(Mandatory = $true)]
    [object[]]$Devices
  )

  if ($Devices.Count -lt 2) {
    throw "At least two resolved playback devices are required."
  }

  for ($index = 0; $index -lt $Devices.Count; $index++) {
    if ([bool]$Devices[$index].Default) {
      return $Devices[($index + 1) % $Devices.Count]
    }
  }

  return $Devices[0]
}

function Show-AudioOutputNotification {
  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$DeviceName,

    [scriptblock]$Notifier
  )

  $title = "Audio output"
  if ($null -ne $Notifier) {
    & $Notifier $title $DeviceName
    return
  }

  Add-Type -AssemblyName System.Drawing
  Add-Type -AssemblyName System.Windows.Forms
  $notification = New-Object System.Windows.Forms.NotifyIcon
  try {
    $notification.Icon = [System.Drawing.SystemIcons]::Information
    $notification.Visible = $true
    $notification.ShowBalloonTip(
      2000,
      $title,
      $DeviceName,
      [System.Windows.Forms.ToolTipIcon]::Info
    )
    Start-Sleep -Milliseconds 2000
  } finally {
    $notification.Visible = $false
    $notification.Dispose()
  }
}

function Assert-AudioModulePathIsNotReparsePoint {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [Parameter(Mandatory = $true)]
    [string]$Description
  )

  if (-not (Test-Path -LiteralPath $Path)) {
    throw "AudioDeviceCmdlets integrity check failed: missing $Description at $Path"
  }
  $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
  if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
    throw "AudioDeviceCmdlets integrity check failed: $Description is a reparse point."
  }
}

function Assert-AudioModuleFileHash {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [Parameter(Mandatory = $true)]
    [string]$ExpectedSha256
  )

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "AudioDeviceCmdlets integrity check failed: required file is missing: $Path"
  }
  Assert-AudioModulePathIsNotReparsePoint `
    -Path $Path `
    -Description "module file"

  $actualHash = (Get-FileHash -LiteralPath $Path -Algorithm "SHA256").Hash
  if (-not [string]::Equals(
    [string]$actualHash,
    $ExpectedSha256,
    [System.StringComparison]::OrdinalIgnoreCase
  )) {
    throw "AudioDeviceCmdlets integrity check failed for: $Path"
  }
}

function Resolve-TrustedAudioDeviceModule {
  param(
    [Parameter(Mandatory = $true)]
    [string]$DocumentsPath
  )

  if ([string]::IsNullOrWhiteSpace($DocumentsPath)) {
    throw "Cannot resolve the current user's MyDocuments directory."
  }

  $requiredVersion = "3.1.0.2"
  $windowsPowerShellPath = Join-Path $DocumentsPath "WindowsPowerShell"
  $modulesPath = Join-Path $windowsPowerShellPath "Modules"
  $moduleContainerPath = Join-Path $modulesPath "AudioDeviceCmdlets"
  $moduleRoot = Join-Path $moduleContainerPath $requiredVersion
  $manifestPath = Join-Path $moduleRoot "AudioDeviceCmdlets.psd1"
  $dllPath = Join-Path $moduleRoot "AudioDeviceCmdlets.dll"
  $manifestSha256 = (
    "0D657B8DDE3DC9B090716162ED351B68F" +
    "785F50483B92E937528D082469DBFB5"
  )
  $dllSha256 = (
    "2E81666DD09BC835C669DAF9771686FD" +
    "AD5651FBEBB600A234F11AF80CA5D25F"
  )

  foreach ($pathEntry in @(
    @($windowsPowerShellPath, "WindowsPowerShell directory"),
    @($modulesPath, "PowerShell modules directory"),
    @($moduleContainerPath, "module container directory"),
    @($moduleRoot, "module version directory")
  )) {
    Assert-AudioModulePathIsNotReparsePoint `
      -Path $pathEntry[0] `
      -Description $pathEntry[1]
  }
  Assert-AudioModuleFileHash `
    -Path $manifestPath `
    -ExpectedSha256 $manifestSha256
  Assert-AudioModuleFileHash `
    -Path $dllPath `
    -ExpectedSha256 $dllSha256

  $modules = @(
    Import-Module `
      -Name $manifestPath `
      -Force `
      -PassThru `
      -ErrorAction Stop
  )
  if ($modules.Count -ne 1) {
    throw "AudioDeviceCmdlets integrity check failed: import returned an unexpected module count."
  }

  $module = $modules[0]
  $expectedModuleBase = [System.IO.Path]::GetFullPath($moduleRoot).TrimEnd(
    [System.IO.Path]::DirectorySeparatorChar,
    [System.IO.Path]::AltDirectorySeparatorChar
  )
  $actualModuleBase = [System.IO.Path]::GetFullPath(
    [string]$module.ModuleBase
  ).TrimEnd(
    [System.IO.Path]::DirectorySeparatorChar,
    [System.IO.Path]::AltDirectorySeparatorChar
  )
  if (-not [string]::Equals(
    $actualModuleBase,
    $expectedModuleBase,
    [System.StringComparison]::OrdinalIgnoreCase
  )) {
    throw "AudioDeviceCmdlets integrity check failed: the imported module path is unexpected."
  }
  if ($module.Version -ne [version]$requiredVersion) {
    throw "AudioDeviceCmdlets integrity check failed: the imported module version is unexpected."
  }

  $getAudioDevice = $module.ExportedCommands["Get-AudioDevice"]
  $setAudioDevice = $module.ExportedCommands["Set-AudioDevice"]
  if ($null -eq $getAudioDevice -or $null -eq $setAudioDevice) {
    throw "AudioDeviceCmdlets integrity check failed: required commands are not exported."
  }

  return [pscustomobject]@{
    Module = $module
    GetCommand = $getAudioDevice
    SetCommand = $setAudioDevice
  }
}

function Invoke-AudioOutputChange {
  param(
    [Parameter(Mandatory = $true)]
    [object]$GetCommand,

    [Parameter(Mandatory = $true)]
    [object]$SetCommand,

    [Parameter(Mandatory = $true)]
    [string[]]$Patterns,

    [scriptblock]$Notifier
  )

  $devices = @(& $GetCommand -List)
  $configuredDevices = @(
    Resolve-AudioOutputDevices -Devices $devices -Patterns $Patterns
  )
  $nextDevice = Select-NextAudioOutputDevice -Devices $configuredDevices
  & $SetCommand -ID $nextDevice.ID | Out-Null
  Write-Host "Audio output: $($nextDevice.Name)"
  Show-AudioOutputNotification -DeviceName $nextDevice.Name -Notifier $Notifier
  return $nextDevice
}

if ($NoRun) {
  return
}

$trustedModule = Resolve-TrustedAudioDeviceModule -DocumentsPath $DocumentsPath
if ($ValidateOnly) {
  return $trustedModule.Module
}

$configPath = Join-Path $PSScriptRoot "audio-output.json"
$patterns = @(Get-AudioOutputPatterns -Path $configPath)
[void](Invoke-AudioOutputChange `
  -GetCommand $trustedModule.GetCommand `
  -SetCommand $trustedModule.SetCommand `
  -Patterns $patterns)
