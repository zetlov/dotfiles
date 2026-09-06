BeforeAll {
  Import-Module (Join-Path $PSScriptRoot '../FlowLauncherConfig.psm1') -Force
  $updater = Join-Path $PSScriptRoot '../update-config.ps1'
}

Describe 'Flow Launcher deployment' {
  BeforeEach {
    $originalLocal = $env:LOCALAPPDATA
    $originalRoaming = $env:APPDATA
    $env:LOCALAPPDATA = Join-Path $TestDrive 'Local'
    $env:APPDATA = Join-Path $TestDrive 'Roaming'
    New-Item -ItemType Directory -Path "$env:LOCALAPPDATA/FlowLauncher" -Force | Out-Null
    New-Item -ItemType File -Path "$env:LOCALAPPDATA/FlowLauncher/Flow.Launcher.exe" -Force | Out-Null
    $settingsDirectory = "$env:APPDATA/FlowLauncher/Settings"
    New-Item -ItemType Directory -Path $settingsDirectory -Force | Out-Null
    $settingsPath = Join-Path $settingsDirectory 'Settings.json'
    Mock Get-Process { [PSCustomObject]@{ SessionId = 1 } } -ParameterFilter { $Id }
    Mock Get-Process { @() } -ParameterFilter { $Name -eq 'Flow.Launcher' }
    Mock Start-Process {}
  }

  AfterEach {
    $env:LOCALAPPDATA = $originalLocal
    $env:APPDATA = $originalRoaming
  }

  It 'preserves local data and creates a backup only on change' {
    $original = '{"Hotkey":"Ctrl + Space","Plugins":{"local":"preserved"}}'
    Set-Content -LiteralPath $settingsPath -Value $original
    $first = & $updater
    $first.Changed | Should -BeTrue
    (Get-Content $first.BackupPath -Raw).Trim() | Should -Be $original
    (Get-Content $settingsPath -Raw | ConvertFrom-Json).Plugins.local | Should -Be 'preserved'
    $second = & $updater
    $second.Changed | Should -BeFalse
    @(Get-ChildItem $settingsDirectory -Filter '*.bak').Count | Should -Be 1
  }

  It 'keeps malformed settings untouched and does not start Flow' {
    Set-Content -LiteralPath $settingsPath -Value '{broken'
    { & $updater } | Should -Throw
    (Get-Content $settingsPath -Raw).Trim() | Should -Be '{broken'
    Should -Invoke Start-Process -Times 0 -Exactly
  }

  It 'refuses portable data before modifying roaming settings' {
    New-Item -ItemType Directory "$env:LOCALAPPDATA/FlowLauncher/UserData" -Force | Out-Null
    { & $updater } | Should -Throw '*Portable*'
    Should -Invoke Start-Process -Times 0 -Exactly
  }
}

Describe 'Flow Launcher managed settings' {
  It 'does not send a close message when no matching process window exists' {
    if (-not ('Dotfiles.FlowLauncherWindow' -as [type])) {
      Add-Type -Path (Join-Path $PSScriptRoot '../FlowLauncherWindow.cs')
    }
    [Dotfiles.FlowLauncherWindow]::RequestClose([uint32]::MaxValue) | Should -BeFalse
  }

  It 'overlays shared preferences while preserving private and plugin settings' {
    $existing = '{"Hotkey":"Ctrl + Space","Plugins":{"token":"test-only"},"Other":42}'
    $result = Merge-FlowLauncherSettings -ExistingJson $existing -ManagedJson '{"Hotkey":"Alt + Space"}'
    $settings = $result.Json | ConvertFrom-Json
    $result.Changed | Should -BeTrue
    $settings.Hotkey | Should -Be 'Alt + Space'
    $settings.Plugins.token | Should -Be 'test-only'
    $settings.Other | Should -Be 42
  }

  It 'does not rewrite settings that already match' {
    $result = Merge-FlowLauncherSettings -ExistingJson '{"Hotkey":"Alt + Space"}' -ManagedJson '{"Hotkey":"Alt + Space"}'
    $result.Changed | Should -BeFalse
  }

  It 'can initialize a new settings file' {
    $result = Merge-FlowLauncherSettings -ExistingJson '{}' -ManagedJson '{"HideOnStartup":true}'
    ($result.Json | ConvertFrom-Json).HideOnStartup | Should -BeTrue
  }

  It 'rejects unmanaged properties and invalid preference types' {
    { Merge-FlowLauncherSettings -ExistingJson '{}' -ManagedJson '{"Plugins":{}}' } | Should -Throw
    { Merge-FlowLauncherSettings -ExistingJson '{}' -ManagedJson '{"HideOnStartup":"true"}' } | Should -Throw
    { Merge-FlowLauncherSettings -ExistingJson '{}' -ManagedJson '{"Hotkey":""}' } | Should -Throw
  }

  It 'rejects damaged or non-object settings instead of replacing them' {
    { Merge-FlowLauncherSettings -ExistingJson '{broken' -ManagedJson '{}' } | Should -Throw
    { Merge-FlowLauncherSettings -ExistingJson '[]' -ManagedJson '{}' } | Should -Throw
    { Merge-FlowLauncherSettings -ExistingJson '{}' -ManagedJson 'null' } | Should -Throw
  }
}
