Describe "GlazeWM process lifecycle" {
  BeforeAll {
    $modulePath = Join-Path $PSScriptRoot "..\GlazeWMProcess.psm1"
    Import-Module $modulePath -Force
  }

  BeforeEach {
    Mock Resolve-GlazeTaskkillPath {
      "C:\Windows\System32\taskkill.exe"
    } -ModuleName GlazeWMProcess
    Mock Invoke-GlazeProcessTreeTermination {
      0
    } -ModuleName GlazeWMProcess
  }

  It "terminates the helper process and every descendant" {
    Stop-GlazeProcessTree -ProcessId 1234

    Assert-MockCalled Invoke-GlazeProcessTreeTermination `
      -ModuleName GlazeWMProcess `
      -Times 1 `
      -Exactly `
      -ParameterFilter {
        $FilePath -eq "C:\Windows\System32\taskkill.exe" -and
        @($ArgumentList).Count -eq 4 -and
        $ArgumentList[0] -eq "/PID" -and
        $ArgumentList[1] -eq "1234" -and
        $ArgumentList[2] -eq "/T" -and
        $ArgumentList[3] -eq "/F"
      }
  }

  It "fails when Windows cannot terminate the complete process tree" {
    Mock Invoke-GlazeProcessTreeTermination {
      5
    } -ModuleName GlazeWMProcess

    {
      Stop-GlazeProcessTree -ProcessId 1234
    } | Should -Throw "*process tree*exit code 5*"
  }

  It "exports only the process tree termination command" {
    @(
      Get-Command -Module GlazeWMProcess |
        Select-Object -ExpandProperty Name
    ) | Should -Be @("Stop-GlazeProcessTree")
  }
}
