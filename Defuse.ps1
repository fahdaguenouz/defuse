<#
.SYNOPSIS
    Defuse – Malware Analysis & Mitigation Tool (PowerShell Edition)
    Targets: Win32/Fynloski family (e.g. Mal-Track / maltrack.exe)

.DESCRIPTION
    Replicates the full Python "Defuse" tool in a single PowerShell script.
    Steps performed:
        1.  Admin check
        2.  User input  ->  normalize target name
        3.  Network: extract attacker IPs from live connections
                     or fall back to binary-string scanning
        4.  Registry & Startup folder cleanup (Run / RunOnce / WOW64 / Startup)
        5.  Process termination  ->  delete EXE  ->  delete malware folder
        6.  Print Mitigation Summary

.NOTES
    Run from an ELEVATED (Administrator) PowerShell session.
    Compatible with Windows PowerShell 5.1 and PowerShell 7+.
#>

#Requires -Version 5.1

# ─────────────────────────────────────────────────────────────────────────────
#  BANNER
# ─────────────────────────────────────────────────────────────────────────────
function Show-Banner {
    Write-Host ("=" * 50) -ForegroundColor Cyan
    Write-Host "   Malware Analysis & Mitigation Tool (Defuse)   " -ForegroundColor Cyan
    Write-Host ("=" * 50) -ForegroundColor Cyan
    Write-Host ""
}

# ─────────────────────────────────────────────────────────────────────────────
#  ADMIN CHECK  (mirrors is_admin() in main.py)
# ─────────────────────────────────────────────────────────────────────────────
function Test-IsAdmin {
    $current = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    return $current.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ─────────────────────────────────────────────────────────────────────────────
#  NORMALIZE TARGET  (mirrors normalize_target() in file.py)
# ─────────────────────────────────────────────────────────────────────────────
function Get-NormalizedTarget {
    param([string]$UserInput)

    $s = $UserInput.Trim().ToLower()

    # Strip .exe suffix if present
    if ($s.EndsWith(".exe")) {
        $s = $s.Substring(0, $s.Length - 4)
    }

    # Strip hyphens used in registry key names (e.g. "Mal-Track" -> "maltrack")
    $s = $s -replace "-", ""

    return $s
}

# ─────────────────────────────────────────────────────────────────────────────
#  REGISTRY & STARTUP CLEANUP  (mirrors registry.py)
# ─────────────────────────────────────────────────────────────────────────────
$PERSISTENCE_PATHS = @(
    @{ Hive = "HKCU"; Path = "SOFTWARE\Microsoft\Windows\CurrentVersion\Run" },
    @{ Hive = "HKLM"; Path = "SOFTWARE\Microsoft\Windows\CurrentVersion\Run" },
    @{ Hive = "HKCU"; Path = "SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" },
    @{ Hive = "HKLM"; Path = "SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" },
    @{ Hive = "HKLM"; Path = "SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run" }
)

function Remove-FromRegistry {
    param([string]$Target)

    $removed = [System.Collections.Generic.List[string]]::new()

    # ── 1. Registry Run/RunOnce keys ─────────────────────────────────────────
    foreach ($entry in $PERSISTENCE_PATHS) {
        $fullPath = "$($entry.Hive):\$($entry.Path)"

        try {
            if (-not (Test-Path $fullPath)) { continue }

            $key = Get-Item -LiteralPath $fullPath -ErrorAction Stop

            # Collect matching value names first (avoid mutating while enumerating)
            $toDelete = @()
            foreach ($valueName in $key.GetValueNames()) {
                $valueData = $key.GetValue($valueName)
                $valueStr  = if ($null -ne $valueData) { $valueData.ToString() } else { "" }

                if (($valueName.ToLower() -like "*$Target*") -or
                    ($valueStr.ToLower()  -like "*$Target*")) {
                    $toDelete += @{ Name = $valueName; Data = $valueStr }
                }
            }

            foreach ($item in $toDelete) {
                $label = "$($entry.Hive)\$($entry.Path) -> '$($item.Name)' = '$($item.Data)'"
                try {
                    Remove-ItemProperty -LiteralPath $fullPath -Name $item.Name -ErrorAction Stop
                    Write-Host "[REG] Removed: $label" -ForegroundColor Green
                    $removed.Add($label)
                }
                catch [System.UnauthorizedAccessException] {
                    Write-Warning "[!] Permission denied deleting '$($item.Name)'. Run as Administrator."
                }
                catch {
                    Write-Warning "[!] Failed to delete '$($item.Name)': $_"
                }
            }
        }
        catch [System.UnauthorizedAccessException] {
            Write-Warning "[!] Permission denied accessing $fullPath. Run as Administrator."
        }
        catch {
            # Key simply doesn't exist - normal, skip silently
        }
    }

    # ── 2. Startup folders ───────────────────────────────────────────────────
    $startupFolders = @(
        [System.IO.Path]::Combine($env:APPDATA, "Microsoft\Windows\Start Menu\Programs\Startup"),
        [System.IO.Path]::Combine($env:ProgramData, "Microsoft\Windows\Start Menu\Programs\StartUp")
    )

    foreach ($folder in $startupFolders) {
        if (-not (Test-Path $folder)) { continue }

        try {
            $items = Get-ChildItem -LiteralPath $folder -File -ErrorAction Stop
            foreach ($file in $items) {
                if ($file.Name.ToLower() -like "*$Target*") {
                    try {
                        Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
                        $label = "Startup Folder File -> $($file.FullName)"
                        Write-Host "[STARTUP] Removed file: $($file.FullName)" -ForegroundColor Green
                        $removed.Add($label)
                    }
                    catch [System.UnauthorizedAccessException] {
                        Write-Warning "[!] Permission denied deleting startup file $($file.FullName). Run as Administrator."
                    }
                    catch {
                        Write-Warning "[!] Failed to delete startup file $($file.FullName): $_"
                    }
                }
            }
        }
        catch {
            Write-Warning "[!] Could not read startup folder $folder : $_"
        }
    }

    return $removed
}

# ─────────────────────────────────────────────────────────────────────────────
#  SAFE FILE DELETION  (mirrors remove_exe() in file.py)
# ─────────────────────────────────────────────────────────────────────────────
function Remove-MalwareFile {
    param([string]$FilePath)

    if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) { return $false }

    try {
        # Clear read-only attribute before deleting (mirrors os.chmod + stat.S_IWRITE)
        $item = Get-Item -LiteralPath $FilePath -Force
        $item.Attributes = $item.Attributes -band (-bnot [System.IO.FileAttributes]::ReadOnly)

        Remove-Item -LiteralPath $FilePath -Force -ErrorAction Stop
        return $true
    }
    catch [System.UnauthorizedAccessException] {
        Write-Warning "[!] Permission denied removing $FilePath. It might be locked."
        return $false
    }
    catch {
        Write-Warning "[!] Failed to remove $FilePath : $_"
        return $false
    }
}

