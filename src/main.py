from handler import process_handler as p 
from handler import network_handler as n 
from handler import registry_handler as r
from  handler import file_handler as f


target=""
while True:
    target = input("[Process Name]: ")
    if target.strip():
        break
ip= n.get_remote_ips(target)
if  not ip:
    ip = n.find_ip_from_strings(target)
    
r.remove_from_registry(target)
p.kill_by_name(target)
print(f"Attacker ip : {ip}")


