Set-StrictMode -Version Latest

function Merge-FlowLauncherSettings {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$ExistingJson,
    [Parameter(Mandatory = $true)][string]$ManagedJson
  )

  foreach ($json in @($ExistingJson, $ManagedJson)) {
    if (-not $json.TrimStart().StartsWith('{')) {
      throw 'Flow Launcher settings must be JSON objects.'
    }
  }
  $existing = $ExistingJson | ConvertFrom-Json -ErrorAction Stop
  $managed = $ManagedJson | ConvertFrom-Json -ErrorAction Stop
  $strings = @('Hotkey', 'Language', 'Theme')
  $booleans = @(
    'StartFlowLauncherOnSystemStartup', 'UseLogonTaskForStartup', 'HideOnStartup'
  )
  $result = [ordered]@{}
  foreach ($property in $existing.PSObject.Properties) {
    $result[$property.Name] = $property.Value
  }
  $changed = $false
  foreach ($property in $managed.PSObject.Properties) {
    $name = $property.Name
    $value = $property.Value
    if ($name -cin $strings) {
      if ($value -isnot [string] -or [string]::IsNullOrWhiteSpace($value)) {
        throw "Managed setting $name must be a non-empty string."
      }
    } elseif ($name -cin $booleans) {
      if ($value -isnot [bool]) {
        throw "Managed setting $name must be a boolean."
      }
    } else {
      throw "Unsupported managed Flow Launcher setting: $name"
    }
    if (-not $result.Contains($name) -or $result[$name] -cne $value) {
      $changed = $true
    }
    $result[$name] = $value
  }
  [PSCustomObject]@{
    Changed = $changed
    Json = ConvertTo-Json -InputObject $result -Depth 100
  }
}

function Stop-FlowLauncherProcess {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]$Process
  )

  # Process.MainWindowHandle excludes Flow's hidden launcher window.
  if (-not ('Dotfiles.FlowLauncherWindow' -as [type])) {
    Add-Type -Path (Join-Path $PSScriptRoot 'FlowLauncherWindow.cs') -ErrorAction Stop
  }
  if (-not $Process.HasExited) {
    if (-not [Dotfiles.FlowLauncherWindow]::RequestClose($Process.Id)) {
      throw 'Flow Launcher could not be closed gracefully; settings were not changed.'
    }
    if (-not $Process.WaitForExit(15000)) {
      throw 'Flow Launcher did not exit; settings were not changed.'
    }
  }
}

Export-ModuleMember -Function Merge-FlowLauncherSettings, Stop-FlowLauncherProcess
