#!/usr/bin/env python3
import os
import subprocess
import sys
from pathlib import Path


SUCCESS_LINE = "ok: recover proximity fixture"


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    godot_bin = os.environ.get("GODOT_BIN", "/Applications/Godot.app/Contents/MacOS/Godot")
    command = [
        godot_bin,
        "--headless",
        "--fixed-fps",
        "120",
        "--path",
        str(root),
        "res://tools/recover_proximity_fixture.tscn",
    ]
    completed = subprocess.run(
        command,
        cwd=root,
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
        print("fail: recover proximity fixture did not report success", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
