Set-StrictMode -Version Latest

function Invoke-Komorebic {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [Parameter(Mandatory = $true)]
    [string[]]$Arguments
  )

  & $Path @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "komorebic $($Arguments -join ' ') failed with exit code $LASTEXITCODE."
  }
}

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

function Get-KomorebiFileSha256 {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "Cannot hash a missing file: $Path"
  }

  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Resolve-KomorebiConfigHome {
  param(
    [string]$Path = (Join-Path $env:USERPROFILE ".config\komorebi")
  )

  if ([string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
    throw "USERPROFILE is not set."
  }

  $profilePath = [System.IO.Path]::GetFullPath($env:USERPROFILE)
  $candidatePath = [System.IO.Path]::GetFullPath($Path)
  $expectedPath = [System.IO.Path]::GetFullPath(
    (Join-Path $profilePath ".config\komorebi")
  )
  $profilePrefix = $profilePath.TrimEnd(
    [System.IO.Path]::DirectorySeparatorChar,
    [System.IO.Path]::AltDirectorySeparatorChar
  ) + [System.IO.Path]::DirectorySeparatorChar

  if (-not $candidatePath.StartsWith(
    $profilePrefix,
    [System.StringComparison]::OrdinalIgnoreCase
  )) {
    throw "Komorebi config home must be inside USERPROFILE: $candidatePath"
  }
  if (-not $candidatePath.Equals(
    $expectedPath,
    [System.StringComparison]::OrdinalIgnoreCase
  )) {
    throw "Komorebi config home must use the managed path: $expectedPath"
  }

  $currentPath = $candidatePath
  while (-not $currentPath.Equals(
    $profilePath,
    [System.StringComparison]::OrdinalIgnoreCase
  )) {
    if (Test-Path -LiteralPath $currentPath) {
      $item = Get-Item -LiteralPath $currentPath -Force
      if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
        throw "Komorebi config home cannot traverse a reparse point: $currentPath"
      }
    }
    $parentPath = Split-Path -Parent $currentPath
    if ([string]::IsNullOrWhiteSpace($parentPath) -or $parentPath -eq $currentPath) {
      throw "Cannot validate Komorebi config home: $candidatePath"
    }
    $currentPath = $parentPath
  }

  return $candidatePath
}

function Install-KomorebiManagedFile {
  param(
    [Parameter(Mandatory = $true)]
    [string]$SourcePath,

    [Parameter(Mandatory = $true)]
    [string]$DestinationPath,

    [ValidatePattern("^$|^[0-9a-fA-F]{64}$")]
    [string]$PreviousSha256 = "",

    [switch]$Force
  )

  if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
    throw "Managed source file does not exist: $SourcePath"
  }
  if (
    (Test-Path -LiteralPath $DestinationPath) -and
    -not (Test-Path -LiteralPath $DestinationPath -PathType Leaf)
  ) {
    throw "Managed destination must be a file path: $DestinationPath"
  }

  $sourceSha256 = Get-KomorebiFileSha256 -Path $SourcePath
  $destinationExists = Test-Path -LiteralPath $DestinationPath -PathType Leaf
  if ($destinationExists) {
    $currentSha256 = Get-KomorebiFileSha256 -Path $DestinationPath
    if ($currentSha256 -eq $sourceSha256) {
      return [pscustomobject]@{
        DestinationPath = $DestinationPath
        Sha256 = $sourceSha256
        Changed = $false
        BackupPath = $null
      }
    }

    $isPreviouslyManaged = -not [string]::IsNullOrWhiteSpace($PreviousSha256) -and
      $currentSha256 -eq $PreviousSha256.ToLowerInvariant()
    if (-not $isPreviouslyManaged -and -not $Force) {
      throw "Refusing to overwrite a user-modified config file: $DestinationPath"
    }
  }

  $destinationDirectory = Split-Path -Parent $DestinationPath
  New-Item -ItemType Directory -Force -Path $destinationDirectory | Out-Null
  $backupPath = $null
  if ($destinationExists -and $Force) {
    $timestamp = Get-Date -Format "yyyyMMddHHmmssfff"
    $backupPath = "$DestinationPath.pre-dotfiles-$timestamp.bak"
    Copy-Item -LiteralPath $DestinationPath -Destination $backupPath
  }

  $temporaryPath = Join-Path $destinationDirectory (
    ".{0}.{1}.tmp" -f ([System.IO.Path]::GetFileName($DestinationPath)),
    [guid]::NewGuid().ToString("N")
  )
  try {
    Copy-Item -LiteralPath $SourcePath -Destination $temporaryPath
    if ((Get-KomorebiFileSha256 -Path $temporaryPath) -ne $sourceSha256) {
      throw "Managed config verification failed before deployment: $SourcePath"
    }
    Move-Item -LiteralPath $temporaryPath -Destination $DestinationPath -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) {
      Remove-Item -LiteralPath $temporaryPath -Force
    }
  }

  return [pscustomobject]@{
    DestinationPath = $DestinationPath
    Sha256 = $sourceSha256
    Changed = $true
    BackupPath = $backupPath
  }
}

