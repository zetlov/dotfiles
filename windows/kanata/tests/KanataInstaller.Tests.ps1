Describe "Kanata installer" {
BeforeAll {
  $modulePath = Join-Path $PSScriptRoot "..\KanataInstaller.psm1"
  Import-Module $modulePath -Force
  $defenderModulePath = Join-Path $PSScriptRoot "..\KanataDefender.psm1"
  Import-Module $defenderModulePath -Force

  function Assert-Equal {
    param($Actual, $Expected)
    if ($Actual -ne $Expected) {
      throw "Expected '$Expected', got '$Actual'."
    }
  }

  function Assert-Throws {
    param([scriptblock]$Operation)
    try {
      & $Operation
    } catch {
      return
    }
    throw "Expected the operation to throw."
  }

  function Assert-DoesNotThrow {
    param([scriptblock]$Operation)
    & $Operation
  }
}

Context "Get-KanataReleaseSpec" {
  It "returns the pinned x64 release metadata" {
    $spec = Get-KanataReleaseSpec -Cpu "x64" -Driver "winio"

    Assert-Equal $spec.Version "v1.12.0"
    Assert-Equal $spec.AssetName "windows-binaries-x64.zip"
    Assert-Equal $spec.Sha256 "13947ed78cfa3284bfef854e3c542c74ab366236b72fd9f7e039f8638deead9d"
  }

  It "returns the pinned arm64 release metadata" {
    $spec = Get-KanataReleaseSpec -Cpu "arm64" -Driver "winio"

    Assert-Equal $spec.Version "v1.12.0"
    Assert-Equal $spec.AssetName "windows-binaries-arm64.zip"
    Assert-Equal $spec.Sha256 "f6970ebda03c03c370a1dedf8a75cb73a1690cfd3095f459b5bb3f527aa75407"
  }

  It "rejects unsupported CPU values" {
    Assert-Throws { Get-KanataReleaseSpec -Cpu "x86" -Driver "winio" }
  }

  It "rejects wintercept on arm64 before installation" {
    Assert-Throws { Get-KanataReleaseSpec -Cpu "arm64" -Driver "wintercept" }
  }
}

Context "Resolve-KanataDefenderExclusionPath" {
  It "accepts only kanata.exe under LOCALAPPDATA" {
    $path = Join-Path $env:LOCALAPPDATA "kanata\kanata.exe"
    $resolved = Resolve-KanataDefenderExclusionPath -ExePath $path

    Assert-Equal $resolved ([System.IO.Path]::GetFullPath($path))
  }

  It "rejects paths outside LOCALAPPDATA" {
    Assert-Throws {
      Resolve-KanataDefenderExclusionPath -ExePath "$env:WINDIR\System32\kanata.exe"
    }
  }

  It "rejects exclusions for other file names" {
    Assert-Throws {
      Resolve-KanataDefenderExclusionPath `
        -ExePath (Join-Path $env:LOCALAPPDATA "kanata\other.exe")
    }
  }
}

Context "Keyboard modifier configuration" {
  It "turns IME off after sending Escape from Space+Q" {
    $configPath = Join-Path $PSScriptRoot "..\kanata.kbd"
    $config = Get-Content -LiteralPath $configPath -Raw

    $escapeImeOff = "(?m)^\s*escimeoff\s+" +
      [regex]::Escape("(macro esc f13)") +
      "\s*$"
    if ($config -notmatch $escapeImeOff) {
      throw "Space+Q must send Escape before the IME-off F13 key."
    }

    $navLayer = [regex]::Match(
      $config,
      "(?ms)^\(deflayer\s+nav\s+(.*?)^\)\s*$"
    )
    Assert-Equal $navLayer.Success $true
    $tokens = @($navLayer.Groups[1].Value -split "\s+" | Where-Object { $_ })
    Assert-Equal $tokens[15] "@escimeoff"
  }

  It "swaps Left Win and Left Alt and uses Right Alt for IME on" {
    $configPath = Join-Path $PSScriptRoot "..\kanata.kbd"
    $config = Get-Content -LiteralPath $configPath -Raw

    $leftSuper = "(?m)^\s*lsuper\s+" +
      [regex]::Escape("(tap-hold-press 120 180 f13 (layer-while-held wm))") +
      "\s*$"
    if ($config -notmatch $leftSuper) {
      throw "The Left Alt position must tap F13 and hold the window-manager layer."
    }

    $rightIme = "(?m)^\s*imeon\s+" +
      [regex]::Escape("(tap-hold-press 120 180 f15 ralt)") +
      "\s*$"
    if ($config -notmatch $rightIme) {
      throw "Right Alt must tap F15 and hold the native Alt modifier."
    }

    $safeTab = "(?m)^\s*safetab\s+" +
      [regex]::Escape(
        "(switch ((input real lalt)) XX break () tab break)"
      ) +
      "\s*$"
    if ($config -notmatch $safeTab) {
      throw (
        "Tab must stay blocked throughout the physical Super key chord " +
        "and its release boundary."
      )
    }

    if ($config -match 'safetab[^\r\n]*(input real lmet)') {
      throw "The original Left Win position must retain native Alt+Tab."
    }

    $modifierRow = "(?m)^\s*_\s+lalt\s+@lsuper\s+@spcnav\s+@imeon\s+_\s+_\s*$"
    Assert-Equal ([regex]::Matches($config, $modifierRow).Count) 2

    $activeConfig = [regex]::Replace($config, "(?m);;.*$", "")
    $defsrc = [regex]::Match(
      $activeConfig,
      "(?ms)^\(defsrc\s+(.*?)^\)\s*$"
    )
    Assert-Equal $defsrc.Success $true
    $sourceTokens = @($defsrc.Groups[1].Value -split "\s+" | Where-Object { $_ })
    Assert-Equal $sourceTokens.Count 65

    foreach ($layerName in @("us", "jis", "nav", "wm")) {
      $layer = [regex]::Match(
        $activeConfig,
        "(?ms)^\(deflayer\s+$layerName\s+(.*?)^\)\s*$"
      )
      Assert-Equal $layer.Success $true
      $layerTokens = @($layer.Groups[1].Value -split "\s+" | Where-Object { $_ })
      Assert-Equal $layerTokens.Count $sourceTokens.Count
    }

    foreach ($layerName in @("us", "jis")) {
      $layer = [regex]::Match(
        $activeConfig,
        "(?ms)^\(deflayer\s+$layerName\s+(.*?)^\)\s*$"
      )
      $layerTokens = @($layer.Groups[1].Value -split "\s+" | Where-Object { $_ })
      Assert-Equal $layerTokens[14] "@safetab"
    }

    $wmLayer = [regex]::Match(
      $activeConfig,
      "(?ms)^\(deflayer\s+wm\s+(.*?)^\)\s*$"
    )
    Assert-Equal $wmLayer.Success $true

    $tokens = @($wmLayer.Groups[1].Value -split "\s+" | Where-Object { $_ })
    $expectedTokens = @(
      "XX", "@wm1", "@wm2", "@wm3", "@wm4", "@wm5", "@wm6",
      "@wm7", "@wm8", "@wm9", "@wm0", "@wmminus", "@wmequal", "XX",
      "XX", "C-A-q", "XX", "XX", "XX", "XX", "XX", "XX", "XX", "XX",
      "pp", "XX", "XX", "XX",
      "XX", "XX", "M-S-s", "XX", "@wmf", "XX", "@wmh", "@wmj", "@wmk",
      "@wml", "XX", "XX", "C-A-t",
      "XX", "XX", "XX", "XX", "XX", "C-A-b", "XX", "C-A-m", "@wmcomma",
      "@wmperiod", "XX", "XX", "XX",
      "XX", "_", "XX", "A-spc", "_", "XX", "XX",
      "C-A-left", "C-A-down", "C-A-up", "C-A-rght"
    )
    Assert-Equal ($tokens -join "|") ($expectedTokens -join "|")

    $shiftCondition = "((or (input real lsft) (input real rsft)))"
    $controlCondition = "((or (input real lctl) (input real rctl)))"
    foreach ($mapping in @(
      @{ Name = "wm1"; Key = "1" },
      @{ Name = "wm2"; Key = "2" },
      @{ Name = "wm3"; Key = "3" },
      @{ Name = "wm4"; Key = "4" },
      @{ Name = "wm5"; Key = "5" },
      @{ Name = "wm6"; Key = "6" },
      @{ Name = "wm7"; Key = "7" },
      @{ Name = "wm8"; Key = "8" },
      @{ Name = "wm9"; Key = "9" },
      @{ Name = "wm0"; Key = "0" },
      @{ Name = "wmminus"; Key = "-" },
      @{ Name = "wmequal"; Key = "=" }
    )) {
      $aliasLine = [regex]::Match(
        $activeConfig,
        "(?m)^\s*$($mapping.Name)\s+(.+?)\s*$"
      )
      Assert-Equal $aliasLine.Success $true
      $expected = (
        "(switch $shiftCondition C-A-S-$($mapping.Key) break " +
        "() C-A-$($mapping.Key) break)"
      )
      Assert-Equal $aliasLine.Groups[1].Value $expected
    }

    foreach ($mapping in @(
      @{ Name = "wmh"; Focus = "f16"; Move = "f20"; Reserve = "S-f16" },
      @{ Name = "wmj"; Focus = "f17"; Move = "f21"; Reserve = "S-f17" },
      @{ Name = "wmk"; Focus = "f18"; Move = "f22"; Reserve = "S-f18" },
      @{ Name = "wml"; Focus = "f19"; Move = "f23"; Reserve = "S-f19" }
    )) {
      $aliasLine = [regex]::Match(
        $activeConfig,
        "(?m)^\s*$($mapping.Name)\s+(.+?)\s*$"
      )
      Assert-Equal $aliasLine.Success $true
      $expected = (
        "(switch $controlCondition $($mapping.Move) break " +
        "$shiftCondition $($mapping.Reserve) break " +
        "() $($mapping.Focus) break)"
      )
      Assert-Equal $aliasLine.Groups[1].Value $expected
    }

    $floatAlias = [regex]::Match(
      $activeConfig,
      "(?m)^\s*wmf\s+(.+?)\s*$"
    )
    Assert-Equal $floatAlias.Success $true
    Assert-Equal $floatAlias.Groups[1].Value (
      "(switch $shiftCondition C-A-S-f break () C-A-f break)"
    )

    foreach ($mapping in @(
      @{ Name = "wmcomma"; Key = "," },
      @{ Name = "wmperiod"; Key = "." }
    )) {
      $aliasLine = [regex]::Match(
        $activeConfig,
        "(?m)^\s*$($mapping.Name)\s+(.+?)\s*$"
      )
      Assert-Equal $aliasLine.Success $true
      $expected = (
        "(switch $controlCondition C-A-S-$($mapping.Key) break " +
        "() C-A-$($mapping.Key) break)"
      )
      Assert-Equal $aliasLine.Groups[1].Value $expected
    }

    $whkdPath = Join-Path $PSScriptRoot "..\..\komorebi\whkdrc"
    $whkdKeyAliases = @{
      "oem_1" = ";"
      "oem_comma" = ","
      "oem_period" = "."
      "oem_minus" = "-"
      "oem_plus" = "="
      "return" = "ret"
      "right" = "rght"
    }
    $whkdChords = @(
      foreach ($line in Get-Content -LiteralPath $whkdPath) {
        $binding = [regex]::Match(
          $line,
          "^\s*ctrl\s+\+\s+alt(?:\s+\+\s+shift)?\s+\+\s+([^:]+?)\s+:"
        )
        $pause = [regex]::Match(
          $line,
          "^\s*\.pause\s+ctrl\s+\+\s+alt(?:\s+\+\s+shift)?\s+\+\s+(\S+)\s*$"
        )
        if ($binding.Success -or $pause.Success) {
          $match = if ($binding.Success) { $binding } else { $pause }
          $key = $match.Groups[1].Value.Trim()
          if ($whkdKeyAliases.ContainsKey($key)) {
            $key = $whkdKeyAliases[$key]
          }
          $prefix = if ($line -match "\+\s+shift\s+\+") {
            "C-A-S-"
          } else {
            "C-A-"
          }
          "$prefix$key"
        }
      }
    ) | Sort-Object -Unique
    $wmChords = @(
      [regex]::Matches($activeConfig, "(?<!\S)C-A-[^\s()]+") |
        ForEach-Object { $_.Value } |
        Sort-Object -Unique
    )
    $undefinedChords = @($wmChords | Where-Object { $_ -notin $whkdChords })
    Assert-Equal ($undefinedChords -join "|") ""
  }
}

Context "Game mode installer integration" {
  It "does not recreate the shared Run key when it already exists" {
    foreach ($relativePath in @(
      "..\KanataGameMode.psm1",
      "..\install.ps1",
      "..\update-config.ps1"
    )) {
      $script = Get-Content `
        -LiteralPath (Join-Path $PSScriptRoot $relativePath) `
        -Raw
      if ($script -match 'New-Item -Path \$runKey -Force') {
        throw "The shared Windows Run key must not be recreated."
      }
    }
  }

  BeforeAll {
    $installScript = Get-Content `
      -LiteralPath (Join-Path $PSScriptRoot "..\install.ps1") `
      -Raw
    $updateScript = Get-Content `
      -LiteralPath (Join-Path $PSScriptRoot "..\update-config.ps1") `
      -Raw
    $uninstallScript = Get-Content `
      -LiteralPath (Join-Path $PSScriptRoot "..\uninstall.ps1") `
      -Raw
  }

  It "installs and starts the game mode watcher" {
    foreach ($name in @(
      "KanataGameMode.psm1",
      "game-mode.ps1",
      "game-mode.json"
    )) {
      Assert-Equal $installScript.Contains($name) $true
    }
    Assert-Equal $installScript.Contains("Start-KanataGameModeWatcher") $true
  }

  It "lets the watcher restart Kanata after config updates" {
    foreach ($name in @(
      "kanata.kbd",
      "KanataGameMode.psm1",
      "game-mode.ps1",
      "game-mode.json"
    )) {
      Assert-Equal $updateScript.Contains($name) $true
    }
    Assert-Equal $updateScript.Contains("Start-KanataGameModeWatcher") $true
    Assert-Equal $updateScript.Contains("Set-KanataGameModeRunEntry") $true
  }

  It "stops and unregisters the watcher during uninstall" {
    Assert-Equal $uninstallScript.Contains("Stop-KanataGameModeWatcher") $true
    Assert-Equal $uninstallScript.Contains("Test-KanataOwnedRunValue") $true
  }

  It "restores managed files when installation fails" {
    Assert-Equal $installScript.Contains("rollbackPrepared") $true
    Assert-Equal $installScript.Contains("previousRunValues") $true
  }
}

Context "Assert-FileSha256" {
  BeforeEach {
    $testFile = Join-Path $TestDrive "kanata-test.bin"
    $bytes = [System.Text.Encoding]::ASCII.GetBytes("kanata-test")
    [System.IO.File]::WriteAllBytes($testFile, $bytes)
  }

  It "accepts a matching SHA-256 digest" {
    Assert-DoesNotThrow {
      Assert-FileSha256 `
        -Path $testFile `
        -ExpectedSha256 "bfee19df63a8403a277e9a0657e7bf63ebfe15a0639c084aa3d3c219290e496f"
    }
  }

  It "rejects a mismatched SHA-256 digest" {
    Assert-Throws {
      Assert-FileSha256 `
        -Path $testFile `
        -ExpectedSha256 ("0" * 64)
    }
  }
}

Context "Verified Kanata executable installation" {
  BeforeEach {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $caseRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString("N"))
    $zipPath = Join-Path $caseRoot "kanata.zip"
    $sourceDir = Join-Path $caseRoot "source"
    New-Item -ItemType Directory -Path $sourceDir | Out-Null

    $ttyPath = Join-Path $sourceDir "kanata_windows_tty_winIOv2_x64.exe"
    $guiPath = Join-Path $sourceDir "kanata_windows_gui_winIOv2_x64.exe"
    $cmdPath = Join-Path $sourceDir "kanata_windows_tty_winIOv2_cmd_allowed_x64.exe"
    [System.IO.File]::WriteAllText($ttyPath, "tty")
    [System.IO.File]::WriteAllText($guiPath, "gui")
    [System.IO.File]::WriteAllText($cmdPath, "cmd")
    [System.IO.Compression.ZipFile]::CreateFromDirectory($sourceDir, $zipPath)
  }

  It "extracts only the requested executable directly to the destination" {
    $destination = Join-Path $caseRoot "installed\kanata.exe"
    $zipSha256 = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash
    $payload = Get-VerifiedKanataExecutablePayload `
      -ZipPath $zipPath `
      -ExpectedSha256 $zipSha256 `
      -Driver "winio" `
      -Ui "tty" `
      -CmdAllowed $false

    $selected = Install-KanataExecutablePayload `
      -Payload $payload `
      -DestinationPath $destination

    Assert-Equal $selected "kanata_windows_tty_winIOv2_x64.exe"
    Assert-Equal (Get-Content -LiteralPath $destination -Raw) "tty"
    $installedFileCount = @(Get-ChildItem -LiteralPath (Split-Path $destination) -File).Count
    Assert-Equal $installedFileCount 1
  }

  It "rejects cmd-enabled binaries when CmdAllowed is false" {
    $destination = Join-Path $caseRoot "installed\kanata.exe"
    $cmdOnlyZip = Join-Path $caseRoot "cmd-only.zip"
    $cmdOnlyDir = Join-Path $caseRoot "cmd-only"
    New-Item -ItemType Directory -Path $cmdOnlyDir | Out-Null
    Copy-Item `
      -LiteralPath (Join-Path $sourceDir "kanata_windows_tty_winIOv2_cmd_allowed_x64.exe") `
      -Destination $cmdOnlyDir
    [System.IO.Compression.ZipFile]::CreateFromDirectory($cmdOnlyDir, $cmdOnlyZip)
    $cmdOnlySha256 = (Get-FileHash -LiteralPath $cmdOnlyZip -Algorithm SHA256).Hash

    Assert-Throws {
      Get-VerifiedKanataExecutablePayload `
        -ZipPath $cmdOnlyZip `
        -ExpectedSha256 $cmdOnlySha256 `
        -Driver "winio" `
        -Ui "tty" `
        -CmdAllowed $false
    }

    Assert-Equal (Test-Path -LiteralPath $destination) $false
  }

  It "rejects a ZIP that changes after its expected hash is captured" {
    Assert-Throws {
      Get-VerifiedKanataExecutablePayload `
        -ZipPath $zipPath `
        -ExpectedSha256 ("0" * 64) `
        -Driver "winio" `
        -Ui "tty" `
        -CmdAllowed $false
    }
  }

  It "replaces an existing executable without leaving extra files" {
    $destination = Join-Path $caseRoot "installed\kanata.exe"
    New-Item -ItemType Directory -Path (Split-Path $destination) | Out-Null
    [System.IO.File]::WriteAllText($destination, "old")
    $payload = [pscustomobject]@{
      Name = "kanata_windows_tty_winIOv2_x64.exe"
      Bytes = [System.Text.Encoding]::UTF8.GetBytes("new")
    }

    Install-KanataExecutablePayload -Payload $payload -DestinationPath $destination | Out-Null

    Assert-Equal (Get-Content -LiteralPath $destination -Raw) "new"
    $transactionFiles = @(Get-ChildItem -LiteralPath (Split-Path $destination) -File |
      Where-Object { $_.Name -ne "kanata.exe" })
    Assert-Equal $transactionFiles.Count 0
  }
}
}
