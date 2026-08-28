param(
  [string]$InstallDir = "$env:LOCALAPPDATA\kanata"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$modulePath = Join-Path $InstallDir "KanataGameMode.psm1"
Import-Module $modulePath -Force -ErrorAction Stop
$InstallDir = Resolve-KanataInstallDir -Path $InstallDir

$paths = Get-KanataWatcherPaths -InstallDir $InstallDir
$settings = Get-KanataGameModeSettings -Path $paths.Settings
$exePath = Join-Path $InstallDir "kanata.exe"
$configPath = Join-Path $InstallDir "kanata.kbd"
$mutex = New-Object `
  -TypeName System.Threading.Mutex `
  -ArgumentList @($false, "Local\DotfilesKanataGameMode")
$stopEvent = New-Object `
  -TypeName System.Threading.EventWaitHandle `
  -ArgumentList @(
    $false,
    [System.Threading.EventResetMode]::ManualReset,
    "Local\DotfilesKanataGameModeStop"
  )
$ownsMutex = $false
$script:lastLogMessage = ""
$script:lastLogAt = [datetime]::MinValue

function Write-GameModeLog {
  param([string]$ErrorMessage)

  try {
    $now = [datetime]::UtcNow
    if (
      $ErrorMessage -eq $script:lastLogMessage -and
      ($now - $script:lastLogAt).TotalSeconds -lt 30
    ) {
      return
    }
    if (
      (Test-Path -LiteralPath $paths.Log -PathType Leaf) -and
      (Get-Item -LiteralPath $paths.Log).Length -gt 256KB
    ) {
      Clear-Content -LiteralPath $paths.Log
    }
    $message = "$($now.ToString("o")) $ErrorMessage"
    Add-Content -LiteralPath $paths.Log -Value $message -Encoding UTF8
    $script:lastLogMessage = $ErrorMessage
    $script:lastLogAt = $now
  } catch {
    # A logging failure must not stop the watcher retry loop.
  }
}

try {
  try {
    $ownsMutex = $mutex.WaitOne(0, $false)
  } catch [System.Threading.AbandonedMutexException] {
    $ownsMutex = $true
  }
  if (-not $ownsMutex) {
    exit 0
  }

  $steamCommonPaths = @()
  $steamRefreshAt = [datetime]::MinValue
  $resumeKanataAt = [datetime]::MinValue
  $gameModeEnabled = $false
  $managedKanataId = 0

  while (-not $stopEvent.WaitOne(0)) {
    try {
      if (
        $settings.DisableForSteamGames -and
        [datetime]::UtcNow -ge $steamRefreshAt
      ) {
        $steamPath = ""
        try {
          $steamPath = [string](
            Get-ItemProperty `
              -LiteralPath "HKCU:\Software\Valve\Steam" `
              -ErrorAction Stop
          ).SteamPath
        } catch {
          $steamPath = ""
        }
        if (-not [string]::IsNullOrWhiteSpace($steamPath)) {
          try {
            $steamCommonPaths = @(
              Get-KanataSteamCommonPaths -SteamPath $steamPath
            )
          } catch {
            # Retain the last known-good Steam library list.
          }
        } else {
          $steamCommonPaths = @()
        }
        $steamRefreshAt = [datetime]::UtcNow.AddMinutes(1)
      }

      $games = @(
        if ($settings.DisableOnlyWhenGameForeground) {
          Get-KanataForegroundGameProcesses `
            -Settings $settings `
            -SteamCommonPaths $steamCommonPaths
        } else {
          Get-KanataRunningGameProcesses `
            -Settings $settings `
            -SteamCommonPaths $steamCommonPaths
        }
      )
      $kanataProcesses = @(
        Get-KanataManagedProcesses -ExePath $exePath
      )

      if ($kanataProcesses.Count -eq 0) {
        $kanataProcess = Start-KanataManagedProcess `
          -ExePath $exePath `
          -ConfigPath $configPath
        $kanataProcesses = @($kanataProcess)
      } elseif ($kanataProcesses.Count -gt 1) {
        throw "Multiple managed Kanata processes are running."
      }

      $kanataProcess = $kanataProcesses[0]
      if ($managedKanataId -ne $kanataProcess.Id) {
        if (Test-KanataAnyKeyboardKeyPressed) {
          [void]$stopEvent.WaitOne($settings.PollIntervalMilliseconds)
          continue
        }
        try {
          Set-KanataGameModeState -Enabled $false
        } catch {
          $endpointError = $_.Exception.Message
          $managedKanataId = 0
          if (Test-KanataAnyKeyboardKeyPressed) {
            throw (
              "Postponing Kanata TCP endpoint recovery until all keyboard " +
              "keys are released: $endpointError"
            )
          }
          Stop-KanataManagedProcesses -ExePath $exePath
          throw (
            "Restarting Kanata after TCP endpoint validation failed: " +
            $endpointError
          )
        }
        $managedKanataId = $kanataProcess.Id
        $gameModeEnabled = $false
        $resumeKanataAt = [datetime]::MinValue
      }

      $gameStateMismatch = (($games.Count -gt 0) -ne $gameModeEnabled)
      $keyboardKeyPressed = (
        $gameStateMismatch -and
        (Test-KanataAnyKeyboardKeyPressed)
      )
      $decision = Get-KanataGameModeDecision `
        -GameActive ($games.Count -gt 0) `
        -GameModeEnabled $gameModeEnabled `
        -KeyboardKeyPressed $keyboardKeyPressed `
        -ResumeKanataAt $resumeKanataAt `
        -Now ([datetime]::UtcNow) `
        -ResumeDelayMilliseconds $settings.ResumeDelayMilliseconds
      $resumeKanataAt = $decision.ResumeKanataAt

      switch ($decision.Action) {
        "EnableGameMode" {
          if (-not (Test-KanataAnyKeyboardKeyPressed)) {
            try {
              Set-KanataGameModeState -Enabled $true
            } catch {
              $managedKanataId = 0
              throw
            }
            $gameModeEnabled = $true
          }
        }
        "DisableGameMode" {
          if (-not (Test-KanataAnyKeyboardKeyPressed)) {
            try {
              Set-KanataGameModeState -Enabled $false
            } catch {
              $managedKanataId = 0
              throw
            }
            $gameModeEnabled = $false
          }
        }
      }
    } catch {
      Write-GameModeLog -ErrorMessage $_.Exception.Message
    }

    [void]$stopEvent.WaitOne($settings.PollIntervalMilliseconds)
  }
} finally {
  if ($ownsMutex) {
    $mutex.ReleaseMutex()
  }
  $stopEvent.Dispose()
  $mutex.Dispose()
}
