Set-StrictMode -Version Latest

$script:AudioDeviceModuleName = "AudioDeviceCmdlets"
$script:AudioDeviceModuleVersion = "3.1.0.2"
$script:AudioDevicePackageUri = (
  "https://www.powershellgallery.com/api/v2/package/" +
  "AudioDeviceCmdlets/3.1.0.2"
)
$script:AudioDeviceManifestName = "AudioDeviceCmdlets.psd1"
$script:AudioDeviceDllName = "AudioDeviceCmdlets.dll"
$script:AudioDeviceManifestSha256 = (
  "0D657B8DDE3DC9B090716162ED351B68F" +
  "785F50483B92E937528D082469DBFB5"
)
$script:AudioDeviceDllSha256 = (
  "2E81666DD09BC835C669DAF9771686FD" +
  "AD5651FBEBB600A234F11AF80CA5D25F"
)
$script:AudioDevicePackageMaximumBytes = 1MB
$script:AudioDeviceManifestBytes = 5434
$script:AudioDeviceDllBytes = 45056

function Get-AudioDeviceModulePaths {
  param(
    [string]$DocumentsPath = [Environment]::GetFolderPath("MyDocuments")
  )

  $documentsPath = $DocumentsPath
  if ([string]::IsNullOrWhiteSpace($documentsPath)) {
    throw "Cannot resolve the current user's MyDocuments directory."
  }

  $windowsPowerShellPath = Join-Path $documentsPath "WindowsPowerShell"
  $modulesPath = Join-Path $windowsPowerShellPath "Modules"
  $moduleContainerPath = Join-Path $modulesPath $script:AudioDeviceModuleName
  $moduleRoot = Join-Path $moduleContainerPath $script:AudioDeviceModuleVersion

  return [pscustomobject]@{
    WindowsPowerShell = $windowsPowerShellPath
    Modules = $modulesPath
    Container = $moduleContainerPath
    Root = $moduleRoot
    Manifest = Join-Path $moduleRoot $script:AudioDeviceManifestName
    Dll = Join-Path $moduleRoot $script:AudioDeviceDllName
  }
}

function Assert-AudioPathIsNotReparsePoint {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [Parameter(Mandatory = $true)]
    [string]$Description
  )

  if (-not (Test-Path -LiteralPath $Path)) {
    return
  }

  $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
  if (
    $null -ne $item -and
    ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)
  ) {
    throw "AudioDeviceCmdlets integrity check failed: $Description is a reparse point."
  }
}

function Assert-AudioFileHash {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [Parameter(Mandatory = $true)]
    [string]$ExpectedSha256
  )

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "AudioDeviceCmdlets integrity check failed: required file is missing: $Path"
  }
  Assert-AudioPathIsNotReparsePoint -Path $Path -Description $Path

  $actualHash = (Get-FileHash -LiteralPath $Path -Algorithm "SHA256").Hash
  if (-not [string]::Equals(
    [string]$actualHash,
    $ExpectedSha256,
    [System.StringComparison]::OrdinalIgnoreCase
  )) {
    throw "AudioDeviceCmdlets integrity check failed for: $Path"
  }
}

function Assert-AudioDeviceModuleIntegrity {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ModuleRoot
  )

  Assert-AudioPathIsNotReparsePoint `
    -Path $ModuleRoot `
    -Description "the module version directory"
  Assert-AudioFileHash `
    -Path (Join-Path $ModuleRoot $script:AudioDeviceManifestName) `
    -ExpectedSha256 $script:AudioDeviceManifestSha256
  Assert-AudioFileHash `
    -Path (Join-Path $ModuleRoot $script:AudioDeviceDllName) `
    -ExpectedSha256 $script:AudioDeviceDllSha256
}

function Assert-AudioDeviceModulePathAncestors {
  param(
    [Parameter(Mandatory = $true)]
    [pscustomobject]$Paths
  )

  foreach ($pathEntry in @(
    @($Paths.WindowsPowerShell, "the WindowsPowerShell directory"),
    @($Paths.Modules, "the PowerShell modules directory"),
    @($Paths.Container, "the module container directory"),
    @($Paths.Root, "the module version directory")
  )) {
    Assert-AudioPathIsNotReparsePoint `
      -Path $pathEntry[0] `
      -Description $pathEntry[1]
  }
}

