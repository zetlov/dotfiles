Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-SurfaceInternalDisplay {
  [CmdletBinding()]
  param([Parameter(Mandatory = $true)][object[]]$Displays)

  $internal = @($Displays | Where-Object {
    $_.PSObject.Properties.Name -contains "IsInternal" -and
    [bool]$_.IsInternal
  })
  if ($internal.Count -ne 1) {
    throw "Windows did not report exactly one internal display."
  }
  return $internal[0]
}

function Initialize-SurfaceDisplayConfigInterop {
  if ("SurfaceDisplayConfig.NativeMethods" -as [type]) {
    return
  }

  Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;

namespace SurfaceDisplayConfig {
  [StructLayout(LayoutKind.Sequential)]
  public struct Luid { public uint LowPart; public int HighPart; }

  [StructLayout(LayoutKind.Sequential)]
  public struct PathSourceInfo {
    public Luid adapterId; public uint id; public uint modeInfoIdx;
    public uint statusFlags;
  }

  [StructLayout(LayoutKind.Sequential)]
  public struct Rational { public uint Numerator; public uint Denominator; }

  [StructLayout(LayoutKind.Sequential)]
  public struct PathTargetInfo {
    public Luid adapterId; public uint id; public uint modeInfoIdx;
    public uint outputTechnology; public uint rotation; public uint scaling;
    public Rational refreshRate; public uint scanLineOrdering;
    [MarshalAs(UnmanagedType.Bool)] public bool targetAvailable;
    public uint statusFlags;
  }

  [StructLayout(LayoutKind.Sequential)]
  public struct PathInfo {
    public PathSourceInfo sourceInfo; public PathTargetInfo targetInfo;
    public uint flags;
  }

  [StructLayout(LayoutKind.Explicit, Size = 56)]
  public struct ModeInfoUnion { }

  [StructLayout(LayoutKind.Sequential)]
  public struct ModeInfo {
    public uint infoType; public uint id; public Luid adapterId;
    public ModeInfoUnion modeInfo;
  }

  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
  public struct SourceDeviceName {
    public uint type; public uint size; public Luid adapterId; public uint id;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
    public string viewGdiDeviceName;
  }

  public sealed class Target {
    public string DeviceName { get; set; }
    public string DevicePath { get; set; }
    public uint OutputTechnology { get; set; }
  }

  public static class NativeMethods {
    const uint QDC_ONLY_ACTIVE_PATHS = 2;
    const uint GET_SOURCE_NAME = 1;

    [DllImport("user32.dll")]
    static extern int GetDisplayConfigBufferSizes(
      uint flags, out uint pathCount, out uint modeCount);

    [DllImport("user32.dll")]
    static extern int QueryDisplayConfig(
      uint flags, ref uint pathCount, [Out] PathInfo[] paths,
      ref uint modeCount, [Out] ModeInfo[] modes, IntPtr topologyId);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    static extern int DisplayConfigGetDeviceInfo(ref SourceDeviceName request);

    static string AdapterKey(Luid luid) {
      return luid.HighPart.ToString("X8") + luid.LowPart.ToString("X8");
    }

    public static Target[] GetActiveTargets() {
      uint pathCount, modeCount;
      int error = GetDisplayConfigBufferSizes(
        QDC_ONLY_ACTIVE_PATHS, out pathCount, out modeCount);
      if (error != 0) throw new Win32Exception(error);

      var paths = new PathInfo[pathCount];
      var modes = new ModeInfo[modeCount];
      error = QueryDisplayConfig(
        QDC_ONLY_ACTIVE_PATHS, ref pathCount, paths,
        ref modeCount, modes, IntPtr.Zero);
      if (error != 0) throw new Win32Exception(error);

      var result = new List<Target>();
      for (int index = 0; index < pathCount; index++) {
        var source = new SourceDeviceName();
        source.type = GET_SOURCE_NAME;
        source.size = (uint)Marshal.SizeOf(typeof(SourceDeviceName));
        source.adapterId = paths[index].sourceInfo.adapterId;
        source.id = paths[index].sourceInfo.id;
        error = DisplayConfigGetDeviceInfo(ref source);
        if (error != 0) throw new Win32Exception(error);

        result.Add(new Target {
          DeviceName = source.viewGdiDeviceName,
          DevicePath = AdapterKey(paths[index].targetInfo.adapterId) + ":" +
            paths[index].targetInfo.id.ToString(),
          OutputTechnology = paths[index].targetInfo.outputTechnology,
        });
      }
      return result.ToArray();
    }
  }
}
'@
}

