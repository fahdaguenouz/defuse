
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

    for path , hive,label in PERSISTENCE_KEYS:
        try:
            flags = winreg.KEY_READ | winreg.KEY_SET_VALUE
            key   = winreg.OpenKey(hive, path, 0, flags)

            to_del = []
            i = 0
            while True:
                try:
                    entry_name, value, _ = winreg.EnumValue(key, i)
                    if (name.lower() in entry_name.lower() or
                        name.lower() in value):
                        to_del.append((entry_name, value))
                    i += 1
                except OSError:
                    break
            for entry_name, value in to_del:
                label = f"{_hive_label(hive)}\\...\\Run → '{entry_name}'"
                winreg.DeleteValue(key, entry_name)
                removed.append(label)
                print(f"  [OK] Supprimé : {label}")

            winreg.CloseKey(key)

        except PermissionError:
            print(f"  [!] Permission refusée sur {_hive_label(hive)}\\{path.split(chr(92))[-1]}")
            print(      "      → relance le script en Administrateur")
        except FileNotFoundError:
            pass

    return removed