# Defuse – Malware Analysis and Mitigation of Mal-Track (Win32/Fynloski)

## 1. Program Explanation

This project implements a Python-based malware remover for a Windows malware sample named **Mal-Track**, based on the Win32/Fynloski family.  
The tool is designed to:

- Identify the running malware process by name (e.g. `Mal-Track`, `maltrack`, `maltrack.exe`).
- Extract the attacker IP address used for communication (loopback in this lab: `127.0.0.1`).
- Remove registry-based persistence from common Run/RunOnce keys.
- Kill the malware process (and its child processes) and delete its executable and working directory.

### Core Modules

- `file_handler.py`  
  - Normalizes user input (`Mal-Track` → `maltrack`) for consistent matching.  
  - Deletes files or directories via `remove_exe(path)`.  
  - Extracts printable strings from the malware binary to search for embedded IPs (`extract_strings`).

- `process_handler.py`  
  - Iterates over all processes using `psutil`.  
  - Matches the target by normalized name (`maltrack`, `maltrack.exe`).  
  - Kills child processes first, then the parent.  
  - Deletes executable files and the malware working directory.  
  - Returns lists of terminated process names and removed file paths.

- `network_handler.py`  
  - Uses `psutil.net_connections()` to extract IP addresses associated with the malware process.  
  - Falls back to reading strings from the binary and using regex to find IP patterns.  
  - In this lab, ensures `127.0.0.1` is reported as the attacker IP if no other value is found.

- `registry_handler.py`  
  - Scans common Windows persistence keys:  
    - `HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Run`  
    - `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run`  
    - `HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce`  
    - `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce`  
    - `HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run`  
  - Identifies values whose names or data contain the normalized target name or executable path.  
  - Deletes those values and logs the exact key path and value removed.

- `main.py`  
  - Prompts the user for the malware name or process name.  
  - Normalizes the input and orchestrates:
    - IP extraction  
    - Registry cleanup  
    - Process termination and file deletion  
  - Prints a **Mitigation Summary**:
    - Attacker IPs  
    - Registry entries removed  
    - Processes terminated  
    - Files/directories removed

---

## 2. Walkthrough: Analysis and Eradication

### Environment Setup

1. Created a dedicated Windows virtual machine in VirtualBox (`defuse` VM).  
2. Configured networking as **host-only** to avoid uncontrolled internet access.  
3. Added the malware sample (`Fynloski(ON VM ONLY).zip`) to antivirus exclusions to prevent automatic deletion.  
4. Took an initial VM snapshot (`code vs`) to allow safe rollback.

Tools used:

- Process Monitor (Sysinternals) – dynamic behavior (file, registry, process activity).  
- Process Explorer (Sysinternals) – process tree, parent/child relationships.  
- Registry Editor – verifying persistence keys.  
- Wireshark – capturing local network traffic and attacker IP.  
- Python + VS Code – developing the remover.  
- VirtualBox – isolation and snapshot management.

### Static & Dynamic Analysis

1. **Execution and Process Discovery**

   - Launched the malware executable (`maltrack.exe`).  
   - Observed a process named `maltrack.exe` in Process Explorer with path:  
     `C:\Users\faguenouz\Documents\maltrack\maltrack.exe`.  
   - Identified parent/child relationships and working directory (`C:\Windows\system32`).

   **Screenshot:** `processexplore.png`

2. **Registry Persistence**

   - Using Process Monitor + Registry Editor, observed creation of a Run entry:  
     - Key: `HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Run`  
     - Name: `Mal-Track`  
     - Data: `C:\Users\faguenouz\Documents\maltrack\maltrack.exe`

   **Screenshot:** `registery.png`  
   **Screenshot:** `processmonitor.png`

3. **Network Activity and Attacker IP**

   - Captured traffic with Wireshark on the loopback interface.  
   - Observed repeated TCP connections to `127.0.0.1` (local C2 simulation for the lab).  
   - The project defines the attacker IP as `127.0.0.1`.

   **Screenshot:** `wireshark.png`  
   **Screenshot:** `vmnetwork.png`

4. **VM Isolation and Safety**

   - Verified no external internet connections from the VM.  
   - Confirmed host-only network configuration.

   **Screenshot:** `vmnetwork.png`  
   **Screenshot:** `vmsnapshot.png`

### Eradication Using the Python Tool

1. Ran the remover from an elevated PowerShell in the VM:

   ```powershell
   python .\main.py
   ```

2. When prompted `[Process Name / Name in Run]:`, entered:

   ```text
   maltrack
   ```

3. The tool:

   - Normalized `maltrack` and matched both `maltrack.exe` and registry name `Mal-Track`.  
   - Extracted attacker IPs (loopback packets → `127.0.0.1`).  
   - Removed the persistence entry:

     ```text
     [REG] Removed: HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Run → 'Mal-Track' = 'C:\Users\faguenouz\Documents\maltrack\maltrack.exe'
     ```

   - Killed the malware process and deleted the executable:

     ```text
     [PROC] Found target process: maltrack.exe (PID ...)
     [PROC] Killed parent maltrack.exe at C:\Users\faguenouz\Documents\maltrack\maltrack.exe
     ```

   - Skipped deletion of protected system directories (e.g. `C:\Windows\system32`), logging access denied safely.

   **Screenshot:** `outputoftheprog.png`

