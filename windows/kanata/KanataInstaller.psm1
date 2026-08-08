Set-StrictMode -Version Latest

function Get-KanataReleaseSpec {
  param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("arm64", "x64")]
    [string]$Cpu,

    [Parameter(Mandatory = $true)]
    [ValidateSet("winio", "wintercept")]
    [string]$Driver
  )

  if ($Cpu -eq "arm64" -and $Driver -eq "wintercept") {
    throw "Kanata v1.12.0 does not provide a wintercept binary for arm64."
  }

  $version = "v1.12.0"
  $sha256ByCpu = @{
    arm64 = "f6970ebda03c03c370a1dedf8a75cb73a1690cfd3095f459b5bb3f527aa75407"
    x64 = "13947ed78cfa3284bfef854e3c542c74ab366236b72fd9f7e039f8638deead9d"
  }
  $assetName = "windows-binaries-$Cpu.zip"

  return [pscustomobject]@{
    Version = $version
    AssetName = $assetName
    Sha256 = $sha256ByCpu[$Cpu]
    DownloadUrl = "https://github.com/jtroo/kanata/releases/download/$version/$assetName"
  }
}

function Assert-FileSha256 {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [Parameter(Mandatory = $true)]
    [ValidatePattern("^[0-9a-fA-F]{64}$")]
    [string]$ExpectedSha256
  )

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "Cannot verify a missing file: $Path"
  }

  $actualSha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
  $expectedNormalized = $ExpectedSha256.ToLowerInvariant()
  if ($actualSha256 -ne $expectedNormalized) {
    throw "SHA-256 mismatch for ${Path}: expected $expectedNormalized, got $actualSha256"
  }

  return $actualSha256
}

function Select-KanataExecutableEntry {
  param(
    [object[]]$Entries,
    [string]$Driver,
    [string]$Ui,
    [bool]$CmdAllowed
  )

  $executables = @($Entries | Where-Object {
    $_.Name -match "^kanata.*\.exe$"
  })
  $candidates = @($executables | Where-Object {
    $_.Name -match $Driver -and $_.Name -match $Ui
  })

  if ($CmdAllowed) {
    $candidates = @($candidates | Where-Object { $_.Name -match "cmd" })
  } else {
    $candidates = @($candidates | Where-Object { $_.Name -notmatch "cmd" })
  }
  if ($candidates.Count -eq 0) {
    throw "Could not find a Kanata executable for driver=$Driver, ui=$Ui, cmd_allowed=$CmdAllowed."
  }

  return $candidates | Sort-Object -Property Name | Select-Object -First 1
}

function Get-VerifiedKanataExecutablePayload {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ZipPath,

    [Parameter(Mandatory = $true)]
    [ValidatePattern("^[0-9a-fA-F]{64}$")]
    [string]$ExpectedSha256,

    [Parameter(Mandatory = $true)]
    [string]$Driver,

    [Parameter(Mandatory = $true)]
    [string]$Ui,

    [Parameter(Mandatory = $true)]
    [bool]$CmdAllowed
  )

  Add-Type -AssemblyName System.IO.Compression
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $archiveStream = [System.IO.File]::Open(
    $ZipPath,
    [System.IO.FileMode]::Open,
    [System.IO.FileAccess]::Read,
    [System.IO.FileShare]::None
  )
  try {
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
      $actualBytes = $sha256.ComputeHash($archiveStream)
      $actualSha256 = ([BitConverter]::ToString($actualBytes)).Replace("-", "").ToLowerInvariant()
    } finally {
      $sha256.Dispose()
    }
    $expectedNormalized = $ExpectedSha256.ToLowerInvariant()
    if ($actualSha256 -ne $expectedNormalized) {
      throw "SHA-256 mismatch for ${ZipPath}: expected $expectedNormalized, got $actualSha256"
    }

    $archiveStream.Position = 0
    $archive = [System.IO.Compression.ZipArchive]::new(
      $archiveStream,
      [System.IO.Compression.ZipArchiveMode]::Read,
      $true
    )
    try {
      $entry = Select-KanataExecutableEntry `
        -Entries @($archive.Entries) `
        -Driver $Driver `
        -Ui $Ui `
        -CmdAllowed $CmdAllowed
      $inputStream = $entry.Open()
      try {
        $payloadStream = New-Object System.IO.MemoryStream
        try {
          $inputStream.CopyTo($payloadStream)
          $payloadBytes = $payloadStream.ToArray()
        } finally {
          $payloadStream.Dispose()
        }
      } finally {
        $inputStream.Dispose()
      }
    } finally {
      $archive.Dispose()
    }
  } finally {
    $archiveStream.Dispose()
  }

  return [pscustomobject]@{
    Name = $entry.Name
    Bytes = $payloadBytes
    ArchiveSha256 = $actualSha256
  }
}

function Install-KanataExecutablePayload {
  param(
    [Parameter(Mandatory = $true)]
    [object]$Payload,

    [Parameter(Mandatory = $true)]
    [string]$DestinationPath
  )

  if (-not $Payload.Bytes -or $Payload.Bytes.Count -eq 0) {
    throw "The Kanata executable payload is empty."
  }

  $destinationDir = Split-Path -Parent $DestinationPath
  New-Item -ItemType Directory -Force -Path $destinationDir | Out-Null
  $hadExistingExecutable = Test-Path -LiteralPath $DestinationPath -PathType Leaf
  $existingBytes = if ($hadExistingExecutable) {
    [System.IO.File]::ReadAllBytes($DestinationPath)
  } else {
    $null
  }

  try {
    [System.IO.File]::WriteAllBytes($DestinationPath, $Payload.Bytes)
  } catch {
    $writeError = $_
    try {
      if ($hadExistingExecutable) {
        [System.IO.File]::WriteAllBytes($DestinationPath, $existingBytes)
      } elseif (Test-Path -LiteralPath $DestinationPath) {
        Remove-Item -LiteralPath $DestinationPath -Force
      }
    } catch {
      Write-Warning "Failed to restore the previous Kanata executable: $($_.Exception.Message)"
    }
    throw $writeError
  }

  return $Payload.Name
}

Export-ModuleMember -Function `
  Get-KanataReleaseSpec, `
  Assert-FileSha256, `
  Get-VerifiedKanataExecutablePayload, `
  Install-KanataExecutablePayload
