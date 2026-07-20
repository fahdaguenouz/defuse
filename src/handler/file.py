from pathlib import Path
import os
import re
import stat

def remove_exe(path_str: str) -> bool:
    """Safely removes a specific file, bypassing Read-Only locks."""
    try:
        path = Path(path_str)

        if path.exists():
            if path.is_file():
                # Force Windows to remove the Read-Only attribute
                os.chmod(path, stat.S_IWRITE)
                os.remove(path)
                return True
            elif path.is_dir():
                print(f"[!] DANGER: Blocked generic attempt to delete directory: {path_str}")
                return False
    except PermissionError:
        print(f"[!] WARNING: Permission denied to remove {path_str}. It might be locked by another process.")
        return False
    except Exception as e:
        print(f"[!] WARNING: Failed to remove {path_str}: {e}")
        return False
        
    return False

def extract_strings(proc_path: str, min_length: int = 4) -> list:
    """Extracts human-readable strings from a binary file to find IPs."""
    try:
        with open(proc_path, "rb") as f:
            data = f.read()
            
        pattern = rb"[ -~]{%d,}" % min_length
        strings = re.findall(pattern, data)
        return [s.decode(errors="ignore") for s in strings]
    except PermissionError:
        print(f"[!] WARNING: Permission denied reading strings from {proc_path}. Run as Admin.")
        return []
    except Exception as e:
        print(f"[!] WARNING: Failed to read strings from {proc_path}: {e}")
        return []

def normalize_target(user_input: str) -> str:
    """Normalizes the target name for consistent matching."""
    s = user_input.strip().lower()
    
    # Strip .exe if present
    if s.endswith(".exe"):
        s = s[:-4]
        
    # Strip common punctuation used in registry keys
    s = s.replace("-", "")
    
    return s