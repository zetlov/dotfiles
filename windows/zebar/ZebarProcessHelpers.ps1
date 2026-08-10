function Get-ZetshellGpuMonitorCommandLines {
  $program = "C:\Windows\System32\nvidia-smi.exe"
  $arguments = @(
    "--query-gpu=utilization.gpu,temperature.gpu --format=csv,noheader,nounits --id=0 --loop-ms=2000"
    "--query-gpu=utilization.gpu --format=csv,noheader,nounits --id=0 --loop-ms=2000"
  )

  return @($arguments | ForEach-Object {
    [char]34 + $program + [char]34 + " " + $_
  })
}

function Get-ZetshellGpuMonitorProcess {
  $expectedCommandLines = @(Get-ZetshellGpuMonitorCommandLines)
  return Get-CimInstance Win32_Process |
    Where-Object {
      $_.Name -eq "nvidia-smi.exe" -and
      $_.CommandLine -in $expectedCommandLines
    }
}
