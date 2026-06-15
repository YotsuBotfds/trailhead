#!/usr/bin/env python3
"""Run the GL-1b recoverable-object render subscriber headless fixture."""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
GODOT_BIN = os.environ.get("GODOT_BIN", "/Applications/Godot.app/Contents/MacOS/Godot")
SUCCESS_LINE = "ok: RecoverableObjectRender tags placeholder visual state without sim writes"


def main() -> int:
    command = [
        GODOT_BIN,
        "--headless",
        "--path",
        str(ROOT),
        "res://tools/recoverable_render_fixture.tscn",
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
        print("fail: recoverable render fixture did not report success", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
