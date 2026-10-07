Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Test-GlazeMonitorExpansion {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [ValidateRange(1, 3)]
    [int]$CurrentMonitorCount,

    [Parameter(Mandatory = $true)]
    [ValidateSet("all", "left-center", "right-only")]
    [string]$ProfileName
  )

  $targetCount = switch ($ProfileName) {
    "all" { 3; break }
    "left-center" { 2; break }
    "right-only" { 1; break }
  }
  return $CurrentMonitorCount -eq 1 -and $targetCount -gt 1
}

function Get-GlazeWorkspacesInTree {
  param([Parameter(Mandatory = $true)][object]$Container)

  if (
    $Container.PSObject.Properties.Name -contains "type" -and
    [string]$Container.type -eq "workspace"
  ) {
    $Container
    return
  }
  if ($Container.PSObject.Properties.Name -notcontains "children") {
    return
  }
  foreach ($child in @($Container.children)) {
    if ($null -ne $child) {
      Get-GlazeWorkspacesInTree -Container $child
    }
  }
}

function Get-GlazeWindowsInTree {
  param([Parameter(Mandatory = $true)][object]$Container)

  if (
    $Container.PSObject.Properties.Name -contains "type" -and
    [string]$Container.type -eq "window"
  ) {
    $Container
    return
  }
  if ($Container.PSObject.Properties.Name -notcontains "children") {
    return
  }
  foreach ($child in @($Container.children)) {
    if ($null -ne $child) {
      Get-GlazeWindowsInTree -Container $child
    }
  }
}

function ConvertFrom-GlazeResponse {
  param(
    [Parameter(Mandatory = $true)][string]$Raw,
    [Parameter(Mandatory = $true)][string]$Operation
  )

  try {
    $response = $Raw | ConvertFrom-Json -ErrorAction Stop
  } catch {
    throw "GlazeWM $Operation returned invalid JSON."
  }
  if (
    $response.PSObject.Properties.Name -contains "success" -and
    -not [bool]$response.success
  ) {
    throw "GlazeWM rejected $Operation."
  }
  return $response
}

function Invoke-GlazeQuery {
  param(
    [Parameter(Mandatory = $true)][string]$GlazeWMPath,
    [Parameter(Mandatory = $true)][string]$Query
  )

  $raw = (& $GlazeWMPath query $Query 2>&1 | Out-String).Trim()
  if ($LASTEXITCODE -ne 0) {
    throw "GlazeWM $Query query failed: $raw"
  }
  return ConvertFrom-GlazeResponse -Raw $raw -Operation "$Query query"
}

function Get-GlazeResponseCollection {
  param(
    [Parameter(Mandatory = $true)][object]$Response,
    [Parameter(Mandatory = $true)][string]$Name
  )

  if (
    $Response.PSObject.Properties.Name -contains "data" -and
    $null -ne $Response.data -and
    $Response.data.PSObject.Properties.Name -contains $Name
  ) {
    return @($Response.data.$Name)
  }
  if ($Response.PSObject.Properties.Name -contains $Name) {
    return @($Response.$Name)
  }
  return @($Response)
}

function New-GlazeWindowSnapshot {
  [CmdletBinding()]
  param(
    [string]$GlazeWMPath = "",
    [object[]]$Monitors = @()
  )

  $currentMonitors = if (@($Monitors).Count -gt 0) {
    @($Monitors)
  } else {
    if ([string]::IsNullOrWhiteSpace($GlazeWMPath)) {
      throw "GlazeWMPath is required when monitors are not supplied."
    }
    $response = Invoke-GlazeQuery `
      -GlazeWMPath $GlazeWMPath `
      -Query "monitors"
    @(Get-GlazeResponseCollection -Response $response -Name "monitors")
  }

  $focusedWorkspaces = @()
  $windows = @(
    foreach ($monitor in $currentMonitors) {
      foreach ($workspace in @(Get-GlazeWorkspacesInTree $monitor)) {
        if (
          $workspace.PSObject.Properties.Name -notcontains "name" -or
          [string]::IsNullOrWhiteSpace([string]$workspace.name)
        ) {
          throw "GlazeWM returned a workspace without a name."
        }
        if (
          $workspace.PSObject.Properties.Name -contains "hasFocus" -and
          [bool]$workspace.hasFocus
        ) {
          $focusedWorkspaces += [string]$workspace.name
        }
        foreach ($window in @(Get-GlazeWindowsInTree $workspace)) {
          if (
            $window.PSObject.Properties.Name -notcontains "handle" -or
            [long]$window.handle -le 0
          ) {
            throw "GlazeWM returned a window without a valid handle."
          }
          $windowState = if (
            $window.PSObject.Properties.Name -contains "state" -and
            $null -ne $window.state
          ) {
            $window.state
          } else {
            $null
          }
          $stateType = if (
            $null -ne $windowState -and
            $windowState.PSObject.Properties.Name -contains "type"
          ) {
            [string]$windowState.type
          } else {
            "tiling"
          }
          [pscustomobject]@{
            Handle = [long]$window.handle
            WorkspaceName = [string]$workspace.name
            StateType = $stateType
            State = $windowState
            WasFocused = (
              $window.PSObject.Properties.Name -contains "hasFocus" -and
              [bool]$window.hasFocus
            )
          }
        }
      }
    }
  )

  $duplicate = @($windows | Group-Object Handle | Where-Object Count -gt 1)
  if ($duplicate.Count -gt 0) {
    throw "GlazeWM returned a duplicate window handle."
  }
  if ($focusedWorkspaces.Count -ne 1) {
    throw "GlazeWM did not report exactly one focused workspace."
  }
  return [pscustomobject]@{
    Windows = $windows
    FocusedWorkspaceName = $focusedWorkspaces[0]
  }
}

