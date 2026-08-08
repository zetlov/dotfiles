[CmdletBinding()]
param(
  [string]$UserProfile = $env:USERPROFILE
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($env:OS -ne "Windows_NT") {
  throw "This font installer must run in Windows PowerShell."
}
if ([string]::IsNullOrWhiteSpace($UserProfile)) {
  throw "UserProfile is required."
}

$installerModule = Join-Path $PSScriptRoot "FontInstaller.psm1"
Import-Module $installerModule -Force -ErrorAction Stop

$resolvedUserProfile = [System.IO.Path]::GetFullPath($UserProfile)
$userFontsDirectory = Join-Path (
  Join-Path $resolvedUserProfile "AppData\Local"
) "Microsoft\Windows\Fonts"
$windowsFontsDirectory = Join-Path $env:WINDIR "Fonts"
$userRegistryPath = "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts"
$registryPaths = @(
  $userRegistryPath,
  "HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Fonts"
)
$changedFontPaths = @()
$packageResults = @()

foreach ($package in @(Get-WezTermFontPackages)) {
  $missingFonts = @(
    $package.Fonts | Where-Object {
      -not (Test-FontRegistration `
        -RegistryName $_.RegistryName `
        -RegistryPaths $registryPaths `
        -WindowsFontsDirectory $windowsFontsDirectory)
    }
  )
  if ($missingFonts.Count -eq 0) {
    Write-Host "$($package.Name) $($package.Version): already installed"
    $packageResults += [PSCustomObject]@{
      Name = $package.Name
      Version = $package.Version
      Changed = $false
      InstalledFiles = @()
    }
    continue
  }

  $temporaryDirectory = Join-Path (
    [System.IO.Path]::GetTempPath()
  ) ("dotfiles-font-" + [guid]::NewGuid().ToString("N"))
  $archivePath = Join-Path $temporaryDirectory "font.zip"
  $extractDirectory = Join-Path $temporaryDirectory "extracted"
  $installedFiles = @()
  try {
    New-Item -ItemType Directory -Path $temporaryDirectory | Out-Null
    Write-Host "Downloading $($package.Name) $($package.Version)..."
    Invoke-WebRequest `
      -Uri $package.Uri `
      -OutFile $archivePath `
      -UseBasicParsing
    [void](Assert-FontArchiveHash `
      -Path $archivePath `
      -ExpectedSha256 $package.Sha256)
    Expand-Archive `
      -LiteralPath $archivePath `
      -DestinationPath $extractDirectory

    foreach ($font in $missingFonts) {
      $matches = @(
        Get-ChildItem `
          -LiteralPath $extractDirectory `
          -Recurse `
          -File | Where-Object Name -eq $font.FileName
      )
      if ($matches.Count -ne 1) {
        throw (
          "Expected exactly one $($font.FileName) in the verified archive; " +
          "found $($matches.Count)."
        )
      }
      $result = Install-UserFontFile `
        -SourcePath $matches[0].FullName `
        -RegistryName $font.RegistryName `
        -FontsDirectory $userFontsDirectory `
        -RegistryPath $userRegistryPath
      if ($result.Changed) {
        $installedFiles += $result.DestinationPath
        $changedFontPaths += $result.DestinationPath
      }
    }
  } finally {
    if (Test-Path -LiteralPath $temporaryDirectory -PathType Container) {
      Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force
    }
  }

  $packageResults += [PSCustomObject]@{
    Name = $package.Name
    Version = $package.Version
    Changed = $installedFiles.Count -gt 0
    InstalledFiles = $installedFiles
  }
}

if ($changedFontPaths.Count -gt 0) {
  Publish-UserFontChanges -FontPaths $changedFontPaths
  Write-Host "Close all WezTerm windows before validating the new fonts."
}

$packageResults
