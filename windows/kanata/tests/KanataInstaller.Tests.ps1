Describe "Kanata installer" {
BeforeAll {
  $modulePath = Join-Path $PSScriptRoot "..\KanataInstaller.psm1"
  Import-Module $modulePath -Force
  $defenderModulePath = Join-Path $PSScriptRoot "..\KanataDefender.psm1"
  Import-Module $defenderModulePath -Force
  $surfaceImeModulePath = Join-Path $PSScriptRoot "..\KanataSurfaceIme.psm1"
  Import-Module $surfaceImeModulePath -Force
  $powerToysModulePath = Join-Path $PSScriptRoot "..\KanataPowerToys.psm1"
  Import-Module $powerToysModulePath -Force

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

Context "Surface IME Scancode Map" {
  BeforeAll {
    $capsToControl = [byte[]]@(
      0, 0, 0, 0, 0, 0, 0, 0,
      2, 0, 0, 0,
      0x1D, 0, 0x3A, 0,
      0, 0, 0, 0
    )
  }

  It "preserves existing mappings while adding the supported Surface key" {
    $update = Get-KanataSurfaceImeScancodeMapUpdate `
      -Action Add `
      -CurrentData $capsToControl
    $mappings = @(ConvertFrom-KanataScancodeMap -Data $update.DesiredData)

    Assert-Equal $update.Changed $true
    Assert-Equal $mappings.Count 2
    Assert-Equal $mappings[0].Source 0x003A
    Assert-Equal $mappings[0].Target 0x001D
    Assert-Equal $mappings[1].Source 0x0079
    Assert-Equal $mappings[1].Target 0x0066
  }

  It "removes only the managed Surface mappings" {
    $added = Get-KanataSurfaceImeScancodeMapUpdate `
      -Action Add `
      -CurrentData $capsToControl
    $removed = Get-KanataSurfaceImeScancodeMapUpdate `
      -Action Remove `
      -CurrentData $added.DesiredData

    Assert-Equal (
      [Convert]::ToBase64String($removed.DesiredData)
    ) ([Convert]::ToBase64String($capsToControl))
  }

  It "removes the ineffective legacy IME Off mapping during migration" {
    $legacy = ConvertTo-KanataScancodeMap -Mappings @(
      [pscustomobject]@{ Source = 0xE0F1; Target = 0x0064 }
    )
    $update = Get-KanataSurfaceImeScancodeMapUpdate `
      -Action Add `
      -CurrentData $legacy
    $mappings = @(ConvertFrom-KanataScancodeMap -Data $update.DesiredData)

    Assert-Equal $mappings.Count 1
    Assert-Equal $mappings[0].Source 0x0079
    Assert-Equal $mappings[0].Target 0x0066
  }

  It "rejects an existing mapping for a managed source" {
    $conflict = ConvertTo-KanataScancodeMap -Mappings @(
      [pscustomobject]@{ Source = 0x0079; Target = 0x0042 }
    )

    Assert-Throws {
      Get-KanataSurfaceImeScancodeMapUpdate `
        -Action Add `
        -CurrentData $conflict
    }
  }
}

Context "Surface IME PowerToys mapping" {
  BeforeAll {
    $emptyProfile = @{
      remapKeys = @{ inProcess = @() }
      remapKeysToText = @{ inProcess = @() }
      remapShortcuts = @{ global = @(); appSpecific = @() }
      remapShortcutsToText = @{ global = @(); appSpecific = @() }
    } | ConvertTo-Json -Depth 10 -Compress
  }

  It "adds VK_IME_OFF to F13 while preserving the profile" {
    $update = Get-KanataImeOffPowerToysProfileUpdate `
      -Action Add `
      -ProfileJson $emptyProfile
    $profile = $update.DesiredJson | ConvertFrom-Json

    Assert-Equal $update.Changed $true
    Assert-Equal @($profile.remapKeys.inProcess).Count 1
    Assert-Equal $profile.remapKeys.inProcess[0].originalKeys "26"
    Assert-Equal $profile.remapKeys.inProcess[0].newRemapKeys "124"
  }

  It "is idempotent and removes only its exact mapping" {
    $added = Get-KanataImeOffPowerToysProfileUpdate `
      -Action Add `
      -ProfileJson $emptyProfile
    $same = Get-KanataImeOffPowerToysProfileUpdate `
      -Action Add `
      -ProfileJson $added.DesiredJson
    $removed = Get-KanataImeOffPowerToysProfileUpdate `
      -Action Remove `
      -ProfileJson $added.DesiredJson

    Assert-Equal $same.Changed $false
    Assert-Equal $removed.Changed $true
    Assert-Equal @(
      ($removed.DesiredJson | ConvertFrom-Json).remapKeys.inProcess
    ).Count 0
  }

  It "rejects a conflicting IME Off remap" {
    $profile = $emptyProfile | ConvertFrom-Json
    $profile.remapKeys.inProcess = @(
      [pscustomobject]@{ originalKeys = "26"; newRemapKeys = "65" }
    )

    Assert-Throws {
      Get-KanataImeOffPowerToysProfileUpdate `
        -Action Add `
        -ProfileJson ($profile | ConvertTo-Json -Depth 10 -Compress)
    }
  }
}

Context "Keyboard modifier configuration" {
  It "exposes the Surface IME Off action through a TCP virtual key" {
    $configPath = Join-Path $PSScriptRoot "..\kanata.kbd"
    $config = Get-Content -LiteralPath $configPath -Raw

    Assert-Equal ($config -match (
      "(?ms)^\(defvirtualkeys\s+" +
      ".*surface-imeoff\s+" +
      [regex]::Escape(
        "(tap-hold-press 120 180 f13 (layer-while-held wm))"
      ) +
      ".*^\)\s*$"
    )) $true
  }

  It "disables only the Space layer while game mode is active" {
    $configPath = Join-Path $PSScriptRoot "..\kanata.kbd"
    $config = Get-Content -LiteralPath $configPath -Raw

    Assert-Equal ($config -match "(?m)^\s*game-mode\s+nop0\s*$") $true
    Assert-Equal $config.Contains("((input virtual game-mode)) spc break") $true
    Assert-Equal $config.Contains(
      "() (tap-hold-press `$tap `$hold spc (layer-while-held nav)) break"
    ) $true
  }

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

  It "keeps Win and Alt native and uses physical F13 and F15 as mods" {
    $configPath = Join-Path $PSScriptRoot "..\kanata.kbd"
    $config = Get-Content -LiteralPath $configPath -Raw

    foreach ($alias in @(
      "imeoffmod (tap-hold-press 120 180 f13 (layer-while-held wm))",
      "imeonmod (tap-hold-press 120 180 f15 (layer-while-held wm))"
    )) {
      Assert-Equal $config.Contains($alias) $true
    }
    Assert-Equal ($config -match "(?m)^\s*safetab\s+") $false

    $activeConfig = [regex]::Replace($config, "(?m);;.*$", "")
    $defsrc = [regex]::Match(
      $activeConfig,
      "(?ms)^\(defsrc\s+(.*?)^\)\s*$"
    )
    Assert-Equal $defsrc.Success $true
    $sourceTokens = @($defsrc.Groups[1].Value -split "\s+" | Where-Object { $_ })
    Assert-Equal $sourceTokens.Count 67
    Assert-Equal ($sourceTokens[-2..-1] -join "|") "f13|f15"

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
      Assert-Equal $layerTokens[14] "_"
      Assert-Equal $layerTokens[55] "_"
      Assert-Equal $layerTokens[56] "_"
      Assert-Equal $layerTokens[58] "_"
      Assert-Equal $layerTokens[65] "@imeoffmod"
      Assert-Equal $layerTokens[66] "@imeonmod"
    }
  }

  It "emits the GlazeWM and retained Windows shortcuts from the private mods" {
    $configPath = Join-Path $PSScriptRoot "..\kanata.kbd"
    $config = Get-Content -LiteralPath $configPath -Raw
    $activeConfig = [regex]::Replace($config, "(?m);;.*$", "")

    Assert-Equal ($activeConfig -match "(?m)^\(deflayer\s+wm\b") $true
    Assert-Equal ($activeConfig -match "(?m)^\(deflayer\s+desktop\b") $false
    foreach ($binding in @(
      "f16", "f17", "f18", "f19", "f20", "f21", "f22", "f23", "f24",
      "C-A-f12", "A-tab", "A-spc"
    )) {
      $bindingPattern = "(?i)(?:^|[\s(])" +
        [regex]::Escape($binding) +
        "(?=$|[\s)])"
      Assert-Equal ($activeConfig -match $bindingPattern) $true
    }

    $wmLayer = [regex]::Match(
      $activeConfig,
      "(?ms)^\(deflayer\s+wm\s+(.*?)^\)\s*$"
    )
    Assert-Equal $wmLayer.Success $true
    $tokens = @($wmLayer.Groups[1].Value -split "\s+" | Where-Object { $_ })
    Assert-Equal $tokens.Count 67
    Assert-Equal $tokens[29] "@wmprofileall"
    Assert-Equal $tokens[48] "C-A-f12"
    Assert-Equal ($activeConfig -match "(?i)\bwindowstate\b") $false
    Assert-Equal ($activeConfig -match "(?i)(?<!\S)M-(?:down|up)(?!\S)") $false
  }

  It "allows repeated move keys while either physical Ctrl remains held" {
    $configPath = Join-Path $PSScriptRoot "..\kanata.kbd"
    $config = Get-Content -LiteralPath $configPath -Raw
    $moveAliases = [ordered]@{
      wmh = [pscustomobject]@{ Move = "f20"; Focus = "f16" }
      wmj = [pscustomobject]@{ Move = "f21"; Focus = "f17" }
      wmk = [pscustomobject]@{ Move = "f22"; Focus = "f18" }
      wml = [pscustomobject]@{ Move = "f23"; Focus = "f19" }
    }

    foreach ($entry in $moveAliases.GetEnumerator()) {
      $expected = (
        "$($entry.Key) (switch " +
        "((or (input real lctl) (input real rctl))) " +
        "(unmod (lctl rctl) $($entry.Value.Move)) break " +
        "() $($entry.Value.Focus) break)"
      )
      Assert-Equal $config.Contains($expected) $true
    }
  }

  It "keeps monitor navigation from moving whole workspaces" {
    $configPath = Join-Path $PSScriptRoot "..\kanata.kbd"
    $config = Get-Content -LiteralPath $configPath -Raw

    Assert-Equal $config.Contains("wmcomma C-A-,") $true
    Assert-Equal $config.Contains("wmperiod C-A-.") $true
    Assert-Equal ($config -match "(?m)^\s*wmcomma\s+\(switch\b") $false
    Assert-Equal ($config -match "(?m)^\s*wmperiod\s+\(switch\b") $false
    Assert-Equal ($config -match "(?i)C-A-S-[,.]") $false
  }

  It "emits monitor profile shortcuts only while physical Shift is held" {
    $configPath = Join-Path $PSScriptRoot "..\kanata.kbd"
    $config = Get-Content -LiteralPath $configPath -Raw
    $activeConfig = [regex]::Replace($config, "(?m);;.*$", "")
    $aliases = [ordered]@{
      wmprofileall = "S-f16"
      wmprofileleftcenter = "S-f17"
      wmprofileright = "S-f18"
    }

    foreach ($entry in $aliases.GetEnumerator()) {
      $expected = (
        "$($entry.Key) (switch " +
        "((or (input real lsft) (input real rsft))) " +
        "$($entry.Value) break () nop0 break)"
      )
      Assert-Equal $config.Contains($expected) $true
    }

    $wmLayer = [regex]::Match(
      $activeConfig,
      "(?ms)^\(deflayer\s+wm\s+(.*?)^\)\s*$"
    )
    Assert-Equal $wmLayer.Success $true
    $tokens = @($wmLayer.Groups[1].Value -split "\s+" | Where-Object { $_ })
    Assert-Equal $tokens[18] "@wmprofileright"
    Assert-Equal $tokens[29] "@wmprofileall"
    Assert-Equal $tokens[44] "@wmprofileleftcenter"
  }

  It "keeps the F13 and F15 shortcut layer available during games" {
    $configPath = Join-Path $PSScriptRoot "..\kanata.kbd"
    $config = Get-Content -LiteralPath $configPath -Raw

    Assert-Equal $config.Contains(
      "imeoffmod (tap-hold-press 120 180 f13 (layer-while-held wm))"
    ) $true
    Assert-Equal $config.Contains(
      "imeonmod (tap-hold-press 120 180 f15 (layer-while-held wm))"
    ) $true
    Assert-Equal ($config -match "(?m)^\(deflayer\s+wm\b") $true
    Assert-Equal $config.Contains("C-A-f12") $true
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
    Assert-Equal $installScript.Contains("Add-KanataSurfaceImeScancodeMap") $true
    Assert-Equal $installScript.Contains("Add-KanataImeOffPowerToysMapping") $true
    Assert-Equal $installScript.Contains(
      "surface_ime_scancode_map_added"
    ) $true
    Assert-Equal $installScript.Contains(
      "ime_off_powertoys_mapping_added"
    ) $true
    $watcherStart = $installScript.IndexOf(
      "Start-KanataGameModeWatcher -InstallDir `$InstallDir"
    )
    $powerToysRestart = $installScript.IndexOf(
      "Restart-KanataPowerToys"
    )
    Assert-Equal ($watcherStart -ge 0) $true
    Assert-Equal ($powerToysRestart -gt $watcherStart) $true
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
    Assert-Equal $updateScript.Contains(
      '$legacyManagedFiles = @("kanata-game.kbd")'
    ) $true
    Assert-Equal $updateScript.Contains(
      "Remove-Item -LiteralPath `$legacyPath -Force"
    ) $true
  }

  It "stops and unregisters the watcher during uninstall" {
    Assert-Equal $uninstallScript.Contains("Stop-KanataGameModeWatcher") $true
    Assert-Equal $uninstallScript.Contains("Test-KanataOwnedRunValue") $true
    Assert-Equal $uninstallScript.Contains(
      "Remove-KanataSurfaceImeScancodeMap"
    ) $true
    Assert-Equal $uninstallScript.Contains(
      "Remove-KanataImeOffPowerToysMapping"
    ) $true
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
