[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($env:OS -ne "Windows_NT") {
  throw "This script must run on Windows."
}
if (@(Get-Process -Name "Spotify" -ErrorAction SilentlyContinue).Count -gt 0) {
  throw "Close Spotify before applying Spicetify."
}

$null = & (Join-Path $PSScriptRoot "install.ps1")
$applicationPaths = @(
  (Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links\spicetify.exe"),
  (Join-Path $env:LOCALAPPDATA "spicetify\spicetify.exe")
)
$spicetifyPath = @(
  $applicationPaths |
    Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }
) | Select-Object -First 1
if ([string]::IsNullOrWhiteSpace($spicetifyPath)) {
  throw "The managed Spicetify executable was not found."
}

& $spicetifyPath "backup" "apply"
if ($LASTEXITCODE -ne 0) {
  throw "Spicetify failed to patch Spotify (exit code $LASTEXITCODE)."
}
