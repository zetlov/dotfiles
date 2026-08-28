Describe "GlazeWM managed configuration" {
  BeforeAll {
    $configPath = Join-Path $PSScriptRoot "..\config.yaml"
    $startPath = Join-Path $PSScriptRoot "..\install.ps1"
    $kanataPath = Join-Path $PSScriptRoot "..\..\kanata\kanata.kbd"
    $gameModePath = Join-Path $PSScriptRoot "..\..\kanata\game-mode.json"
  }

  It "defines profile-safe workspaces without fixed monitor indexes" {
    $config = Get-Content -LiteralPath $configPath -Raw

    foreach ($workspace in 1..12) {
      $config | Should -Match "(?m)^  - name: '$workspace'\r?$"
    }
    $config | Should -Match "(?m)^  - name: 'left'\r?$"
    $config | Should -Match "(?m)^  - name: 'vert'\r?$"
    foreach ($workspace in @("left", "vert")) {
      $config | Should -Match (
        "(?ms)^  - name: '$workspace'\r?\n    keep_alive: true\r?$"
      )
    }
    $config | Should -Not -Match "bind_to_monitor"
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

  It "starts only the managed helper scripts" {
    $config = Get-Content -LiteralPath $configPath -Raw

    $config | Should -Match "autotile\.ps1"
    $config | Should -Match "Start-GlazeWorkspaceApps\.ps1"
    $config | Should -Match "Sync-GlazeMonitorLayout\.ps1"
    $config | Should -Match "-RestartZebar"
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
    $script | Should -Match 'sourceZebarInstaller'
    $script | Should -Not -Match "(?i)seelen"
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

  It "routes the requested applications to workspaces one through four" {
    $config = Get-Content -LiteralPath $configPath -Raw

    foreach ($rule in @(
      "zen:1",
      "zotero:2",
      "Raindrop:2",
      "Todoist:2",
      "Notion Calendar:2",
      "Spotify:3",
      "Discord:3",
      "Obsidian:4"
    )) {
      $parts = $rule.Split(":")
      $pattern = "(?ms)commands: \['move --workspace $($parts[1])'\].{0,400}window_process: \{ equals: '$([regex]::Escape($parts[0]))' \}"
      $config | Should -Match $pattern
    }
  }

  It "routes every registered game to floating workspace eleven" {
    $config = Get-Content -LiteralPath $configPath -Raw
    $settings = Get-Content -LiteralPath $gameModePath -Raw | ConvertFrom-Json

    $config | Should -Match ([regex]::Escape(
      "commands: ['move --workspace 11', 'set-floating --centered=false']"
    ))
    foreach ($executable in @($settings.hard_off_executables)) {
      $processName = [IO.Path]::GetFileNameWithoutExtension($executable)
      $config | Should -Match ([regex]::Escape(
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
    $script | Should -Match '& \$GlazeWMPath --version'
    $script | Should -Match 'Unexpected GlazeWM version'
  }

  It "retries transient IPC failures while the manager starts" {
    $script = Get-Content -LiteralPath $startPath -Raw

    $script | Should -Match 'function Wait-GlazeWMReady'
    $script | Should -Match '& \$CliPath query app-metadata'
    $script | Should -Match 'while \(\(Get-Date\) -lt \$deadline\)'
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
    $script | Should -Match 'MainWindowTitle -eq "Zebar - zetshell / bar"'
    $script | Should -Match 'Zebar did not start within'
  }

  It "uses numeric monitor selectors accepted by GlazeWM 3.10" {
    $config = Get-Content -LiteralPath $configPath -Raw

    $config | Should -Match "focus --monitor 0"
    $config | Should -Match "focus --monitor 1"
    $config | Should -Not -Match "focus --monitor (left|right)"
  }
}
