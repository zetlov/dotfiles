Describe "1Password installer" {
  BeforeAll {
    $componentRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
    $windowsRoot = [IO.Path]::GetFullPath((Join-Path $componentRoot ".."))
    $installPath = Join-Path $componentRoot "install.ps1"
    $manifestPath = Join-Path $windowsRoot "components.json"
  }

  It "uses the official WinGet package and Appx identity" {
    $source = Get-Content -LiteralPath $installPath -Raw

    $source | Should -Match ([regex]::Escape("AgileBits.1Password"))
    $source | Should -Match ([regex]::Escape("Agilebits.1Password"))
    $source | Should -Match "Install-WinGetPackage"
  }

  It "is a required active Windows component" {
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $component = @(
      $manifest.components |
        Where-Object { $_.name -eq "onepassword" }
    )

    $component.Count | Should -Be 1
    $component[0].lifecycle | Should -Be "active"
    $component[0].selectionPolicy | Should -Be "required"
    $component[0].entrypoints.install |
      Should -Be "onepassword/install.ps1"
    $component[0].entrypoints.update |
      Should -Be "onepassword/install.ps1"
  }
}
