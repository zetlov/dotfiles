Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-WezTermFontPackages {
  return @(
    [PSCustomObject]@{
      Name = "JetBrains Mono Nerd Font"
      Version = "3.5.0"
      Uri = [uri](
        "https://github.com/ryanoasis/nerd-fonts/releases/download/" +
        "v3.5.0/JetBrainsMono.zip"
      )
      Sha256 = "9577de1ae84ec523df16fc69bac5338b89497a5b4fb91489e2dcb79dc06ac2b5"
      Fonts = @(
        [PSCustomObject]@{
          FileName = "JetBrainsMonoNerdFont-Regular.ttf"
          RegistryName = "JetBrainsMono NF Regular (TrueType)"
        }
        [PSCustomObject]@{
          FileName = "JetBrainsMonoNerdFont-Bold.ttf"
          RegistryName = "JetBrainsMono NF Bold (TrueType)"
        }
        [PSCustomObject]@{
          FileName = "JetBrainsMonoNerdFont-Italic.ttf"
          RegistryName = "JetBrainsMono NF Italic (TrueType)"
        }
        [PSCustomObject]@{
          FileName = "JetBrainsMonoNerdFont-BoldItalic.ttf"
          RegistryName = "JetBrainsMono NF Bold Italic (TrueType)"
        }
      )
    }
    [PSCustomObject]@{
      Name = "Noto Sans Mono CJK JP"
      Version = "2.004"
      Uri = [uri](
        "https://github.com/notofonts/noto-cjk/releases/download/" +
        "Sans2.004/11_NotoSansMonoCJKjp.zip"
      )
      Sha256 = "6c8faf475ce78fa37486dd5d8920e4bb4450b1b0f3c497edf3ba2d25cf52ab78"
      Fonts = @(
        [PSCustomObject]@{
          FileName = "NotoSansMonoCJKjp-Regular.otf"
          RegistryName = "Noto Sans Mono CJK JP (TrueType)"
        }
        [PSCustomObject]@{
          FileName = "NotoSansMonoCJKjp-Bold.otf"
          RegistryName = "Noto Sans Mono CJK JP Bold (TrueType)"
        }
      )
    }
  )
}

function Resolve-RegisteredFontPath {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Value,

    [Parameter(Mandatory = $true)]
    [string]$WindowsFontsDirectory
  )

  if ([System.IO.Path]::IsPathRooted($Value)) {
    return [System.IO.Path]::GetFullPath($Value)
  }
  return [System.IO.Path]::GetFullPath((
    Join-Path $WindowsFontsDirectory $Value
  ))
}

