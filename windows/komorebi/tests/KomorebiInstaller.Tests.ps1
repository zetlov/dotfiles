Describe "Komorebi installer" {
BeforeAll {
  $modulePath = Join-Path $PSScriptRoot "..\KomorebiInstaller.psm1"
  Import-Module $modulePath -Force

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

Context "Resolve-KomorebiConfigHome" {
  It "accepts the managed directory under USERPROFILE" {
    $candidate = Join-Path $env:USERPROFILE ".config\komorebi"
    $resolved = Resolve-KomorebiConfigHome -Path $candidate

    Assert-Equal $resolved ([System.IO.Path]::GetFullPath($candidate))
  }

  It "rejects directories outside USERPROFILE" {
    Assert-Throws {
      Resolve-KomorebiConfigHome -Path (Join-Path $env:WINDIR "komorebi")
    }
  }

  It "rejects USERPROFILE prefix collisions" {
    Assert-Throws {
      Resolve-KomorebiConfigHome -Path ($env:USERPROFILE + "-other\komorebi")
    }
  }

  It "rejects another directory inside USERPROFILE" {
    Assert-Throws {
      Resolve-KomorebiConfigHome -Path (Join-Path $env:USERPROFILE "other")
    }
  }
}

Context "Get-KomorebiFileSha256" {
  It "rejects a missing file" {
    Assert-Throws {
      Get-KomorebiFileSha256 -Path (Join-Path $TestDrive "missing")
    }
  }
}

Context "Install-KomorebiManagedFile" {
  BeforeEach {
    $caseRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString("N"))
    $sourcePath = Join-Path $caseRoot "source\komorebi.json"
    $destinationPath = Join-Path $caseRoot "destination\komorebi.json"
    New-Item -ItemType Directory -Path (Split-Path $sourcePath) | Out-Null
    [System.IO.File]::WriteAllText($sourcePath, "new")
  }

  It "installs a new managed file" {
    $result = Install-KomorebiManagedFile `
      -SourcePath $sourcePath `
      -DestinationPath $destinationPath

    Assert-Equal (Get-Content -LiteralPath $destinationPath -Raw) "new"
    Assert-Equal $result.Changed $true
    Assert-Equal $result.BackupPath $null
  }

  It "updates a previously managed unmodified file" {
    New-Item -ItemType Directory -Path (Split-Path $destinationPath) | Out-Null
    [System.IO.File]::WriteAllText($destinationPath, "old")
    $previousSha256 = Get-KomorebiFileSha256 -Path $destinationPath

    $result = Install-KomorebiManagedFile `
      -SourcePath $sourcePath `
      -DestinationPath $destinationPath `
      -PreviousSha256 $previousSha256

    Assert-Equal (Get-Content -LiteralPath $destinationPath -Raw) "new"
    Assert-Equal $result.Changed $true
    Assert-Equal $result.BackupPath $null
  }

  It "does not overwrite a user-modified file" {
    New-Item -ItemType Directory -Path (Split-Path $destinationPath) | Out-Null
    [System.IO.File]::WriteAllText($destinationPath, "user edit")

    Assert-Throws {
      Install-KomorebiManagedFile `
        -SourcePath $sourcePath `
        -DestinationPath $destinationPath `
        -PreviousSha256 ("0" * 64)
    }

    Assert-Equal (Get-Content -LiteralPath $destinationPath -Raw) "user edit"
  }

  It "backs up a user-modified file when forced" {
    New-Item -ItemType Directory -Path (Split-Path $destinationPath) | Out-Null
    [System.IO.File]::WriteAllText($destinationPath, "user edit")

    $result = Install-KomorebiManagedFile `
      -SourcePath $sourcePath `
      -DestinationPath $destinationPath `
      -PreviousSha256 ("0" * 64) `
      -Force

    Assert-Equal (Get-Content -LiteralPath $destinationPath -Raw) "new"
    Assert-Equal (Get-Content -LiteralPath $result.BackupPath -Raw) "user edit"
  }

  It "is idempotent when source and destination match" {
    New-Item -ItemType Directory -Path (Split-Path $destinationPath) | Out-Null
    Copy-Item -LiteralPath $sourcePath -Destination $destinationPath

    $result = Install-KomorebiManagedFile `
      -SourcePath $sourcePath `
      -DestinationPath $destinationPath

    Assert-Equal $result.Changed $false
    Assert-Equal $result.BackupPath $null
  }

  It "rejects a directory at the destination path" {
    New-Item -ItemType Directory -Path $destinationPath | Out-Null

    Assert-Throws {
      Install-KomorebiManagedFile `
        -SourcePath $sourcePath `
        -DestinationPath $destinationPath
    }
  }

  It "rejects a missing source file" {
    Assert-Throws {
      Install-KomorebiManagedFile `
        -SourcePath (Join-Path $caseRoot "missing") `
        -DestinationPath $destinationPath
    }
  }
}

Context "Get-KomorebiManifest" {
  It "returns null for a missing manifest" {
    $manifest = Get-KomorebiManifest -Path (Join-Path $TestDrive "missing.json")

    Assert-Equal $manifest $null
  }

  It "parses a valid manifest" {
    $manifestPath = Join-Path $TestDrive "valid.json"
    [System.IO.File]::WriteAllText($manifestPath, '{"version":1}')

    $manifest = Get-KomorebiManifest -Path $manifestPath

    Assert-Equal $manifest.version 1
  }

  It "rejects an invalid manifest" {
    $manifestPath = Join-Path $TestDrive "invalid.json"
    [System.IO.File]::WriteAllText($manifestPath, "{")

    Assert-Throws {
      Get-KomorebiManifest -Path $manifestPath
    }
  }
}

