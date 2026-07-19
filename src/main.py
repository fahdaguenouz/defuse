import ctypes
from handler.file import normalize_target
from handler import process as p
from handler import network as n
from handler import registry  as r

def is_admin():
    """Check if the script is running with elevated privileges on Windows."""
    try:
        return ctypes.windll.shell32.IsUserAnAdmin()
    except Exception:
        return False

def main():
    print("="*50)
    print("   Malware Analysis & Mitigation Tool (Defuse)   ")
    print("="*50)

    # Warn the user immediately if they lack the privileges to remove the malware
    if not is_admin():
        print("\n[!] CRITICAL WARNING: You are NOT running as Administrator.")
        print("    Registry editing, network scanning, and process termination")
        print("    will likely fail with 'Access Denied' errors.")
        print("    Please right-click your terminal and select 'Run as Administrator'.\n")

    raw = ""
    while True:
        raw = input("[?] Enter the target [Process Name / Name in Run]: ")
        if raw.strip():
            break

    target = normalize_target(raw)
    print(f"\n[*] Normalized target: {target}")

    # 1. Network Extraction
    print("\n[*] Collecting attacker IPs...")
    ip = n.get_remote_ips(target)
    if not ip:
        print("    - No live connections found. Scraping binary strings...")
        ip = n.find_ip_from_strings(target) or ["127.0.0.1"]  # Safe fallback for lab
    print(f"    -> Identified IPs: {ip}")

    # 2. Registry & Startup Cleanup
    print("\n[*] Removing persistence from registry & startup folders...")
    removed_keys = r.remove_from_registry(target)

    # 3. Process Termination & File Deletion
    print("\n[*] Killing processes and deleting binaries...")
    removed_procs, removed_paths = p.kill_by_name(target)

    # 4. Final Report
    print("\n" + "="*50)
    print("                MITIGATION SUMMARY                ")
    print("="*50)
    print(f"  [+] Attacker IPs         : {ip}")
    
    print(f"  [+] Persistence removed  : {len(removed_keys)}")
    for k in removed_keys:
        print(f"      - {k}")
        
    print(f"  [+] Processes terminated : {len(removed_procs)}")
    for pn in set(removed_procs):  # Use set to avoid printing duplicate child names
        print(f"      - {pn}")
        
    print(f"  [+] Files removed        : {len(removed_paths)}")
    for path in set(removed_paths):
        print(f"      - {path}")
        
    print("="*50 + "\n")

if __name__ == "__main__":
    main()