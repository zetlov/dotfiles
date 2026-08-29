Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "GlazeWMWorkspaceHelpers.ps1")

function Get-GlazeTilingDirection {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [double]$Width,

    [Parameter(Mandatory = $true)]
    [double]$Height
  )

  if ($Width -le 0 -or $Height -le 0 -or $Width -eq $Height) {
    return $null
  }

  if ($Width -gt $Height) {
    return "horizontal"
  }

  return "vertical"
}

function Find-GlazeFocusedWindow {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [object]$Container
  )

  if (
    $Container.PSObject.Properties.Name -contains "type" -and
    $Container.type -eq "window" -and
    $Container.PSObject.Properties.Name -contains "hasFocus" -and
    $Container.hasFocus
  ) {
    return $Container
  }

  if (-not ($Container.PSObject.Properties.Name -contains "children")) {
    return $null
  }

  foreach ($child in @($Container.children)) {
    if ($null -eq $child) {
      continue
    }

    $focused = Find-GlazeFocusedWindow -Container $child
    if ($null -ne $focused) {
      return $focused
    }
  }

  return $null
}

function Get-GlazeFocusedWindowFromEvent {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string]$Json
  )

  try {
    $message = $Json | ConvertFrom-Json -ErrorAction Stop
  } catch {
    return $null
  }

  if (
    (
      $message.PSObject.Properties.Name -contains "messageType" -and
      $message.messageType -ne "event_subscription"
    ) -or
    -not ($message.PSObject.Properties.Name -contains "data") -or
    $null -eq $message.data -or
    -not ($message.data.PSObject.Properties.Name -contains "eventType") -or
    $message.data.eventType -notin @(
      "focus_changed",
      "focused_container_moved"
    ) -or
    -not ($message.data.PSObject.Properties.Name -contains "focusedContainer") -or
    $null -eq $message.data.focusedContainer
  ) {
    return $null
  }

  return Find-GlazeFocusedWindow `
    -Container $message.data.focusedContainer
}

function Test-GlazeContainerContainsId {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [object]$Container,

    [Parameter(Mandatory = $true)]
    [string]$ContainerId
  )

  if (
    $Container.PSObject.Properties.Name -contains "id" -and
    [string]$Container.id -eq $ContainerId
  ) {
    return $true
  }
  if (-not ($Container.PSObject.Properties.Name -contains "children")) {
    return $false
  }
  foreach ($child in @($Container.children)) {
    if (
      $null -ne $child -and
      (Test-GlazeContainerContainsId `
        -Container $child `
        -ContainerId $ContainerId)
    ) {
      return $true
    }
  }
  return $false
}

function Find-GlazeWorkspaceNameForContainer {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [AllowEmptyCollection()]
    [object[]]$Workspaces,

    [Parameter(Mandatory = $true)]
    [string]$ContainerId
  )

  foreach ($workspace in $Workspaces) {
    if (
      $null -ne $workspace -and
      $workspace.PSObject.Properties.Name -contains "name" -and
      (Test-GlazeContainerContainsId `
        -Container $workspace `
        -ContainerId $ContainerId)
    ) {
      return [string]$workspace.name
    }
  }
  return $null
}

function Test-GlazeWindowRequiresGameFloating {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [object]$Window,

    [AllowEmptyString()]
    [string]$WorkspaceName = "",

    [string[]]$GameWorkspaceNames = @("11")
  )

  return (
    $Window.PSObject.Properties.Name -contains "type" -and
    [string]$Window.type -eq "window" -and
    $Window.PSObject.Properties.Name -contains "id" -and
    $Window.PSObject.Properties.Name -contains "state" -and
    $null -ne $Window.state -and
    $Window.state.PSObject.Properties.Name -contains "type" -and
    [string]$Window.state.type -eq "tiling" -and
    $WorkspaceName -in $GameWorkspaceNames
  )
}

function Get-GlazeTilingWindowsInContainer {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [object]$Container
  )

  if (
    $Container.PSObject.Properties.Name -contains "type" -and
    [string]$Container.type -eq "window"
  ) {
    if (
      $Container.PSObject.Properties.Name -contains "state" -and
      $null -ne $Container.state -and
      $Container.state.PSObject.Properties.Name -contains "type" -and
      [string]$Container.state.type -eq "tiling"
    ) {
      $Container
    }
    return
  }

  if (-not ($Container.PSObject.Properties.Name -contains "children")) {
    return
  }
  foreach ($child in @($Container.children)) {
    if ($null -ne $child) {
      Get-GlazeTilingWindowsInContainer -Container $child
    }
  }
}

function Get-GlazeGameWorkspaceTilingWindows {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [AllowEmptyCollection()]
    [object[]]$Workspaces,

    [string[]]$GameWorkspaceNames = @("11")
  )

  foreach ($workspace in $Workspaces) {
    if (
      $null -ne $workspace -and
      $workspace.PSObject.Properties.Name -contains "name" -and
      [string]$workspace.name -in $GameWorkspaceNames
    ) {
      Get-GlazeTilingWindowsInContainer -Container $workspace
    }
  }
}

function Get-GlazeWorkspaceGridPlan {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [AllowEmptyCollection()]
    [object[]]$Windows,

    [Parameter(Mandatory = $true)]
    [ValidateCount(4, 4)]
    [string[]]$ProcessNames
  )

  $targets = @($Windows | Where-Object {
    $null -ne $_ -and
    $_.PSObject.Properties.Name -contains "processName" -and
    [string]$_.processName -in $ProcessNames
  })
  if ($targets.Count -ne 4) {
    return
  }

  foreach ($processName in $ProcessNames) {
    if (@($targets | Where-Object {
      [string]$_.processName -eq $processName
    }).Count -ne 1) {
      return
    }
  }
  $unknownTiling = @($Windows | Where-Object {
    $null -ne $_ -and
    $_.PSObject.Properties.Name -contains "state" -and
    $null -ne $_.state -and
    $_.state.PSObject.Properties.Name -contains "type" -and
    [string]$_.state.type -eq "tiling" -and
    (
      -not ($_.PSObject.Properties.Name -contains "processName") -or
      [string]$_.processName -notin $ProcessNames
    )
  })
  if ($unknownTiling.Count -gt 0) {
    return
  }
  if (Test-GlazeWorkspaceTwoByTwo `
    -Windows $Windows `
    -ProcessNames $ProcessNames
  ) {
    return
  }

  foreach ($window in $targets) {
    if (
      -not ($window.PSObject.Properties.Name -contains "id") -or
      -not ($window.PSObject.Properties.Name -contains "x") -or
      -not ($window.PSObject.Properties.Name -contains "y") -or
      -not ($window.PSObject.Properties.Name -contains "state") -or
      $null -eq $window.state -or
      -not ($window.state.PSObject.Properties.Name -contains "type") -or
      [string]$window.state.type -ne "tiling"
    ) {
      return
    }
  }

  $columns = @($targets |
    Group-Object x |
    Sort-Object { [double]$_.Name })
  $stationary = $null
  $moving = $null
  $moveDirection = $null

  if (
    $columns.Count -eq 4 -and
    @($columns | Where-Object { $_.Count -ne 1 }).Count -eq 0
  ) {
    $stationary = $columns[0].Group[0]
    $moving = $columns[1].Group[0]
    $moveDirection = "left"
  } elseif ($columns.Count -eq 3) {
    $singleColumnIndexes = @(for ($index = 0; $index -lt 3; $index++) {
      if ($columns[$index].Count -eq 1) {
        $index
      }
    })
    $pairColumns = @($columns | Where-Object { $_.Count -eq 2 })
    if ($singleColumnIndexes.Count -ne 2 -or $pairColumns.Count -ne 1) {
      return
    }
    if ($singleColumnIndexes[1] - $singleColumnIndexes[0] -eq 1) {
      $stationary = $columns[$singleColumnIndexes[1]].Group[0]
      $moving = $columns[$singleColumnIndexes[0]].Group[0]
      $moveDirection = "right"
    } elseif (
      $singleColumnIndexes[0] -eq 0 -and
      $singleColumnIndexes[1] -eq 2
    ) {
      $stationary = $columns[0].Group[0]
      $moving = @($columns[1].Group | Sort-Object y)[0]
      $moveDirection = "left"
    } else {
      return
    }
  } else {
    return
  }

  [pscustomobject]@{
    ContainerId = [string]$stationary.id
    Command = "set-tiling-direction vertical"
  }
  [pscustomobject]@{
    ContainerId = [string]$moving.id
    Command = "move --direction $moveDirection"
  }
}

function Test-GlazeWorkspaceTwoByTwo {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [AllowEmptyCollection()]
    [object[]]$Windows,

    [Parameter(Mandatory = $true)]
    [ValidateCount(4, 4)]
    [string[]]$ProcessNames
  )

  $targets = @($Windows | Where-Object {
    $null -ne $_ -and
    $_.PSObject.Properties.Name -contains "processName" -and
    [string]$_.processName -in $ProcessNames -and
    $_.PSObject.Properties.Name -contains "state" -and
    $null -ne $_.state -and
    $_.state.PSObject.Properties.Name -contains "type" -and
    [string]$_.state.type -eq "tiling"
  })
  if ($targets.Count -ne 4) {
    return $false
  }
  foreach ($processName in $ProcessNames) {
    if (@($targets | Where-Object {
      [string]$_.processName -eq $processName
    }).Count -ne 1) {
      return $false
    }
  }

  $columns = @($targets | Group-Object x)
  return (
    $columns.Count -eq 2 -and
    @($columns | Where-Object {
      $_.Count -eq 2 -and
      @($_.Group.y | Sort-Object -Unique).Count -eq 2
    }).Count -eq 2
  )
}

function Test-GlazeWorkspaceBalancedTwoByTwo {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [object]$Workspace,

    [Parameter(Mandatory = $true)]
    [AllowEmptyCollection()]
    [object[]]$Windows,

    [Parameter(Mandatory = $true)]
    [ValidateCount(4, 4)]
    [string[]]$ProcessNames,

    [ValidateRange(0, 10)]
    [int]$TolerancePixels = 2
  )

  if (-not (Test-GlazeWorkspaceTwoByTwo `
    -Windows $Windows `
    -ProcessNames $ProcessNames
  )) {
    return $false
  }
  foreach ($property in @("x", "y", "width", "height")) {
    if (-not ($Workspace.PSObject.Properties.Name -contains $property)) {
      return $false
    }
  }

  $targets = @($Windows | Where-Object {
    $null -ne $_ -and
    $_.PSObject.Properties.Name -contains "processName" -and
    [string]$_.processName -in $ProcessNames
  })
  foreach ($window in $targets) {
    foreach ($property in @("x", "y", "width", "height")) {
      if (-not ($window.PSObject.Properties.Name -contains $property)) {
        return $false
      }
    }
  }

  $left = [double](($targets | Measure-Object x -Minimum).Minimum)
  $top = [double](($targets | Measure-Object y -Minimum).Minimum)
  $right = [double](($targets | ForEach-Object {
    [double]$_.x + [double]$_.width
  } | Measure-Object -Maximum).Maximum)
  $bottom = [double](($targets | ForEach-Object {
    [double]$_.y + [double]$_.height
  } | Measure-Object -Maximum).Maximum)
  $widths = $targets | Measure-Object width -Minimum -Maximum
  $heights = $targets | Measure-Object height -Minimum -Maximum

  return (
    [math]::Abs($left - [double]$Workspace.x) -le $TolerancePixels -and
    [math]::Abs($top - [double]$Workspace.y) -le $TolerancePixels -and
    [math]::Abs(
      $right - ([double]$Workspace.x + [double]$Workspace.width)
    ) -le $TolerancePixels -and
    [math]::Abs(
      $bottom - ([double]$Workspace.y + [double]$Workspace.height)
    ) -le $TolerancePixels -and
    [math]::Abs(
      [double]$widths.Maximum - [double]$widths.Minimum
    ) -le $TolerancePixels -and
    [math]::Abs(
      [double]$heights.Maximum - [double]$heights.Minimum
    ) -le $TolerancePixels
  )
}

function Get-GlazeWorkspaceGridRebuildPlan {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [AllowEmptyCollection()]
    [object[]]$Windows,

    [Parameter(Mandatory = $true)]
    [ValidateCount(4, 4)]
    [string[]]$ProcessNames
  )

  $targets = @($ProcessNames | ForEach-Object {
    $processName = $_
    $matches = @($Windows | Where-Object {
      $null -ne $_ -and
      $_.PSObject.Properties.Name -contains "processName" -and
      [string]$_.processName -eq $processName
    })
    if ($matches.Count -ne 1) {
      return
    }
    $matches[0]
  })
  if ($targets.Count -ne 4) {
    return
  }
  $unknownTiling = @($Windows | Where-Object {
    $null -ne $_ -and
    $_.PSObject.Properties.Name -contains "state" -and
    $null -ne $_.state -and
    $_.state.PSObject.Properties.Name -contains "type" -and
    [string]$_.state.type -eq "tiling" -and
    (
      -not ($_.PSObject.Properties.Name -contains "processName") -or
      [string]$_.processName -notin $ProcessNames
    )
  })
  if ($unknownTiling.Count -gt 0) {
    return
  }

  $invalidTargets = @($targets | Where-Object {
    -not ($_.PSObject.Properties.Name -contains "id") -or
    -not ($_.PSObject.Properties.Name -contains "state") -or
    $null -eq $_.state -or
    [string]$_.state.type -ne "tiling"
  })
  if ($invalidTargets.Count -gt 0) {
    return
  }

  foreach ($window in $targets) {
    [pscustomobject]@{
      ContainerId = [string]$window.id
      Command = "set-floating --centered=false"
    }
  }
  foreach ($window in $targets) {
    [pscustomobject]@{
      ContainerId = [string]$window.id
      Command = "set-tiling"
    }
  }
}

function Invoke-GlazeStartupWorkspacePlacement {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string]$GlazeWMPath,

    [Parameter(Mandatory = $true)]
    [string]$ProcessName,

    [Parameter(Mandatory = $true)]
    [string]$WorkspaceName,

    [ValidateRange(1, 300)]
    [int]$WaitSeconds = 60,

    [scriptblock]$CommandInvoker
  )

  $deadline = (Get-Date).AddSeconds($WaitSeconds)
  $movedWindowIds = @{}
  do {
    $queryResult = Invoke-GlazeWMIPC `
      -GlazeWMPath $GlazeWMPath `
      -Arguments @("query", "workspaces") `
      -CommandInvoker $CommandInvoker
    if ($queryResult.ExitCode -ne 0) {
      throw "GlazeWM could not query startup windows for $ProcessName."
    }
    $response = $queryResult.Output |
      Out-String |
      ConvertFrom-Json -ErrorAction Stop
    if (
      -not ($response.PSObject.Properties.Name -contains "success") -or
      -not $response.success -or
      -not ($response.PSObject.Properties.Name -contains "data") -or
      $null -eq $response.data -or
      -not ($response.data.PSObject.Properties.Name -contains "workspaces")
    ) {
      throw "GlazeWM returned an invalid workspace response."
    }

    $targets = @(
      foreach ($workspace in @($response.data.workspaces)) {
        foreach ($window in @(Get-GlazeWindowsInContainer -Container $workspace)) {
          if (
            $window.PSObject.Properties.Name -contains "processName" -and
            [string]$window.processName -eq $ProcessName
          ) {
            [pscustomobject]@{
              Window = $window
              WorkspaceName = [string]$workspace.name
            }
          }
        }
      }
    )
    if (
      $targets.Count -gt 0 -and
      @($targets | Where-Object { $_.WorkspaceName -ne $WorkspaceName }).Count -eq 0
    ) {
      return
    }

    foreach ($target in @($targets | Where-Object {
      $_.WorkspaceName -ne $WorkspaceName
    })) {
      if (-not ($target.Window.PSObject.Properties.Name -contains "id")) {
        throw "GlazeWM returned a startup window without an ID."
      }
      $windowId = [string]$target.Window.id
      if ($movedWindowIds.ContainsKey($windowId)) {
        continue
      }
      $commandResult = Invoke-GlazeWMIPC `
        -GlazeWMPath $GlazeWMPath `
        -Arguments @(
          "command", "--id", $windowId, "move", "--workspace", $WorkspaceName
        ) `
        -CommandInvoker $CommandInvoker
      if ($commandResult.ExitCode -ne 0) {
        throw "GlazeWM could not place startup window for $ProcessName."
      }
      $movedWindowIds[$windowId] = $true
    }
    Start-Sleep -Milliseconds 500
  } while ((Get-Date) -lt $deadline)

  throw "Startup window for $ProcessName did not reach workspace $WorkspaceName."
}

function Invoke-GlazeWorkspaceGrid {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string]$GlazeWMPath,

    [Parameter(Mandatory = $true)]
    [string]$WorkspaceName,

    [Parameter(Mandatory = $true)]
    [ValidateCount(4, 4)]
    [string[]]$ProcessNames,

    [ValidateRange(1, 300)]
    [int]$WaitSeconds = 60,

    [scriptblock]$CommandInvoker
  )

  $deadline = (Get-Date).AddSeconds($WaitSeconds)
  $movesCompleted = 0
  $rebuildAttempted = $false
  do {
    $queryResult = Invoke-GlazeWMIPC `
      -GlazeWMPath $GlazeWMPath `
      -Arguments @("query", "workspaces") `
      -CommandInvoker $CommandInvoker
    if ($queryResult.ExitCode -ne 0) {
      throw "GlazeWM could not query workspace $WorkspaceName."
    }
    $response = $queryResult.Output |
      Out-String |
      ConvertFrom-Json -ErrorAction Stop
    if (
      -not ($response.PSObject.Properties.Name -contains "success") -or
      -not $response.success -or
      -not ($response.PSObject.Properties.Name -contains "data") -or
      $null -eq $response.data -or
      -not ($response.data.PSObject.Properties.Name -contains "workspaces")
    ) {
      throw "GlazeWM returned an invalid workspace response."
    }

    $workspace = Get-GlazeWorkspaceByName `
      -Workspaces @($response.data.workspaces) `
      -WorkspaceName $WorkspaceName
    if ($null -ne $workspace) {
      $windows = @(Get-GlazeWindowsInContainer -Container $workspace)
      $unmanagedWindows = @($windows | Where-Object {
        $_.PSObject.Properties.Name -notcontains "processName" -or
        [string]$_.processName -notin $ProcessNames
      })
      $duplicateManagedProcess = @(
        $ProcessNames | Where-Object {
          $processName = $_
          @($windows | Where-Object {
            $_.PSObject.Properties.Name -contains "processName" -and
            [string]$_.processName -eq $processName
          }).Count -gt 1
        }
      )
      if (
        $unmanagedWindows.Count -gt 0 -or
        $duplicateManagedProcess.Count -gt 0
      ) {
        return
      }
      if (Test-GlazeWorkspaceBalancedTwoByTwo `
        -Workspace $workspace `
        -Windows $windows `
        -ProcessNames $ProcessNames
      ) {
        return
      }

      $isTwoByTwo = Test-GlazeWorkspaceTwoByTwo `
        -Windows $windows `
        -ProcessNames $ProcessNames
      $isDisplayed = (
        $workspace.PSObject.Properties.Name -contains "isDisplayed" -and
        $workspace.isDisplayed
      )
      if ($isTwoByTwo -and -not $rebuildAttempted -and -not $isDisplayed) {
        $plan = @(Get-GlazeWorkspaceGridRebuildPlan `
          -Windows $windows `
          -ProcessNames $ProcessNames
        )
        if ($plan.Count -gt 0) {
          $rebuildAttempted = $true
        }
      } else {
        $plan = @(Get-GlazeWorkspaceGridPlan `
          -Windows $windows `
          -ProcessNames $ProcessNames
        )
      }
      if ($plan.Count -gt 0) {
        foreach ($step in $plan) {
          $isMove = [string]$step.Command -like "move *"
          if ($isMove -and $movesCompleted -ge 2) {
            throw "Workspace $WorkspaceName reached the safe move limit."
          }
          $arguments = @(
            "command",
            "--id",
            [string]$step.ContainerId
          ) + @([string]$step.Command -split " ")
          $commandResult = Invoke-GlazeWMIPC `
            -GlazeWMPath $GlazeWMPath `
            -Arguments $arguments `
            -CommandInvoker $CommandInvoker
          if ($commandResult.ExitCode -ne 0) {
            throw "GlazeWM could not arrange workspace $WorkspaceName."
          }
          if ($isMove) {
            $movesCompleted++
          }
          Start-Sleep -Milliseconds 250
        }
      }
    }
    Start-Sleep -Milliseconds 500
  } while ((Get-Date) -lt $deadline)

  throw "Workspace $WorkspaceName did not reach the managed two-by-two layout."
}