Context "Get-KomorebiManifestFileSha256" {
  It "handles a legacy manifest without a files property" {
    $manifest = [pscustomobject]@{
      version = 0
    }

    $sha256 = Get-KomorebiManifestFileSha256 `
      -Manifest $manifest `
      -Name "komorebi.json"

    Assert-Equal $sha256 ""
  }

  It "returns the hash for a managed file" {
    $expected = "a" * 64
    $manifest = [pscustomobject]@{
      files = @(
        [pscustomobject]@{
          name = "komorebi.json"
          sha256 = $expected
        }
      )
    }

    $sha256 = Get-KomorebiManifestFileSha256 `
      -Manifest $manifest `
      -Name "komorebi.json"

    Assert-Equal $sha256 $expected
  }

  It "returns an empty string for an unmanaged file" {
    $manifest = [pscustomobject]@{
      files = @()
    }

    $sha256 = Get-KomorebiManifestFileSha256 `
      -Manifest $manifest `
      -Name "whkdrc"

    Assert-Equal $sha256 ""
  }
}

Context "Test-KomorebiManifestPackageOwned" {
  It "returns true for an installer-owned package" {
    $manifest = [pscustomobject]@{
      packages = [pscustomobject]@{
        komorebi = $true
        whkd = $false
        masir = $true
      }
    }

    Assert-Equal (
      Test-KomorebiManifestPackageOwned -Manifest $manifest -Name "masir"
    ) $true
  }

  It "treats a package missing from a legacy manifest as pre-existing" {
    $legacyManifest = [pscustomobject]@{
      packages = [pscustomobject]@{
        komorebi = $true
        whkd = $true
      }
    }

    Assert-Equal (
      Test-KomorebiManifestPackageOwned `
        -Manifest $legacyManifest `
        -Name "masir"
    ) $false
  }
}

Context "Resolve-KomorebiManagedPath" {
  It "reconstructs only known managed config paths" {
    $configHome = Join-Path $env:USERPROFILE ".config\komorebi"
    foreach ($name in @(
      "komorebi.json",
      "komorebi.bar.json",
      "whkdrc",
      "restart.ps1",
      "switch-audio.ps1",
      "audio-output.json"
    )) {
      $path = Resolve-KomorebiManagedPath `
        -ConfigHome $configHome `
        -Name $name

      Assert-Equal $path (Join-Path $configHome $name)
    }
  }

  It "rejects unknown managed config names" {
    Assert-Throws {
      Resolve-KomorebiManagedPath `
        -ConfigHome (Join-Path $env:USERPROFILE ".config\komorebi") `
        -Name "..\other.txt"
    }
  }
}

Context "Get-KomorebiManagedFileSpecification" {
  It "deploys a selected local audio configuration under the managed name" {
    $sourceRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $sourceRoot | Out-Null
    $defaultAudioPath = Join-Path $sourceRoot "audio-output.json"
    $localAudioPath = Join-Path $sourceRoot "audio-output.local.json"
    [System.IO.File]::WriteAllText($defaultAudioPath, '{"outputs":["default"]}')
    [System.IO.File]::WriteAllText($localAudioPath, '{"outputs":["local"]}')
    $previousAudioSha256 = "a" * 64
    $manifest = [pscustomobject]@{
      files = @(
        [pscustomobject]@{
          name = "audio-output.json"
          sha256 = $previousAudioSha256
        }
      )
    }

    $files = @(Get-KomorebiManagedFileSpecification `
      -SourceRoot $sourceRoot `
      -ConfigHome (Join-Path $env:USERPROFILE ".config\komorebi") `
      -Manifest $manifest)
    $audioFile = @($files | Where-Object { $_.Name -eq "audio-output.json" }) |
      Select-Object -First 1
    $deployedAudioPath = Join-Path $sourceRoot "deployed\audio-output.json"

    Install-KomorebiManagedFilesTransaction -Files @(
      @{
        SourcePath = $audioFile.SourcePath
        DestinationPath = $deployedAudioPath
        PreviousSha256 = ""
      }
    ) | Out-Null

    Assert-Equal $audioFile.SourcePath $localAudioPath
    Assert-Equal $audioFile.PreviousSha256 $previousAudioSha256
    Assert-Equal $audioFile.DestinationPath (
      Join-Path $env:USERPROFILE ".config\komorebi\audio-output.json"
    )
    Assert-Equal (
      Get-Content -LiteralPath $deployedAudioPath -Raw
    ) '{"outputs":["local"]}'
  }

  It "falls back to the checked-in audio configuration" {
    $sourceRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $sourceRoot | Out-Null
    $defaultAudioPath = Join-Path $sourceRoot "audio-output.json"
    [System.IO.File]::WriteAllText($defaultAudioPath, '{"outputs":["default"]}')

    $audioFile = @(Get-KomorebiManagedFileSpecification `
      -SourceRoot $sourceRoot `
      -ConfigHome (Join-Path $env:USERPROFILE ".config\komorebi") |
      Where-Object { $_.Name -eq "audio-output.json" }) |
      Select-Object -First 1

    Assert-Equal $audioFile.SourcePath $defaultAudioPath
  }
}

Context "Install-KomorebiManagedFilesTransaction" {
  BeforeEach {
    $caseRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $caseRoot | Out-Null
    $sourceOne = Join-Path $caseRoot "source-one"
    $sourceTwo = Join-Path $caseRoot "source-two"
    $destinationOne = Join-Path $caseRoot "destination-one"
    $destinationTwo = Join-Path $caseRoot "destination-two"
    [System.IO.File]::WriteAllText($sourceOne, "new one")
    [System.IO.File]::WriteAllText($sourceTwo, "new two")
    [System.IO.File]::WriteAllText($destinationOne, "old one")
    [System.IO.File]::WriteAllText($destinationTwo, "old two")
  }

  It "rolls back all files when a later deployment fails" {
    Remove-Item -LiteralPath $destinationTwo
    New-Item -ItemType Directory -Path $destinationTwo | Out-Null
    $files = @(
      @{
        SourcePath = $sourceOne
        DestinationPath = $destinationOne
        PreviousSha256 = Get-KomorebiFileSha256 -Path $destinationOne
      },
      @{
        SourcePath = $sourceTwo
        DestinationPath = $destinationTwo
        PreviousSha256 = ""
      }
    )

    Assert-Throws {
      Install-KomorebiManagedFilesTransaction -Files $files
    }

    Assert-Equal (Get-Content -LiteralPath $destinationOne -Raw) "old one"
    Assert-Equal (Test-Path -LiteralPath $destinationTwo -PathType Container) $true
  }

  It "rolls back files when post-deployment validation fails" {
    $files = @(
      @{
        SourcePath = $sourceOne
        DestinationPath = $destinationOne
        PreviousSha256 = Get-KomorebiFileSha256 -Path $destinationOne
      },
      @{
        SourcePath = $sourceTwo
        DestinationPath = $destinationTwo
        PreviousSha256 = Get-KomorebiFileSha256 -Path $destinationTwo
      }
    )

    Assert-Throws {
      Install-KomorebiManagedFilesTransaction `
        -Files $files `
        -AfterInstall { throw "injected failure" }
    }

    Assert-Equal (Get-Content -LiteralPath $destinationOne -Raw) "old one"
    Assert-Equal (Get-Content -LiteralPath $destinationTwo -Raw) "old two"
  }
}

Context "Wait-KomorebiProcessSet" {
  It "accepts processes which are already running" {
    $currentName = (Get-Process -Id $PID).ProcessName

    Wait-KomorebiProcessSet `
      -Names @($currentName) `
      -TimeoutSeconds 0 `
      -StableMilliseconds 0
  }

  It "rejects a missing process" {
    Assert-Throws {
      Wait-KomorebiProcessSet `
        -Names @("dotfiles-process-that-does-not-exist") `
        -TimeoutSeconds 0 `
        -StableMilliseconds 0
    }
  }

  It "rejects a process which exits before the stability window" {
    $executablePath = Join-Path $TestDrive "dotfiles-transient.exe"
    Copy-Item -LiteralPath $env:ComSpec -Destination $executablePath
    $process = Start-Process `
      -FilePath $executablePath `
      -ArgumentList @("/c", "ping -n 2 127.0.0.1 > nul") `
      -WindowStyle Hidden `
      -PassThru

    try {
      Assert-Throws {
        Wait-KomorebiProcessSet `
          -Names @($process.ProcessName) `
          -TimeoutSeconds 2 `
          -StableMilliseconds 1500
      }
    } finally {
      if (-not $process.HasExited) {
        $process.Kill()
      }
    }
  }
}

