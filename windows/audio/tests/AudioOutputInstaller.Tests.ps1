Describe "Audio output dependency installer" {
  BeforeAll {
    $modulePath = Join-Path $PSScriptRoot "..\AudioOutputInstaller.psm1"
    $moduleSource = Get-Content -LiteralPath $modulePath -Raw
    Import-Module $modulePath -Force -ErrorAction Stop

    $documentsPath = [Environment]::GetFolderPath("MyDocuments")
    $trustedModuleRoot = Join-Path $documentsPath (
      "WindowsPowerShell\Modules\" +
      "AudioDeviceCmdlets\3.1.0.2"
    )
    $trustedManifestPath = Join-Path `
      $trustedModuleRoot `
      "AudioDeviceCmdlets.psd1"
    $trustedDllPath = Join-Path `
      $trustedModuleRoot `
      "AudioDeviceCmdlets.dll"
    $trustedManifestSha256 = (
      "0D657B8DDE3DC9B090716162ED351B68F" +
      "785F50483B92E937528D082469DBFB5"
    )
    $trustedDllSha256 = (
      "2E81666DD09BC835C669DAF9771686FD" +
      "AD5651FBEBB600A234F11AF80CA5D25F"
    )
    $trustedPackageUri = (
      "https://www.powershellgallery.com/api/v2/package/" +
      "AudioDeviceCmdlets/3.1.0.2"
    )

    function Get-TestContentSha256 {
      param([Parameter(Mandatory = $true)][byte[]]$Content)

      $sha256 = [System.Security.Cryptography.SHA256]::Create()
      try {
        return [System.BitConverter]::ToString(
          $sha256.ComputeHash($Content)
        ).Replace("-", "")
      } finally {
        $sha256.Dispose()
      }
    }

    function New-TestAudioPackage {
      param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][object[]]$Entries
      )

      Add-Type -AssemblyName "System.IO.Compression"
      Add-Type -AssemblyName "System.IO.Compression.FileSystem"
      $archive = [System.IO.Compression.ZipFile]::Open(
        $Path,
        [System.IO.Compression.ZipArchiveMode]::Create
      )
      try {
        foreach ($entrySpecification in $Entries) {
          $entry = $archive.CreateEntry([string]$entrySpecification.Name)
          $stream = $entry.Open()
          try {
            $content = [byte[]]$entrySpecification.Content
            $stream.Write($content, 0, $content.Length)
          } finally {
            $stream.Dispose()
          }
        }
      } finally {
        $archive.Dispose()
      }
    }
  }

  BeforeEach {
    Mock Test-Path {
      $LiteralPath -in @($trustedManifestPath, $trustedDllPath)
    } -ModuleName AudioOutputInstaller
    Mock Get-FileHash {
      if ($LiteralPath -eq $trustedManifestPath) {
        return [pscustomobject]@{ Hash = $trustedManifestSha256 }
      }
      if ($LiteralPath -eq $trustedDllPath) {
        return [pscustomobject]@{ Hash = $trustedDllSha256 }
      }
      throw "Unexpected hash path: $LiteralPath"
    } -ModuleName AudioOutputInstaller
    Mock Get-Item {
      [pscustomobject]@{
        Attributes = [System.IO.FileAttributes]::Normal
      }
    } -ModuleName AudioOutputInstaller
    Mock Get-Module {
      throw "PSModulePath discovery must not be used."
    } -ModuleName AudioOutputInstaller
    Mock Get-PackageProvider { $null } -ModuleName AudioOutputInstaller
    Mock Install-PackageProvider {} -ModuleName AudioOutputInstaller
    Mock Install-Module {} -ModuleName AudioOutputInstaller
    Mock Save-AudioDevicePackage {
      throw "download intercepted"
    } -ModuleName AudioOutputInstaller
  }

  It "exports the audio device module installer" {
    $module = Get-Module -Name "AudioOutputInstaller"

    $module | Should -Not -BeNullOrEmpty
    $module.ExportedFunctions.Keys |
      Should -Contain "Install-AudioDeviceModule"
  }

  It "accepts only the exact CurrentUser module files and hashes" {
    $changed = Install-AudioDeviceModule -RequiredVersion "3.1.0.2"

    $changed | Should -BeFalse
    Should -Invoke Get-FileHash `
      -ModuleName AudioOutputInstaller `
      -Times 1 `
      -ParameterFilter {
        $LiteralPath -eq $trustedManifestPath -and $Algorithm -eq "SHA256"
      }
    Should -Invoke Get-FileHash `
      -ModuleName AudioOutputInstaller `
      -Times 1 `
      -ParameterFilter {
        $LiteralPath -eq $trustedDllPath -and $Algorithm -eq "SHA256"
      }
  }

  It "ignores an earlier malicious same-name module on PSModulePath" {
    Mock Get-Module {
      [pscustomobject]@{
        Name = "AudioDeviceCmdlets"
        Version = [version]"3.1.0.2"
        ModuleBase = "C:\attacker\AudioDeviceCmdlets\3.1.0.2"
        Path = "C:\attacker\AudioDeviceCmdlets.psd1"
      }
    } -ModuleName AudioOutputInstaller

    $changed = Install-AudioDeviceModule -RequiredVersion "3.1.0.2"

    $changed | Should -BeFalse
    Should -Invoke Get-Module -ModuleName AudioOutputInstaller -Times 0
    Should -Invoke Get-FileHash `
      -ModuleName AudioOutputInstaller `
      -Times 0 `
      -ParameterFilter { $LiteralPath -like "C:\attacker\*" }
  }

  It "rejects a trusted-path installation with a mismatched manifest hash" {
    Mock Get-FileHash {
      if ($LiteralPath -eq $trustedManifestPath) {
        return [pscustomobject]@{ Hash = ("0" * 64) }
      }
      return [pscustomobject]@{ Hash = $trustedDllSha256 }
    } -ModuleName AudioOutputInstaller

    {
      Install-AudioDeviceModule -RequiredVersion "3.1.0.2"
    } | Should -Throw "*integrity*"

    Should -Invoke Save-AudioDevicePackage `
      -ModuleName AudioOutputInstaller `
      -Times 0
  }

  It "rejects a trusted-path installation with a mismatched DLL hash" {
    Mock Get-FileHash {
      if ($LiteralPath -eq $trustedDllPath) {
        return [pscustomobject]@{ Hash = ("0" * 64) }
      }
      return [pscustomobject]@{ Hash = $trustedManifestSha256 }
    } -ModuleName AudioOutputInstaller

    {
      Install-AudioDeviceModule -RequiredVersion "3.1.0.2"
    } | Should -Throw "*integrity*"

    Should -Invoke Save-AudioDevicePackage `
      -ModuleName AudioOutputInstaller `
      -Times 0
  }

  It "downloads only the pinned package from its fixed Gallery URI" {
    Mock Test-Path { $false } -ModuleName AudioOutputInstaller

    {
      Install-AudioDeviceModule -RequiredVersion "3.1.0.2"
    } | Should -Throw "download intercepted"

    Should -Invoke Save-AudioDevicePackage `
      -ModuleName AudioOutputInstaller `
      -Times 1 `
      -ParameterFilter {
        $Uri -eq $trustedPackageUri -and
          -not [string]::IsNullOrWhiteSpace([string]$DestinationPath) -and
          $MaximumBytes -eq 1MB
      }
    Should -Invoke Get-PackageProvider -ModuleName AudioOutputInstaller -Times 0
    Should -Invoke Install-PackageProvider -ModuleName AudioOutputInstaller -Times 0
    Should -Invoke Install-Module -ModuleName AudioOutputInstaller -Times 0
  }

  It "pins package identity and integrity without PackageManagement" {
    $moduleSource | Should -Match 'powershellgallery\.com/api/v2/package/'
    $moduleSource | Should -Match 'AudioDeviceCmdlets/3\.1\.0\.2'
    foreach ($hashPart in @(
      "0D657B8DDE3DC9B090716162ED351B68F",
      "785F50483B92E937528D082469DBFB5",
      "2E81666DD09BC835C669DAF9771686FD",
      "AD5651FBEBB600A234F11AF80CA5D25F"
    )) {
      $moduleSource | Should -Match $hashPart
    }
    $moduleSource | Should -Match 'GetFolderPath\("MyDocuments"\)'
    $moduleSource | Should -Match '"WindowsPowerShell"'
    $moduleSource | Should -Match '"Modules"'
    $moduleSource | Should -Not -Match '(?m)^\s*Install-Module\b'
    $moduleSource | Should -Not -Match '(?m)^\s*(Get|Install)-PackageProvider\b'
    $moduleSource | Should -Not -Match '(?m)^\s*Invoke-WebRequest\b'
    $moduleSource | Should -Match 'Copy-BoundedAudioPackageStream'
  }

  It "selectively extracts the two module files without Expand-Archive" {
    $moduleSource | Should -Match 'System\.IO\.Compression\.ZipArchive'
    $moduleSource | Should -Match 'AudioDeviceCmdlets\.psd1'
    $moduleSource | Should -Match 'AudioDeviceCmdlets\.dll'
    $moduleSource | Should -Not -Match '(?m)^\s*Expand-Archive\b'
  }

  Context "transactional package installation" {
    BeforeEach {
      $testDocumentsPath = Join-Path `
        $TestDrive `
        ([guid]::NewGuid().ToString("N"))
      $testPackagePath = Join-Path $TestDrive (
        [guid]::NewGuid().ToString("N") + ".nupkg"
      )
      $testManifestContent = [Text.Encoding]::UTF8.GetBytes(
        "@{ ModuleVersion = '3.1.0.2' }"
      )
      $testDllContent = [Text.Encoding]::UTF8.GetBytes("test assembly")
      $testManifestHash = Get-TestContentSha256 $testManifestContent
      $testDllHash = Get-TestContentSha256 $testDllContent
      $testEntries = @(
        [pscustomobject]@{
          Name = "AudioDeviceCmdlets.psd1"
          Content = $testManifestContent
        },
        [pscustomobject]@{
          Name = "AudioDeviceCmdlets.dll"
          Content = $testDllContent
        },
        [pscustomobject]@{
          Name = "tools\ignored.ps1"
          Content = [Text.Encoding]::UTF8.GetBytes("not installed")
        }
      )
      New-TestAudioPackage -Path $testPackagePath -Entries $testEntries

      InModuleScope AudioOutputInstaller -Parameters @{
        ManifestHash = $testManifestHash
        DllHash = $testDllHash
        ManifestBytes = $testManifestContent.Length
        DllBytes = $testDllContent.Length
        PackageMaximumBytes = 1MB
      } {
        param(
          $ManifestHash,
          $DllHash,
          $ManifestBytes,
          $DllBytes,
          $PackageMaximumBytes
        )
        $script:AudioDeviceManifestSha256 = $ManifestHash
        $script:AudioDeviceDllSha256 = $DllHash
        $script:AudioDeviceManifestBytes = $ManifestBytes
        $script:AudioDeviceDllBytes = $DllBytes
        $script:AudioDevicePackageMaximumBytes = $PackageMaximumBytes
      }

      Mock Test-Path {
        $requestedPathType = if (
          $null -ne (Get-Variable -Name PathType -ErrorAction SilentlyContinue)
        ) {
          $PathType
        } else {
          "Any"
        }
        if ($requestedPathType -eq "Leaf") {
          return [System.IO.File]::Exists($LiteralPath)
        }
        if ($requestedPathType -eq "Container") {
          return [System.IO.Directory]::Exists($LiteralPath)
        }
        return (
          [System.IO.File]::Exists($LiteralPath) -or
          [System.IO.Directory]::Exists($LiteralPath)
        )
      } -ModuleName AudioOutputInstaller
      Mock Get-FileHash {
        Microsoft.PowerShell.Utility\Get-FileHash `
          -LiteralPath $LiteralPath `
          -Algorithm $Algorithm
      } -ModuleName AudioOutputInstaller
      Mock Get-Item {
        Microsoft.PowerShell.Management\Get-Item `
          -LiteralPath $LiteralPath `
          -Force `
          -ErrorAction Stop
      } -ModuleName AudioOutputInstaller
      Mock Save-AudioDevicePackage {
        $global:AudioInstallerTestTemporaryRoot = Split-Path `
          -Parent `
          $DestinationPath
        [System.IO.File]::Copy($testPackagePath, $DestinationPath)
      } -ModuleName AudioOutputInstaller
      Remove-Variable `
        -Name AudioInstallerTestTemporaryRoot `
        -Scope Global `
        -ErrorAction SilentlyContinue
    }

    AfterEach {
      Remove-Variable `
        -Name AudioInstallerTestTemporaryRoot `
        -Scope Global `
        -ErrorAction SilentlyContinue
      Remove-Variable `
        -Name AudioInstallerTestObservedProtocol `
        -Scope Global `
        -ErrorAction SilentlyContinue
    }

    It "installs exactly the two reviewed files into an injected Documents path" {
      $changed = Install-AudioDeviceModule `
        -RequiredVersion "3.1.0.2" `
        -DocumentsPath $testDocumentsPath

      $changed | Should -BeTrue
      $installedRoot = Join-Path $testDocumentsPath (
        "WindowsPowerShell\Modules\AudioDeviceCmdlets\3.1.0.2"
      )
      $installedFiles = @(Get-ChildItem -LiteralPath $installedRoot -File)
      $installedFiles.Name | Should -Be @(
        "AudioDeviceCmdlets.dll",
        "AudioDeviceCmdlets.psd1"
      )
      Get-Content `
        -LiteralPath (Join-Path $installedRoot "AudioDeviceCmdlets.psd1") `
        -Raw |
        Should -Be ([Text.Encoding]::UTF8.GetString($testManifestContent))
      Test-Path -LiteralPath $global:AudioInstallerTestTemporaryRoot |
        Should -BeFalse
    }

    It "rejects a package with a duplicate reviewed entry before creating the target" {
      Remove-Item -LiteralPath $testPackagePath -Force
      New-TestAudioPackage -Path $testPackagePath -Entries @(
        $testEntries[0],
        $testEntries[0],
        $testEntries[1]
      )

      {
        Install-AudioDeviceModule `
          -RequiredVersion "3.1.0.2" `
          -DocumentsPath $testDocumentsPath
      } | Should -Throw "*exactly one root entry*"

      $installedRoot = Join-Path $testDocumentsPath (
        "WindowsPowerShell\Modules\AudioDeviceCmdlets\3.1.0.2"
      )
      Test-Path -LiteralPath $installedRoot | Should -BeFalse
      Test-Path -LiteralPath $global:AudioInstallerTestTemporaryRoot |
        Should -BeFalse
    }

    It "rejects a package with a missing reviewed entry before creating the target" {
      Remove-Item -LiteralPath $testPackagePath -Force
      New-TestAudioPackage -Path $testPackagePath -Entries @($testEntries[0])

      {
        Install-AudioDeviceModule `
          -RequiredVersion "3.1.0.2" `
          -DocumentsPath $testDocumentsPath
      } | Should -Throw "*exactly one root entry*"

      $installedRoot = Join-Path $testDocumentsPath (
        "WindowsPowerShell\Modules\AudioDeviceCmdlets\3.1.0.2"
      )
      Test-Path -LiteralPath $installedRoot | Should -BeFalse
    }

    It "rejects a staged hash mismatch before creating the target" {
      InModuleScope AudioOutputInstaller {
        $script:AudioDeviceDllSha256 = "0" * 64
      }

      {
        Install-AudioDeviceModule `
          -RequiredVersion "3.1.0.2" `
          -DocumentsPath $testDocumentsPath
      } | Should -Throw "*integrity*"

      $installedRoot = Join-Path $testDocumentsPath (
        "WindowsPowerShell\Modules\AudioDeviceCmdlets\3.1.0.2"
      )
      Test-Path -LiteralPath $installedRoot | Should -BeFalse
    }

    It "rejects an oversized package before opening the archive" {
      $boundedDestination = Join-Path $TestDrive (
        [guid]::NewGuid().ToString("N") + ".nupkg"
      )
      InModuleScope AudioOutputInstaller -Parameters @{
        DestinationPath = $boundedDestination
      } {
        param($DestinationPath)
        $inputStream = New-Object `
          -TypeName System.IO.MemoryStream `
          -ArgumentList (,[byte[]]@(1, 2, 3, 4))
        try {
          {
            Copy-BoundedAudioPackageStream `
              -InputStream $inputStream `
              -DestinationPath $DestinationPath `
              -MaximumBytes 3
          } | Should -Throw "*package is too large*"
        } finally {
          $inputStream.Dispose()
        }
      }
      Test-Path -LiteralPath $boundedDestination | Should -BeFalse
    }

    It "rejects an unexpected reviewed entry size before creating the target" {
      InModuleScope AudioOutputInstaller {
        $script:AudioDeviceManifestBytes++
      }

      {
        Install-AudioDeviceModule `
          -RequiredVersion "3.1.0.2" `
          -DocumentsPath $testDocumentsPath
      } | Should -Throw "*archive entry size*"

      $installedRoot = Join-Path $testDocumentsPath (
        "WindowsPowerShell\Modules\AudioDeviceCmdlets\3.1.0.2"
      )
      Test-Path -LiteralPath $installedRoot | Should -BeFalse
    }

    It "rejects a reparse point below the trusted Documents root" {
      $windowsPowerShellPath = Join-Path $testDocumentsPath "WindowsPowerShell"
      [void](New-Item -ItemType Directory -Path $windowsPowerShellPath)
      Mock Get-Item {
        if ($LiteralPath -eq $windowsPowerShellPath) {
          return [pscustomobject]@{
            Attributes = [System.IO.FileAttributes]::ReparsePoint
          }
        }
        Microsoft.PowerShell.Management\Get-Item `
          -LiteralPath $LiteralPath `
          -Force `
          -ErrorAction Stop
      } -ModuleName AudioOutputInstaller

      {
        Install-AudioDeviceModule `
          -RequiredVersion "3.1.0.2" `
          -DocumentsPath $testDocumentsPath
      } | Should -Throw "*reparse point*"

      Should -Invoke Save-AudioDevicePackage `
        -ModuleName AudioOutputInstaller `
        -Times 0
    }

    It "rolls back the target when copying a reviewed file fails" {
      Mock Copy-Item {
        throw "copy failed"
      } -ModuleName AudioOutputInstaller -ParameterFilter {
        $Destination -like "$testDocumentsPath*"
      }

      {
        Install-AudioDeviceModule `
          -RequiredVersion "3.1.0.2" `
          -DocumentsPath $testDocumentsPath
      } | Should -Throw "copy failed"

      $installedRoot = Join-Path $testDocumentsPath (
        "WindowsPowerShell\Modules\AudioDeviceCmdlets\3.1.0.2"
      )
      Test-Path -LiteralPath $installedRoot | Should -BeFalse
    }

    It "rolls back the target when post-copy verification fails" {
      Mock Get-FileHash {
        if ($LiteralPath -like "$testDocumentsPath*") {
          return [pscustomobject]@{ Hash = ("0" * 64) }
        }
        Microsoft.PowerShell.Utility\Get-FileHash `
          -LiteralPath $LiteralPath `
          -Algorithm $Algorithm
      } -ModuleName AudioOutputInstaller

      {
        Install-AudioDeviceModule `
          -RequiredVersion "3.1.0.2" `
          -DocumentsPath $testDocumentsPath
      } | Should -Throw "*integrity*"

      $installedRoot = Join-Path $testDocumentsPath (
        "WindowsPowerShell\Modules\AudioDeviceCmdlets\3.1.0.2"
      )
      Test-Path -LiteralPath $installedRoot | Should -BeFalse
    }

    It "restores TLS and removes temporary files when download fails" {
      Mock Save-AudioDevicePackage {
        $global:AudioInstallerTestTemporaryRoot = Split-Path `
          -Parent `
          $DestinationPath
        $global:AudioInstallerTestObservedProtocol = (
          [Net.ServicePointManager]::SecurityProtocol
        )
        throw "download failed"
      } -ModuleName AudioOutputInstaller
      $originalProtocol = [Net.ServicePointManager]::SecurityProtocol
      $beforeCallProtocol = [Net.SecurityProtocolType]::Tls11

      try {
        [Net.ServicePointManager]::SecurityProtocol = $beforeCallProtocol
        {
          Install-AudioDeviceModule `
            -RequiredVersion "3.1.0.2" `
            -DocumentsPath $testDocumentsPath
        } | Should -Throw "download failed"

        $global:AudioInstallerTestObservedProtocol |
          Should -Be ([Net.SecurityProtocolType]::Tls12)
        [Net.ServicePointManager]::SecurityProtocol |
          Should -Be $beforeCallProtocol
        Test-Path -LiteralPath $global:AudioInstallerTestTemporaryRoot |
          Should -BeFalse
      } finally {
        [Net.ServicePointManager]::SecurityProtocol = $originalProtocol
      }
    }
  }
}