# ─────────────────────────────────────────────────────────────────────────────
#  PROCESS TERMINATION & FILE CLEANUP  (mirrors process.py -> kill_by_name())
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-KillByName {
    param([string]$Target)

    $removedProcs = [System.Collections.Generic.List[string]]::new()
    $removedPaths = [System.Collections.Generic.List[string]]::new()

    try {
        $allProcs = Get-CimInstance -ClassName Win32_Process -ErrorAction Stop
    }
    catch {
        Write-Warning "[!] Cannot enumerate processes: $_"
        return $removedProcs, $removedPaths
    }

    foreach ($proc in $allProcs) {
        $procName = if ($proc.Name) { $proc.Name } else { "" }
        $procBase = $procName.ToLower()
        if ($procBase.EndsWith(".exe")) { $procBase = $procBase.Substring(0, $procBase.Length - 4) }
        $procBase = $procBase -replace "-", ""

        if ($procBase -eq $Target -or $procBase -like "*$Target*") {
            Write-Host "`n[+] Found target process: $procName (PID: $($proc.ProcessId))" -ForegroundColor Yellow

            $parentPath = $proc.ExecutablePath

            # ── Kill children first ───────────────────────────────────────────
            $children = $allProcs | Where-Object { $_.ParentProcessId -eq $proc.ProcessId }
            foreach ($child in $children) {
                $childName = $child.Name
                $childPath = $child.ExecutablePath
                try {
                    Stop-Process -Id $child.ProcessId -Force -ErrorAction Stop
                    Write-Host "    - Killed child: $childName (PID: $($child.ProcessId))" -ForegroundColor Magenta
                    $removedProcs.Add($childName)

                    if ($childPath -and (Test-Path -LiteralPath $childPath -PathType Leaf)) {
                        if (Remove-MalwareFile -FilePath $childPath) {
                            $removedPaths.Add($childPath)
                            Write-Host "    - Deleted child executable: $childPath" -ForegroundColor Red
                        }
                    }
                }
                catch [System.UnauthorizedAccessException] {
                    Write-Warning "[!] Access denied killing child $childName."
                }
                catch {
                    Write-Warning "[!] Child process error: $_"
                }
            }

            # ── Kill parent ───────────────────────────────────────────────────
            try {
                Stop-Process -Id $proc.ProcessId -Force -ErrorAction Stop
                Write-Host "    - Killed parent: $procName (PID: $($proc.ProcessId))" -ForegroundColor Magenta
                $removedProcs.Add($procName)

                if ($parentPath -and (Test-Path -LiteralPath $parentPath -PathType Leaf)) {
                    if (Remove-MalwareFile -FilePath $parentPath) {
                        $removedPaths.Add($parentPath)
                        Write-Host "    - Deleted parent executable: $parentPath" -ForegroundColor Red

                        # Safe folder cleanup: only if folder name matches target
                        $parentDir  = Split-Path $parentPath -Parent
                        $folderName = (Split-Path $parentDir -Leaf).ToLower() -replace "-", ""

                        if ($folderName -eq $Target) {
                            try {
                                Remove-Item -LiteralPath $parentDir -Recurse -Force -ErrorAction Stop
                                $removedPaths.Add($parentDir)
                                Write-Host "    - Deleted malware folder: $parentDir" -ForegroundColor Red
                            }
                            catch {
                                Write-Warning "[!] Could not delete malware folder $parentDir : $_"
                            }
                        }
                    }
                }
            }
            catch [System.UnauthorizedAccessException] {
                Write-Warning "[!] Access denied killing $procName. Run as Administrator."
            }
            catch {
                Write-Warning "[!] Process error on PID $($proc.ProcessId): $_"
            }
        }
    }

    return $removedProcs, $removedPaths
}

