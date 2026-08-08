param(
  [switch]$ForceConfig = $false,
  [switch]$SkipStart = $false,
  [switch]$SkipAutostart = $false
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$installerModule = Join-Path $PSScriptRoot "KomorebiInstaller.psm1"
Import-Module $installerModule -Force -ErrorAction Stop

function Install-WinGetCommand {
  param(
    [Parameter(Mandatory = $true)]
    [string]$PackageId,

    [Parameter(Mandatory = $true)]
    [string]$ExpectedPath,

    [Parameter(Mandatory = $true)]
    [string]$WingetPath
  )

  if (Test-Path -LiteralPath $ExpectedPath -PathType Leaf) {
    return $false
  }
  if (-not (Test-Path -LiteralPath $WingetPath -PathType Leaf)) {
    throw "The official winget application alias was not found: $WingetPath"
  }

  Write-Host "Installing $PackageId with winget..."
  & $WingetPath install `
    --id $PackageId `
    --exact `
    --source winget `
    --silent `
    --disable-interactivity `
    --accept-source-agreements `
    --accept-package-agreements
  if ($LASTEXITCODE -ne 0) {
    throw "winget failed to install $PackageId (exit code $LASTEXITCODE)."
  }
  if (-not (Test-Path -LiteralPath $ExpectedPath -PathType Leaf)) {
    throw "The expected application was not installed: $ExpectedPath"
  }

  return $true
}

function Assert-KomorebiAutostart {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ShortcutPath,

    [Parameter(Mandatory = $true)]
    [string]$ExpectedTarget
  )

  if (-not (Test-KomorebiShortcutSpec `
    -ShortcutPath $ShortcutPath `
    -ExpectedTarget $ExpectedTarget `
    -AllowedArguments @("start --bar --whkd")
  )) {
    throw "Komorebi autostart shortcut did not match the expected specification."
  }
}

function Restore-FileSnapshot {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [Parameter(Mandatory = $true)]
    [bool]$Existed,

    [string]$SnapshotPath
  )

  if ($Existed) {
    Copy-Item -LiteralPath $SnapshotPath -Destination $Path -Force
  } elseif (Test-Path -LiteralPath $Path -PathType Leaf) {
    Remove-Item -LiteralPath $Path -Force
  }
}

