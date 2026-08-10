[CmdletBinding()]
param(
  [string]$ZebarPath = (
    Join-Path $env:ProgramFiles "glzr.io\Zebar\zebar.exe"
  ),

  [string]$DestinationRoot = (
    Join-Path $env:USERPROFILE ".glzr\zebar\zetshell"
  ),

  [ValidatePattern('^\d+\.\d+\.\d+$')]
  [string]$RequiredVersion = "3.3.1"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($env:OS -ne "Windows_NT") {
  throw "This script must run on Windows."
}

$expectedDestination = [IO.Path]::GetFullPath(
  (Join-Path $env:USERPROFILE ".glzr\zebar\zetshell")
)
$DestinationRoot = [IO.Path]::GetFullPath($DestinationRoot)
if (-not $DestinationRoot.Equals(
  $expectedDestination,
  [StringComparison]::OrdinalIgnoreCase
)) {
  throw "Zebar pack must be installed at: $expectedDestination"
}

if (-not (Test-Path -LiteralPath $ZebarPath -PathType Leaf)) {
  & winget.exe install `
    --id "glzr-io.zebar" `
    --exact `
    --version $RequiredVersion `
    --silent `
    --accept-source-agreements `
    --accept-package-agreements
  if ($LASTEXITCODE -ne 0) {
    throw "WinGet could not install glzr-io.zebar."
  }
}
if (-not (Test-Path -LiteralPath $ZebarPath -PathType Leaf)) {
  throw "Zebar executable not found: $ZebarPath"
}
$versionOutput = (& $ZebarPath --version 2>&1 | Out-String).Trim()
if (
  $LASTEXITCODE -ne 0 -or
  $versionOutput -ne "zebar $RequiredVersion"
) {
  throw (
    "Unexpected Zebar version. Expected $RequiredVersion, got: " +
    $versionOutput
  )
}

$sourcePack = Join-Path $PSScriptRoot "zpack.json"
$sourceDist = Join-Path $PSScriptRoot "dist"
$sourceIndex = Join-Path $sourceDist "index.html"
$sourceProcessHelpers = Join-Path $PSScriptRoot "ZebarProcessHelpers.ps1"
foreach ($sourcePath in @($sourcePack, $sourceIndex, $sourceProcessHelpers)) {
  if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
    throw "Required Zebar file not found: $sourcePath"
  }
}
try {
  $pack = Get-Content -LiteralPath $sourcePack -Raw | ConvertFrom-Json
} catch {
  throw "Cannot parse Zebar widget pack: $sourcePack"
}
if ($pack.name -ne "zetshell" -or @($pack.widgets).Count -ne 1) {
  throw "Unexpected Zebar widget pack identity."
}
. $sourceProcessHelpers

$destinationParent = Split-Path -Parent $DestinationRoot
New-Item -ItemType Directory -Path $destinationParent -Force | Out-Null
$stagingRoot = Join-Path $destinationParent (
  "zetshell.new-" + [guid]::NewGuid().ToString("N")
)
$backupRoot = Join-Path $destinationParent (
  "zetshell.old-" + [guid]::NewGuid().ToString("N")
)
$hadExisting = Test-Path -LiteralPath $DestinationRoot -PathType Container
$zebarWasRunning = @(
  Get-Process -Name "zebar" -ErrorAction SilentlyContinue
).Count -gt 0
$installed = $false
try {
  Get-ZetshellGpuMonitorProcess |
    ForEach-Object {
      Stop-Process -Id $_.ProcessId -Force -ErrorAction Stop
    }
  Get-Process -Name "zebar" -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue
  New-Item -ItemType Directory -Path $stagingRoot | Out-Null
  Copy-Item -LiteralPath $sourcePack -Destination $stagingRoot
  Copy-Item -LiteralPath $sourceDist -Destination $stagingRoot -Recurse
  if ($hadExisting) {
    Move-Item -LiteralPath $DestinationRoot -Destination $backupRoot
  }
  Move-Item -LiteralPath $stagingRoot -Destination $DestinationRoot
  $installed = $true
} finally {
  if (-not $installed -and $hadExisting -and (
    Test-Path -LiteralPath $backupRoot -PathType Container
  )) {
    Move-Item -LiteralPath $backupRoot -Destination $DestinationRoot
  }
  if (-not $installed -and $zebarWasRunning -and $hadExisting) {
    Start-Process `
      -FilePath $ZebarPath `
      -ArgumentList @(
        "start-widget-preset",
        "--pack", "zetshell",
        "--widget-name", "bar",
        "--preset", "primary-monitor"
      ) `
      -WindowStyle Hidden |
      Out-Null
  }
  foreach ($temporaryPath in @($stagingRoot, $backupRoot)) {
    if (Test-Path -LiteralPath $temporaryPath) {
      Remove-Item -LiteralPath $temporaryPath -Recurse -Force
    }
  }
}

[pscustomobject]@{
  Pack = "zetshell"
  Destination = $DestinationRoot
  ZebarPath = $ZebarPath
}
