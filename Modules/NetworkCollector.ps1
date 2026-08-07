#Requires -RunAsAdministrator

# ============================================
# Defuse - Network Endpoint Collection
# ============================================

<#
.SYNOPSIS
    Collects established remote TCP endpoints for given PIDs.
.DESCRIPTION
    Queries active TCP connections and returns unique remote
    addresses associated with the specified process IDs.
.PARAMETER Pids
    Array of process IDs to filter by.
.OUTPUTS
    [array] Unique remote IP addresses.
#>
function Get-RemoteEndpoints {
    [CmdletBinding()]
    param([array]$Pids)

    $ips = @()

    try {
        $connections = @(
            Get-NetTCPConnection -State Established -ErrorAction Stop |
            Where-Object { $_.OwningProcess -in $Pids }
        )

        $ips = @($connections |
            ForEach-Object { $_.RemoteAddress } |
            Where-Object { $_ -and $_ -notin @("0.0.0.0", "::", "::1") } |
            Sort-Object -Unique)
    }
    catch {
        Write-Warning "Could not read TCP connections: $($_.Exception.Message)"
    }

    return $ips
}
