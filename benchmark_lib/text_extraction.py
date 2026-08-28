import re
from pathlib import Path

def read_text_file_or_empty(file_path):
    try:
        return Path(file_path).read_text(errors="replace")
    except OSError:
        return ""

def first_float_matching(text, pattern, flags=0):
    match = re.search(pattern, text, flags)
    return float(match.group(1)) if match else None

def first_integer_matching(text, pattern, flags=0):
    match = re.search(pattern, text, flags)
    return int(match.group(1)) if match else None

def first_string_matching(text, pattern, flags=0):
    match = re.search(pattern, text, flags)
    return match.group(1) if match else None

def last_integer_matching(text, pattern, flags=re.MULTILINE):
    matches = re.findall(pattern, text, flags)
    return int(matches[-1]) if matches else None

def last_float_matching(text, pattern, flags=re.MULTILINE):
    matches = re.findall(pattern, text, flags)
    return float(matches[-1]) if matches else None