function Copy-AudioDevicePackageFiles {
  param(
    [Parameter(Mandatory = $true)]
    [string]$PackagePath,

    [Parameter(Mandatory = $true)]
    [string]$DestinationPath
  )

  Add-Type -AssemblyName "System.IO.Compression.FileSystem"
  [System.IO.Compression.ZipArchive]$archive = [System.IO.Compression.ZipFile]::OpenRead(
    $PackagePath
  )
  try {
    foreach ($fileName in @(
      $script:AudioDeviceManifestName,
      $script:AudioDeviceDllName
    )) {
      $entries = @(
        $archive.Entries | Where-Object {
          [string]::Equals(
            $_.FullName,
            $fileName,
            [System.StringComparison]::Ordinal
          )
        }
      )
      if ($entries.Count -ne 1) {
        throw (
          "AudioDeviceCmdlets package integrity check failed: expected " +
          "exactly one root entry named $fileName."
        )
      }

      $expectedLength = if ($fileName -eq $script:AudioDeviceManifestName) {
        $script:AudioDeviceManifestBytes
      } else {
        $script:AudioDeviceDllBytes
      }
      if (
        $entries[0].Length -ne $expectedLength -or
        $entries[0].CompressedLength -gt $script:AudioDevicePackageMaximumBytes
      ) {
        throw (
          "AudioDeviceCmdlets package integrity check failed: unexpected " +
          "archive entry size for $fileName."
        )
      }

      $destinationFile = Join-Path $DestinationPath $fileName
      $inputStream = $entries[0].Open()
      $outputStream = [System.IO.File]::Open(
        $destinationFile,
        [System.IO.FileMode]::CreateNew,
        [System.IO.FileAccess]::Write,
        [System.IO.FileShare]::None
      )
      try {
        $inputStream.CopyTo($outputStream)
      } finally {
        $outputStream.Dispose()
        $inputStream.Dispose()
      }
    }
  } finally {
    $archive.Dispose()
  }
}

