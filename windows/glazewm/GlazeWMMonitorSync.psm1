Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-GlazeContainerBounds {
  [CmdletBinding()]
  param([Parameter(Mandatory = $true)][object]$Container)

  $source = if (
    $Container.PSObject.Properties.Name -contains "rect" -and
    $null -ne $Container.rect
  ) {
    $Container.rect
  } else {
    $Container
  }
  foreach ($name in @("x", "y", "width", "height")) {
    if ($source.PSObject.Properties.Name -notcontains $name) {
      throw "GlazeWM monitor is missing its $name coordinate."
    }
  }
  return [pscustomobject]@{
    X = [int]$source.x
    Y = [int]$source.y
    Width = [int]$source.width
    Height = [int]$source.height
  }
}

function Get-GlazeWorkspacesInContainer {
  [CmdletBinding()]
  param([Parameter(Mandatory = $true)][object]$Container)

  if (
    $Container.PSObject.Properties.Name -contains "type" -and
    [string]$Container.type -eq "workspace"
  ) {
    $Container
    return
  }
  if ($Container.PSObject.Properties.Name -notcontains "children") {
    return
  }
  foreach ($child in @($Container.children)) {
    if ($null -ne $child) {
      Get-GlazeWorkspacesInContainer -Container $child
    }
  }
}

function Test-GlazeBoundsEqual {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][object]$First,
    [Parameter(Mandatory = $true)][object]$Second
  )

  return (
    [int]$First.X -eq [int]$Second.X -and
    [int]$First.Y -eq [int]$Second.Y -and
    [int]$First.Width -eq [int]$Second.Width -and
    [int]$First.Height -eq [int]$Second.Height
  )
}

function Get-GlazeWorkspaceMonitorMovePlan {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [object[]]$Monitors,

    [Parameter(Mandatory = $true)]
    [object]$PrimaryBounds
  )

  $ordered = @($Monitors | Sort-Object `
    @{ Expression = { (Get-GlazeContainerBounds $_).X } }, `
    @{ Expression = { (Get-GlazeContainerBounds $_).Y } })
  $primaryIndexes = @(
    for ($index = 0; $index -lt $ordered.Count; $index++) {
      $bounds = Get-GlazeContainerBounds -Container $ordered[$index]
      if (Test-GlazeBoundsEqual -First $bounds -Second $PrimaryBounds) {
        $index
      }
    }
  )
  if ($primaryIndexes.Count -ne 1) {
    throw "Windows primary monitor could not be matched to exactly one GlazeWM monitor."
  }

  $primaryIndex = $primaryIndexes[0]
  for ($monitorIndex = 0; $monitorIndex -lt $ordered.Count; $monitorIndex++) {
    foreach ($workspace in @(Get-GlazeWorkspacesInContainer $ordered[$monitorIndex])) {
      if (
        $workspace.PSObject.Properties.Name -notcontains "id" -or
        $workspace.PSObject.Properties.Name -notcontains "name"
      ) {
        throw "GlazeWM returned a workspace without an id or name."
      }
      $name = [string]$workspace.name
      $targetIndex = switch -Regex ($name) {
        '^(?:[1-9]|1[0-2])$' { $primaryIndex; break }
        '^left$' { 0; break }
        '^vert$' { $ordered.Count - 1; break }
        default { $null }
      }
      if ($null -eq $targetIndex -or $targetIndex -eq $monitorIndex) {
        continue
      }
      $direction = if ($targetIndex -lt $monitorIndex) { "left" } else { "right" }
      foreach ($step in 1..[Math]::Abs($targetIndex - $monitorIndex)) {
        [pscustomobject]@{
          WorkspaceId = [string]$workspace.id
          WorkspaceName = $name
          Direction = $direction
        }
      }
    }
  }
}