Context "Get-KomorebiBarArgumentString" {
  It "quotes a config path containing spaces" {
    $configPath = "C:\Users\John Doe\.config\komorebi\komorebi.bar.json"

    $arguments = Get-KomorebiBarArgumentString -ConfigPath $configPath

    Assert-Equal $arguments ('-c "{0}"' -f $configPath)
  }

  It "rejects a config path containing a quote" {
    Assert-Throws {
      Get-KomorebiBarArgumentString `
        -ConfigPath 'C:\Users\invalid"name\komorebi.bar.json'
    }
  }
}

Context "Test-KomorebiShortcutSpec" {
  BeforeEach {
    $shortcutPath = Join-Path $TestDrive "komorebi.lnk"
    $targetPath = Join-Path $TestDrive "komorebic-no-console.exe"
    [System.IO.File]::WriteAllText($targetPath, "")
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $targetPath
    $shortcut.Arguments = "start --whkd"
    $shortcut.Save()
  }

  It "accepts an expected target and argument set" {
    $valid = Test-KomorebiShortcutSpec `
      -ShortcutPath $shortcutPath `
      -ExpectedTarget $targetPath `
      -AllowedArguments @("start --whkd")

    Assert-Equal $valid $true
  }

  It "rejects unexpected arguments" {
    $valid = Test-KomorebiShortcutSpec `
      -ShortcutPath $shortcutPath `
      -ExpectedTarget $targetPath `
      -AllowedArguments @("start --bar")

    Assert-Equal $valid $false
  }
}

Context "Installer entrypoint safety contracts" {
  BeforeAll {
    $installScript = Get-Content `
      -LiteralPath (Join-Path $PSScriptRoot "..\install.ps1") `
      -Raw
    $updateScript = Get-Content `
      -LiteralPath (Join-Path $PSScriptRoot "..\update-config.ps1") `
      -Raw
    $uninstallScript = Get-Content `
      -LiteralPath (Join-Path $PSScriptRoot "..\uninstall.ps1") `
      -Raw
    $installerModule = Get-Content `
      -LiteralPath (Join-Path $PSScriptRoot "..\KomorebiInstaller.psm1") `
      -Raw
  }

  It "preserves an existing applications database" {
    Assert-Equal $installScript.Contains(
      "if (-not (Test-Path -LiteralPath `$applicationsPath -PathType Leaf))"
    ) $true
  }

  It "uses transactions for install and update" {
    Assert-Equal $installScript.Contains(
      "Install-KomorebiManagedFilesTransaction"
    ) $true
    Assert-Equal $updateScript.Contains(
      "Install-KomorebiManagedFilesTransaction"
    ) $true
  }

  It "centralizes shared deployment operations" {
    foreach ($script in @($installScript, $updateScript, $uninstallScript)) {
      Assert-Equal $script.Contains("function Write-KomorebiManifest") $false
    }
    foreach ($script in @($installScript, $updateScript)) {
      Assert-Equal $script.Contains("function Invoke-Komorebic") $false
      Assert-Equal $script.Contains(
        "Get-KomorebiManagedFileSpecification"
      ) $true
    }
    Assert-Equal $installerModule.Contains("function Invoke-Komorebic") $true
    Assert-Equal $installerModule.Contains("function Write-KomorebiManifest") $true
  }

  It "verifies processes and autostart after commands return" {
    Assert-Equal $installScript.Contains("Wait-KomorebiProcessSet") $true
    Assert-Equal $installScript.Contains("Assert-KomorebiAutostart") $true
    Assert-Equal $installScript.Contains(
      '-AllowedArguments @("start --bar --whkd")'
    ) $true
    Assert-Equal $installScript.Contains(
      '@("enable-autostart", "--whkd", "--bar")'
    ) $true
  }

  It "deploys the managed bar configuration" {
    Assert-Equal $installerModule.Contains(
      'Name = "komorebi.bar.json"'
    ) $true
    Assert-Equal $updateScript.Contains(
      '"komorebi.bar.json"'
    ) $true
    Assert-Equal $updateScript.Contains(
      "Cannot parse the Komorebi bar configuration"
    ) $true
  }

  It "deploys and uses the guarded session restart" {
    Assert-Equal $installerModule.Contains('Name = "restart.ps1"') $true
    Assert-Equal $updateScript.Contains('Name "restart.ps1"') $true
    Assert-Equal $updateScript.Contains(
      '& $restartSourcePath -ConfigHome $configHome'
    ) $true
    foreach ($script in @($installScript, $updateScript)) {
      Assert-Equal $script.Contains('& $restartPath') $true
      Assert-Equal $script.Contains(
        '& $restartSourcePath -ConfigHome $configHome'
      ) $true
      Assert-Equal $script.Contains(
        '@("replace-configuration", $configPath)'
      ) $false
    }
  }

  It "deploys the managed audio switch configuration" {
    foreach ($name in @("switch-audio.ps1", "audio-output.json")) {
      Assert-Equal $installerModule.Contains("Name = `"$name`"") $true
    }
    Assert-Equal $installScript.Contains(
      'Install-AudioDeviceModule -RequiredVersion "3.1.0.2"'
    ) $true
    Assert-Equal $updateScript.Contains(
      'Install-AudioDeviceModule -RequiredVersion "3.1.0.2"'
    ) $true
    foreach ($script in @($installScript, $updateScript)) {
      Assert-Equal $script.Contains("Get-AudioOutputPatterns") $true
    }
    Assert-Equal $installerModule.Contains(
      'Install-PackageProvider -Name "NuGet" -Scope "CurrentUser" -Force'
    ) $false
  }

  It "imports the shared audio dependency installer" {
    foreach ($script in @($installScript, $updateScript)) {
      Assert-Equal $script.Contains(
        'AudioOutputInstaller.psm1'
      ) $true
      Assert-Equal $script.Contains(
        'Import-Module $audioInstallerModule -Force -ErrorAction Stop'
      ) $true
    }
  }

  It "leaves audio dependency installation out of the Komorebi module" {
    Assert-Equal $installerModule.Contains(
      "function Install-AudioDeviceModule"
    ) $false
    Assert-Equal $installerModule.Contains(
      '  Install-AudioDeviceModule, `'
    ) $false
  }

  It "installs and owns the official masir package" {
    Assert-Equal $installScript.Contains(
      '-PackageId "LGUG2Z.masir"'
    ) $true
    Assert-Equal $installScript.Contains(
      'masir = [bool]($oldMasirOwned -or $masirInstalledNow)'
    ) $true
    Assert-Equal $uninstallScript.Contains(
      'Id = "LGUG2Z.masir"'
    ) $true
  }

  It "keeps focus-follows-mouse disabled when starting Komorebi" {
    foreach ($script in @($installScript, $updateScript)) {
      Assert-Equal $script.Contains(
        '@("start", "-c", $configPath, "--whkd", "--bar")'
      ) $true
      Assert-Equal $script.Contains(
        'Wait-KomorebiProcessSet -Names @("komorebi", "whkd", "komorebi-bar") -StableMilliseconds 1000'
      ) $true
      Assert-Equal $script.Contains(
        'Get-Process -Name "masir" -ErrorAction SilentlyContinue |'
      ) $true
      Assert-Equal $script.Contains(
        'Wait-Process -Timeout 5 -ErrorAction SilentlyContinue'
      ) $true
      Assert-Equal $script.Contains(
        '-ArgumentList (Get-KomorebiBarArgumentString -ConfigPath $barConfigPath)'
      ) $true
    }
  }

  It "migrates installer-owned autostart away from masir during updates" {
    Assert-Equal $updateScript.Contains(
      '$manifest.PSObject.Properties["autostart_owned"]'
    ) $true
    Assert-Equal $updateScript.Contains(
      'Test-KomorebiShortcutSpec'
    ) $true
    Assert-Equal $updateScript.Contains(
      '@("enable-autostart", "--whkd", "--bar")'
    ) $true
    Assert-Equal $updateScript.Contains(
      'Copy-Item -LiteralPath $autostartSnapshot -Destination $startupShortcutPath -Force'
    ) $true
  }

  It "reconstructs delete targets and stops helpers independently" {
    Assert-Equal $uninstallScript.Contains("Resolve-KomorebiManagedPath") $true
    Assert-Equal $uninstallScript.Contains(
      'foreach ($processName in @("whkd", "komorebi-bar", "masir"))'
    ) $true
    Assert-Equal $uninstallScript.Contains(
      "Get-Process -Name `$processName"
    ) $true
    Assert-Equal $uninstallScript.Contains("stop --whkd --bar --masir") $true
  }
}

