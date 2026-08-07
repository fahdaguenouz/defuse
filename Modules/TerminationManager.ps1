#Requires -RunAsAdministrator

# ============================================
# Defuse - Process Termination
# ============================================

<#
.SYNOPSIS
    Terminates processes by PID, children first.
.DESCRIPTION
    Sorts PIDs in descending order (children typically have higher PIDs)
    and forcefully terminates each one. Handles already-exited processes.
.PARAMETER Pids
    Array of process IDs to terminate.
.PARAMETER DryRun
    If set, only logs what would be terminated.
.OUTPUTS
    [int] Count of processes actually terminated.
#>
function Stop-TargetProcesses {
    [CmdletBinding()]
    param(
        [array]$Pids,
        [switch]$DryRun
    )

    $terminated = 0

    foreach ($pid in ($Pids | Sort-Object -Descending)) {
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

    return $terminated
}
