"""Reads KEY=VALUE lines from a .env file into the environment. Variables that are already set win. Standard library only."""
import os
import re
from pathlib import Path


def load_env(path=None):
    """Load ./.env (or the one next to the package). Blank values are skipped, so `KEY=` lines in .env.example do nothing."""
    files = [Path(path)] if path else [Path.cwd() / ".env", Path(__file__).resolve().parent.parent / ".env"]
    for f in files:
        if not f.is_file():
            continue
        for line in f.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, _, val = line.partition("=")
            key = key.strip()
            if key.startswith("export "):
                key = key[len("export "):].strip()
            val = val.strip()
            if len(val) > 1 and val[0] in "\"'" and val[-1] == val[0]:
                val = val[1:-1]
            else:
                val = re.split(r"(?:^|\s)#", val, maxsplit=1)[0].strip()   # a trailing comment, or a value that is only a comment
            if key and val and key not in os.environ:
                os.environ[key] = val
        return f
    return None