Context "Hyprland-compatible static configuration" {
  BeforeAll {
    $configPath = Join-Path $PSScriptRoot "..\komorebi.json"
    $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
  }

  It "pins the schema and Hyprland gap and border values" {
    Assert-Equal $config.'$schema' "https://raw.githubusercontent.com/LGUG2Z/komorebi/v0.1.41/schema.json"
    Assert-Equal $config.default_container_padding 8
    Assert-Equal $config.default_workspace_padding 10
    Assert-Equal $config.border_width 3
    Assert-Equal $config.border $true
  }

  It "does not warp the pointer when keyboard focus changes" {
    Assert-Equal $config.mouse_follows_focus $false
    Assert-Equal $config.transparency $false
    Assert-Equal $config.transparency_alpha 255
  }

  It "animates window movement with the Hyprland easing curve" {
    Assert-Equal $config.animation.enabled.movement $true
    Assert-Equal $config.animation.style.movement "EaseOutQuint"
    Assert-Equal $config.animation.fps 60
    Assert-Equal $config.animation.duration.movement 160
  }

  It "defines twelve BSP workspaces on the main monitor" {
    $main = $config.monitors[0]
    Assert-Equal @($main.workspaces).Count 12

    for ($index = 0; $index -lt 12; $index++) {
      Assert-Equal $main.workspaces[$index].name ([string]($index + 1))
      Assert-Equal $main.workspaces[$index].layout "BSP"
    }
  }

  It "keeps workspaces 11 and 12 untiled for games" {
    $main = $config.monitors[0]
    foreach ($index in 0..9) {
      Assert-Equal (
        $null -eq $main.workspaces[$index].PSObject.Properties["tile"]
      ) $true
      Assert-Equal (
        $null -eq $main.workspaces[$index].PSObject.Properties[
          "floating_layer_behaviour"
        ]
      ) $true
    }

    foreach ($index in 10..11) {
      Assert-Equal $main.workspaces[$index].tile $false
      Assert-Equal (
        $main.workspaces[$index].floating_layer_behaviour
      ) "Float"
    }
  }

  It "does not configure transparency exceptions when transparency is disabled" {
    Assert-Equal (
      $null -eq $config.PSObject.Properties["transparency_ignore_rules"]
    ) $true
  }

  It "defines a single vertical workspace on the secondary monitor" {
    $secondary = $config.monitors[1]
    Assert-Equal @($secondary.workspaces).Count 1
    Assert-Equal $secondary.workspaces[0].name "vert"
    Assert-Equal $secondary.workspaces[0].layout "Columns"
  }

  It "lets Komorebi discover the host display order" {
    Assert-Equal (
      $null -eq $config.PSObject.Properties["display_index_preferences"]
    ) $true
  }

  It "routes known Windows applications to their initial workspaces" {
    $main = $config.monitors[0]
    $workspace1Rules = @($main.workspaces[0].initial_workspace_rules)
    $workspace2Rules = @($main.workspaces[1].initial_workspace_rules)
    $workspace3Rules = @($main.workspaces[2].initial_workspace_rules)
    $workspace4Rules = @($main.workspaces[3].initial_workspace_rules)
    $workspace6Rules = @($main.workspaces[5].initial_workspace_rules)

    Assert-Equal ($workspace1Rules.id -contains "zen.exe") $true
    Assert-Equal ($workspace2Rules.id -contains "Tana.exe") $true
    Assert-Equal ($workspace2Rules.id -contains "zotero.exe") $true
    Assert-Equal ($workspace2Rules.id -contains "Raindrop.io.exe") $true
    Assert-Equal ($workspace2Rules.id -contains "Todoist.exe") $true
    Assert-Equal ($workspace2Rules.id -contains "Notion Calendar.exe") $true
    Assert-Equal ($workspace3Rules.id -contains "Spotify.exe") $true
    Assert-Equal ($workspace3Rules.id -contains "Discord.exe") $true
    Assert-Equal ($workspace4Rules.id -contains "Obsidian.exe") $true
    Assert-Equal ($workspace6Rules.id -contains "Discord.exe") $false
    Assert-Equal ($workspace6Rules.id -contains "slack.exe") $true
  }

  It "creates new containers relative to the focused container" {
    Assert-Equal $config.window_container_behaviour "Create"
  }
}

