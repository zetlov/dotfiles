param(
  [switch]$Force = $false,
  [switch]$Restart = $true
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$rollbackSafetyModule = Join-Path $PSScriptRoot "..\rollback\RollbackSafety.psm1"
Import-Module $rollbackSafetyModule -Force -ErrorAction Stop
Assert-GlazeWMInactive

$installerModule = Join-Path $PSScriptRoot "KomorebiInstaller.psm1"
Import-Module $installerModule -Force -ErrorAction Stop
$audioInstallerModule = Join-Path `
  $PSScriptRoot `
  "..\audio\AudioOutputInstaller.psm1"
Import-Module $audioInstallerModule -Force -ErrorAction Stop

$metadataPath = Join-Path $env:LOCALAPPDATA "dotfiles\komorebi\install.json"
$manifest = Get-KomorebiManifest -Path $metadataPath
if (-not $manifest) {
  throw "Installer state is missing. Run install.ps1 first: $metadataPath"
}

$komorebicPath = Join-Path $env:ProgramFiles "komorebi\bin\komorebic.exe"
$komorebicNoConsolePath = Join-Path $env:ProgramFiles (
  "komorebi\bin\komorebic-no-console.exe"
)
$whkdPath = Join-Path $env:ProgramFiles "whkd\bin\whkd.exe"
$barPath = Join-Path $env:ProgramFiles "komorebi\bin\komorebi-bar.exe"
$masirPath = Join-Path $env:ProgramFiles "masir\bin\masir.exe"
if (-not (Test-Path -LiteralPath $komorebicPath -PathType Leaf)) {
  throw "The official Komorebi executable is missing: $komorebicPath"
}
if (-not (Test-Path -LiteralPath $whkdPath -PathType Leaf)) {
  throw "The official whkd executable is missing: $whkdPath"
}
if (-not (Test-Path -LiteralPath $barPath -PathType Leaf)) {
  throw "The official Komorebi bar executable is missing: $barPath"
}
if (-not (Test-Path -LiteralPath $masirPath -PathType Leaf)) {
  throw "The official masir executable is missing: $masirPath"
}

$startupShortcutPath = Join-Path (
  [Environment]::GetFolderPath("Startup")
) "komorebi.lnk"
$autostartProperty = $manifest.PSObject.Properties["autostart_owned"]
$autostartOwned = $null -ne $autostartProperty -and [bool]$autostartProperty.Value
$autostartExisted = Test-Path -LiteralPath $startupShortcutPath -PathType Leaf
if (
  $autostartOwned -and
  $autostartExisted -and
  -not (Test-KomorebiShortcutSpec `
    -ShortcutPath $startupShortcutPath `
    -ExpectedTarget $komorebicNoConsolePath `
    -AllowedArguments @(
      "start --bar --whkd",
      "start --bar --whkd --masir",
      "start --whkd --bar --masir",
      "start --whkd --masir"
    )
  )
) {
  throw "Refusing to replace a modified Komorebi autostart shortcut."
}

$configHome = Resolve-KomorebiConfigHome -Path ([string]$manifest.config_home)
$env:KOMOREBI_CONFIG_HOME = $configHome
$env:WHKD_CONFIG_HOME = $configHome
$configSourcePath = Join-Path $PSScriptRoot "komorebi.json"
$barConfigSourcePath = Join-Path $PSScriptRoot "komorebi.bar.json"
$audioScriptSourcePath = Join-Path $PSScriptRoot "switch-audio.ps1"
$managedFileSpecs = @(Get-KomorebiManagedFileSpecification `
  -SourceRoot $PSScriptRoot `
  -ConfigHome $configHome `
  -Manifest $manifest)
$audioConfigSourcePath = [string](@(
  $managedFileSpecs | Where-Object { $_.Name -eq "audio-output.json" }
) | Select-Object -First 1).SourcePath
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

$barConfigPath = Resolve-KomorebiManagedPath `
  -ConfigHome $configHome `
  -Name "komorebi.bar.json"
$restartPath = Resolve-KomorebiManagedPath `
  -ConfigHome $configHome `
  -Name "restart.ps1"
$restartSourcePath = Join-Path $PSScriptRoot "restart.ps1"

$manifestSnapshot = "$metadataPath.$([guid]::NewGuid().ToString('N')).bak"
Copy-Item -LiteralPath $metadataPath -Destination $manifestSnapshot
$autostartSnapshot = "$startupShortcutPath.$([guid]::NewGuid().ToString('N')).bak"
if ($autostartOwned -and $autostartExisted) {
  Copy-Item -LiteralPath $startupShortcutPath -Destination $autostartSnapshot
}
$komorebiWasRunning = [bool](Get-Process -Name "komorebi" -ErrorAction SilentlyContinue)
$whkdWasRunning = [bool](Get-Process -Name "whkd" -ErrorAction SilentlyContinue)
$barWasRunning = [bool](Get-Process -Name "komorebi-bar" -ErrorAction SilentlyContinue)
$masirWasRunning = [bool](Get-Process -Name "masir" -ErrorAction SilentlyContinue)
try {
  $afterInstall = {
    param($results)

    $configPath = Resolve-KomorebiManagedPath `
      -ConfigHome $configHome `
      -Name "komorebi.json"
    Invoke-Komorebic -Path $komorebicPath -Arguments @(
      "check",
      "--komorebi-config",
      $configPath
    )

    if ($Restart) {
      if (Get-Process -Name "komorebi" -ErrorAction SilentlyContinue) {
        & $restartPath
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

    if ($autostartOwned) {
      Invoke-Komorebic `
        -Path $komorebicPath `
        -Arguments @("enable-autostart", "--whkd", "--bar")
      if (-not (Test-KomorebiShortcutSpec `
        -ShortcutPath $startupShortcutPath `
        -ExpectedTarget $komorebicNoConsolePath `
        -AllowedArguments @("start --bar --whkd")
      )) {
        throw "Komorebi autostart migration did not produce the expected shortcut."
      }
    }

    $updatedFiles = @()
    for ($index = 0; $index -lt $managedFileSpecs.Count; $index++) {
      $result = $results[$index]
      $updatedFiles += @{
        name = $managedFileSpecs[$index].Name
        path = $result.DestinationPath
        sha256 = $result.Sha256
      }
      if ($result.BackupPath) {
        Write-Host "Backed up config: $($result.BackupPath)"
      }
    }
    $manifest.files = $updatedFiles
    $manifest.updated_at = (Get-Date).ToString("o")
    Write-KomorebiManifest -Manifest $manifest -Path $metadataPath
  }

  Install-KomorebiManagedFilesTransaction `
    -Files $managedFileSpecs `
    -Force:$Force `
    -AfterInstall $afterInstall | Out-Null
} catch {
  $updateError = $_
  Copy-Item -LiteralPath $manifestSnapshot -Destination $metadataPath -Force
  if ($autostartOwned) {
    if ($autostartExisted) {
      Copy-Item -LiteralPath $autostartSnapshot -Destination $startupShortcutPath -Force
    } elseif (Test-Path -LiteralPath $startupShortcutPath -PathType Leaf) {
      Remove-Item -LiteralPath $startupShortcutPath -Force
    }
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
        & $restartSourcePath -ConfigHome $configHome
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
  throw $updateError
} finally {
  if (Test-Path -LiteralPath $manifestSnapshot) {
    Remove-Item -LiteralPath $manifestSnapshot -Force
  }
  if (Test-Path -LiteralPath $autostartSnapshot) {
    Remove-Item -LiteralPath $autostartSnapshot -Force
  }
}

Write-Host "Updated Komorebi configuration: $configHome"