function Get-GlazeMonitors {
  [CmdletBinding()]
  param([Parameter(Mandatory = $true)][string]$GlazeWMPath)

  $raw = (& $GlazeWMPath query monitors 2>&1 | Out-String).Trim()
  if ($LASTEXITCODE -ne 0) {
    throw "GlazeWM monitor query failed: $raw"
  }
  try {
    $response = $raw | ConvertFrom-Json -ErrorAction Stop
  } catch {
    throw "GlazeWM monitor query returned invalid JSON."
  }
  if (
    $response.PSObject.Properties.Name -contains "success" -and
    -not [bool]$response.success
  ) {
    throw "GlazeWM rejected the monitor query."
  }
  $monitors = if (
    $response.PSObject.Properties.Name -contains "data" -and
    $null -ne $response.data -and
    $response.data.PSObject.Properties.Name -contains "monitors"
  ) {
    @($response.data.monitors)
  } elseif ($response.PSObject.Properties.Name -contains "monitors") {
    @($response.monitors)
  } else {
    @($response)
  }
  if (@($monitors).Count -lt 1) {
    throw "GlazeWM returned no active monitors."
  }
  return $monitors
}

function Get-WindowsPrimaryBounds {
  Add-Type -AssemblyName System.Windows.Forms
  $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
  return [pscustomobject]@{
    X = $bounds.X
    Y = $bounds.Y
    Width = $bounds.Width
    Height = $bounds.Height
  }
}

function Get-WindowsScreenBounds {
  Add-Type -AssemblyName System.Windows.Forms
  return @(
    [System.Windows.Forms.Screen]::AllScreens | ForEach-Object {
      [pscustomobject]@{
        X = $_.Bounds.X
        Y = $_.Bounds.Y
        Width = $_.Bounds.Width
        Height = $_.Bounds.Height
      }
    }
  )
}

function Test-GlazeMonitorTopologyMatchesWindows {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][object[]]$Monitors,
    [Parameter(Mandatory = $true)][object[]]$WindowsBounds
  )

  if ($Monitors.Count -ne $WindowsBounds.Count) {
    return $false
  }
  $unmatched = [Collections.Generic.List[object]]::new()
  foreach ($bounds in $WindowsBounds) {
    $unmatched.Add($bounds)
  }
  foreach ($monitor in $Monitors) {
    $glazeBounds = Get-GlazeContainerBounds -Container $monitor
    $match = $unmatched | Where-Object {
      Test-GlazeBoundsEqual -First $glazeBounds -Second $_
    } | Select-Object -First 1
    if ($null -eq $match) {
      return $false
    }
    [void]$unmatched.Remove($match)
  }
  return $unmatched.Count -eq 0
}

function Wait-GlazeMonitorTopology {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$GlazeWMPath,
    [ValidateRange(1, 60)][int]$TimeoutSeconds = 30
  )

  $windowsBounds = @(Get-WindowsScreenBounds)
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  $reloadAttempted = $false
  do {
    $monitors = @(Get-GlazeMonitors -GlazeWMPath $GlazeWMPath)
    if (Test-GlazeMonitorTopologyMatchesWindows `
      -Monitors $monitors `
      -WindowsBounds $windowsBounds
    ) {
      return $monitors
    }
    if (-not $reloadAttempted) {
      Invoke-GlazeCliCommand `
        -GlazeWMPath $GlazeWMPath `
        -Arguments @("command", "wm-reload-config") |
        Out-Null
      $reloadAttempted = $true
    }
    Start-Sleep -Milliseconds 250
  } while ((Get-Date) -lt $deadline)
  throw "GlazeWM did not observe the current Windows monitor topology."
}

function Get-GlazeFocusedWorkspaceName {
  [CmdletBinding()]
  param([Parameter(Mandatory = $true)][object[]]$Monitors)

  $focused = @(
    foreach ($monitor in $Monitors) {
      Get-GlazeWorkspacesInContainer -Container $monitor |
        Where-Object {
          $_.PSObject.Properties.Name -contains "hasFocus" -and
          [bool]$_.hasFocus
        }
    }
  )
  if ($focused.Count -ne 1) {
    throw "GlazeWM did not report exactly one focused workspace."
  }
  return [string]$focused[0].name
}

