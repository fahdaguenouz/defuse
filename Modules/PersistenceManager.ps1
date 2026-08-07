#Requires -RunAsAdministrator

# ============================================
# Defuse - Persistence Removal
# ============================================

<#
.SYNOPSIS
    Removes registry Run/RunOnce entries matching the target.
.DESCRIPTION
    Scans configured registry locations and removes values whose
    name or data contains the target string.
.PARAMETER Target
    The normalized target name.
.PARAMETER DryRun
    If set, only logs what would be removed.
.OUTPUTS
    [int] Count of registry values removed.
#>
function Remove-RegistryPersistence {
    [CmdletBinding()]
    param(
        [string]$Target,
        [switch]$DryRun
    )

    $removed = 0

    foreach ($location in $script:RegistryLocations) {
        if (-not (Test-Path -LiteralPath $location)) {
            continue
        }

        try {
            $key = Get-Item -LiteralPath $location
            $valueNames = @($key.GetValueNames())

            foreach ($valueName in $valueNames) {
                $valueData = [string]$key.GetValue($valueName)

                $nameMatches = (Normalize-Name $valueName) -eq $Target
                $dataMatches = $valueData.ToLower().Contains($Target)

                if ($nameMatches -or $dataMatches) {
                    if ($DryRun) {
                        Write-Host "[DRY-RUN] Would remove registry value: $location\$valueName" `
                            -ForegroundColor Yellow
                    }
                    else {
                        Remove-ItemProperty `
                            -LiteralPath $location `
                            -Name $valueName `
                            -Force `
                            -ErrorAction Stop

                        Write-Host "[+] Removed registry persistence: $location\$valueName" `
                            -ForegroundColor Green

                        $removed++
                    }
                }
            }
        }
        catch {
            Write-Warning "Could not inspect $location`: $($_.Exception.Message)"
        }
    }

    return $removed
}

<#
.SYNOPSIS
    Removes startup folder files matching the target.
.DESCRIPTION
    Scans user and system startup folders and removes files
    whose normalized name contains the target.
.PARAMETER Target
    The normalized target name.
.PARAMETER DryRun
    If set, only logs what would be removed.
.OUTPUTS
    [int] Count of startup files removed.
#>
function Remove-StartupFiles {
    [CmdletBinding()]
    param(
        [string]$Target,
        [switch]$DryRun
    )

    $removed = 0

    foreach ($folder in $script:StartupFolders) {
        if (-not (Test-Path -LiteralPath $folder)) {
            continue
        }

        $startupFiles = @(
            Get-ChildItem -LiteralPath $folder -Force -File -ErrorAction SilentlyContinue |
            Where-Object { (Normalize-Name $_.Name).Contains($Target) }
        )

        foreach ($file in $startupFiles) {
            if (Remove-Safely -Path $file.FullName -Description "Startup file" -DryRun:$DryRun) {
                $removed++
            }
        }
    }

    return $removed
}
