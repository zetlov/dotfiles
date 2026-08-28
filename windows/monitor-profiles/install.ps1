[CmdletBinding()]
param(
  [string]$InstallRoot = (
    Join-Path $env:LOCALAPPDATA "dotfiles\monitor-profiles"
  ),

  [switch]$Reinitialize
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($env:OS -ne "Windows_NT") {
  throw "This script must run on Windows."
}

$sourceModule = Join-Path $PSScriptRoot "MonitorProfiles.psm1"
$sourceSwitchScript = Join-Path $PSScriptRoot "Switch-MonitorProfile.ps1"
$sourceShortcutScripts = @(
  Join-Path $PSScriptRoot "Switch-MonitorProfile-All.ps1"
  Join-Path $PSScriptRoot "Switch-MonitorProfile-LeftCenter.ps1"
  Join-Path $PSScriptRoot "Switch-MonitorProfile-RightOnly.ps1"
)
$managedSources = @($sourceModule, $sourceSwitchScript) + $sourceShortcutScripts
foreach ($sourcePath in $managedSources) {
  if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
    throw "Required monitor profile file not found: $sourcePath"
  }
}
Import-Module $sourceModule -Force -ErrorAction Stop

$InstallRoot = Resolve-MonitorProfileInstallRoot -Path $InstallRoot
$release = Get-DisplayConfigReleaseSpec
$dependencyParent = Join-Path $InstallRoot "dependencies\DisplayConfig"
$dependencyRoot = Join-Path $dependencyParent $release.Version
$temporaryRoot = Join-Path $env:TEMP (
  "monitor-profiles-" + [guid]::NewGuid().ToString("N")
)
$archivePath = Join-Path $temporaryRoot "DisplayConfig.zip"
$extractedRoot = Join-Path $temporaryRoot "extracted"
$stagingRoot = Join-Path $temporaryRoot "dependency.new"
$backupRoot = Join-Path $temporaryRoot "dependency.old"
$hadDependency = Test-Path -LiteralPath $dependencyRoot -PathType Container
$dependencyReady = $false

try {
  New-Item -ItemType Directory -Path $temporaryRoot | Out-Null
  Invoke-WebRequest -Uri $release.Uri -OutFile $archivePath
  Assert-MonitorProfileFileHash `
    -Path $archivePath `
    -ExpectedSha256 $release.Sha256
  Expand-Archive -LiteralPath $archivePath -DestinationPath $extractedRoot

  $requiredPayload = @(
    "DisplayConfig.deps.json",
    "DisplayConfig.dll",
    "DisplayConfig.psd1",
    "DisplayConfigFormat.ps1xml",
    "DisplayConfigType.ps1xml",
    "en-US\DisplayConfig.dll-Help.xml"
  )
  foreach ($relativePath in $requiredPayload) {
    $payloadPath = Join-Path $extractedRoot $relativePath
    if (-not (Test-Path -LiteralPath $payloadPath -PathType Leaf)) {
      throw "DisplayConfig payload is missing: $relativePath"
    }
  }

  New-Item -ItemType Directory -Path $stagingRoot | Out-Null
  foreach ($relativePath in $requiredPayload) {
    $destination = Join-Path $stagingRoot $relativePath
    New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force |
      Out-Null
    Copy-Item -LiteralPath (Join-Path $extractedRoot $relativePath) `
      -Destination $destination
  }
  $manifest = Test-ModuleManifest `
    -Path (Join-Path $stagingRoot "DisplayConfig.psd1") `
    -ErrorAction Stop
  if ($manifest.Version.ToString() -ne $release.Version) {
    throw "DisplayConfig manifest version mismatch."
  }

  $dependencyMatches = $hadDependency
  if ($dependencyMatches) {
    foreach ($relativePath in $requiredPayload) {
      $installedPath = Join-Path $dependencyRoot $relativePath
      if (-not (Test-Path -LiteralPath $installedPath -PathType Leaf)) {
        $dependencyMatches = $false
        break
      }
      $stagedHash = (Get-FileHash `
        -LiteralPath (Join-Path $stagingRoot $relativePath) `
        -Algorithm SHA256
      ).Hash
      $installedHash = (Get-FileHash `
        -LiteralPath $installedPath `
        -Algorithm SHA256
      ).Hash
      if ($stagedHash -ne $installedHash) {
        $dependencyMatches = $false
        break
      }
    }
  }

  New-Item -ItemType Directory -Path $dependencyParent -Force | Out-Null
  if ($dependencyMatches) {
    Remove-Item -LiteralPath $stagingRoot -Recurse -Force
    $dependencyReady = $true
  } else {
    if ($hadDependency) {
      Move-Item -LiteralPath $dependencyRoot -Destination $backupRoot
    }
    Move-Item -LiteralPath $stagingRoot -Destination $dependencyRoot
    $dependencyReady = $true
  }

  New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null
  foreach ($sourcePath in $managedSources) {
    Copy-Item -LiteralPath $sourcePath -Destination $InstallRoot -Force
  }

  $configurationPath = Join-Path $InstallRoot "config.json"
  if ($Reinitialize -or -not (
    Test-Path -LiteralPath $configurationPath -PathType Leaf
  )) {
    Initialize-MonitorProfileConfiguration -InstallRoot $InstallRoot | Out-Null
  }

  [pscustomobject]@{
    dependency = "DisplayConfig"
    version = $release.Version
    uri = $release.Uri.AbsoluteUri
    sha256 = $release.Sha256
    installedAt = (Get-Date).ToString("o")
  } | ConvertTo-Json | Set-Content `
    -LiteralPath (Join-Path $InstallRoot "install.json") `
    -Encoding UTF8
} finally {
  if (-not $dependencyReady -and $hadDependency -and (
    Test-Path -LiteralPath $backupRoot -PathType Container
  )) {
    Move-Item -LiteralPath $backupRoot -Destination $dependencyRoot
  } elseif (-not $dependencyReady -and (
    Test-Path -LiteralPath $dependencyRoot -PathType Container
  )) {
    Remove-Item -LiteralPath $dependencyRoot -Recurse -Force
  }
  if (Test-Path -LiteralPath $temporaryRoot) {
    Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
  }
}

[pscustomobject]@{
  Version = $release.Version
  Module = Join-Path $dependencyRoot "DisplayConfig.psd1"
  ProfileRoot = Join-Path $InstallRoot "profiles"
  Configuration = Join-Path $InstallRoot "config.json"
}
