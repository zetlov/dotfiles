function Get-WindowsProcessMatches {
  param([Parameter(Mandatory = $true)][string[]]$Name)

  try {
    $processes = @(Get-Process -ErrorAction Stop)
  } catch {
    throw "Unable to inspect Windows processes: $($_.Exception.Message)"
  }
  return @(
    $processes | Where-Object { $Name -contains $_.ProcessName }
  )
}

function Test-WindowsRunValue {
  param([Parameter(Mandatory = $true)][string]$Name)

  $runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
  try {
    $state = Get-ItemProperty -LiteralPath $runKey -ErrorAction Stop
  } catch [System.Management.Automation.ItemNotFoundException] {
    return $false
  } catch {
    throw "Unable to inspect Windows Run registrations: $($_.Exception.Message)"
  }
  return $null -ne $state.PSObject.Properties[$Name]
}

function Test-KomorebiStartupShortcut {
  $startupShortcut = Join-Path `
    ([Environment]::GetFolderPath("Startup")) `
    "komorebi.lnk"
  return Test-Path -LiteralPath $startupShortcut -PathType Leaf
}

function Get-RollbackAutostartTasks {
  if ($null -eq (Get-Command -Name "Get-ScheduledTask" -ErrorAction SilentlyContinue)) {
    throw "Get-ScheduledTask is required for Windows runtime preflight."
  }
  try {
    $allTasks = @(Get-ScheduledTask -ErrorAction Stop)
  } catch {
    throw "Unable to inspect scheduled tasks: $($_.Exception.Message)"
  }
  return @(
    $allTasks | Where-Object { $_.TaskName -like "Dotfiles App - *" }
  )
}

function Assert-WindowsRuntimeCompatibility {
  param(
    [Parameter(Mandatory = $true)][object[]]$Plan,
    [Parameter(Mandatory = $true)][object[]]$Catalog
  )

  $selectedNames = @($Plan | ForEach-Object { $_.Name })
  $catalogByName = @{}
  foreach ($item in $Catalog) {
    $catalogByName[[string]$item.Name] = $item
  }
  $selectsRollback = @(
    $selectedNames |
      Where-Object { $catalogByName[[string]$_].Lifecycle -eq "rollback-only" }
  ).Count -gt 0
  if ($selectsRollback) {
    $glazeProcesses = @(Get-WindowsProcessMatches -Name @("glazewm"))
    if ($glazeProcesses.Count -gt 0) {
      throw "GlazeWM is running; stop it before applying rollback components."
    }
    if (Test-WindowsRunValue -Name "GlazeWM") {
      throw (
        "GlazeWM automatic startup is enabled; disable it before applying " +
        "rollback components."
      )
    }
  }

  if ($selectedNames -contains "glazewm") {
    $komorebiProcesses = @(Get-WindowsProcessMatches `
      -Name @("komorebi", "whkd", "komorebi-bar", "masir"))
    if ($komorebiProcesses.Count -gt 0) {
      throw "Komorebi rollback processes are running; stop them first."
    }

    if (Test-KomorebiStartupShortcut) {
      throw "Komorebi automatic startup is enabled."
    }

    $rollbackTasks = @(Get-RollbackAutostartTasks)
    if ($rollbackTasks.Count -gt 0) {
      throw "Rollback-only app autostart tasks are still registered."
    }
  }
}
