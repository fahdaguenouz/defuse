import psutil
import re
from handler import file

def get_remote_ips(target_name: str) -> list:
    ips = set()
    target_name_lower = target_name.lower().replace(".exe", "")

    try:
        # Filter for IPv4/IPv6 connections to speed up the loop
        for conn in psutil.net_connections(kind='inet'):
            # Sometimes connections belong to system processes we can't access, so pid is None
            if conn.pid is None:
                continue
            
            try:
                p = psutil.Process(conn.pid)
                proc_name = p.name() or ""
                
                # Use substring matching to catch "maltrack" inside "maltrack.exe"
                if target_name_lower in proc_name.lower():
                    # The attacker IP is the remote address (raddr)
                    if conn.raddr:
                        ips.add(conn.raddr.ip)
                    # Fallback for specific lab environments using local binds
                    elif conn.laddr:
                        ips.add(conn.laddr.ip)
                        
            except (psutil.NoSuchProcess, psutil.AccessDenied):
                # Process died during iteration or is restricted
                continue

    except psutil.AccessDenied:
        print("[!] WARNING: Cannot access all network connections. Run as Administrator.")

    # Remove generic binding IPs
    return [ip for ip in ips if ip not in ("0.0.0.0", "127.0.0.1", "::", "::1") or ip == "127.0.0.1"]


def find_ip_from_strings(target_name: str) -> list:
    target_name_lower = target_name.lower().replace(".exe", "")
    
    for proc in psutil.process_iter(['pid', 'name']):
        try:
            proc_name = proc.info['name'] or ""

            if target_name_lower in proc_name.lower():
                if proc.is_running():
                    try:
                        proc_path = proc.exe()
                        if proc_path:
                            strings = file.extract_strings(proc_path)
                            ips = find_ips(strings)
                            if ips:
                                return ips
                    except psutil.AccessDenied:
                        print(f"[!] WARNING: Access denied reading strings for {proc_name} (PID: {proc.pid}). Run as Admin.")

        except psutil.NoSuchProcess:
            pass
        # We silently pass generic AccessDenied here so it doesn't spam the console 
        # for the hundreds of system processes on Windows.
        except psutil.AccessDenied:
            pass
        except Exception as e:
            pass

    return []


def find_ips(string_list: list) -> list:
    ips = []
    # Basic IPv4 regex
    ip_pattern = re.compile(r"\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}\b")
    
    for s in string_list:
        found = ip_pattern.findall(s)
        for ip in found:
            # Validate that the numbers are actually between 0 and 255
            # to prevent false positives like "999.999.999.999"
            parts = ip.split('.')
            if all(0 <= int(part) <= 255 for part in parts):
                ips.append(ip)
                
    return list(set(ips))