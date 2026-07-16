from handler.file_handler import normalize_target
from handler import process_handler as p
from handler import network_handler as n
from handler import registry_handler as r

raw = ""
while True:
    raw = input("[Process Name / Name in Run]: ")
    if raw.strip():
        break

target = normalize_target(raw)
print(f"\n[+] Normalized target: {target}")

print("[+] Collecting attacker IPs...")
ip = n.get_remote_ips(target)
if not ip:
    ip = n.find_ip_from_strings(target) or ["127.0.0.1"]  # safe fallback for lab

print("[+] Removing persistence from registry...")
removed_keys = r.remove_from_registry(target)

print("[+] Killing processes and deleting binaries...")
removed_procs, removed_paths = p.kill_by_name(target)

print("\n=== Mitigation Summary ===")
print(f"  - Attacker IPs: {ip}")
print(f"  - Registry entries removed: {len(removed_keys)}")
for k in removed_keys:
    print(f"    * {k}")
print(f"  - Processes terminated: {len(removed_procs)}")
for pn in removed_procs:
    print(f"    * {pn}")
print(f"  - Files / directories removed: {len(removed_paths)}")
for path in removed_paths:
    print(f"    * {path}")