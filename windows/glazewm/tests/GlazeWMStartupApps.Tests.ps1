Describe "GlazeWM startup applications" {
  BeforeAll {
    $configPath = Join-Path $PSScriptRoot "..\startup-apps.json"
    $scriptPath = Join-Path $PSScriptRoot "..\Start-GlazeWorkspaceApps.ps1"
  }

  It "defines the requested application set without duplicates" {
    $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    $names = @($config.applications | ForEach-Object { $_.name })

    ($names -join "|") | Should -Be (
      "Zen Browser (Personal)|Discord|Spotify|Todoist|Notion Calendar|" +
      "Obsidian|Notion|Zen Browser (MadoriLABO)|Slack|" +
      "Zen Browser (University)|Zotero"
    )
    @($config.applications.processName | Sort-Object -Unique).Count |
      Should -Be 9
  }

  It "validates config and skips applications that are already running" {
    $script = Get-Content -LiteralPath $scriptPath -Raw

    $script | Should -Match "ConvertFrom-Json"
    $script | Should -Match "Get-StartApps"
    $script | Should -Match 'Get-Process -Name \$processName'
    $script | Should -Match "shell:AppsFolder"
    $script | Should -Match "startup-apps-error\.log"
    $script | Should -Match "startup-apps-state\.json"
    $script | Should -Match 'Remove-Item -LiteralPath \$statePath'
  }

  It "places Zen on workspace 1 only from the startup helper" {
    $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    $script = Get-Content -LiteralPath $scriptPath -Raw
    $zen = @($config.applications | Where-Object {
      $_.name -eq "Zen Browser (Personal)"
    })[0]

    $zen.startupWorkspace | Should -Be "1"
    $zen.arguments | Should -Be '-P "Personal"'
    @($config.applications | Where-Object {
      $_.name -eq "Zen Browser (MadoriLABO)"
    })[0].startupWorkspace | Should -Be "7"
    @($config.applications | Where-Object {
      $_.name -eq "Zen Browser (University)"
    })[0].startupWorkspace | Should -Be "9"
    [int]$config.workspacePlacementWaitSeconds | Should -BeGreaterThan 0
    $script | Should -Match "Invoke-GlazeStartupWorkspacePlacement"
  }

  It "does not apply the obsolete workspace grid" {
    $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    $script = Get-Content -LiteralPath $scriptPath -Raw

    @($config.workspaceGrids).Count | Should -Be 0
    $script | Should -Match "Invoke-GlazeWorkspaceGrid"
  }

  It "reconciles workspace monitors after startup placement and grids" {
    $script = Get-Content -LiteralPath $scriptPath -Raw
    $placementIndex = $script.LastIndexOf(
      "Invoke-GlazeStartupWorkspacePlacement"
    )
    $gridIndex = $script.LastIndexOf("Invoke-GlazeWorkspaceGrid")
    $syncIndex = $script.LastIndexOf("Invoke-GlazeWorkspaceMonitorSync")
    $stateIndex = $script.LastIndexOf("WorkspaceSynchronized")

    $script | Should -Match "GlazeWMMonitorSync\.psm1"
    $placementIndex -ge 0 | Should -Be $true
    $gridIndex -gt $placementIndex | Should -Be $true
    $syncIndex -gt $gridIndex | Should -Be $true
    $stateIndex -gt $syncIndex | Should -Be $true
  }
}
