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
  It "contains the requested game executable fallbacks" {
    $settings = Get-KanataGameModeSettings `
      -Path (Join-Path $PSScriptRoot "..\game-mode.json")
    $expected = @(
      "StreetFighter6.exe",
      "FactoryGameSteam.exe",
      "FactoryGameSteam-Win64-Shipping.exe",
      "ShadowverseWB.exe",
      "AimLab_tb.exe",
      "VALORANT.exe",
      "VALORANT-Win64-Shipping.exe",
      "GenshinImpact.exe",
      "StarRail.exe",
      "EscapeFromTarkov.exe",
      "EscapeFromTarkov_BE.exe"
    )

    Assert-Equal (
      $settings.HardOffExecutables -join "|"
    ) ($expected -join "|")
    Assert-Equal $settings.PollIntervalMilliseconds 250
    Assert-Equal $settings.ResumeDelayMilliseconds 750
    Assert-Equal $settings.DisableOnlyWhenGameForeground $true
    Assert-Equal $settings.SteamIgnoreExecutables.Count 10
    Assert-Equal (
      $settings.SteamIgnoreDirectories -join "|"
    ) "wallpaper_engine"
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
  "steam_ignore_directories": ["wallpaper_engine"],
  "hard_off_executables": [
    "StreetFighter6.exe",
    "FactoryGameSteam.exe",
    "FactoryGameSteam-Win64-Shipping.exe",
    "ShadowverseWB.exe",
    "AimLab_tb.exe",
    "VALORANT.exe",
    "VALORANT-Win64-Shipping.exe",
    "GenshinImpact.exe",
    "StarRail.exe",
    "EscapeFromTarkov.exe",
    "EscapeFromTarkov_BE.exe"
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
    Assert-Equal $settings.SteamIgnoreDirectories.Count 1
    Assert-Equal $settings.HardOffExecutables.Count 11
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
  "steam_ignore_directories": [],
  "hard_off_executables": []
}
'@
    )

    $settings = Get-KanataGameModeSettings -Path $settingsPath

    Assert-Equal $settings.SteamIgnoreExecutables.Count 0
    Assert-Equal $settings.SteamIgnoreDirectories.Count 0
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
  "steam_ignore_directories": [],
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
      "VALORANT-Win64-Shipping.exe",
      "GenshinImpact.exe",
      "StarRail.exe",
      "EscapeFromTarkov.exe",
      "EscapeFromTarkov_BE.exe"
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

  It "ignores every process inside a configured Steam utility directory" {
    $isGame = Test-KanataGameProcess `
      -ProcessName "winrtutil64" `
      -ProcessPath "$steamCommon\wallpaper_engine\bin\winrtutil64.exe" `
      -SteamCommonPaths @($steamCommon) `
      -DisableForSteamGames $true `
      -SteamIgnoreExecutables $steamIgnore `
      -SteamIgnoreDirectories @("wallpaper_engine") `
      -HardOffExecutables $hardOff

    Assert-Equal $isGame $false
  }

  It "does not classify the Steam client as a game" {
    $isGame = Test-KanataGameProcess `
      -ProcessName "steam" `
      -ProcessPath "C:\Program Files (x86)\Steam\steam.exe" `
      -SteamCommonPaths @($steamCommon) `
      -DisableForSteamGames $true `
      -SteamIgnoreExecutables $steamIgnore `
      -SteamIgnoreDirectories @("wallpaper_engine") `
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
      SteamIgnoreDirectories = @()
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
      SteamIgnoreDirectories = @()
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

  It "waits for keyboard release before enabling game mode" {
    $held = Get-KanataGameModeDecision `
      -GameActive $true `
      -GameModeEnabled $false `
      -KeyboardKeyPressed $true `
      -ResumeKanataAt ([datetime]::MinValue) `
      -Now $now `
      -ResumeDelayMilliseconds 750
    $released = Get-KanataGameModeDecision `
      -GameActive $true `
      -GameModeEnabled $false `
      -KeyboardKeyPressed $false `
      -ResumeKanataAt ([datetime]::MinValue) `
      -Now $now `
      -ResumeDelayMilliseconds 750

    Assert-Equal $held.Action "None"
    Assert-Equal $released.Action "EnableGameMode"
  }

  It "disables game mode only after the resume delay" {
    $initial = Get-KanataGameModeDecision `
      -GameActive $false `
      -GameModeEnabled $true `
      -KeyboardKeyPressed $false `
      -ResumeKanataAt ([datetime]::MinValue) `
      -Now $now `
      -ResumeDelayMilliseconds 750
    $early = Get-KanataGameModeDecision `
      -GameActive $false `
      -GameModeEnabled $true `
      -KeyboardKeyPressed $false `
      -ResumeKanataAt $initial.ResumeKanataAt `
      -Now $now.AddMilliseconds(749) `
      -ResumeDelayMilliseconds 750
    $ready = Get-KanataGameModeDecision `
      -GameActive $false `
      -GameModeEnabled $true `
      -KeyboardKeyPressed $false `
      -ResumeKanataAt $initial.ResumeKanataAt `
      -Now $now.AddMilliseconds(750) `
      -ResumeDelayMilliseconds 750

    Assert-Equal $initial.Action "None"
    Assert-Equal $initial.ResumeKanataAt $now.AddMilliseconds(750)
    Assert-Equal $early.Action "None"
    Assert-Equal $ready.Action "DisableGameMode"
  }

  It "keeps game mode enabled while a game remains active" {
    $decision = Get-KanataGameModeDecision `
      -GameActive $true `
      -GameModeEnabled $true `
      -KeyboardKeyPressed $false `
      -ResumeKanataAt ([datetime]::MinValue) `
      -Now $now `
      -ResumeDelayMilliseconds 750

    Assert-Equal $decision.Action "None"
    Assert-Equal $decision.ResumeKanataAt ([datetime]::MinValue)
  }

  It "cancels a pending resume when a game becomes active again" {
    $decision = Get-KanataGameModeDecision `
      -GameActive $true `
      -GameModeEnabled $true `
      -KeyboardKeyPressed $false `
      -ResumeKanataAt $now.AddMilliseconds(750) `
      -Now $now.AddMilliseconds(200) `
      -ResumeDelayMilliseconds 750

    Assert-Equal $decision.Action "None"
    Assert-Equal $decision.ResumeKanataAt ([datetime]::MinValue)
  }
}

Context "Set-KanataGameModeState" {
  BeforeAll {
    if (-not ("KanataTcpTestServer" -as [type])) {
      Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Net.Sockets;
using System.Text;
using System.Threading.Tasks;

public static class KanataTcpTestServer
{
    public static Task<string[]> Start(TcpListener listener)
    {
        return Task.Factory.StartNew(() =>
        {
            using (TcpClient client = listener.AcceptTcpClient())
            using (NetworkStream stream = client.GetStream())
            using (StreamReader reader = new StreamReader(stream, new UTF8Encoding(false)))
            using (StreamWriter writer = new StreamWriter(stream, new UTF8Encoding(false)))
            {
                writer.NewLine = "\n";
                writer.AutoFlush = true;
                writer.WriteLine("{\"LayerChange\":{\"new\":\"us\"}}");
                string[] messages = new string[3];
                messages[0] = reader.ReadLine();
                writer.WriteLine("{\"FakeKeyNames\":{\"names\":[\"game-mode\"]}}");
                messages[1] = reader.ReadLine();
                messages[2] = reader.ReadLine();
                writer.WriteLine("{\"FakeKeyNames\":{\"names\":[\"game-mode\"]}}");
                return messages;
            }
        });
    }
}
'@
    }
  }

  It "validates the endpoint and sends virtual key state changes as JSON" {
    foreach ($case in @(
      [pscustomobject]@{ Enabled = $true; Action = "Press" },
      [pscustomobject]@{ Enabled = $false; Action = "Release" }
    )) {
      $listener = New-Object `
        -TypeName System.Net.Sockets.TcpListener `
        -ArgumentList @([System.Net.IPAddress]::Loopback, 0)
      $listener.Start()
      $port = ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port
      $serverTask = [KanataTcpTestServer]::Start($listener)
      try {
        Set-KanataGameModeState `
          -Enabled $case.Enabled `
          -Port $port
        $messages = $serverTask.GetAwaiter().GetResult()
      } finally {
        $listener.Stop()
      }

      $request = $messages[0] | ConvertFrom-Json
      $action = $messages[1] | ConvertFrom-Json
      $barrier = $messages[2] | ConvertFrom-Json
      Assert-Equal ($null -ne $request.RequestFakeKeyNames) $true
      Assert-Equal $action.ActOnFakeKey.name "game-mode"
      Assert-Equal $action.ActOnFakeKey.action $case.Action
      Assert-Equal ($null -ne $barrier.RequestFakeKeyNames) $true
    }
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

  It "waits for keyboard release before changing the game virtual key" {
    $watcherSource = Get-Content `
      -LiteralPath (Join-Path $PSScriptRoot "..\game-mode.ps1") `
      -Raw

    Assert-Equal $watcherSource.Contains(
      '-not (Test-KanataAnyKeyboardKeyPressed)'
    ) $true
  }

  It "changes game mode through the Kanata TCP virtual key" {
    $watcherSource = Get-Content `
      -LiteralPath (Join-Path $PSScriptRoot "..\game-mode.ps1") `
      -Raw

    Assert-Equal $watcherSource.Contains("kanata-game.kbd") $false
    Assert-Equal $watcherSource.Contains('"EnableGameMode"') $true
    Assert-Equal $watcherSource.Contains('"DisableGameMode"') $true
    Assert-Equal $watcherSource.Contains("Set-KanataGameModeState") $true
  }

  It "starts one Kanata process with a loopback-only TCP server" {
    $moduleSource = Get-Content `
      -LiteralPath (Join-Path $PSScriptRoot "..\KanataGameMode.psm1") `
      -Raw

    Assert-Equal $moduleSource.Contains(
      '$script:KanataTcpAddress = "127.0.0.1"'
    ) $true
    Assert-Equal $moduleSource.Contains('$script:KanataTcpPort = 5829') $true
    Assert-Equal $moduleSource.Contains('"--nodelay --port $tcpEndpoint "') $true
    Assert-Equal $moduleSource.Contains(
      '"--cfg $(Get-KanataQuotedArgument -Value $ConfigPath)"'
    ) $true
  }

  It "fails closed when a managed Kanata process cannot be stopped" {
    Mock Get-KanataManagedProcesses {
      [pscustomobject]@{ Id = 4242 }
    } -ModuleName KanataGameMode
    Mock Stop-Process {
      throw [System.InvalidOperationException]::new("access denied")
    } -ModuleName KanataGameMode

    Assert-Throws {
      Stop-KanataManagedProcesses -ExePath "C:\Kanata\kanata.exe"
    }
  }

  It "does not restart Kanata when game focus changes" {
    $moduleSource = Get-Content `
      -LiteralPath (Join-Path $PSScriptRoot "..\KanataGameMode.psm1") `
      -Raw
    $watcherSource = Get-Content `
      -LiteralPath (Join-Path $PSScriptRoot "..\game-mode.ps1") `
      -Raw

    $focusSwitch = [regex]::Match(
      $watcherSource,
      '(?s)switch \(\$decision\.Action\) \{(.*?)\n\s{6}\}\n\s{4}\} catch'
    )
    Assert-Equal $focusSwitch.Success $true
    Assert-Equal $focusSwitch.Groups[1].Value.Contains(
      "Stop-KanataManagedProcesses"
    ) $false
    Assert-Equal $watcherSource.Contains("Start-KanataManagedProcess") $true
    Assert-Equal $watcherSource.Contains('$gameModeEnabled = $true') $true
  }

  It "restarts Kanata only when a new process has no valid TCP endpoint" {
    $watcherSource = Get-Content `
      -LiteralPath (Join-Path $PSScriptRoot "..\game-mode.ps1") `
      -Raw

    Assert-Equal $watcherSource.Contains(
      'if (Test-KanataAnyKeyboardKeyPressed) {'
    ) $true
    Assert-Equal ($watcherSource -match (
      '(?s)if \(\$managedKanataId -ne \$kanataProcess\.Id\).*?' +
      'Set-KanataGameModeState -Enabled \$false.*?catch \{.*?' +
      'Stop-KanataManagedProcesses -ExePath \$exePath'
    )) $true
  }

  It "marks the current process for recovery when a state change fails" {
    $watcherSource = Get-Content `
      -LiteralPath (Join-Path $PSScriptRoot "..\game-mode.ps1") `
      -Raw

    Assert-Equal ($watcherSource -match (
      '(?s)"EnableGameMode" \{.*?' +
      'Set-KanataGameModeState -Enabled \$true.*?catch \{.*?' +
      '\$managedKanataId = 0.*?\$gameModeEnabled = \$true'
    )) $true
    Assert-Equal ($watcherSource -match (
      '(?s)"DisableGameMode" \{.*?' +
      'Set-KanataGameModeState -Enabled \$false.*?catch \{.*?' +
      '\$managedKanataId = 0.*?\$gameModeEnabled = \$false'
    )) $true
  }

  It "rechecks the keyboard immediately before a recovery restart" {
    $watcherSource = Get-Content `
      -LiteralPath (Join-Path $PSScriptRoot "..\game-mode.ps1") `
      -Raw

    Assert-Equal ($watcherSource -match (
      '(?s)Set-KanataGameModeState -Enabled \$false.*?catch \{.*?' +
      'if \(Test-KanataAnyKeyboardKeyPressed\).*?' +
      'Stop-KanataManagedProcesses -ExePath \$exePath'
    )) $true
  }
}
}
