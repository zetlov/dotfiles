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

  It "normalizes a single monitor response into a collection" {
    $fakeCli = Join-Path $TestDrive "glazewm.ps1"
    @'
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
$global:LASTEXITCODE = 0
'{"success":true,"data":{"monitors":{"type":"monitor","id":"right","x":0,"y":0,"width":1920,"height":1080,"children":[]}}}'
'@ | Set-Content -LiteralPath $fakeCli -Encoding UTF8

    InModuleScope GlazeWMMonitorSync -Parameters @{ FakeCli = $fakeCli } {
      $monitors = @(Get-GlazeMonitors -GlazeWMPath $FakeCli)

      $monitors.Count | Should -Be 1
      $monitors[0].id | Should -Be "right"
    }
  }

  It "reloads GlazeWM once and tolerates slow monitor removal" {
    $fakeCli = Join-Path $TestDrive "glazewm-reload.ps1"
    $reloadMarker = Join-Path $TestDrive "reloaded.txt"
    @'
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
$global:LASTEXITCODE = 0
if ($Arguments -join " " -eq "command wm-reload-config") {
  Set-Content -LiteralPath $env:GLAZE_TEST_RELOAD_MARKER -Value "reloaded"
  '{"success":true,"data":null,"error":null}'
}
'@ | Set-Content -LiteralPath $fakeCli -Encoding UTF8

    InModuleScope GlazeWMMonitorSync -Parameters @{
      FakeCli = $fakeCli
      ReloadMarker = $reloadMarker
    } {
      $env:GLAZE_TEST_RELOAD_MARKER = $ReloadMarker
      $script:GlazeTestMonitorPolls = 0
      $script:GlazeTestDateCalls = 0
      Mock Get-WindowsScreenBounds {
        @(
          [pscustomobject]@{ X = -1920; Y = 495; Width = 1920; Height = 1080 }
          [pscustomobject]@{ X = 0; Y = 0; Width = 3840; Height = 2160 }
          [pscustomobject]@{ X = 3840; Y = 430; Width = 1920; Height = 1080 }
        )
      }
      Mock Get-GlazeMonitors {
        $null = $script:GlazeTestMonitorPolls++
        if ($script:GlazeTestMonitorPolls -gt 1) {
          return @(
            [pscustomobject]@{
              id = "left"; x = -1920; y = 495
              width = 1920; height = 1080; children = @()
            }
            [pscustomobject]@{
              id = "center"; x = 0; y = 0
              width = 3840; height = 2160; children = @()
            }
            [pscustomobject]@{
              id = "right"; x = 3840; y = 430
              width = 1920; height = 1080; children = @()
            }
          )
        }
        return @(
          [pscustomobject]@{
            id = "right"; x = 0; y = 0
            width = 1920; height = 1080; children = @()
          }
        )
      }
      Mock Get-Date {
        $null = $script:GlazeTestDateCalls++
        $start = [datetime]"2026-08-29T12:00:00"
        if ($script:GlazeTestDateCalls -eq 1) {
          return $start
        }
        return $start.AddSeconds(20)
      }
      Mock Start-Sleep {}

      try {
        $monitors = @(Wait-GlazeMonitorTopology `
          -GlazeWMPath $FakeCli)

        $monitors.Count | Should -Be 3
        Test-Path -LiteralPath $ReloadMarker | Should -BeTrue
      } finally {
        Remove-Item Env:GLAZE_TEST_RELOAD_MARKER -ErrorAction SilentlyContinue
      }
    }
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

  It "verifies the asset server and AppBar before preserving a bar" {
    $module = Get-Content -LiteralPath $modulePath -Raw

    $module | Should -Match 'Get-NetTCPConnection[\s\S]*6124'
    $module | Should -Match 'Get-Process[\s\S]+OwningProcess'
    $module | Should -Match 'existingBar'
    $module | Should -Match 'CloseMainWindow'
    $module | Should -Not -Match 'Stop-Process.+zebar'
    $module | Should -Match 'start-widget-preset'
    $module | Should -Match 'ReservedTop'
    $module | Should -Match 'ListenerOwningProcess'
    $module | Should -Match 'SHAppBarMessage'
    $module | Should -Match 'QueryPosition'
    $module | Should -Match 'SetPosition'
    $module | Should -Match 'SystemParametersInfo'
    $module | Should -Match 'GetWindowRect'
  }

  It "calculates reserved top from the live primary work area" {
    InModuleScope GlazeWMMonitorSync {
      Mock Get-ZebarPrimaryWorkingArea {
        [pscustomobject]@{ Top = 42 }
      }
      Mock Get-WindowsPrimaryBounds {
        [pscustomobject]@{ X = 0; Y = 0; Width = 3840; Height = 2160 }
      }

      Get-PrimaryReservedTop | Should -Be 42
    }
  }

  It "queries and sets the expected AppBar rectangle in order" {
    InModuleScope GlazeWMMonitorSync {
      $global:GlazeTestAppBarMessages = [Collections.Generic.List[string]]::new()
      Mock Get-WindowsPrimaryBounds {
        [pscustomobject]@{ X = 0; Y = 0; Width = 3840; Height = 2160 }
      }
      Mock Get-ZebarWindowBounds {
        [pscustomobject]@{ Left = 0; Top = 0; Right = 3840; Bottom = 42 }
      }
      Mock Invoke-ZebarAppBarNativeMessage {
        param($Message, $Data)
        $global:GlazeTestAppBarMessages.Add(
          "${Message}:$($Data.Bounds.Left),$($Data.Bounds.Top)," +
          "$($Data.Bounds.Right),$($Data.Bounds.Bottom)"
        )
        return $Data
      }

      try {
        $result = Invoke-ZebarAppBarPositionRefresh `
          -Bar ([pscustomobject]@{ MainWindowHandle = [IntPtr]12345 }) `
          -ExpectedReservedTop 42

        $global:GlazeTestAppBarMessages | Should -Be @(
          "2:0,0,3840,42"
          "3:0,0,3840,42"
        )
        $result.Bottom | Should -Be 42
      } finally {
        Remove-Variable `
          GlazeTestAppBarMessages `
          -Scope Global `
          -ErrorAction SilentlyContinue
      }
    }
  }

  It "rejects a bar outside the primary rectangle before AppBar messages" {
    InModuleScope GlazeWMMonitorSync {
      Mock Get-WindowsPrimaryBounds {
        [pscustomobject]@{ X = 0; Y = 0; Width = 3840; Height = 2160 }
      }
      Mock Get-ZebarWindowBounds {
        [pscustomobject]@{ Left = -1920; Top = 495; Right = 0; Bottom = 537 }
      }
      Mock Invoke-ZebarAppBarNativeMessage {}

      {
        Invoke-ZebarAppBarPositionRefresh `
          -Bar ([pscustomobject]@{ MainWindowHandle = [IntPtr]12345 }) `
          -ExpectedReservedTop 42
      } | Should -Throw "*not aligned with the primary monitor*"
      Should -Invoke Invoke-ZebarAppBarNativeMessage -Times 0
    }
  }

  It "rejects a visible reserved bar when its listener is orphaned" {
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

    {
      Ensure-GlazeZebar `
        -ZebarPath "C:\Zebar\zebar.exe" `
        -TimeoutSeconds 1
    } | Should -Throw "*orphaned*sign out or reboot*"
    Should -Invoke Start-Process -ModuleName GlazeWMMonitorSync -Times 0
  }

  It "repairs a lost AppBar reservation without relaunching the widget" {
    $global:GlazeTestAppBarRefreshed = $false
    $barProcess = [pscustomobject]@{
      Id = 123
      Responding = $true
      MainWindowTitle = "Zebar - zetshell / bar"
      MainWindowHandle = [IntPtr]12345
    }
    Mock Test-Path { $true } -ModuleName GlazeWMMonitorSync
    Mock Get-Process {
      param($Name, $Id)
      if ($null -ne $Name) {
        return $barProcess
      }
      if ($Id -eq 123) {
        return [pscustomobject]@{ Id = 123 }
      }
      return $null
    } -ModuleName GlazeWMMonitorSync
    Mock Get-ZebarListener {
      [pscustomobject]@{ OwningProcess = 123 }
    } -ModuleName GlazeWMMonitorSync
    Mock Get-PrimaryReservedTop {
      if ($global:GlazeTestAppBarRefreshed) { return 42 }
      return 0
    } -ModuleName GlazeWMMonitorSync
    Mock Invoke-ZebarAppBarPositionRefresh {
      $global:GlazeTestAppBarRefreshed = $true
    } -ModuleName GlazeWMMonitorSync
    Mock Start-Process {} -ModuleName GlazeWMMonitorSync

    try {
      $result = Ensure-GlazeZebar `
        -ZebarPath "C:\Zebar\zebar.exe" `
        -TimeoutSeconds 1

      $result.ProcessId | Should -Be 123
      $result.ReservedTop | Should -Be 42
      $result.ReservationRefreshed | Should -BeTrue
      Should -Invoke `
        Invoke-ZebarAppBarPositionRefresh `
        -ModuleName GlazeWMMonitorSync `
        -Times 1
      Should -Invoke Start-Process -ModuleName GlazeWMMonitorSync -Times 0
    } finally {
      Remove-Variable `
        GlazeTestAppBarRefreshed `
        -Scope Global `
        -ErrorAction SilentlyContinue
    }
  }

  It "requires authorization before relaunching only the Zebar widget" {
    $global:GlazeTestZebarClosed = $false
    $global:GlazeTestZebarStarted = $false
    $barProcess = [pscustomobject]@{
      Id = 123
      Responding = $true
      MainWindowTitle = "Zebar - zetshell / bar"
    }
    $barProcess | Add-Member -MemberType ScriptMethod -Name CloseMainWindow -Value {
      $global:GlazeTestZebarClosed = $true
      return $true
    }
    Mock Test-Path { $true } -ModuleName GlazeWMMonitorSync
    Mock Get-Process {
      param($Name, $Id)
      if ($null -ne $Name) {
        if ($global:GlazeTestZebarClosed -and -not $global:GlazeTestZebarStarted) {
          return [pscustomobject]@{
            Id = 123
            Responding = $true
            MainWindowTitle = ""
          }
        }
        return $barProcess
      }
      if ($Id -eq 123) {
        return [pscustomobject]@{ Id = 123 }
      }
      return $null
    } -ModuleName GlazeWMMonitorSync
    Mock Get-ZebarListener {
      return [pscustomobject]@{ OwningProcess = 123 }
    } -ModuleName GlazeWMMonitorSync
    Mock Get-PrimaryReservedTop {
      if ($global:GlazeTestZebarStarted) { return 42 }
      return 0
    } -ModuleName GlazeWMMonitorSync
    Mock Invoke-ZebarAppBarPositionRefresh {} `
      -ModuleName GlazeWMMonitorSync
    Mock Start-Process {
      $global:GlazeTestZebarStarted = $true
    } -ModuleName GlazeWMMonitorSync
    Mock Stop-Process {} -ModuleName GlazeWMMonitorSync
    Mock Start-Sleep {} -ModuleName GlazeWMMonitorSync

    try {
      {
        Ensure-GlazeZebar `
          -ZebarPath "C:\Zebar\zebar.exe" `
          -TimeoutSeconds 1
      } | Should -Throw "*explicit authorization*"
      $global:GlazeTestZebarClosed | Should -BeFalse
      Should -Invoke Start-Process -ModuleName GlazeWMMonitorSync -Times 0

      $result = Ensure-GlazeZebar `
        -ZebarPath "C:\Zebar\zebar.exe" `
        -TimeoutSeconds 1 `
        -AllowWidgetRelaunch

      $result.ProcessId | Should -Be 123
      $result.ReservedTop | Should -Be 42
      $global:GlazeTestZebarClosed | Should -BeTrue
      Should -Invoke Start-Process -ModuleName GlazeWMMonitorSync -Times 1
      Should -Invoke Stop-Process -ModuleName GlazeWMMonitorSync -Times 0
    } finally {
      Remove-Variable `
        GlazeTestZebarClosed `
        -Scope Global `
        -ErrorAction SilentlyContinue
      Remove-Variable `
        GlazeTestZebarStarted `
        -Scope Global `
        -ErrorAction SilentlyContinue
    }
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
