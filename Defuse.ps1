[CmdletBinding()]
param(
    [string]$Target = "maltrack",
    [switch]$DryRun
)

# Requires an elevated PowerShell session.
$principal = New-Object Security.Principal.WindowsPrincipal(
    [Security.Principal.WindowsIdentity]::GetCurrent()
)

if (-not $principal.IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)) {
    Write-Error "Run this script as Administrator."
    exit 1
}

function Normalize-Name {
    param([string]$Name)

    return (($Name -replace "\.exe$", "") -replace "[^a-zA-Z0-9]", "").ToLower()
}

function Remove-Safely {
    param(
        [string]$Path,
        [string]$Description
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

$Target = Normalize-Name $Target

if ([string]::IsNullOrWhiteSpace($Target)) {
    Write-Error "Invalid target name."
    exit 1
}

Write-Host "============================================" -ForegroundColor Cyan
Write-Host " Defuse - Malware Mitigation Tool" -ForegroundColor Cyan
Write-Host " Target: $Target" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

# ------------------------------------------------------------
# 1. Discover target processes
# ------------------------------------------------------------

$processTable = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)

$targetProcesses = @(
    $processTable | Where-Object {
        (Normalize-Name $_.Name) -eq $Target
    }
)

if (-not $targetProcesses) {
    Write-Warning "No process named '$Target' was found."
    exit 0
}

$targetPids = @(
    $targetProcesses | ForEach-Object {
        [int]$_.ProcessId
    }
)

Write-Host "[+] Found target PID(s): $($targetPids -join ', ')" -ForegroundColor Green

# ------------------------------------------------------------
# 2. Collect active TCP endpoints before termination
# ------------------------------------------------------------

$ips = @()

try {
    $connections = @(
        Get-NetTCPConnection `
            -State Established `
            -ErrorAction Stop |
        Where-Object {
            $_.OwningProcess -in $targetPids
        }
    )

    $ips = @(
        $connections |
        ForEach-Object { $_.RemoteAddress } |
        Where-Object {
            $_ -and $_ -notin @("0.0.0.0", "::", "::1")
        } |
        Sort-Object -Unique
    )
}
catch {
    Write-Warning "Could not read TCP connections: $($_.Exception.Message)"
}

if ($ips.Count -gt 0) {
    Write-Host "[+] Observed remote endpoint(s): $($ips -join ', ')" -ForegroundColor Green
}
else {
    Write-Host "[*] No established remote endpoint was observed." -ForegroundColor Yellow
}

# ------------------------------------------------------------
# 3. Collect executable paths
# ------------------------------------------------------------

$paths = @(
    $targetProcesses |
    ForEach-Object { $_.ExecutablePath } |
    Where-Object {
        $_ -and (Test-Path -LiteralPath $_)
    } |
    Sort-Object -Unique
)

foreach ($path in $paths) {
    Write-Host "[+] Target executable: $path" -ForegroundColor Green
}

# ------------------------------------------------------------
# 4. Find child processes
# ------------------------------------------------------------

$allPids = [System.Collections.Generic.HashSet[int]]::new()

foreach ($pid in $targetPids) {
    [void]$allPids.Add($pid)
}

$changed = $true

while ($changed) {
    $changed = $false

    foreach ($proc in $processTable) {
        $parentPid = [int]$proc.ParentProcessId
        $childPid = [int]$proc.ProcessId

        if ($allPids.Contains($parentPid) -and
            -not $allPids.Contains($childPid)) {
            [void]$allPids.Add($childPid)
            $changed = $true
        }
    }
}

$allPidsArray = @($allPids)

if ($allPidsArray.Count -gt $targetPids.Count) {
    Write-Host "[+] Related child PID(s): $(
        $allPidsArray | Where-Object { $_ -notin $targetPids } -join ', '
    )" -ForegroundColor Yellow
}

# ------------------------------------------------------------
# 5. Remove registry persistence
# ------------------------------------------------------------

$registryLocations = @(
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run",
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce",
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run",
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce",
    "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"
)

$removedRegistry = 0

foreach ($location in $registryLocations) {
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

                    $removedRegistry++
                }
            }
        }
    }
    catch {
        Write-Warning "Could not inspect $location`: $($_.Exception.Message)"
    }
}

