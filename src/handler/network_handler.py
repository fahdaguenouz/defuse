import psutil
import re
from handler import file_handler
def get_remote_ips(p_name)->list:
    ips = set()

    for conn in psutil.net_connections():
        if conn.laddr:
            p = psutil.Process(conn.pid)
            if p.name() == p_name:
                ip = conn.laddr.ip
                ips.add(ip)

    return list(ips)

def find_ip_from_strings(name):
    for proc in psutil.process_iter(['pid', 'name']):
        try:
            proc_name = proc.info['name']

            if proc_name and proc_name.lower() == name.lower():

                
                if proc.is_running():
                    proc_path = proc.exe()
                    strings = file_handler.extract_strings(proc_path)
                    ips = find_ips(strings)
                    return ips
                    

        except psutil.NoSuchProcess:
            pass
        except psutil.AccessDenied:
            print(f"Access denied PID {proc.pid}")
        except Exception as e:
            print(f"Error: {e}")

    return None


def find_ips(string_list):
    ips=[]
    for s in string_list:
        ips.extend(re.findall(r"\b(?:\d{1,3}\.){3}\d{1,3}\b" , s))
    return list(set(ips))