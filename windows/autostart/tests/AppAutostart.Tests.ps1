Describe "Windows app autostart" {
BeforeAll {
  $modulePath = Join-Path $PSScriptRoot "..\AppAutostart.psm1"
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

Context "managed configuration" {
  It "defines the requested apps and workspaces" {
    $configPath = Join-Path $PSScriptRoot "..\apps.json"
    $config = Read-AppAutostartConfig -Path $configPath
    $expected = @{
      "Zen" = 1
      "Zotero" = 2
      "Raindrop" = 2
      "Todoist" = 2
      "Notion Calendar" = 2
      "Spotify" = 3
      "Discord" = 3
      "Obsidian" = 4
    }

    Assert-Equal @($config.apps).Count $expected.Count
    foreach ($app in @($config.apps)) {
      Assert-Equal $app.workspace $expected[$app.name]
    }
  }

  It "rejects duplicate names" {
    $configPath = Join-Path $TestDrive "duplicate.json"
    [System.IO.File]::WriteAllText(
      $configPath,
      '{"version":1,"apps":[' +
        '{"name":"App","workspace":1,"launch_type":"appx","app_id":"Example.App_123!App","delay_seconds":1},' +
        '{"name":"App","workspace":2,"launch_type":"appx","app_id":"Example.App_123!App","delay_seconds":2}' +
      ']}'
    )

    Assert-Throws { Read-AppAutostartConfig -Path $configPath }
  }
}

Context "action resolution" {
  It "uses the first installed executable candidate" {
    $first = Join-Path $TestDrive "missing.exe"
    $second = Join-Path $TestDrive "installed.exe"
    [System.IO.File]::WriteAllText($second, "test")
    $app = [pscustomobject]@{
      name = "Example"
      launch_type = "executable"
      path_candidates = @($first, $second)
      arguments = "--example"
    }

    $action = Resolve-AppAutostartAction -App $app

    Assert-Equal $action.Execute ([System.IO.Path]::GetFullPath($second))
    Assert-Equal $action.Arguments "--example"
    Assert-Equal $action.WorkingDirectory (Split-Path -Parent $second)
  }

  It "rejects an app with no installed executable" {
    $app = [pscustomobject]@{
      name = "Missing"
      launch_type = "executable"
      path_candidates = @((Join-Path $TestDrive "missing.exe"))
      arguments = ""
    }

    Assert-Throws { Resolve-AppAutostartAction -App $app }
  }

  It "uses Explorer for an AppX application" {
    $originalWindir = $env:WINDIR
    try {
      $env:WINDIR = Join-Path $TestDrive "Windows"
      New-Item -ItemType Directory -Path $env:WINDIR | Out-Null
      [System.IO.File]::WriteAllText(
        (Join-Path $env:WINDIR "explorer.exe"),
        "test"
      )
      $app = [pscustomobject]@{
        name = "Store App"
        launch_type = "appx"
        app_id = "Example.App_123!App"
      }

      $action = Resolve-AppAutostartAction -App $app

      Assert-Equal $action.Execute (Join-Path $env:WINDIR "explorer.exe")
      Assert-Equal $action.Arguments "shell:AppsFolder\Example.App_123!App"
      Assert-Equal ($null -eq $action.WorkingDirectory) $true
    } finally {
      $env:WINDIR = $originalWindir
    }
  }
}

Context "task ownership" {
  It "uses a narrow task name prefix" {
    Assert-Equal (Get-AppAutostartTaskName -Name "Spotify") "Dotfiles App - Spotify"
  }

  It "rejects task separator characters" {
    Assert-Throws { Get-AppAutostartTaskName -Name "Folder\App" }
  }
}
}
