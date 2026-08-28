Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Assert-AudioSwitcherPathIsNotReparsePoint {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Description
  )

  $currentPath = [IO.Path]::GetFullPath($Path)
  while (-not [string]::IsNullOrWhiteSpace($currentPath)) {
    if (Test-Path -LiteralPath $currentPath) {
      $item = Get-Item `
        -LiteralPath $currentPath `
        -Force `
        -ErrorAction Stop
      if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw "$Description cannot use a reparse point: $currentPath"
      }
    }

    $parent = [IO.Directory]::GetParent($currentPath)
    if ($null -eq $parent) {
      break
    }
    $parentPath = $parent.FullName
    if ($parentPath.Equals(
      $currentPath,
      [StringComparison]::OrdinalIgnoreCase
    )) {
      break
    }
    $currentPath = $parentPath
  }
}

function Resolve-AudioOutputConfigSource {
  param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [Parameter(Mandatory = $true)][string]$LegacySourceRoot
  )

  $candidates = @(
    (Join-Path $SourceRoot "audio-output.local.json"),
    (Join-Path $LegacySourceRoot "audio-output.local.json"),
    (Join-Path $SourceRoot "audio-output.json")
  )
  foreach ($candidate in $candidates) {
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
      return $candidate
    }
  }
  throw "Audio output configuration is missing under: $SourceRoot"
}

function Get-AudioSwitcherPowerShellArguments {
  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ScriptPath
  )

  if ($ScriptPath.IndexOfAny([char[]]@('"', "`r", "`n")) -ge 0) {
    throw "The audio switch script path contains unsupported characters."
  }
  return (
    '-NoProfile -NonInteractive -WindowStyle Hidden ' +
    '-ExecutionPolicy Bypass -File "' + $ScriptPath + '"'
  )
}

function Test-AudioSwitcherShortcutSpec {
  param(
    [Parameter(Mandatory = $true)][string]$ShortcutPath,
    [Parameter(Mandatory = $true)][string]$ExpectedTarget,
    [Parameter(Mandatory = $true)][string]$ExpectedArguments,
    [Parameter(Mandatory = $true)][string]$ExpectedWorkingDirectory,
    [Parameter(Mandatory = $true)][string]$ExpectedHotkey
  )

  if (-not (Test-Path -LiteralPath $ShortcutPath -PathType Leaf)) {
    return $false
  }
  try {
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($ShortcutPath)
    $targetMatches = [IO.Path]::GetFullPath(
      [string]$shortcut.TargetPath
    ).Equals(
      [IO.Path]::GetFullPath($ExpectedTarget),
      [StringComparison]::OrdinalIgnoreCase
    )
    $workingDirectoryMatches = [IO.Path]::GetFullPath(
      [string]$shortcut.WorkingDirectory
    ).Equals(
      [IO.Path]::GetFullPath($ExpectedWorkingDirectory),
      [StringComparison]::OrdinalIgnoreCase
    )
    $argumentsMatch = [string]::Equals(
      [string]$shortcut.Arguments,
      $ExpectedArguments,
      [StringComparison]::Ordinal
    )
    $actualHotkey = @(
      ([string]$shortcut.Hotkey) -split "\+" |
        ForEach-Object { $_.Trim() } |
        Sort-Object
    ) -join "+"
    $expectedHotkey = @(
      $ExpectedHotkey -split "\+" |
        ForEach-Object { $_.Trim() } |
        Sort-Object
    ) -join "+"
    $hotkeyMatches = [string]::Equals(
      $actualHotkey,
      $expectedHotkey,
      [StringComparison]::OrdinalIgnoreCase
    )
    return (
      $targetMatches -and
      $workingDirectoryMatches -and
      $argumentsMatch -and
      $hotkeyMatches
    )
  } catch {
    return $false
  }
}

function Install-AudioSwitcherShortcut {
  param(
    [Parameter(Mandatory = $true)][string]$ShortcutPath,
    [Parameter(Mandatory = $true)][string]$TargetPath,
    [Parameter(Mandatory = $true)][string]$Arguments,
    [Parameter(Mandatory = $true)][string]$WorkingDirectory,
    [Parameter(Mandatory = $true)][string]$Hotkey,
    [switch]$Force
  )

  if (-not $ShortcutPath.EndsWith(
    ".lnk",
    [StringComparison]::OrdinalIgnoreCase
  )) {
    throw "The audio shortcut path must end in .lnk."
  }
  if (-not (Test-Path -LiteralPath $TargetPath -PathType Leaf)) {
    throw "The audio shortcut target is missing: $TargetPath"
  }
  if (-not (Test-Path -LiteralPath $WorkingDirectory -PathType Container)) {
    throw "The audio shortcut working directory is missing: $WorkingDirectory"
  }
  Assert-AudioSwitcherPathIsNotReparsePoint `
    -Path $ShortcutPath `
    -Description "The audio shortcut path"
  Assert-AudioSwitcherPathIsNotReparsePoint `
    -Path $TargetPath `
    -Description "The audio shortcut target"
  Assert-AudioSwitcherPathIsNotReparsePoint `
    -Path $WorkingDirectory `
    -Description "The audio shortcut working directory"

  $matches = Test-AudioSwitcherShortcutSpec `
    -ShortcutPath $ShortcutPath `
    -ExpectedTarget $TargetPath `
    -ExpectedArguments $Arguments `
    -ExpectedWorkingDirectory $WorkingDirectory `
    -ExpectedHotkey $Hotkey
  if (
    (Test-Path -LiteralPath $ShortcutPath -PathType Leaf) -and
    -not $matches -and
    -not $Force
  ) {
    throw "Refusing to replace a modified audio shortcut: $ShortcutPath"
  }

  $shortcutDirectory = Split-Path -Parent $ShortcutPath
  New-Item -ItemType Directory -Path $shortcutDirectory -Force | Out-Null
  $shell = New-Object -ComObject WScript.Shell
  $shortcut = $shell.CreateShortcut($ShortcutPath)
  $shortcut.TargetPath = $TargetPath
  $shortcut.Arguments = $Arguments
  $shortcut.WorkingDirectory = $WorkingDirectory
  $shortcut.Hotkey = $Hotkey
  $shortcut.WindowStyle = 7
  $shortcut.Description = "Switch between configured audio outputs"
  $shortcut.Save()

  if (-not (Test-AudioSwitcherShortcutSpec `
    -ShortcutPath $ShortcutPath `
    -ExpectedTarget $TargetPath `
    -ExpectedArguments $Arguments `
    -ExpectedWorkingDirectory $WorkingDirectory `
    -ExpectedHotkey $Hotkey
  )) {
    throw "The audio shortcut did not match the requested specification."
  }
  return $ShortcutPath
}

function Install-AudioSwitcherManagedFile {
  param(
    [Parameter(Mandatory = $true)][string]$SourcePath,
    [Parameter(Mandatory = $true)][string]$DestinationPath
  )

  if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
    throw "Managed audio source file is missing: $SourcePath"
  }
  Assert-AudioSwitcherPathIsNotReparsePoint `
    -Path $SourcePath `
    -Description "The managed audio source"
  Assert-AudioSwitcherPathIsNotReparsePoint `
    -Path $DestinationPath `
    -Description "The managed audio destination"

  $sourceHash = (
    Get-FileHash -LiteralPath $SourcePath -Algorithm SHA256
  ).Hash
  if (Test-Path -LiteralPath $DestinationPath -PathType Leaf) {
    $destinationHash = (
      Get-FileHash -LiteralPath $DestinationPath -Algorithm SHA256
    ).Hash
    if ($sourceHash -eq $destinationHash) {
      return $false
    }
  }

  $destinationDirectory = Split-Path -Parent $DestinationPath
  New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
  $temporaryPath = "{0}.{1}.tmp" -f `
    $DestinationPath, `
    ([guid]::NewGuid().ToString("N"))
  try {
    Copy-Item -LiteralPath $SourcePath -Destination $temporaryPath
    $temporaryHash = (
      Get-FileHash -LiteralPath $temporaryPath -Algorithm SHA256
    ).Hash
    if ($temporaryHash -ne $sourceHash) {
      throw "Managed audio file staging integrity check failed."
    }
    Move-Item `
      -LiteralPath $temporaryPath `
      -Destination $DestinationPath `
      -Force
    $installedHash = (
      Get-FileHash -LiteralPath $DestinationPath -Algorithm SHA256
    ).Hash
    if ($installedHash -ne $sourceHash) {
      throw "Managed audio file installation integrity check failed."
    }
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) {
      Remove-Item -LiteralPath $temporaryPath -Force
    }
  }
  return $true
}

Export-ModuleMember -Function @(
  "Resolve-AudioOutputConfigSource",
  "Get-AudioSwitcherPowerShellArguments",
  "Test-AudioSwitcherShortcutSpec",
  "Install-AudioSwitcherShortcut",
  "Install-AudioSwitcherManagedFile"
)
