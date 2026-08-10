Describe "Zetshell Zebar configuration" {
  BeforeAll {
    function Assert-Equal {
      param(
        [Parameter(ValueFromPipeline = $true)]
        $Actual,
        [Parameter(Position = 0)]
        $Expected
      )
      process {
        if ($Actual -ne $Expected) {
          throw "Expected '$Expected', got '$Actual'."
        }
      }
    }

    function Assert-Match {
      param(
        [Parameter(ValueFromPipeline = $true)]
        [string]$Actual,
        [Parameter(Position = 0)]
        [string]$Pattern,
        [switch]$Not
      )
      process {
        $matched = $Actual -match $Pattern
        if ($matched -eq $Not.IsPresent) {
          throw "Unexpected match result for pattern '$Pattern'."
        }
      }
    }

    $root = Join-Path $PSScriptRoot ".."
    $packPath = Join-Path $root "zpack.json"
    $sourcePath = Join-Path $root "src\index.tsx"
    $stylePath = Join-Path $root "src\index.css"
    $installerPath = Join-Path $root "install.ps1"
    $processHelpersPath = Join-Path $root "ZebarProcessHelpers.ps1"
    $glazeConfigPath = Join-Path $root "..\glazewm\config.yaml"
    $packagePath = Join-Path $root "package.json"
    $misePath = Join-Path $root "mise.toml"
    $workflowPath = Join-Path $root "..\..\.github\workflows\check.yaml"
  }

  It "defines a docked 42 pixel bar on the primary monitor" {
    $pack = Get-Content -LiteralPath $packPath -Raw | ConvertFrom-Json
    $widget = @($pack.widgets)[0]
    $preset = @($widget.presets)[0]

    $pack.name | Assert-Equal "zetshell"
    $widget.name | Assert-Equal "bar"
    $widget.htmlPath | Assert-Equal "./dist/index.html"
    (@($widget.includeFiles) -contains "dist/**/*") | Assert-Equal $true
    $widget.transparent | Assert-Equal $true
    $preset.height | Assert-Equal "42px"
    $preset.width | Assert-Equal "100%"
    $preset.name | Assert-Equal "primary-monitor"
    $preset.monitorSelection.type | Assert-Equal "primary"
    $preset.monitorSelection.PSObject.Properties.Name -contains "match" |
      Assert-Equal $false
    $preset.dockToEdge.enabled | Assert-Equal $true
    $preset.dockToEdge.edge | Assert-Equal "top"
  }

  It "uses local bundled assets and the requested providers" {
    $source = Get-Content -LiteralPath $sourcePath -Raw
    $pack = Get-Content -LiteralPath $packPath -Raw

    foreach ($provider in @(
      "glazewm",
      "audio",
      "cpu",
      "date",
      "media",
      "memory",
      "network",
      "systray"
    )) {
      $source | Assert-Match "${provider}:\s*\{\s*type:\s*'${provider}'"
    }
    $pack | Assert-Match -Not "https?://"
    $source | Assert-Match -Not "https?://"
  }

  It "allows only the pinned NVIDIA utilization and temperature command" {
    $pack = Get-Content -LiteralPath $packPath -Raw | ConvertFrom-Json
    $widget = @($pack.widgets)[0]
    $commands = @($widget.privileges.shellCommands)

    $commands.Count | Assert-Equal 1
    $commands[0].program | Assert-Equal "C:\Windows\System32\nvidia-smi.exe"
    $commands[0].argsRegex | Assert-Equal (
      '^--query-gpu=utilization\.gpu,temperature\.gpu ' +
      '--format=csv,noheader,nounits ' +
      '--id=0 --loop-ms=2000$'
    )
  }

  It "uses floating glass islands with restrained motion" {
    $style = Get-Content -LiteralPath $stylePath -Raw

    $style | Assert-Match '--bar-height:\s*42px'
    $style | Assert-Match '\.island\s*\{[^}]*backdrop-filter:\s*blur\('
    $style | Assert-Match '\.island\s*\{[^}]*box-shadow:'
    $style | Assert-Match 'Segoe UI Variable'
    $style | Assert-Match '@media\s*\(prefers-reduced-motion:\s*reduce\)'
  }

  It "keeps a two-tier clock centered and includes seconds" {
    $source = Get-Content -LiteralPath $sourcePath -Raw
    $style = Get-Content -LiteralPath $stylePath -Raw

    $source | Assert-Match "formatting:\s*'HH:mm:ss'"
    $source | Assert-Match "formatting:\s*'yyyy/MM/dd \(ccc\)'"
    $source | Assert-Match 'class="clock-time"'
    $source | Assert-Match 'class="clock-date"'
    $style | Assert-Match 'left:\s*50%'
    $style | Assert-Match 'transform:\s*translateX\(-50%\)'
  }

  It "uses bundled vector icons for media and system status" {
    $source = Get-Content -LiteralPath $sourcePath -Raw
    $package = Get-Content -LiteralPath $packagePath -Raw | ConvertFrom-Json

    $package.dependencies."lucide-solid" | Assert-Equal "1.30.0"
    $source | Assert-Match "from 'lucide-solid'"
    foreach ($icon in @("Pause", "Play", "SkipBack", "SkipForward")) {
      $source | Assert-Match "<${icon}\b"
    }
    $source | Assert-Match -Not "[‹›Ⅱ▶]"
    $source | Assert-Match 'aria-current='
    $source | Assert-Match 'aria-label=\{`CPU'
    $source | Assert-Match 'aria-label=\{`Memory'
    $source | Assert-Match '(?s)aria-label=\{.+?GPU.+?degrees Celsius'
    $source | Assert-Match '<Gpu\b'
  }

  It "pins Node with mise and verifies generated assets in CI" {
    $mise = Get-Content -LiteralPath $misePath -Raw
    $workflow = Get-Content -LiteralPath $workflowPath -Raw

    $mise | Assert-Match 'node\s*=\s*"26\.7\.0"'
    $mise | Assert-Match 'npm run typecheck'
    $mise | Assert-Match 'npm run build'
    $workflow | Assert-Match 'jdx/mise-action@7e36c90d9ab29c415a2384db3006f3ec8a8cc654'
    $workflow | Assert-Match 'version:\s*2026\.8\.3'
    $workflow | Assert-Match '(?s)zebar:.+?sha256:\s*b09bfe160ffa33236f03547e6e0ef2bd937fcd7556b1feb5c2d227c174ef2a22'
    $workflow | Assert-Match 'working_directory:\s*windows/zebar'
    $workflow | Assert-Match 'mise run check'
    $workflow | Assert-Match 'git diff --exit-code -- dist'
  }

  It "deploys the built pack and is started by GlazeWM" {
    $installer = Get-Content -LiteralPath $installerPath -Raw
    $glazeConfig = Get-Content -LiteralPath $glazeConfigPath -Raw

    $installer | Assert-Match 'zpack\.json'
    $installer | Assert-Match 'dist'
    $installer | Assert-Match '\.glzr\\zebar\\zetshell'
    $glazeConfig | Assert-Match 'zebar start-widget-preset'
    $glazeConfig | Assert-Match 'window_process: \{ equals: ''zebar'' \}'
  }

  It "pins and validates the Zebar runtime version" {
    $installer = Get-Content -LiteralPath $installerPath -Raw

    $installer | Assert-Match '\$RequiredVersion = "3\.3\.1"'
    $installer | Assert-Match '--version \$RequiredVersion'
    $installer | Assert-Match '& \$ZebarPath --version'
    $installer | Assert-Match 'Unexpected Zebar version'
  }

  It "restores a running managed widget after deployment failure" {
    $installer = Get-Content -LiteralPath $installerPath -Raw
    $glazeConfig = Get-Content -LiteralPath $glazeConfigPath -Raw

    $installer | Assert-Match '\$zebarWasRunning'
    $installer | Assert-Match 'if \(-not \$installed -and \$zebarWasRunning'
    $installer | Assert-Match 'start-widget-preset'
    $installer | Assert-Match '"--preset", "primary-monitor"'
    $glazeConfig | Assert-Match '--preset primary-monitor'
    $installer | Assert-Match -Not 'all-monitors'
    $glazeConfig | Assert-Match -Not 'all-monitors'
  }

  It "stops only the managed GPU monitor before replacing Zebar" {
    $installer = Get-Content -LiteralPath $installerPath -Raw
    . $processHelpersPath
    $commandLines = @(Get-ZetshellGpuMonitorCommandLines)

    $commandLines.Count | Assert-Equal 2
    $commandLines[0] | Assert-Equal (
      '"C:\Windows\System32\nvidia-smi.exe" ' +
      '--query-gpu=utilization.gpu,temperature.gpu ' +
      '--format=csv,noheader,nounits --id=0 --loop-ms=2000'
    )
    $commandLines[1] | Assert-Equal (
      '"C:\Windows\System32\nvidia-smi.exe" ' +
      '--query-gpu=utilization.gpu ' +
      '--format=csv,noheader,nounits --id=0 --loop-ms=2000'
    )
    $installer | Assert-Match '\. \$sourceProcessHelpers'
    $installer | Assert-Match '(?s)Get-ZetshellGpuMonitorProcess.+?Stop-Process.+?Get-Process -Name "zebar".+?Stop-Process'
  }
}
