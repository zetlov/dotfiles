Describe "Audio output dependency installer" {
  BeforeAll {
    $modulePath = Join-Path $PSScriptRoot "..\AudioOutputInstaller.psm1"
    Import-Module $modulePath -Force -ErrorAction Stop
  }

  It "exports the audio device module installer" {
    $module = Get-Module -Name "AudioOutputInstaller"

    $module | Should -Not -BeNullOrEmpty
    $module.ExportedFunctions.Keys |
      Should -Contain "Install-AudioDeviceModule"
  }

  It "does nothing when the required module version is installed" {
    Mock Get-Module {
      [pscustomobject]@{ Version = [version]"3.1.0.2" }
    } -ModuleName AudioOutputInstaller
    Mock Get-PackageProvider {} -ModuleName AudioOutputInstaller
    Mock Install-PackageProvider {} -ModuleName AudioOutputInstaller
    Mock Install-Module {} -ModuleName AudioOutputInstaller

    $changed = Install-AudioDeviceModule -RequiredVersion "3.1.0.2"

    $changed | Should -BeFalse
    Should -Invoke Get-Module -ModuleName AudioOutputInstaller -Times 1
    Should -Invoke Get-PackageProvider -ModuleName AudioOutputInstaller -Times 0
    Should -Invoke Install-PackageProvider -ModuleName AudioOutputInstaller -Times 0
    Should -Invoke Install-Module -ModuleName AudioOutputInstaller -Times 0
  }

  It "bootstraps NuGet and installs the pinned module for the current user" {
    $script:audioModuleLookupCount = 0
    Mock Get-Module {
      $script:audioModuleLookupCount++
      if ($script:audioModuleLookupCount -gt 1) {
        [pscustomobject]@{ Version = [version]"3.1.0.2" }
      }
    } -ModuleName AudioOutputInstaller
    Mock Get-PackageProvider { $null } -ModuleName AudioOutputInstaller
    Mock Install-PackageProvider {} -ModuleName AudioOutputInstaller
    Mock Install-Module {} -ModuleName AudioOutputInstaller

    $changed = Install-AudioDeviceModule -RequiredVersion "3.1.0.2"

    $changed | Should -BeTrue
    Should -Invoke Install-PackageProvider `
      -ModuleName AudioOutputInstaller `
      -Times 1 `
      -ParameterFilter {
        $Name -eq "NuGet" -and $Scope -eq "CurrentUser" -and $Force
      }
    Should -Invoke Install-Module `
      -ModuleName AudioOutputInstaller `
      -Times 1 `
      -ParameterFilter {
        $Name -eq "AudioDeviceCmdlets" -and
          $RequiredVersion -eq "3.1.0.2" -and
          $Repository -eq "PSGallery" -and
          $Scope -eq "CurrentUser" -and
          $Force -and
          $AllowClobber -and
          $ErrorAction -eq "Stop"
      }
  }

  It "fails when the pinned module is still unavailable after installation" {
    Mock Get-Module { $null } -ModuleName AudioOutputInstaller
    Mock Get-PackageProvider {
      [pscustomobject]@{ Name = "NuGet" }
    } -ModuleName AudioOutputInstaller
    Mock Install-PackageProvider {} -ModuleName AudioOutputInstaller
    Mock Install-Module {} -ModuleName AudioOutputInstaller

    {
      Install-AudioDeviceModule -RequiredVersion "3.1.0.2"
    } | Should -Throw "AudioDeviceCmdlets 3.1.0.2 was not installed."

    Should -Invoke Install-PackageProvider -ModuleName AudioOutputInstaller -Times 0
    Should -Invoke Install-Module -ModuleName AudioOutputInstaller -Times 1
  }
}
