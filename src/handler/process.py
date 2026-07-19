import psutil
import os
from handler import file
from handler.file import normalize_target

def kill_by_name(name: str):
    target = normalize_target(name)
    removed = []          # process names
    removed_paths = []    # file paths

    for proc in psutil.process_iter(['pid', 'name']):
        try:
            proc_name = proc.info['name'] or ""
            proc_name_l = proc_name.lower()

            proc_base = proc_name_l
            if proc_base.endswith(".exe"):
                proc_base = proc_base[:-4]
            proc_base = proc_base.replace("-", "")

            # Match normalized base names
            if proc_base == target or target in proc_base:
                print(f"\n[+] Found target process: {proc_name} (PID: {proc.pid})")

                # 1. KILL CHILDREN FIRST
                children = proc.children(recursive=True)
                for child in children:
                    try:
                        child_name = child.name()
                        
                        # Safely try to get the executable path
                        try:
                            child_path = child.exe()
                        except psutil.AccessDenied:
                            child_path = None
                            print(f"[!] WARNING: Cannot access path for child {child_name}. Run as Admin.")

                        if child.is_running():
                            child.kill()
                            child.wait(timeout=3)
                            print(f"    - Killed child: {child_name} (PID: {child.pid})")
                            removed.append(child_name)
                            
                            # Only delete if it's a specific file, NEVER a directory
                            if child_path and os.path.isfile(child_path):
                                file.remove_exe(child_path)
                                removed_paths.append(child_path)
                                print(f"    - Deleted child executable: {child_path}")

                    except psutil.AccessDenied:
                        print(f"[!] WARNING: Access denied to kill child {child_name}.")
                    except Exception as e:
                        print(f"[!] Child error: {e}")

                # 2. KILL PARENT
                try:
                    parent_path = proc.exe()
                except psutil.AccessDenied:
                    parent_path = None
                    print(f"[!] WARNING: Cannot access path for {proc_name}. Run as Admin.")

                if proc.is_running():
                    proc.kill()
                    proc.wait(timeout=3)
                    print(f"    - Killed parent: {proc_name} (PID: {proc.pid})")
                    removed.append(proc_name)
                    
                    # Only delete if it's a specific file, NEVER a directory
                    if parent_path and os.path.isfile(parent_path):
                        file.remove_exe(parent_path)
                        removed_paths.append(parent_path)
                        print(f"    - Deleted parent executable: {parent_path}")

        except psutil.NoSuchProcess:
            pass
        except psutil.AccessDenied:
            # We don't print on every single AccessDenied in process_iter to avoid console spam,
            # but if it fails on our target, it's handled above.
            pass
        except Exception as e:
            print(f"[!] Unexpected error on PID {proc.pid}: {e}")

    return removed, removed_paths