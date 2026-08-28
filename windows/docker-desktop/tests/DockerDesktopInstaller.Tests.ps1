Describe "Docker Desktop installer" {
  BeforeAll {
    $dockerRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
    $windowsRoot = [IO.Path]::GetFullPath((Join-Path $dockerRoot ".."))
    $installPath = Join-Path $dockerRoot "install.ps1"
    $manifestPath = Join-Path $windowsRoot "components.json"
  }

  It "uses the official package and both supported installation locations" {
    $source = Get-Content -LiteralPath $installPath -Raw

    $source | Should -Match ([regex]::Escape("Docker.DockerDesktop"))
    $source | Should -Match ([regex]::Escape(
      "LOCALAPPDATA\Programs\DockerDesktop\Docker Desktop.exe"
    ))
    $source | Should -Match ([regex]::Escape(
      "ProgramFiles\Docker\Docker\Docker Desktop.exe"
    ))
    $source | Should -Match "Install-WinGetPackage"
    $source | Should -Match ([regex]::Escape("--user"))
    $source | Should -Match ([regex]::Escape("--accept-license"))
  }

  It "starts Docker Desktop unless explicitly skipped" {
    $source = Get-Content -LiteralPath $installPath -Raw

    $source | Should -Match '\[switch\]\$SkipStart'
    $source | Should -Match 'Start-Process'
  }

  It "is an optional active Windows component" {
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $component = @(
      $manifest.components |
        Where-Object { $_.name -eq "docker-desktop" }
    )

    $component.Count | Should -Be 1
    $component[0].lifecycle | Should -Be "active"
    $component[0].selectionPolicy | Should -Be "optional"
    $component[0].entrypoints.install |
      Should -Be "docker-desktop/install.ps1"
  }
}
