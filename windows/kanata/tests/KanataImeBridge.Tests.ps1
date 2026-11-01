Describe "Kanata Surface IME bridge" {
  BeforeAll {
    function Assert-Equal {
      param($Actual, $Expected)
      if ($Actual -ne $Expected) { throw "Expected $Expected, got $Actual." }
    }
    Import-Module (Join-Path $PSScriptRoot "..\KanataImeBridge.psm1") -Force
  }

  It "accepts only physical IME Off transitions" {
    Assert-Equal ([Dotfiles.Kanata.ImeKeyState]::Matches(0, 0x100, 26, 0)) $true
    Assert-Equal ([Dotfiles.Kanata.ImeKeyState]::Matches(0, 0x101, 26, 0x80)) $true
    Assert-Equal ([Dotfiles.Kanata.ImeKeyState]::Matches(0, 0x104, 26, 0)) $true
    Assert-Equal ([Dotfiles.Kanata.ImeKeyState]::Matches(0, 0x105, 26, 0x80)) $true
    Assert-Equal ([Dotfiles.Kanata.ImeKeyState]::Matches(0, 0x100, 26, 0x10)) $false
    Assert-Equal ([Dotfiles.Kanata.ImeKeyState]::Matches(-1, 0x100, 26, 0)) $false
    Assert-Equal ([Dotfiles.Kanata.ImeKeyState]::Matches(0, 0x100, 72, 0)) $false
    Assert-Equal ([Dotfiles.Kanata.ImeKeyState]::Matches(0, 0x102, 26, 0)) $false
  }

  It "deduplicates key repeat while preserving press and release" {
    $state = New-Object Dotfiles.Kanata.ImeKeyState
    Assert-Equal ($state.Transition($false)) 0
    Assert-Equal ($state.Transition($true)) 1
    $state.Reset()
    Assert-Equal ($state.Transition($true)) 1
    Assert-Equal ($state.Transition($true)) 0
    Assert-Equal ($state.Transition($false)) 2
    Assert-Equal ($state.Transition($false)) 0
    Assert-Equal ($state.Transition($true)) 1
  }

  It "uses Kanata virtual-key messages rather than injected F13" {
    $press = [Dotfiles.Kanata.ImeBridge]::Payload($true) | ConvertFrom-Json
    Assert-Equal ($press.ActOnFakeKey.name) "surface-imeoff"
    Assert-Equal ($press.ActOnFakeKey.action) "Press"
    $release = [Dotfiles.Kanata.ImeBridge]::Payload($false) | ConvertFrom-Json
    Assert-Equal ($release.ActOnFakeKey.action) "Release"
  }

  It "rejects a different service or a missing virtual key" {
    Assert-Equal ([Dotfiles.Kanata.ImeBridge]::ValidateEndpoint(
      '{"LayerChange":{"new":"us"}}',
      '{"FakeKeyNames":{"names":["game-mode","surface-imeoff"]}}'
    )) $true
    Assert-Equal ([Dotfiles.Kanata.ImeBridge]::ValidateEndpoint(
      '{"Other":{}}', '{"FakeKeyNames":{"names":["surface-imeoff"]}}'
    )) $false
    Assert-Equal ([Dotfiles.Kanata.ImeBridge]::ValidateEndpoint(
      '{"LayerChange":{"new":"us"}}',
      '{"FakeKeyNames":{"names":["game-mode"]}}'
    )) $false
  }

  It "stops safely before a bridge has started" {
    Stop-KanataImeBridge
    Assert-Equal (Get-KanataImeBridgeError) ""
  }
}