4. Verified eradication:

   - `maltrack.exe` no longer present in Process Explorer.  
   - `Mal-Track` entry removed from `HKCU\...\Run`.  
   - `C:\Users\faguenouz\Documents\maltrack\maltrack.exe` deleted.  
   - Program summary showed 1 process terminated, 1 registry persistence entry removed, and 2 paths cleaned.

---

## 3. Remediation & Recommendations

To prevent similar infections in a real environment:

- **System Hardening**
  - Enforce least privilege; avoid users with unnecessary admin rights.
  - Enable and maintain up‑to‑date endpoint protection (AV/EDR).
  - Restrict execution from user profile directories (e.g. `Downloads`, `Documents`) via AppLocker or similar.

- **Monitoring & Detection**
  - Monitor Run/RunOnce keys for suspicious entries pointing to user‑profile EXEs.
  - Flag unusual processes with names like `maltrack.exe` running from non‑standard locations.
  - Inspect loopback and unexpected outbound connections for C2 behavior (e.g. beaconing).

- **User Awareness**
  - Train users to avoid executing unknown binaries from email or web downloads.
  - Implement attachment scanning and sandboxing for suspicious executables.

- **Incident Response**
  - Maintain playbooks for:
    - Process isolation and termination.  
    - Persistence hunting (registry, startup folders, scheduled tasks).  
    - Safe acquisition of forensic artifacts (logs, memory, disk).

---

## 4. Malware Mitigation Report Email

```text
To: security@[organization].com
Subject: Malware Analysis Report: Mitigation of Mal-Track (Win32/Fynloski)

Dear Security Team,

I am writing to report the successful analysis and mitigation of the malware sample "Mal-Track", associated with the Win32/Fynloski family, identified during an educational malware analysis exercise.

Summary:
During execution, Mal-Track created a persistence mechanism by adding the following entry to the Windows startup registry:
- HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Run
  Name: Mal-Track
  Data: C:\Users\faguenouz\Documents\maltrack\maltrack.exe

The malware also ran as a process under the name "maltrack.exe", with its binary located in the user's Documents folder. Network analysis showed that the malware communicated over the loopback interface, using the IP address 127.0.0.1 as its command-and-control endpoint in this controlled lab environment.

Proof of Mitigation:
Using a custom Python-based remover, the following remediation steps were performed:

1. Registry Persistence Removal:
   - Deleted the startup entry:
     HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Run → 'Mal-Track' = 'C:\Users\faguenouz\Documents\maltrack\maltrack.exe'

2. Process Termination and File Deletion:
   - Identified and terminated the "maltrack.exe" process and its child processes.
   - Deleted the primary malware executable:
     C:\Users\faguenouz\Documents\maltrack\maltrack.exe

3. Validation:
   - Confirmed that "maltrack.exe" no longer appears in Task Manager / Process Explorer.
   - Verified that the "Mal-Track" registry entry is absent from all monitored Run/RunOnce locations.
   - Confirmed that the malware binary is no longer present on disk.

Attacker Information:
In this lab scenario, the malware communicated with the following IP address:
- 127.0.0.1

This represents the local loopback interface used as a simulated attacker endpoint for safe, isolated testing.

If you require further details, including tool output, screenshots (registry, process explorer, Wireshark), or code samples of the remover, I would be happy to provide them.

Best regards,
Aguenouz Fahd
Malware Analyst (Educational Lab)
[Contact Information]
```

---

## 5. Ethical Hacking Report

1. **Importance of a Controlled Environment**
   - All analysis was performed inside an isolated Windows VM with host-only networking.
   - Snapshots were used to revert the environment to a clean state after each test.
   - This isolation ensures the malware cannot escape to the host or the wider network.

2. **Legal and Ethical Boundaries**
   - The malware sample was used strictly for educational purposes as part of a structured lab.
   - No attempts were made to deploy or test the malware outside the controlled VM.
   - All actions focused on understanding, detecting, and removing malicious behavior, aligned with ethical hacking practices.

3. **Risks of Executing Malware Outside Isolation**
   - Running malware on a production or personal system can lead to data theft, system compromise, and legal consequences.
   - Malware can pivot to other devices on the network, escalate privileges, or exfiltrate sensitive information.
   - Proper isolation (VMs, sandboxes) and strict handling policies are mandatory when working with live samples.

---

You can drop this into `README.md` and adjust wording or add your actual screenshot paths (e.g. `![Process Explorer](resources (virus)/images/processexplore.png)` if your instructor allows images).

To check your understanding: based on this README and email, how would you verbally explain to a stakeholder *why* your tool’s summary output (registry keys removed, processes terminated, files deleted, IP found) is strong evidence that Mal-Track is fully eradicated from the VM?