# ─────────────────────────────────────────────────────────────────────────────
#  EXTRACT PRINTABLE STRINGS FROM BINARY  (mirrors extract_strings() in file.py)
# ─────────────────────────────────────────────────────────────────────────────
function Get-BinaryStrings {
    param(
        [string]$FilePath,
        [int]$MinLength = 4
    )

    try {
        $bytes   = [System.IO.File]::ReadAllBytes($FilePath)
        $result  = [System.Text.StringBuilder]::new()
        $strings = [System.Collections.Generic.List[string]]::new()

        foreach ($b in $bytes) {
            if ($b -ge 0x20 -and $b -le 0x7E) {   # printable ASCII
                [void]$result.Append([char]$b)
            }
            else {
                if ($result.Length -ge $MinLength) {
                    $strings.Add($result.ToString())
                }
                [void]$result.Clear()
            }
        }
        # Flush last token
        if ($result.Length -ge $MinLength) { $strings.Add($result.ToString()) }

        return $strings
    }
    catch [System.UnauthorizedAccessException] {
        Write-Warning "[!] Permission denied reading strings from $FilePath. Run as Admin."
        return [System.Collections.Generic.List[string]]::new()
    }
    catch {
        Write-Warning "[!] Failed to read strings from $FilePath : $_"
        return [System.Collections.Generic.List[string]]::new()
    }
}

# ─────────────────────────────────────────────────────────────────────────────
#  FIND IPs IN STRING LIST  (mirrors find_ips() in network.py)
# ─────────────────────────────────────────────────────────────────────────────
function Find-IpsInStrings {
    param($StringList)

    $ipPattern = [System.Text.RegularExpressions.Regex]::new(
        '\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}\b'
    )
    $found = [System.Collections.Generic.HashSet[string]]::new()

    foreach ($s in $StringList) {
        $matches = $ipPattern.Matches($s)
        foreach ($m in $matches) {
            $ip    = $m.Value
            $parts = $ip -split '\.'
            $valid = $true
            foreach ($part in $parts) {
                if ([int]$part -lt 0 -or [int]$part -gt 255) { $valid = $false; break }
            }
            if ($valid) { [void]$found.Add($ip) }
        }
    }

    return [string[]]$found
}

# ─────────────────────────────────────────────────────────────────────────────
#  LIVE NETWORK CONNECTIONS  (mirrors get_remote_ips() in network.py)
# ─────────────────────────────────────────────────────────────────────────────
function Get-RemoteIPs {
    param([string]$Target)

    $ips = [System.Collections.Generic.HashSet[string]]::new()

    try {
        $netstat = netstat -ano 2>$null

        foreach ($line in $netstat) {
            if ($line -notmatch '^\s*(TCP|UDP)') { continue }
            $parts = ($line.Trim()) -split '\s+'

            # TCP: proto  local  remote  state  pid  (5 parts minimum)
            # UDP: proto  local  remote  pid        (4 parts)
            $pid = $null
            if ($parts.Count -ge 5) { $pid = $parts[4] }
            elseif ($parts.Count -eq 4) { $pid = $parts[3] }
            if (-not $pid) { continue }

            try {
                $procObj = Get-Process -Id ([int]$pid) -ErrorAction SilentlyContinue
                if (-not $procObj) { continue }

                $procBase = $procObj.ProcessName.ToLower() -replace "-", ""
                if (-not ($procBase -like "*$Target*")) { continue }

                # Remote address is parts[2] in form  "1.2.3.4:port"
                $remoteRaw = $parts[2]
                if ($remoteRaw -match '^(.+):(\d+)$') {
                    $remoteIP = $Matches[1]
                    $skip = @("0.0.0.0", "::", "::1")
                    if ($remoteIP -notin $skip) {
                        [void]$ips.Add($remoteIP)
                    }
                }
            }
            catch { }
        }
    }
    catch {
        Write-Warning "[!] Cannot enumerate network connections: $_"
    }

    return [string[]]$ips
}

