#Requires -RunAsAdministrator

# ============================================
# Defuse - File & Directory Cleanup
# ============================================

<#
.SYNOPSIS
    Deletes target executables and their parent directories.
.DESCRIPTION
    Removes each executable path. If the parent directory's
    normalized name exactly matches the target, removes the directory too.
.PARAMETER Paths
    Array of executable file paths.
.PARAMETER Target
    The normalized target name for directory matching.
.PARAMETER DryRun
    If set, only logs what would be removed.
.OUTPUTS
    [int] Count of items (files + directories) removed.
#>
function Remove-MalwareArtifacts {
    [CmdletBinding()]
    param(
        [array]$Paths,
        [string]$Target,
        [switch]$DryRun
    )

    $removed = 0

    foreach ($path in $Paths) {
        if (Remove-Safely -Path $path -Description "malware executable" -DryRun:$DryRun) {
            $removed++
        }

$parentDirectory = [System.IO.Path]::GetDirectoryName($path)

if (-not [string]::IsNullOrWhiteSpace($parentDirectory)) {
    $directoryName = [System.IO.Path]::GetFileName($parentDirectory)

    if (
        (Normalize-Name $directoryName) -eq $Target -and
        (Test-Path -LiteralPath $parentDirectory)
    ) {
        if (
            Remove-Safely `
                -Path $parentDirectory `
                -Description "malware directory" `
                -DryRun:$DryRun
        ) {
            $removed++
        }
    }
}


        if ((Normalize-Name $directoryName) -eq $Target -and
            (Test-Path -LiteralPath $parentDirectory)) {

            if (Remove-Safely -Path $parentDirectory -Description "malware directory" -DryRun:$DryRun) {
                $removed++
            }
        }
    }

    return $removed
}