# ------------------------------------------------------------
# 6. Remove matching Startup-folder files
# ------------------------------------------------------------

$startupFolders = @(
    "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup",
    "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup"
)

$removedStartup = 0

foreach ($folder in $startupFolders) {
    if (-not (Test-Path -LiteralPath $folder)) {
        continue
    }

    $startupFiles = @(
        Get-ChildItem -LiteralPath $folder -Force -File `
            -ErrorAction SilentlyContinue |
        Where-Object {
            (Normalize-Name $_.Name).Contains($Target)
        }
    )

    foreach ($file in $startupFiles) {
        if (Remove-Safely `
            -Path $file.FullName `
            -Description "Startup file") {
            $removedStartup++
        }
    }
}

# ------------------------------------------------------------
# 7. Terminate target and child processes
# ------------------------------------------------------------

$terminated = 0

# Children first, then the target process.
foreach ($pid in ($allPidsArray | Sort-Object -Descending)) {
    try {
        $process = Get-Process -Id $pid -ErrorAction Stop

        if ($DryRun) {
            Write-Host "[DRY-RUN] Would terminate $($process.ProcessName) PID $pid" `
                -ForegroundColor Yellow
        }
        else {
            Stop-Process -Id $pid -Force -ErrorAction Stop
            Write-Host "[+] Terminated $($process.ProcessName) PID $pid" `
                -ForegroundColor Green
            $terminated++
        }
    }
    catch [Microsoft.PowerShell.Commands.ProcessCommandException] {
        Write-Host "[*] PID $pid is no longer running." -ForegroundColor DarkGray
    }
    catch {
        Write-Warning "Could not terminate PID $pid`: $($_.Exception.Message)"
    }
}

Start-Sleep -Milliseconds 500

# ------------------------------------------------------------
# 8. Delete executable and matching malware directory
# ------------------------------------------------------------

$removedFiles = 0

foreach ($path in $paths) {
    if (Remove-Safely -Path $path -Description "malware executable") {
        $removedFiles++
    }

    $parentDirectory = Split-Path -LiteralPath $path -Parent
    $directoryName = Split-Path -LiteralPath $parentDirectory -Leaf

    # Only remove the directory when its name exactly matches the target.
    if ((Normalize-Name $directoryName) -eq $Target -and
        (Test-Path -LiteralPath $parentDirectory)) {

        if (Remove-Safely `
            -Path $parentDirectory `
            -Description "malware directory") {
            $removedFiles++
        }
    }
}

# ------------------------------------------------------------
# 9. Verification
# ------------------------------------------------------------

$remainingProcesses = @(
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object {
        (Normalize-Name $_.Name) -eq $Target
    }
)

$remainingRegistry = @()

foreach ($location in $registryLocations) {
    if (Test-Path -LiteralPath $location) {
        try {
            $key = Get-Item -LiteralPath $location

            foreach ($valueName in $key.GetValueNames()) {
                $valueData = [string]$key.GetValue($valueName)

                if (
                    (Normalize-Name $valueName) -eq $Target -or
                    $valueData.ToLower().Contains($Target)
                ) {
                    $remainingRegistry += "$location\$valueName"
                }
            }
        }
        catch {
            Write-Warning "Could not verify $location"
        }
    }
}

Write-Host ""
Write-Host "============== MITIGATION SUMMARY ==============" `
    -ForegroundColor Cyan
Write-Host "Observed endpoint(s) : $(
    if ($ips.Count -gt 0) { $ips -join ', ' } else { 'None' }
)"
Write-Host "Registry values removed: $removedRegistry"
Write-Host "Startup files removed  : $removedStartup"
Write-Host "Processes terminated   : $terminated"
Write-Host "Files/directories removed: $removedFiles"

if ($remainingProcesses.Count -eq 0) {
    Write-Host "[+] Verification: target process is no longer running." `
        -ForegroundColor Green
}
else {
    Write-Warning "Verification: target process still exists."
}

if ($remainingRegistry.Count -eq 0) {
    Write-Host "[+] Verification: no matching monitored registry values remain." `
        -ForegroundColor Green
}
else {
    Write-Warning "Matching registry values still exist:"
    $remainingRegistry | ForEach-Object {
        Write-Warning "  $_"
    }
}

Write-Host "================================================" `
    -ForegroundColor Cyan