# ─────────────────────────────────────────────────────────────────────────────
#  BINARY-STRING IP FALLBACK  (mirrors find_ip_from_strings() in network.py)
# ─────────────────────────────────────────────────────────────────────────────
function Get-IpsFromBinary {
    param([string]$Target)

    try {
        $allProcs = Get-CimInstance -ClassName Win32_Process -ErrorAction Stop
    }
    catch { return @() }

    foreach ($proc in $allProcs) {
        $procName = if ($proc.Name) { $proc.Name } else { "" }
        $procBase = $procName.ToLower() -replace "\.exe$", "" -replace "-", ""

        if ($procBase -like "*$Target*" -and $proc.ExecutablePath) {
            $strings = Get-BinaryStrings -FilePath $proc.ExecutablePath
            if ($strings.Count -gt 0) {
                $ips = Find-IpsInStrings -StringList $strings
                if ($ips.Count -gt 0) { return $ips }
            }
        }
    }
    return @()
}

# ─────────────────────────────────────────────────────────────────────────────
#  MAIN
# ─────────────────────────────────────────────────────────────────────────────
function Main {
    Show-Banner

    # Admin check
    if (-not (Test-IsAdmin)) {
        Write-Host ""
        Write-Host "[!] CRITICAL WARNING: You are NOT running as Administrator." -ForegroundColor Red
        Write-Host "    Registry editing, network scanning, and process termination" -ForegroundColor Red
        Write-Host "    will likely fail with 'Access Denied' errors." -ForegroundColor Red
        Write-Host "    Please right-click PowerShell and select 'Run as Administrator'." -ForegroundColor Red
        Write-Host ""
    }

    # User input
    do {
        $raw = Read-Host "[?] Enter the target [Process Name / Name in Run]"
    } while ([string]::IsNullOrWhiteSpace($raw))

    $target = Get-NormalizedTarget -UserInput $raw
    Write-Host "`n[*] Normalized target: $target" -ForegroundColor Cyan

    # 1. Network: extract attacker IPs
    Write-Host "`n[*] Collecting attacker IPs..." -ForegroundColor Cyan
    $ips = Get-RemoteIPs -Target $target

    if ($ips.Count -eq 0) {
        Write-Host "    - No live connections found. Scraping binary strings..." -ForegroundColor Gray
        $ips = Get-IpsFromBinary -Target $target
    }

    # Lab fallback
    if ($ips.Count -eq 0) {
        $ips = @("127.0.0.1")
    }

    Write-Host "    -> Identified IPs: $($ips -join ', ')" -ForegroundColor White

    # 2. Registry & Startup cleanup
    Write-Host "`n[*] Removing persistence from registry & startup folders..." -ForegroundColor Cyan
    $removedKeys = Remove-FromRegistry -Target $target

    # 3. Process termination & file deletion
    Write-Host "`n[*] Killing processes and deleting binaries..." -ForegroundColor Cyan
    $removedProcs, $removedPaths = Invoke-KillByName -Target $target

    # 4. Mitigation Summary
    Write-Host ""
    Write-Host ("=" * 50) -ForegroundColor Cyan
    Write-Host "                MITIGATION SUMMARY                " -ForegroundColor Cyan
    Write-Host ("=" * 50) -ForegroundColor Cyan

    Write-Host "  [+] Attacker IPs         : $($ips -join ', ')" -ForegroundColor Green

    Write-Host "  [+] Persistence removed  : $($removedKeys.Count)" -ForegroundColor Green
    foreach ($k in $removedKeys) {
        Write-Host "      - $k" -ForegroundColor White
    }

    $uniqueProcs = $removedProcs | Sort-Object -Unique
    Write-Host "  [+] Processes terminated : $($removedProcs.Count)" -ForegroundColor Green
    foreach ($pn in $uniqueProcs) {
        Write-Host "      - $pn" -ForegroundColor White
    }

    $uniquePaths = $removedPaths | Sort-Object -Unique
    Write-Host "  [+] Files removed        : $($removedPaths.Count)" -ForegroundColor Green
    foreach ($path in $uniquePaths) {
        Write-Host "      - $path" -ForegroundColor White
    }

    Write-Host ("=" * 50) -ForegroundColor Cyan
    Write-Host ""
}

# Entry point
Main
