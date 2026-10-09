Describe "GlazeWM Surface display synchronization" {
  BeforeAll {
    $modulePath = Join-Path $PSScriptRoot "..\GlazeSurfaceDisplay.psm1"
    Import-Module $modulePath -Force -ErrorAction Stop

    function New-SurfaceMonitor {
      param(
        [string]$Name,
        [string[]]$Workspaces,
        [int]$X = 0,
        [int]$Y = 0
      )
      [pscustomobject]@{
        deviceName = $Name
        x = $X
        y = $Y
        width = 1920
        height = 1080
        children = @($Workspaces | ForEach-Object {
          [pscustomobject]@{
            type = "workspace"
            id = "workspace-$_"
            name = $_
            children = @()
          }
        })
      }
    }
  }

  It "uses left-to-right monitor indexes regardless of query order" {
    $monitors = @(
      (New-SurfaceMonitor "\\.\DISPLAY3" @("1", "2") 0 0),
      (New-SurfaceMonitor "\\.\DISPLAY8" @("6") -1920 0)
    )

    $plan = @(Get-GlazeSurfaceWorkspaceBindingPlan `
      -Monitors $monitors `
      -InternalDeviceName "\\.\DISPLAY3")

    @($plan | ForEach-Object { "$($_.WorkspaceName):$($_.MonitorIndex)" }) |
      Should -Be @("1:1", "2:1", "3:1", "4:1", "5:1", "6:0")
  }

  It "keeps one through five on the internal display and six on one external" {
    $monitors = @(
      (New-SurfaceMonitor "\\.\DISPLAY8" @("1", "6", "7") -1920 0),
      (New-SurfaceMonitor "\\.\DISPLAY3" @("2", "3", "4", "5") 0 0)
    )

    $plan = @(Get-GlazeSurfaceWorkspaceBindingPlan `
      -Monitors $monitors `
      -InternalDeviceName "\\.\display3")

    @($plan | ForEach-Object { "$($_.WorkspaceName):$($_.MonitorIndex)" }) |
      Should -Be @("1:1", "2:1", "3:1", "4:1", "5:1", "6:0")
    @($plan.WorkspaceName) | Should -Not -Contain "7"
  }

  It "does not create or bind dynamic workspaces on the internal display only" {
    $monitors = @(
      (New-SurfaceMonitor "\\.\DISPLAY3" @("1", "2", "3", "4", "5", "9"))
    )

    $plan = @(Get-GlazeSurfaceWorkspaceBindingPlan `
      -Monitors $monitors `
      -InternalDeviceName "\\.\DISPLAY3")

    @($plan.WorkspaceName) | Should -Be @("1", "2", "3", "4", "5")
  }

  It "fails closed when more than one external display is active" {
    $monitors = @(
      (New-SurfaceMonitor "\\.\DISPLAY1" @("1")),
      (New-SurfaceMonitor "\\.\DISPLAY2" @()),
      (New-SurfaceMonitor "\\.\DISPLAY3" @())
    )

    {
      Get-GlazeSurfaceWorkspaceBindingPlan `
        -Monitors $monitors `
        -InternalDeviceName "\\.\DISPLAY1"
    } | Should -Throw "*more than one external display*"
  }

  It "matches the internal panel by device name instead of bounds or orientation" {
    $landscape = @(
      [pscustomobject]@{ DeviceName = "\\.\DISPLAY3"; DevicePath = "panel-a"; IsInternal = $true; Width = 2736; Height = 1824 }
    )
    $portrait = @(
      [pscustomobject]@{ DeviceName = "\\.\DISPLAY3"; DevicePath = "panel-a"; IsInternal = $true; Width = 1824; Height = 2736 }
    )

    (Get-SurfaceInternalDisplay -Displays $landscape).DeviceName |
      Should -Be "\\.\DISPLAY3"
    (Get-SurfaceInternalDisplay -Displays $portrait).DeviceName |
      Should -Be "\\.\DISPLAY3"
  }

  It "requires exactly one active internal panel" {
    {
      Get-SurfaceInternalDisplay -Displays @(
        [pscustomobject]@{ DeviceName = "\\.\DISPLAY1"; IsInternal = $false }
      )
    } | Should -Throw "*exactly one internal display*"
  }

  It "coalesces display changes until the quiet period expires" {
    $state = New-SurfaceDisplayDebounceState
    $state = Update-SurfaceDisplayDebounceState -State $state -NowMilliseconds 0
    $state = Update-SurfaceDisplayDebounceState -State $state -NowMilliseconds 300
    $state = Update-SurfaceDisplayDebounceState -State $state -NowMilliseconds 900

    (Test-SurfaceDisplayDebounceReady -State $state -NowMilliseconds 2399 `
      -QuietPeriodMilliseconds 1500) | Should -BeFalse
    (Test-SurfaceDisplayDebounceReady -State $state -NowMilliseconds 2400 `
      -QuietPeriodMilliseconds 1500) | Should -BeTrue
  }

  It "retries AppBar repair when the Surface bar is not responding" {
    InModuleScope GlazeSurfaceDisplay {
      Mock Get-Process {
        [pscustomobject]@{
          Responding = $false
          MainWindowTitle = "Zebar - zetshell / surface-bar"
        }
      }

      {
        Repair-SurfaceZebarAppBar -InternalDisplay ([pscustomobject]@{
          X = 0; Y = 0; Width = 1824; Height = 2736
        })
      } | Should -Throw "*not responding*"
    }
  }
}
