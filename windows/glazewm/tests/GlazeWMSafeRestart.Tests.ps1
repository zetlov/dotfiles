Describe "GlazeWM safe monitor expansion" {
  BeforeAll {
    $modulePath = Join-Path $PSScriptRoot "..\GlazeWMSafeRestart.psm1"
    Import-Module $modulePath -Force -ErrorAction Stop
  }

  It "uses the safe restart path only when expanding from one monitor" {
    Test-GlazeMonitorExpansion -CurrentMonitorCount 1 -ProfileName "all" |
      Should -BeTrue
    Test-GlazeMonitorExpansion `
      -CurrentMonitorCount 1 `
      -ProfileName "left-center" |
      Should -BeTrue
    Test-GlazeMonitorExpansion `
      -CurrentMonitorCount 1 `
      -ProfileName "right-only" |
      Should -BeFalse
    Test-GlazeMonitorExpansion -CurrentMonitorCount 2 -ProfileName "all" |
      Should -BeFalse
  }

  It "captures windows by handle with their workspace, state, and focus" {
    $monitors = @(
      [pscustomobject]@{
        type = "monitor"
        children = @(
          [pscustomobject]@{
            type = "workspace"
            name = "2"
            hasFocus = $true
            children = @(
              [pscustomobject]@{
                type = "split"
                children = @(
                  [pscustomobject]@{
                    type = "window"
                    id = "old-a"
                    handle = 101
                    hasFocus = $true
                    state = [pscustomobject]@{ type = "floating" }
                  }
                )
              }
            )
          }
        )
      }
    )

    $snapshot = New-GlazeWindowSnapshot -Monitors $monitors

    $snapshot.FocusedWorkspaceName | Should -Be "2"
    $snapshot.Windows.Count | Should -Be 1
    $snapshot.Windows[0].Handle | Should -Be 101
    $snapshot.Windows[0].WorkspaceName | Should -Be "2"
    $snapshot.Windows[0].StateType | Should -Be "floating"
    $snapshot.Windows[0].WasFocused | Should -BeTrue
  }

  It "fails closed when a snapshot contains duplicate handles" {
    $window = [pscustomobject]@{
      type = "window"
      id = "duplicate"
      handle = 101
      hasFocus = $false
      state = [pscustomobject]@{ type = "tiling" }
    }
    $monitors = @(
      [pscustomobject]@{
        type = "monitor"
        children = @(
          [pscustomobject]@{
            type = "workspace"
            name = "1"
            hasFocus = $true
            children = @($window, $window)
          }
        )
      }
    )

    { New-GlazeWindowSnapshot -Monitors $monitors } |
      Should -Throw "*duplicate window handle*"
  }

  It "treats a lost IPC endpoint as a completed graceful exit" {
    InModuleScope GlazeWMSafeRestart {
      Mock Get-GlazeManagerProcessIds { @() }
      Mock Invoke-GlazeCommand {}
      Mock Test-GlazeManagerActive { $false }
      Mock Start-Sleep {}

      {
        Stop-GlazeManagerSafely `
          -GlazeWMPath "C:\GlazeWM\glazewm.exe" `
          -ManagerPath "C:\GlazeWM\glazewm-manager.exe"
      } | Should -Not -Throw
    }
  }

  It "does not stop GlazeWM or apply DisplayConfig when uncloak fails" {
    InModuleScope GlazeWMSafeRestart {
      Mock Get-GlazeManagerProcessIds { @() }
      $global:GlazeSafeRestartApplyCalled = $false
      Mock New-GlazeWindowSnapshot {
        [pscustomobject]@{ Windows = @(); FocusedWorkspaceName = "1" }
      }
      Mock Toggle-GlazeManagerPause {}
      Mock Assert-GlazeSnapshotWindowsUncloaked { throw "still cloaked" }
      Mock Stop-GlazeManagerSafely {}

      try {
        {
          Invoke-GlazeSafeMonitorExpansion `
            -GlazeWMPath "C:\GlazeWM\glazewm.exe" `
            -ManagerPath "C:\GlazeWM\glazewm-manager.exe" `
            -ConfigPath "C:\GlazeWM\config.yaml" `
            -MonitorSyncModulePath "C:\GlazeWM\sync.psm1" `
            -ApplyProfile {
              $global:GlazeSafeRestartApplyCalled = $true
            }
        } | Should -Throw "*still cloaked*"

        Should -Invoke Stop-GlazeManagerSafely -Times 0 -Exactly
        Should -Invoke Toggle-GlazeManagerPause -Times 2 -Exactly
        $global:GlazeSafeRestartApplyCalled | Should -BeFalse
      } finally {
        Remove-Variable GlazeSafeRestartApplyCalled -Scope Global `
          -ErrorAction SilentlyContinue
      }
    }
  }

  It "rechecks pause state and retries when the first resume response fails" {
    InModuleScope GlazeWMSafeRestart {
      Mock Get-GlazeManagerProcessIds { @() }
      $global:GlazeSafeRestartToggleCount = 0
      $global:GlazeSafeRestartPausedChecks = 0
      $global:GlazeSafeRestartApplyCalled = $false
      Mock New-GlazeWindowSnapshot {
        [pscustomobject]@{ Windows = @(); FocusedWorkspaceName = "1" }
      }
      Mock Toggle-GlazeManagerPause {
        $global:GlazeSafeRestartToggleCount++
        if ($global:GlazeSafeRestartToggleCount -eq 2) {
          throw "resume response lost"
        }
      }
      Mock Get-GlazeManagerPaused {
        $global:GlazeSafeRestartPausedChecks++
        return $global:GlazeSafeRestartPausedChecks -eq 1
      }
      Mock Assert-GlazeSnapshotWindowsUncloaked {}
      Mock Stop-GlazeManagerSafely {}
      Mock Show-GlazeSnapshotWindows {}
      Mock Start-GlazeManagerSafely {}
      Mock Wait-GlazeManagerReady {}
      Mock Sync-GlazeMonitorTopology {}
      Mock Restore-GlazeWindowSnapshot {}

      try {
        Invoke-GlazeSafeMonitorExpansion `
          -GlazeWMPath "C:\GlazeWM\glazewm.exe" `
          -ManagerPath "C:\GlazeWM\glazewm-manager.exe" `
          -ConfigPath "C:\GlazeWM\config.yaml" `
          -MonitorSyncModulePath "C:\GlazeWM\sync.psm1" `
          -ApplyProfile {
            $global:GlazeSafeRestartApplyCalled = $true
          } |
          Out-Null

        $global:GlazeSafeRestartToggleCount | Should -Be 3
        $global:GlazeSafeRestartApplyCalled | Should -BeTrue
      } finally {
        Remove-Variable GlazeSafeRestartToggleCount -Scope Global `
          -ErrorAction SilentlyContinue
        Remove-Variable GlazeSafeRestartPausedChecks -Scope Global `
          -ErrorAction SilentlyContinue
        Remove-Variable GlazeSafeRestartApplyCalled -Scope Global `
          -ErrorAction SilentlyContinue
      }
    }
  }

  It "orders snapshot protection before exit and restores after restart" {
    InModuleScope GlazeWMSafeRestart {
      Mock Get-GlazeManagerProcessIds { @() }
      $global:GlazeSafeRestartOrder = [Collections.Generic.List[string]]::new()
      Mock New-GlazeWindowSnapshot {
        $global:GlazeSafeRestartOrder.Add("snapshot")
        [pscustomobject]@{ Windows = @(); FocusedWorkspaceName = "1" }
      }
      Mock Toggle-GlazeManagerPause {
        $global:GlazeSafeRestartOrder.Add("pause")
      }
      Mock Assert-GlazeSnapshotWindowsUncloaked {
        $global:GlazeSafeRestartOrder.Add("uncloak")
      }
      Mock Stop-GlazeManagerSafely {
        $global:GlazeSafeRestartOrder.Add("stop")
      }
      Mock Show-GlazeSnapshotWindows {
        $global:GlazeSafeRestartOrder.Add("show")
      }
      Mock Start-GlazeManagerSafely {
        param(
          $ManagerPath,
          $ConfigPath,
          $StartupRuntimeRoot,
          $SkipStartupApplications
        )
        $StartupRuntimeRoot | Should -Be "C:\GlazeWM"
        $SkipStartupApplications | Should -BeTrue
        $global:GlazeSafeRestartOrder.Add("start")
      }
      Mock Wait-GlazeManagerReady {
        $global:GlazeSafeRestartOrder.Add("ready")
      }
      Mock Sync-GlazeMonitorTopology {
        $global:GlazeSafeRestartOrder.Add("sync")
      }
      Mock Restore-GlazeWindowSnapshot {
        $global:GlazeSafeRestartOrder.Add("restore")
      }

      try {
        Invoke-GlazeSafeMonitorExpansion `
          -GlazeWMPath "C:\GlazeWM\glazewm.exe" `
          -ManagerPath "C:\GlazeWM\glazewm-manager.exe" `
          -ConfigPath "C:\GlazeWM\config.yaml" `
          -MonitorSyncModulePath "C:\GlazeWM\sync.psm1" `
          -ApplyProfile { $global:GlazeSafeRestartOrder.Add("apply") } |
          Out-Null

        @($global:GlazeSafeRestartOrder) | Should -Be @(
          "snapshot", "pause", "uncloak", "pause", "stop", "apply", "show", "start",
          "ready", "sync", "restore"
        )
      } finally {
        Remove-Variable GlazeSafeRestartOrder -Scope Global `
          -ErrorAction SilentlyContinue
      }
    }
  }

  It "restarts and restores GlazeWM when profile application fails" {
    InModuleScope GlazeWMSafeRestart {
      Mock Get-GlazeManagerProcessIds { @() }
      Mock New-GlazeWindowSnapshot {
        [pscustomobject]@{ Windows = @(); FocusedWorkspaceName = "1" }
      }
      Mock Toggle-GlazeManagerPause {}
      Mock Assert-GlazeSnapshotWindowsUncloaked {}
      Mock Stop-GlazeManagerSafely {}
      Mock Show-GlazeSnapshotWindows {}
      Mock Start-GlazeManagerSafely {}
      Mock Wait-GlazeManagerReady {}
      Mock Sync-GlazeMonitorTopology {}
      Mock Restore-GlazeWindowSnapshot {}

      {
        Invoke-GlazeSafeMonitorExpansion `
          -GlazeWMPath "C:\GlazeWM\glazewm.exe" `
          -ManagerPath "C:\GlazeWM\glazewm-manager.exe" `
          -ConfigPath "C:\GlazeWM\config.yaml" `
          -MonitorSyncModulePath "C:\GlazeWM\sync.psm1" `
          -ApplyProfile { throw "DisplayConfig failed" }
      } | Should -Throw "*DisplayConfig failed*"

      Should -Invoke Start-GlazeManagerSafely -Times 1 -Exactly
      Should -Invoke Restore-GlazeWindowSnapshot -Times 1 -Exactly
    }
  }

  It "still restarts the manager when post-exit window showing fails" {
    InModuleScope GlazeWMSafeRestart {
      Mock Get-GlazeManagerProcessIds { @() }
      Mock New-GlazeWindowSnapshot {
        [pscustomobject]@{ Windows = @(); FocusedWorkspaceName = "1" }
      }
      Mock Toggle-GlazeManagerPause {}
      Mock Assert-GlazeSnapshotWindowsUncloaked {}
      Mock Stop-GlazeManagerSafely {}
      Mock Show-GlazeSnapshotWindows { throw "window closed" }
      Mock Start-GlazeManagerSafely {}
      Mock Wait-GlazeManagerReady {}
      Mock Sync-GlazeMonitorTopology {}
      Mock Restore-GlazeWindowSnapshot {}

      {
        Invoke-GlazeSafeMonitorExpansion `
          -GlazeWMPath "C:\GlazeWM\glazewm.exe" `
          -ManagerPath "C:\GlazeWM\glazewm-manager.exe" `
          -ConfigPath "C:\GlazeWM\config.yaml" `
          -MonitorSyncModulePath "C:\GlazeWM\sync.psm1" `
          -ApplyProfile { "applied" }
      } | Should -Throw "*window closed*"

      Should -Invoke Start-GlazeManagerSafely -Times 1 -Exactly
      Should -Invoke Restore-GlazeWindowSnapshot -Times 1 -Exactly
    }
  }

  It "restarts when wm-exit reports an error after the manager stopped" {
    InModuleScope GlazeWMSafeRestart {
      Mock Get-GlazeManagerProcessIds { @() }
      Mock New-GlazeWindowSnapshot {
        [pscustomobject]@{ Windows = @(); FocusedWorkspaceName = "1" }
      }
      Mock Toggle-GlazeManagerPause {}
      Mock Assert-GlazeSnapshotWindowsUncloaked {}
      Mock Stop-GlazeManagerSafely { throw "exit response lost" }
      Mock Test-GlazeManagerActive { $false }
      Mock Show-GlazeSnapshotWindows {}
      Mock Start-GlazeManagerSafely {}
      Mock Wait-GlazeManagerReady {}
      Mock Sync-GlazeMonitorTopology {}
      Mock Restore-GlazeWindowSnapshot {}

      {
        Invoke-GlazeSafeMonitorExpansion `
          -GlazeWMPath "C:\GlazeWM\glazewm.exe" `
          -ManagerPath "C:\GlazeWM\glazewm-manager.exe" `
          -ConfigPath "C:\GlazeWM\config.yaml" `
          -MonitorSyncModulePath "C:\GlazeWM\sync.psm1" `
          -ApplyProfile { throw "must not run" }
      } | Should -Throw "*exit response lost*"

      Should -Invoke Start-GlazeManagerSafely -Times 1 -Exactly
    }
  }

  It "restores by handle, moves first, minimizes last, and focuses last" {
    InModuleScope GlazeWMSafeRestart {
      $global:GlazeSafeRestartCommands =
        [Collections.Generic.List[string]]::new()
      Mock Get-GlazeCurrentWindows {
        @(
          [pscustomobject]@{ id = "new-a"; handle = 101 },
          [pscustomobject]@{ id = "new-b"; handle = 202 },
          [pscustomobject]@{ id = "new-c"; handle = 303 }
        )
      }
      Mock Invoke-GlazeCommand {
        param($GlazeWMPath, $Arguments)
        $global:GlazeSafeRestartCommands.Add($Arguments -join " ")
      }
      $snapshot = [pscustomobject]@{
        FocusedWorkspaceName = "2"
        Windows = @(
          [pscustomobject]@{
            Handle = 101
            WorkspaceName = "2"
            StateType = "floating"
            State = [pscustomobject]@{ shownOnTop = $false }
            WasFocused = $true
          },
          [pscustomobject]@{
            Handle = 202
            WorkspaceName = "3"
            StateType = "minimized"
            State = [pscustomobject]@{ type = "minimized" }
            WasFocused = $false
          },
          [pscustomobject]@{
            Handle = 303
            WorkspaceName = "4"
            StateType = "fullscreen"
            State = [pscustomobject]@{
              type = "fullscreen"
              maximized = $true
              shownOnTop = $true
            }
            WasFocused = $false
          }
        )
      }

      try {
        Restore-GlazeWindowSnapshot `
          -GlazeWMPath "C:\GlazeWM\glazewm.exe" `
          -Snapshot $snapshot

        @($global:GlazeSafeRestartCommands) | Should -Be @(
          "command --id new-a move --workspace 2",
          (
            "command --id new-a set-floating --centered=false " +
            "--shown-on-top=false"
          ),
          "command --id new-b move --workspace 3",
          "command --id new-c move --workspace 4",
          (
            "command --id new-c set-fullscreen --maximized=true " +
            "--shown-on-top=true"
          ),
          "command --id new-b set-minimized",
          "command focus --workspace 2",
          "command --id new-a focus"
        )
      } finally {
        Remove-Variable GlazeSafeRestartCommands -Scope Global `
          -ErrorAction SilentlyContinue
      }
    }
  }
}
