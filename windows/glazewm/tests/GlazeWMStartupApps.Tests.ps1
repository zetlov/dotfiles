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
    $script | Should -Match 'Get-CimInstance Win32_Process'
    $script | Should -Match "shell:AppsFolder"
    $script | Should -Match "startup-apps-error\.log"
    $script | Should -Match "startup-apps-state\.json"
    $script | Should -Match 'Remove-Item -LiteralPath \$statePath'
  }

  It "validates fields according to each launch type" {
    $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    $script = Get-Content -LiteralPath $scriptPath -Raw

    foreach ($app in @($config.applications)) {
      $launchTypeProperty = $app.PSObject.Properties["launchType"]
      $launchType = if ($null -eq $launchTypeProperty) {
        "start-app"
      } else {
        [string]$launchTypeProperty.Value
      }
      if ($launchType -eq "executable") {
        @($app.pathCandidates).Count | Should -BeGreaterThan 0
      } else {
        [string]$app.startAppName | Should -Not -BeNullOrEmpty
      }
    }

    $script | Should -Match "Get-OptionalAppProperty"
    $script | Should -Not -Match '\$app\.(arguments|launchType|pathCandidates|processCommandLinePattern|startAppName|startupWorkspace)\b'
    $script | Should -Match (
      'if \(-not \[string\]::IsNullOrWhiteSpace' +
      '\(\$processCommandLinePattern\)\)'
    )
  }

  It "places each application only from the startup helper" {
    $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    $script = Get-Content -LiteralPath $scriptPath -Raw
    $expectedWorkspaces = @{
      "Zen Browser (Personal)" = "1"
      "Discord" = "2"
      "Spotify" = "2"
      "Todoist" = "3"
      "Notion Calendar" = "3"
      "Obsidian" = "4"
      "Notion" = "4"
      "Zen Browser (MadoriLABO)" = "7"
      "Slack" = "7"
      "Zen Browser (University)" = "9"
      "Zotero" = "9"
    }

    foreach ($app in @($config.applications)) {
      [string]$app.startupWorkspace | Should -Be $expectedWorkspaces[$app.name]
    }

    $zen = @($config.applications | Where-Object {
      $_.name -eq "Zen Browser (Personal)"
    })[0]

    $zen.arguments | Should -Be '-P "Personal"'
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

  It "serializes initial Zebar sync before application placement" {
    $script = Get-Content -LiteralPath $scriptPath -Raw
    $initialSyncIndex = $script.IndexOf(
      '& $monitorSyncScript -RestartZebar'
    )
    $applicationIndex = $script.IndexOf('$startApps = @(Get-StartApps)')

    $initialSyncIndex | Should -BeGreaterThan -1
    $applicationIndex | Should -BeGreaterThan $initialSyncIndex
  }

  It "defers startup placement during a safe monitor restart" {
    $script = Get-Content -LiteralPath $scriptPath -Raw
    $guardIndex = $script.IndexOf(
      '$env:DOTFILES_GLAZE_SAFE_RESTART'
    )
    $initialSyncIndex = $script.IndexOf(
      '& $monitorSyncScript -RestartZebar'
    )

    $guardIndex | Should -BeGreaterThan -1
    $initialSyncIndex | Should -BeGreaterThan $guardIndex
    $script | Should -Match 'safe-restart-\$safeRestartToken\.pending'
    $script | Should -Match 'Remove-Item -LiteralPath \$safeRestartMarkerPath'
  }

  It "does not abort application placement when initial Zebar sync fails" {
    $script = Get-Content -LiteralPath $scriptPath -Raw

    $script | Should -Match (
      'try\s*\{[\s\S]*& \$monitorSyncScript -RestartZebar' +
      '[\s\S]*\}\s*catch\s*\{'
    )
    $script | Should -Match 'InitialMonitorSyncError'
  }
}