function Initialize-GlazeWindowRecoveryNativeType {
  if ($null -ne ("GlazeSafeRestart.WindowRecovery" -as [type])) {
    return
  }
  Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace GlazeSafeRestart
{
    internal enum ApplicationViewCloakType : int
    {
        None = 0,
        Default = 1,
        VirtualDesktop = 2
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct Rect
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [ComImport]
    [InterfaceType(ComInterfaceType.InterfaceIsIInspectable)]
    [Guid("372E1D3B-38D3-42E4-A15B-8AB2B178F513")]
    internal interface IApplicationView
    {
        int SetFocus();
        int SwitchTo();
        int TryInvokeBack(IntPtr callback);
        int GetThumbnailWindow(out IntPtr hwnd);
        int GetMonitor(out IntPtr monitor);
        int GetVisibility(out int visibility);
        int SetCloak(ApplicationViewCloakType cloakType, int unknown);
        int GetPosition(ref Guid guid, out IntPtr position);
        int SetPosition(ref IntPtr position);
        int InsertAfterWindow(IntPtr hwnd);
        int GetExtendedFramePosition(out Rect rect);
    }

    [ComImport]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    [Guid("1841C6D7-4F9D-42C0-AF41-8747538F10E5")]
    internal interface IApplicationViewCollection
    {
        int GetViews(out IntPtr array);
        int GetViewsByZOrder(out IntPtr array);
        int GetViewsByAppUserModelId(string id, out IntPtr array);
        int GetViewForHwnd(IntPtr hwnd, out IApplicationView view);
    }

    [ComImport]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    [Guid("6D5140C1-7436-11CE-8034-00AA006009FA")]
    internal interface IServiceProvider
    {
        [return: MarshalAs(UnmanagedType.IUnknown)]
        object QueryService(ref Guid service, ref Guid riid);
    }

    public static class WindowRecovery
    {
        private static readonly Guid ImmersiveShell =
            new Guid("C2F03A33-21F5-47FA-B4BB-156362A2F239");

        [DllImport("dwmapi.dll")]
        private static extern int DwmGetWindowAttribute(
            IntPtr hwnd, int attribute, out int value, int valueSize);

        [DllImport("user32.dll")]
        private static extern bool ShowWindowAsync(IntPtr hwnd, int command);

        public static int GetCloaked(IntPtr hwnd)
        {
            int value;
            int result = DwmGetWindowAttribute(hwnd, 14, out value, 4);
            if (result != 0)
            {
                Marshal.ThrowExceptionForHR(result);
            }
            return value;
        }

        public static void UncloakAndShow(IntPtr hwnd)
        {
            Type shellType = Type.GetTypeFromCLSID(ImmersiveShell);
            object shellObject = Activator.CreateInstance(shellType);
            IServiceProvider shell = (IServiceProvider)shellObject;
            Guid service = typeof(IApplicationViewCollection).GUID;
            object collectionObject = shell.QueryService(ref service, ref service);
            IApplicationViewCollection collection =
                (IApplicationViewCollection)collectionObject;
            IApplicationView view;
            int result = collection.GetViewForHwnd(hwnd, out view);
            if (result != 0 || view == null)
            {
                Marshal.ThrowExceptionForHR(
                    result != 0 ? result : unchecked((int)0x80004005));
            }
            result = view.SetCloak(ApplicationViewCloakType.Default, 0);
            if (result != 0)
            {
                Marshal.ThrowExceptionForHR(result);
            }
            Show(hwnd);
        }

        public static void Show(IntPtr hwnd)
        {
            ShowWindowAsync(hwnd, 9);
            ShowWindowAsync(hwnd, 5);
        }
    }
}
'@
}

function Get-GlazeWindowCloakState {
  param([Parameter(Mandatory = $true)][long]$Handle)

  Initialize-GlazeWindowRecoveryNativeType
  return [GlazeSafeRestart.WindowRecovery]::GetCloaked([IntPtr]$Handle)
}

function Set-GlazeWindowUncloaked {
  param([Parameter(Mandatory = $true)][long]$Handle)

  Initialize-GlazeWindowRecoveryNativeType
  [GlazeSafeRestart.WindowRecovery]::UncloakAndShow([IntPtr]$Handle)
}

function Assert-GlazeSnapshotWindowsUncloaked {
  param([Parameter(Mandatory = $true)][object]$Snapshot)

  foreach ($window in @($Snapshot.Windows)) {
    $handle = [long]$window.Handle
    if ((Get-GlazeWindowCloakState -Handle $handle) -ne 0) {
      Set-GlazeWindowUncloaked -Handle $handle
    }
    if ((Get-GlazeWindowCloakState -Handle $handle) -ne 0) {
      throw "Window handle $handle remains cloaked; GlazeWM will not be stopped."
    }
  }
}

function Toggle-GlazeManagerPause {
  param([Parameter(Mandatory = $true)][string]$GlazeWMPath)

  Invoke-GlazeCommand `
    -GlazeWMPath $GlazeWMPath `
    -Arguments @("command", "wm-toggle-pause")
}

function Get-GlazeManagerPaused {
  param([Parameter(Mandatory = $true)][string]$GlazeWMPath)

  $response = Invoke-GlazeQuery -GlazeWMPath $GlazeWMPath -Query "paused"
  if (
    $response.PSObject.Properties.Name -notcontains "data" -or
    $null -eq $response.data
  ) {
    throw "GlazeWM paused query returned no state."
  }
  return [bool]$response.data
}

function Resume-GlazeManagerAfterSnapshotProtection {
  param([Parameter(Mandatory = $true)][string]$GlazeWMPath)

  try {
    Toggle-GlazeManagerPause -GlazeWMPath $GlazeWMPath
    return
  } catch {
    $firstError = $_
  }

  try {
    $stillPaused = Get-GlazeManagerPaused -GlazeWMPath $GlazeWMPath
  } catch {
    if ($null -ne $firstError) {
      throw [InvalidOperationException]::new(
        "GlazeWM resume failed and its pause state could not be verified.",
        $firstError.Exception
      )
    }
    throw
  }
  if (-not $stillPaused) {
    return
  }

  Toggle-GlazeManagerPause -GlazeWMPath $GlazeWMPath
  if (Get-GlazeManagerPaused -GlazeWMPath $GlazeWMPath) {
    throw "GlazeWM remained paused after the resume retry."
  }
}

function Show-GlazeSnapshotWindows {
  param([Parameter(Mandatory = $true)][object]$Snapshot)

  Initialize-GlazeWindowRecoveryNativeType
  foreach ($window in @($Snapshot.Windows)) {
    $handle = [long]$window.Handle
    [GlazeSafeRestart.WindowRecovery]::Show([IntPtr]$handle)
  }
  Assert-GlazeSnapshotWindowsUncloaked -Snapshot $Snapshot
}

function Invoke-GlazeCommand {
  param(
    [Parameter(Mandatory = $true)][string]$GlazeWMPath,
    [Parameter(Mandatory = $true)][string[]]$Arguments
  )

  $raw = (& $GlazeWMPath @Arguments 2>&1 | Out-String).Trim()
  if ($LASTEXITCODE -ne 0) {
    throw "GlazeWM command failed: $raw"
  }
  [void](ConvertFrom-GlazeResponse -Raw $raw -Operation "command")
}

function Get-GlazeManagerProcessIds {
  param([Parameter(Mandatory = $true)][string]$ManagerPath)

  return @(
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
      Where-Object {
        $_.Name -eq "glazewm.exe" -and
        (
          [string]::IsNullOrWhiteSpace([string]$_.ExecutablePath) -or
          ([string]$_.ExecutablePath).Equals(
            $ManagerPath,
            [StringComparison]::OrdinalIgnoreCase
          )
        )
      } |
      ForEach-Object { [int]$_.ProcessId }
  )
}

function Wait-GlazeManagerProcessesExit {
  param(
    [Parameter(Mandatory = $true)][int[]]$ProcessIds,
    [ValidateRange(1, 60)][int]$TimeoutSeconds = 15
  )

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  do {
    $running = @($ProcessIds | Where-Object {
      $null -ne (Get-Process -Id $_ -ErrorAction SilentlyContinue)
    })
    if ($running.Count -eq 0) {
      return $true
    }
    Start-Sleep -Milliseconds 250
  } while ((Get-Date) -lt $deadline)
  return $false
}

function Stop-GlazeManagerSafely {
  param(
    [Parameter(Mandatory = $true)][string]$GlazeWMPath,
    [Parameter(Mandatory = $true)][string]$ManagerPath,
    [ValidateRange(1, 60)][int]$TimeoutSeconds = 15
  )

  $managerProcessIds = @(Get-GlazeManagerProcessIds `
    -ManagerPath $ManagerPath)
  Invoke-GlazeCommand `
    -GlazeWMPath $GlazeWMPath `
    -Arguments @("command", "wm-exit")
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  do {
    Start-Sleep -Milliseconds 250
    $managerActive = Test-GlazeManagerActive -GlazeWMPath $GlazeWMPath
    if (-not $managerActive) {
      if (
        $managerProcessIds.Count -eq 0 -or
        (Wait-GlazeManagerProcessesExit `
          -ProcessIds $managerProcessIds `
          -TimeoutSeconds $TimeoutSeconds)
      ) {
        return
      }
      throw "The previous GlazeWM manager process did not exit in time."
    }
  } while ((Get-Date) -lt $deadline)
  throw "GlazeWM did not exit within $TimeoutSeconds seconds."
}

function Start-GlazeManagerSafely {
  param(
    [Parameter(Mandatory = $true)][string]$ManagerPath,
    [Parameter(Mandatory = $true)][string]$ConfigPath,
    [Parameter(Mandatory = $true)][string]$StartupRuntimeRoot,
    [switch]$SkipStartupApplications
  )

  $variableName = "DOTFILES_GLAZE_SAFE_RESTART"
  $previousValue = [Environment]::GetEnvironmentVariable(
    $variableName,
    [EnvironmentVariableTarget]::Process
  )
  $markerPath = ""
  $managerStarted = $false
  try {
    if ($SkipStartupApplications) {
      $token = [guid]::NewGuid().ToString("N")
      $markerPath = Join-Path `
        $StartupRuntimeRoot `
        "safe-restart-$token.pending"
      Set-Content `
        -LiteralPath $markerPath `
        -Value $token `
        -NoNewline `
        -Encoding ASCII
      [Environment]::SetEnvironmentVariable(
        $variableName,
        $token,
        [EnvironmentVariableTarget]::Process
      )
    }
    Start-Process `
      -FilePath $ManagerPath `
      -ArgumentList @("start", "--config=`"$ConfigPath`"") `
      -WindowStyle Hidden |
      Out-Null
    $managerStarted = $true
  } finally {
    [Environment]::SetEnvironmentVariable(
      $variableName,
      $previousValue,
      [EnvironmentVariableTarget]::Process
    )
    if (
      -not $managerStarted -and
      -not [string]::IsNullOrWhiteSpace($markerPath)
    ) {
      Remove-Item -LiteralPath $markerPath -Force -ErrorAction SilentlyContinue
    }
  }
}

function Wait-GlazeManagerReady {
  param(
    [Parameter(Mandatory = $true)][string]$GlazeWMPath,
    [ValidateRange(1, 60)][int]$TimeoutSeconds = 30
  )

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  do {
    Start-Sleep -Milliseconds 250
    $managerActive = Test-GlazeManagerActive -GlazeWMPath $GlazeWMPath
    if ($managerActive) {
      return
    }
  } while ((Get-Date) -lt $deadline)
  throw "GlazeWM did not become ready within $TimeoutSeconds seconds."
}

function Test-GlazeManagerActive {
  param([Parameter(Mandatory = $true)][string]$GlazeWMPath)

  try {
    & $GlazeWMPath query app-metadata 2>$null | Out-Null
    return $LASTEXITCODE -eq 0
  } catch {
    return $false
  }
}

function Sync-GlazeMonitorTopology {
  param(
    [Parameter(Mandatory = $true)][string]$GlazeWMPath,
    [Parameter(Mandatory = $true)][string]$MonitorSyncModulePath
  )

  Import-Module $MonitorSyncModulePath -Force -ErrorAction Stop
  Invoke-GlazeWorkspaceMonitorSync -GlazeWMPath $GlazeWMPath | Out-Null
}

function Get-GlazeCurrentWindows {
  param([Parameter(Mandatory = $true)][string]$GlazeWMPath)

  $response = Invoke-GlazeQuery -GlazeWMPath $GlazeWMPath -Query "windows"
  return @(Get-GlazeResponseCollection -Response $response -Name "windows")
}

function Restore-GlazeWindowSnapshot {
  param(
    [Parameter(Mandatory = $true)][string]$GlazeWMPath,
    [Parameter(Mandatory = $true)][object]$Snapshot,
    [ValidateRange(1, 120)][int]$TimeoutSeconds = 60
  )

  $remaining = @($Snapshot.Windows)
  $current = @()
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  do {
    $current = @(Get-GlazeCurrentWindows -GlazeWMPath $GlazeWMPath)
    $currentHandles = @($current | ForEach-Object { [long]$_.handle })
    $remaining = @($Snapshot.Windows | Where-Object {
      [long]$_.Handle -notin $currentHandles
    })
    if ($remaining.Count -eq 0) {
      break
    }
    Start-Sleep -Milliseconds 250
  } while ((Get-Date) -lt $deadline)
  if ($remaining.Count -gt 0) {
    throw "GlazeWM did not register every preserved window after restart."
  }

  foreach ($saved in @($Snapshot.Windows)) {
    $window = $current | Where-Object {
      [long]$_.handle -eq [long]$saved.Handle
    } | Select-Object -First 1
    $id = [string]$window.id
    Invoke-GlazeCommand -GlazeWMPath $GlazeWMPath -Arguments @(
      "command", "--id", $id, "move", "--workspace", $saved.WorkspaceName
    )
    switch ([string]$saved.StateType) {
      "floating" {
        $shownOnTop = if (
          $null -ne $saved.State -and
          $saved.State.PSObject.Properties.Name -contains "shownOnTop"
        ) {
          ([bool]$saved.State.shownOnTop).ToString().ToLowerInvariant()
        } else {
          "false"
        }
        Invoke-GlazeCommand -GlazeWMPath $GlazeWMPath -Arguments @(
          "command", "--id", $id, "set-floating", "--centered=false",
          "--shown-on-top=$shownOnTop"
        )
      }
      "fullscreen" {
        $maximized = if (
          $null -ne $saved.State -and
          $saved.State.PSObject.Properties.Name -contains "maximized"
        ) {
          ([bool]$saved.State.maximized).ToString().ToLowerInvariant()
        } else {
          "false"
        }
        $fullscreenShownOnTop = if (
          $null -ne $saved.State -and
          $saved.State.PSObject.Properties.Name -contains "shownOnTop"
        ) {
          ([bool]$saved.State.shownOnTop).ToString().ToLowerInvariant()
        } else {
          "false"
        }
        Invoke-GlazeCommand -GlazeWMPath $GlazeWMPath -Arguments @(
          "command", "--id", $id, "set-fullscreen",
          "--maximized=$maximized",
          "--shown-on-top=$fullscreenShownOnTop"
        )
      }
      "minimized" { }
      default {
        Invoke-GlazeCommand -GlazeWMPath $GlazeWMPath -Arguments @(
          "command", "--id", $id, "set-tiling"
        )
      }
    }
  }
  foreach ($saved in @($Snapshot.Windows | Where-Object StateType -eq "minimized")) {
    $window = $current | Where-Object {
      [long]$_.handle -eq [long]$saved.Handle
    } | Select-Object -First 1
    Invoke-GlazeCommand -GlazeWMPath $GlazeWMPath -Arguments @(
      "command", "--id", [string]$window.id, "set-minimized"
    )
  }
  Invoke-GlazeCommand -GlazeWMPath $GlazeWMPath -Arguments @(
    "command", "focus", "--workspace", $Snapshot.FocusedWorkspaceName
  )
  $focused = @($Snapshot.Windows | Where-Object {
    $_.PSObject.Properties.Name -contains "WasFocused" -and
    [bool]$_.WasFocused
  })
  if ($focused.Count -gt 1) {
    throw "The GlazeWM snapshot contains multiple focused windows."
  }
  if ($focused.Count -eq 1) {
    $focusedWindow = $current | Where-Object {
      [long]$_.handle -eq [long]$focused[0].Handle
    } | Select-Object -First 1
    Invoke-GlazeCommand -GlazeWMPath $GlazeWMPath -Arguments @(
      "command", "--id", [string]$focusedWindow.id, "focus"
    )
  }
}

function Invoke-GlazeSafeMonitorExpansion {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$GlazeWMPath,
    [Parameter(Mandatory = $true)][string]$ManagerPath,
    [Parameter(Mandatory = $true)][string]$ConfigPath,
    [Parameter(Mandatory = $true)][string]$MonitorSyncModulePath,
    [Parameter(Mandatory = $true)][scriptblock]$ApplyProfile
  )

  $snapshot = New-GlazeWindowSnapshot -GlazeWMPath $GlazeWMPath
  $managerPaused = $false
  Toggle-GlazeManagerPause -GlazeWMPath $GlazeWMPath
  $managerPaused = $true
  try {
    Assert-GlazeSnapshotWindowsUncloaked -Snapshot $snapshot
  } catch {
    try {
      Resume-GlazeManagerAfterSnapshotProtection -GlazeWMPath $GlazeWMPath
      $managerPaused = $false
    } catch {
      throw [InvalidOperationException]::new(
        "Window uncloak verification failed and GlazeWM could not be resumed.",
        $_.Exception
      )
    }
    throw
  }
  Resume-GlazeManagerAfterSnapshotProtection -GlazeWMPath $GlazeWMPath
  $managerPaused = $false
  $originalManagerProcessIds = @(Get-GlazeManagerProcessIds `
    -ManagerPath $ManagerPath)
  $profileResult = $null
  $transactionError = $null
  $managerStopped = $false
  try {
    Stop-GlazeManagerSafely `
      -GlazeWMPath $GlazeWMPath `
      -ManagerPath $ManagerPath
    $managerStopped = $true
    try {
      $profileResult = & $ApplyProfile
    } catch {
      $transactionError = $_
    }
  } catch {
    $transactionError = $_
    $oldManagerExited = (
      $originalManagerProcessIds.Count -eq 0 -or
      (Wait-GlazeManagerProcessesExit `
        -ProcessIds $originalManagerProcessIds `
        -TimeoutSeconds 5)
    )
    if (
      $oldManagerExited -and
      -not (Test-GlazeManagerActive -GlazeWMPath $GlazeWMPath)
    ) {
      $managerStopped = $true
    }
  }

  if (-not $managerStopped) {
    if ($managerPaused) {
      Toggle-GlazeManagerPause -GlazeWMPath $GlazeWMPath
    }
    throw $transactionError
  }

  $recoveryErrors = [Collections.Generic.List[string]]::new()
  try {
    Show-GlazeSnapshotWindows -Snapshot $snapshot
  } catch {
    $recoveryErrors.Add($_.Exception.Message)
  }
  try {
    Start-GlazeManagerSafely `
      -ManagerPath $ManagerPath `
      -ConfigPath $ConfigPath `
      -StartupRuntimeRoot (Split-Path -Parent $MonitorSyncModulePath) `
      -SkipStartupApplications
    Wait-GlazeManagerReady -GlazeWMPath $GlazeWMPath
    Sync-GlazeMonitorTopology `
      -GlazeWMPath $GlazeWMPath `
      -MonitorSyncModulePath $MonitorSyncModulePath
    Restore-GlazeWindowSnapshot `
      -GlazeWMPath $GlazeWMPath `
      -Snapshot $snapshot
  } catch {
    $recoveryErrors.Add($_.Exception.Message)
  }

  if ($null -ne $transactionError -and $recoveryErrors.Count -gt 0) {
    throw [InvalidOperationException]::new(
      "Monitor expansion failed: $($transactionError.Exception.Message) " +
      "GlazeWM recovery also failed: $($recoveryErrors -join '; ')",
      $transactionError.Exception
    )
  }
  if ($null -ne $transactionError) {
    throw $transactionError
  }
  if ($recoveryErrors.Count -gt 0) {
    throw "GlazeWM recovery failed: $($recoveryErrors -join '; ')"
  }
  return $profileResult
}

Export-ModuleMember -Function @(
  "Test-GlazeMonitorExpansion",
  "New-GlazeWindowSnapshot",
  "Invoke-GlazeSafeMonitorExpansion"
)
