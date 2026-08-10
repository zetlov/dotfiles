param(
  [ValidateSet("winio","wintercept")]
  [string]$Driver = "winio",

  [ValidateSet("tty","gui")]
  [string]$Ui = "tty",

  [switch]$CmdAllowed = $false,

  [ValidateSet("arm64","x64","auto")]
  [string]$Cpu = "auto",

  [switch]$AddDefenderExclusion = $false,

  [string]$InstallDir = "$env:LOCALAPPDATA\kanata"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$installerModule = Join-Path $PSScriptRoot "KanataInstaller.psm1"
Import-Module $installerModule -Force -ErrorAction Stop
$defenderModule = Join-Path $PSScriptRoot "KanataDefender.psm1"
Import-Module $defenderModule -Force -ErrorAction Stop
$gameModeModule = Join-Path $PSScriptRoot "KanataGameMode.psm1"
Import-Module $gameModeModule -Force -ErrorAction Stop

function Resolve-DotfilesRoot {
  # dotfiles/windows/kanata/install.ps1 -> dotfiles/
  return (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
}

function Detect-Cpu {
  param([string]$CpuParam)
  if ($CpuParam -ne "auto") { return $CpuParam }

  # Windows ARM は ARM64 として出る想定
  $arch = $env:PROCESSOR_ARCHITECTURE
  if ($arch -match "ARM64") { return "arm64" }
  return "x64"
}

function Stop-KanataIfRunning {
  param([string]$ExePath)
  Stop-KanataManagedProcesses -ExePath $ExePath
}

function Register-RunEntry {
  param([string]$InstallDir)
  Set-KanataGameModeRunEntry -InstallDir $InstallDir
}

# ---- main ----
$dot = Resolve-DotfilesRoot
$InstallDir = Resolve-KanataInstallDir -Path $InstallDir
$cfgSrc = Join-Path $dot "windows\kanata\kanata.kbd"
if (-not (Test-Path $cfgSrc)) {
  throw "Config not found: $cfgSrc"
}
$gameModeSources = @(
  @{
    Name = "KanataGameMode.psm1"
    Path = Join-Path $PSScriptRoot "KanataGameMode.psm1"
  },
  @{
    Name = "game-mode.ps1"
    Path = Join-Path $PSScriptRoot "game-mode.ps1"
  },
  @{
    Name = "game-mode.json"
    Path = Join-Path $PSScriptRoot "game-mode.json"
  }
)
foreach ($source in $gameModeSources) {
  if (-not (Test-Path -LiteralPath $source.Path -PathType Leaf)) {
    throw "Game mode file not found: $($source.Path)"
  }
}
[void](Get-KanataGameModeSettings `
  -Path (Join-Path $PSScriptRoot "game-mode.json"))

$cpuResolved = Detect-Cpu -CpuParam $Cpu
$releaseSpec = Get-KanataReleaseSpec -Cpu $cpuResolved -Driver $Driver

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
$cfgDst  = Join-Path $InstallDir "kanata.kbd"
$exeDst  = Join-Path $InstallDir "kanata.exe"
$metaDst = Join-Path $InstallDir "install.json"

Write-Host "Dotfiles root  : $dot"
Write-Host "Install dir    : $InstallDir"
Write-Host "CPU            : $cpuResolved"
Write-Host "Driver         : $Driver"
Write-Host "UI             : $Ui"
Write-Host "CmdAllowed     : $CmdAllowed"
Write-Host "Version        : $($releaseSpec.Version)"

$tmp = Join-Path $env:TEMP ("kanata_dl_" + [guid]::NewGuid().ToString("N"))
$zip = Join-Path $tmp "kanata.zip"
$defenderExclusionAdded = $false
$defenderExclusionOwned = $false
$installCompleted = $false
$installError = $null
$rollbackPrepared = $false
$rollbackSucceeded = $false
$rollbackDir = Join-Path $tmp "rollback"
$managedFileNames = @(
  "kanata.exe",
  "kanata.kbd",
  "install.json",
  "KanataGameMode.psm1",
  "game-mode.ps1",
  "game-mode.json"
)
$previousFiles = @{}
$previousRunValues = @{}
$previousWatcherRunning = $false
$previousKanataRunning = $false

if (Test-Path -LiteralPath $metaDst -PathType Leaf) {
  $previousMeta = Get-Content -LiteralPath $metaDst -Raw | ConvertFrom-Json
  $ownershipProperty = $previousMeta.PSObject.Properties["defender_exclusion_added"]
  if ($ownershipProperty) {
    $defenderExclusionOwned = [bool]$ownershipProperty.Value
  }
}

try {
  New-Item -ItemType Directory -Force -Path $tmp | Out-Null
  $url = $releaseSpec.DownloadUrl
  Write-Host "Downloading    : $url"
  Invoke-WebRequest -Uri $url -OutFile $zip
  $payload = Get-VerifiedKanataExecutablePayload `
    -ZipPath $zip `
    -ExpectedSha256 $releaseSpec.Sha256 `
    -Driver $Driver `
    -Ui $Ui `
    -CmdAllowed ([bool]$CmdAllowed)
  Write-Host "SHA-256        : verified"

  New-Item -ItemType Directory -Path $rollbackDir | Out-Null
  foreach ($name in $managedFileNames) {
    $destinationPath = Join-Path $InstallDir $name
    $existed = Test-Path -LiteralPath $destinationPath -PathType Leaf
    $previousFiles[$name] = $existed
    if ($existed) {
      Copy-Item `
        -LiteralPath $destinationPath `
        -Destination (Join-Path $rollbackDir $name)
    }
  }
  $runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
  $runProperties = if (Test-Path -LiteralPath $runKey) {
    Get-ItemProperty -LiteralPath $runKey
  } else {
    $null
  }
  foreach ($name in @("DotfilesKanataGameMode", "Kanata")) {
    $property = if ($runProperties) {
      $runProperties.PSObject.Properties[$name]
    } else {
      $null
    }
    $previousRunValues[$name] = [pscustomobject]@{
      Existed = $null -ne $property
      Value = if ($property) { [string]$property.Value } else { "" }
    }
  }
  $previousWatcherRunning = Test-KanataGameModeWatcher `
    -InstallDir $InstallDir
  $previousKanataRunning = @(
    Get-KanataManagedProcesses -ExePath $exeDst
  ).Count -gt 0
  $rollbackPrepared = $true

  if ($AddDefenderExclusion) {
    $defenderExclusionAdded = Add-KanataDefenderExclusion -ExePath $exeDst
    $defenderExclusionOwned = $defenderExclusionOwned -or $defenderExclusionAdded
    Write-Host "Defender allow : $exeDst"
  }

  Stop-KanataGameModeWatcher -InstallDir $InstallDir
  Stop-KanataIfRunning -ExePath $exeDst
  $exePicked = Install-KanataExecutablePayload `
    -Payload $payload `
    -DestinationPath $exeDst
  Write-Host "Selected exe   : $exePicked"

  Copy-Item -Path $cfgSrc -Destination $cfgDst -Force
  foreach ($source in $gameModeSources) {
    Copy-Item `
      -LiteralPath $source.Path `
      -Destination (Join-Path $InstallDir $source.Name) `
      -Force
  }
  $meta = @{
    cpu = $cpuResolved
    version = $releaseSpec.Version
    asset = $releaseSpec.AssetName
    sha256 = $releaseSpec.Sha256
    driver = $Driver
    ui = $Ui
    cmd_allowed = [bool]$CmdAllowed
    defender_exclusion = [bool]$AddDefenderExclusion
    defender_exclusion_added = [bool]$defenderExclusionOwned
    game_mode = $true
    installed_at = (Get-Date).ToString("o")
  }
  $meta | ConvertTo-Json | Set-Content -Path $metaDst -Encoding UTF8
  Register-RunEntry -InstallDir $InstallDir

  Write-Host "Installed exe  : $exeDst"
  Write-Host "Installed cfg  : $cfgDst"
  Write-Host "Saved meta     : $metaDst"
  Write-Host "Run at login   : HKCU\...\Run\DotfilesKanataGameMode"

  Start-KanataGameModeWatcher -InstallDir $InstallDir
  Write-Host "Started Kanata game mode watcher."
  $installCompleted = $true
} catch {
  $installError = $_
  if ($rollbackPrepared) {
    try {
      Stop-KanataGameModeWatcher -InstallDir $InstallDir
      Stop-KanataManagedProcesses -ExePath $exeDst
      foreach ($name in $managedFileNames) {
        $destinationPath = Join-Path $InstallDir $name
        if ([bool]$previousFiles[$name]) {
          Copy-Item `
            -LiteralPath (Join-Path $rollbackDir $name) `
            -Destination $destinationPath `
            -Force
        } elseif (Test-Path -LiteralPath $destinationPath -PathType Leaf) {
          Remove-Item -LiteralPath $destinationPath -Force
        }
      }
      if (-not (Test-Path -LiteralPath $runKey)) {
        New-Item -Path $runKey | Out-Null
      }
      foreach ($name in @("DotfilesKanataGameMode", "Kanata")) {
        $state = $previousRunValues[$name]
        if ($state.Existed) {
          New-ItemProperty `
            -LiteralPath $runKey `
            -Name $name `
            -Value $state.Value `
            -PropertyType String `
            -Force | Out-Null
        } else {
          Remove-ItemProperty `
            -LiteralPath $runKey `
            -Name $name `
            -ErrorAction SilentlyContinue
        }
      }
      if ($previousWatcherRunning) {
        Start-KanataGameModeWatcher -InstallDir $InstallDir
      } elseif ($previousKanataRunning) {
        Start-KanataManagedProcess `
          -ExePath $exeDst `
          -ConfigPath $cfgDst | Out-Null
      }
      $rollbackSucceeded = $true
    } catch {
      Write-Warning (
        "Failed to restore the previous Kanata install. Recovery files remain " +
        "at ${rollbackDir}: $($_.Exception.Message)"
      )
    }
  }
} finally {
  if (-not $installCompleted -and $defenderExclusionAdded) {
    try {
      Remove-KanataDefenderExclusion -ExePath $exeDst | Out-Null
    } catch {
      Write-Warning "Failed to roll back the Kanata Defender exclusion: $($_.Exception.Message)"
    }
  }
  if (
    (Test-Path -LiteralPath $tmp) -and
    ($installCompleted -or $rollbackSucceeded -or -not $rollbackPrepared)
  ) {
    try {
      Remove-Item -LiteralPath $tmp -Recurse -Force
    } catch {
      Write-Warning "Failed to remove temporary Kanata files: $($_.Exception.Message)"
    }
  }
}

if ($installError) {
  throw $installError
}
