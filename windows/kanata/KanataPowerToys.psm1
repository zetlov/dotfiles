Set-StrictMode -Version Latest

function Get-KanataPowerToysKeyboardManagerProfilePath {
  return Join-Path $env:LOCALAPPDATA (
    "Microsoft\PowerToys\Keyboard Manager\default.json"
  )
}

function Get-KanataImeOffPowerToysProfileUpdate {
  param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("Add", "Remove")]
    [string]$Action,

    [Parameter(Mandatory = $true)]
    [string]$ProfileJson
  )

  try {
    $profile = $ProfileJson | ConvertFrom-Json -ErrorAction Stop
  } catch {
    throw "PowerToys Keyboard Manager profile is not valid JSON."
  }
  if (
    $null -eq $profile.remapKeys -or
    $null -eq $profile.remapKeys.PSObject.Properties["inProcess"]
  ) {
    throw "PowerToys Keyboard Manager profile is missing remapKeys.inProcess."
  }

  $entries = @($profile.remapKeys.inProcess)
  $source = "26"
  $target = "124"
  $sourceEntries = @($entries | Where-Object {
    [string]$_.originalKeys -eq $source
  })
  if ($Action -eq "Add" -and $sourceEntries.Count -gt 0) {
    $conflicting = @($sourceEntries | Where-Object {
      [string]$_.newRemapKeys -ne $target
    })
    if ($sourceEntries.Count -ne 1 -or $conflicting.Count -ne 0) {
      throw "PowerToys already has a conflicting remap for VK_IME_OFF."
    }
    return [pscustomobject]@{
      Changed = $false
      DesiredJson = $ProfileJson
    }
  }

  $desiredEntries = if ($Action -eq "Add") {
    @($entries) + @([pscustomobject]@{
      originalKeys = $source
      newRemapKeys = $target
    })
  } else {
    @($entries | Where-Object {
      -not (
        [string]$_.originalKeys -eq $source -and
        [string]$_.newRemapKeys -eq $target
      )
    })
  }
  $desiredEntries = @($desiredEntries)
  $profile.remapKeys.inProcess = @($desiredEntries)
  return [pscustomobject]@{
    Changed = $desiredEntries.Count -ne $entries.Count
    DesiredJson = ($profile | ConvertTo-Json -Depth 20 -Compress)
  }
}

function Restart-KanataPowerToys {
  $runner = Get-Process -Name "PowerToys" -ErrorAction SilentlyContinue |
    Select-Object -First 1
  if ($null -eq $runner -or [string]::IsNullOrWhiteSpace($runner.Path)) {
    throw "PowerToys must be running to activate the Surface IME mapping."
  }
  $runnerPath = $runner.Path
  Stop-Process -Id $runner.Id -Force -ErrorAction Stop
  $deadline = (Get-Date).AddSeconds(5)
  do {
    Start-Sleep -Milliseconds 100
  } while (
    (Get-Process -Id $runner.Id -ErrorAction SilentlyContinue) -and
    (Get-Date) -lt $deadline
  )
  if (Get-Process -Id $runner.Id -ErrorAction SilentlyContinue) {
    throw "PowerToys did not stop for Keyboard Manager reload."
  }

  Start-Process -FilePath $runnerPath | Out-Null
  $deadline = (Get-Date).AddSeconds(10)
  do {
    Start-Sleep -Milliseconds 100
    $engine = Get-Process `
      -Name "PowerToys.KeyboardManagerEngine" `
      -ErrorAction SilentlyContinue
  } while ($null -eq $engine -and (Get-Date) -lt $deadline)
  if ($null -eq $engine) {
    throw "PowerToys Keyboard Manager did not restart."
  }
}

function Set-KanataImeOffPowerToysMapping {
  param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("Add", "Remove")]
    [string]$Action
  )

  $profilePath = Get-KanataPowerToysKeyboardManagerProfilePath
  if (-not (Test-Path -LiteralPath $profilePath -PathType Leaf)) {
    throw "PowerToys Keyboard Manager profile not found: $profilePath"
  }
  $currentJson = [IO.File]::ReadAllText($profilePath)
  $update = Get-KanataImeOffPowerToysProfileUpdate `
    -Action $Action `
    -ProfileJson $currentJson
  if (-not $update.Changed) {
    return $false
  }

  $temporaryPath = "$profilePath.new-$([guid]::NewGuid().ToString('N'))"
  try {
    [IO.File]::WriteAllText(
      $temporaryPath,
      $update.DesiredJson,
      [Text.UTF8Encoding]::new($false)
    )
    Move-Item `
      -LiteralPath $temporaryPath `
      -Destination $profilePath `
      -Force
    Restart-KanataPowerToys
  } catch {
    [IO.File]::WriteAllText(
      $profilePath,
      $currentJson,
      [Text.UTF8Encoding]::new($false)
    )
    throw
  } finally {
    Remove-Item `
      -LiteralPath $temporaryPath `
      -Force `
      -ErrorAction SilentlyContinue
  }
  return $true
}

function Add-KanataImeOffPowerToysMapping {
  return Set-KanataImeOffPowerToysMapping -Action Add
}

function Remove-KanataImeOffPowerToysMapping {
  return Set-KanataImeOffPowerToysMapping -Action Remove
}

Export-ModuleMember -Function `
  Get-KanataPowerToysKeyboardManagerProfilePath, `
  Get-KanataImeOffPowerToysProfileUpdate, `
  Restart-KanataPowerToys, `
  Add-KanataImeOffPowerToysMapping, `
  Remove-KanataImeOffPowerToysMapping
