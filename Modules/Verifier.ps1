# Requires -RunAsAdministrator


<#
.SYNOPSIS
    Checks if any target processes are still running.
.PARAMETER Target
    The normalized target name.
.OUTPUTS
    [array] Remaining Win32_Process objects.
#>
function Test-RemainingProcesses {
  [CmdletBinding()]
  param([string]$Target)

  return @(
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
      Where-Object { (Normalize-Name $_.Name) -eq $Target }
  )
}

<#
.SYNOPSIS
    Checks for remaining registry persistence entries.
.PARAMETER Target
    The normalized target name.
.OUTPUTS
    [array] Strings describing remaining registry values.
#>
function Test-RemainingRegistry {
  [CmdletBinding()]
  param([string]$Target)

  $remaining = @()

  foreach ($location in $script:RegistryLocations) {
    if (Test-Path -LiteralPath $location) {
      try {
        $key = Get-Item -LiteralPath $location

        foreach ($valueName in $key.GetValueNames()) {
          $valueData = [string]$key.GetValue($valueName)

          if ((Normalize-Name $valueName) -eq $Target -or
            $valueData.ToLower().Contains($Target)) {
            $remaining += "$location\$valueName"
          }
        }
      }
      catch {
        Write-Warning "Could not verify $location"
      }
    }
  }

  return $remaining
}

<#
.SYNOPSIS
    Displays the mitigation summary report.
.PARAMETER Endpoints
    Array of observed remote endpoints.
.PARAMETER RegistryRemoved
    Count of registry values removed.
.PARAMETER StartupRemoved
    Count of startup files removed.
.PARAMETER Terminated
    Count of processes terminated.
.PARAMETER FilesRemoved
    Count of files/directories removed.
.PARAMETER RemainingProcesses
    Array of remaining process objects.
.PARAMETER RemainingRegistry
    Array of remaining registry strings.
#>
function Write-Summary {
  [CmdletBinding()]
  param(
    [array]$Endpoints,
    [int]$RegistryRemoved,
    [int]$StartupRemoved,
    [int]$Terminated,
    [int]$FilesRemoved,
    [array]$RemainingProcesses,
    [array]$RemainingRegistry
  )

  Write-Host ""
  Write-Host "============== MITIGATION SUMMARY ==============" -ForegroundColor Cyan
  Write-Host "Observed endpoint(s)     : $(if ($Endpoints.Count -gt 0) { $Endpoints -join ', ' } else { 'None' })"
  Write-Host "Registry values removed  : $RegistryRemoved"
  Write-Host "Startup files removed    : $StartupRemoved"
  Write-Host "Processes terminated     : $Terminated"
  Write-Host "Files/directories removed: $FilesRemoved"

  if ($RemainingProcesses.Count -eq 0) {
    Write-Host "[+] Verification: target process is no longer running." -ForegroundColor Green
  }
  else {
    Write-Warning "Verification: target process still exists."
  }

  if ($RemainingRegistry.Count -eq 0) {
    Write-Host "[+] Verification: no matching monitored registry values remain." -ForegroundColor Green
  }
  else {
    Write-Warning "Matching registry values still exist:"
    $RemainingRegistry | ForEach-Object { Write-Warning "  $_" }
  }

  Write-Host "================================================" -ForegroundColor Cyan
}
