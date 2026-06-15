#!/usr/bin/env python3
"""Run the GL-1c photo stationary fixture in headless Godot."""

import os
import pathlib
import subprocess
import sys


ROOT = pathlib.Path(__file__).resolve().parents[1]
GODOT_BIN = os.environ.get("GODOT_BIN", "/Applications/Godot.app/Contents/MacOS/Godot")


def main() -> int:
    cmd = [
        GODOT_BIN,
        "--headless",
        "--path",
        str(ROOT),
        "res://tools/photo_stationary_fixture.tscn",
    ]
    return subprocess.run(cmd, cwd=ROOT, check=False).returncode


if __name__ == "__main__":
    sys.exit(main())
