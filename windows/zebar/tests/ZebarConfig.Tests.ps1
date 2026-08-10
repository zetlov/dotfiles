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

Describe "Zetshell Zebar configuration" {
  It "defines a docked 42 pixel bar on the primary monitor" {
    $pack = Get-Content -LiteralPath $packPath -Raw | ConvertFrom-Json
    $widget = @($pack.widgets)[0]
    $preset = @($widget.presets)[0]

    $pack.name | Should Be "zetshell"
    $widget.name | Should Be "bar"
    $widget.htmlPath | Should Be "./dist/index.html"
    (@($widget.includeFiles) -contains "dist/**/*") | Should Be $true
    $widget.transparent | Should Be $true
    $preset.height | Should Be "42px"
    $preset.width | Should Be "100%"
    $preset.name | Should Be "primary-monitor"
    $preset.monitorSelection.type | Should Be "primary"
    $preset.monitorSelection.PSObject.Properties.Name -contains "match" |
      Should Be $false
    $preset.dockToEdge.enabled | Should Be $true
    $preset.dockToEdge.edge | Should Be "top"
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
      $source | Should Match "${provider}:\s*\{\s*type:\s*'${provider}'"
    }
    $pack | Should Not Match "https?://"
    $source | Should Not Match "https?://"
  }

  It "allows only the pinned NVIDIA utilization and temperature command" {
    $pack = Get-Content -LiteralPath $packPath -Raw | ConvertFrom-Json
    $widget = @($pack.widgets)[0]
    $commands = @($widget.privileges.shellCommands)

    $commands.Count | Should Be 1
    $commands[0].program | Should Be "C:\Windows\System32\nvidia-smi.exe"
    $commands[0].argsRegex | Should Be (
      '^--query-gpu=utilization\.gpu,temperature\.gpu ' +
      '--format=csv,noheader,nounits ' +
      '--id=0 --loop-ms=2000$'
    )
  }

  It "uses floating glass islands with restrained motion" {
    $style = Get-Content -LiteralPath $stylePath -Raw

    $style | Should Match '--bar-height:\s*42px'
    $style | Should Match '\.island\s*\{[^}]*backdrop-filter:\s*blur\('
    $style | Should Match '\.island\s*\{[^}]*box-shadow:'
    $style | Should Match 'Segoe UI Variable'
    $style | Should Match '@media\s*\(prefers-reduced-motion:\s*reduce\)'
  }

  It "keeps a two-tier clock centered and includes seconds" {
    $source = Get-Content -LiteralPath $sourcePath -Raw
    $style = Get-Content -LiteralPath $stylePath -Raw

    $source | Should Match "formatting:\s*'HH:mm:ss'"
    $source | Should Match "formatting:\s*'yyyy/MM/dd \(ccc\)'"
    $source | Should Match 'class="clock-time"'
    $source | Should Match 'class="clock-date"'
    $style | Should Match 'left:\s*50%'
    $style | Should Match 'transform:\s*translateX\(-50%\)'
  }

  It "uses bundled vector icons for media and system status" {
    $source = Get-Content -LiteralPath $sourcePath -Raw
    $package = Get-Content -LiteralPath $packagePath -Raw | ConvertFrom-Json

    $package.dependencies."lucide-solid" | Should Be "1.30.0"
    $source | Should Match "from 'lucide-solid'"
    foreach ($icon in @("Pause", "Play", "SkipBack", "SkipForward")) {
      $source | Should Match "<${icon}\b"
    }
    $source | Should Not Match "[‹›Ⅱ▶]"
    $source | Should Match 'aria-current='
    $source | Should Match 'aria-label=\{`CPU'
    $source | Should Match 'aria-label=\{`Memory'
    $source | Should Match '(?s)aria-label=\{.+?GPU.+?degrees Celsius'
    $source | Should Match '<Gpu\b'
  }

  It "pins Node with mise and verifies generated assets in CI" {
    $mise = Get-Content -LiteralPath $misePath -Raw
    $workflow = Get-Content -LiteralPath $workflowPath -Raw

    $mise | Should Match 'node\s*=\s*"26\.7\.0"'
    $mise | Should Match 'npm run typecheck'
    $mise | Should Match 'npm run build'
    $workflow | Should Match 'jdx/mise-action@7e36c90d9ab29c415a2384db3006f3ec8a8cc654'
    $workflow | Should Match 'version:\s*2026\.8\.3'
    $workflow | Should Match 'sha256:\s*66585ac496c10bf6fbf13272e3e550c1813aed0e1cb780b9bb73c1751de49289'
    $workflow | Should Match 'working_directory:\s*windows/zebar'
    $workflow | Should Match 'mise run check'
    $workflow | Should Match 'git diff --exit-code -- dist'
  }

  It "deploys the built pack and is started by GlazeWM" {
    $installer = Get-Content -LiteralPath $installerPath -Raw
    $glazeConfig = Get-Content -LiteralPath $glazeConfigPath -Raw

    $installer | Should Match 'zpack\.json'
    $installer | Should Match 'dist'
    $installer | Should Match '\.glzr\\zebar\\zetshell'
    $glazeConfig | Should Match 'zebar start-widget-preset'
    $glazeConfig | Should Match 'window_process: \{ equals: ''zebar'' \}'
  }

  It "pins and validates the Zebar runtime version" {
    $installer = Get-Content -LiteralPath $installerPath -Raw

    $installer | Should Match '\$RequiredVersion = "3\.3\.1"'
    $installer | Should Match '--version \$RequiredVersion'
    $installer | Should Match '& \$ZebarPath --version'
    $installer | Should Match 'Unexpected Zebar version'
  }

  It "restores a running managed widget after deployment failure" {
    $installer = Get-Content -LiteralPath $installerPath -Raw
    $glazeConfig = Get-Content -LiteralPath $glazeConfigPath -Raw

    $installer | Should Match '\$zebarWasRunning'
    $installer | Should Match 'if \(-not \$installed -and \$zebarWasRunning'
    $installer | Should Match 'start-widget-preset'
    $installer | Should Match '"--preset", "primary-monitor"'
    $glazeConfig | Should Match '--preset primary-monitor'
    $installer | Should Not Match 'all-monitors'
    $glazeConfig | Should Not Match 'all-monitors'
  }

  It "stops only the managed GPU monitor before replacing Zebar" {
    $installer = Get-Content -LiteralPath $installerPath -Raw
    . $processHelpersPath
    $commandLines = @(Get-ZetshellGpuMonitorCommandLines)

    $commandLines.Count | Should Be 2
    $commandLines[0] | Should Be (
      '"C:\Windows\System32\nvidia-smi.exe" ' +
      '--query-gpu=utilization.gpu,temperature.gpu ' +
      '--format=csv,noheader,nounits --id=0 --loop-ms=2000'
    )
    $commandLines[1] | Should Be (
      '"C:\Windows\System32\nvidia-smi.exe" ' +
      '--query-gpu=utilization.gpu ' +
      '--format=csv,noheader,nounits --id=0 --loop-ms=2000'
    )
    $installer | Should Match '\. \$sourceProcessHelpers'
    $installer | Should Match '(?s)Get-ZetshellGpuMonitorProcess.+?Stop-Process.+?Get-Process -Name "zebar".+?Stop-Process'
  }
}
