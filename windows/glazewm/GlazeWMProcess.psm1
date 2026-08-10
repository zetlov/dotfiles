Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-GlazeTaskkillPath {
  $systemDirectory = [Environment]::SystemDirectory
  if ([string]::IsNullOrWhiteSpace($systemDirectory)) {
    throw "The Windows system directory is unavailable."
  }
  $taskkillPath = Join-Path $systemDirectory "taskkill.exe"
  if (-not (Test-Path -LiteralPath $taskkillPath -PathType Leaf)) {
    throw "The trusted taskkill executable was not found: $taskkillPath"
  }
  return $taskkillPath
}

function Invoke-GlazeProcessTreeTermination {
  param(
    [Parameter(Mandatory = $true)][string]$FilePath,
    [Parameter(Mandatory = $true)][string[]]$ArgumentList
  )

  & $FilePath @ArgumentList 2>$null | Out-Null
  return [int]$LASTEXITCODE
}

function Stop-GlazeProcessTree {
  [CmdletBinding()]
  param([Parameter(Mandatory = $true)][int]$ProcessId)

  $taskkillPath = Resolve-GlazeTaskkillPath
  $arguments = @("/PID", [string]$ProcessId, "/T", "/F")
  $exitCode = Invoke-GlazeProcessTreeTermination `
    -FilePath $taskkillPath `
    -ArgumentList $arguments
  if ($exitCode -ne 0) {
    throw (
      "Unable to stop the GlazeWM helper process tree for PID $ProcessId; " +
      "taskkill exited with exit code $exitCode."
    )
  }
}

Export-ModuleMember -Function "Stop-GlazeProcessTree"