function Get-KomorebiManifest {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    return $null
  }

  try {
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
  } catch {
    throw "Cannot parse the Komorebi installer manifest at ${Path}: $($_.Exception.Message)"
  }
}

function Get-KomorebiManifestFileSha256 {
  param(
    [object]$Manifest,

    [Parameter(Mandatory = $true)]
    [string]$Name
  )

  if (
    $null -eq $Manifest -or
    $null -eq $Manifest.PSObject.Properties["files"]
  ) {
    return ""
  }

  $entry = @($Manifest.files | Where-Object { $_.name -eq $Name }) |
    Select-Object -First 1
  if ($null -eq $entry) {
    return ""
  }

  return [string]$entry.sha256
}

function Test-KomorebiManifestPackageOwned {
  param(
    [object]$Manifest,

    [Parameter(Mandatory = $true)]
    [ValidateSet("komorebi", "whkd", "masir")]
    [string]$Name
  )

  if (
    $null -eq $Manifest -or
    $null -eq $Manifest.PSObject.Properties["packages"]
  ) {
    return $false
  }

  $property = $Manifest.packages.PSObject.Properties[$Name]
  return $null -ne $property -and [bool]$property.Value
}

function Resolve-KomorebiManagedPath {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ConfigHome,

    [Parameter(Mandatory = $true)]
    [ValidateSet(
      "komorebi.json",
      "komorebi.bar.json",
      "whkdrc",
      "switch-audio.ps1",
      "audio-output.json"
    )]
    [string]$Name
  )

  $resolvedHome = Resolve-KomorebiConfigHome -Path $ConfigHome
  return Join-Path $resolvedHome $Name
}

function Get-KomorebiManagedFileSpecification {
  param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot,

    [Parameter(Mandatory = $true)]
    [string]$ConfigHome,

    [object]$Manifest
  )

  $audioConfigSourcePath = Join-Path $SourceRoot "audio-output.local.json"
  if (-not (Test-Path -LiteralPath $audioConfigSourcePath -PathType Leaf)) {
    $audioConfigSourcePath = Join-Path $SourceRoot "audio-output.json"
  }
  $sources = @(
    @{
      Name = "komorebi.json"
      SourcePath = Join-Path $SourceRoot "komorebi.json"
    },
    @{
      Name = "komorebi.bar.json"
      SourcePath = Join-Path $SourceRoot "komorebi.bar.json"
    },
    @{
      Name = "whkdrc"
      SourcePath = Join-Path $SourceRoot "whkdrc"
    },
    @{
      Name = "switch-audio.ps1"
      SourcePath = Join-Path $SourceRoot "switch-audio.ps1"
    },
    @{
      Name = "audio-output.json"
      SourcePath = $audioConfigSourcePath
    }
  )

  return @($sources | ForEach-Object {
    [pscustomobject]@{
      Name = $_.Name
      SourcePath = $_.SourcePath
      DestinationPath = Resolve-KomorebiManagedPath `
        -ConfigHome $ConfigHome `
        -Name $_.Name
      PreviousSha256 = Get-KomorebiManifestFileSha256 `
        -Manifest $Manifest `
        -Name $_.Name
    }
  })
}

function Install-AudioDeviceModule {
  param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern("^\d+\.\d+\.\d+\.\d+$")]
    [string]$RequiredVersion
  )

  $installed = Get-Module -ListAvailable -Name "AudioDeviceCmdlets" |
    Where-Object { $_.Version.ToString() -eq $RequiredVersion } |
    Select-Object -First 1
  if ($installed) {
    return $false
  }

  $nugetProvider = Get-PackageProvider -Name "NuGet" -ErrorAction SilentlyContinue
  if (-not $nugetProvider) {
    Install-PackageProvider -Name "NuGet" -Scope "CurrentUser" -Force |
      Out-Null
  }

  Install-Module `
    -Name "AudioDeviceCmdlets" `
    -RequiredVersion $RequiredVersion `
    -Repository "PSGallery" `
    -Scope "CurrentUser" `
    -Force `
    -AllowClobber `
    -ErrorAction Stop

  $installed = Get-Module -ListAvailable -Name "AudioDeviceCmdlets" |
    Where-Object { $_.Version.ToString() -eq $RequiredVersion } |
    Select-Object -First 1
  if (-not $installed) {
    throw "AudioDeviceCmdlets $RequiredVersion was not installed."
  }

  return $true
}

function Install-KomorebiManagedFilesTransaction {
  param(
    [Parameter(Mandatory = $true)]
    [object[]]$Files,

    [switch]$Force,

    [scriptblock]$AfterInstall
  )

  if ($Files.Count -eq 0) {
    throw "At least one managed file is required."
  }

  $snapshotRoot = Join-Path $env:TEMP (
    "komorebi_config_{0}" -f [guid]::NewGuid().ToString("N")
  )
  New-Item -ItemType Directory -Path $snapshotRoot | Out-Null
  $snapshots = @()
  $results = @()
  try {
    for ($index = 0; $index -lt $Files.Count; $index++) {
      $file = $Files[$index]
      $destinationPath = [string]$file.DestinationPath
      $wasFile = Test-Path -LiteralPath $destinationPath -PathType Leaf
      $wasPresent = Test-Path -LiteralPath $destinationPath
      $backupPath = $null
      if ($wasFile) {
        $backupPath = Join-Path $snapshotRoot ([string]$index)
        Copy-Item -LiteralPath $destinationPath -Destination $backupPath
      }
      $snapshots += [pscustomobject]@{
        DestinationPath = $destinationPath
        WasFile = $wasFile
        WasPresent = $wasPresent
        BackupPath = $backupPath
      }
    }

    foreach ($file in $Files) {
      $results += Install-KomorebiManagedFile `
        -SourcePath ([string]$file.SourcePath) `
        -DestinationPath ([string]$file.DestinationPath) `
        -PreviousSha256 ([string]$file.PreviousSha256) `
        -Force:$Force
    }

    if ($AfterInstall) {
      & $AfterInstall $results | Out-Null
    }

    return $results
  } catch {
    $deploymentError = $_
    foreach ($snapshot in $snapshots) {
      try {
        if ($snapshot.WasFile) {
          Copy-Item `
            -LiteralPath $snapshot.BackupPath `
            -Destination $snapshot.DestinationPath `
            -Force
        } elseif (
          -not $snapshot.WasPresent -and
          (Test-Path -LiteralPath $snapshot.DestinationPath -PathType Leaf)
        ) {
          Remove-Item -LiteralPath $snapshot.DestinationPath -Force
        }
      } catch {
        Write-Warning "Failed to restore managed config: $($snapshot.DestinationPath)"
      }
    }
    throw $deploymentError
  } finally {
    if (Test-Path -LiteralPath $snapshotRoot) {
      Remove-Item -LiteralPath $snapshotRoot -Recurse -Force
    }
  }
}

