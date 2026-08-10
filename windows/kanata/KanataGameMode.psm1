Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function ConvertTo-KanataExecutableList {
  param(
    [Parameter(Mandatory = $true)]
    [AllowEmptyCollection()]
    [object[]]$Values,

    [Parameter(Mandatory = $true)]
    [string]$SettingName
  )

  $executables = @()
  foreach ($executable in $Values) {
    $name = [string]$executable
    if (
      [string]::IsNullOrWhiteSpace($name) -or
      $name -notmatch '^[^\\/:*?"<>|]+\.exe$'
    ) {
      throw "Invalid executable name in ${SettingName}: $name"
    }
    if ($executables -contains $name) {
      throw "Duplicate executable name in ${SettingName}: $name"
    }
    $executables += $name
  }
  return $executables
}

function ConvertTo-KanataDirectoryList {
  param(
    [Parameter(Mandatory = $true)]
    [AllowEmptyCollection()]
    [object[]]$Values,

    [Parameter(Mandatory = $true)]
    [string]$SettingName
  )

  $directories = @()
  foreach ($value in $Values) {
    $name = [string]$value
    if (
      [string]::IsNullOrWhiteSpace($name) -or
      $name -in @(".", "..") -or
      $name -notmatch '^[A-Za-z0-9][A-Za-z0-9._ -]*$'
    ) {
      throw "Invalid directory name in ${SettingName}: $name"
    }
    if ($directories -contains $name) {
      throw "Duplicate directory name in ${SettingName}: $name"
    }
    $directories += $name
  }
  return $directories
}

function Resolve-KanataInstallDir {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  $expectedPath = [System.IO.Path]::GetFullPath(
    (Join-Path $env:LOCALAPPDATA "kanata")
  )
  $normalizedPath = [System.IO.Path]::GetFullPath($Path)
  if (-not $normalizedPath.Equals(
    $expectedPath,
    [System.StringComparison]::OrdinalIgnoreCase
  )) {
    throw "Kanata must be installed at: $expectedPath"
  }
  if (Test-Path -LiteralPath $normalizedPath) {
    $attributes = [System.IO.File]::GetAttributes($normalizedPath)
    if ($attributes.HasFlag([System.IO.FileAttributes]::ReparsePoint)) {
      throw "The Kanata install directory cannot be a reparse point."
    }
  }
  return $normalizedPath
}

function Get-KanataGameModeSettings {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "Kanata game mode settings not found: $Path"
  }
  try {
    $raw = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
  } catch {
    throw "Cannot parse Kanata game mode settings: $Path"
  }

  foreach ($propertyName in @(
    "poll_interval_ms",
    "resume_delay_ms",
    "disable_for_steam_games",
    "disable_only_when_game_foreground",
    "steam_ignore_executables",
    "steam_ignore_directories",
    "hard_off_executables"
  )) {
    if (-not $raw.PSObject.Properties[$propertyName]) {
      throw "Kanata game mode setting is missing: $propertyName"
    }
  }

  $pollInterval = [int]$raw.poll_interval_ms
  if ($pollInterval -lt 250 -or $pollInterval -gt 10000) {
    throw "poll_interval_ms must be between 250 and 10000."
  }
  $resumeDelay = [int]$raw.resume_delay_ms
  if ($resumeDelay -lt 0 -or $resumeDelay -gt 10000) {
    throw "resume_delay_ms must be between 0 and 10000."
  }
  if ($raw.disable_for_steam_games -isnot [bool]) {
    throw "disable_for_steam_games must be a boolean."
  }
  if ($raw.disable_only_when_game_foreground -isnot [bool]) {
    throw "disable_only_when_game_foreground must be a boolean."
  }

  $steamIgnoreExecutables = @(
    ConvertTo-KanataExecutableList `
      -Values @($raw.steam_ignore_executables) `
      -SettingName "steam_ignore_executables"
  )
  $hardOffExecutables = @(
    ConvertTo-KanataExecutableList `
      -Values @($raw.hard_off_executables) `
      -SettingName "hard_off_executables"
  )
  $steamIgnoreDirectories = @(
    ConvertTo-KanataDirectoryList `
      -Values @($raw.steam_ignore_directories) `
      -SettingName "steam_ignore_directories"
  )
  foreach ($executable in $steamIgnoreExecutables) {
    if ($hardOffExecutables -contains $executable) {
      throw "Executable cannot be both ignored and hard-off: $executable"
    }
  }

  return [pscustomobject]@{
    PollIntervalMilliseconds = $pollInterval
    ResumeDelayMilliseconds = $resumeDelay
    DisableForSteamGames = [bool]$raw.disable_for_steam_games
    DisableOnlyWhenGameForeground = (
      [bool]$raw.disable_only_when_game_foreground
    )
    SteamIgnoreExecutables = $steamIgnoreExecutables
    SteamIgnoreDirectories = $steamIgnoreDirectories
    HardOffExecutables = $hardOffExecutables
  }
}