Context "Hyprland-inspired bar configuration" {
  BeforeAll {
    $barPath = Join-Path $PSScriptRoot "..\komorebi.bar.json"
    $bar = Get-Content -LiteralPath $barPath -Raw | ConvertFrom-Json
  }

  It "targets the main monitor with the matching size and theme" {
    Assert-Equal $bar.'$schema' "https://raw.githubusercontent.com/LGUG2Z/komorebi/v0.1.41/schema.bar.json"
    Assert-Equal $bar.monitor 0
    Assert-Equal $bar.height 42
    Assert-Equal $bar.font_family "JetBrainsMono NF Regular"
    Assert-Equal $bar.theme.palette "Catppuccin"
    Assert-Equal $bar.theme.name "Mocha"
    Assert-Equal $bar.theme.accent "Blue"
  }

  It "shows workspaces, layout, focused window, and system status" {
    $komorebi = $bar.left_widgets[0].Komorebi
    Assert-Equal $komorebi.workspaces.enable $true
    Assert-Equal $komorebi.workspaces.hide_empty_workspaces $false
    Assert-Equal $komorebi.layout.enable $true
    Assert-Equal $komorebi.focused_container.enable $true

    $centerNames = @(
      $bar.center_widgets |
        ForEach-Object { $_.PSObject.Properties.Name }
    )
    Assert-Equal ($centerNames -join "|") "Date|Time"

    $rightNames = @(
      $bar.right_widgets |
        ForEach-Object { $_.PSObject.Properties.Name }
    )
    Assert-Equal (
      $rightNames -join "|"
    ) "Media|Cpu|Memory|Network|Keyboard|Systray"
  }

  It "shows the weekday in the date and seconds in the time" {
    Assert-Equal $bar.center_widgets[0].Date.format.Custom "%Y-%m-%d (%a)"
    Assert-Equal $bar.center_widgets[1].Time.format "TwentyFourHour"
  }
}

