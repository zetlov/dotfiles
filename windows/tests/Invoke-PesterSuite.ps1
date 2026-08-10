[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$requiredPesterVersion = [version]"5.7.1"
$requiredPesterSignerThumbprint = "147C2FD397677DC76DD198E83E7D9D234AA59D1A"
$pesterModule = Get-Module -ListAvailable -Name Pester |
  Where-Object Version -EQ $requiredPesterVersion |
  Select-Object -First 1
if ($null -eq $pesterModule) {
  throw "Pester $requiredPesterVersion is required."
}
$pesterRoot = Split-Path -Parent $pesterModule.Path
$pesterExecutableFiles = @(
  Get-ChildItem -LiteralPath $pesterRoot -Recurse -File |
    Where-Object {
      $_.Extension -in @(".dll", ".ps1", ".ps1xml", ".psd1", ".psm1")
    }
)
if ($pesterExecutableFiles.Count -eq 0) {
  throw "Pester $requiredPesterVersion has no verifiable executable files."
}
foreach ($pesterFile in $pesterExecutableFiles) {
  $pesterSignature = Get-AuthenticodeSignature -LiteralPath $pesterFile.FullName
  if (
    $pesterSignature.Status -ne "Valid" -or
    $pesterSignature.SignerCertificate.Thumbprint -ne $requiredPesterSignerThumbprint
  ) {
    throw "Pester $requiredPesterVersion has an unexpected Authenticode signature."
  }
}
Import-Module -Name $pesterModule.Path -Force

$windowsRoot = Split-Path -Parent $PSScriptRoot
$repoRoot = Split-Path -Parent $windowsRoot
$suiteManifest = Join-Path $PSScriptRoot "pester-suites.txt"
$suitePaths = @(Get-Content -LiteralPath $suiteManifest | Where-Object { $_ })
if ($suitePaths.Count -eq 0) {
  throw "The Windows Pester suite manifest is empty."
}
$testFiles = @(
  $suitePaths | ForEach-Object {
    if ($_ -notmatch '^windows/[a-z0-9-]+/tests/[A-Za-z0-9.-]+\.Tests\.ps1$') {
      throw "The Windows Pester suite manifest contains an invalid path: $_"
    }
    $testFile = Join-Path $repoRoot $_
    if (-not (Test-Path -LiteralPath $testFile -PathType Leaf)) {
      throw "The Windows Pester test file does not exist: $_"
    }
    $testFile
  }
)

$result = Invoke-Pester -Path $testFiles -PassThru
if ($result.FailedCount -gt 0) {
  exit 1
}
