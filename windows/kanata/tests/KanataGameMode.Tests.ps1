Describe "Kanata game mode" {
BeforeAll {
  $modulePath = Join-Path $PSScriptRoot "..\KanataGameMode.psm1"
  Import-Module $modulePath -Force

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
}

Context "Get-KanataSteamCommonPaths" {
  It "discovers the primary and additional Steam libraries" {
    $steamPath = Join-Path $TestDrive "Primary Steam"
    $additionalPath = Join-Path $TestDrive "Additional Steam"
    $libraryFile = Join-Path $steamPath "steamapps\libraryfolders.vdf"
    New-Item -ItemType Directory -Path (Split-Path $libraryFile) | Out-Null
    New-Item `
      -ItemType Directory `
      -Path (Join-Path $steamPath "steamapps\common") | Out-Null
    New-Item `
      -ItemType Directory `
      -Path (Join-Path $additionalPath "steamapps\common") `
      -Force | Out-Null
    $escapedAdditionalPath = $additionalPath.Replace("\", "\\")
    [System.IO.File]::WriteAllText(
      $libraryFile,
      (
        '"libraryfolders"' + "`n{" + "`n" +
        '  "0" { "path" "' + $steamPath.Replace("\", "\\") + '" }' + "`n" +
        '  "1" { "path" "' + $escapedAdditionalPath + '" }' + "`n" +
        "}"
      )
    )

    $paths = @(
      Get-KanataSteamCommonPaths `
        -SteamPath $steamPath `
        -LibraryFoldersPath $libraryFile
    )

    Assert-Equal $paths.Count 2
    Assert-Equal $paths[0] (Join-Path $steamPath "steamapps\common")
    Assert-Equal $paths[1] (Join-Path $additionalPath "steamapps\common")
  }

  It "rejects an unexpectedly large Steam library file" {
    $steamPath = Join-Path $TestDrive "Steam"
    $libraryFile = Join-Path $steamPath "steamapps\libraryfolders.vdf"
    New-Item -ItemType Directory -Path (Split-Path $libraryFile) | Out-Null
    $stream = [System.IO.File]::Create($libraryFile)
    try {
      $stream.SetLength(1MB + 1)
    } finally {
      $stream.Dispose()
    }

    Assert-Throws {
      Get-KanataSteamCommonPaths `
        -SteamPath $steamPath `
        -LibraryFoldersPath $libraryFile
    }
  }
}

