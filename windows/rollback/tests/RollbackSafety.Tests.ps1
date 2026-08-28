Describe "Rollback safety" {
BeforeAll {
  $modulePath = Join-Path $PSScriptRoot "..\RollbackSafety.psm1"
  Import-Module $modulePath -Force
}

Context "module surface" {
  It "exports only the window-manager inactivity assertions" {
    $exportedCommands = @(
      Get-Command -Module RollbackSafety |
        Select-Object -ExpandProperty Name |
        Sort-Object
    )

    $exportedCommands | Should -Be @(
      "Assert-GlazeWMInactive",
      "Assert-KomorebiInactive"
    )
  }
}

Context "Assert-KomorebiInactive" {
  BeforeEach {
    Mock Get-Process { @() } -ModuleName RollbackSafety
    Mock Test-Path { $false } -ModuleName RollbackSafety
    Mock Get-ScheduledTask { @() } -ModuleName RollbackSafety
  }

  It "allows GlazeWM when the rollback runtime and startup hooks are absent" {
    { Assert-KomorebiInactive } | Should -Not -Throw
  }

  It "blocks a running rollback process named <Name>" -TestCases @(
    @{ Name = "komorebi" }
    @{ Name = "whkd" }
    @{ Name = "komorebi-bar" }
    @{ Name = "masir" }
  ) {
    param($Name)
    Mock Get-Process {
      [pscustomobject]@{ Id = 1234; ProcessName = $Name }
    } -ModuleName RollbackSafety

    { Assert-KomorebiInactive } | Should -Throw "*rollback processes*running*"
  }

  It "blocks the Komorebi Startup shortcut" {
    Mock Test-Path { $true } -ModuleName RollbackSafety

    { Assert-KomorebiInactive } | Should -Throw "*automatic startup*"
  }

  It "blocks rollback-only app scheduled tasks" {
    Mock Get-ScheduledTask {
      [pscustomobject]@{ TaskName = "Dotfiles App - Spotify" }
    } -ModuleName RollbackSafety

    { Assert-KomorebiInactive } | Should -Throw "*scheduled tasks*"
  }

  It "fails closed when rollback process inspection fails" {
    Mock Get-Process {
      throw [System.UnauthorizedAccessException]::new("denied")
    } -ModuleName RollbackSafety

    {
      Assert-KomorebiInactive
    } | Should -Throw "*Unable to inspect Komorebi processes*denied*"
  }

  It "fails closed when Startup shortcut inspection fails" {
    Mock Test-Path {
      throw [System.UnauthorizedAccessException]::new("denied")
    } -ModuleName RollbackSafety

    {
      Assert-KomorebiInactive
    } | Should -Throw "*Unable to inspect Komorebi automatic startup*denied*"
  }

  It "fails closed when scheduled task inspection fails" {
    Mock Get-ScheduledTask {
      throw [System.UnauthorizedAccessException]::new("denied")
    } -ModuleName RollbackSafety

    {
      Assert-KomorebiInactive
    } | Should -Throw "*Unable to inspect rollback scheduled tasks*denied*"
  }
}

Context "Assert-GlazeWMInactive" {
  BeforeEach {
    Mock Get-Process { @() } -ModuleName RollbackSafety
    Mock Get-ItemProperty {
      [pscustomobject]@{}
    } -ModuleName RollbackSafety
  }

  It "allows rollback when GlazeWM is inactive and has no Run registration" {
    { Assert-GlazeWMInactive } | Should -Not -Throw
  }

  It "blocks rollback while a GlazeWM process exists" {
    Mock Get-Process {
      [pscustomobject]@{ Id = 1234; ProcessName = "glazewm" }
    } -ModuleName RollbackSafety

    { Assert-GlazeWMInactive } | Should -Throw "*GlazeWM*running*"
  }

  It "blocks rollback while the GlazeWM Run registration exists" {
    Mock Get-ItemProperty {
      [pscustomobject]@{ GlazeWM = '"C:\Program Files\GlazeWM.exe"' }
    } -ModuleName RollbackSafety

    { Assert-GlazeWMInactive } | Should -Throw "*automatic startup*"
  }

  It "allows rollback when the Run key is missing" {
    Mock Get-ItemProperty {
      throw [System.Management.Automation.ItemNotFoundException]::new(
        "Run key missing"
      )
    } -ModuleName RollbackSafety

    { Assert-GlazeWMInactive } | Should -Not -Throw
  }

  It "fails closed when process inspection fails" {
    Mock Get-Process {
      throw [System.UnauthorizedAccessException]::new("denied")
    } -ModuleName RollbackSafety

    {
      Assert-GlazeWMInactive
    } | Should -Throw "*Unable to inspect GlazeWM processes*denied*"
  }

  It "fails closed when Run registration inspection fails" {
    Mock Get-ItemProperty {
      throw [System.UnauthorizedAccessException]::new("denied")
    } -ModuleName RollbackSafety

    {
      Assert-GlazeWMInactive
    } | Should -Throw "*Unable to inspect Windows Run registrations*denied*"
  }
}

Context "direct rollback installers" {
  It "guards Komorebi before importing its component modules or mutating state" {
    $installerPath = Join-Path $PSScriptRoot "..\..\komorebi\install.ps1"
    $source = Get-Content -LiteralPath $installerPath -Raw
    $guardPathIndex = $source.IndexOf(
      'Join-Path $PSScriptRoot "..\rollback\RollbackSafety.psm1"'
    )
    $guardImportIndex = $source.IndexOf(
      'Import-Module $rollbackSafetyModule -Force -ErrorAction Stop'
    )
    $guardCallIndex = $source.IndexOf("Assert-GlazeWMInactive")
    $componentImportIndex = $source.IndexOf(
      'Import-Module $installerModule -Force -ErrorAction Stop'
    )
    $firstMutationIndex = $source.IndexOf('$configHome =')

    $guardPathIndex | Should -BeGreaterThan -1
    $guardImportIndex | Should -BeGreaterThan $guardPathIndex
    $guardCallIndex | Should -BeGreaterThan $guardImportIndex
    $componentImportIndex | Should -BeGreaterThan $guardCallIndex
    $firstMutationIndex | Should -BeGreaterThan $guardCallIndex
  }

  It "guards app autostart before importing its component module or mutating state" {
    $installerPath = Join-Path $PSScriptRoot "..\..\autostart\install.ps1"
    $source = Get-Content -LiteralPath $installerPath -Raw
    $guardPathIndex = $source.IndexOf(
      'Join-Path $PSScriptRoot "..\rollback\RollbackSafety.psm1"'
    )
    $guardImportIndex = $source.IndexOf(
      'Import-Module $rollbackSafetyModule -Force -ErrorAction Stop'
    )
    $guardCallIndex = $source.IndexOf("Assert-GlazeWMInactive")
    $componentImportIndex = $source.IndexOf(
      'Import-Module $modulePath -Force -ErrorAction Stop'
    )
    $firstMutationIndex = $source.IndexOf("Install-AppAutostartTasks")

    $guardPathIndex | Should -BeGreaterThan -1
    $guardImportIndex | Should -BeGreaterThan $guardPathIndex
    $guardCallIndex | Should -BeGreaterThan $guardImportIndex
    $componentImportIndex | Should -BeGreaterThan $guardCallIndex
    $firstMutationIndex | Should -BeGreaterThan $guardCallIndex
  }

  It "guards Komorebi updates before importing component modules or mutating state" {
    $updatePath = Join-Path $PSScriptRoot "..\..\komorebi\update-config.ps1"
    $source = Get-Content -LiteralPath $updatePath -Raw
    $guardPathIndex = $source.IndexOf(
      'Join-Path $PSScriptRoot "..\rollback\RollbackSafety.psm1"'
    )
    $guardImportIndex = $source.IndexOf(
      'Import-Module $rollbackSafetyModule -Force -ErrorAction Stop'
    )
    $guardCallIndex = $source.IndexOf("Assert-GlazeWMInactive")
    $componentImportIndex = $source.IndexOf(
      'Import-Module $installerModule -Force -ErrorAction Stop'
    )
    $firstMutationIndex = $source.IndexOf('$metadataPath =')

    $guardPathIndex | Should -BeGreaterThan -1
    $guardImportIndex | Should -BeGreaterThan $guardPathIndex
    $guardCallIndex | Should -BeGreaterThan $guardImportIndex
    $componentImportIndex | Should -BeGreaterThan $guardCallIndex
    $firstMutationIndex | Should -BeGreaterThan $guardCallIndex
  }

}
}
