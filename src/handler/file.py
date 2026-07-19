from pathlib import Path
import os
import re

def remove_exe(path_str: str):
    """Safely removes a specific file. Strictly refuses to delete directories."""
    try:
        path = Path(path_str)

        if path.exists():
            if path.is_file():
                os.remove(path)
            elif path.is_dir():
                print(f"[!] DANGER: Blocked attempt to delete an entire directory: {path_str}")
                print("    Only individual executable files should be targeted.")
    except PermissionError:
        print(f"[!] WARNING: Permission denied to remove {path_str}. Run as Admin.")
    except Exception as e:
        print(f"[!] WARNING: Failed to remove {path_str}: {e}")

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