function Get-KanataSteamCommonPaths {
  param(
    [Parameter(Mandatory = $true)]
    [string]$SteamPath,

    [string]$LibraryFoldersPath = ""
  )

  try {
    $normalizedSteamPath = [System.IO.Path]::GetFullPath($SteamPath)
  } catch {
    throw "Steam path is invalid: $SteamPath"
  }
  if ($normalizedSteamPath.StartsWith("\\")) {
    throw "A network Steam library is not supported."
  }

  $candidates = @($normalizedSteamPath)
  if ([string]::IsNullOrWhiteSpace($LibraryFoldersPath)) {
    $LibraryFoldersPath = Join-Path `
      $normalizedSteamPath `
      "steamapps\libraryfolders.vdf"
  }
  if (Test-Path -LiteralPath $LibraryFoldersPath -PathType Leaf) {
    $libraryFile = Get-Item -LiteralPath $LibraryFoldersPath
    if ($libraryFile.Length -gt 1MB) {
      throw "Steam libraryfolders.vdf is unexpectedly large."
    }
    $libraryText = Get-Content -LiteralPath $LibraryFoldersPath -Raw
    $candidates += @(
      [regex]::Matches($libraryText, '"path"\s+"([^"]+)"') |
        ForEach-Object { $_.Groups[1].Value.Replace("\\", "\") }
    )
  }

  $result = @()
  foreach ($candidate in $candidates) {
    if ([string]::IsNullOrWhiteSpace([string]$candidate)) {
      continue
    }
    try {
      $normalizedCandidate = [System.IO.Path]::GetFullPath([string]$candidate)
    } catch {
      continue
    }
    if ($normalizedCandidate.StartsWith("\\")) {
      continue
    }
    $commonPath = Join-Path $normalizedCandidate "steamapps\common"
    if (-not (Test-Path -LiteralPath $commonPath -PathType Container)) {
      continue
    }
    $alreadyPresent = @($result | Where-Object {
      $_.Equals(
        $commonPath,
        [System.StringComparison]::OrdinalIgnoreCase
      )
    }).Count -gt 0
    if (-not $alreadyPresent) {
      $result += $commonPath
    }
  }

  return $result
}

function Test-KanataGameProcess {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ProcessName,

    [AllowEmptyString()]
    [string]$ProcessPath = "",

    [string[]]$SteamCommonPaths = @(),

    [bool]$DisableForSteamGames = $true,

    [string[]]$SteamIgnoreExecutables = @(),

    [string[]]$SteamIgnoreDirectories = @(),

    [string[]]$HardOffExecutables = @()
  )

  $processExecutable = if ($ProcessName.EndsWith(
    ".exe",
    [System.StringComparison]::OrdinalIgnoreCase
  )) {
    $ProcessName
  } else {
    "$ProcessName.exe"
  }
  foreach ($hardOffExecutable in $HardOffExecutables) {
    if ($processExecutable.Equals(
      $hardOffExecutable,
      [System.StringComparison]::OrdinalIgnoreCase
    )) {
      return $true
    }
  }
  if (
    -not $DisableForSteamGames -or
    [string]::IsNullOrWhiteSpace($ProcessPath)
  ) {
    return $false
  }

  try {
    $normalizedProcessPath = [System.IO.Path]::GetFullPath($ProcessPath)
  } catch {
    return $false
  }
  foreach ($steamCommonPath in $SteamCommonPaths) {
    try {
      $normalizedCommonPath = (
        [System.IO.Path]::GetFullPath($steamCommonPath).TrimEnd("\") + "\"
      )
    } catch {
      continue
    }
    if ($normalizedProcessPath.StartsWith(
      $normalizedCommonPath,
      [System.StringComparison]::OrdinalIgnoreCase
    )) {
      $relativePath = $normalizedProcessPath.Substring(
        $normalizedCommonPath.Length
      )
      $topLevelDirectory = @($relativePath.Split("\"))[0]
      foreach ($ignoredDirectory in $SteamIgnoreDirectories) {
        if ($topLevelDirectory.Equals(
          $ignoredDirectory,
          [System.StringComparison]::OrdinalIgnoreCase
        )) {
          return $false
        }
      }
      foreach ($ignoredExecutable in $SteamIgnoreExecutables) {
        if ($processExecutable.Equals(
          $ignoredExecutable,
          [System.StringComparison]::OrdinalIgnoreCase
        )) {
          return $false
        }
      }
      return $true
    }
  }

  return $false
}

function Get-KanataRunningGameProcesses {
  param(
    [Parameter(Mandatory = $true)]
    [object]$Settings,

    [string[]]$SteamCommonPaths = @()
  )

  $matches = @()
  foreach ($process in Get-Process -ErrorAction SilentlyContinue) {
    $processPath = ""
    try {
      $processPath = [string]$process.Path
    } catch {
      $processPath = ""
    }
    if (Test-KanataGameProcess `
      -ProcessName $process.ProcessName `
      -ProcessPath $processPath `
      -SteamCommonPaths $SteamCommonPaths `
      -DisableForSteamGames $Settings.DisableForSteamGames `
      -SteamIgnoreExecutables $Settings.SteamIgnoreExecutables `
      -SteamIgnoreDirectories $Settings.SteamIgnoreDirectories `
      -HardOffExecutables $Settings.HardOffExecutables
    ) {
      $matches += $process
    }
  }
  return $matches
}

function Initialize-KanataForegroundWindowType {
  $typeName = "Dotfiles.Kanata.ForegroundWindow"
  if (-not ([System.Management.Automation.PSTypeName]$typeName).Type) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace Dotfiles.Kanata {
  public static class ForegroundWindow {
    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(
      IntPtr windowHandle,
      out uint processId
    );

    [DllImport("user32.dll")]
    public static extern short GetAsyncKeyState(int virtualKey);
  }
}
'@
  }
}

function Get-KanataForegroundProcess {
  Initialize-KanataForegroundWindowType
  $windowHandle = [Dotfiles.Kanata.ForegroundWindow]::GetForegroundWindow()
  if ($windowHandle -eq [IntPtr]::Zero) {
    return $null
  }
  $processId = [uint32]0
  [void][Dotfiles.Kanata.ForegroundWindow]::GetWindowThreadProcessId(
    $windowHandle,
    [ref]$processId
  )
  if ($processId -eq 0) {
    return $null
  }
  return Get-Process -Id $processId -ErrorAction SilentlyContinue
}

function Test-KanataAnyKeyboardKeyPressed {
  Initialize-KanataForegroundWindowType
  for ($virtualKey = 8; $virtualKey -le 254; $virtualKey++) {
    $state = [int](
      [Dotfiles.Kanata.ForegroundWindow]::GetAsyncKeyState($virtualKey)
    )
    if (($state -band 0x8000) -ne 0) {
      return $true
    }
  }
  return $false
}

function Get-KanataForegroundGameProcesses {
  param(
    [Parameter(Mandatory = $true)]
    [object]$Settings,

    [string[]]$SteamCommonPaths = @()
  )

  $process = Get-KanataForegroundProcess
  if (-not $process) {
    return @()
  }
  $processPath = ""
  try {
    $processPath = [string]$process.Path
  } catch {
    $processPath = ""
  }
  if (Test-KanataGameProcess `
    -ProcessName $process.ProcessName `
    -ProcessPath $processPath `
    -SteamCommonPaths $SteamCommonPaths `
    -DisableForSteamGames $Settings.DisableForSteamGames `
    -SteamIgnoreExecutables $Settings.SteamIgnoreExecutables `
    -SteamIgnoreDirectories $Settings.SteamIgnoreDirectories `
    -HardOffExecutables $Settings.HardOffExecutables
  ) {
    return @($process)
  }
  return @()
}

function Get-KanataGameModeDecision {
  param(
    [Parameter(Mandatory = $true)]
    [bool]$GameActive,

    [Parameter(Mandatory = $true)]
    [bool]$KanataRunning,

    [Parameter(Mandatory = $true)]
    [bool]$KeyboardKeyPressed,

    [Parameter(Mandatory = $true)]
    [datetime]$ResumeKanataAt,

    [Parameter(Mandatory = $true)]
    [datetime]$Now,

    [Parameter(Mandatory = $true)]
    [ValidateRange(0, 10000)]
    [int]$ResumeDelayMilliseconds
  )

  if ($GameActive) {
    $action = if ($KanataRunning -and -not $KeyboardKeyPressed) {
      "Stop"
    } else {
      "None"
    }
    return [pscustomobject]@{
      Action = $action
      ResumeKanataAt = [datetime]::MinValue
    }
  }
  if ($KanataRunning) {
    return [pscustomobject]@{
      Action = "None"
      ResumeKanataAt = [datetime]::MinValue
    }
  }
  if ($ResumeKanataAt -eq [datetime]::MinValue) {
    return [pscustomobject]@{
      Action = "None"
      ResumeKanataAt = $Now.AddMilliseconds($ResumeDelayMilliseconds)
    }
  }
  if ($Now -ge $ResumeKanataAt) {
    return [pscustomobject]@{
      Action = "Start"
      ResumeKanataAt = [datetime]::MinValue
    }
  }
  return [pscustomobject]@{
    Action = "None"
    ResumeKanataAt = $ResumeKanataAt
  }
}

function Get-KanataWatcherPaths {
  param(
    [Parameter(Mandatory = $true)]
    [string]$InstallDir
  )

  $normalizedInstallDir = Resolve-KanataInstallDir -Path $InstallDir
  return [pscustomobject]@{
    Script = Join-Path $normalizedInstallDir "game-mode.ps1"
    Settings = Join-Path $normalizedInstallDir "game-mode.json"
    Log = Join-Path $normalizedInstallDir "game-mode.log"
  }
}

function Test-KanataGameModeWatcher {
  param(
    [Parameter(Mandatory = $true)]
    [string]$InstallDir
  )

  [void](Resolve-KanataInstallDir -Path $InstallDir)
  try {
    $mutex = [System.Threading.Mutex]::OpenExisting(
      "Local\DotfilesKanataGameMode"
    )
  } catch [System.Threading.WaitHandleCannotBeOpenedException] {
    return $false
  }

  try {
    try {
      $acquired = $mutex.WaitOne(0, $false)
    } catch [System.Threading.AbandonedMutexException] {
      $acquired = $true
    }
    if ($acquired) {
      $mutex.ReleaseMutex()
      return $false
    }
    return $true
  } finally {
    $mutex.Dispose()
  }
}

function Get-KanataQuotedArgument {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Value
  )

  if ($Value.Contains('"')) {
    throw "A Windows process argument cannot contain a quote."
  }
  return '"{0}"' -f $Value
}

function Get-KanataGameModeRunCommand {
  param(
    [Parameter(Mandatory = $true)]
    [string]$InstallDir
  )

  $normalizedInstallDir = Resolve-KanataInstallDir -Path $InstallDir
  $powerShellPath = Join-Path $env:WINDIR (
    "System32\WindowsPowerShell\v1.0\powershell.exe"
  )
  $watcherPath = Join-Path $normalizedInstallDir "game-mode.ps1"
  foreach ($value in @($powerShellPath, $watcherPath, $normalizedInstallDir)) {
    if ($value.Contains('"')) {
      throw "A Kanata autostart path cannot contain a quote."
    }
  }
  return (
    "`"$powerShellPath`" -NoProfile -ExecutionPolicy Bypass " +
    "-WindowStyle Hidden -File `"$watcherPath`" " +
    "-InstallDir `"$normalizedInstallDir`""
  )
}

function Get-KanataLegacyRunCommands {
  param(
    [Parameter(Mandatory = $true)]
    [string]$InstallDir
  )

  $normalizedInstallDir = Resolve-KanataInstallDir -Path $InstallDir
  $exePath = Join-Path $normalizedInstallDir "kanata.exe"
  $configPath = Join-Path $normalizedInstallDir "kanata.kbd"
  $conhostPath = Join-Path $env:WINDIR "System32\conhost.exe"
  return @(
    "`"$exePath`" --cfg `"$configPath`"",
    (
      "`"$conhostPath`" --headless `"$exePath`" " +
      "--cfg `"$configPath`""
    )
  )
}

function Test-KanataOwnedRunValue {
  param(
    [AllowNull()]
    [string]$Value,

    [Parameter(Mandatory = $true)]
    [string[]]$ExpectedValues
  )

  if ([string]::IsNullOrWhiteSpace($Value)) {
    return $false
  }
  foreach ($expected in $ExpectedValues) {
    if ($Value.Equals(
      $expected,
      [System.StringComparison]::OrdinalIgnoreCase
    )) {
      return $true
    }
  }
  return $false
}

function Set-KanataGameModeRunEntry {
  param(
    [Parameter(Mandatory = $true)]
    [string]$InstallDir
  )

  $runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
  $name = "DotfilesKanataGameMode"
  $command = Get-KanataGameModeRunCommand -InstallDir $InstallDir
  $legacyCommands = @(Get-KanataLegacyRunCommands -InstallDir $InstallDir)

  if (-not (Test-Path -LiteralPath $runKey)) {
    New-Item -Path $runKey | Out-Null
  }
  $runValues = Get-ItemProperty -LiteralPath $runKey
  $existingGameMode = $runValues.PSObject.Properties[$name]
  if (
    $existingGameMode -and
    -not (Test-KanataOwnedRunValue `
      -Value ([string]$existingGameMode.Value) `
      -ExpectedValues @($command))
  ) {
    throw "Refusing to overwrite an unrecognized Run entry: $name"
  }
  $legacy = $runValues.PSObject.Properties["Kanata"]
  if (
    $legacy -and
    -not (Test-KanataOwnedRunValue `
      -Value ([string]$legacy.Value) `
      -ExpectedValues $legacyCommands)
  ) {
    throw "Refusing to remove an unrecognized Run entry: Kanata"
  }

  New-ItemProperty `
    -LiteralPath $runKey `
    -Name $name `
    -Value $command `
    -PropertyType String `
    -Force | Out-Null
  if ($legacy) {
    Remove-ItemProperty -LiteralPath $runKey -Name "Kanata"
  }
}

function Start-KanataManagedProcess {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ExePath,

    [Parameter(Mandatory = $true)]
    [string]$ConfigPath
  )

  foreach ($path in @($ExePath, $ConfigPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
      throw "Required Kanata file not found: $path"
    }
  }
  $arguments = "--nodelay --cfg $(Get-KanataQuotedArgument -Value $ConfigPath)"
  return Start-Process `
    -FilePath $ExePath `
    -ArgumentList $arguments `
    -WindowStyle Hidden `
    -PassThru
}

function Get-KanataManagedProcesses {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ExePath
  )

  $normalizedExePath = [System.IO.Path]::GetFullPath($ExePath)
  return @(
    Get-Process -Name "kanata" -ErrorAction SilentlyContinue |
      Where-Object {
        try {
          ([System.IO.Path]::GetFullPath([string]$_.Path)).Equals(
            $normalizedExePath,
            [System.StringComparison]::OrdinalIgnoreCase
          )
        } catch {
          $false
        }
      }
  )
}

function Stop-KanataManagedProcesses {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ExePath
  )

  foreach ($process in @(Get-KanataManagedProcesses -ExePath $ExePath)) {
    try {
      $process | Stop-Process -Force -ErrorAction Stop
    } catch {
      Write-Warning "Failed to stop managed Kanata process $($process.Id)."
    }
  }
}

function Start-KanataGameModeWatcher {
  param(
    [Parameter(Mandatory = $true)]
    [string]$InstallDir
  )

  $paths = Get-KanataWatcherPaths -InstallDir $InstallDir
  foreach ($path in @($paths.Script, $paths.Settings)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
      throw "Required Kanata game mode file not found: $path"
    }
  }
  if (Test-KanataGameModeWatcher -InstallDir $InstallDir) {
    return
  }
  $powerShellPath = Join-Path $env:WINDIR (
    "System32\WindowsPowerShell\v1.0\powershell.exe"
  )
  if (-not (Test-Path -LiteralPath $powerShellPath -PathType Leaf)) {
    throw "Windows PowerShell not found: $powerShellPath"
  }
  $normalizedInstallDir = Split-Path -Parent $paths.Script
  $arguments = (
    "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden " +
    "-File $(Get-KanataQuotedArgument -Value $paths.Script) " +
    "-InstallDir $(Get-KanataQuotedArgument -Value $normalizedInstallDir)"
  )
  $watcherProcess = Start-Process `
    -FilePath $powerShellPath `
    -ArgumentList $arguments `
    -WindowStyle Hidden `
    -PassThru

  $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
  while ($stopwatch.Elapsed.TotalSeconds -lt 3) {
    if (Test-KanataGameModeWatcher -InstallDir $InstallDir) {
      return
    }
    if ($watcherProcess.HasExited) {
      throw (
        "Kanata game mode watcher exited during startup with code " +
        "$($watcherProcess.ExitCode)."
      )
    }
    Start-Sleep -Milliseconds 100
  }
  if (-not $watcherProcess.HasExited) {
    $watcherProcess | Stop-Process -Force -ErrorAction SilentlyContinue
  }
  throw "Timed out waiting for the Kanata game mode watcher to start."
}

function Stop-KanataGameModeWatcher {
  param(
    [Parameter(Mandatory = $true)]
    [string]$InstallDir,

    [ValidateRange(0, 10)]
    [int]$TimeoutSeconds = 3
  )

  if (-not (Test-KanataGameModeWatcher -InstallDir $InstallDir)) {
    return
  }

  try {
    $stopEvent = [System.Threading.EventWaitHandle]::OpenExisting(
      "Local\DotfilesKanataGameModeStop"
    )
  } catch [System.Threading.WaitHandleCannotBeOpenedException] {
    if (-not (Test-KanataGameModeWatcher -InstallDir $InstallDir)) {
      return
    }
    throw "Kanata game mode watcher stop event was not found."
  }
  try {
    [void]$stopEvent.Set()
  } finally {
    $stopEvent.Dispose()
  }

  $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
  while (Test-KanataGameModeWatcher -InstallDir $InstallDir) {
    if ($stopwatch.Elapsed.TotalSeconds -ge $TimeoutSeconds) {
      if (-not (Test-KanataGameModeWatcher -InstallDir $InstallDir)) {
        return
      }
      throw "Timed out waiting for the Kanata game mode watcher to stop."
    }
    Start-Sleep -Milliseconds 100
  }
}

Export-ModuleMember -Function `
  Resolve-KanataInstallDir, `
  Get-KanataGameModeSettings, `
  Get-KanataSteamCommonPaths, `
  Test-KanataGameProcess, `
  Get-KanataRunningGameProcesses, `
  Get-KanataForegroundProcess, `
  Test-KanataAnyKeyboardKeyPressed, `
  Get-KanataForegroundGameProcesses, `
  Get-KanataGameModeDecision, `
  Get-KanataWatcherPaths, `
  Test-KanataGameModeWatcher, `
  Get-KanataGameModeRunCommand, `
  Get-KanataLegacyRunCommands, `
  Test-KanataOwnedRunValue, `
  Set-KanataGameModeRunEntry, `
  Start-KanataManagedProcess, `
  Get-KanataManagedProcesses, `
  Stop-KanataManagedProcesses, `
  Start-KanataGameModeWatcher, `
  Stop-KanataGameModeWatcher