function Invoke-GlazeCliCommand {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$GlazeWMPath,
    [Parameter(Mandatory = $true)][string[]]$Arguments
  )

  $raw = (& $GlazeWMPath @Arguments 2>&1 | Out-String).Trim()
  if ($LASTEXITCODE -ne 0) {
    throw "GlazeWM command failed: $raw"
  }
  try {
    $response = $raw | ConvertFrom-Json -ErrorAction Stop
  } catch {
    throw "GlazeWM command returned invalid JSON."
  }
  if (
    $response.PSObject.Properties.Name -notcontains "success" -or
    -not [bool]$response.success
  ) {
    $message = if ($response.PSObject.Properties.Name -contains "error") {
      [string]$response.error
    } else {
      "unknown error"
    }
    throw "GlazeWM rejected the command: $message"
  }
  return $response
}

function Ensure-GlazeAuxiliaryWorkspaces {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$GlazeWMPath,
    [Parameter(Mandatory = $true)][object[]]$Monitors
  )

  $current = @($Monitors)
  foreach ($name in @("left", "vert")) {
    $exists = @(
      foreach ($monitor in $current) {
        Get-GlazeWorkspacesInContainer -Container $monitor |
          Where-Object { [string]$_.name -eq $name }
      }
    ).Count -eq 1
    if (-not $exists) {
      Invoke-GlazeCliCommand -GlazeWMPath $GlazeWMPath -Arguments @(
        "command", "focus", "--workspace", $name
      ) | Out-Null
      $current = @(Get-GlazeMonitors -GlazeWMPath $GlazeWMPath)
    }
  }
  return $current
}

function Invoke-GlazeWorkspaceMonitorSync {
  [CmdletBinding()]
  param([Parameter(Mandatory = $true)][string]$GlazeWMPath)

  $primaryBounds = Get-WindowsPrimaryBounds
  $monitors = @(Wait-GlazeMonitorTopology -GlazeWMPath $GlazeWMPath)
  $focusedWorkspaceName = Get-GlazeFocusedWorkspaceName -Monitors $monitors
  $plan = @()
  try {
    $monitors = @(Ensure-GlazeAuxiliaryWorkspaces `
      -GlazeWMPath $GlazeWMPath `
      -Monitors $monitors)
    $plan = @(Get-GlazeWorkspaceMonitorMovePlan `
      -Monitors $monitors `
      -PrimaryBounds $primaryBounds |
        Select-Object *, @{
          Name = "AuxiliaryFirst"
          Expression = { if ($_.WorkspaceName -in @("left", "vert")) { 0 } else { 1 } }
        } |
        Sort-Object AuxiliaryFirst, WorkspaceName)
    foreach ($move in $plan) {
      Invoke-GlazeCliCommand -GlazeWMPath $GlazeWMPath -Arguments @(
        "command", "focus", "--workspace", $move.WorkspaceName
      ) | Out-Null
      Invoke-GlazeCliCommand -GlazeWMPath $GlazeWMPath -Arguments @(
        "command", "move-workspace", "--direction", $move.Direction
      ) | Out-Null
    }
  } finally {
    Invoke-GlazeCliCommand -GlazeWMPath $GlazeWMPath -Arguments @(
      "command", "focus", "--workspace", $focusedWorkspaceName
    ) | Out-Null
  }

  $remaining = @(Get-GlazeWorkspaceMonitorMovePlan `
    -Monitors (Get-GlazeMonitors -GlazeWMPath $GlazeWMPath) `
    -PrimaryBounds $primaryBounds)
  if ($remaining.Count -ne 0) {
    throw "GlazeWM workspace monitor synchronization did not converge."
  }
  return $plan
}

