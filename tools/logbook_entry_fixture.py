#!/usr/bin/env python3
"""Run the GL-2a LogbookSystem headless fixture."""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
GODOT_BIN = os.environ.get("GODOT_BIN", "/Applications/Godot.app/Contents/MacOS/Godot")
SUCCESS_LINE = "ok: logbook entry fixture"


def main() -> int:
    command = [
        GODOT_BIN,
        "--headless",
        "--fixed-fps",
        "120",
        "--path",
        str(ROOT),
        "res://tools/logbook_entry_fixture.tscn",
    ]
    completed = subprocess.run(
        command,
        cwd=ROOT,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    output = completed.stdout
    sys.stdout.write(output)
    if completed.returncode != 0:
        return int(completed.returncode)
    if "SCRIPT ERROR:" in output or "\nERROR:" in output or output.startswith("ERROR:"):
        return 1
    if SUCCESS_LINE not in output:
        print("fail: logbook entry fixture did not report success", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
