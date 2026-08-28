Describe "GlazeWM monitor profile synchronization" {
  BeforeAll {
    $modulePath = Join-Path $PSScriptRoot "..\GlazeWMMonitorSync.psm1"
    Import-Module $modulePath -Force -ErrorAction Stop

    function New-TestWorkspace {
      param([string]$Name)
      [pscustomobject]@{
        type = "workspace"
        id = "workspace-$Name"
        name = $Name
        children = @()
      }
    }

    function New-TestMonitor {
      param(
        [string]$Id,
        [int]$X,
        [int]$Y,
        [int]$Width,
        [int]$Height,
        [object[]]$Workspaces
      )
      [pscustomobject]@{
        type = "monitor"
        id = $Id
        x = $X
        y = $Y
        width = $Width
        height = $Height
        children = $Workspaces
      }
    }
  }

  It "moves numeric workspaces to primary and keeps auxiliary roles on edges" {
    $monitors = @(
      New-TestMonitor "left" -1920 495 1920 1080 @(
        (New-TestWorkspace "1"), (New-TestWorkspace "left")
      )
      New-TestMonitor "center" 0 0 3840 2160 @(
        (New-TestWorkspace "2")
      )
      New-TestMonitor "right" 3840 430 1920 1080 @(
        (New-TestWorkspace "11"), (New-TestWorkspace "vert")
      )
    )
    $primary = [pscustomobject]@{
      X = 0
      Y = 0
      Width = 3840
      Height = 2160
    }

    $plan = @(Get-GlazeWorkspaceMonitorMovePlan `
      -Monitors $monitors `
      -PrimaryBounds $primary)

    @($plan | ForEach-Object { "$($_.WorkspaceName):$($_.Direction)" }) |
      Should -Be @("1:right", "11:left")
  }

  It "collapses the right auxiliary workspace onto primary for left-center" {
    $monitors = @(
      New-TestMonitor "left" -1920 495 1920 1080 @(
        (New-TestWorkspace "1"),
        (New-TestWorkspace "left"),
        (New-TestWorkspace "vert")
      )
      New-TestMonitor "center" 0 0 3840 2160 @(
        (New-TestWorkspace "2")
      )
    )
    $primary = [pscustomobject]@{
      X = 0
      Y = 0
      Width = 3840
      Height = 2160
    }

    $plan = @(Get-GlazeWorkspaceMonitorMovePlan `
      -Monitors $monitors `
      -PrimaryBounds $primary)

    @($plan | ForEach-Object { "$($_.WorkspaceName):$($_.Direction)" }) |
      Should -Be @("1:right", "vert:right")
  }

  It "does not move workspaces when only the primary display is active" {
    $monitors = @(
      New-TestMonitor "right" 0 0 1920 1080 @(
        (New-TestWorkspace "1"),
        (New-TestWorkspace "11"),
        (New-TestWorkspace "left"),
        (New-TestWorkspace "vert")
      )
    )
    $primary = [pscustomobject]@{
      X = 0
      Y = 0
      Width = 1920
      Height = 1080
    }

    @(Get-GlazeWorkspaceMonitorMovePlan `
      -Monitors $monitors `
      -PrimaryBounds $primary).Count | Should -Be 0
  }

  It "fails closed when Windows primary cannot be matched to GlazeWM" {
    $monitors = @(
      New-TestMonitor "left" 0 0 1920 1080 @((New-TestWorkspace "1"))
    )
    $primary = [pscustomobject]@{
      X = 1920
      Y = 0
      Width = 1920
      Height = 1080
    }

    {
      Get-GlazeWorkspaceMonitorMovePlan `
        -Monitors $monitors `
        -PrimaryBounds $primary
    } | Should -Throw "*primary monitor*"
  }

  It "preserves an existing Zebar process and verifies the AppBar" {
    $module = Get-Content -LiteralPath $modulePath -Raw

    $module | Should -Match 'Get-NetTCPConnection[\s\S]*6124'
    $module | Should -Match 'Get-Process[\s\S]+OwningProcess'
    $module | Should -Match 'existingBar'
    $module | Should -Not -Match 'CloseMainWindow'
    $module | Should -Not -Match 'Stop-ManagedZebar'
    $module | Should -Match 'start-widget-preset'
    $module | Should -Match 'ReservedTop'
    $module | Should -Match 'ListenerOwningProcess'
  }

  It "keeps a visible reserved bar when its listener is orphaned" {
    Mock Test-Path { $true } -ModuleName GlazeWMMonitorSync
    Mock Get-Process {
      param($Name, $Id)
      if ($null -ne $Name) {
        return [pscustomobject]@{
          Id = 123
          Responding = $true
          MainWindowTitle = "Zebar - zetshell / bar"
        }
      }
      return $null
    } -ModuleName GlazeWMMonitorSync
    Mock Get-ZebarListener {
      [pscustomobject]@{ OwningProcess = 999 }
    } -ModuleName GlazeWMMonitorSync
    Mock Get-PrimaryReservedTop { 42 } -ModuleName GlazeWMMonitorSync
    Mock Start-Process {} -ModuleName GlazeWMMonitorSync
    Mock Start-Sleep {} -ModuleName GlazeWMMonitorSync

    $result = Ensure-GlazeZebar `
      -ZebarPath "C:\Zebar\zebar.exe" `
      -TimeoutSeconds 1

    $result.ProcessId | Should -Be 123
    $result.ListenerOwningProcess | Should -Be 999
    $result.ListenerOwnerExists | Should -BeFalse
    $result.ListenerOwnedByBar | Should -BeFalse
    Should -Invoke Start-Process -ModuleName GlazeWMMonitorSync -Times 0
  }

  It "fails fast without restarting when only an orphaned listener remains" {
    Mock Test-Path { $true } -ModuleName GlazeWMMonitorSync
    Mock Get-Process {
      param($Name, $Id)
      if ($null -ne $Name) {
        return [pscustomobject]@{
          Id = 123
          Responding = $false
          MainWindowTitle = ""
        }
      }
      return $null
    } -ModuleName GlazeWMMonitorSync
    Mock Get-ZebarListener {
      [pscustomobject]@{ OwningProcess = 999 }
    } -ModuleName GlazeWMMonitorSync
    Mock Start-Process {} -ModuleName GlazeWMMonitorSync

    {
      Ensure-GlazeZebar `
        -ZebarPath "C:\Zebar\zebar.exe" `
        -TimeoutSeconds 1
    } | Should -Throw "*orphaned*sign out or reboot*"
    Should -Invoke Start-Process -ModuleName GlazeWMMonitorSync -Times 0
  }

  It "moves arbitrary workspaces through focus and validates CLI JSON" {
    $module = Get-Content -LiteralPath $modulePath -Raw

    $module | Should -Match 'focus.+--workspace'
    $module | Should -Match 'FocusedWorkspaceName'
    $module | Should -Match 'Ensure-GlazeAuxiliaryWorkspaces'
    $module | Should -Match 'left.+vert'
    $module | Should -Match 'AuxiliaryFirst'
    $module | Should -Match '\.success'
    $module | Should -Not -Match 'command `\s*\r?\n\s*--id \$move\.WorkspaceId'
  }
}