function Get-ZebarListener {
  $listener = Get-NetTCPConnection `
    -State Listen `
    -LocalPort 6124 `
    -ErrorAction SilentlyContinue |
    Select-Object -First 1
  if ($null -ne $listener) {
    return $listener
  }

  $netstatPath = Join-Path $env:SystemRoot "System32\netstat.exe"
  if (-not (Test-Path -LiteralPath $netstatPath -PathType Leaf)) {
    return $null
  }
  foreach ($line in @(& $netstatPath -ano -p tcp 2>$null)) {
    if ($line -match '^\s*TCP\s+\S+:6124\s+\S+\s+LISTENING\s+(\d+)\s*$') {
      return [pscustomobject]@{ OwningProcess = [int]$Matches[1] }
    }
  }
  return $null
}

function Get-PrimaryReservedTop {
  Add-Type -AssemblyName System.Windows.Forms
  $screen = [System.Windows.Forms.Screen]::PrimaryScreen
  return [int]($screen.WorkingArea.Y - $screen.Bounds.Y)
}

function Assert-ZebarAssetServerHealthy {
  param(
    [object]$Listener,
    [object[]]$Processes
  )

  if ($null -eq $Listener) {
    if ($Processes.Count -eq 0) {
      return
    }
    throw (
      "Zebar is running without its port 6124 asset server; sign out or " +
      "reboot before starting the bar."
    )
  }
  $owner = Get-Process `
    -Id $Listener.OwningProcess `
    -ErrorAction SilentlyContinue
  if ($null -eq $owner) {
    throw (
      "Port 6124 has an orphaned listener; sign out or reboot before " +
      "starting Zebar."
    )
  }
  if ([int]$Listener.OwningProcess -notin @($Processes.Id)) {
    throw "Port 6124 is owned by another live process."
  }
}

function Close-GlazeZebarWidget {
  param(
    [Parameter(Mandatory = $true)][object]$Bar,
    [ValidateRange(1, 60)][int]$TimeoutSeconds
  )

  if (-not $Bar.CloseMainWindow()) {
    throw "The managed Zebar widget did not accept an orderly close request."
  }
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  do {
    $remainingBars = @(
      Get-Process -Name "zebar" -ErrorAction SilentlyContinue |
        Where-Object {
          $_.Responding -and $_.MainWindowTitle -eq "Zebar - zetshell / bar"
        }
    )
    if ($remainingBars.Count -eq 0) {
      # Allow Zebar's window-destroyed event to remove the old preset state.
      Start-Sleep -Milliseconds 250
      return
    }
    Start-Sleep -Milliseconds 250
  } while ((Get-Date) -lt $deadline)
  throw "The managed Zebar widget did not close before the timeout."
}

function Start-GlazeZebarPrimaryPreset {
  param(
    [string]$ZebarPath,
    [ValidateRange(1, 60)][int]$TimeoutSeconds,
    [ValidateRange(1, 200)][int]$ExpectedReservedTop
  )

  Start-Process -FilePath $ZebarPath -ArgumentList @(
    "start-widget-preset",
    "--pack", "zetshell",
    "--widget-name", "bar",
    "--preset", "primary-monitor"
  ) -WindowStyle Hidden | Out-Null

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  do {
    Start-Sleep -Milliseconds 250
    $bar = Get-Process -Name "zebar" -ErrorAction SilentlyContinue |
      Where-Object {
        $_.Responding -and $_.MainWindowTitle -eq "Zebar - zetshell / bar"
      } |
      Select-Object -First 1
    $listener = Get-ZebarListener
    $reservedTop = Get-PrimaryReservedTop
  } while (
    (
      $null -eq $bar -or
      $null -eq $listener -or
      [int]$listener.OwningProcess -ne [int]$bar.Id -or
      $reservedTop -ne $ExpectedReservedTop
    ) -and
    (Get-Date) -lt $deadline
  )
  if ($null -eq $bar) {
    throw "The managed Zebar bar did not become visible."
  }
  if ($null -eq $listener -or [int]$listener.OwningProcess -ne [int]$bar.Id) {
    throw "The visible Zebar bar does not own port 6124."
  }
  if ($reservedTop -ne $ExpectedReservedTop) {
    throw "Zebar ReservedTop is $reservedTop; expected $ExpectedReservedTop."
  }
  return [pscustomobject]@{
    ProcessId = $bar.Id
    ListenerOwningProcess = [int]$listener.OwningProcess
    ListenerOwnerExists = $true
    ListenerOwnedByBar = $true
    ReservedTop = $reservedTop
  }
}

function Ensure-GlazeZebar {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$ZebarPath,
    [ValidateRange(1, 60)][int]$TimeoutSeconds = 30,
    [ValidateRange(1, 200)][int]$ExpectedReservedTop = 42,
    [switch]$AllowWidgetRelaunch
  )

  if (-not (Test-Path -LiteralPath $ZebarPath -PathType Leaf)) {
    throw "Zebar executable not found: $ZebarPath"
  }
  # Zebar 3.3.1 can orphan port 6124 after process exit (upstream #285). Never
  # terminate its runtime for a monitor change; relaunch only the widget inside
  # the live process so the asset-server socket remains owned.
  $zebarProcesses = @(Get-Process `
    -Name "zebar" `
    -ErrorAction SilentlyContinue)
  $listener = Get-ZebarListener
  Assert-ZebarAssetServerHealthy `
    -Listener $listener `
    -Processes $zebarProcesses
  $existingBar = $zebarProcesses |
    Where-Object {
      $_.Responding -and $_.MainWindowTitle -eq "Zebar - zetshell / bar"
    } |
    Select-Object -First 1
  if ($null -ne $existingBar) {
    $reservedTop = Get-PrimaryReservedTop
    if (
      $null -ne $listener -and
      [int]$listener.OwningProcess -eq [int]$existingBar.Id -and
      $reservedTop -eq $ExpectedReservedTop
    ) {
      return [pscustomobject]@{
        ProcessId = $existingBar.Id
        ListenerOwningProcess = [int]$listener.OwningProcess
        ListenerOwnerExists = $true
        ListenerOwnedByBar = $true
        ReservedTop = $reservedTop
      }
    }
    if (
      $null -eq $listener -or
      [int]$listener.OwningProcess -ne [int]$existingBar.Id
    ) {
      throw "The visible Zebar bar does not own port 6124."
    }
    if (-not $AllowWidgetRelaunch) {
      throw (
        "Zebar widget relaunch requires explicit authorization. " +
        "Rerun with -AllowWidgetRelaunch only after user approval."
      )
    }
    Close-GlazeZebarWidget `
      -Bar $existingBar `
      -TimeoutSeconds $TimeoutSeconds
  }
  return Start-GlazeZebarPrimaryPreset `
    -ZebarPath $ZebarPath `
    -TimeoutSeconds $TimeoutSeconds `
    -ExpectedReservedTop $ExpectedReservedTop
}

