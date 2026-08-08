Describe "WezTerm configuration" {
BeforeAll {
  $weztermRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
  $repoRoot = [System.IO.Path]::GetFullPath((Join-Path $weztermRoot "..\.."))
  $configPath = Join-Path $repoRoot "stow\base\.config\wezterm\wezterm.lua"
  $zshrcPath = Join-Path $repoRoot "stow\base\.zshrc"
  $fontInstallerModulePath = Join-Path $weztermRoot "FontInstaller.psm1"
  $fontInstallScriptPath = Join-Path $weztermRoot "install-fonts.ps1"
  $installScriptPath = Join-Path $weztermRoot "install.ps1"
  $updateScriptPath = Join-Path $weztermRoot "update-config.ps1"

  function Assert-Equal {
    param($Actual, $Expected)
    if ($Actual -ne $Expected) {
      throw "Expected '$Expected', got '$Actual'."
    }
  }

  function Assert-Matches {
    param([string]$Actual, [string]$Pattern)
    if ($Actual -notmatch $Pattern) {
      throw "Expected content to match '$Pattern'."
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

Context "Version-controlled Kitty baseline appearance" {
  It "matches the Arch Kitty font and window appearance" {
    $config = Get-Content -LiteralPath $configPath -Raw

    Assert-Matches $config (
      "(?s)wezterm\.font_with_fallback\s*\{\s*" +
      "'JetBrainsMono Nerd Font'\s*,\s*" +
      "'Noto Sans Mono CJK JP'\s*,?\s*\}"
    )
    Assert-Matches $config "font_size\s*=\s*13"
    Assert-Matches $config "default_cursor_style\s*=\s*'SteadyBar'"
    Assert-Matches $config "window_background_opacity\s*=\s*0\.7"
    if ($config -match 'win32_system_backdrop\s*=\s*[''"]Acrylic[''"]') {
      throw "Windows Acrylic must remain disabled so unfocused windows stay translucent."
    }
    Assert-Matches $config "use_fancy_tab_bar\s*=\s*false"
    Assert-Matches $config "hide_tab_bar_if_only_one_tab\s*=\s*true"
  }

  It "uses a bar in Zsh insert mode and a block in command mode" {
    $zshrc = Get-Content -LiteralPath $zshrcPath -Raw

    Assert-Matches $zshrc "add-zle-hook-widget\s+keymap-select"
    Assert-Matches $zshrc "add-zle-hook-widget\s+line-init"
    Assert-Matches $zshrc "add-zle-hook-widget\s+line-finish"
    Assert-Matches $zshrc "vicmd\).*\\e\[2 q"
    Assert-Matches $zshrc "viins\|main\).*\\e\[6 q"
    if ($zshrc -match "zle\s+-N\s+zle-(keymap-select|line-init|line-finish)") {
      throw "Cursor hooks must not replace existing ZLE widgets."
    }
  }

  It "hides the title bar and opens the Arch WSL domain by default" {
    $config = Get-Content -LiteralPath $configPath -Raw

    Assert-Matches $config "window_decorations\s*=\s*'RESIZE'"
    Assert-Matches $config "default_domain\s*=\s*'WSL:archlinux'"
  }

  It "contains the Catppuccin Mocha colors used by Kitty" {
    $config = Get-Content -LiteralPath $configPath -Raw

    foreach ($color in @(
      "#CDD6F4", "#1E1E2E", "#F5E0DC", "#CBA6F7",
      "#45475A", "#F38BA8", "#A6E3A1", "#F9E2AF",
      "#89B4FA", "#F5C2E7", "#94E2D5", "#BAC2DE"
    )) {
      Assert-Matches $config ([regex]::Escape($color))
    }
  }
}

Context "Codex composer input compatibility" {
  It "does not enable the keyboard protocol that breaks Windows IME input" {
    $config = Get-Content -LiteralPath $configPath -Raw

    if ($config -match "enable_kitty_keyboard\s*=\s*true") {
      throw "Kitty keyboard mode must remain disabled for Windows IME compatibility."
    }
  }

  It "maps Shift-Enter to the Codex newline key without changing other Shift input" {
    $weztermConfig = Get-Content -LiteralPath $configPath -Raw
    Assert-Matches $weztermConfig "key\s*=\s*'Enter'"
    Assert-Matches $weztermConfig "mods\s*=\s*'SHIFT'"
    Assert-Matches $weztermConfig "SendKey\s*\{\s*key\s*=\s*'j',\s*mods\s*=\s*'CTRL'\s*\}"
  }
}

Context "Windows deployment" {
  It "resolves the managed config from the script location by default" {
    $caseRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString("N"))

    $result = & $updateScriptPath -UserProfile $caseRoot
    $destinationPath = Join-Path $caseRoot ".config\wezterm\wezterm.lua"

    Assert-Equal (Test-Path -LiteralPath $destinationPath -PathType Leaf) $true
    Assert-Equal $result.Changed $true
    Assert-Equal (
      (Get-FileHash -LiteralPath $destinationPath -Algorithm SHA256).Hash
    ) (
      (Get-FileHash -LiteralPath $configPath -Algorithm SHA256).Hash
    )
  }

  It "installs the managed config under USERPROFILE" {
    $caseRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString("N"))
    $sourcePath = Join-Path $caseRoot "source.lua"
    New-Item -ItemType Directory -Path $caseRoot | Out-Null
    [System.IO.File]::WriteAllText($sourcePath, "return { font_size = 13 }")

    $result = & $updateScriptPath -SourcePath $sourcePath -UserProfile $caseRoot
    $destinationPath = Join-Path $caseRoot ".config\wezterm\wezterm.lua"

    Assert-Equal (Get-Content -LiteralPath $destinationPath -Raw) "return { font_size = 13 }"
    Assert-Equal $result.Changed $true
    Assert-Equal $result.DestinationPath $destinationPath
    Assert-Equal $result.BackupPath $null
  }

  It "backs up an existing config before replacing it" {
    $caseRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString("N"))
    $sourcePath = Join-Path $caseRoot "source.lua"
    $destinationPath = Join-Path $caseRoot ".config\wezterm\wezterm.lua"
    New-Item -ItemType Directory -Path (Split-Path $destinationPath) | Out-Null
    [System.IO.File]::WriteAllText($sourcePath, "new")
    [System.IO.File]::WriteAllText($destinationPath, "existing")

    $result = & $updateScriptPath -SourcePath $sourcePath -UserProfile $caseRoot

    Assert-Equal (Get-Content -LiteralPath $destinationPath -Raw) "new"
    Assert-Equal (Get-Content -LiteralPath $result.BackupPath -Raw) "existing"
  }

  It "never replaces an existing config without a backup path" {
    $updateScript = Get-Content -LiteralPath $updateScriptPath -Raw

    Assert-Matches $updateScript ([regex]::Escape(
      '[System.IO.File]::Replace($temporaryPath, $destinationPath, $backupPath)'
    ))
    if ($updateScript -match "File\]::Replace\([^\r\n]+,\s*\`$null\s*\)") {
      throw "File.Replace must always receive a backup path."
    }
  }

  It "does not rewrite an unchanged config" {
    $caseRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString("N"))
    $sourcePath = Join-Path $caseRoot "source.lua"
    $destinationPath = Join-Path $caseRoot ".config\wezterm\wezterm.lua"
    New-Item -ItemType Directory -Path (Split-Path $destinationPath) | Out-Null
    [System.IO.File]::WriteAllText($sourcePath, "same")
    [System.IO.File]::WriteAllText($destinationPath, "same")

    $result = & $updateScriptPath -SourcePath $sourcePath -UserProfile $caseRoot

    Assert-Equal $result.Changed $false
    Assert-Equal $result.BackupPath $null
  }

  It "rejects a missing source config" {
    $caseRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString("N"))

    Assert-Throws {
      & $updateScriptPath `
        -SourcePath (Join-Path $caseRoot "missing.lua") `
        -UserProfile $caseRoot
    }
  }
}