function Copy-BoundedAudioPackageStream {
  param(
    [Parameter(Mandatory = $true)]
    [System.IO.Stream]$InputStream,

    [Parameter(Mandatory = $true)]
    [string]$DestinationPath,

    [Parameter(Mandatory = $true)]
    [long]$MaximumBytes
  )

  $outputStream = $null
  try {
    $outputStream = [System.IO.File]::Open(
      $DestinationPath,
      [System.IO.FileMode]::CreateNew,
      [System.IO.FileAccess]::Write,
      [System.IO.FileShare]::None
    )
    $buffer = New-Object byte[] 81920
    [long]$totalBytes = 0
    while (($bytesRead = $InputStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
      $totalBytes += $bytesRead
      if ($totalBytes -gt $MaximumBytes) {
        throw "AudioDeviceCmdlets package integrity check failed: package is too large."
      }
      $outputStream.Write($buffer, 0, $bytesRead)
    }
  } catch {
    if ($null -ne $outputStream) {
      $outputStream.Dispose()
      $outputStream = $null
    }
    Remove-Item `
      -LiteralPath $DestinationPath `
      -Force `
      -ErrorAction SilentlyContinue
    throw
  } finally {
    if ($null -ne $outputStream) {
      $outputStream.Dispose()
    }
  }
}

function Save-AudioDevicePackage {
  param(
    [Parameter(Mandatory = $true)]
    [uri]$Uri,

    [Parameter(Mandatory = $true)]
    [string]$DestinationPath,

    [Parameter(Mandatory = $true)]
    [long]$MaximumBytes
  )

  $request = [System.Net.HttpWebRequest]::Create($Uri)
  $request.Method = "GET"
  $request.AllowAutoRedirect = $true
  $response = $null
  $inputStream = $null
  try {
    $response = [System.Net.HttpWebResponse]$request.GetResponse()
    if (
      $response.ContentLength -ge 0 -and
      $response.ContentLength -gt $MaximumBytes
    ) {
      throw "AudioDeviceCmdlets package integrity check failed: package is too large."
    }
    $inputStream = $response.GetResponseStream()
    Copy-BoundedAudioPackageStream `
      -InputStream $inputStream `
      -DestinationPath $DestinationPath `
      -MaximumBytes $MaximumBytes
  } finally {
    if ($null -ne $inputStream) {
      $inputStream.Dispose()
    }
    if ($null -ne $response) {
      $response.Dispose()
    }
  }
}

function Install-AudioDeviceModule {
  param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern("^\d+\.\d+\.\d+\.\d+$")]
    [string]$RequiredVersion,

    [string]$DocumentsPath = [Environment]::GetFolderPath("MyDocuments")
  )

  if ($RequiredVersion -ne $script:AudioDeviceModuleVersion) {
    throw (
      "Unsupported AudioDeviceCmdlets version '$RequiredVersion'. " +
      "The reviewed version is $($script:AudioDeviceModuleVersion)."
    )
  }

  $paths = Get-AudioDeviceModulePaths -DocumentsPath $DocumentsPath
  Assert-AudioDeviceModulePathAncestors -Paths $paths
  $rootExists = Test-Path -LiteralPath $paths.Root -PathType Container
  $manifestExists = Test-Path -LiteralPath $paths.Manifest -PathType Leaf
  $dllExists = Test-Path -LiteralPath $paths.Dll -PathType Leaf

  if ($rootExists -or $manifestExists -or $dllExists) {
    if (-not ($manifestExists -and $dllExists)) {
      throw (
        "AudioDeviceCmdlets integrity check failed: the trusted installation " +
        "is incomplete at $($paths.Root)."
      )
    }
    Assert-AudioDeviceModuleIntegrity -ModuleRoot $paths.Root
    return $false
  }

  $temporaryRoot = $null
  $targetCreated = $false
  try {
    $temporaryRoot = Join-Path (
      [System.IO.Path]::GetTempPath()
    ) ("audio-device-cmdlets-" + [Guid]::NewGuid().ToString("N"))
    $stagingPath = Join-Path $temporaryRoot "staging"
    $packagePath = Join-Path $temporaryRoot "AudioDeviceCmdlets.3.1.0.2.nupkg"
    [void](New-Item -ItemType Directory -Path $stagingPath -ErrorAction Stop)

    $previousSecurityProtocol = [Net.ServicePointManager]::SecurityProtocol
    try {
      [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
      Save-AudioDevicePackage `
        -Uri $script:AudioDevicePackageUri `
        -DestinationPath $packagePath `
        -MaximumBytes $script:AudioDevicePackageMaximumBytes
    } finally {
      [Net.ServicePointManager]::SecurityProtocol = $previousSecurityProtocol
    }

    Copy-AudioDevicePackageFiles `
      -PackagePath $packagePath `
      -DestinationPath $stagingPath
    Assert-AudioDeviceModuleIntegrity -ModuleRoot $stagingPath

    [void](New-Item -ItemType Directory -Path $paths.Container -Force -ErrorAction Stop)
    Assert-AudioDeviceModulePathAncestors -Paths $paths
    [void](New-Item -ItemType Directory -Path $paths.Root -ErrorAction Stop)
    $targetCreated = $true
    Assert-AudioDeviceModulePathAncestors -Paths $paths

    Copy-Item `
      -LiteralPath (Join-Path $stagingPath $script:AudioDeviceManifestName) `
      -Destination $paths.Manifest `
      -ErrorAction Stop
    Copy-Item `
      -LiteralPath (Join-Path $stagingPath $script:AudioDeviceDllName) `
      -Destination $paths.Dll `
      -ErrorAction Stop
    Assert-AudioDeviceModuleIntegrity -ModuleRoot $paths.Root

    return $true
  } catch {
    if ($targetCreated) {
      Remove-Item -LiteralPath $paths.Root -Recurse -Force -ErrorAction SilentlyContinue
    }
    throw
  } finally {
    if (-not [string]::IsNullOrWhiteSpace($temporaryRoot)) {
      Remove-Item `
        -LiteralPath $temporaryRoot `
        -Recurse `
        -Force `
        -ErrorAction SilentlyContinue
    }
  }
}

Export-ModuleMember -Function Install-AudioDeviceModule