Context "Get-KanataGameModeSettings" {
  It "contains the requested Steam fallbacks and Valorant executables" {
    $settings = Get-KanataGameModeSettings `
      -Path (Join-Path $PSScriptRoot "..\game-mode.json")
    $expected = @(
      "StreetFighter6.exe",
      "FactoryGameSteam.exe",
      "FactoryGameSteam-Win64-Shipping.exe",
      "ShadowverseWB.exe",
      "AimLab_tb.exe",
      "VALORANT.exe",
      "VALORANT-Win64-Shipping.exe"
    )

    Assert-Equal (
      $settings.HardOffExecutables -join "|"
    ) ($expected -join "|")
    Assert-Equal $settings.PollIntervalMilliseconds 250
    Assert-Equal $settings.ResumeDelayMilliseconds 750
    Assert-Equal $settings.DisableOnlyWhenGameForeground $true
    Assert-Equal $settings.SteamIgnoreExecutables.Count 10
  }

  It "loads a valid settings file" {
    $settingsPath = Join-Path $TestDrive "game-mode.json"
    [System.IO.File]::WriteAllText(
      $settingsPath,
      @'
{
  "poll_interval_ms": 1000,
  "resume_delay_ms": 750,
  "disable_for_steam_games": true,
  "disable_only_when_game_foreground": true,
  "steam_ignore_executables": [
    "wallpaper32.exe",
    "wallpaper64.exe"
  ],
  "hard_off_executables": [
    "StreetFighter6.exe",
    "FactoryGameSteam.exe",
    "FactoryGameSteam-Win64-Shipping.exe",
    "ShadowverseWB.exe",
    "AimLab_tb.exe",
    "VALORANT.exe",
    "VALORANT-Win64-Shipping.exe"
  ]
}
'@
    )

    $settings = Get-KanataGameModeSettings -Path $settingsPath

    Assert-Equal $settings.PollIntervalMilliseconds 1000
    Assert-Equal $settings.ResumeDelayMilliseconds 750
    Assert-Equal $settings.DisableForSteamGames $true
    Assert-Equal $settings.DisableOnlyWhenGameForeground $true
    Assert-Equal $settings.SteamIgnoreExecutables.Count 2
    Assert-Equal $settings.HardOffExecutables.Count 7
  }

  It "accepts empty executable lists" {
    $settingsPath = Join-Path $TestDrive "empty-lists.json"
    [System.IO.File]::WriteAllText(
      $settingsPath,
      @'
{
  "poll_interval_ms": 1000,
  "resume_delay_ms": 750,
  "disable_for_steam_games": true,
  "disable_only_when_game_foreground": true,
  "steam_ignore_executables": [],
  "hard_off_executables": []
}
'@
    )

    $settings = Get-KanataGameModeSettings -Path $settingsPath

    Assert-Equal $settings.SteamIgnoreExecutables.Count 0
    Assert-Equal $settings.HardOffExecutables.Count 0
  }

  It "rejects executable entries containing a path" {
    $settingsPath = Join-Path $TestDrive "invalid-game-mode.json"
    [System.IO.File]::WriteAllText(
      $settingsPath,
      @'
{
  "poll_interval_ms": 1000,
  "resume_delay_ms": 750,
  "disable_for_steam_games": true,
  "disable_only_when_game_foreground": true,
  "steam_ignore_executables": [],
  "hard_off_executables": ["C:\\Games\\game.exe"]
}
'@
    )

    Assert-Throws {
      Get-KanataGameModeSettings -Path $settingsPath
    }
  }
}

Context "Test-KanataGameProcess" {
  BeforeAll {
    $steamCommon = "C:\Program Files (x86)\Steam\steamapps\common"
    $hardOff = @(
      "StreetFighter6.exe",
      "FactoryGameSteam.exe",
      "FactoryGameSteam-Win64-Shipping.exe",
      "ShadowverseWB.exe",
      "AimLab_tb.exe",
      "VALORANT.exe",
      "VALORANT-Win64-Shipping.exe"
    )
    $steamIgnore = @(
      "applicationwallpaperinject32.exe",
      "applicationwallpaperinject64.exe",
      "edgewallpaper64.exe",
      "wallpaper32.exe",
      "wallpaper64.exe",
      "wallpaperservice32.exe",
      "wallpaperservice64.exe",
      "wallpaperui.exe",
      "webwallpaper32.exe",
      "webwallpaper64.exe"
    )
  }

  It "matches any executable inside a Steam common directory" {
    $isGame = Test-KanataGameProcess `
      -ProcessName "StreetFighter6" `
      -ProcessPath (
        "$steamCommon\Street Fighter 6\StreetFighter6.exe"
      ) `
      -SteamCommonPaths @($steamCommon) `
      -DisableForSteamGames $true `
      -SteamIgnoreExecutables $steamIgnore `
      -HardOffExecutables $hardOff

    Assert-Equal $isGame $true
  }

  It "does not accept a Steam path prefix collision" {
    $isGame = Test-KanataGameProcess `
      -ProcessName "unrelated" `
      -ProcessPath (
        "C:\Program Files (x86)\Steam\steamapps\common-old\unrelated.exe"
      ) `
      -SteamCommonPaths @($steamCommon) `
      -DisableForSteamGames $true `
      -SteamIgnoreExecutables $steamIgnore `
      -HardOffExecutables $hardOff

    Assert-Equal $isGame $false
  }

  It "matches configured non-Steam games without a readable path" {
    $isGame = Test-KanataGameProcess `
      -ProcessName "VALORANT-Win64-Shipping" `
      -ProcessPath "" `
      -SteamCommonPaths @($steamCommon) `
      -DisableForSteamGames $true `
      -SteamIgnoreExecutables $steamIgnore `
      -HardOffExecutables $hardOff

    Assert-Equal $isGame $true
  }

  It "matches a configured Steam fallback without a readable path" {
    $isGame = Test-KanataGameProcess `
      -ProcessName "FactoryGameSteam-Win64-Shipping" `
      -ProcessPath "" `
      -SteamCommonPaths @($steamCommon) `
      -DisableForSteamGames $true `
      -SteamIgnoreExecutables $steamIgnore `
      -HardOffExecutables $hardOff

    Assert-Equal $isGame $true
  }

  It "ignores ordinary non-game processes" {
    $isGame = Test-KanataGameProcess `
      -ProcessName "WindowsTerminal" `
      -ProcessPath "C:\Program Files\WindowsApps\WindowsTerminal.exe" `
      -SteamCommonPaths @($steamCommon) `
      -DisableForSteamGames $true `
      -SteamIgnoreExecutables $steamIgnore `
      -HardOffExecutables $hardOff

    Assert-Equal $isGame $false
  }

  It "ignores configured Steam utility executables" {
    $isGame = Test-KanataGameProcess `
      -ProcessName "wallpaper64" `
      -ProcessPath "$steamCommon\wallpaper_engine\wallpaper64.exe" `
      -SteamCommonPaths @($steamCommon) `
      -DisableForSteamGames $true `
      -SteamIgnoreExecutables $steamIgnore `
      -HardOffExecutables $hardOff

    Assert-Equal $isGame $false
  }
}

Context "Get-KanataForegroundGameProcesses" {
  It "returns the foreground game only" {
    Mock Get-KanataForegroundProcess {
      [pscustomobject]@{
        ProcessName = "StreetFighter6"
        Path = "C:\Games\StreetFighter6.exe"
      }
    } -ModuleName KanataGameMode
    $settings = [pscustomobject]@{
      DisableForSteamGames = $true
      SteamIgnoreExecutables = @()
      HardOffExecutables = @("StreetFighter6.exe")
    }

    $games = @(
      Get-KanataForegroundGameProcesses `
        -Settings $settings `
        -SteamCommonPaths @()
    )

    Assert-Equal $games.Count 1
    Assert-Equal $games[0].ProcessName "StreetFighter6"
  }

  It "ignores a foreground non-game process" {
    Mock Get-KanataForegroundProcess {
      [pscustomobject]@{
        ProcessName = "WindowsTerminal"
        Path = "C:\Windows\System32\WindowsTerminal.exe"
      }
    } -ModuleName KanataGameMode
    $settings = [pscustomobject]@{
      DisableForSteamGames = $true
      SteamIgnoreExecutables = @()
      HardOffExecutables = @("StreetFighter6.exe")
    }

    $games = @(
      Get-KanataForegroundGameProcesses `
        -Settings $settings `
        -SteamCommonPaths @()
    )

    Assert-Equal $games.Count 0
  }
}

Context "Get-KanataGameModeDecision" {
  BeforeAll {
    $now = [datetime]::Parse("2026-07-31T00:00:00Z").ToUniversalTime()
  }

  It "waits for keyboard release before stopping Kanata" {
    $held = Get-KanataGameModeDecision `
      -GameActive $true `
      -KanataRunning $true `
      -KeyboardKeyPressed $true `
      -ResumeKanataAt ([datetime]::MinValue) `
      -Now $now `
      -ResumeDelayMilliseconds 750
    $released = Get-KanataGameModeDecision `
      -GameActive $true `
      -KanataRunning $true `
      -KeyboardKeyPressed $false `
      -ResumeKanataAt ([datetime]::MinValue) `
      -Now $now `
      -ResumeDelayMilliseconds 750

    Assert-Equal $held.Action "None"
    Assert-Equal $released.Action "Stop"
  }

  It "starts Kanata only after the resume delay" {
    $initial = Get-KanataGameModeDecision `
      -GameActive $false `
      -KanataRunning $false `
      -KeyboardKeyPressed $false `
      -ResumeKanataAt ([datetime]::MinValue) `
      -Now $now `
      -ResumeDelayMilliseconds 750
    $early = Get-KanataGameModeDecision `
      -GameActive $false `
      -KanataRunning $false `
      -KeyboardKeyPressed $false `
      -ResumeKanataAt $initial.ResumeKanataAt `
      -Now $now.AddMilliseconds(749) `
      -ResumeDelayMilliseconds 750
    $ready = Get-KanataGameModeDecision `
      -GameActive $false `
      -KanataRunning $false `
      -KeyboardKeyPressed $false `
      -ResumeKanataAt $initial.ResumeKanataAt `
      -Now $now.AddMilliseconds(750) `
      -ResumeDelayMilliseconds 750

    Assert-Equal $initial.Action "None"
    Assert-Equal $initial.ResumeKanataAt $now.AddMilliseconds(750)
    Assert-Equal $early.Action "None"
    Assert-Equal $ready.Action "Start"
  }

  It "cancels a pending resume when game focus returns" {
    $decision = Get-KanataGameModeDecision `
      -GameActive $true `
      -KanataRunning $false `
      -KeyboardKeyPressed $false `
      -ResumeKanataAt $now.AddMilliseconds(750) `
      -Now $now.AddMilliseconds(200) `
      -ResumeDelayMilliseconds 750

    Assert-Equal $decision.Action "None"
    Assert-Equal $decision.ResumeKanataAt ([datetime]::MinValue)
  }
}

Context "Run entry ownership" {
  It "recognizes only exact managed values" {
    $expected = @('"C:\Tools\powershell.exe" -File "game-mode.ps1"')

    Assert-Equal (
      Test-KanataOwnedRunValue -Value $expected[0] -ExpectedValues $expected
    ) $true
    Assert-Equal (
      Test-KanataOwnedRunValue `
        -Value '"C:\Other\program.exe"' `
        -ExpectedValues $expected
    ) $false
  }
}

Context "Watcher lifecycle implementation" {
  It "waits for the watcher to acquire its mutex" {
    $moduleSource = Get-Content `
      -LiteralPath (Join-Path $PSScriptRoot "..\KanataGameMode.psm1") `
      -Raw

    Assert-Equal $moduleSource.Contains("-PassThru") $true
    Assert-Equal $moduleSource.Contains(
      "Timed out waiting for the Kanata game mode watcher to start."
    ) $true
  }

  It "deduplicates logs before adding a timestamp" {
    $watcherSource = Get-Content `
      -LiteralPath (Join-Path $PSScriptRoot "..\game-mode.ps1") `
      -Raw

    Assert-Equal $watcherSource.Contains(
      '$ErrorMessage -eq $script:lastLogMessage'
    ) $true
    Assert-Equal $watcherSource.Contains(
      'Write-GameModeLog -ErrorMessage $_.Exception.Message'
    ) $true
  }

  It "keeps foreground game results as an array" {
    $watcherSource = Get-Content `
      -LiteralPath (Join-Path $PSScriptRoot "..\game-mode.ps1") `
      -Raw

    Assert-Equal $watcherSource.Contains('$games = @(') $true
  }

  It "waits for keyboard release before stopping Kanata" {
    $watcherSource = Get-Content `
      -LiteralPath (Join-Path $PSScriptRoot "..\game-mode.ps1") `
      -Raw

    Assert-Equal $watcherSource.Contains(
      '-not (Test-KanataAnyKeyboardKeyPressed)'
    ) $true
  }

  It "restarts Kanata without its default startup delay" {
    $moduleSource = Get-Content `
      -LiteralPath (Join-Path $PSScriptRoot "..\KanataGameMode.psm1") `
      -Raw

    Assert-Equal $moduleSource.Contains('--nodelay --cfg') $true
  }
}
}
