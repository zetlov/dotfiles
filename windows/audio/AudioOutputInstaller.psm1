Set-StrictMode -Version Latest

function Install-AudioDeviceModule {
  param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern("^\d+\.\d+\.\d+\.\d+$")]
    [string]$RequiredVersion
  )

  $installed = Get-Module -ListAvailable -Name "AudioDeviceCmdlets" |
    Where-Object {
      $null -ne $_ -and
        $null -ne $_.PSObject.Properties["Version"] -and
        $_.Version.ToString() -eq $RequiredVersion
    } |
    Select-Object -First 1
  if ($installed) {
    return $false
  }

  $nugetProvider = Get-PackageProvider -Name "NuGet" -ErrorAction SilentlyContinue
  if (-not $nugetProvider) {
    Install-PackageProvider -Name "NuGet" -Scope "CurrentUser" -Force |
      Out-Null
  }

  Install-Module `
    -Name "AudioDeviceCmdlets" `
    -RequiredVersion $RequiredVersion `
    -Repository "PSGallery" `
    -Scope "CurrentUser" `
    -Force `
    -AllowClobber `
    -ErrorAction Stop

  $installed = Get-Module -ListAvailable -Name "AudioDeviceCmdlets" |
    Where-Object {
      $null -ne $_ -and
        $null -ne $_.PSObject.Properties["Version"] -and
        $_.Version.ToString() -eq $RequiredVersion
    } |
    Select-Object -First 1
  if (-not $installed) {
    throw "AudioDeviceCmdlets $RequiredVersion was not installed."
  }

  return $true
}

Export-ModuleMember -Function Install-AudioDeviceModule
