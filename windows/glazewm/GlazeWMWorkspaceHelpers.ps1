function Get-GlazeWindowsInContainer {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [object]$Container
  )

  if (
    $Container.PSObject.Properties.Name -contains "type" -and
    [string]$Container.type -eq "window"
  ) {
    $Container
    return
  }
  if (-not ($Container.PSObject.Properties.Name -contains "children")) {
    return
  }
  foreach ($child in @($Container.children)) {
    if ($null -ne $child) {
      Get-GlazeWindowsInContainer -Container $child
    }
  }
}

function Get-GlazeWorkspaceByName {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [AllowEmptyCollection()]
    [object[]]$Workspaces,

    [Parameter(Mandatory = $true)]
    [string]$WorkspaceName
  )

  return $Workspaces | Where-Object {
    $null -ne $_ -and
    $_.PSObject.Properties.Name -contains "name" -and
    [string]$_.name -eq $WorkspaceName
  } | Select-Object -First 1
}

function Invoke-GlazeWMIPC {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string]$GlazeWMPath,

    [Parameter(Mandatory = $true)]
    [string[]]$Arguments,

    [scriptblock]$CommandInvoker
  )

  if ($null -ne $CommandInvoker) {
    return & $CommandInvoker ([pscustomobject]@{
      Path = $GlazeWMPath
      Arguments = @($Arguments)
    })
  }

  $output = @(& $GlazeWMPath @Arguments 2>$null)
  return [pscustomobject]@{
    Output = $output
    ExitCode = $LASTEXITCODE
  }
}
