Describe "WinGet package installer" {
  BeforeAll {
    $modulePath = Join-Path $PSScriptRoot "..\WinGetPackageInstaller.psm1"
    Import-Module $modulePath -Force -ErrorAction Stop

    function Assert-Equal {
      param($Actual, $Expected)
      if ($Actual -ne $Expected) {
        throw "Expected '$Expected', got '$Actual'."
      }
    }

    function Assert-Throws {
      param([scriptblock]$Operation)
      try {
        & $Operation
      } catch {
        return
      }
      throw "Expected the operation to throw."
    }
  }

  It "builds a noninteractive exact WinGet install command" {
    $arguments = @(Get-WinGetInstallArguments `
      -PackageId "wez.wezterm" `
      -Architecture "x64")

    $arguments | Should -Be @(
      "install",
      "--id", "wez.wezterm",
      "--exact",
      "--source", "winget",
      "--silent",
      "--disable-interactivity",
      "--accept-source-agreements",
      "--accept-package-agreements",
      "--architecture", "x64"
    )
  }

  It "lets WinGet choose the native Docker Desktop architecture" {
    $override = (
      "install --user --quiet --accept-license " +
      "--backend=wsl-2 --no-windows-containers"
    )
    $arguments = @(Get-WinGetInstallArguments `
      -PackageId "Docker.DockerDesktop" `
      -InstallerOverride $override)

    $arguments | Should -Not -Contain "--architecture"
    $arguments[-2] | Should -Be "--override"
    $arguments[-1] | Should -Be $override
  }

  It "rejects unsafe package identifiers and unsupported architectures" {
    Assert-Throws {
      Get-WinGetInstallArguments -PackageId "wez.wezterm;whoami"
    }
    Assert-Throws {
      Get-WinGetInstallArguments `
        -PackageId "wez.wezterm" `
        -Architecture "mips"
    }
    Assert-Throws {
      Get-WinGetInstallArguments `
        -PackageId "wez.wezterm" `
        -InstallerOverride 'install --quiet; whoami'
    }
  }

  It "detects native ARM64 even from an emulated process" {
    Assert-Equal (
      Resolve-WindowsNativeArchitecture `
        -ProcessArchitecture "AMD64" `
        -Wow64Architecture "ARM64"
    ) "arm64"
    Assert-Equal (
      Resolve-WindowsNativeArchitecture `
        -ProcessArchitecture "AMD64"
    ) "x64"
  }

  It "returns the first existing executable path" {
    $firstPath = Join-Path $TestDrive "missing.exe"
    $secondPath = Join-Path $TestDrive "application.exe"
    [IO.File]::WriteAllText($secondPath, "test")

    Assert-Equal (
      Resolve-InstalledApplicationPath `
        -CandidatePath @($firstPath, $secondPath)
    ) ([IO.Path]::GetFullPath($secondPath))
  }

  It "resolves an installed Appx package location" {
    $installLocation = Join-Path $TestDrive "Agilebits.1Password"
    [void](New-Item -ItemType Directory -Path $installLocation)
    $resolver = {
      param($PackageName)
      if ($PackageName -ne "Agilebits.1Password") {
        throw "Unexpected package name: $PackageName"
      }
      return [PSCustomObject]@{
        Name = "Agilebits.1Password"
        InstallLocation = $installLocation
      }
    }.GetNewClosure()

    Assert-Equal (
      Resolve-InstalledAppxPackagePath `
        -PackageName "Agilebits.1Password" `
        -PackageResolver $resolver
    ) ([IO.Path]::GetFullPath($installLocation))
  }

  It "does not invoke WinGet for an existing application" {
    $applicationPath = Join-Path $TestDrive "existing.exe"
    $wingetPath = Join-Path $TestDrive "winget.exe"
    [IO.File]::WriteAllText($applicationPath, "test")
    [IO.File]::WriteAllText($wingetPath, "test")
    $runner = { throw "WinGet must not run." }

    $result = Install-WinGetPackage `
      -PackageId "wez.wezterm" `
      -ExpectedPath $applicationPath `
      -WingetPath $wingetPath `
      -CommandRunner $runner

    Assert-Equal $result.Changed $false
    Assert-Equal $result.Path ([IO.Path]::GetFullPath($applicationPath))
  }

  It "installs a missing application and verifies its executable" {
    $applicationPath = Join-Path $TestDrive "installed.exe"
    $wingetPath = Join-Path $TestDrive "winget.exe"
    [IO.File]::WriteAllText($wingetPath, "test")
    $runner = {
      param($Executable, $Arguments)
      [IO.File]::WriteAllText($applicationPath, "installed")
      return 0
    }.GetNewClosure()

    $result = Install-WinGetPackage `
      -PackageId "Docker.DockerDesktop" `
      -ExpectedPath $applicationPath `
      -WingetPath $wingetPath `
      -CommandRunner $runner

    Assert-Equal $result.Changed $true
    Assert-Equal $result.Path ([IO.Path]::GetFullPath($applicationPath))
  }

  It "does not invoke WinGet for an existing Appx package" {
    $installLocation = Join-Path $TestDrive "existing-appx"
    $wingetPath = Join-Path $TestDrive "winget.exe"
    [void](New-Item -ItemType Directory -Path $installLocation)
    [IO.File]::WriteAllText($wingetPath, "test")
    $resolver = {
      return [PSCustomObject]@{
        Name = "Agilebits.1Password"
        InstallLocation = $installLocation
      }
    }.GetNewClosure()
    $runner = { throw "WinGet must not run." }

    $result = Install-WinGetPackage `
      -PackageId "AgileBits.1Password" `
      -ExpectedAppxPackageName "Agilebits.1Password" `
      -WingetPath $wingetPath `
      -AppxPackageResolver $resolver `
      -CommandRunner $runner

    Assert-Equal $result.Changed $false
    Assert-Equal $result.Path ([IO.Path]::GetFullPath($installLocation))
  }

  It "installs a missing Appx package and verifies its registration" {
    $installLocation = Join-Path $TestDrive "installed-appx"
    $wingetPath = Join-Path $TestDrive "winget.exe"
    [IO.File]::WriteAllText($wingetPath, "test")
    $state = [PSCustomObject]@{ Installed = $false }
    $resolver = {
      if (-not $state.Installed) {
        return $null
      }
      return [PSCustomObject]@{
        Name = "Agilebits.1Password"
        InstallLocation = $installLocation
      }
    }.GetNewClosure()
    $runner = {
      param($Executable, $Arguments)
      [void](New-Item -ItemType Directory -Path $installLocation)
      $state.Installed = $true
      return 0
    }.GetNewClosure()

    $result = Install-WinGetPackage `
      -PackageId "AgileBits.1Password" `
      -ExpectedAppxPackageName "Agilebits.1Password" `
      -WingetPath $wingetPath `
      -AppxPackageResolver $resolver `
      -CommandRunner $runner

    Assert-Equal $result.Changed $true
    Assert-Equal $result.Path ([IO.Path]::GetFullPath($installLocation))
  }

  It "fails when WinGet succeeds without installing the executable" {
    $applicationPath = Join-Path $TestDrive "absent.exe"
    $wingetPath = Join-Path $TestDrive "winget.exe"
    [IO.File]::WriteAllText($wingetPath, "test")
    $runner = { return 0 }

    Assert-Throws {
      Install-WinGetPackage `
        -PackageId "Docker.DockerDesktop" `
        -ExpectedPath $applicationPath `
        -WingetPath $wingetPath `
        -CommandRunner $runner
    }
  }

  It "rejects ambiguous install detection inputs" {
    $wingetPath = Join-Path $TestDrive "winget.exe"
    [IO.File]::WriteAllText($wingetPath, "test")

    Assert-Throws {
      Install-WinGetPackage `
        -PackageId "AgileBits.1Password" `
        -ExpectedPath $wingetPath `
        -ExpectedAppxPackageName "Agilebits.1Password" `
        -WingetPath $wingetPath
    }
  }
}
