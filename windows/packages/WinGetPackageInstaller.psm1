function Resolve-WindowsNativeArchitecture {
  param(
    [string]$ProcessArchitecture = $env:PROCESSOR_ARCHITECTURE,
    [string]$Wow64Architecture = $env:PROCESSOR_ARCHITEW6432
  )

  $architecture = if (
    -not [string]::IsNullOrWhiteSpace($Wow64Architecture)
  ) {
    $Wow64Architecture
  } else {
    $ProcessArchitecture
  }

  switch -Regex ($architecture) {
    '^ARM64$' { return "arm64" }
    '^(AMD64|X64)$' { return "x64" }
    default {
      throw "Unsupported Windows architecture: $architecture"
    }
  }
}

function Get-WinGetInstallArguments {
  param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]+$')]
    [string]$PackageId,

    [ValidateSet("", "x64", "arm64")]
    [AllowEmptyString()]
    [string]$Architecture = "",

    [ValidatePattern('^[A-Za-z0-9 ._=/:-]*$')]
    [AllowEmptyString()]
    [string]$InstallerOverride = ""
  )

  $arguments = @(
    "install",
    "--id", $PackageId,
    "--exact",
    "--source", "winget",
    "--silent",
    "--disable-interactivity",
    "--accept-source-agreements",
    "--accept-package-agreements"
  )
  if (-not [string]::IsNullOrWhiteSpace($Architecture)) {
    $arguments += @("--architecture", $Architecture)
  }
  if (-not [string]::IsNullOrWhiteSpace($InstallerOverride)) {
    $arguments += @("--override", $InstallerOverride)
  }

  return $arguments
}

function Resolve-InstalledApplicationPath {
  param(
    [Parameter(Mandatory = $true)]
    [string[]]$CandidatePath
  )

  foreach ($path in $CandidatePath) {
    if (
      [string]::IsNullOrWhiteSpace($path) -or
      -not [IO.Path]::IsPathRooted($path)
    ) {
      throw "Application paths must be non-empty absolute paths."
    }
    if (Test-Path -LiteralPath $path -PathType Leaf) {
      return [IO.Path]::GetFullPath($path)
    }
  }

  return $null
}

function Resolve-InstalledAppxPackagePath {
  param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]+$')]
    [string]$PackageName,

    [scriptblock]$PackageResolver
  )

  $packages = if ($null -eq $PackageResolver) {
    @(Get-AppxPackage -Name $PackageName -ErrorAction SilentlyContinue)
  } else {
    @(& $PackageResolver $PackageName)
  }

  foreach ($package in $packages) {
    if ($null -eq $package) {
      continue
    }
    $nameProperty = $package.PSObject.Properties["Name"]
    $pathProperty = $package.PSObject.Properties["InstallLocation"]
    if ($null -eq $nameProperty -or $null -eq $pathProperty) {
      continue
    }
    if (
      -not ([string]$nameProperty.Value).Equals(
        $PackageName,
        [StringComparison]::OrdinalIgnoreCase
      )
    ) {
      continue
    }

    $installLocation = [string]$pathProperty.Value
    if ([string]::IsNullOrWhiteSpace($installLocation)) {
      continue
    }
    if (-not [IO.Path]::IsPathRooted($installLocation)) {
      throw "Appx install locations must be absolute paths."
    }
    if (Test-Path -LiteralPath $installLocation -PathType Container) {
      return [IO.Path]::GetFullPath($installLocation)
    }
  }

  return $null
}

function Install-WinGetPackage {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]+$')]
    [string]$PackageId,

    [string[]]$ExpectedPath = @(),

    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]+$')]
    [AllowEmptyString()]
    [string]$ExpectedAppxPackageName = "",

    [Parameter(Mandatory = $true)]
    [string]$WingetPath,

    [ValidateSet("", "x64", "arm64")]
    [AllowEmptyString()]
    [string]$Architecture = "",

    [ValidatePattern('^[A-Za-z0-9 ._=/:-]*$')]
    [AllowEmptyString()]
    [string]$InstallerOverride = "",

    [scriptblock]$CommandRunner,

    [scriptblock]$AppxPackageResolver
  )

  $hasExpectedPath = $null -ne $ExpectedPath -and $ExpectedPath.Count -gt 0
  $hasExpectedAppx = -not [string]::IsNullOrWhiteSpace(
    $ExpectedAppxPackageName
  )
  if ($hasExpectedPath -eq $hasExpectedAppx) {
    throw (
      "Specify exactly one expected executable path list or Appx package " +
      "name."
    )
  }

  $installedPath = if ($hasExpectedPath) {
    Resolve-InstalledApplicationPath -CandidatePath $ExpectedPath
  } else {
    Resolve-InstalledAppxPackagePath `
      -PackageName $ExpectedAppxPackageName `
      -PackageResolver $AppxPackageResolver
  }
  if ($null -ne $installedPath) {
    return [PSCustomObject]@{
      PackageId = $PackageId
      Changed = $false
      Path = $installedPath
    }
  }
  if (-not (Test-Path -LiteralPath $WingetPath -PathType Leaf)) {
    throw "The official WinGet application alias was not found: $WingetPath"
  }

  $arguments = @(Get-WinGetInstallArguments `
    -PackageId $PackageId `
    -Architecture $Architecture `
    -InstallerOverride $InstallerOverride)
  Write-Host "Installing $PackageId with WinGet..."
  if ($null -eq $CommandRunner) {
    & $WingetPath @arguments
    $exitCode = $LASTEXITCODE
  } else {
    $exitCode = & $CommandRunner $WingetPath ([string[]]$arguments)
  }
  if ([int]$exitCode -ne 0) {
    throw "WinGet failed to install $PackageId (exit code $exitCode)."
  }

  $installedPath = if ($hasExpectedPath) {
    Resolve-InstalledApplicationPath -CandidatePath $ExpectedPath
  } else {
    Resolve-InstalledAppxPackagePath `
      -PackageName $ExpectedAppxPackageName `
      -PackageResolver $AppxPackageResolver
  }
  if ($null -eq $installedPath) {
    throw "WinGet did not install the expected application for $PackageId."
  }

  return [PSCustomObject]@{
    PackageId = $PackageId
    Changed = $true
    Path = $installedPath
  }
}

Export-ModuleMember -Function @(
  "Get-WinGetInstallArguments",
  "Install-WinGetPackage",
  "Resolve-InstalledAppxPackagePath",
  "Resolve-InstalledApplicationPath",
  "Resolve-WindowsNativeArchitecture"
)
