Set-StrictMode -Version Latest

function Resolve-KanataDefenderExclusionPath {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ExePath
  )

  $normalizedPath = [System.IO.Path]::GetFullPath($ExePath)
  $localAppDataRoot = [System.IO.Path]::GetFullPath($env:LOCALAPPDATA).TrimEnd("\") + "\"
  $isUnderLocalAppData = $normalizedPath.StartsWith(
    $localAppDataRoot,
    [System.StringComparison]::OrdinalIgnoreCase
  )
  if (-not $isUnderLocalAppData -or [System.IO.Path]::GetFileName($normalizedPath) -ne "kanata.exe") {
    throw "The Defender exclusion must target kanata.exe under LOCALAPPDATA."
  }

  return $normalizedPath
}

function Invoke-KanataDefenderExclusion {
  param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("Add", "Remove")]
    [string]$Action,

    [Parameter(Mandatory = $true)]
    [string]$ExePath
  )

  $normalizedPath = Resolve-KanataDefenderExclusionPath -ExePath $ExePath
  $pathBase64 = [Convert]::ToBase64String(
    [System.Text.Encoding]::Unicode.GetBytes($normalizedPath)
  )
  $elevatedCommand = @"
`$ErrorActionPreference = "Stop"
`$path = [System.Text.Encoding]::Unicode.GetString([Convert]::FromBase64String("$pathBase64"))
`$normalized = [System.IO.Path]::GetFullPath(`$path)
`$root = [System.IO.Path]::GetFullPath(`$env:LOCALAPPDATA).TrimEnd("\") + "\"
if (-not `$normalized.StartsWith(`$root, [System.StringComparison]::OrdinalIgnoreCase)) { exit 20 }
if ([System.IO.Path]::GetFileName(`$normalized) -ne "kanata.exe") { exit 20 }
`$existing = @((Get-MpPreference).ExclusionPath)
if ("$Action" -eq "Add") {
  if (`$existing -contains `$normalized) { exit 10 }
  Add-MpPreference -ExclusionPath `$normalized
} else {
  if (`$existing -notcontains `$normalized) { exit 10 }
  Remove-MpPreference -ExclusionPath `$normalized
}
"@
  $encodedCommand = [Convert]::ToBase64String(
    [System.Text.Encoding]::Unicode.GetBytes($elevatedCommand)
  )
  $windowsPowerShell = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
  $process = Start-Process `
    -FilePath $windowsPowerShell `
    -Verb RunAs `
    -ArgumentList @("-NoProfile", "-EncodedCommand", $encodedCommand) `
    -Wait `
    -PassThru

  if ($process.ExitCode -eq 0) {
    return $true
  }
  if ($process.ExitCode -eq 10) {
    return $false
  }
  throw "The elevated Defender $Action operation failed with exit code $($process.ExitCode)."
}

function Add-KanataDefenderExclusion {
  param([Parameter(Mandatory = $true)][string]$ExePath)
  return Invoke-KanataDefenderExclusion -Action "Add" -ExePath $ExePath
}

function Remove-KanataDefenderExclusion {
  param([Parameter(Mandatory = $true)][string]$ExePath)
  return Invoke-KanataDefenderExclusion -Action "Remove" -ExePath $ExePath
}

Export-ModuleMember -Function `
  Resolve-KanataDefenderExclusionPath, `
  Add-KanataDefenderExclusion, `
  Remove-KanataDefenderExclusion
