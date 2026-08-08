# Requires -RunAsAdministrator


<#
.SYNOPSIS
    Normalizes a process/file name for comparison.
.DESCRIPTION
    Removes .exe extension, strips non-alphanumeric characters,
    and converts to lowercase.
.PARAMETER Name
    The name to normalize.
#>
function Normalize-Name {
  [CmdletBinding()]
  param([string]$Name)

  return (($Name -replace "\.exe$", "") -replace "[^a-zA-Z0-9]", "").ToLower()
}

<#
.SYNOPSIS
    Safely removes a file or directory with dry-run support.
.DESCRIPTION
    Checks existence, respects DryRun mode, and handles errors gracefully.
.PARAMETER Path
    The literal path to remove.
.PARAMETER Description
    Human-readable description for logging.
.PARAMETER DryRun
    If set, only logs what would be removed.
.OUTPUTS
    [bool] True if an item was actually removed.
#>
function Remove-Safely {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string]$Path,

    [Parameter(Mandatory)]
    [string]$Description,

    [switch]$DryRun
  )

  if (-not (Test-Path -LiteralPath $Path)) {
    return $false
  }

  if ($DryRun) {
    Write-Host "[DRY-RUN] Would remove $Description`: $Path" -ForegroundColor Yellow
    return $false
  }

  try {
    Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
    Write-Host "[+] Removed $Description`: $Path" -ForegroundColor Green
    return $true
  }
  catch {
    Write-Warning "Could not remove $Path`: $($_.Exception.Message)"
    return $false
  }
}

<#
.SYNOPSIS
    Writes the Defuse banner to the console.
.PARAMETER Target
    The target name to display.
#>
function Write-Banner {
  [CmdletBinding()]
  param([string]$Target)

  Write-Host "============================================" -ForegroundColor Cyan
  Write-Host " Defuse - Malware Mitigation Tool" -ForegroundColor Cyan
  Write-Host " Target: $Target" -ForegroundColor Cyan
  Write-Host "============================================" -ForegroundColor Cyan
}
