import psutil
from handler import file_handler
from handler.file_handler import normalize_target

def kill_by_name(name: str):
    target = normalize_target(name)
    removed = []          # process names
    removed_paths = []    # file/dir paths

    for proc in psutil.process_iter(['pid', 'name']):
        try:
            proc_name = proc.info['name'] or ""
            proc_name_l = proc_name.lower()

            proc_base = proc_name_l
            if proc_base.endswith(".exe"):
                proc_base = proc_base[:-4]
            proc_base = proc_base.replace("-", "")

            if proc_base == target or target in proc_base:
                print(f"[PROC] Found target process: {proc_name} (PID {proc.pid})")

                # CHILDREN FIRST
                children = proc.children(recursive=True)
                for child in children:
                    try:
                        child_name = child.name()
                        child_path = child.exe()

                        if child.is_running():
                            child.kill()
                            child.wait(timeout=3)
                            file_handler.remove_exe(child_path)
                            removed.append(child_name)
                            removed_paths.append(child_path)
                            print(f"[PROC] Killed child {child_name} at {child_path}")
                    except Exception as e:
                        print(f"[PROC] Child error: {e}")

                # PARENT
                parent_path = proc.exe()
                current_dir = proc.cwd()
                if proc.is_running():
                    proc.kill()
                    proc.wait(timeout=3)
                    file_handler.remove_exe(parent_path)
                    removed.append(proc_name)
                    removed_paths.append(parent_path)
                    print(f"[PROC] Killed parent {proc_name} at {parent_path}")

                file_handler.remove_exe(current_dir)
                removed_paths.append(current_dir)
                print(f"[PROC] Removed working directory {current_dir}")

        except psutil.NoSuchProcess:
            pass
        except psutil.AccessDenied:
            print(f"[PROC] Access denied PID {proc.pid}")
        except Exception as e:
            print(f"[PROC] Error: {e}")

    return removed, removed_paths
    target = normalize_target(name)  # e.g. "Mal-Track" → "maltrack"
    removed = []

    for proc in psutil.process_iter(['pid', 'name']):
        try:
            proc_name = proc.info['name'] or ""
            proc_name_l = proc_name.lower()

            proc_base = proc_name_l
            if proc_base.endswith(".exe"):
                proc_base = proc_base[:-4]
            proc_base = proc_base.replace("-", "")

            # match normalized base names
            if proc_base == target or target in proc_base:
                # CHILDREN FIRST
                children = proc.children(recursive=True)
                for child in children:
                    try:
                        child_name = child.name()
                        child_path = child.exe()

                        if child.is_running():
                            child.kill()
                            child.wait(timeout=3)
                            file_handler.remove_exe(child_path)
                            removed.append(child_name)
                    except Exception as e:
                        print(f"Child error: {e}")

                # PARENT
                parent_path = proc.exe()
                current_dir = proc.cwd()
                if proc.is_running():
                    proc.kill()
                    proc.wait(timeout=3)
                    file_handler.remove_exe(parent_path)
                    removed.append(proc_name)

                file_handler.remove_exe(current_dir)

        except psutil.NoSuchProcess:
            pass
        except psutil.AccessDenied:
            print(f"Access denied PID {proc.pid}")
        except Exception as e:
            print(f"Error: {e}")

    return removed