function Get-FontRegistryValue {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RegistryPath,

    [Parameter(Mandatory = $true)]
    [string]$RegistryName
  )

  if (-not (Test-Path -LiteralPath $RegistryPath)) {
    return $null
  }
  try {
    return [string](Get-ItemPropertyValue `
      -LiteralPath $RegistryPath `
      -Name $RegistryName `
      -ErrorAction Stop)
  } catch [System.Management.Automation.PSArgumentException] {
    return $null
  } catch [System.Management.Automation.ItemNotFoundException] {
    return $null
  }
}

function Test-FontRegistration {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RegistryName,

    [Parameter(Mandatory = $true)]
    [string[]]$RegistryPaths,

    [Parameter(Mandatory = $true)]
    [string]$WindowsFontsDirectory
  )

  foreach ($registryPath in $RegistryPaths) {
    $fontValue = Get-FontRegistryValue `
      -RegistryPath $registryPath `
      -RegistryName $RegistryName
    if ([string]::IsNullOrWhiteSpace($fontValue)) {
      continue
    }
    $fontPath = Resolve-RegisteredFontPath `
      -Value ([string]$fontValue) `
      -WindowsFontsDirectory $WindowsFontsDirectory
    if (Test-Path -LiteralPath $fontPath -PathType Leaf) {
      return $true
    }
  }
  return $false
}

function Assert-FontArchiveHash {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [Parameter(Mandatory = $true)]
    [ValidatePattern("^[0-9a-fA-F]{64}$")]
    [string]$ExpectedSha256
  )

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "Font archive not found: $Path"
  }
  $actualSha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
  if ($actualSha256 -ne $ExpectedSha256) {
    throw (
      "Font archive SHA-256 mismatch for ${Path}: " +
      "expected $ExpectedSha256, got $actualSha256"
    )
  }
  return $actualSha256
}

function Install-UserFontFile {
  param(
    [Parameter(Mandatory = $true)]
    [string]$SourcePath,

    [Parameter(Mandatory = $true)]
    [string]$RegistryName,

    [Parameter(Mandatory = $true)]
    [string]$FontsDirectory,

    [Parameter(Mandatory = $true)]
    [string]$RegistryPath
  )

  if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
    throw "Font file not found: $SourcePath"
  }
  $resolvedSourcePath = [System.IO.Path]::GetFullPath($SourcePath)
  $resolvedFontsDirectory = [System.IO.Path]::GetFullPath($FontsDirectory)
  $destinationPath = Join-Path `
    $resolvedFontsDirectory `
    ([System.IO.Path]::GetFileName($resolvedSourcePath))

  $registeredPath = [string](Get-FontRegistryValue `
    -RegistryPath $RegistryPath `
    -RegistryName $RegistryName)
  $registrationMatches = [string]::Equals(
    $registeredPath,
    $destinationPath,
    [System.StringComparison]::OrdinalIgnoreCase
  )
  if (-not [string]::IsNullOrWhiteSpace($registeredPath) -and
      -not $registrationMatches) {
    $registeredFontPath = Resolve-RegisteredFontPath `
      -Value $registeredPath `
      -WindowsFontsDirectory $resolvedFontsDirectory
    if (Test-Path -LiteralPath $registeredFontPath -PathType Leaf) {
      throw (
        "Refusing to replace an existing font registration: " +
        "$RegistryName -> $registeredFontPath"
      )
    }
  }

  New-Item -ItemType Directory -Path $resolvedFontsDirectory -Force | Out-Null

  $fileChanged = $false
  if (Test-Path -LiteralPath $destinationPath -PathType Leaf) {
    $sourceHash = (Get-FileHash -LiteralPath $resolvedSourcePath -Algorithm SHA256).Hash
    $destinationHash = (
      Get-FileHash -LiteralPath $destinationPath -Algorithm SHA256
    ).Hash
    if ($sourceHash -ne $destinationHash) {
      throw "Refusing to overwrite a different existing font: $destinationPath"
    }
  } else {
    $temporaryPath = "$destinationPath.tmp-$([guid]::NewGuid().ToString('N'))"
    try {
      Copy-Item -LiteralPath $resolvedSourcePath -Destination $temporaryPath
      [System.IO.File]::Move($temporaryPath, $destinationPath)
      $fileChanged = $true
    } finally {
      if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
        Remove-Item -LiteralPath $temporaryPath -Force
      }
    }
  }

  $registryChanged = $false
  try {
    if (-not (Test-Path -LiteralPath $RegistryPath)) {
      New-Item -Path $RegistryPath -Force | Out-Null
    }
    if (-not $registrationMatches) {
      New-ItemProperty `
        -LiteralPath $RegistryPath `
        -Name $RegistryName `
        -Value $destinationPath `
        -PropertyType String `
        -Force | Out-Null
      $registryChanged = $true
    }
  } catch {
    if ($fileChanged -and (Test-Path -LiteralPath $destinationPath -PathType Leaf)) {
      Remove-Item -LiteralPath $destinationPath -Force
    }
    throw
  }

  return [PSCustomObject]@{
    Changed = $fileChanged -or $registryChanged
    DestinationPath = $destinationPath
    RegistryName = $RegistryName
  }
}

function Publish-UserFontChanges {
  param(
    [Parameter(Mandatory = $true)]
    [string[]]$FontPaths
  )

  if ($null -eq ("DotfilesFontInstaller.NativeMethods" -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

namespace DotfilesFontInstaller {
  public static class NativeMethods {
    [DllImport("gdi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern int AddFontResourceEx(
      string fileName,
      uint flags,
      IntPtr reserved
    );

    [DllImport("user32.dll", SetLastError = true)]
    public static extern IntPtr SendMessageTimeout(
      IntPtr window,
      uint message,
      IntPtr wordParameter,
      IntPtr longParameter,
      uint flags,
      uint timeout,
      out IntPtr result
    );
  }
}
"@
  }

  foreach ($fontPath in $FontPaths) {
    if (-not (Test-Path -LiteralPath $fontPath -PathType Leaf)) {
      throw "Registered font file not found: $fontPath"
    }
    $loaded = [DotfilesFontInstaller.NativeMethods]::AddFontResourceEx(
      $fontPath,
      0,
      [IntPtr]::Zero
    )
    if ($loaded -eq 0) {
      Write-Warning "Windows did not load the font immediately: $fontPath"
    }
  }

  $broadcastWindow = [IntPtr]0xffff
  $fontChangeMessage = 0x001d
  $abortIfHung = 0x0002
  $result = [IntPtr]::Zero
  [void][DotfilesFontInstaller.NativeMethods]::SendMessageTimeout(
    $broadcastWindow,
    $fontChangeMessage,
    [IntPtr]::Zero,
    [IntPtr]::Zero,
    $abortIfHung,
    1000,
    [ref]$result
  )
}

Export-ModuleMember -Function @(
  "Get-WezTermFontPackages",
  "Test-FontRegistration",
  "Assert-FontArchiveHash",
  "Install-UserFontFile",
  "Publish-UserFontChanges"
)
