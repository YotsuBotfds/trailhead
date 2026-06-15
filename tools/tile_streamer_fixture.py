#!/usr/bin/env python3
import os
import json
import subprocess
import sys
from pathlib import Path

WORKER_COUNTS = (1, 2, 8)
RESULT_PREFIX = "tile_streamer_fixture_result="


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    godot_bin = os.environ.get("GODOT_BIN", "/Applications/Godot.app/Contents/MacOS/Godot")
    results = []

    for worker_count in WORKER_COUNTS:
        command = [
            godot_bin,
            "--headless",
            "--fixed-fps",
            "120",
            "--path",
            str(root),
            "res://tools/tile_streamer_fixture.tscn",
            "--",
            f"--tile-streamer-workers={worker_count}",
        ]
        completed = subprocess.run(command, cwd=root, text=True, capture_output=True)
        sys.stdout.write(completed.stdout)
        sys.stderr.write(completed.stderr)
        if completed.returncode != 0:
            return completed.returncode
        result = parse_result(completed.stdout, worker_count)
        if result is None:
            print(f"error: missing TileStreamer fixture result for worker_count={worker_count}", file=sys.stderr)
            return 1
        results.append(result)

    baseline = results[0]
    for result in results[1:]:
        if result["activation_order"] != baseline["activation_order"]:
            print(
                "error: activation order differs for "
                f"worker_count={result['worker_count']}",
                file=sys.stderr,
            )
            return 1
        if result["activation_ticks"] != baseline["activation_ticks"]:
            print(
                "error: activation ticks differ for "
                f"worker_count={result['worker_count']}",
                file=sys.stderr,
            )
            return 1

    print("ok: TileStreamer worker-count determinism for 1/2/8 workers")
    return 0


def parse_result(stdout: str, worker_count: int) -> dict | None:
    for line in stdout.splitlines():
        if line.startswith(RESULT_PREFIX):
            result = json.loads(line[len(RESULT_PREFIX) :])
            if result.get("worker_count") != worker_count:
                raise ValueError(
                    f"result worker_count {result.get('worker_count')} != expected {worker_count}"
                )
            return result
    return None


if __name__ == "__main__":
    sys.exit(main())
