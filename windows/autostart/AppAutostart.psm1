Set-StrictMode -Version Latest

$script:TaskNamePrefix = "Dotfiles App - "

function Get-AppAutostartTaskName {
  param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern("^[A-Za-z0-9][A-Za-z0-9 ._-]{0,63}$")]
    [string]$Name
  )

  return "$($script:TaskNamePrefix)$Name"
}

function Read-AppAutostartConfig {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "Autostart config does not exist: $Path"
  }

  try {
    $config = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
  } catch {
    throw "Autostart config is not valid JSON: $Path"
  }

  if ($config.version -ne 1) {
    throw "Unsupported autostart config version: $($config.version)"
  }
  if (@($config.apps).Count -eq 0) {
    throw "Autostart config must define at least one app."
  }

  $seenNames = @{}
  foreach ($app in @($config.apps)) {
    $null = Get-AppAutostartTaskName -Name $app.name
    if ($seenNames.ContainsKey($app.name)) {
      throw "Duplicate autostart app name: $($app.name)"
    }
    $seenNames[$app.name] = $true

    if ($app.workspace -lt 1 -or $app.workspace -gt 99) {
      throw "Invalid workspace for $($app.name): $($app.workspace)"
    }
    if ($app.delay_seconds -lt 0 -or $app.delay_seconds -gt 300) {
      throw "Invalid startup delay for $($app.name): $($app.delay_seconds)"
    }
    if ($app.launch_type -notin @("executable", "appx")) {
      throw "Unsupported launch type for $($app.name): $($app.launch_type)"
    }

    if ($app.launch_type -eq "executable") {
      if (@($app.path_candidates).Count -eq 0) {
        throw "Executable app has no path candidates: $($app.name)"
      }
      if ($null -eq $app.PSObject.Properties["arguments"]) {
        throw "Executable app has no arguments property: $($app.name)"
      }
    } elseif ($app.app_id -notmatch "^[A-Za-z0-9._-]+![A-Za-z0-9._-]+$") {
      throw "Invalid AppUserModelID for $($app.name): $($app.app_id)"
    }
  }

  return $config
}

function Resolve-AppAutostartAction {
  param(
    [Parameter(Mandatory = $true)]
    [object]$App
  )

  if ($App.launch_type -eq "appx") {
    $explorerPath = Join-Path $env:WINDIR "explorer.exe"
    if (-not (Test-Path -LiteralPath $explorerPath -PathType Leaf)) {
      throw "Windows Explorer does not exist: $explorerPath"
    }
    return [pscustomobject]@{
      Execute = $explorerPath
      Arguments = "shell:AppsFolder\$($App.app_id)"
      WorkingDirectory = $null
    }
  }

  foreach ($candidate in @($App.path_candidates)) {
    $expandedPath = [Environment]::ExpandEnvironmentVariables($candidate)
    if (-not [System.IO.Path]::IsPathRooted($expandedPath)) {
      throw "Autostart executable path must be absolute: $candidate"
    }
    if (Test-Path -LiteralPath $expandedPath -PathType Leaf) {
      return [pscustomobject]@{
        Execute = [System.IO.Path]::GetFullPath($expandedPath)
        Arguments = [string]$App.arguments
        WorkingDirectory = Split-Path -Parent $expandedPath
      }
    }
  }

  throw "No installed executable found for $($App.name)."
}

function Install-AppAutostartTasks {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ConfigPath
  )

  $config = Read-AppAutostartConfig -Path $ConfigPath
  $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
  if ([string]::IsNullOrWhiteSpace($currentUser)) {
    throw "Cannot determine the current Windows user."
  }

  $definitions = @(
    foreach ($app in @($config.apps)) {
      [pscustomobject]@{
        App = $app
        TaskName = Get-AppAutostartTaskName -Name $app.name
        Action = Resolve-AppAutostartAction -App $app
      }
    }
  )

  $desiredTaskNames = @{}
  foreach ($definition in $definitions) {
    $desiredTaskNames[$definition.TaskName] = $true
    Register-AppAutostartTask `
      -App $definition.App `
      -TaskName $definition.TaskName `
      -ResolvedAction $definition.Action `
      -CurrentUser $currentUser
  }

  Remove-StaleAppAutostartTasks -DesiredTaskNames $desiredTaskNames
}

function Register-AppAutostartTask {
  param(
    [Parameter(Mandatory = $true)]
    [object]$App,

    [Parameter(Mandatory = $true)]
    [string]$TaskName,

    [Parameter(Mandatory = $true)]
    [object]$ResolvedAction,

    [Parameter(Mandatory = $true)]
    [string]$CurrentUser
  )

    $actionParameters = @{
      Execute = $ResolvedAction.Execute
    }
    if (-not [string]::IsNullOrWhiteSpace($ResolvedAction.Arguments)) {
      $actionParameters.Argument = $ResolvedAction.Arguments
    }
    if (-not [string]::IsNullOrWhiteSpace($ResolvedAction.WorkingDirectory)) {
      $actionParameters.WorkingDirectory = $ResolvedAction.WorkingDirectory
    }
    $action = New-ScheduledTaskAction @actionParameters

    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $CurrentUser
    if ($App.delay_seconds -gt 0) {
      $trigger.Delay = "PT$($App.delay_seconds)S"
    }

    $principal = New-ScheduledTaskPrincipal `
      -UserId $CurrentUser `
      -LogonType Interactive `
      -RunLevel Limited
    $settings = New-ScheduledTaskSettingsSet `
      -MultipleInstances IgnoreNew `
      -StartWhenAvailable

    Register-ScheduledTask `
      -TaskName $taskName `
      -Action $action `
      -Trigger $trigger `
      -Principal $principal `
      -Settings $settings `
      -Description "Managed by the dotfiles Windows app autostart installer." `
      -Force | Out-Null
}

function Remove-StaleAppAutostartTasks {
  param(
    [Parameter(Mandatory = $true)]
    [hashtable]$DesiredTaskNames
  )

  Get-ScheduledTask -TaskPath "\" |
    Where-Object {
      $_.TaskName.StartsWith(
        $script:TaskNamePrefix,
        [System.StringComparison]::Ordinal
      ) -and -not $DesiredTaskNames.ContainsKey($_.TaskName)
    } |
    ForEach-Object {
      Unregister-ScheduledTask `
        -TaskName $_.TaskName `
        -TaskPath $_.TaskPath `
        -Confirm:$false
    }
}

function Uninstall-AppAutostartTasks {
  Get-ScheduledTask -TaskPath "\" |
    Where-Object {
      $_.TaskName.StartsWith(
        $script:TaskNamePrefix,
        [System.StringComparison]::Ordinal
      )
    } |
    ForEach-Object {
      Unregister-ScheduledTask `
        -TaskName $_.TaskName `
        -TaskPath $_.TaskPath `
        -Confirm:$false
    }
}

Export-ModuleMember -Function @(
  "Get-AppAutostartTaskName",
  "Read-AppAutostartConfig",
  "Resolve-AppAutostartAction",
  "Install-AppAutostartTasks",
  "Uninstall-AppAutostartTasks"
)
