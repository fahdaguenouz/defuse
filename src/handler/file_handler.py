from pathlib import Path
import os
import shutil
import re
def remove_exe(path_str):
    try:
        path = Path(path_str)

        if path.exists() and path.is_file():
            os.remove(path)
        elif  path.exists() and path.is_dir():
            shutil.rmtree(path)
    except Exception as e:
        print(f"Failed to remove {path_str}: {e}")


def extract_strings(proc_path,min_length=4):
    with open(proc_path,"rb") as f:
                        data = f.read()
    pattern = rb"[ -~]{%d,}"%min_length
    strings = re.findall(pattern , data)
    return [s.decode(errors= "ignore") for s in strings]

def normalize_target(user_input: str) -> str:
    s = user_input.strip().lower()
    # strip .exe if present
    if s.endswith(".exe"):
        s = s[:-4]
    # strip common punctuation used in registry keys
    s = s.replace("-", "")
    return s