function Wait-KomorebiProcessSet {
  param(
    [Parameter(Mandatory = $true)]
    [string[]]$Names,

    [ValidateRange(0, 60)]
    [int]$TimeoutSeconds = 10,

    [ValidateRange(0, 10000)]
    [int]$StableMilliseconds = 1000
  )

  $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
  $stableSinceMilliseconds = $null
  do {
    $missing = @($Names | Where-Object {
      -not (Get-Process -Name $_ -ErrorAction SilentlyContinue)
    })
    if ($missing.Count -eq 0) {
      if ($StableMilliseconds -eq 0) {
        return
      }
      if ($null -eq $stableSinceMilliseconds) {
        $stableSinceMilliseconds = $stopwatch.Elapsed.TotalMilliseconds
      } elseif (
        $stopwatch.Elapsed.TotalMilliseconds - $stableSinceMilliseconds -ge
        $StableMilliseconds
      ) {
        return
      }
    } else {
      $stableSinceMilliseconds = $null
    }
    if ($stopwatch.Elapsed.TotalSeconds -ge $TimeoutSeconds) {
      break
    }
    Start-Sleep -Milliseconds 100
  } while ($true)

  if ($missing.Count -gt 0) {
    throw "Timed out waiting for processes: $($missing -join ', ')"
  }
  throw (
    "Processes did not remain available for {0} ms: {1}" -f
    $StableMilliseconds,
    ($Names -join ", ")
  )
}

function Get-KomorebiBarArgumentString {
  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigPath
  )

  if ($ConfigPath.Contains('"')) {
    throw "The Komorebi bar config path cannot contain a quote."
  }

  return '-c "{0}"' -f $ConfigPath
}

function Test-KomorebiShortcutSpec {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ShortcutPath,

    [Parameter(Mandatory = $true)]
    [string]$ExpectedTarget,

    [Parameter(Mandatory = $true)]
    [string[]]$AllowedArguments
  )

  if (-not (Test-Path -LiteralPath $ShortcutPath -PathType Leaf)) {
    return $false
  }
  try {
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($ShortcutPath)
    $targetMatches = [System.IO.Path]::GetFullPath(
      $shortcut.TargetPath
    ).Equals(
      [System.IO.Path]::GetFullPath($ExpectedTarget),
      [System.StringComparison]::OrdinalIgnoreCase
    )
    $argumentsMatch = $AllowedArguments -contains $shortcut.Arguments.Trim()
    return $targetMatches -and $argumentsMatch
  } catch {
    return $false
  }
}

Export-ModuleMember -Function `
  Invoke-Komorebic, `
  Write-KomorebiManifest, `
  Get-KomorebiFileSha256, `
  Resolve-KomorebiConfigHome, `
  Install-KomorebiManagedFile, `
  Get-KomorebiManifest, `
  Get-KomorebiManifestFileSha256, `
  Test-KomorebiManifestPackageOwned, `
  Resolve-KomorebiManagedPath, `
  Get-KomorebiManagedFileSpecification, `
  Install-AudioDeviceModule, `
  Install-KomorebiManagedFilesTransaction, `
  Wait-KomorebiProcessSet, `
  Get-KomorebiBarArgumentString, `
  Test-KomorebiShortcutSpec