function Get-SurfaceActiveDisplays {
  [CmdletBinding()]
  param()

  Initialize-SurfaceDisplayConfigInterop
  Add-Type -AssemblyName System.Windows.Forms
  $screens = @{}
  foreach ($screen in [System.Windows.Forms.Screen]::AllScreens) {
    $screens[[string]$screen.DeviceName] = $screen
  }

  $internalTechnologies = @(
    [Convert]::ToUInt32("80000000", 16), # Internal.
    [uint32]11,         # Embedded DisplayPort.
    [uint32]13,         # Embedded UDI.
    [uint32]17          # Display Serial Interface.
  )
  return @(
    [SurfaceDisplayConfig.NativeMethods]::GetActiveTargets() |
      ForEach-Object {
        $screen = $screens[[string]$_.DeviceName]
        if ($null -eq $screen) {
          throw "DisplayConfig returned an unknown GDI display name."
        }
        [pscustomobject]@{
          DeviceName = [string]$_.DeviceName
          DevicePath = [string]$_.DevicePath
          IsInternal = [uint32]$_.OutputTechnology -in $internalTechnologies
          X = [int]$screen.Bounds.X
          Y = [int]$screen.Bounds.Y
          Width = [int]$screen.Bounds.Width
          Height = [int]$screen.Bounds.Height
        }
      }
  )
}

function Get-GlazeSurfaceWorkspaces {
  param([Parameter(Mandatory = $true)][object]$Container)
  if (
    $Container.PSObject.Properties.Name -contains "type" -and
    [string]$Container.type -eq "workspace"
  ) {
    $Container
    return
  }
  if ($Container.PSObject.Properties.Name -notcontains "children") { return }
  foreach ($child in @($Container.children)) {
    if ($null -ne $child) { Get-GlazeSurfaceWorkspaces -Container $child }
  }
}

function Get-GlazeSurfaceMonitorBounds {
  param([Parameter(Mandatory = $true)][object]$Monitor)

  $source = if (
    $Monitor.PSObject.Properties.Name -contains "rect" -and
    $null -ne $Monitor.rect
  ) { $Monitor.rect } else { $Monitor }
  foreach ($name in @("x", "y")) {
    if ($source.PSObject.Properties.Name -notcontains $name) {
      throw "GlazeWM monitor is missing its $name coordinate."
    }
  }
  return [pscustomobject]@{
    X = [int]$source.x
    Y = [int]$source.y
  }
}

function Get-GlazeSurfaceOrderedMonitors {
  param([Parameter(Mandatory = $true)][object[]]$Monitors)

  if ($Monitors.Count -lt 1) {
    throw "GlazeWM returned no active monitors."
  }
  return @($Monitors | Sort-Object `
    @{ Expression = { (Get-GlazeSurfaceMonitorBounds $_).X } }, `
    @{ Expression = { (Get-GlazeSurfaceMonitorBounds $_).Y } })
}

function Get-GlazeSurfaceWorkspaceBindingPlan {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][object[]]$Monitors,
    [Parameter(Mandatory = $true)][string]$InternalDeviceName
  )

  $ordered = @(Get-GlazeSurfaceOrderedMonitors -Monitors $Monitors)
  $internalIndexes = @(for ($index = 0; $index -lt $ordered.Count; $index++) {
    if (
      $ordered[$index].PSObject.Properties.Name -contains "deviceName" -and
      ([string]$ordered[$index].deviceName).Equals(
        $InternalDeviceName, [StringComparison]::OrdinalIgnoreCase)
    ) { $index }
  })
  if ($internalIndexes.Count -ne 1) {
    throw "The internal display did not match exactly one GlazeWM monitor."
  }
  $externalIndexes = @(0..($ordered.Count - 1) | Where-Object {
    $_ -ne $internalIndexes[0]
  })
  if ($externalIndexes.Count -gt 1) {
    throw "Surface profile does not support more than one external display."
  }

  foreach ($name in 1..5) {
    [pscustomobject]@{
      WorkspaceName = [string]$name
      MonitorIndex = [int]$internalIndexes[0]
    }
  }
  if ($externalIndexes.Count -eq 1) {
    [pscustomobject]@{ WorkspaceName = "6"; MonitorIndex = $externalIndexes[0] }
  }
}

function New-SurfaceDisplayDebounceState {
  [pscustomobject]@{ Pending = $false; LastChangeMilliseconds = [long]0 }
}