Context "Hyprland-compatible hotkeys" {
  BeforeAll {
    $whkdrcPath = Join-Path $PSScriptRoot "..\whkdrc"
    $whkdrc = Get-Content -LiteralPath $whkdrcPath -Raw
  }

  It "defines Vim focus and move bindings" {
    foreach ($binding in @(
      "ctrl + alt + h : & `"`$Env:ProgramFiles\komorebi\bin\komorebic.exe`" focus left",
      "ctrl + alt + j : & `"`$Env:ProgramFiles\komorebi\bin\komorebic.exe`" focus down",
      "ctrl + alt + k : & `"`$Env:ProgramFiles\komorebi\bin\komorebic.exe`" focus up",
      "ctrl + alt + l : & `"`$Env:ProgramFiles\komorebi\bin\komorebic.exe`" focus right",
      "ctrl + alt + shift + h : & `"`$Env:ProgramFiles\komorebi\bin\komorebic.exe`" move left",
      "ctrl + alt + shift + j : & `"`$Env:ProgramFiles\komorebi\bin\komorebic.exe`" move down",
      "ctrl + alt + shift + k : & `"`$Env:ProgramFiles\komorebi\bin\komorebic.exe`" move up",
      "ctrl + alt + shift + l : & `"`$Env:ProgramFiles\komorebi\bin\komorebic.exe`" move right"
    )) {
      Assert-Equal $whkdrc.Contains($binding) $true
    }
  }

  It "uses named workspace commands for all main workspaces" {
    foreach ($workspace in 1..12) {
      Assert-Equal $whkdrc.Contains("focus-named-workspace $workspace") $true
      Assert-Equal $whkdrc.Contains("move-to-named-workspace $workspace") $true
    }
  }

  It "does not toggle transparency while changing workspaces" {
    Assert-Equal $whkdrc.Contains("transparency") $false
  }

  It "focuses and moves windows between monitors explicitly" {
    foreach ($binding in @(
      "ctrl + alt + oem_comma : & `"`$Env:ProgramFiles\komorebi\bin\komorebic.exe`" cycle-monitor previous",
      "ctrl + alt + oem_period : & `"`$Env:ProgramFiles\komorebi\bin\komorebic.exe`" cycle-monitor next",
      "ctrl + alt + shift + oem_comma : & `"`$Env:ProgramFiles\komorebi\bin\komorebic.exe`" cycle-move-to-monitor previous",
      "ctrl + alt + shift + oem_period : & `"`$Env:ProgramFiles\komorebi\bin\komorebic.exe`" cycle-move-to-monitor next"
    )) {
      Assert-Equal $whkdrc.Contains($binding) $true
    }
  }

  It "does not define duplicate hotkeys" {
    $hotkeys = @(
      Get-Content -LiteralPath $whkdrcPath |
        Where-Object { $_ -match "^\s*[^.#].*:" } |
        ForEach-Object { ($_ -split ":", 2)[0].Trim().ToLowerInvariant() }
    )
    $duplicates = @($hotkeys | Group-Object | Where-Object { $_.Count -gt 1 })

    Assert-Equal $duplicates.Count 0
  }

  It "uses the guarded restart for configuration changes" {
    Assert-Equal $whkdrc.Contains("replace-configuration") $false
    Assert-Equal $whkdrc.Contains(
      '-File "$Env:KOMOREBI_CONFIG_HOME\restart.ps1"'
    ) $true
  }

  It "preselects the next split direction with shifted arrow keys" {
    foreach ($binding in @(
      "ctrl + alt + shift + left : & `"`$Env:ProgramFiles\komorebi\bin\komorebic.exe`" preselect-direction left",
      "ctrl + alt + shift + down : & `"`$Env:ProgramFiles\komorebi\bin\komorebic.exe`" preselect-direction down",
      "ctrl + alt + shift + up : & `"`$Env:ProgramFiles\komorebi\bin\komorebic.exe`" preselect-direction up",
      "ctrl + alt + shift + right : & `"`$Env:ProgramFiles\komorebi\bin\komorebic.exe`" preselect-direction right"
    )) {
      Assert-Equal $whkdrc.Contains($binding) $true
    }
  }

  It "cycles audio outputs with the Super M transport chord" {
    Assert-Equal $whkdrc.Contains(
      'ctrl + alt + m : & "$Env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "$Env:KOMOREBI_CONFIG_HOME\switch-audio.ps1"'
    ) $true
  }
}

