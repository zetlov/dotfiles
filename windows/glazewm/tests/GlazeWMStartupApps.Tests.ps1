$configPath = Join-Path $PSScriptRoot "..\startup-apps.json"
$scriptPath = Join-Path $PSScriptRoot "..\Start-GlazeWorkspaceApps.ps1"

Describe "GlazeWM startup applications" {
  It "defines the requested application set without duplicates" {
    $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    $names = @($config.applications | ForEach-Object { $_.name })

    ($names -join "|") | Should Be (
      "Zen Browser|Zotero|Raindrop.io|Todoist|Notion Calendar|" +
      "Spotify|Discord|Obsidian"
    )
    @($config.applications.processName | Sort-Object -Unique).Count |
      Should Be 8
  }

  It "validates config and skips applications that are already running" {
    $script = Get-Content -LiteralPath $scriptPath -Raw

    $script | Should Match "ConvertFrom-Json"
    $script | Should Match "Get-StartApps"
    $script | Should Match 'Get-Process -Name \$processName'
    $script | Should Match "shell:AppsFolder"
    $script | Should Match "startup-apps-error\.log"
    $script | Should Match "startup-apps-state\.json"
    $script | Should Match 'Remove-Item -LiteralPath \$statePath'
  }

  It "arranges the four workspace 2 applications as a guarded grid" {
    $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    $script = Get-Content -LiteralPath $scriptPath -Raw
    $grid = @($config.workspaceGrids)[0]

    $grid.workspaceName | Should Be "2"
    (@($grid.processNames) -join "|") | Should Be (
      "Zotero|Raindrop|Todoist|Notion Calendar"
    )
    $script | Should Match "Invoke-GlazeWorkspaceGrid"
  }
}
