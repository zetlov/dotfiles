param(
  [string]$InstallDir = "$env:LOCALAPPDATA\kanata",
  [switch]$RemoveFiles = $false,
  [switch]$KeepDefenderExclusion = $false,
  [switch]$KeepSurfaceImeScancodeMap = $false,
  [switch]$KeepImeOffPowerToysMapping = $false
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$gameModeModule = Join-Path $PSScriptRoot "KanataGameMode.psm1"
Import-Module $gameModeModule -Force -ErrorAction Stop
$InstallDir = Resolve-KanataInstallDir -Path $InstallDir
$defenderModule = Join-Path $PSScriptRoot "KanataDefender.psm1"
Import-Module $defenderModule -Force -ErrorAction Stop
$surfaceImeModule = Join-Path $PSScriptRoot "KanataSurfaceIme.psm1"
Import-Module $surfaceImeModule -Force -ErrorAction Stop
$powerToysModule = Join-Path $PSScriptRoot "KanataPowerToys.psm1"
Import-Module $powerToysModule -Force -ErrorAction Stop

# stop
Stop-KanataGameModeWatcher -InstallDir $InstallDir
$exeDst = Join-Path $InstallDir "kanata.exe"
Stop-KanataManagedProcesses -ExePath $exeDst

# remove Run entry
$runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
if (Test-Path $runKey) {
  $runValues = Get-ItemProperty -LiteralPath $runKey
  $gameModeProperty = $runValues.PSObject.Properties[
    "DotfilesKanataGameMode"
  ]
  $expectedGameMode = Get-KanataGameModeRunCommand -InstallDir $InstallDir
  if (
    $gameModeProperty -and
    (Test-KanataOwnedRunValue `
      -Value ([string]$gameModeProperty.Value) `
      -ExpectedValues @($expectedGameMode))
  ) {
    Remove-ItemProperty `
      -LiteralPath $runKey `
      -Name "DotfilesKanataGameMode"
  }

  $legacyProperty = $runValues.PSObject.Properties["Kanata"]
  $legacyCommands = @(Get-KanataLegacyRunCommands -InstallDir $InstallDir)
  if (
    $legacyProperty -and
    (Test-KanataOwnedRunValue `
      -Value ([string]$legacyProperty.Value) `
      -ExpectedValues $legacyCommands)
  ) {
    Remove-ItemProperty -LiteralPath $runKey -Name "Kanata"
  }
}

Write-Host "Removed Run entry and stopped kanata."

$metaPath = Join-Path $InstallDir "install.json"
$ownsDefenderExclusion = $false
$ownsSurfaceImeScancodeMap = $false
$ownsImeOffPowerToysMapping = $false
if (Test-Path -LiteralPath $metaPath -PathType Leaf) {
  $meta = Get-Content -LiteralPath $metaPath -Raw | ConvertFrom-Json
  $ownershipProperty = $meta.PSObject.Properties["defender_exclusion_added"]
  if ($ownershipProperty) {
    $ownsDefenderExclusion = [bool]$ownershipProperty.Value
  }
  $surfaceImeProperty = $meta.PSObject.Properties[
    "surface_ime_scancode_map_added"
  ]
  if ($surfaceImeProperty) {
    $ownsSurfaceImeScancodeMap = [bool]$surfaceImeProperty.Value
  }
  $powerToysProperty = $meta.PSObject.Properties[
    "ime_off_powertoys_mapping_added"
  ]
  if ($powerToysProperty) {
    $ownsImeOffPowerToysMapping = [bool]$powerToysProperty.Value
  }
}
$isLocalAppDataInstall = [System.IO.Path]::GetFullPath($InstallDir).StartsWith(
  [System.IO.Path]::GetFullPath($env:LOCALAPPDATA).TrimEnd("\") + "\",
  [System.StringComparison]::OrdinalIgnoreCase
)
if (-not $KeepDefenderExclusion -and $ownsDefenderExclusion -and $isLocalAppDataInstall) {
  $removed = Remove-KanataDefenderExclusion -ExePath $exeDst
  if ($removed) {
    Write-Host "Removed Defender exclusion: $exeDst"
  }
}
if (
  -not $KeepSurfaceImeScancodeMap -and
  $ownsSurfaceImeScancodeMap -and
  $isLocalAppDataInstall
) {
  if (Remove-KanataSurfaceImeScancodeMap) {
    Write-Host "Removed Surface IME Scancode Map entries."
  }
}
if (
  -not $KeepImeOffPowerToysMapping -and
  $ownsImeOffPowerToysMapping -and
  $isLocalAppDataInstall
) {
  if (Remove-KanataImeOffPowerToysMapping) {
    Write-Host "Removed Surface IME PowerToys mapping."
  }
}

if ($RemoveFiles -and (Test-Path $InstallDir)) {
  Remove-Item -Recurse -Force $InstallDir
  Write-Host "Removed files: $InstallDir"
}