Context "Safe Komorebi restart" {
  BeforeAll {
    $restartPath = Join-Path $PSScriptRoot "..\restart.ps1"
    $restartSource = Get-Content -LiteralPath $restartPath -Raw
  }

  It "checks rollback safety before defining or invoking Komorebi operations" {
    $guardCallIndex = $restartSource.IndexOf(
      "`nAssert-KomorebiRollbackRestartSafe`n"
    )
    $invokeFunctionIndex = $restartSource.IndexOf("function Invoke-Komorebic")
    $firstMutationIndex = $restartSource.IndexOf('$komorebicPath =')

    $guardCallIndex | Should -BeGreaterThan -1
    $invokeFunctionIndex | Should -BeGreaterThan $guardCallIndex
    $firstMutationIndex | Should -BeGreaterThan $guardCallIndex
  }

  It "blocks restart while GlazeWM is running" {
    Mock Get-Process {
      [pscustomobject]@{ Id = 1234; ProcessName = "glazewm" }
    }
    Mock Get-ItemProperty { [pscustomobject]@{} }
    Mock Test-Path { $false }

    {
      & $restartPath -ConfigHome (Join-Path $TestDrive "komorebi")
    } | Should -Throw "*GlazeWM*running*"
    Should -Invoke Get-ItemProperty -Times 0
    Should -Invoke Test-Path -Times 0
  }

  It "blocks restart while GlazeWM automatic startup is enabled" {
    Mock Get-Process { @() }
    Mock Get-ItemProperty {
      [pscustomobject]@{ GlazeWM = '"C:\Program Files\GlazeWM.exe"' }
    }
    Mock Test-Path { $false }

    {
      & $restartPath -ConfigHome (Join-Path $TestDrive "komorebi")
    } | Should -Throw "*automatic startup*"
    Should -Invoke Test-Path -Times 0
  }

  It "treats a missing Windows Run key as safe" {
    Mock Get-Process { @() }
    Mock Get-ItemProperty {
      throw [System.Management.Automation.ItemNotFoundException]::new(
        "Run key missing"
      )
    }
    Mock Test-Path { $false }

    {
      & $restartPath -ConfigHome (Join-Path $TestDrive "komorebi")
    } | Should -Throw "*official Komorebi executable is missing*"
  }

  It "fails closed when GlazeWM process inspection fails" {
    Mock Get-Process {
      throw [System.UnauthorizedAccessException]::new("denied")
    }
    Mock Test-Path { $false }

    {
      & $restartPath -ConfigHome (Join-Path $TestDrive "komorebi")
    } | Should -Throw "*Unable to inspect GlazeWM processes*denied*"
    Should -Invoke Test-Path -Times 0
  }

  It "fails closed when GlazeWM Run registration inspection fails" {
    Mock Get-Process { @() }
    Mock Get-ItemProperty {
      throw [System.UnauthorizedAccessException]::new("denied")
    }
    Mock Test-Path { $false }

    {
      & $restartPath -ConfigHome (Join-Path $TestDrive "komorebi")
    } | Should -Throw "*Unable to inspect Windows Run registrations*denied*"
    Should -Invoke Test-Path -Times 0
  }

  It "captures and validates current state before stopping" {
    Assert-Equal $restartSource.Contains('Invoke-KomorebicJson -Path $komorebicPath -Arguments @("state")') $true
    Assert-Equal $restartSource.Contains("Save-KomorebiStateSnapshot") $true
  }

  It "waits for a graceful stop and starts without clean state" {
    Assert-Equal $restartSource.Contains('Arguments @("stop", "--whkd", "--bar", "--masir")') $true
    Assert-Equal $restartSource.Contains("Wait-KomorebiProcessExit") $true
    Assert-Equal $restartSource.Contains('Arguments @("start", "-c", $configPath, "--whkd", "--bar")') $true
    Assert-Equal $restartSource.Contains("--clean-state") $false
  }

  It "verifies saved window workspace placements after restart" {
    Assert-Equal $restartSource.Contains("Get-KomorebiWindowPlacement") $true
    Assert-Equal $restartSource.Contains("Test-KomorebiWindowPlacementRestored") $true
  }
}

