Describe "Windows component orchestrator" {
  BeforeAll {
    $windowsRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
    $manifestPath = Join-Path $windowsRoot "components.json"
    $modulePath = Join-Path `
      $windowsRoot `
      "orchestrator\WindowsOrchestrator.psm1"
    $rootInstallerPath = Join-Path $windowsRoot "install.ps1"

    Import-Module $modulePath -Force -ErrorAction Stop
    $catalog = @(
      Import-WindowsComponentCatalog `
        -Path $manifestPath `
        -WindowsRoot $windowsRoot
    )
  }

  It "keeps the lifecycle manifest authoritative" {
    $expected = @{
      glazewm = "active|optional"
      zebar = "active|managed"
      audio = "shared|managed"
      wezterm = "active|required"
      kanata = "active|required"
      komorebi = "rollback-only|rollback-only"
      autostart = "rollback-only|rollback-only"
    }

    $catalog.Count | Should -Be $expected.Count
    foreach ($component in $catalog) {
      $expected[$component.Name] |
        Should -Be "$($component.Lifecycle)|$($component.SelectionPolicy)"
    }
  }

  It "loads the fixed implementation files in dependency order" {
    $expectedFiles = @(
      "Catalog.ps1",
      "Planning.ps1",
      "Runtime.ps1",
      "Execution.ps1"
    )
    $moduleRoot = Split-Path -Parent $modulePath
    foreach ($fileName in $expectedFiles) {
      Test-Path -LiteralPath (Join-Path $moduleRoot $fileName) -PathType Leaf |
        Should -BeTrue
    }

    $moduleSource = Get-Content -LiteralPath $modulePath -Raw
    $lastIndex = -1
    foreach ($fileName in $expectedFiles) {
      $sourceExpression = '. (Join-Path $PSScriptRoot "' + $fileName + '")'
      $sourceIndex = $moduleSource.IndexOf($sourceExpression)
      $sourceIndex | Should -BeGreaterThan $lastIndex
      $lastIndex = $sourceIndex
    }
  }

  It "keeps each implementation file focused on its assigned functions" {
    $expectedFunctions = [ordered]@{
      "Catalog.ps1" = @(
        "Test-WindowsEntrypointPath",
        "Assert-WindowsTrustedEntrypoint",
        "Get-RequiredProperty",
        "Import-WindowsComponentCatalog"
      )
      "Planning.ps1" = @(
        "Resolve-WindowsComponentPlan",
        "Assert-WindowsComponentPlan",
        "Assert-WindowsSelectionPolicy"
      )
      "Runtime.ps1" = @(
        "Get-WindowsProcessMatches",
        "Test-WindowsRunValue",
        "Test-KomorebiStartupShortcut",
        "Get-RollbackAutostartTasks",
        "Assert-WindowsRuntimeCompatibility"
      )
      "Execution.ps1" = @(
        "Invoke-WindowsComponentEntrypoint",
        "Assert-WindowsComponentExecutionPreflight",
        "Invoke-WindowsComponentPlan",
        "Invoke-WindowsComponentSelection"
      )
    }
    $moduleRoot = Split-Path -Parent $modulePath
    foreach ($entry in $expectedFunctions.GetEnumerator()) {
      $implementationPath = Join-Path $moduleRoot $entry.Key
      if (-not (Test-Path -LiteralPath $implementationPath -PathType Leaf)) {
        continue
      }
      $source = Get-Content -LiteralPath $implementationPath -Raw
      $actualFunctions = @(
        [regex]::Matches($source, '(?m)^function ([A-Za-z0-9-]+)') |
          ForEach-Object { $_.Groups[1].Value }
      )
      $actualFunctions | Should -Be $entry.Value
    }
  }

  It "exports exactly the supported public functions" {
    $module = Get-Module -Name "WindowsOrchestrator"

    @($module.ExportedFunctions.Keys | Sort-Object) | Should -Be @(
      "Assert-WindowsComponentPlan",
      "Import-WindowsComponentCatalog",
      "Invoke-WindowsComponentSelection",
      "Resolve-WindowsComponentPlan"
    )
  }

  It "selects required components in deterministic order by default" {
    $plan = @(
      Resolve-WindowsComponentPlan `
        -Catalog $catalog `
        -Mode Install `
        -WindowsRoot $windowsRoot
    )

    @($plan.Name) | Should -Be @("wezterm", "kanata")
    @($plan.Entrypoint) | Should -Be @(
      "wezterm/install.ps1",
      "kanata/install.ps1"
    )
  }

  It "uses update entrypoints for the default update plan" {
    $plan = @(
      Resolve-WindowsComponentPlan `
        -Catalog $catalog `
        -Mode Update `
        -WindowsRoot $windowsRoot
    )

    @($plan.Name) | Should -Be @("wezterm", "kanata")
    @($plan.Entrypoint) | Should -Be @(
      "wezterm/update-config.ps1",
      "kanata/update-config.ps1"
    )
  }

  It "canonicalizes explicit component order" {
    $plan = @(
      Resolve-WindowsComponentPlan `
        -Catalog $catalog `
        -Mode Install `
        -Component @("glazewm", "kanata", "wezterm") `
        -WindowsRoot $windowsRoot
    )

    @($plan.Name) | Should -Be @("wezterm", "kanata", "glazewm")
  }

  It "keeps managed dependencies inside their current owner" {
    $plan = @(
      Resolve-WindowsComponentPlan `
        -Catalog $catalog `
        -Mode Install `
        -Component "glazewm" `
        -WindowsRoot $windowsRoot
    )

    @($plan.Name) | Should -Be @("glazewm")
    {
      Resolve-WindowsComponentPlan `
        -Catalog $catalog `
        -Mode Install `
        -Component "zebar" `
        -WindowsRoot $windowsRoot
    } | Should -Throw "*managed by*"
    {
      Resolve-WindowsComponentPlan `
        -Catalog $catalog `
        -Mode Install `
        -Component "audio" `
        -WindowsRoot $windowsRoot
    } | Should -Throw "*managed by*"
  }

  It "requires an explicit gate for rollback-only components" {
    {
      Resolve-WindowsComponentPlan `
        -Catalog $catalog `
        -Mode Install `
        -Component "komorebi" `
        -WindowsRoot $windowsRoot
    } | Should -Throw "*AllowRollbackOnly*"

    $plan = @(
      Resolve-WindowsComponentPlan `
        -Catalog $catalog `
        -Mode Install `
        -Component @("komorebi", "autostart") `
        -AllowRollbackOnly `
        -WindowsRoot $windowsRoot
    )
    @($plan.Name) | Should -Be @("komorebi", "autostart")
  }

  It "requires declared companion selections" {
    {
      Resolve-WindowsComponentPlan `
        -Catalog $catalog `
        -Mode Install `
        -Component "autostart" `
        -AllowRollbackOnly `
        -WindowsRoot $windowsRoot
    } | Should -Throw "*requires*komorebi*"
  }

  It "rejects conflicting window manager selections before execution" {
    {
      Resolve-WindowsComponentPlan `
        -Catalog $catalog `
        -Mode Install `
        -Component @("glazewm", "komorebi") `
        -AllowRollbackOnly `
        -WindowsRoot $windowsRoot
    } | Should -Throw "*conflict*"

    {
      Resolve-WindowsComponentPlan `
        -Catalog $catalog `
        -Mode Install `
        -Component @("glazewm", "autostart") `
        -AllowRollbackOnly `
        -WindowsRoot $windowsRoot
    } | Should -Throw "*conflict*"
  }

  It "rejects unknown, duplicate, and unsafe component definitions" {
    {
      Resolve-WindowsComponentPlan `
        -Catalog $catalog `
        -Mode Install `
        -Component "unknown" `
        -WindowsRoot $windowsRoot
    } | Should -Throw "*Unknown Windows component*"
    {
      Resolve-WindowsComponentPlan `
        -Catalog $catalog `
        -Mode Install `
        -Component @("wezterm", "WEZTERM") `
        -WindowsRoot $windowsRoot
    } | Should -Throw "*duplicate*"

    $unsafeManifest = Join-Path $TestDrive "unsafe-components.json"
    [IO.File]::WriteAllText($unsafeManifest, @'
{
  "schemaVersion": 1,
  "components": [
    {
      "name": "unsafe",
      "lifecycle": "active",
      "selectionPolicy": "required",
      "order": 10,
      "managedBy": [],
      "conflictsWith": [],
      "requiresSelection": [],
      "entrypoints": {
        "install": "../outside.ps1",
        "update": "../outside.ps1"
      }
    }
  ]
}
'@)

    {
      Import-WindowsComponentCatalog `
        -Path $unsafeManifest `
        -WindowsRoot $windowsRoot
    } | Should -Throw "*safe relative PowerShell script*"
  }

  It "rejects lifecycle and selection policy mismatches" {
    $invalidManifest = Join-Path $TestDrive "invalid-lifecycle.json"
    [IO.File]::WriteAllText($invalidManifest, @'
{
  "schemaVersion": 1,
  "components": [
    {
      "name": "unsafe-rollback",
      "lifecycle": "rollback-only",
      "selectionPolicy": "optional",
      "order": 10,
      "managedBy": [],
      "conflictsWith": [],
      "requiresSelection": [],
      "entrypoints": {
        "install": "wezterm/install.ps1",
        "update": "wezterm/update-config.ps1"
      }
    }
  ]
}
'@)

    {
      Import-WindowsComponentCatalog `
        -Path $invalidManifest `
        -WindowsRoot $windowsRoot
    } | Should -Throw "*rollback-only*"
  }

  It "requires owners for managed components" {
    $invalidManifest = Join-Path $TestDrive "invalid-managed.json"
    [IO.File]::WriteAllText($invalidManifest, @'
{
  "schemaVersion": 1,
  "components": [
    {
      "name": "orphan",
      "lifecycle": "shared",
      "selectionPolicy": "managed",
      "order": 10,
      "managedBy": [],
      "conflictsWith": [],
      "requiresSelection": [],
      "entrypoints": {}
    }
  ]
}
'@)

    {
      Import-WindowsComponentCatalog `
        -Path $invalidManifest `
        -WindowsRoot $windowsRoot
    } | Should -Throw "*owner*"
  }

  It "requires a nonempty catalog and complete selectable entrypoints" {
    $emptyManifest = Join-Path $TestDrive "empty-components.json"
    [IO.File]::WriteAllText(
      $emptyManifest,
      '{ "schemaVersion": 1, "components": [] }'
    )
    {
      Import-WindowsComponentCatalog `
        -Path $emptyManifest `
        -WindowsRoot $windowsRoot
    } | Should -Throw "*empty*"

    $incompleteManifest = Join-Path $TestDrive "incomplete-component.json"
    [IO.File]::WriteAllText($incompleteManifest, @'
{
  "schemaVersion": 1,
  "components": [
    {
      "name": "incomplete",
      "lifecycle": "active",
      "selectionPolicy": "optional",
      "order": 10,
      "managedBy": [],
      "conflictsWith": [],
      "requiresSelection": [],
      "entrypoints": {
        "install": "wezterm/install.ps1"
      }
    }
  ]
}
'@)
    {
      Import-WindowsComponentCatalog `
        -Path $incompleteManifest `
        -WindowsRoot $windowsRoot
    } | Should -Throw "*update entrypoint*"
  }

  It "rejects reparse-point-backed entrypoints" {
    Mock Get-Item {
      [pscustomobject]@{
        Attributes = [IO.FileAttributes]::ReparsePoint
      }
    } -ModuleName WindowsOrchestrator -ParameterFilter {
      $LiteralPath -like "*wezterm*"
    }

    {
      Import-WindowsComponentCatalog `
        -Path $manifestPath `
        -WindowsRoot $windowsRoot
    } | Should -Throw "*reparse*"
  }

  It "preflights every selected entrypoint before invoking any component" {
    $invalidPlan = @(
      Resolve-WindowsComponentPlan `
        -Catalog $catalog `
        -Mode Install `
        -WindowsRoot $windowsRoot
    )
    $invalidPlan[1].EntrypointPath = Join-Path $TestDrive "missing.ps1"

    Mock Invoke-WindowsComponentEntrypoint {} `
      -ModuleName WindowsOrchestrator

    {
      Assert-WindowsComponentPlan `
        -Plan $invalidPlan `
        -Catalog $catalog `
        -WindowsRoot $windowsRoot
    } | Should -Throw "*entrypoint*"
    Should -Invoke Invoke-WindowsComponentEntrypoint `
      -ModuleName WindowsOrchestrator `
      -Times 0
  }

  It "does not execute a caller-supplied plan outside the catalog" {
    $invalidPlan = @(
      Resolve-WindowsComponentPlan `
        -Catalog $catalog `
        -Mode Install `
        -Component "wezterm" `
        -WindowsRoot $windowsRoot
    )
    $externalScript = Join-Path $TestDrive "external.ps1"
    [IO.File]::WriteAllText($externalScript, "throw 'called'")
    $invalidPlan[0].EntrypointPath = $externalScript

    Mock Invoke-WindowsComponentEntrypoint {} `
      -ModuleName WindowsOrchestrator

    {
      Assert-WindowsComponentPlan `
        -Plan $invalidPlan `
        -Catalog $catalog `
        -WindowsRoot $windowsRoot
    } | Should -Throw "*does not match the catalog*"
    Should -Invoke Invoke-WindowsComponentEntrypoint `
      -ModuleName WindowsOrchestrator `
      -Times 0
  }

  It "blocks rollback execution while GlazeWM is running" {
    Mock Get-Process {
      [pscustomobject]@{ Id = 1234; ProcessName = "glazewm" }
    } -ModuleName WindowsOrchestrator
    Mock Invoke-WindowsComponentEntrypoint {} `
      -ModuleName WindowsOrchestrator

    {
      Invoke-WindowsComponentSelection `
        -Mode Install `
        -Component "komorebi" `
        -AllowRollbackOnly
    } | Should -Throw "*GlazeWM*running*"
    Should -Invoke Invoke-WindowsComponentEntrypoint `
      -ModuleName WindowsOrchestrator `
      -Times 0
  }

  It "blocks rollback execution while GlazeWM autostart is enabled" {
    Mock Get-Process { @() } -ModuleName WindowsOrchestrator
    Mock Get-ItemProperty {
      [pscustomobject]@{ GlazeWM = '"C:\Program Files\GlazeWM.exe"' }
    } -ModuleName WindowsOrchestrator
    Mock Invoke-WindowsComponentEntrypoint {} `
      -ModuleName WindowsOrchestrator

    {
      Invoke-WindowsComponentSelection `
        -Mode Install `
        -Component "komorebi" `
        -AllowRollbackOnly
    } | Should -Throw "*automatic startup*"
    Should -Invoke Invoke-WindowsComponentEntrypoint `
      -ModuleName WindowsOrchestrator `
      -Times 0
  }

  It "fails closed when GlazeWM autostart cannot be inspected" {
    Mock Get-Process { @() } -ModuleName WindowsOrchestrator
    Mock Get-ItemProperty {
      throw [UnauthorizedAccessException]::new("denied")
    } -ModuleName WindowsOrchestrator
    Mock Invoke-WindowsComponentEntrypoint {} `
      -ModuleName WindowsOrchestrator

    {
      Invoke-WindowsComponentSelection `
        -Mode Install `
        -Component "komorebi" `
        -AllowRollbackOnly
    } | Should -Throw "*Unable to inspect Windows Run registrations*"
    Should -Invoke Invoke-WindowsComponentEntrypoint `
      -ModuleName WindowsOrchestrator `
      -Times 0
  }

  It "blocks GlazeWM while Komorebi processes are running" {
    Mock Get-Process {
      [pscustomobject]@{ Id = 5678; ProcessName = "komorebi" }
    } -ModuleName WindowsOrchestrator
    Mock Invoke-WindowsComponentEntrypoint {} `
      -ModuleName WindowsOrchestrator

    {
      Invoke-WindowsComponentSelection `
        -Mode Install `
        -Component "glazewm"
    } | Should -Throw "*Komorebi rollback processes are running*"
    Should -Invoke Invoke-WindowsComponentEntrypoint `
      -ModuleName WindowsOrchestrator `
      -Times 0
  }

  It "blocks GlazeWM while the Komorebi startup shortcut exists" {
    Mock Get-Process { @() } -ModuleName WindowsOrchestrator
    Mock Test-KomorebiStartupShortcut { $true } `
      -ModuleName WindowsOrchestrator
    Mock Invoke-WindowsComponentEntrypoint {} `
      -ModuleName WindowsOrchestrator

    {
      Invoke-WindowsComponentSelection `
        -Mode Install `
        -Component "glazewm"
    } | Should -Throw "*Komorebi automatic startup*"
    Should -Invoke Invoke-WindowsComponentEntrypoint `
      -ModuleName WindowsOrchestrator `
      -Times 0
  }

  It "blocks GlazeWM while rollback app tasks exist" {
    Mock Get-Process { @() } -ModuleName WindowsOrchestrator
    Mock Test-KomorebiStartupShortcut { $false } `
      -ModuleName WindowsOrchestrator
    Mock Get-ScheduledTask {
      [pscustomobject]@{ TaskName = "Dotfiles App - Todoist" }
    } -ModuleName WindowsOrchestrator
    Mock Invoke-WindowsComponentEntrypoint {} `
      -ModuleName WindowsOrchestrator

    {
      Invoke-WindowsComponentSelection `
        -Mode Install `
        -Component "glazewm"
    } | Should -Throw "*Rollback-only app autostart tasks*"
    Should -Invoke Invoke-WindowsComponentEntrypoint `
      -ModuleName WindowsOrchestrator `
      -Times 0
  }

  It "fails closed when scheduled tasks cannot be inspected" {
    Mock Get-Process { @() } -ModuleName WindowsOrchestrator
    Mock Test-KomorebiStartupShortcut { $false } `
      -ModuleName WindowsOrchestrator
    Mock Get-ScheduledTask { throw "probe failed" } `
      -ModuleName WindowsOrchestrator
    Mock Invoke-WindowsComponentEntrypoint {} `
      -ModuleName WindowsOrchestrator

    {
      Invoke-WindowsComponentSelection `
        -Mode Install `
        -Component "glazewm"
    } | Should -Throw "*Unable to inspect scheduled tasks*"
    Should -Invoke Invoke-WindowsComponentEntrypoint `
      -ModuleName WindowsOrchestrator `
      -Times 0
  }

  It "runs runtime compatibility checks in Preflight without entrypoints" {
    Mock Get-Process {
      [pscustomobject]@{ Id = 1234; ProcessName = "glazewm" }
    } -ModuleName WindowsOrchestrator
    Mock Invoke-WindowsComponentEntrypoint {} `
      -ModuleName WindowsOrchestrator

    {
      Invoke-WindowsComponentSelection `
        -Mode Install `
        -Component "komorebi" `
        -AllowRollbackOnly `
        -Preflight
    } | Should -Throw "*GlazeWM*running*"
    Should -Invoke Invoke-WindowsComponentEntrypoint `
      -ModuleName WindowsOrchestrator `
      -Times 0
  }

  It "fails closed when process inspection fails in Preflight" {
    Mock Get-Process { throw [UnauthorizedAccessException]::new("denied") } `
      -ModuleName WindowsOrchestrator
    Mock Invoke-WindowsComponentEntrypoint {} `
      -ModuleName WindowsOrchestrator

    {
      Invoke-WindowsComponentSelection `
        -Mode Install `
        -Component "glazewm" `
        -Preflight
    } | Should -Throw "*Unable to inspect Windows processes*"
    Should -Invoke Invoke-WindowsComponentEntrypoint `
      -ModuleName WindowsOrchestrator `
      -Times 0
  }

  It "keeps PlanOnly free of runtime probes" {
    Mock Assert-WindowsRuntimeCompatibility { throw "runtime probe called" } `
      -ModuleName WindowsOrchestrator

    $plan = @(
      Invoke-WindowsComponentSelection `
        -Mode Install `
        -Component "glazewm" `
        -PlanOnly
    )

    @($plan.Name) | Should -Be @("glazewm")
    Should -Invoke Assert-WindowsRuntimeCompatibility `
      -ModuleName WindowsOrchestrator `
      -Times 0
  }

  It "rejects PlanOnly and Preflight together" {
    {
      Invoke-WindowsComponentSelection -PlanOnly -Preflight
    } | Should -Throw "*PlanOnly*Preflight*"
  }

  It "runs sequentially and stops on the first component failure" {
    Mock Invoke-WindowsComponentEntrypoint {
      if ($Component.Name -eq "kanata") {
        throw "injected failure"
      }
    } -ModuleName WindowsOrchestrator
    Mock Assert-WindowsRuntimeCompatibility {} `
      -ModuleName WindowsOrchestrator

    {
      Invoke-WindowsComponentSelection `
        -Mode Install `
        -Component @("wezterm", "kanata", "glazewm")
    } | Should -Throw "*kanata*injected failure*"
    Should -Invoke Invoke-WindowsComponentEntrypoint `
      -ModuleName WindowsOrchestrator `
      -Times 1 `
      -ParameterFilter { $Component.Name -eq "wezterm" }
    Should -Invoke Invoke-WindowsComponentEntrypoint `
      -ModuleName WindowsOrchestrator `
      -Times 1 `
      -ParameterFilter { $Component.Name -eq "kanata" }
    Should -Invoke Invoke-WindowsComponentEntrypoint `
      -ModuleName WindowsOrchestrator `
      -Times 0 `
      -ParameterFilter { $Component.Name -eq "glazewm" }
  }

  It "supports a non-mutating root plan" {
    $plan = @(
      & $rootInstallerPath `
        -Mode Install `
        -Component "glazewm" `
        -PlanOnly
    )

    @($plan.Name) | Should -Be @("glazewm")
    $plan[0].Entrypoint | Should -Be "glazewm/install.ps1"
  }

  It "accepts a scalar component CSV from native File callers" {
    $plan = @(
      & $rootInstallerPath `
        -Mode Install `
        -ComponentCsv "glazewm,kanata,wezterm" `
        -PlanOnly
    )

    @($plan.Name) | Should -Be @("wezterm", "kanata", "glazewm")
  }

  It "adds optional components to catalog-required defaults" {
    $plan = @(
      & $rootInstallerPath `
        -Mode Install `
        -AdditionalComponentCsv "glazewm" `
        -PlanOnly
    )

    @($plan.Name) | Should -Be @("wezterm", "kanata", "glazewm")
  }

  It "rejects explicit and additional component selections together" {
    {
      & $rootInstallerPath `
        -ComponentCsv "wezterm,kanata" `
        -AdditionalComponentCsv "glazewm" `
        -PlanOnly
    } | Should -Throw "*AdditionalComponentCsv*"
  }

  It "rejects malformed component CSV values" {
    foreach ($componentCsv in @(
      "",
      "wezterm, kanata",
      "wezterm,,kanata",
      "WEZTERM,kanata",
      "wezterm,kanata,"
    )) {
      {
        & $rootInstallerPath `
          -Mode Install `
          -ComponentCsv $componentCsv `
          -PlanOnly
      } | Should -Throw "*ComponentCsv*"
    }
  }

  It "rejects Component and ComponentCsv together" {
    {
      & $rootInstallerPath `
        -Mode Install `
        -Component "wezterm" `
        -ComponentCsv "wezterm,kanata" `
        -PlanOnly
    } | Should -Throw "*Component*ComponentCsv*"
  }

  It "rejects an ineffective Defender exclusion in PlanOnly mode" {
    {
      & $rootInstallerPath `
        -Mode Install `
        -Component "glazewm" `
        -AddKanataDefenderExclusion `
        -PlanOnly
    } | Should -Throw "*requires Kanata*"
  }

  It "delegates the root CLI to the fixed-root execution boundary" {
    $installerSource = Get-Content -LiteralPath $rootInstallerPath -Raw

    $installerSource | Should -Match (
      'Invoke-WindowsComponentSelection\s+@invokeParameters'
    )
  }
}
