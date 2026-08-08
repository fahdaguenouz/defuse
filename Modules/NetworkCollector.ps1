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


#Requires -RunAsAdministrator

# ============================================
# Defuse - Network Endpoint Collection
# ============================================

function Get-RemoteEndpoints {
    [CmdletBinding()]
    param(
        [array]$Pids
    )

    $ips = @()

    try {
        $connections = @(
            Get-NetTCPConnection -ErrorAction Stop |
            Where-Object {
                $_.OwningProcess -in $Pids -and
                $_.State -in @(
                    "Established",
                    "SynSent",
                    "SynReceived"
                )
            }
        )

        $ips = @(
            $connections |
            ForEach-Object { $_.RemoteAddress } |
            Where-Object {
                $_ -and
                $_ -notin @("0.0.0.0", "::", "::1")
            } |
            Sort-Object -Unique
        )
    }
    catch {
        Write-Warning "Could not read TCP connections: $($_.Exception.Message)"
    }

    return $ips
}

function Get-IPsFromFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $ips = @()

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $ips
    }

    try {
        # Read the file as bytes and search for ASCII IPv4 strings.
        $bytes = [System.IO.File]::ReadAllBytes($Path)

        $text = [System.Text.Encoding]::ASCII.GetString($bytes)

        $matches = [regex]::Matches(
            $text,
            '\b(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(?:\.(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}\b'
        )

        foreach ($match in $matches) {
            $ip = $match.Value

            if ($ip -notin @(
                "0.0.0.0",
                "255.255.255.255"
            )) {
                $ips += $ip
            }
        }
    }
    catch {
        Write-Warning "Could not scan file for IP addresses: $Path"
    }

    return @($ips | Sort-Object -Unique)
}

function Get-TargetIPArtifacts {
    [CmdletBinding()]
    param(
        [array]$Paths
    )

    $results = @()

    foreach ($path in $Paths) {
        $found = @(Get-IPsFromFile -Path $path)

        foreach ($ip in $found) {
            $results += $ip

            Write-Host "[+] IP string found in artifact: $ip" `
                -ForegroundColor Green

            Write-Host "    Source: $path" `
                -ForegroundColor DarkGray
        }
    }

    return @($results | Sort-Object -Unique)
}