Context "Windows audio output switching" {
  BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot "..\switch-audio.ps1"
    $scriptSource = Get-Content -LiteralPath $scriptPath -Raw
    . $scriptPath -NoRun
  }

  It "imports the pinned module through its exact CurrentUser manifest path" {
    $scriptSource | Should -Match '"WindowsPowerShell"'
    $scriptSource | Should -Match '"Modules"'
    $scriptSource | Should -Match '"AudioDeviceCmdlets"'
    $scriptSource | Should -Match '"3\.1\.0\.2"'
    $scriptSource | Should -Match (
      '(?s)Import-Module\s+.*?-Name \$manifestPath'
    )
    $scriptSource | Should -Not -Match (
      'Import-Module\s+["'']AudioDeviceCmdlets["'']'
    )
    $scriptSource | Should -Match 'Get-FileHash'
    foreach ($hashPart in @(
      "0D657B8DDE3DC9B090716162ED351B68F",
      "785F50483B92E937528D082469DBFB5",
      "2E81666DD09BC835C669DAF9771686FD",
      "AD5651FBEBB600A234F11AF80CA5D25F"
    )) {
      $scriptSource | Should -Match $hashPart
    }
    $scriptSource | Should -Match (
      '\$module\.ExportedCommands\["Get-AudioDevice"\]'
    )
    $scriptSource | Should -Match '& \$GetCommand -List'
  }

  It "resolves configured playback devices without depending on display prefixes" {
    $devices = @(
      [pscustomobject]@{ Type = "Playback"; Name = "Headphones (USB headset)"; ID = "a"; Default = $true },
      [pscustomobject]@{ Type = "Playback"; Name = "Speakers (Desktop speakers)"; ID = "b"; Default = $false },
      [pscustomobject]@{ Type = "Recording"; Name = "Microphone (USB headset)"; ID = "c"; Default = $false }
    )

    $resolved = @(Resolve-AudioOutputDevices `
      -Devices $devices `
      -Patterns @("USB headset", "Desktop speakers"))

    Assert-Equal ($resolved.ID -join "|") "a|b"
  }

  It "validates the checked-in audio output configuration" {
    $configPath = Join-Path $PSScriptRoot "..\audio-output.json"
    $patterns = @(Get-AudioOutputPatterns -Path $configPath)

    Assert-Equal ($patterns -join "|") (
      "USB headset|Desktop speakers"
    )
  }

  It "rejects invalid audio output configuration" {
    $invalidPath = Join-Path $TestDrive "audio-output.json"
    [System.IO.File]::WriteAllText(
      $invalidPath,
      '{"playback_device_patterns":["USB headset","usb headset"]}'
    )

    Assert-Throws { Get-AudioOutputPatterns -Path $invalidPath }
  }

  It "selects the next configured device after the current default" {
    $devices = @(
      [pscustomobject]@{ ID = "a"; Default = $true },
      [pscustomobject]@{ ID = "b"; Default = $false }
    )

    Assert-Equal (Select-NextAudioOutputDevice -Devices $devices).ID "b"
    $devices[0].Default = $false
    $devices[1].Default = $true
    Assert-Equal (Select-NextAudioOutputDevice -Devices $devices).ID "a"
  }

  It "notifies with the selected audio output name" {
    $script:notification = $null
    Show-AudioOutputNotification `
      -DeviceName "Headphones (USB headset)" `
      -Notifier {
        param($title, $message)
        $script:notification = "$title|$message"
      }

    Assert-Equal $script:notification (
      "Audio output|Headphones (USB headset)"
    )
  }

  It "rejects missing and ambiguous device patterns" {
    $devices = @(
      [pscustomobject]@{ Type = "Playback"; Name = "USB headset Game"; ID = "a" },
      [pscustomobject]@{ Type = "Playback"; Name = "USB headset Chat"; ID = "b" }
    )

    Assert-Throws {
      Resolve-AudioOutputDevices -Devices $devices -Patterns @("USB headset")
    }
    Assert-Throws {
      Resolve-AudioOutputDevices -Devices $devices -Patterns @("Desktop speakers")
    }
  }

  It "invokes audio commands and notification through injected scriptblocks" {
    $script:getAudioInvocation = $null
    $script:setAudioInvocation = $null
    $script:audioNotification = $null
    $devices = @(
      [pscustomobject]@{
        Type = "Playback"
        Name = "Headphones (USB headset)"
        ID = "a"
        Default = $true
      },
      [pscustomobject]@{
        Type = "Playback"
        Name = "Speakers (Desktop speakers)"
        ID = "b"
        Default = $false
      }
    )

    Invoke-AudioOutputChange `
      -Patterns @("USB headset", "Desktop speakers") `
      -GetCommand {
        $script:getAudioInvocation = $args -join "|"
        return $devices
      } `
      -SetCommand {
        $script:setAudioInvocation = $args -join "|"
      } `
      -Notifier {
        param($title, $message)
        $script:audioNotification = "$title|$message"
      }

    Assert-Equal $script:getAudioInvocation "-List"
    Assert-Equal $script:setAudioInvocation "-ID|b"
    Assert-Equal $script:audioNotification (
      "Audio output|Speakers (Desktop speakers)"
    )
  }

  Context "validated runtime module loading" {
    BeforeEach {
      $runtimeDocumentsPath = Join-Path `
        $TestDrive `
        ([guid]::NewGuid().ToString("N"))
      $runtimeModuleRoot = Join-Path $runtimeDocumentsPath (
        "WindowsPowerShell\Modules\AudioDeviceCmdlets\3.1.0.2"
      )
      $runtimeManifestPath = Join-Path `
        $runtimeModuleRoot `
        "AudioDeviceCmdlets.psd1"
      $runtimeManifestHash = (
        "0D657B8DDE3DC9B090716162ED351B68F" +
        "785F50483B92E937528D082469DBFB5"
      )
      $runtimeDllHash = (
        "2E81666DD09BC835C669DAF9771686FD" +
        "AD5651FBEBB600A234F11AF80CA5D25F"
      )
      $global:AudioRuntimeTestModule = [pscustomobject]@{
        ModuleBase = $runtimeModuleRoot
        Version = [version]"3.1.0.2"
        ExportedCommands = @{
          "Get-AudioDevice" = { param([switch]$List) }
          "Set-AudioDevice" = { param([string]$ID) }
        }
      }

      Mock Test-Path { $true }
      Mock Get-Item {
        [pscustomobject]@{
          Attributes = [System.IO.FileAttributes]::Normal
        }
      }
      Mock Get-FileHash {
        if ($LiteralPath -like "*.psd1") {
          return [pscustomobject]@{ Hash = $runtimeManifestHash }
        }
        return [pscustomobject]@{ Hash = $runtimeDllHash }
      }
      Mock Import-Module { $global:AudioRuntimeTestModule }
    }

    AfterEach {
      Remove-Variable `
        -Name AudioRuntimeTestModule `
        -Scope Global `
        -ErrorAction SilentlyContinue
    }

    It "accepts the exact validated module without changing audio" {
      {
        . $scriptPath `
          -ValidateOnly `
          -DocumentsPath $runtimeDocumentsPath
      } | Should -Not -Throw

      Should -Invoke Import-Module -Times 1 -ParameterFilter {
        $Name -eq $runtimeManifestPath -and
          $Force -and
          $PassThru -and
          $ErrorAction -eq "Stop"
      }
    }

    It "rejects an imported module from a different ModuleBase" {
      $global:AudioRuntimeTestModule.ModuleBase = "C:\attacker"

      {
        . $scriptPath `
          -ValidateOnly `
          -DocumentsPath $runtimeDocumentsPath
      } | Should -Throw "*integrity*"
    }

    It "rejects an imported module with a different version" {
      $global:AudioRuntimeTestModule.Version = [version]"3.1.0.1"

      {
        . $scriptPath `
          -ValidateOnly `
          -DocumentsPath $runtimeDocumentsPath
      } | Should -Throw "*integrity*"
    }

    It "rejects an imported module without both required exports" {
      $global:AudioRuntimeTestModule.ExportedCommands = @{
        "Get-AudioDevice" = { param([switch]$List) }
      }

      {
        . $scriptPath `
          -ValidateOnly `
          -DocumentsPath $runtimeDocumentsPath
      } | Should -Throw "*integrity*"
    }
  }
}
}