function Update-SurfaceDisplayDebounceState {
  param(
    [Parameter(Mandatory = $true)][object]$State,
    [Parameter(Mandatory = $true)][long]$NowMilliseconds
  )
  [pscustomobject]@{ Pending = $true; LastChangeMilliseconds = $NowMilliseconds }
}

function Test-SurfaceDisplayDebounceReady {
  param(
    [Parameter(Mandatory = $true)][object]$State,
    [Parameter(Mandatory = $true)][long]$NowMilliseconds,
    [ValidateRange(1, 10000)][int]$QuietPeriodMilliseconds = 1500
  )
  return (
    [bool]$State.Pending -and
    $NowMilliseconds - [long]$State.LastChangeMilliseconds -ge
      $QuietPeriodMilliseconds
  )
}

function Invoke-GlazeSurfaceCli {
  param(
    [Parameter(Mandatory = $true)][string]$GlazeWMPath,
    [Parameter(Mandatory = $true)][string[]]$Arguments
  )
  $raw = (& $GlazeWMPath @Arguments 2>&1 | Out-String).Trim()
  if ($LASTEXITCODE -ne 0) { throw "GlazeWM command failed: $raw" }
  $response = $raw | ConvertFrom-Json -ErrorAction Stop
  if (
    $response.PSObject.Properties.Name -notcontains "success" -or
    -not [bool]$response.success
  ) {
    throw "GlazeWM rejected a Surface display command."
  }
  return $response
}

function Get-GlazeSurfaceMonitors {
  param([Parameter(Mandatory = $true)][string]$GlazeWMPath)
  $response = Invoke-GlazeSurfaceCli `
    -GlazeWMPath $GlazeWMPath `
    -Arguments @("query", "monitors")
  $monitors = if (
    $response.PSObject.Properties.Name -contains "data" -and
    $response.data.PSObject.Properties.Name -contains "monitors"
  ) { @($response.data.monitors) } else { @($response.monitors) }
  if ($monitors.Count -lt 1) { throw "GlazeWM returned no active monitors." }
  return @(Get-GlazeSurfaceOrderedMonitors -Monitors $monitors)
}

function Get-GlazeSurfaceFocusedWorkspaceName {
  param([Parameter(Mandatory = $true)][object[]]$Monitors)
  $focused = @(
    foreach ($monitor in $Monitors) {
      Get-GlazeSurfaceWorkspaces -Container $monitor | Where-Object {
        $_.PSObject.Properties.Name -contains "hasFocus" -and
        [bool]$_.hasFocus
      }
    }
  )
  if ($focused.Count -ne 1) {
    throw "GlazeWM did not report exactly one focused workspace."
  }
  return [string]$focused[0].name
}

