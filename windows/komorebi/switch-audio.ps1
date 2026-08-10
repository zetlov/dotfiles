param(
  [switch]$NoRun = $false
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

if ($NoRun) {
  return
}

$requiredVersion = "3.1.0.2"
$configPath = Join-Path $PSScriptRoot "audio-output.json"
$patterns = @(Get-AudioOutputPatterns -Path $configPath)
Import-Module "AudioDeviceCmdlets" -RequiredVersion $requiredVersion -ErrorAction Stop
$devices = @(Get-AudioDevice -List)
$configuredDevices = @(
  Resolve-AudioOutputDevices -Devices $devices -Patterns $patterns
)
$nextDevice = Select-NextAudioOutputDevice -Devices $configuredDevices
Set-AudioDevice -ID $nextDevice.ID | Out-Null
Write-Host "Audio output: $($nextDevice.Name)"
Show-AudioOutputNotification -DeviceName $nextDevice.Name
