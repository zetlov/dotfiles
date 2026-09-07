Describe "Spicetify installer" {
  BeforeAll {
    $componentRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
    $windowsRoot = [IO.Path]::GetFullPath((Join-Path $componentRoot ".."))
    $installPath = Join-Path $componentRoot "install.ps1"
    $applyPath = Join-Path $componentRoot "apply.ps1"
    $settingsPath = Join-Path $componentRoot "settings.psd1"
    $manifestPath = Join-Path $windowsRoot "components.json"
  }

  It "installs the official WinGet package without executing a remote script" {
    $source = Get-Content -LiteralPath $installPath -Raw

    $source | Should -Match ([regex]::Escape("Spicetify.Spicetify"))
    $source | Should -Match "Install-WinGetPackage"
    $source | Should -Not -Match "Invoke-Expression|\biex\b|curl|Invoke-WebRequest"
  }

  It "keeps portable settings in a tracked PowerShell data file" {
    $settings = Import-PowerShellDataFile -LiteralPath $settingsPath

    $settings.check_spicetify_update | Should -Be "1"
    $settings.inject_css | Should -Be "1"
    $settings.inject_theme_js | Should -Be "1"
    $settings.replace_colors | Should -Be "1"
    $settings.overwrite_assets | Should -Be "0"
    $settings.disable_sentry | Should -Be "1"
    $settings.disable_ui_logging | Should -Be "1"
    $settings.remove_rtl_rule | Should -Be "1"
    $settings.expose_apis | Should -Be "1"
  }

  It "does not apply Spotify patches during package installation" {
    $installSource = Get-Content -LiteralPath $installPath -Raw
    $applySource = Get-Content -LiteralPath $applyPath -Raw

    $installSource | Should -Not -Match "backup\s+apply"
    $applySource | Should -Match "backup"
    $applySource | Should -Match "apply"
  }

  It "is an optional active Windows component" {
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $component = @(
      $manifest.components |
        Where-Object { $_.name -eq "spicetify" }
    )

    $component.Count | Should -Be 1
    $component[0].lifecycle | Should -Be "active"
    $component[0].selectionPolicy | Should -Be "optional"
    $component[0].entrypoints.install | Should -Be "spicetify/install.ps1"
    $component[0].entrypoints.update | Should -Be "spicetify/install.ps1"
  }
}
