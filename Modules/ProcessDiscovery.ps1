#Requires -RunAsAdministrator

# ============================================
# Defuse - Process Discovery
# ============================================

<#
.SYNOPSIS
    Discovers target processes by normalized name.
.DESCRIPTION
    Queries Win32_Process and returns processes whose normalized
    name matches the target.
.PARAMETER Target
    The normalized target name.
.OUTPUTS
    [array] Matching Win32_Process objects.
#>
function Find-TargetProcesses {
    [CmdletBinding()]
    param([string]$Target)

    $processTable = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)

    return @($processTable | Where-Object {
        (Normalize-Name $_.Name) -eq $Target
    })
}

<#
.SYNOPSIS
    Collects all executable paths from a list of processes.
.PARAMETER Processes
    Array of Win32_Process objects.
.OUTPUTS
    [array] Unique, existing executable paths.
#>
function Get-ExecutablePaths {
    [CmdletBinding()]
    param([array]$Processes)

    return @($Processes |
        ForEach-Object { $_.ExecutablePath } |
        Where-Object { $_ -and (Test-Path -LiteralPath $_) } |
        Sort-Object -Unique)
}

<#
.SYNOPSIS
    Discovers all child processes recursively.
.DESCRIPTION
    Builds a transitive closure of child PIDs starting from
    the given parent PIDs.
.PARAMETER ParentPids
    Array of parent process IDs.
.PARAMETER ProcessTable
    Array of Win32_Process objects to search within.
.OUTPUTS
    [array] All PIDs including parents and children.
#>
function Find-ChildProcesses {
    [CmdletBinding()]
    param(
        [array]$ParentPids,
        [array]$ProcessTable
    )

    $allPids = [System.Collections.Generic.HashSet[int]]::new()

    foreach ($pid in $ParentPids) {
        [void]$allPids.Add($pid)
    }

    $changed = $true
    while ($changed) {
        $changed = $false

        foreach ($proc in $ProcessTable) {
            $parentPid = [int]$proc.ParentProcessId
            $childPid  = [int]$proc.ProcessId

            if ($allPids.Contains($parentPid) -and
                -not $allPids.Contains($childPid)) {
                [void]$allPids.Add($childPid)
                $changed = $true
            }
        }
    }

    return @($allPids)
}
