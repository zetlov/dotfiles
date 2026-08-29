Describe "Monitor profile management" {
BeforeAll {
  $componentRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
  $modulePath = Join-Path $componentRoot "MonitorProfiles.psm1"
  $installScriptPath = Join-Path $componentRoot "install.ps1"
  $switchScriptPath = Join-Path $componentRoot "Switch-MonitorProfile.ps1"
  Import-Module $modulePath -Force
}

Context "Pinned DisplayConfig dependency" {
  It "uses the reviewed PowerShell Gallery package" {
    $spec = Get-DisplayConfigReleaseSpec

    $spec.Version | Should -Be "6.0.0"
    $spec.Uri.Scheme | Should -Be "https"
    $spec.Uri.Host | Should -Be "www.powershellgallery.com"
    $spec.Uri.AbsolutePath |
      Should -Be "/api/v2/package/DisplayConfig/6.0.0"
    $spec.Sha256 | Should -Be (
      "816c17b0be5678197b0dc8c7ebd898f5f4cfdab1fe0ec768c7c25bd66a45f879"
    )
  }

  It "rejects a dependency package with a different SHA-256" {
    $packagePath = Join-Path $TestDrive "unexpected.nupkg"
    [IO.File]::WriteAllText($packagePath, "unexpected")

    {
      Assert-MonitorProfileFileHash `
        -Path $packagePath `
        -ExpectedSha256 ("0" * 64)
    } | Should -Throw "*SHA-256 mismatch*"
  }
}

Context "Supported profiles" {
  It "defines only the requested profile names and files" {
    $profiles = @(Get-MonitorProfileCatalog)

    $profiles.Name | Should -Be @("all", "left-center", "right-only")
    $profiles.FileName |
      Should -Be @("all.clixml", "left-center.clixml", "right-only.clixml")
  }

  It "rejects unknown and path-like profile names" {
    { Resolve-MonitorProfileFileName -Name "unknown" } |
      Should -Throw "*Unknown monitor profile*"
    { Resolve-MonitorProfileFileName -Name "..\all" } |
      Should -Throw "*Unknown monitor profile*"
    { Resolve-MonitorProfileFileName -Name "all.clixml" } |
      Should -Throw "*Unknown monitor profile*"
  }

  It "defines exact display and primary expectations" {
    $all = Get-MonitorProfileDefinition -Name all
    $leftCenter = Get-MonitorProfileDefinition -Name left-center
    $rightOnly = Get-MonitorProfileDefinition -Name right-only

    @($all.Displays | Where-Object Active).Role |
      Should -Be @("left", "center", "right")
    @($all.Displays | Where-Object Primary).Role | Should -Be @("center")
    ($all.Displays | Where-Object Role -EQ "left").X | Should -Be -1920
    ($all.Displays | Where-Object Role -EQ "left").Y | Should -Be 495
    ($all.Displays | Where-Object Role -EQ "center").X | Should -Be 0
    ($all.Displays | Where-Object Role -EQ "center").Y | Should -Be 0
    ($all.Displays | Where-Object Role -EQ "right").X | Should -Be 3840
    ($all.Displays | Where-Object Role -EQ "right").Y | Should -Be 430

    @($leftCenter.Displays | Where-Object Active).Role |
      Should -Be @("left", "center")
    @($leftCenter.Displays | Where-Object Primary).Role |
      Should -Be @("center")

    @($rightOnly.Displays | Where-Object Active).Role | Should -Be @("right")
    @($rightOnly.Displays | Where-Object Primary).Role | Should -Be @("right")
    ($rightOnly.Displays | Where-Object Role -EQ "right").X | Should -Be 0
    ($rightOnly.Displays | Where-Object Role -EQ "right").Y | Should -Be 0
  }

}

Context "Stable monitor identity" {
  BeforeAll {
    $configured = @(
      [pscustomobject]@{ Role = "left"; Serial = "LEFT-SERIAL"; DevicePath = "left-path" },
      [pscustomobject]@{ Role = "center"; Serial = "CENTER-SERIAL"; DevicePath = "center-path" },
      [pscustomobject]@{ Role = "right"; Serial = "RIGHT-SERIAL"; DevicePath = "right-path" }
    )
    $inventory = @(
      [pscustomobject]@{ DisplayId = 3; Serial = "RIGHT-SERIAL"; DevicePath = "new-right-path" },
      [pscustomobject]@{ DisplayId = 1; Serial = "LEFT-SERIAL"; DevicePath = "new-left-path" },
      [pscustomobject]@{ DisplayId = 2; Serial = "CENTER-SERIAL"; DevicePath = "new-center-path" }
    )
  }

  It "resolves roles by EDID serial instead of DISPLAY number" {
    $resolved = Resolve-MonitorRoleMap `
      -ConfiguredMonitors $configured `
      -Inventory $inventory

    $resolved.left.DisplayId | Should -Be 1
    $resolved.center.DisplayId | Should -Be 2
    $resolved.right.DisplayId | Should -Be 3
  }

  It "fails closed when a serial is ambiguous" {
    $ambiguous = @(
      $inventory
      [pscustomobject]@{ DisplayId = 4; Serial = "LEFT-SERIAL"; DevicePath = "duplicate" }
    )

    {
      Resolve-MonitorRoleMap `
        -ConfiguredMonitors $configured `
        -Inventory $ambiguous
    } | Should -Throw "*ambiguous*LEFT-SERIAL*"
  }

  It "fails closed when a configured monitor is missing" {
    {
      Resolve-MonitorRoleMap `
        -ConfiguredMonitors $configured `
        -Inventory @($inventory | Where-Object Serial -NE "RIGHT-SERIAL")
    } | Should -Throw "*not connected*RIGHT-SERIAL*"
  }
}

Context "Post-apply verification" {
  BeforeAll {
    $expected = @(
      [pscustomobject]@{ Role = "left"; Serial = "L"; Active = $true; Primary = $false; X = -1920; Y = 495; Width = 1920; Height = 1080 },
      [pscustomobject]@{ Role = "center"; Serial = "C"; Active = $true; Primary = $true; X = 0; Y = 0; Width = 3840; Height = 2160 },
      [pscustomobject]@{ Role = "right"; Serial = "R"; Active = $false; Primary = $false; X = 0; Y = 0; Width = 0; Height = 0 }
    )
  }

  It "accepts an exact semantic match regardless of DisplayId order" {
    $actual = @(
      [pscustomobject]@{ DisplayId = 8; Serial = "R"; Active = $false; Primary = $false; X = 0; Y = 0; Width = 0; Height = 0 },
      [pscustomobject]@{ DisplayId = 9; Serial = "C"; Active = $true; Primary = $true; X = 0; Y = 0; Width = 3840; Height = 2160 },
      [pscustomobject]@{ DisplayId = 7; Serial = "L"; Active = $true; Primary = $false; X = -1920; Y = 495; Width = 1920; Height = 1080 }
    )

    $result = Compare-MonitorProfileState -Expected $expected -Actual $actual

    $result.Succeeded | Should -BeTrue
    $result.Problems | Should -BeNullOrEmpty
  }

  It "rejects a left-right or primary mismatch" {
    $actual = @(
      [pscustomobject]@{ DisplayId = 1; Serial = "L"; Active = $true; Primary = $true; X = 0; Y = 0; Width = 1920; Height = 1080 },
      [pscustomobject]@{ DisplayId = 2; Serial = "C"; Active = $true; Primary = $false; X = -3840; Y = 0; Width = 3840; Height = 2160 },
      [pscustomobject]@{ DisplayId = 3; Serial = "R"; Active = $false; Primary = $false; X = 0; Y = 0; Width = 0; Height = 0 }
    )

    $result = Compare-MonitorProfileState -Expected $expected -Actual $actual

    $result.Succeeded | Should -BeFalse
    $result.Problems -join "|" | Should -Match "left.*primary"
    $result.Problems -join "|" | Should -Match "center.*position"
  }

  It "reads rollback JSON arrays without nesting them on PowerShell 5.1" {
    $path = Join-Path $TestDrive "rollback-state.json"
    $expected | ConvertTo-Json -Depth 5 |
      Set-Content -LiteralPath $path -Encoding UTF8

    $loaded = @(Read-MonitorProfileJsonArray -Path $path)

    $loaded.Count | Should -Be 3
    $loaded.Role | Should -Be @("left", "center", "right")
  }
}

Context "Managed scripts" {
  It "installs only the pinned DisplayConfig package" {
    $source = Get-Content -LiteralPath $installScriptPath -Raw

    $source | Should -Match 'Get-DisplayConfigReleaseSpec'
    $source | Should -Match 'Assert-MonitorProfileFileHash'
    $source | Should -Match 'Expand-Archive'
    $source | Should -Not -Match 'MultiMonitorTool'
  }

  It "keeps an identical loaded dependency during idempotent updates" {
    $source = Get-Content -LiteralPath $installScriptPath -Raw

    $source | Should -Match '\$dependencyMatches = \$hadDependency'
    $source | Should -Match 'Get-FileHash[\s\S]*\$installedPath'
    $source | Should -Match '\$dependencyReady = \$true'
  }

  It "exposes preflight and recovery without accepting arbitrary names" {
    $source = Get-Content -LiteralPath $switchScriptPath -Raw

    $source | Should -Match '\[ValidateSet\("all", "left-center", "right-only"\)\]'
    $source | Should -Match '\[switch\]\$ValidateOnly'
    $source | Should -Match '\[switch\]\$Recover'
    $source | Should -Match 'Invoke-MonitorProfile'
    $source | Should -Match 'Sync-GlazeMonitorLayout\.ps1'
    $source | Should -Match '-RestartZebar'
  }

  It "resolves the default install root after File parameter binding" {
    $source = Get-Content -LiteralPath $switchScriptPath -Raw

    $source | Should -Match '\[string\]\$InstallRoot = ""'
    $source | Should -Match (
      '(?s)IsNullOrWhiteSpace\(\$InstallRoot\).+?' +
      '\$InstallRoot = \$PSScriptRoot.+?' +
      'Resolve-MonitorProfileInstallRoot'
    )
  }

  It "installs fixed-name shortcut scripts without arbitrary profile input" {
    $installer = Get-Content -LiteralPath $installScriptPath -Raw
    foreach ($shortcut in @(
      @{ File = "Switch-MonitorProfile-All.ps1"; Name = "all" },
      @{ File = "Switch-MonitorProfile-LeftCenter.ps1"; Name = "left-center" },
      @{ File = "Switch-MonitorProfile-RightOnly.ps1"; Name = "right-only" }
    )) {
      $path = Join-Path $componentRoot $shortcut.File
      Test-Path -LiteralPath $path -PathType Leaf | Should -BeTrue
      if (Test-Path -LiteralPath $path -PathType Leaf) {
        $source = Get-Content -LiteralPath $path -Raw
        $source | Should -Match 'Switch-MonitorProfile\.ps1'
        $source | Should -Match (
          [regex]::Escape("-Name $($shortcut.Name)")
        )
        $source | Should -Not -Match '(?m)^\s*param\s*\('
      }
      $installer | Should -Match ([regex]::Escape($shortcut.File))
    }
  }

  It "validates, applies temporarily, verifies, and rolls back failures" {
    $source = Get-Content -LiteralPath $modulePath -Raw

    $source | Should -Match 'SDC_VALIDATE'
    $source | Should -Match 'Use-DisplayConfig[\s\S]*-DontSave'
    $source | Should -Match 'Compare-MonitorProfileState'
    $source | Should -Match 'Undo-DisplayConfigChanges'
    $source | Should -Match 'Invoke-MonitorProfileRollback'
  }

  It "moves primary before disabling displays and positions them last" {
    $source = Get-Content -LiteralPath $modulePath -Raw
    $primaryIndex = $source.IndexOf('$profile = Set-DisplayPrimary')
    $disableIndex = $source.IndexOf('$profile = Disable-Display')
    $positionIndex = $source.IndexOf('$profile = Set-DisplayPosition')

    $primaryIndex | Should -BeGreaterThan -1
    $disableIndex | Should -BeGreaterThan $primaryIndex
    $positionIndex | Should -BeGreaterThan $disableIndex
  }

}
}