function Ensure-GlazeSurfaceWorkspaces {
  param(
    [Parameter(Mandatory = $true)][string]$GlazeWMPath,
    [Parameter(Mandatory = $true)][object[]]$Monitors,
    [Parameter(Mandatory = $true)][bool]$HasExternalDisplay
  )
  $current = @($Monitors)
  $required = @(1..5 | ForEach-Object { [string]$_ })
  if ($HasExternalDisplay) { $required += "6" }
  foreach ($name in $required) {
    $exists = @(
      foreach ($monitor in $current) {
        Get-GlazeSurfaceWorkspaces -Container $monitor |
          Where-Object { [string]$_.name -eq $name }
      }
    ).Count -eq 1
    if (-not $exists) {
      Invoke-GlazeSurfaceCli -GlazeWMPath $GlazeWMPath `
        -Arguments @("command", "focus", "--workspace", $name) | Out-Null
      $current = @(Get-GlazeSurfaceMonitors -GlazeWMPath $GlazeWMPath)
    }
  }
  return $current
}

function Repair-SurfaceZebarAppBar {
  param([Parameter(Mandatory = $true)][object]$InternalDisplay)

  $bars = @(
    Get-Process -Name "zebar" -ErrorAction SilentlyContinue |
      Where-Object {
        $_.MainWindowTitle -eq "Zebar - zetshell / surface-bar"
      }
  )
  if ($bars.Count -eq 0) { return $false }
  if ($bars.Count -ne 1) {
    throw "Windows reported multiple managed Surface bars."
  }
  if (-not $bars[0].Responding) {
    throw "The managed Surface bar is not responding."
  }
  $monitorSyncModule = Join-Path $PSScriptRoot "GlazeWMMonitorSync.psm1"
  Import-Module $monitorSyncModule -Force -ErrorAction Stop
  Invoke-ZebarAppBarPositionRefresh `
    -Bar $bars[0] `
    -ExpectedReservedTop 42 `
    -ExpectedMonitorBounds $InternalDisplay | Out-Null
  return $true
}

function Invoke-GlazeSurfaceWorkspaceSync {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$GlazeWMPath,
    [object[]]$Displays = @()
  )
  $activeDisplays = if ($Displays.Count -gt 0) {
    @($Displays)
  } else {
    @(Get-SurfaceActiveDisplays)
  }
  $internal = Get-SurfaceInternalDisplay -Displays $activeDisplays
  $externalCount = @($activeDisplays | Where-Object { -not [bool]$_.IsInternal }).Count
  if ($externalCount -gt 1) {
    throw "Surface profile does not support more than one external display."
  }

  $mutex = [Threading.Mutex]::new($false, "Local\DotfilesGlazeSurfaceSync")
  $acquired = $false
  try {
    $acquired = $mutex.WaitOne([TimeSpan]::FromSeconds(30))
    if (-not $acquired) { throw "Timed out waiting for Surface display sync." }
    $monitors = @(Get-GlazeSurfaceMonitors -GlazeWMPath $GlazeWMPath)
    if ($monitors.Count -ne $activeDisplays.Count) {
      throw "Windows and GlazeWM display topologies have not converged."
    }
    $focused = $null
    try {
      $focused = Get-GlazeSurfaceFocusedWorkspaceName -Monitors $monitors
      $monitors = @(Ensure-GlazeSurfaceWorkspaces `
        -GlazeWMPath $GlazeWMPath `
        -Monitors $monitors `
        -HasExternalDisplay ($externalCount -eq 1))
      $plan = @(Get-GlazeSurfaceWorkspaceBindingPlan `
        -Monitors $monitors `
        -InternalDeviceName ([string]$internal.DeviceName))
      foreach ($binding in $plan) {
        Invoke-GlazeSurfaceCli -GlazeWMPath $GlazeWMPath -Arguments @(
          "command", "update-workspace-config",
          "--workspace", $binding.WorkspaceName,
          "--bind-to-monitor", [string]$binding.MonitorIndex
        ) | Out-Null
      }

      $monitors = @(Get-GlazeSurfaceMonitors -GlazeWMPath $GlazeWMPath)
      foreach ($binding in $plan) {
        $sourceIndex = -1
        for ($index = 0; $index -lt $monitors.Count; $index++) {
          if (@(Get-GlazeSurfaceWorkspaces -Container $monitors[$index] |
            Where-Object {
              [string]$_.name -eq $binding.WorkspaceName
            }).Count -eq 1) {
            $sourceIndex = $index
            break
          }
        }
        if ($sourceIndex -lt 0 -or $sourceIndex -eq $binding.MonitorIndex) {
          continue
        }
        Invoke-GlazeSurfaceCli -GlazeWMPath $GlazeWMPath `
          -Arguments @("command", "focus", "--workspace", $binding.WorkspaceName) |
          Out-Null
        $direction = if ($binding.MonitorIndex -lt $sourceIndex) {
          "left"
        } else { "right" }
        Invoke-GlazeSurfaceCli -GlazeWMPath $GlazeWMPath `
          -Arguments @("command", "move-workspace", "--direction", $direction) |
          Out-Null
      }
      $appBarRefreshed = Repair-SurfaceZebarAppBar -InternalDisplay $internal
      return [pscustomobject]@{
        InternalDeviceName = [string]$internal.DeviceName
        ExternalDisplayCount = $externalCount
        BindingCount = $plan.Count
        AppBarRefreshed = $appBarRefreshed
      }
    } finally {
      if ($null -ne $focused) {
        try {
          Invoke-GlazeSurfaceCli -GlazeWMPath $GlazeWMPath `
            -Arguments @("command", "focus", "--workspace", $focused) |
            Out-Null
        } catch {
          Write-Warning (
            "Surface display sync could not restore workspace focus: " +
            $_.Exception.Message
          )
        }
      }
    }
  } finally {
    if ($acquired) { [void]$mutex.ReleaseMutex() }
    $mutex.Dispose()
  }
}

Export-ModuleMember -Function @(
  "Get-SurfaceInternalDisplay",
  "Get-SurfaceActiveDisplays",
  "Get-GlazeSurfaceWorkspaceBindingPlan",
  "Invoke-GlazeSurfaceWorkspaceSync",
  "Repair-SurfaceZebarAppBar",
  "New-SurfaceDisplayDebounceState",
  "Update-SurfaceDisplayDebounceState",
  "Test-SurfaceDisplayDebounceReady"
)