function Undo-WinGetInstall {
  param(
    [Parameter(Mandatory = $true)]
    [bool]$InstalledNow,

    [Parameter(Mandatory = $true)]
    [string]$PackageId,

    [Parameter(Mandatory = $true)]
    [string]$WingetPath
  )

  if (-not $InstalledNow) {
    return
  }
  & $WingetPath uninstall `
    --id $PackageId `
    --exact `
    --source winget `
    --silent `
    --disable-interactivity
  if ($LASTEXITCODE -ne 0) {
    throw "winget failed to roll back $PackageId (exit code $LASTEXITCODE)."
  }
}

if ($env:OS -ne "Windows_NT") {
  throw "This installer must run in Windows PowerShell."
}

$configHome = Resolve-KomorebiConfigHome
$metadataDirectory = Join-Path $env:LOCALAPPDATA "dotfiles\komorebi"
$metadataPath = Join-Path $metadataDirectory "install.json"
$previousManifest = Get-KomorebiManifest -Path $metadataPath
$wingetPath = Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps\winget.exe"
$komorebicPath = Join-Path $env:ProgramFiles "komorebi\bin\komorebic.exe"
$komorebicNoConsolePath = Join-Path $env:ProgramFiles (
  "komorebi\bin\komorebic-no-console.exe"
)
$whkdPath = Join-Path $env:ProgramFiles "whkd\bin\whkd.exe"
$barPath = Join-Path $env:ProgramFiles "komorebi\bin\komorebi-bar.exe"
$masirPath = Join-Path $env:ProgramFiles "masir\bin\masir.exe"

$previousKomorebiHome = [Environment]::GetEnvironmentVariable(
  "KOMOREBI_CONFIG_HOME",
  "User"
)
$previousWhkdHome = [Environment]::GetEnvironmentVariable(
  "WHKD_CONFIG_HOME",
  "User"
)
$originalKomorebiHome = $previousKomorebiHome
$originalWhkdHome = $previousWhkdHome
if (
  $previousManifest -and
  $previousManifest.PSObject.Properties["previous_environment"]
) {
  $savedEnvironment = $previousManifest.previous_environment
  if ($savedEnvironment.PSObject.Properties["KOMOREBI_CONFIG_HOME"]) {
    $originalKomorebiHome = $savedEnvironment.KOMOREBI_CONFIG_HOME
  }
  if ($savedEnvironment.PSObject.Properties["WHKD_CONFIG_HOME"]) {
    $originalWhkdHome = $savedEnvironment.WHKD_CONFIG_HOME
  }
}
foreach ($entry in @(
  @{
    Name = "KOMOREBI_CONFIG_HOME"
    Value = $previousKomorebiHome
  },
  @{
    Name = "WHKD_CONFIG_HOME"
    Value = $previousWhkdHome
  }
)) {
  if (
    -not [string]::IsNullOrWhiteSpace($entry.Value) -and
    $entry.Value -ne $configHome
  ) {
    throw "$($entry.Name) already points elsewhere: $($entry.Value)"
  }
}

$startupDirectory = [Environment]::GetFolderPath("Startup")
$startupShortcutPath = Join-Path $startupDirectory "komorebi.lnk"
$oldAutostartOwned = $false
if (
  $previousManifest -and
  $previousManifest.PSObject.Properties["autostart_owned"]
) {
  $oldAutostartOwned = [bool]$previousManifest.autostart_owned
} elseif ($previousManifest -and (Test-Path -LiteralPath $startupShortcutPath)) {
  # Backward compatibility for manifests created before ownership was recorded.
  $legacyConfigPath = Join-Path $configHome "komorebi.json"
  $oldAutostartOwned = Test-KomorebiShortcutSpec `
    -ShortcutPath $startupShortcutPath `
    -ExpectedTarget $komorebicNoConsolePath `
    -AllowedArguments @(
      "start --bar --whkd",
      "start --bar --whkd --masir",
      "start --whkd --bar --masir",
      "start --whkd --masir",
      "start --whkd",
      "start --config $legacyConfigPath --whkd"
    )
}
if (
  -not $SkipAutostart -and
  (Test-Path -LiteralPath $startupShortcutPath) -and
  -not $oldAutostartOwned
) {
  throw "Refusing to replace a pre-existing Komorebi autostart shortcut."
}

