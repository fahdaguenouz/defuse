import winreg
import os

# Most common persistence registry keys
PERSISTENCE_KEYS = [
    (r"SOFTWARE\Microsoft\Windows\CurrentVersion\Run",       winreg.HKEY_CURRENT_USER,  "HKCU Run"),
    (r"SOFTWARE\Microsoft\Windows\CurrentVersion\Run",       winreg.HKEY_LOCAL_MACHINE, "HKLM Run"),
    (r"SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce",   winreg.HKEY_CURRENT_USER,  "HKCU RunOnce"),
    (r"SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce",   winreg.HKEY_LOCAL_MACHINE, "HKLM RunOnce"),
    (r"SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run", winreg.HKEY_LOCAL_MACHINE, "HKLM Run (32bit)"),
]

def _hive_label(hive):
    return "HKCU" if hive == winreg.HKEY_CURRENT_USER else "HKLM"

def remove_from_registry(name: str) -> list:
    removed = []

    # 1. Sweep Registry Keys
    for path, hive, label in PERSISTENCE_KEYS:
        try:
            flags = winreg.KEY_READ | winreg.KEY_SET_VALUE
            key = winreg.OpenKey(hive, path, 0, flags)

            to_del = []
            i = 0
            while True:
                try:
                    entry_name, value, _ = winreg.EnumValue(key, i)
                    
                    # Safely cast 'value' to string. If the registry value is a REG_DWORD 
                    # (integer) or binary, calling .lower() on it would crash the script.
                    value_str = str(value)
                    
                    if (name.lower() in entry_name.lower() or
                        name.lower() in value_str.lower()):
                        to_del.append((entry_name, value_str))
                    i += 1
                except OSError:
                    # No more values in this key
                    break

            for entry_name, value_str in to_del:
                label_str = f"{_hive_label(hive)}\\{path} → '{entry_name}' = '{value_str}'"
                try:
                    winreg.DeleteValue(key, entry_name)
                    removed.append(label_str)
                    print(f"[REG] Removed: {label_str}")
                except PermissionError:
                    print(f"[!] WARNING: Permission denied to delete registry value '{entry_name}'. Run as Admin.")

            winreg.CloseKey(key)

        except PermissionError:
            print(f"[!] WARNING: Permission denied accessing {_hive_label(hive)}\\{path}. Run as Admin.")
        except FileNotFoundError:
            # Key doesn't exist, which is normal. Move on.
            pass
        except Exception as e:
            print(f"[!] WARNING: Unexpected error reading registry key {_hive_label(hive)}\\{path}: {e}")

    # 2. Sweep Windows Startup Folders (To fully satisfy project requirements)
    user_startup = os.path.join(os.environ.get('APPDATA', ''), r"Microsoft\Windows\Start Menu\Programs\Startup")
    all_users_startup = os.path.join(os.environ.get('PROGRAMDATA', ''), r"Microsoft\Windows\Start Menu\Programs\StartUp")

    for startup_path in [user_startup, all_users_startup]:
        if os.path.exists(startup_path):
            try:
                for item in os.listdir(startup_path):
                    if name.lower() in item.lower():
                        full_path = os.path.join(startup_path, item)
                        
                        # Safety check: Only delete files, never directories
                        if os.path.isfile(full_path):
                            try:
                                os.remove(full_path)
                                removed_label = f"Startup Folder File → {full_path}"
                                removed.append(removed_label)
                                print(f"[STARTUP] Removed file: {full_path}")
                            except PermissionError:
                                print(f"[!] WARNING: Permission denied to delete startup file {full_path}. Run as Admin.")
            except PermissionError:
                print(f"[!] WARNING: Permission denied reading directory {startup_path}.")
            except Exception as e:
                print(f"[!] WARNING: Unexpected error reading startup folder {startup_path}: {e}")

    return removed