function Invoke-GlazeMonitorProfileRefresh {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$GlazeWMPath,
    [string]$ZebarPath = "",
    [switch]$RestartZebar,
    [switch]$AllowZebarWidgetRelaunch
  )

  if (-not (Test-Path -LiteralPath $GlazeWMPath -PathType Leaf)) {
    return [pscustomobject]@{ Active = $false; Reason = "CLI missing" }
  }
  & $GlazeWMPath query app-metadata 2>$null | Out-Null
  if ($LASTEXITCODE -ne 0) {
    return [pscustomobject]@{ Active = $false; Reason = "Manager inactive" }
  }
  $moves = @(Invoke-GlazeWorkspaceMonitorSync -GlazeWMPath $GlazeWMPath)
  $zebar = if ($RestartZebar) {
    Ensure-GlazeZebar `
      -ZebarPath $ZebarPath `
      -AllowWidgetRelaunch:$AllowZebarWidgetRelaunch
  } else {
    $null
  }
  return [pscustomobject]@{
    Active = $true
    WorkspaceMoveCount = $moves.Count
    Zebar = $zebar
  }
}

Export-ModuleMember -Function @(
  "Get-GlazeWorkspaceMonitorMovePlan",
  "Invoke-GlazeWorkspaceMonitorSync",
  "Ensure-GlazeZebar",
  "Invoke-GlazeMonitorProfileRefresh"
)