$applicationsPath = Join-Path $configHome "applications.json"
$komorebiInstalledNow = $false
$whkdInstalledNow = $false
$masirInstalledNow = $false
$applicationsCreatedNow = $false
$configSourcePath = Join-Path $PSScriptRoot "komorebi.json"
$barConfigSourcePath = Join-Path $PSScriptRoot "komorebi.bar.json"
$audioScriptSourcePath = Join-Path $PSScriptRoot "switch-audio.ps1"
$managedFileSpecs = @(Get-KomorebiManagedFileSpecification `
  -SourceRoot $PSScriptRoot `
  -ConfigHome $configHome `
  -Manifest $previousManifest)
$audioConfigSourcePath = [string](@(
  $managedFileSpecs | Where-Object { $_.Name -eq "audio-output.json" }
) | Select-Object -First 1).SourcePath
try {
  $komorebiInstalledNow = Install-WinGetCommand `
    -PackageId "LGUG2Z.komorebi" `
    -ExpectedPath $komorebicPath `
    -WingetPath $wingetPath
  $whkdInstalledNow = Install-WinGetCommand `
    -PackageId "LGUG2Z.whkd" `
    -ExpectedPath $whkdPath `
    -WingetPath $wingetPath
  $masirInstalledNow = Install-WinGetCommand `
    -PackageId "LGUG2Z.masir" `
    -ExpectedPath $masirPath `
    -WingetPath $wingetPath

  $env:KOMOREBI_CONFIG_HOME = $configHome
  $env:WHKD_CONFIG_HOME = $configHome
  New-Item -ItemType Directory -Force -Path $configHome | Out-Null
  if (-not (Test-Path -LiteralPath $applicationsPath -PathType Leaf)) {
    Invoke-Komorebic -Path $komorebicPath -Arguments @("fetch-asc")
    $applicationsCreatedNow = $true
  }

  Invoke-Komorebic -Path $komorebicPath -Arguments @(
    "check",
    "--komorebi-config",
    $configSourcePath
  )
  try {
    [void](Get-Content -LiteralPath $barConfigSourcePath -Raw | ConvertFrom-Json)
  } catch {
    throw "Cannot parse the Komorebi bar configuration: $barConfigSourcePath"
  }
  . $audioScriptSourcePath -NoRun
  [void](Get-AudioOutputPatterns -Path $audioConfigSourcePath)
  Install-AudioDeviceModule -RequiredVersion "3.1.0.2" | Out-Null
} catch {
  $preflightError = $_
  if ($applicationsCreatedNow -and (Test-Path -LiteralPath $applicationsPath)) {
    Remove-Item -LiteralPath $applicationsPath -Force
  }
  foreach ($package in @(
    @{
      InstalledNow = $masirInstalledNow
      Id = "LGUG2Z.masir"
    },
    @{
      InstalledNow = $whkdInstalledNow
      Id = "LGUG2Z.whkd"
    },
    @{
      InstalledNow = $komorebiInstalledNow
      Id = "LGUG2Z.komorebi"
    }
  )) {
    try {
      Undo-WinGetInstall `
        -InstalledNow $package.InstalledNow `
        -PackageId $package.Id `
        -WingetPath $wingetPath
    } catch {
      Write-Warning "Failed to roll back package: $($package.Id)"
    }
  }
  throw $preflightError
}

$oldKomorebiOwned = $false
$oldWhkdOwned = $false
$oldMasirOwned = $false
$oldCreatedAt = $null
if ($previousManifest) {
  if ($previousManifest.PSObject.Properties["packages"]) {
    if ($previousManifest.packages.PSObject.Properties["komorebi"]) {
      $oldKomorebiOwned = [bool]$previousManifest.packages.komorebi
    }
    if ($previousManifest.packages.PSObject.Properties["whkd"]) {
      $oldWhkdOwned = [bool]$previousManifest.packages.whkd
    }
    if ($previousManifest.packages.PSObject.Properties["masir"]) {
      $oldMasirOwned = [bool]$previousManifest.packages.masir
    }
  }
  if ($previousManifest.PSObject.Properties["created_at"]) {
    $oldCreatedAt = [string]$previousManifest.created_at
  }
}
if ([string]::IsNullOrWhiteSpace($oldCreatedAt)) {
  $oldCreatedAt = (Get-Date).ToString("o")
}

$barConfigPath = Resolve-KomorebiManagedPath `
  -ConfigHome $configHome `
  -Name "komorebi.bar.json"

New-Item -ItemType Directory -Force -Path $metadataDirectory | Out-Null
$rollbackRoot = Join-Path $env:TEMP (
  "komorebi_install_{0}" -f [guid]::NewGuid().ToString("N")
)
New-Item -ItemType Directory -Path $rollbackRoot | Out-Null
$metadataExisted = Test-Path -LiteralPath $metadataPath -PathType Leaf
$metadataSnapshot = Join-Path $rollbackRoot "install.json"
if ($metadataExisted) {
  Copy-Item -LiteralPath $metadataPath -Destination $metadataSnapshot
}
$autostartExisted = Test-Path -LiteralPath $startupShortcutPath -PathType Leaf
$autostartSnapshot = Join-Path $rollbackRoot "komorebi.lnk"
if ($autostartExisted) {
  Copy-Item -LiteralPath $startupShortcutPath -Destination $autostartSnapshot
}
$komorebiWasRunning = [bool](Get-Process -Name "komorebi" -ErrorAction SilentlyContinue)
$whkdWasRunning = [bool](Get-Process -Name "whkd" -ErrorAction SilentlyContinue)
$barWasRunning = [bool](Get-Process -Name "komorebi-bar" -ErrorAction SilentlyContinue)
$masirWasRunning = [bool](Get-Process -Name "masir" -ErrorAction SilentlyContinue)

try {
  $postInstall = {
    param($results)

    $managedFiles = @()
    for ($index = 0; $index -lt $managedFileSpecs.Count; $index++) {
      $result = $results[$index]
      $managedFiles += @{
        name = $managedFileSpecs[$index].Name
        path = $result.DestinationPath
        sha256 = $result.Sha256
      }
      if ($result.BackupPath) {
        Write-Host "Backed up config: $($result.BackupPath)"
      }
    }

    $configPath = Resolve-KomorebiManagedPath `
      -ConfigHome $configHome `
      -Name "komorebi.json"
    Invoke-Komorebic -Path $komorebicPath -Arguments @(
      "check",
      "--komorebi-config",
      $configPath
    )

    [Environment]::SetEnvironmentVariable(
      "KOMOREBI_CONFIG_HOME",
      $configHome,
      "User"
    )
    [Environment]::SetEnvironmentVariable(
      "WHKD_CONFIG_HOME",
      $configHome,
      "User"
    )

    if (-not $SkipStart) {
      if (Get-Process -Name "komorebi" -ErrorAction SilentlyContinue) {
        Invoke-Komorebic `
          -Path $komorebicPath `
          -Arguments @("replace-configuration", $configPath)
        Get-Process -Name "whkd" -ErrorAction SilentlyContinue |
          Stop-Process -Force
        Start-Process -FilePath $whkdPath -WindowStyle Hidden | Out-Null
        Get-Process -Name "komorebi-bar" -ErrorAction SilentlyContinue |
          Stop-Process -Force
        Start-Process `
          -FilePath $barPath `
          -ArgumentList (Get-KomorebiBarArgumentString -ConfigPath $barConfigPath) `
          -WindowStyle Hidden | Out-Null
      } else {
        Invoke-Komorebic `
          -Path $komorebicPath `
          -Arguments @("start", "-c", $configPath, "--whkd", "--bar")
      }
      Get-Process -Name "masir" -ErrorAction SilentlyContinue |
        Stop-Process -Force -PassThru |
        Wait-Process -Timeout 5 -ErrorAction SilentlyContinue
      if (Get-Process -Name "masir" -ErrorAction SilentlyContinue) {
        throw "masir is still running after focus-follows-mouse was disabled."
      }
      Wait-KomorebiProcessSet -Names @("komorebi", "whkd", "komorebi-bar") -StableMilliseconds 1000
    }

    $autostartOwned = $oldAutostartOwned
    if (-not $SkipAutostart) {
      Invoke-Komorebic `
        -Path $komorebicPath `
        -Arguments @("enable-autostart", "--whkd", "--bar")
      Assert-KomorebiAutostart `
        -ShortcutPath $startupShortcutPath `
        -ExpectedTarget $komorebicNoConsolePath
      $autostartOwned = $true
    }

    $manifest = @{
      version = 3
      config_home = $configHome
      created_at = $oldCreatedAt
      updated_at = (Get-Date).ToString("o")
      files = $managedFiles
      packages = @{
        komorebi = [bool]($oldKomorebiOwned -or $komorebiInstalledNow)
        whkd = [bool]($oldWhkdOwned -or $whkdInstalledNow)
        masir = [bool]($oldMasirOwned -or $masirInstalledNow)
      }
      autostart_owned = [bool]$autostartOwned
      previous_environment = @{
        KOMOREBI_CONFIG_HOME = $originalKomorebiHome
        WHKD_CONFIG_HOME = $originalWhkdHome
      }
    }
    Write-KomorebiManifest -Manifest $manifest -Path $metadataPath
  }

  Install-KomorebiManagedFilesTransaction `
    -Files $managedFileSpecs `
    -Force:$ForceConfig `
    -AfterInstall $postInstall | Out-Null
} catch {
  $installError = $_
  [Environment]::SetEnvironmentVariable(
    "KOMOREBI_CONFIG_HOME",
    $previousKomorebiHome,
    "User"
  )
  [Environment]::SetEnvironmentVariable(
    "WHKD_CONFIG_HOME",
    $previousWhkdHome,
    "User"
  )
  Restore-FileSnapshot `
    -Path $metadataPath `
    -Existed $metadataExisted `
    -SnapshotPath $metadataSnapshot
  Restore-FileSnapshot `
    -Path $startupShortcutPath `
    -Existed $autostartExisted `
    -SnapshotPath $autostartSnapshot
  if ($applicationsCreatedNow -and (Test-Path -LiteralPath $applicationsPath)) {
    Remove-Item -LiteralPath $applicationsPath -Force
  }

  try {
    $configPath = Resolve-KomorebiManagedPath `
      -ConfigHome $configHome `
      -Name "komorebi.json"
    $komorebiIsRunning = [bool](
      Get-Process -Name "komorebi" -ErrorAction SilentlyContinue
    )
    if (-not $komorebiWasRunning -and $komorebiIsRunning) {
      Invoke-Komorebic `
        -Path $komorebicPath `
        -Arguments @("stop", "--whkd", "--bar", "--masir")
    } elseif ($komorebiWasRunning -and (Test-Path -LiteralPath $configPath)) {
      if (Get-Process -Name "komorebi" -ErrorAction SilentlyContinue) {
        Invoke-Komorebic `
          -Path $komorebicPath `
          -Arguments @("replace-configuration", $configPath)
      } else {
        Invoke-Komorebic `
          -Path $komorebicPath `
          -Arguments @("start", "-c", $configPath, "--whkd")
      }
    }
    if (
      $whkdWasRunning -and
      -not (Get-Process -Name "whkd" -ErrorAction SilentlyContinue)
    ) {
      Start-Process -FilePath $whkdPath -WindowStyle Hidden | Out-Null
    } elseif (
      -not $whkdWasRunning -and
      (Get-Process -Name "whkd" -ErrorAction SilentlyContinue)
    ) {
      Get-Process -Name "whkd" -ErrorAction SilentlyContinue |
        Stop-Process -Force
    }
    if (
      $masirWasRunning -and
      -not (Get-Process -Name "masir" -ErrorAction SilentlyContinue)
    ) {
      Start-Process -FilePath $masirPath -WindowStyle Hidden | Out-Null
    } elseif (
      -not $masirWasRunning -and
      (Get-Process -Name "masir" -ErrorAction SilentlyContinue)
    ) {
      Get-Process -Name "masir" -ErrorAction SilentlyContinue |
        Stop-Process -Force
    }
    if (
      $barWasRunning -and
      -not (Get-Process -Name "komorebi-bar" -ErrorAction SilentlyContinue)
    ) {
      Start-Process `
        -FilePath $barPath `
        -ArgumentList (Get-KomorebiBarArgumentString -ConfigPath $barConfigPath) `
        -WindowStyle Hidden | Out-Null
    } elseif (
      -not $barWasRunning -and
      (Get-Process -Name "komorebi-bar" -ErrorAction SilentlyContinue)
    ) {
      Get-Process -Name "komorebi-bar" -ErrorAction SilentlyContinue |
        Stop-Process -Force
    }
  } catch {
    Write-Warning "Failed to restore the previous Komorebi runtime."
  }

  foreach ($package in @(
    @{
      InstalledNow = $masirInstalledNow
      Id = "LGUG2Z.masir"
    },
    @{
      InstalledNow = $whkdInstalledNow
      Id = "LGUG2Z.whkd"
    },
    @{
      InstalledNow = $komorebiInstalledNow
      Id = "LGUG2Z.komorebi"
    }
  )) {
    try {
      Undo-WinGetInstall `
        -InstalledNow $package.InstalledNow `
        -PackageId $package.Id `
        -WingetPath $wingetPath
    } catch {
      Write-Warning "Failed to roll back package: $($package.Id)"
    }
  }
  throw $installError
} finally {
  if (Test-Path -LiteralPath $rollbackRoot) {
    Remove-Item -LiteralPath $rollbackRoot -Recurse -Force
  }
}

$configPath = Resolve-KomorebiManagedPath `
  -ConfigHome $configHome `
  -Name "komorebi.json"
Write-Host "Komorebi config : $configPath"
Write-Host "whkd config     : $(Join-Path $configHome 'whkdrc')"
Write-Host "Installer state : $metadataPath"
if (-not $SkipStart) {
  Write-Host "Komorebi, whkd, and the bar are running."
}
if (-not $SkipAutostart) {
  Write-Host "Komorebi, whkd, and the bar will start at login."
}
