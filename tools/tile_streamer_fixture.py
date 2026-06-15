#!/usr/bin/env python3
import os
import subprocess
import sys
from pathlib import Path


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
        "res://tools/tile_streamer_fixture.tscn",
    ]
    return subprocess.run(command, cwd=root).returncode


if __name__ == "__main__":
    sys.exit(main())