function Invoke-GlazeGameWorkspaceReconcile {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string]$GlazeWMPath,

    [string[]]$GameWorkspaceNames = @("11")
  )

  $response = & $GlazeWMPath query workspaces 2>$null |
    Out-String |
    ConvertFrom-Json -ErrorAction Stop
  if (
    -not ($response.PSObject.Properties.Name -contains "success") -or
    -not $response.success -or
    -not ($response.PSObject.Properties.Name -contains "data") -or
    $null -eq $response.data -or
    -not ($response.data.PSObject.Properties.Name -contains "workspaces")
  ) {
    throw "GlazeWM returned an invalid workspace response."
  }

  $gameWindows = @(Get-GlazeGameWorkspaceTilingWindows `
    -Workspaces @($response.data.workspaces) `
    -GameWorkspaceNames $GameWorkspaceNames
  )
  foreach ($gameWindow in $gameWindows) {
    & $GlazeWMPath command `
      --id ([string]$gameWindow.id) `
      set-floating `
      --centered=false 2>$null |
      Out-Null
    if ($LASTEXITCODE -ne 0) {
      throw "GlazeWM could not float window $($gameWindow.id)."
    }
  }
}

function Start-GlazeAutoTile {
  [CmdletBinding()]
  param(
    [string]$GlazeWMPath = (
      Join-Path $env:ProgramFiles "glzr.io\GlazeWM\cli\glazewm.exe"
    ),

    [ValidateRange(1, 30)]
    [int]$ReconnectDelaySeconds = 2,

    [string[]]$GameWorkspaceNames = @("11")
  )

  if (-not (Test-Path -LiteralPath $GlazeWMPath -PathType Leaf)) {
    throw "GlazeWM executable not found: $GlazeWMPath"
  }

  while ($true) {
    $applicationExiting = $false

    try {
      Invoke-GlazeGameWorkspaceReconcile `
        -GlazeWMPath $GlazeWMPath `
        -GameWorkspaceNames $GameWorkspaceNames

      & $GlazeWMPath sub -e `
        focus_changed `
        focused_container_moved `
        window_managed `
        workspace_updated `
        application_exiting 2>$null |
        ForEach-Object {
          $line = [string]$_
          if ([string]::IsNullOrWhiteSpace($line)) {
            return
          }

          try {
            $message = $line | ConvertFrom-Json -ErrorAction Stop
            if (
              $message.PSObject.Properties.Name -contains "data" -and
              $null -ne $message.data -and
              $message.data.PSObject.Properties.Name -contains "eventType" -and
              $message.data.eventType -eq "application_exiting"
            ) {
              $applicationExiting = $true
              return
            }
          } catch {
            return
          }

          try {
            Invoke-GlazeGameWorkspaceReconcile `
              -GlazeWMPath $GlazeWMPath `
              -GameWorkspaceNames $GameWorkspaceNames
          } catch {
            # A later workspace event retries reconciliation after reload races.
          }

          $focused = Get-GlazeFocusedWindowFromEvent -Json $line
          if (
            $null -eq $focused -or
            -not ($focused.PSObject.Properties.Name -contains "width") -or
            -not ($focused.PSObject.Properties.Name -contains "height")
          ) {
            return
          }

          $direction = Get-GlazeTilingDirection `
            -Width ([double]$focused.width) `
            -Height ([double]$focused.height)
          if ($null -eq $direction) {
            return
          }

          & $GlazeWMPath command set-tiling-direction $direction 2>$null |
            Out-Null
        }
    } catch {
      # A short IPC outage is expected while GlazeWM starts or reloads.
    }

    if ($applicationExiting) {
      return
    }

    Start-Sleep -Seconds $ReconnectDelaySeconds
  }
}

Export-ModuleMember -Function @(
  "Find-GlazeFocusedWindow",
  "Find-GlazeWorkspaceNameForContainer",
  "Get-GlazeGameWorkspaceTilingWindows",
  "Get-GlazeFocusedWindowFromEvent",
  "Get-GlazeTilingDirection",
  "Get-GlazeWindowsInContainer",
  "Get-GlazeWorkspaceGridPlan",
  "Get-GlazeWorkspaceGridRebuildPlan",
  "Invoke-GlazeGameWorkspaceReconcile",
  "Invoke-GlazeStartupWorkspacePlacement",
  "Invoke-GlazeWorkspaceGrid",
  "Start-GlazeAutoTile",
  "Test-GlazeContainerContainsId",
  "Test-GlazeWindowRequiresGameFloating",
  "Test-GlazeWorkspaceBalancedTwoByTwo",
  "Test-GlazeWorkspaceTwoByTwo"
)
