Describe "GlazeWM managed configuration" {
  BeforeAll {
    $configPath = Join-Path $PSScriptRoot "..\config.yaml"
    $surfaceConfigPath = Join-Path $PSScriptRoot "..\config.surface.yaml"
    $startPath = Join-Path $PSScriptRoot "..\install.ps1"
    $kanataPath = Join-Path $PSScriptRoot "..\..\kanata\kanata.kbd"
  }

  It "keeps the Surface workspace and startup policy separate" {
    $config = Get-Content -LiteralPath $surfaceConfigPath -Raw

    foreach ($workspace in 1..5) {
      $config | Should -Match (
        "(?ms)^  - name: '$workspace'\r?\n" +
        "    keep_alive: true\r?$"
      )
    }
    foreach ($workspace in 6..12) {
      $config | Should -Match (
        "(?ms)^  - name: '$workspace'\r?\n" +
        "    keep_alive: false\r?$"
      )
    }
    $config | Should -Not -Match "(?m)^  - name: '(left|vert)'"
    $config | Should -Not -Match "Switch-MonitorProfile"
    $config | Should -Not -Match "Start-GlazeWorkspaceApps"
    $config | Should -Match "Watch-GlazeSurfaceDisplay\.ps1"
  }

  It "selects an explicit desktop or Surface profile without ARM inference" {
    $script = Get-Content -LiteralPath $startPath -Raw

    $script | Should -Match '\[ValidateSet\("desktop", "surface"\)\]'
    $script | Should -Match '\[string\]\$DeviceProfile = "desktop"'
    $script | Should -Match 'config\.surface\.yaml'
    $script | Should -Not -Match 'OSArchitecture.+surface'
  }

  It "synchronizes Surface displays immediately and restores an old watcher on rollback" {
    $script = Get-Content -LiteralPath $startPath -Raw

    $script | Should -Match (
      'Invoke-GlazeSurfaceWorkspaceSync\s+`?\r?\n?' +
      '\s*-GlazeWMPath \$GlazeWMPath'
    )
    $script | Should -Match '\$surfaceWatcherWasRunning = \$false'
    $script | Should -Match (
      'if \(\$surfaceWatcherWasRunning\)[\s\S]+?' +
      'Start-HiddenPowerShellScript -ScriptPath \$deployedSurfaceWatcher'
    )
  }

  It "keeps the Surface watcher single-instance and retries transient failures" {
    $watcherPath = Join-Path $PSScriptRoot "..\Watch-GlazeSurfaceDisplay.ps1"
    $watcher = Get-Content -LiteralPath $watcherPath -Raw

    $watcher | Should -Match 'Local\\DotfilesGlazeSurfaceDisplayWatcher'
    $watcher | Should -Match 'WaitOne\(0\)'
    $watcher | Should -Match '\$retryAttemptsRemaining = 3'
    $watcher | Should -Match 'Invoke-SurfaceDisplaySyncSafely'
    $watcher | Should -Match (
      'if \(Invoke-SurfaceDisplaySyncSafely\)[\s\S]+?' +
      'Update-SurfaceDisplayDebounceState'
    )
    $surfaceModule = Get-Content `
      -LiteralPath (Join-Path $PSScriptRoot "..\GlazeSurfaceDisplay.psm1") `
      -Raw
    $surfaceModule | Should -Match 'display topologies have not converged'
    $surfaceModule | Should -Match 'Repair-SurfaceZebarAppBar'
    $surfaceModule | Should -Match (
      '(?s)\$focused = \$null.+?try \{.+?finally \{.+?' +
      'could not restore workspace focus'
    )
  }

  It "requires explicit authorization before replacing a running Zebar pack" {
    $script = Get-Content -LiteralPath $startPath -Raw

    $script | Should -Match '\[switch\]\$AllowZebarRuntimeStop'
    $script | Should -Match (
      '-AllowRuntimeStop:\$AllowZebarRuntimeStop'
    )
  }

  It "restores the previous Zebar pack when a later installation step fails" {
    $script = Get-Content -LiteralPath $startPath -Raw

    $script | Should -Match '\$zebarDeploymentChanged = \$false'
    $script | Should -Match '\$zebarState\.Changed'
    $script | Should -Match (
      'if \(\$zebarDeploymentChanged\)[\s\S]+?' +
      '-LiteralPath \$zebarSnapshot[\s\S]+?' +
      '\$previousZebarWidgetName'
    )
  }

  It "keeps managed workspaces alive without topology-specific startup bindings" {
    $config = Get-Content -LiteralPath $configPath -Raw

    foreach ($workspace in @((1..12) + @("left", "vert"))) {
      $config | Should -Match (
        "(?ms)^  - name: '$workspace'\r?\n" +
        "    keep_alive: true\r?$"
      )
    }
    $config | Should -Not -Match "(?m)^\s+bind_to_monitor:"
  }

  It "uses the existing Kanata Ctrl Alt chords for core navigation" {
    $config = Get-Content -LiteralPath $configPath -Raw

    foreach ($binding in @(
      "ctrl+alt+h",
      "ctrl+alt+j",
      "ctrl+alt+k",
      "ctrl+alt+l",
      "ctrl+alt+shift+h",
      "ctrl+alt+shift+j",
      "ctrl+alt+shift+k",
      "ctrl+alt+shift+l",
      "ctrl+alt+t"
    )) {
      $config | Should -Match ([regex]::Escape("'$binding'"))
    }
  }

  It "accepts the private function keys emitted by the current Kanata layer" {
    $config = Get-Content -LiteralPath $configPath -Raw
    $kanata = Get-Content -LiteralPath $kanataPath -Raw

    foreach ($binding in @("f16", "f17", "f18", "f19", "f20", "f21", "f22", "f23")) {
      $config | Should -Match ([regex]::Escape("'$binding'"))
      $kanata | Should -Match "(?i)\b$binding\b"
    }
  }

  It "accepts Ctrl-modified move keys while physical Ctrl remains held" {
    $config = Get-Content -LiteralPath $configPath -Raw

    foreach ($binding in @("ctrl+f20", "ctrl+f21", "ctrl+f22", "ctrl+f23")) {
      $config | Should -Match ([regex]::Escape("'$binding'"))
    }
  }

  It "launches the GUI terminal without a console-host intermediary" {
    Get-Content -LiteralPath $configPath -Raw |
      Should -Match ([regex]::Escape("'shell-exec wezterm-gui start'"))
  }

  It "switches monitor profiles through the active GlazeWM keybindings" {
    $config = Get-Content -LiteralPath $configPath -Raw

    foreach ($profile in @(
      @{ Name = "all"; Binding = "shift+f16" },
      @{ Name = "left-center"; Binding = "shift+f17" },
      @{ Name = "right-only"; Binding = "shift+f18" }
    )) {
      $command = (
        "shell-exec --hide-window powershell.exe -NoProfile " +
        "-NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden " +
        "-File `"%LOCALAPPDATA%\dotfiles\monitor-profiles\" +
        "Switch-MonitorProfile.ps1`" -Name $($profile.Name)"
      )
      $config | Should -Match ([regex]::Escape("'$command'"))
      $config | Should -Match ([regex]::Escape("'$($profile.Binding)'"))
    }
  }

  It "starts only the managed helper scripts" {
    $config = Get-Content -LiteralPath $configPath -Raw

    $config | Should -Match "autotile\.ps1"
    $config | Should -Match "Start-GlazeWorkspaceApps\.ps1"
    $config | Should -Not -Match (
      "(?m)^\s+- .*Sync-GlazeMonitorLayout\.ps1.*-RestartZebar"
    )
    $config | Should -Not -Match "(?i)seelen"
  }

  It "keeps focus follows cursor disabled" {
    Get-Content -LiteralPath $configPath -Raw |
      Should -Match "(?m)^  focus_follows_cursor: false\r?$"
  }

  It "installs only the managed GlazeWM and helper processes" {
    $script = Get-Content -LiteralPath $startPath -Raw

    $script | Should -Match "glazewm\.exe"
    $script | Should -Match "autotile\.ps1"
    $script | Should -Match "Sync-GlazeMonitorLayout\.ps1"
    $script | Should -Match "GlazeWMMonitorSync\.psm1"
    $script | Should -Match "GlazeWMSafeRestart\.psm1"
    $script | Should -Match 'sourceZebarInstaller'
    $script | Should -Not -Match "(?i)seelen"
  }

  It "can deploy GlazeWM while preserving the existing Zebar runtime" {
    $script = Get-Content -LiteralPath $startPath -Raw

    $script | Should -Match '\[switch\]\$PreserveZebarRuntime'
    $script | Should -Match 'if \(\$PreserveZebarRuntime\)'
    $script | Should -Match '(?s)\$PreserveZebarRuntime.+?\$sourceZebarInstaller'
    $script | Should -Match '(?s)\$PreserveZebarRuntime.+?\$deployedMonitorSyncScript'
  }

  It "can preserve current app placement during a live config update" {
    $script = Get-Content -LiteralPath $startPath -Raw

    $script | Should -Match '\[switch\]\$SkipStartupApps'
    $script | Should -Match (
      '(?s)\$SkipStartupApps.+?requires.+?\$PreserveZebarRuntime'
    )
    $script | Should -Match (
      'if \(\$runStartupApps -and -not \$SkipStartupApps\) \{[\s\S]*?' +
      '\$startupAppsProcess = Start-HiddenPowerShellScript'
    )
    $script | Should -Match (
      'if \(\$runStartupApps -and -not \$SkipStartupApps\) \{[\s\S]*?' +
      '\$startupAppsDeadline = \(Get-Date\)'
    )
  }

  It "leaves audio lifecycle to the active audio component" {
    $script = Get-Content -LiteralPath $startPath -Raw

    $script | Should -Not -Match 'AudioOutputInstaller'
    $script | Should -Not -Match 'switch-audio\.ps1'
    $script | Should -Not -Match 'audio-output\.json'
  }

  It "keeps the elevated manager separate from the dedicated IPC client" {
    $script = Get-Content -LiteralPath $startPath -Raw

    $script | Should -Match 'glzr\.io\\GlazeWM\\glazewm\.exe'
    $script | Should -Match 'glzr\.io\\GlazeWM\\cli\\glazewm\.exe'
    $script | Should -Match '\$_\.Path -ne \$GlazeWMPath'
    $script | Should -Not -Match '\$_\.Path\.Equals\(\$ManagerPath'
    $script | Should -Not -Match "WindowsPrincipal"
  }

  It "quotes managed helper paths that contain environment expansions" {
    $config = Get-Content -LiteralPath $configPath -Raw

    $config | Should -Match ([regex]::Escape('"%LOCALAPPDATA%\dotfiles\glazewm\autotile.ps1"'))
    $config | Should -Match ([regex]::Escape('"%LOCALAPPDATA%\dotfiles\glazewm\Start-GlazeWorkspaceApps.ps1"'))
  }

  It "leaves startup application routing to the startup helper" {
    $config = Get-Content -LiteralPath $configPath -Raw

    foreach ($processName in @(
      "zen",
      "Todoist",
      "Notion Calendar",
      "Spotify",
      "Discord",
      "Obsidian",
      "Notion",
      "slack",
      "zotero"
    )) {
      $config | Should -Not -Match (
        "(?m)^\s+- window_process: \{ equals: '$([regex]::Escape($processName))' \}\r?$"
      )
    }
  }

  It "routes the configured game processes to floating workspace eleven" {
    $config = Get-Content -LiteralPath $configPath -Raw
    # Input remapping exceptions do not define workspace placement.
    $routedGames = @(
      "StreetFighter6",
      "FactoryGameSteam",
      "FactoryGameSteam-Win64-Shipping",
      "ShadowverseWB",
      "AimLab_tb",
      "VALORANT",
      "VALORANT-Win64-Shipping",
      "GenshinImpact",
      "StarRail",
      "EscapeFromTarkov",
      "EscapeFromTarkov_BE"
    )
    $ruleHeader = [regex]::Escape(
      "  - commands: ['move --workspace 11', 'set-floating --centered=false']"
    )
    $rule = [regex]::Match(
      $config, "(?ms)^${ruleHeader}\r?\n.*?(?=^  - commands:|\z)"
    ).Value
    $rule | Should -Not -BeNullOrEmpty
    foreach ($processName in $routedGames) {
      $rule | Should -Match ([regex]::Escape(
        "window_process: { equals: '$processName' }"
      ))
    }
  }

  It "installs the official package and registers the official manager" {
    $script = Get-Content -LiteralPath $startPath -Raw

    $script | Should -Match "glzr-io\.glazewm"
    $script | Should -Match 'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Run'
    $script | Should -Match '-Name "GlazeWM"'
    $script | Should -Match 'komorebi\.lnk'
    $script | Should -Match 'Disable Komorebi autostart'
    $script | Should -Not -Match 'New-Item -Path \$runKey -Force'
  }

  It "pins and validates the GlazeWM runtime version" {
    $script = Get-Content -LiteralPath $startPath -Raw

    $script | Should -Match '\$RequiredVersion = "3\.10\.1"'
    $script | Should -Match '--version \$RequiredVersion'
    $script | Should -Match 'winget\.exe upgrade'
    $script | Should -Match 'winget\.exe uninstall'
    $script | Should -Match '--version \$installedVersion'
    $script | Should -Match '-1978335189'
    $script | Should -Match '-1978335090'
    $script | Should -Match '\$upgradeExitCode -in \$reinstallRequiredExitCodes'
    $script | Should -Match '\$uninstallExitCode -eq 1603'
    $script | Should -Match 'requires[\s\S]+?administrator approval'
    $script | Should -Match '\$installedVersion -lt \$requiredSemanticVersion'
    $script | Should -Match '\$installedVersion -gt \$requiredSemanticVersion'
    $script | Should -Match '& \$GlazeWMPath --version'
    $script | Should -Match 'Unexpected GlazeWM version'
  }

  It "retries transient IPC failures while the manager starts" {
    $script = Get-Content -LiteralPath $startPath -Raw

    $script | Should -Match 'function Wait-GlazeWMReady'
    $script | Should -Match '& \$CliPath query app-metadata'
    $script | Should -Match 'while \(\(Get-Date\) -lt \$deadline\)'
  }

  It "quotes configuration paths with spaces for startup and recovery" {
    $tokens = $null
    $parseErrors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile(
      $startPath, [ref]$tokens, [ref]$parseErrors
    )
    $parseErrors | Should -BeNullOrEmpty
    $starts = @($ast.FindAll({
      param($node)
      $node -is [Management.Automation.Language.CommandAst] -and
        $node.GetCommandName() -eq "Start-Process" -and
        $node.Extent.Text.Contains('-FilePath $ManagerPath')
    }, $true))
    $starts.Count | Should -Be 2
    $ManagerPath = "C:\Program Files\glzr.io\GlazeWM\glazewm.exe"
    $liveConfig = "C:\Users\Example User\.glzr\glazewm\config.yaml"
    Mock Start-Process {
      [pscustomobject]@{ Arguments = $ArgumentList -join " " }
    }

    foreach ($start in $starts) {
      $result = & ([scriptblock]::Create($start.Extent.Text))

      $result.Arguments | Should -Be ('start --config="' + $liveConfig + '"')
    }
  }

  It "reloads a running manager without replacing it" {
    $script = Get-Content -LiteralPath $startPath -Raw

    $script | Should -Match 'command wm-reload-config'
    $script | Should -Not -Match 'command wm-exit'
    $script | Should -Match 'if \(\$managerWasRunning\)'
    $script | Should -Match '\$managerStartedByInstaller'
    $script | Should -Match 'Start-ManagedZebar -ZebarState \$zebarState'
    $script | Should -Match 'Rollback could not reload the previous GlazeWM config'
    $script | Should -Not -Match 'Stop-Process `?[\s\S]*-Id \$manager\.Id'
  }

  It "serializes managed helper restarts and verifies the new daemon" {
    $script = Get-Content -LiteralPath $startPath -Raw

    $script | Should -Match 'Wait-GlazeHelperExit'
    $script | Should -Match 'Import-Module \$processModule'
    $script | Should -Match (
      'Stop-GlazeProcessTree -ProcessId \$existingDaemon\.ProcessId'
    )
    $script | Should -Match '\$existingStartupHelper'
    $script | Should -Match '\$startupAppsProcess'
    $script | Should -Match '\$daemon\.ProcessId -ne \$startedDaemonProcess\.Id'
    $script | Should -Match 'The automatic tiling helper exited during startup'
    $script | Should -Match '-ProcessId \$startedDaemonProcess\.Id'
    $script | Should -Match 'Rollback could not stop the new automatic tiling helper'
  }

  It "waits for startup applications before committing installation state" {
    $script = Get-Content -LiteralPath $startPath -Raw

    $script | Should -Match "startup-apps-state\.json"
    $script | Should -Match "startup-apps-error\.log"
    $script | Should -Match 'StartupAppsTimeoutSeconds'
    $script | Should -Match 'ConvertFrom-Json'
    $script | Should -Match 'Remove-Item `[\s\S]*-LiteralPath \$startupStatePath'
    $script | Should -Match 'WorkspaceSynchronized'
  }

  It "restores managed files and autostart when installation fails" {
    $script = Get-Content -LiteralPath $startPath -Raw

    $script | Should -Match 'runtimeSnapshots'
    $script | Should -Match 'previousRunValue'
    $script | Should -Match 'Remove-ItemProperty'
    $script | Should -Match 'elseif \(-not \$installationSucceeded\)'
    $script | Should -Match 'Stop-GlazeProcessTree -ProcessId \$daemon\.ProcessId'
    $script | Should -Match 'Start-Process `?[\s\S]*-FilePath \$zebarState\.ZebarPath'
    $script | Should -Match 'Rollback could not reload the previous GlazeWM config'
    $script | Should -Match 'Rollback could not restart the automatic tiling helper'
  }

  It "preserves a newly started runtime when later validation fails" {
    $script = Get-Content -LiteralPath $startPath -Raw

    $script | Should -Match '\$preserveStartedRuntime = \$true'
    $script | Should -Match '\$startedRuntimeAutostartRegistered = \$true'
    $script | Should -Match 'if \(-not \$installationSucceeded -and \$preserveStartedRuntime\)'
    $script | Should -Match '(?s)avoid orphaning.*cloaked windows'
    $script | Should -Match '(?s)autostart could not.*be registered'
    $script | Should -Match 'GlazeWM recovery failed'
  }

  It "waits for the managed Zebar process before committing state" {
    $script = Get-Content -LiteralPath $startPath -Raw

    $script | Should -Match '\$ZebarStartupTimeoutSeconds = 30'
    $script | Should -Match (
      'MainWindowTitle -eq "Zebar - zetshell / \$WidgetName"'
    )
    $script | Should -Match 'managedZebarWidgetName'
    $script | Should -Match 'Zebar did not start within'
  }

  It "uses numeric monitor selectors accepted by GlazeWM 3.10" {
    $config = Get-Content -LiteralPath $configPath -Raw

    $config | Should -Match "focus --monitor 0"
    $config | Should -Match "focus --monitor 1"
    $config | Should -Not -Match "focus --monitor (left|right)"
  }

  It "never moves a numeric workspace through monitor navigation" {
    $config = Get-Content -LiteralPath $configPath -Raw

    $config | Should -Not -Match "move-workspace"
    $config | Should -Match (
      "(?ms)commands: \['focus --monitor 0'\].+?" +
      "bindings: \['ctrl\+alt\+,', 'ctrl\+alt\+shift\+,'\]"
    )
    $config | Should -Match (
      "(?ms)commands: \['focus --monitor 2'\].+?" +
      "bindings: \['ctrl\+alt\+\.', 'ctrl\+alt\+shift\+\.'\]"
    )
  }
}
