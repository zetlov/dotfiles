Describe "GlazeWM automatic tiling" {
  BeforeAll {
    $modulePath = Join-Path $PSScriptRoot "..\GlazeWMAutoTile.psm1"
    Import-Module $modulePath -Force -ErrorAction Stop

    function New-WorkspaceGridResponse {
      param(
        [bool]$Balanced,
        [bool]$Displayed = $false
      )

      $left = if ($Balanced) { 10 } else { 1286 }
      $width = if ($Balanced) { 1906 } else { 1268 }
      $right = if ($Balanced) { 1924 } else { 2562 }
      return @{
        success = $true
        data = @{
          workspaces = @(
            @{
              type = "workspace"
              name = "2"
              x = 10
              y = 52
              width = 3820
              height = 2098
              isDisplayed = $Displayed
              children = @(
                @{ type = "window"; id = "a"; processName = "Zotero"; x = $left; y = 52; width = $width; height = 1045; state = @{ type = "tiling" }; children = @() },
                @{ type = "window"; id = "b"; processName = "Raindrop"; x = $left; y = 1105; width = $width; height = 1045; state = @{ type = "tiling" }; children = @() },
                @{ type = "window"; id = "c"; processName = "Todoist"; x = $right; y = 52; width = $width; height = 1045; state = @{ type = "tiling" }; children = @() },
                @{ type = "window"; id = "d"; processName = "Notion Calendar"; x = $right; y = 1105; width = $width; height = 1045; state = @{ type = "tiling" }; children = @() }
              )
            }
          )
        }
      } | ConvertTo-Json -Depth 8 -Compress
    }
  }

  It "uses the horizontal direction for a wider focused window" {
    Get-GlazeTilingDirection -Width 900 -Height 600 |
      Should -Be "horizontal"
  }

  It "uses the vertical direction for a taller focused window" {
    Get-GlazeTilingDirection -Width 600 -Height 900 |
      Should -Be "vertical"
  }

  It "does not change direction for a square window" {
    Get-GlazeTilingDirection -Width 600 -Height 600 |
      Should -BeNullOrEmpty
  }

  It "finds a focused window nested inside a split container" {
    $container = [pscustomobject]@{
      type = "split"
      hasFocus = $false
      children = @(
        [pscustomobject]@{
          type = "window"
          hasFocus = $false
          width = 800
          height = 600
          children = @()
        },
        [pscustomobject]@{
          type = "split"
          hasFocus = $true
          children = @(
            [pscustomobject]@{
              type = "window"
              hasFocus = $true
              width = 400
              height = 700
              children = @()
            }
          )
        }
      )
    }

    $focused = Find-GlazeFocusedWindow -Container $container

    $focused.type | Should -Be "window"
    $focused.width | Should -Be 400
    $focused.height | Should -Be 700
  }

  It "extracts the focused window from supported event payloads" {
    $focusEvent = @{
      messageType = "event_subscription"
      data = @{
        eventType = "focus_changed"
        focusedContainer = @{
          type = "window"
          hasFocus = $true
          width = 1000
          height = 500
          children = @()
        }
      }
    } | ConvertTo-Json -Depth 8

    $moveEvent = @{
      messageType = "event_subscription"
      data = @{
        eventType = "focused_container_moved"
        focusedContainer = @{
          type = "split"
          hasFocus = $true
          children = @(
            @{
              type = "window"
              hasFocus = $true
              width = 300
              height = 700
              children = @()
            }
          )
        }
      }
    } | ConvertTo-Json -Depth 8

    (Get-GlazeFocusedWindowFromEvent -Json $focusEvent).width |
      Should -Be 1000
    (Get-GlazeFocusedWindowFromEvent -Json $moveEvent).height |
      Should -Be 700
  }

  It "accepts the GlazeWM 3.10 subscription envelope" {
    $event = @{
      success = $true
      subscriptionId = "test-subscription"
      data = @{
        eventType = "focus_changed"
        focusedContainer = @{
          type = "window"
          hasFocus = $true
          width = 758
          height = 2140
          children = @()
        }
      }
      error = $null
    } | ConvertTo-Json -Depth 8

    $focused = Get-GlazeFocusedWindowFromEvent -Json $event

    $focused.width | Should -Be 758
    $focused.height | Should -Be 2140
  }

  It "ignores client responses and unrelated events" {
    Get-GlazeFocusedWindowFromEvent -Json '{"messageType":"client_response"}' |
      Should -BeNullOrEmpty
    Get-GlazeFocusedWindowFromEvent -Json '{"messageType":"event_subscription","data":{"eventType":"workspace_updated"}}' |
      Should -BeNullOrEmpty
  }

  It "rejects malformed IPC JSON without terminating the daemon" {
    { Get-GlazeFocusedWindowFromEvent -Json 'not json' } |
      Should -Not -Throw
  }

  It "finds the workspace that contains a nested window" {
    $workspaces = @(
      [pscustomobject]@{
        type = "workspace"
        id = "workspace-11"
        name = "11"
        children = @(
          [pscustomobject]@{
            type = "split"
            id = "split-a"
            children = @(
              [pscustomobject]@{
                type = "window"
                id = "game-window"
                children = @()
              }
            )
          }
        )
      }
    )

    Find-GlazeWorkspaceNameForContainer `
      -Workspaces $workspaces `
      -ContainerId "game-window" |
      Should -Be "11"
  }

  It "floats tiling windows on the managed game workspaces" {
    $window = [pscustomobject]@{
      type = "window"
      id = "game-window"
      state = [pscustomobject]@{ type = "tiling" }
    }

    Test-GlazeWindowRequiresGameFloating `
      -Window $window `
      -WorkspaceName "11" `
      -GameWorkspaceNames @("11") |
      Should -Be $true
  }

  It "leaves floating and ordinary workspace windows unchanged" {
    $floating = [pscustomobject]@{
      type = "window"
      id = "floating-window"
      state = [pscustomobject]@{ type = "floating" }
    }
    $tiling = [pscustomobject]@{
      type = "window"
      id = "tiling-window"
      state = [pscustomobject]@{ type = "tiling" }
    }

    Test-GlazeWindowRequiresGameFloating `
      -Window $floating `
      -WorkspaceName "11" `
      -GameWorkspaceNames @("11") |
      Should -Be $false
    Test-GlazeWindowRequiresGameFloating `
      -Window $tiling `
      -WorkspaceName "4" `
      -GameWorkspaceNames @("11") |
      Should -Be $false
  }

  It "finds every tiling window in game workspaces without requiring focus" {
    $workspaces = @(
      [pscustomobject]@{
        type = "workspace"
        name = "11"
        children = @(
          [pscustomobject]@{
            type = "split"
            children = @(
              [pscustomobject]@{
                type = "window"
                id = "unfocused-game"
                hasFocus = $false
                state = [pscustomobject]@{ type = "tiling" }
                children = @()
              },
              [pscustomobject]@{
                type = "window"
                id = "already-floating"
                hasFocus = $false
                state = [pscustomobject]@{ type = "floating" }
                children = @()
              }
            )
          }
        )
      },
      [pscustomobject]@{
        type = "workspace"
        name = "4"
        children = @(
          [pscustomobject]@{
            type = "window"
            id = "ordinary-window"
            state = [pscustomobject]@{ type = "tiling" }
            children = @()
          }
        )
      }
    )

    $windows = @(
      Get-GlazeGameWorkspaceTilingWindows `
        -Workspaces $workspaces `
        -GameWorkspaceNames @("11")
    )

    $windows.Count | Should -Be 1
    $windows[0].id | Should -Be "unfocused-game"
  }

  It "reconciles game workspaces before waiting for subscription events" {
    $module = Get-Content -LiteralPath $modulePath -Raw

    $module | Should -Match '(?s)try \{\r?\n\s+Invoke-GlazeGameWorkspaceReconcile.+?& \$GlazeWMPath sub -e'
  }

  It "defaults to workspace eleven as the only game workspace" {
    $module = Get-Content -LiteralPath $modulePath -Raw

    $module | Should -Match '\[string\[\]\]\$GameWorkspaceNames = @\("11"\)'
    $module | Should -Not -Match '@\("11", "12"\)'
  }

  It "pairs the two leftmost windows from a four-column layout" {
    $windows = @(
      [pscustomobject]@{ id = "a"; x = 0; y = 0; processName = "Zotero"; state = [pscustomobject]@{ type = "tiling" } },
      [pscustomobject]@{ id = "b"; x = 500; y = 0; processName = "Raindrop"; state = [pscustomobject]@{ type = "tiling" } },
      [pscustomobject]@{ id = "c"; x = 1000; y = 0; processName = "Todoist"; state = [pscustomobject]@{ type = "tiling" } },
      [pscustomobject]@{ id = "d"; x = 1500; y = 0; processName = "Notion Calendar"; state = [pscustomobject]@{ type = "tiling" } }
    )

    $plan = @(Get-GlazeWorkspaceGridPlan `
      -Windows $windows `
      -ProcessNames @("Zotero", "Raindrop", "Todoist", "Notion Calendar"))

    @($plan | ForEach-Object { "$($_.ContainerId):$($_.Command)" }) -join "|" |
      Should -Be "a:set-tiling-direction vertical|b:move --direction left"
  }

  It "pairs the remaining adjacent single windows from a three-column layout" {
    $windows = @(
      [pscustomobject]@{ id = "a"; x = 0; y = 0; processName = "Zotero"; state = [pscustomobject]@{ type = "tiling" } },
      [pscustomobject]@{ id = "b"; x = 0; y = 500; processName = "Todoist"; state = [pscustomobject]@{ type = "tiling" } },
      [pscustomobject]@{ id = "c"; x = 500; y = 0; processName = "Notion Calendar"; state = [pscustomobject]@{ type = "tiling" } },
      [pscustomobject]@{ id = "d"; x = 1000; y = 0; processName = "Raindrop"; state = [pscustomobject]@{ type = "tiling" } }
    )

    $plan = @(Get-GlazeWorkspaceGridPlan `
      -Windows $windows `
      -ProcessNames @("Zotero", "Raindrop", "Todoist", "Notion Calendar"))

    @($plan | ForEach-Object { "$($_.ContainerId):$($_.Command)" }) -join "|" |
      Should -Be "d:set-tiling-direction vertical|c:move --direction right"
  }

  It "splits a center pair toward the adjacent left single window" {
    $windows = @(
      [pscustomobject]@{ id = "a"; x = 0; y = 0; processName = "Raindrop"; state = [pscustomobject]@{ type = "tiling" } },
      [pscustomobject]@{ id = "b"; x = 500; y = 0; processName = "Notion Calendar"; state = [pscustomobject]@{ type = "tiling" } },
      [pscustomobject]@{ id = "c"; x = 500; y = 500; processName = "Todoist"; state = [pscustomobject]@{ type = "tiling" } },
      [pscustomobject]@{ id = "d"; x = 1000; y = 0; processName = "Zotero"; state = [pscustomobject]@{ type = "tiling" } }
    )

    $plan = @(Get-GlazeWorkspaceGridPlan `
      -Windows $windows `
      -ProcessNames @("Zotero", "Raindrop", "Todoist", "Notion Calendar"))

    @($plan | ForEach-Object { "$($_.ContainerId):$($_.Command)" }) -join "|" |
      Should -Be "a:set-tiling-direction vertical|b:move --direction left"
  }

  It "does not rearrange incomplete, duplicate, complete, or unsafe layouts" {
    $base = @(
      [pscustomobject]@{ id = "a"; x = 0; y = 0; processName = "Zotero"; state = [pscustomobject]@{ type = "tiling" } },
      [pscustomobject]@{ id = "b"; x = 500; y = 0; processName = "Raindrop"; state = [pscustomobject]@{ type = "tiling" } },
      [pscustomobject]@{ id = "c"; x = 1000; y = 0; processName = "Todoist"; state = [pscustomobject]@{ type = "tiling" } },
      [pscustomobject]@{ id = "d"; x = 1500; y = 0; processName = "Notion Calendar"; state = [pscustomobject]@{ type = "tiling" } }
    )
    $names = @("Zotero", "Raindrop", "Todoist", "Notion Calendar")

    @(Get-GlazeWorkspaceGridPlan -Windows $base[0..2] -ProcessNames $names).Count |
      Should -Be 0
    $duplicate = @($base) + @($base[0])
    @(Get-GlazeWorkspaceGridPlan -Windows $duplicate -ProcessNames $names).Count |
      Should -Be 0
    $grid = @($base | ForEach-Object { $_.PSObject.Copy() })
    $grid[1].x = 0
    $grid[1].y = 500
    $grid[3].x = 1000
    $grid[3].y = 500
    @(Get-GlazeWorkspaceGridPlan -Windows $grid -ProcessNames $names).Count |
      Should -Be 0

    $unknown = @($base) + @(
      [pscustomobject]@{ id = "other"; x = 2000; y = 0; processName = "Other"; state = [pscustomobject]@{ type = "tiling" } }
    )
    @(Get-GlazeWorkspaceGridPlan -Windows $unknown -ProcessNames $names).Count |
      Should -Be 0
  }

  It "accepts only an equal two-by-two grid that fills the workspace" {
    $workspace = [pscustomobject]@{
      x = 10
      y = 52
      width = 3820
      height = 2098
    }
    $names = @("Zotero", "Raindrop", "Todoist", "Notion Calendar")
    $grid = @(
      [pscustomobject]@{ id = "a"; x = 10; y = 52; width = 1906; height = 1045; processName = "Zotero"; state = [pscustomobject]@{ type = "tiling" } },
      [pscustomobject]@{ id = "b"; x = 10; y = 1105; width = 1906; height = 1045; processName = "Raindrop"; state = [pscustomobject]@{ type = "tiling" } },
      [pscustomobject]@{ id = "c"; x = 1924; y = 52; width = 1906; height = 1045; processName = "Todoist"; state = [pscustomobject]@{ type = "tiling" } },
      [pscustomobject]@{ id = "d"; x = 1924; y = 1105; width = 1906; height = 1045; processName = "Notion Calendar"; state = [pscustomobject]@{ type = "tiling" } }
    )

    Test-GlazeWorkspaceBalancedTwoByTwo `
      -Workspace $workspace `
      -Windows $grid `
      -ProcessNames $names |
      Should -Be $true

    $shifted = @($grid | ForEach-Object { $_.PSObject.Copy() })
    foreach ($window in $shifted) {
      $window.x += 1276
      $window.width = 1268
    }
    Test-GlazeWorkspaceBalancedTwoByTwo `
      -Workspace $workspace `
      -Windows $shifted `
      -ProcessNames $names |
      Should -Be $false
  }

  It "rebuilds only the four managed windows when a hidden grid is unbalanced" {
    $windows = @(
      [pscustomobject]@{ id = "a"; processName = "Zotero"; state = [pscustomobject]@{ type = "tiling" } },
      [pscustomobject]@{ id = "b"; processName = "Raindrop"; state = [pscustomobject]@{ type = "tiling" } },
      [pscustomobject]@{ id = "c"; processName = "Todoist"; state = [pscustomobject]@{ type = "tiling" } },
      [pscustomobject]@{ id = "d"; processName = "Notion Calendar"; state = [pscustomobject]@{ type = "tiling" } },
      [pscustomobject]@{ id = "minimized"; processName = "OpenWith"; state = [pscustomobject]@{ type = "minimized" } }
    )

    $plan = @(Get-GlazeWorkspaceGridRebuildPlan `
      -Windows $windows `
      -ProcessNames @("Zotero", "Raindrop", "Todoist", "Notion Calendar"))

    @($plan | ForEach-Object { "$($_.ContainerId):$($_.Command)" }) -join "|" |
      Should -Be (
        "a:set-floating --centered=false|" +
        "b:set-floating --centered=false|" +
        "c:set-floating --centered=false|" +
        "d:set-floating --centered=false|" +
        "a:set-tiling|b:set-tiling|c:set-tiling|d:set-tiling"
      )
  }

  It "does not return a partial rebuild plan when a later target is invalid" {
    $windows = @(
      [pscustomobject]@{ id = "a"; processName = "Zotero"; state = [pscustomobject]@{ type = "tiling" } },
      [pscustomobject]@{ id = "b"; processName = "Raindrop"; state = [pscustomobject]@{ type = "tiling" } },
      [pscustomobject]@{ id = "c"; processName = "Todoist"; state = [pscustomobject]@{ type = "tiling" } },
      [pscustomobject]@{ processName = "Notion Calendar"; state = [pscustomobject]@{ type = "tiling" } }
    )

    @(Get-GlazeWorkspaceGridRebuildPlan `
      -Windows $windows `
      -ProcessNames @("Zotero", "Raindrop", "Todoist", "Notion Calendar")
    ).Count | Should -Be 0
  }

  It "returns without commands when the workspace is already balanced" {
    $script:gridInvocations = @()
    $invoker = {
      param($request)
      $arguments = @($request.Arguments)
      $script:gridInvocations += , @($arguments)
      [pscustomobject]@{
        Output = @(New-WorkspaceGridResponse -Balanced $true)
        ExitCode = 0
      }
    }

    Invoke-GlazeWorkspaceGrid `
      -GlazeWMPath "fake-glazewm.exe" `
      -WorkspaceName "2" `
      -ProcessNames @("Zotero", "Raindrop", "Todoist", "Notion Calendar") `
      -WaitSeconds 1 `
      -CommandInvoker $invoker

    $script:gridInvocations.Count | Should -Be 1
    $script:gridInvocations[0] -join " " | Should -Be "query workspaces"
  }

  It "skips a workspace that contains an unmanaged window" {
    $script:gridInvocations = @()
    $invoker = {
      param($request)
      $arguments = @($request.Arguments)
      $script:gridInvocations += , @($arguments)
      $response = New-WorkspaceGridResponse -Balanced $false |
        ConvertFrom-Json
      $response.data.workspaces[0].children += [pscustomobject]@{
        type = "window"
        id = "other"
        processName = "wezterm-gui"
        state = [pscustomobject]@{ type = "tiling" }
        children = @()
      }
      [pscustomobject]@{
        Output = @($response | ConvertTo-Json -Depth 8 -Compress)
        ExitCode = 0
      }
    }

    Invoke-GlazeWorkspaceGrid `
      -GlazeWMPath "fake-glazewm.exe" `
      -WorkspaceName "2" `
      -ProcessNames @("Zotero", "Raindrop", "Todoist", "Notion Calendar") `
      -WaitSeconds 1 `
      -CommandInvoker $invoker

    $script:gridInvocations.Count | Should -Be 1
  }

  It "rebuilds a hidden unbalanced grid in a guarded eight-command sequence" {
    $script:gridInvocations = @()
    $script:gridQueryCount = 0
    $invoker = {
      param($request)
      $arguments = @($request.Arguments)
      $script:gridInvocations += , @($arguments)
      if ($arguments[0] -eq "query") {
        $script:gridQueryCount++
        return [pscustomobject]@{
          Output = @(New-WorkspaceGridResponse `
            -Balanced ($script:gridQueryCount -gt 1))
          ExitCode = 0
        }
      }
      return [pscustomobject]@{ Output = @(); ExitCode = 0 }
    }

    Invoke-GlazeWorkspaceGrid `
      -GlazeWMPath "fake-glazewm.exe" `
      -WorkspaceName "2" `
      -ProcessNames @("Zotero", "Raindrop", "Todoist", "Notion Calendar") `
      -WaitSeconds 5 `
      -CommandInvoker $invoker

    @($script:gridInvocations[1..8] | ForEach-Object { $_ -join " " }) -join "|" |
      Should -Be (
        "command --id a set-floating --centered=false|" +
        "command --id b set-floating --centered=false|" +
        "command --id c set-floating --centered=false|" +
        "command --id d set-floating --centered=false|" +
        "command --id a set-tiling|command --id b set-tiling|" +
        "command --id c set-tiling|command --id d set-tiling"
      )
    $script:gridInvocations[9] -join " " | Should -Be "query workspaces"
  }

  It "does not rebuild an unbalanced grid while it is displayed" {
    $script:gridInvocations = @()
    $invoker = {
      param($request)
      $arguments = @($request.Arguments)
      $script:gridInvocations += , @($arguments)
      [pscustomobject]@{
        Output = @(New-WorkspaceGridResponse `
          -Balanced $false `
          -Displayed $true)
        ExitCode = 0
      }
    }

    { Invoke-GlazeWorkspaceGrid `
      -GlazeWMPath "fake-glazewm.exe" `
      -WorkspaceName "2" `
      -ProcessNames @("Zotero", "Raindrop", "Todoist", "Notion Calendar") `
      -WaitSeconds 1 `
      -CommandInvoker $invoker
    } | Should -Throw "*did not reach the managed two-by-two layout*"
    @($script:gridInvocations | Where-Object { $_[0] -eq "command" }).Count |
      Should -Be 0
  }

  It "stops immediately when a workspace command fails" {
    $script:gridInvocations = @()
    $invoker = {
      param($request)
      $arguments = @($request.Arguments)
      $script:gridInvocations += , @($arguments)
      if ($arguments[0] -eq "query") {
        return [pscustomobject]@{
          Output = @(New-WorkspaceGridResponse -Balanced $false)
          ExitCode = 0
        }
      }
      return [pscustomobject]@{ Output = @(); ExitCode = 1 }
    }

    { Invoke-GlazeWorkspaceGrid `
      -GlazeWMPath "fake-glazewm.exe" `
      -WorkspaceName "2" `
      -ProcessNames @("Zotero", "Raindrop", "Todoist", "Notion Calendar") `
      -WaitSeconds 5 `
      -CommandInvoker $invoker
    } | Should -Throw "*could not arrange workspace 2*"
    $script:gridInvocations.Count | Should -Be 2
  }
}
