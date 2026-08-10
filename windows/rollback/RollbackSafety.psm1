Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Assert-GlazeWMInactive {
  [CmdletBinding()]
  param()

  try {
    $glazeProcesses = @(
      Get-Process -ErrorAction Stop |
        Where-Object { $_.ProcessName -ieq "glazewm" }
    )
  } catch {
    throw "Unable to inspect GlazeWM processes: $($_.Exception.Message)"
  }
  if ($glazeProcesses.Count -gt 0) {
    throw "GlazeWM is running; stop it before applying rollback components."
  }

  $runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
  try {
    $runState = Get-ItemProperty -LiteralPath $runKey -ErrorAction Stop
    $hasGlazeWMRunRegistration = (
      $null -ne $runState.PSObject.Properties["GlazeWM"]
    )
  } catch [System.Management.Automation.ItemNotFoundException] {
    return
  } catch {
    throw "Unable to inspect Windows Run registrations: $($_.Exception.Message)"
  }
  if ($hasGlazeWMRunRegistration) {
    throw (
      "GlazeWM automatic startup is enabled; disable it before applying " +
      "rollback components."
    )
  }
}

function Assert-KomorebiInactive {
  [CmdletBinding()]
  param()

  $rollbackProcessNames = @("komorebi", "whkd", "komorebi-bar", "masir")
  try {
    $rollbackProcesses = @(
      Get-Process -ErrorAction Stop |
        Where-Object { $rollbackProcessNames -contains $_.ProcessName }
    )
  } catch {
    throw "Unable to inspect Komorebi processes: $($_.Exception.Message)"
  }
  if ($rollbackProcesses.Count -gt 0) {
    throw "Komorebi rollback processes are running; stop them first."
  }

  try {
    $startupDirectory = [Environment]::GetFolderPath("Startup")
    if ([string]::IsNullOrWhiteSpace($startupDirectory)) {
      throw "The current user's Startup directory is unavailable."
    }
    $startupShortcut = Join-Path $startupDirectory "komorebi.lnk"
    $hasStartupShortcut = Test-Path `
      -LiteralPath $startupShortcut `
      -PathType Leaf `
      -ErrorAction Stop
  } catch {
    throw "Unable to inspect Komorebi automatic startup: $($_.Exception.Message)"
  }
  if ($hasStartupShortcut) {
    throw "Komorebi automatic startup is enabled."
  }

  try {
    $rollbackTasks = @(
      Get-ScheduledTask -ErrorAction Stop |
        Where-Object { $_.TaskName -like "Dotfiles App - *" }
    )
  } catch {
    throw "Unable to inspect rollback scheduled tasks: $($_.Exception.Message)"
  }
  if ($rollbackTasks.Count -gt 0) {
    throw "Rollback-only app scheduled tasks are still registered."
  }
}

Export-ModuleMember -Function @(
  "Assert-GlazeWMInactive",
  "Assert-KomorebiInactive"
)
