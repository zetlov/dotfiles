BeforeAll {
  $componentRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
  $windowsRoot = [IO.Path]::GetFullPath((Join-Path $componentRoot ".."))
  $installPath = Join-Path $componentRoot "install.ps1"
  $settingsPath = Join-Path $componentRoot "JPEGView.ini"
  $keyMapPath = Join-Path $componentRoot "KeyMap.txt"
  $manifestPath = Join-Path $windowsRoot "components.json"
}

Describe "JPEGView installer" {
  It "installs the official WinGet package and deploys user-scoped settings" {
    $source = Get-Content -LiteralPath $installPath -Raw

    $source | Should -Match 'Install-WinGetPackage'
    $source | Should -Match 'sylikc\.JPEGView'
    $source | Should -Match '\$env:APPDATA'
    $source | Should -Match 'JPEGView\.ini'
    $source | Should -Match 'KeyMap\.txt'
  }

  It "keeps imv-style navigation and primary controls" {
    $settings = Get-Content -LiteralPath $settingsPath -Raw
    $keyMap = Get-Content -LiteralPath $keyMapPath -Raw

    $settings | Should -Match '(?m)^FileDisplayOrder=FileName$'
    $settings | Should -Match '(?m)^FolderNavigation=LoopFolder$'
    $settings | Should -Match '(?m)^WrapAroundFolder=true$'
    $keyMap | Should -Match '(?m)^Q\s+IDM_EXIT$'
    $keyMap | Should -Match '(?m)^F\s+IDM_FULL_SCREEN_MODE$'
    $keyMap | Should -Match '(?m)^Right\s+IDM_NEXT$'
    $keyMap | Should -Match '(?m)^Left\s+IDM_PREV$'
  }

  It "is an optional active Windows component" {
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $component = @(
      $manifest.components | Where-Object { $_.name -eq "jpegview" }
    )

    $component.Count | Should -Be 1
    $component[0].lifecycle | Should -Be "active"
    $component[0].selectionPolicy | Should -Be "optional"
    $component[0].entrypoints.install | Should -Be "jpegview/install.ps1"
    $component[0].entrypoints.update | Should -Be "jpegview/install.ps1"
  }
}