Context "Windows font installation" {
  It "pins the official font archives and required WezTerm faces" {
    Import-Module $fontInstallerModulePath -Force

    $packages = @(Get-WezTermFontPackages)
    $jetBrains = @($packages | Where-Object Name -eq "JetBrains Mono Nerd Font")
    $noto = @($packages | Where-Object Name -eq "Noto Sans Mono CJK JP")

    Assert-Equal $jetBrains.Count 1
    Assert-Equal $jetBrains[0].Version "3.5.0"
    Assert-Equal $jetBrains[0].Uri.Host "github.com"
    Assert-Equal $jetBrains[0].Sha256 (
      "9577de1ae84ec523df16fc69bac5338b89497a5b4fb91489e2dcb79dc06ac2b5"
    )
    Assert-Equal $jetBrains[0].Fonts.Count 4
    Assert-Equal $noto.Count 1
    Assert-Equal $noto[0].Version "2.004"
    Assert-Equal $noto[0].Uri.Host "github.com"
    Assert-Equal $noto[0].Sha256 (
      "6c8faf475ce78fa37486dd5d8920e4bb4450b1b0f3c497edf3ba2d25cf52ab78"
    )
    Assert-Equal $noto[0].Fonts.Count 2
  }

  It "rejects a downloaded archive with the wrong SHA-256" {
    Import-Module $fontInstallerModulePath -Force
    $archivePath = Join-Path $TestDrive "font.zip"
    [System.IO.File]::WriteAllText($archivePath, "unexpected")

    Assert-Throws {
      Assert-FontArchiveHash `
        -Path $archivePath `
        -ExpectedSha256 ("0" * 64)
    }
  }

  It "registers a user font idempotently" {
    Import-Module $fontInstallerModulePath -Force
    $caseRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString("N"))
    $sourcePath = Join-Path $caseRoot "source\ExampleFont-Regular.ttf"
    $fontsDirectory = Join-Path $caseRoot "fonts"
    $registryPath = (
      "HKCU:\Software\DotfilesTests\WezTermFonts\" +
      [guid]::NewGuid().ToString("N")
    )
    New-Item -ItemType Directory -Path (Split-Path $sourcePath) | Out-Null
    [System.IO.File]::WriteAllText($sourcePath, "font payload")

    try {
      $first = Install-UserFontFile `
        -SourcePath $sourcePath `
        -RegistryName "Example Font Regular (TrueType)" `
        -FontsDirectory $fontsDirectory `
        -RegistryPath $registryPath
      $second = Install-UserFontFile `
        -SourcePath $sourcePath `
        -RegistryName "Example Font Regular (TrueType)" `
        -FontsDirectory $fontsDirectory `
        -RegistryPath $registryPath

      Assert-Equal $first.Changed $true
      Assert-Equal $second.Changed $false
      Assert-Equal (
        Test-FontRegistration `
          -RegistryName "Example Font Regular (TrueType)" `
          -RegistryPaths @($registryPath) `
          -WindowsFontsDirectory $fontsDirectory
      ) $true
    } finally {
      Remove-Item -LiteralPath $registryPath -Recurse -Force -ErrorAction SilentlyContinue
    }
  }

  It "refuses to overwrite a different existing user font file" {
    Import-Module $fontInstallerModulePath -Force
    $caseRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString("N"))
    $sourcePath = Join-Path $caseRoot "source\ExampleFont-Regular.ttf"
    $fontsDirectory = Join-Path $caseRoot "fonts"
    $destinationPath = Join-Path $fontsDirectory "ExampleFont-Regular.ttf"
    $registryPath = (
      "HKCU:\Software\DotfilesTests\WezTermFonts\" +
      [guid]::NewGuid().ToString("N")
    )
    New-Item -ItemType Directory -Path (Split-Path $sourcePath) | Out-Null
    New-Item -ItemType Directory -Path $fontsDirectory | Out-Null
    [System.IO.File]::WriteAllText($sourcePath, "managed payload")
    [System.IO.File]::WriteAllText($destinationPath, "existing payload")

    try {
      Assert-Throws {
        Install-UserFontFile `
          -SourcePath $sourcePath `
          -RegistryName "Example Font Regular (TrueType)" `
          -FontsDirectory $fontsDirectory `
          -RegistryPath $registryPath
      }
    } finally {
      Remove-Item -LiteralPath $registryPath -Recurse -Force -ErrorAction SilentlyContinue
    }
  }

  It "refuses to replace a valid font registration owned elsewhere" {
    Import-Module $fontInstallerModulePath -Force
    $caseRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString("N"))
    $sourcePath = Join-Path $caseRoot "source\ExampleFont-Regular.ttf"
    $fontsDirectory = Join-Path $caseRoot "fonts"
    $existingPath = Join-Path $caseRoot "existing\ExampleFont-Regular.ttf"
    $registryPath = (
      "HKCU:\Software\DotfilesTests\WezTermFonts\" +
      [guid]::NewGuid().ToString("N")
    )
    New-Item -ItemType Directory -Path (Split-Path $sourcePath) | Out-Null
    New-Item -ItemType Directory -Path (Split-Path $existingPath) | Out-Null
    [System.IO.File]::WriteAllText($sourcePath, "managed payload")
    [System.IO.File]::WriteAllText($existingPath, "existing payload")

    try {
      New-Item -Path $registryPath -Force | Out-Null
      New-ItemProperty `
        -LiteralPath $registryPath `
        -Name "Example Font Regular (TrueType)" `
        -Value $existingPath `
        -PropertyType String | Out-Null
      Assert-Throws {
        Install-UserFontFile `
          -SourcePath $sourcePath `
          -RegistryName "Example Font Regular (TrueType)" `
          -FontsDirectory $fontsDirectory `
          -RegistryPath $registryPath
      }
    } finally {
      Remove-Item -LiteralPath $registryPath -Recurse -Force -ErrorAction SilentlyContinue
    }
  }

  It "runs font and config setup from the Windows and WSL installers" {
    $fontInstallScript = Get-Content -LiteralPath $fontInstallScriptPath -Raw
    $installScript = Get-Content -LiteralPath $installScriptPath -Raw
    $rootInstallScript = Get-Content -LiteralPath (
      Join-Path $repoRoot "install.sh"
    ) -Raw

    Assert-Matches $fontInstallScript "Get-WezTermFontPackages"
    Assert-Matches $installScript ([regex]::Escape("install-fonts.ps1"))
    Assert-Matches $installScript ([regex]::Escape("update-config.ps1"))
    Assert-Matches $rootInstallScript (
      [regex]::Escape("windows/wezterm/install.ps1")
    )
  }
}
}
