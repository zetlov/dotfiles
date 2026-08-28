Describe "Active Windows audio switcher" {
  BeforeAll {
    $audioRoot = Split-Path -Parent $PSScriptRoot
    $installerModulePath = Join-Path $audioRoot "AudioSwitcherInstaller.psm1"
    $installScriptPath = Join-Path $audioRoot "install.ps1"
    $switchScriptPath = Join-Path $audioRoot "switch-audio.ps1"
    $defaultConfigPath = Join-Path $audioRoot "audio-output.json"

    Import-Module $installerModulePath -Force -ErrorAction Stop
    . $switchScriptPath -NoRun
  }

  It "ships the active installer, switch script, and default configuration" {
    foreach ($path in @(
      $installerModulePath,
      $installScriptPath,
      $switchScriptPath,
      $defaultConfigPath
    )) {
      Test-Path -LiteralPath $path -PathType Leaf | Should -BeTrue
    }
  }

  It "prefers the active local device configuration" {
    $sourceRoot = Join-Path $TestDrive (
      "audio-" + [guid]::NewGuid().ToString("N")
    )
    $legacyRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $sourceRoot | Out-Null
    New-Item -ItemType Directory -Path $legacyRoot | Out-Null
    $defaultPath = Join-Path $sourceRoot "audio-output.json"
    $activeLocalPath = Join-Path $sourceRoot "audio-output.local.json"
    $legacyLocalPath = Join-Path $legacyRoot "audio-output.local.json"
    Set-Content -LiteralPath $defaultPath -Value "{}"
    Set-Content -LiteralPath $legacyLocalPath -Value "{}"
    Set-Content -LiteralPath $activeLocalPath -Value "{}"

    $resolved = Resolve-AudioOutputConfigSource `
      -SourceRoot $sourceRoot `
      -LegacySourceRoot $legacyRoot

    $resolved | Should -Be $activeLocalPath
  }

  It "supports the legacy local configuration during migration" {
    $sourceRoot = Join-Path $TestDrive (
      "audio-" + [guid]::NewGuid().ToString("N")
    )
    $legacyRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $sourceRoot | Out-Null
    New-Item -ItemType Directory -Path $legacyRoot | Out-Null
    $defaultPath = Join-Path $sourceRoot "audio-output.json"
    $legacyLocalPath = Join-Path $legacyRoot "audio-output.local.json"
    Set-Content -LiteralPath $defaultPath -Value "{}"
    Set-Content -LiteralPath $legacyLocalPath -Value "{}"

    $resolved = Resolve-AudioOutputConfigSource `
      -SourceRoot $sourceRoot `
      -LegacySourceRoot $legacyRoot

    $resolved | Should -Be $legacyLocalPath
  }

  It "falls back to the checked-in device configuration" {
    $sourceRoot = Join-Path $TestDrive (
      "audio-" + [guid]::NewGuid().ToString("N")
    )
    $legacyRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $sourceRoot | Out-Null
    New-Item -ItemType Directory -Path $legacyRoot | Out-Null
    $defaultPath = Join-Path $sourceRoot "audio-output.json"
    Set-Content -LiteralPath $defaultPath -Value "{}"

    $resolved = Resolve-AudioOutputConfigSource `
      -SourceRoot $sourceRoot `
      -LegacySourceRoot $legacyRoot

    $resolved | Should -Be $defaultPath
  }

  It "builds a quoted noninteractive PowerShell command" {
    $scriptPath = "C:\Users\Test User\AppData\Local\dotfiles\audio\switch-audio.ps1"

    $arguments = Get-AudioSwitcherPowerShellArguments -ScriptPath $scriptPath

    $arguments | Should -Be (
      '-NoProfile -NonInteractive -WindowStyle Hidden ' +
      '-ExecutionPolicy Bypass -File "' + $scriptPath + '"'
    )
  }

  Context "shell shortcut registration" {
    BeforeEach {
      $shortcutPath = Join-Path $TestDrive "Dotfiles Audio Output.lnk"
      $targetPath = Join-Path $TestDrive "powershell.exe"
      $scriptPath = Join-Path $TestDrive "switch-audio.ps1"
      $workingDirectory = $TestDrive
      Set-Content -LiteralPath $targetPath -Value ""
      Set-Content -LiteralPath $scriptPath -Value ""
      $arguments = Get-AudioSwitcherPowerShellArguments -ScriptPath $scriptPath
    }

    It "creates and validates the exact private transport shortcut" {
      Install-AudioSwitcherShortcut `
        -ShortcutPath $shortcutPath `
        -TargetPath $targetPath `
        -Arguments $arguments `
        -WorkingDirectory $workingDirectory `
        -Hotkey "CTRL+ALT+F12"

      Test-AudioSwitcherShortcutSpec `
        -ShortcutPath $shortcutPath `
        -ExpectedTarget $targetPath `
        -ExpectedArguments $arguments `
        -ExpectedWorkingDirectory $workingDirectory `
        -ExpectedHotkey "CTRL+ALT+F12" |
        Should -BeTrue
    }

    It "refuses to replace an unexpected existing shortcut" {
      $shell = New-Object -ComObject WScript.Shell
      $shortcut = $shell.CreateShortcut($shortcutPath)
      $shortcut.TargetPath = $targetPath
      $shortcut.Arguments = "-Unexpected"
      $shortcut.Save()

      {
        Install-AudioSwitcherShortcut `
          -ShortcutPath $shortcutPath `
          -TargetPath $targetPath `
          -Arguments $arguments `
          -WorkingDirectory $workingDirectory `
          -Hotkey "CTRL+ALT+F12"
      } | Should -Throw "*modified audio shortcut*"
    }
  }

  Context "managed runtime files" {
    It "installs content atomically and skips matching files" {
      $sourcePath = Join-Path $TestDrive (
        [guid]::NewGuid().ToString("N") + ".source"
      )
      $destinationPath = Join-Path $TestDrive (
        [guid]::NewGuid().ToString("N") + ".destination"
      )
      Set-Content -LiteralPath $sourcePath -Value "audio"

      $changed = Install-AudioSwitcherManagedFile `
        -SourcePath $sourcePath `
        -DestinationPath $destinationPath
      $unchanged = Install-AudioSwitcherManagedFile `
        -SourcePath $sourcePath `
        -DestinationPath $destinationPath

      $changed | Should -BeTrue
      $unchanged | Should -BeFalse
      Get-Content -LiteralPath $destinationPath -Raw |
        Should -Be (Get-Content -LiteralPath $sourcePath -Raw)
    }

    It "rejects reparse-backed paths before copying" {
      InModuleScope AudioSwitcherInstaller {
        Mock Test-Path { $true }
        Mock Get-Item {
          [pscustomobject]@{
            Attributes = [IO.FileAttributes]::ReparsePoint
          }
        }

        {
          Install-AudioSwitcherManagedFile `
            -SourcePath "C:\source.ps1" `
            -DestinationPath "C:\destination.ps1"
        } | Should -Throw "*reparse point*"
      }
    }
  }

  It "validates the active device configuration" {
    $patterns = @(Get-AudioOutputPatterns -Path $defaultConfigPath)

    $patterns.Count | Should -BeGreaterOrEqual 2
  }

  It "installs the pinned dependency and managed runtime files" {
    $source = Get-Content -LiteralPath $installScriptPath -Raw
    $source | Should -Match '"CTRL\+ALT\+F12"'
    $source | Should -Match 'legacyShortcutMatches'

    $source | Should -Match 'Install-AudioDeviceModule'
    $source | Should -Match 'Install-AudioSwitcherManagedFile'
    $source | Should -Match 'Install-AudioSwitcherShortcut'
    $source | Should -Match 'GetFolderPath\("Programs"\)'
    $source | Should -Match '"CTRL\+ALT\+M"'
  }
}
