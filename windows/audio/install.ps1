[CmdletBinding()]
param(
  [string]$InstallRoot = (
    Join-Path $env:LOCALAPPDATA "dotfiles\audio"
  ),
  [string]$ProgramsRoot = [Environment]::GetFolderPath("Programs"),
  [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($env:OS -ne "Windows_NT") {
  throw "This script must run on Windows."
}
if ([string]::IsNullOrWhiteSpace($InstallRoot)) {
  throw "The audio install root cannot be empty."
}
if ([string]::IsNullOrWhiteSpace($ProgramsRoot)) {
  throw "The current user's Programs folder cannot be resolved."
}

$installerModule = Join-Path $PSScriptRoot "AudioSwitcherInstaller.psm1"
$dependencyModule = Join-Path $PSScriptRoot "AudioOutputInstaller.psm1"
Import-Module $installerModule -Force -ErrorAction Stop
Import-Module $dependencyModule -Force -ErrorAction Stop

$switchSourcePath = Join-Path $PSScriptRoot "switch-audio.ps1"
$legacySourceRoot = Join-Path $PSScriptRoot "..\komorebi"
$configSourcePath = Resolve-AudioOutputConfigSource `
  -SourceRoot $PSScriptRoot `
  -LegacySourceRoot $legacySourceRoot
foreach ($sourcePath in @($switchSourcePath, $configSourcePath)) {
  if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
    throw "Required audio source file not found: $sourcePath"
  }
}

. $switchSourcePath -NoRun
[void](Get-AudioOutputPatterns -Path $configSourcePath)

$InstallRoot = [IO.Path]::GetFullPath($InstallRoot)
$switchDestinationPath = Join-Path $InstallRoot "switch-audio.ps1"
$configDestinationPath = Join-Path $InstallRoot "audio-output.json"
$powershellPath = Join-Path (
  [Environment]::GetFolderPath("Windows")
) "System32\WindowsPowerShell\v1.0\powershell.exe"
if (-not (Test-Path -LiteralPath $powershellPath -PathType Leaf)) {
  throw "Windows PowerShell is missing: $powershellPath"
}
$arguments = Get-AudioSwitcherPowerShellArguments `
  -ScriptPath $switchDestinationPath
$shortcutPath = Join-Path $ProgramsRoot "Dotfiles Audio Output.lnk"

$hotkey = "CTRL+ALT+F12"
$legacyHotkey = "CTRL+ALT+M"
$shortcutExists = Test-Path -LiteralPath $shortcutPath -PathType Leaf
$shortcutMatches = $shortcutExists -and (
  Test-AudioSwitcherShortcutSpec `
    -ShortcutPath $shortcutPath `
    -ExpectedTarget $powershellPath `
    -ExpectedArguments $arguments `
    -ExpectedWorkingDirectory $InstallRoot `
    -ExpectedHotkey $hotkey
)
$legacyShortcutMatches = $shortcutExists -and (
  Test-AudioSwitcherShortcutSpec `
    -ShortcutPath $shortcutPath `
    -ExpectedTarget $powershellPath `
    -ExpectedArguments $arguments `
    -ExpectedWorkingDirectory $InstallRoot `
    -ExpectedHotkey $legacyHotkey
)
$replaceOwnedLegacyShortcut = $legacyShortcutMatches -and -not $shortcutMatches

if (
  $shortcutExists -and -not $shortcutMatches -and
  -not $legacyShortcutMatches -and -not $Force
) {
  throw "Refusing to replace a modified audio shortcut: $shortcutPath"
}

[void](Install-AudioDeviceModule -RequiredVersion "3.1.0.2")
New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null
$scriptChanged = Install-AudioSwitcherManagedFile `
  -SourcePath $switchSourcePath `
  -DestinationPath $switchDestinationPath
$configChanged = Install-AudioSwitcherManagedFile `
  -SourcePath $configSourcePath `
  -DestinationPath $configDestinationPath
$installedShortcut = Install-AudioSwitcherShortcut `
  -ShortcutPath $shortcutPath `
  -TargetPath $powershellPath `
  -Arguments $arguments `
  -WorkingDirectory $InstallRoot `
  -Hotkey $hotkey `
  -Force:($Force -or $replaceOwnedLegacyShortcut)

[void](& $switchDestinationPath -ValidateOnly)

[pscustomobject]@{
  InstallRoot = $InstallRoot
  Script = $switchDestinationPath
  Configuration = $configDestinationPath
  Shortcut = $installedShortcut
  Hotkey = $hotkey
  ScriptChanged = [bool]$scriptChanged
  ConfigurationChanged = [bool]$configChanged
}
