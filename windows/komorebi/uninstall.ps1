param(
  [switch]$RemoveManagedConfig = $false,
  [switch]$RestoreEnvironment = $false,
  [switch]$RemovePackages = $false
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$installerModule = Join-Path $PSScriptRoot "KomorebiInstaller.psm1"
Import-Module $installerModule -Force -ErrorAction Stop

function Write-KomorebiManifest {
  param(
    [Parameter(Mandatory = $true)]
    [object]$Manifest,

    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  $temporaryPath = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
  try {
    $Manifest |
      ConvertTo-Json -Depth 8 |
      Set-Content -LiteralPath $temporaryPath -Encoding UTF8
    Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) {
      Remove-Item -LiteralPath $temporaryPath -Force
    }
  }
}

$metadataPath = Join-Path $env:LOCALAPPDATA "dotfiles\komorebi\install.json"
$manifest = Get-KomorebiManifest -Path $metadataPath
$komorebicPath = Join-Path $env:ProgramFiles "komorebi\bin\komorebic.exe"
$komorebicNoConsolePath = Join-Path $env:ProgramFiles (
  "komorebi\bin\komorebic-no-console.exe"
)
$wingetPath = Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps\winget.exe"
$startupShortcutPath = Join-Path (
  [Environment]::GetFolderPath("Startup")
) "komorebi.lnk"

if (
  (Test-Path -LiteralPath $komorebicPath -PathType Leaf) -and
  (Get-Process -Name "komorebi" -ErrorAction SilentlyContinue)
) {
  & $komorebicPath stop --whkd --bar --masir
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to stop Komorebi."
  }
}
foreach ($processName in @("whkd", "komorebi-bar", "masir")) {
  Get-Process -Name $processName -ErrorAction SilentlyContinue |
    Stop-Process -Force
  if (Get-Process -Name $processName -ErrorAction SilentlyContinue) {
    throw "$processName is still running after the stop request."
  }
}

$autostartOwned = $false
if (
  $manifest -and
  $manifest.PSObject.Properties["autostart_owned"]
) {
  $autostartOwned = [bool]$manifest.autostart_owned
} elseif ($manifest) {
  $legacyConfigPath = Join-Path ([string]$manifest.config_home) "komorebi.json"
  $autostartOwned = Test-KomorebiShortcutSpec `
    -ShortcutPath $startupShortcutPath `
    -ExpectedTarget $komorebicNoConsolePath `
    -AllowedArguments @(
      "start --bar --whkd --masir",
      "start --whkd --bar --masir",
      "start --whkd --masir",
      "start --whkd",
      "start --config $legacyConfigPath --whkd"
    )
}
if (
  $autostartOwned -and
  (Test-Path -LiteralPath $komorebicPath -PathType Leaf)
) {
  & $komorebicPath disable-autostart
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to disable Komorebi autostart."
  }
  if ($manifest.PSObject.Properties["autostart_owned"]) {
    $manifest.autostart_owned = $false
  } else {
    $manifest | Add-Member `
      -MemberType NoteProperty `
      -Name "autostart_owned" `
      -Value $false
  }
  $manifest.updated_at = (Get-Date).ToString("o")
  Write-KomorebiManifest -Manifest $manifest -Path $metadataPath
}

if ($RemoveManagedConfig -and $manifest) {
  $configHome = Resolve-KomorebiConfigHome -Path ([string]$manifest.config_home)
  foreach ($file in @($manifest.files)) {
    $managedPath = Resolve-KomorebiManagedPath `
      -ConfigHome $configHome `
      -Name ([string]$file.name)
    if (-not (Test-Path -LiteralPath $managedPath -PathType Leaf)) {
      continue
    }
    $currentSha256 = Get-KomorebiFileSha256 -Path $managedPath
    if ($currentSha256 -eq [string]$file.sha256) {
      Remove-Item -LiteralPath $managedPath -Force
      Write-Host "Removed managed config: $managedPath"
    } else {
      Write-Warning "Keeping user-modified config: $managedPath"
    }
  }
}

if ($RestoreEnvironment -and $manifest) {
  $previousEnvironment = $manifest.previous_environment
  foreach ($name in @("KOMOREBI_CONFIG_HOME", "WHKD_CONFIG_HOME")) {
    $currentValue = [Environment]::GetEnvironmentVariable($name, "User")
    if ($currentValue -ne [string]$manifest.config_home) {
      Write-Warning "Keeping externally modified environment variable: $name"
      continue
    }
    $previousValue = $previousEnvironment.$name
    [Environment]::SetEnvironmentVariable($name, $previousValue, "User")
  }
}

if ($RemovePackages) {
  if (-not $manifest) {
    throw "Cannot verify package ownership without installer state: $metadataPath"
  }
  if (-not (Test-Path -LiteralPath $wingetPath -PathType Leaf)) {
    throw "The official winget application alias was not found: $wingetPath"
  }
  foreach ($package in @(
    @{
      Name = "masir"
      Id = "LGUG2Z.masir"
    },
    @{
      Name = "whkd"
      Id = "LGUG2Z.whkd"
    },
    @{
      Name = "komorebi"
      Id = "LGUG2Z.komorebi"
    }
  )) {
    if (-not (Test-KomorebiManifestPackageOwned `
      -Manifest $manifest `
      -Name $package.Name
    )) {
      Write-Host "Keeping pre-existing package: $($package.Id)"
      continue
    }
    & $wingetPath uninstall `
      --id $package.Id `
      --exact `
      --source winget `
      --silent `
      --disable-interactivity
    if ($LASTEXITCODE -ne 0) {
      throw "winget failed to uninstall $($package.Id)."
    }
    $manifest.packages.($package.Name) = $false
    $manifest.updated_at = (Get-Date).ToString("o")
    Write-KomorebiManifest -Manifest $manifest -Path $metadataPath
  }
}

if ($manifest) {
  $manifest.updated_at = (Get-Date).ToString("o")
  Write-KomorebiManifest -Manifest $manifest -Path $metadataPath
}

Write-Host "Komorebi, whkd, the bar, and masir stopped."
if ($autostartOwned) {
  Write-Host "Installer-owned autostart disabled."
}
Write-Host "Installer state kept at: $metadataPath"
