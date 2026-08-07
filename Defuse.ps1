#Requires -RunAsAdministrator

# ============================================
# Defuse - Malware Mitigation Tool
# ============================================
# Entry point that orchestrates all modules.
#
# Usage:
#   .\Defuse.ps1 -Target "maltrack"
#   .\Defuse.ps1 -Target "maltrack" -DryRun
# ============================================

# --- Elevation Check ---
$principal = New-Object Security.Principal.WindowsPrincipal(
    [Security.Principal.WindowsIdentity]::GetCurrent()
)

if (-not $principal.IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)) {
    Write-Error "Run this script as Administrator."
    exit 1
}

# --- Load Modules ---
$modulePath = Join-Path $PSScriptRoot "Modules"

. (Join-Path $modulePath "Config.ps1")
. (Join-Path $modulePath "Helpers.ps1")
. (Join-Path $modulePath "ProcessDiscovery.ps1")
. (Join-Path $modulePath "NetworkCollector.ps1")
. (Join-Path $modulePath "PersistenceManager.ps1")
. (Join-Path $modulePath "TerminationManager.ps1")
. (Join-Path $modulePath "FileCleaner.ps1")
. (Join-Path $modulePath "Verifier.ps1")

# --- Normalize Target ---
$Target = Normalize-Name $Target

if ([string]::IsNullOrWhiteSpace($Target)) {
    Write-Error "Invalid target name."
    exit 1
}

Write-Banner -Target $Target

# --- 1. Discover Target Processes ---
$targetProcesses = Find-TargetProcesses -Target $Target

if (-not $targetProcesses) {
    Write-Warning "No process named '$Target' was found."
    exit 0
}

$targetPids = @($targetProcesses | ForEach-Object { [int]$_.ProcessId })
Write-Host "[+] Found target PID(s): $($targetPids -join ', ')" -ForegroundColor Green

# --- 2. Collect Network Endpoints ---
$ips = Get-RemoteEndpoints -Pids $targetPids

if ($ips.Count -gt 0) {
    Write-Host "[+] Observed remote endpoint(s): $($ips -join ', ')" -ForegroundColor Green
}
else {
    Write-Host "[*] No established remote endpoint was observed." -ForegroundColor Yellow
}

# --- 3. Collect Executable Paths ---
$paths = Get-ExecutablePaths -Processes $targetProcesses
foreach ($path in $paths) {
    Write-Host "[+] Target executable: $path" -ForegroundColor Green
}

# --- 4. Find Child Processes ---
$processTable = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)
$allPids = Find-ChildProcesses -ParentPids $targetPids -ProcessTable $processTable

if ($allPids.Count -gt $targetPids.Count) {
    $childPids = $allPids | Where-Object { $_ -notin $targetPids }
    Write-Host "[+] Related child PID(s): $($childPids -join ', ')" -ForegroundColor Yellow
}

# --- 5. Remove Registry Persistence ---
$removedRegistry = Remove-RegistryPersistence -Target $Target -DryRun:$DryRun

# --- 6. Remove Startup Files ---
$removedStartup = Remove-StartupFiles -Target $Target -DryRun:$DryRun

# --- 7. Terminate Processes ---
$terminated = Stop-TargetProcesses -Pids $allPids -DryRun:$DryRun
Start-Sleep -Milliseconds $script:PostTerminationDelay

# --- 8. Delete Files & Directories ---
$removedFiles = Remove-MalwareArtifacts -Paths $paths -Target $Target -DryRun:$DryRun

# --- 9. Verification ---
$remainingProcesses = Test-RemainingProcesses -Target $Target
$remainingRegistry  = Test-RemainingRegistry -Target $Target

Write-Summary `
    -Endpoints $ips `
    -RegistryRemoved $removedRegistry `
    -StartupRemoved $removedStartup `
    -Terminated $terminated `
    -FilesRemoved $removedFiles `
    -RemainingProcesses $remainingProcesses `
    -RemainingRegistry $remainingRegistry