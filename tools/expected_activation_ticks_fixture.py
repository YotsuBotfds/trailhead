#!/usr/bin/env python3
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_FIXTURE_PATH = ROOT / "tests" / "golden" / "tile_streamer_activation_ticks.json"
RESULT_PREFIX = "tile_streamer_fixture_result="


def main() -> int:
    fixture_path = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_FIXTURE_PATH
    if not fixture_path.is_absolute():
        fixture_path = ROOT / fixture_path
    fixture = json.loads(fixture_path.read_text())
    expected = fixture.get("expected_activation_ticks", {})
    if not isinstance(expected, dict) or not expected:
        print(f"error: {fixture_path} missing expected_activation_ticks", file=sys.stderr)
        return 1
    expected_worker_counts = expected_worker_count_set(fixture)

    completed = subprocess.run(
        [sys.executable, "tools/tile_streamer_fixture.py"],
        cwd=ROOT,
        text=True,
        capture_output=True,
    )
    sys.stdout.write(completed.stdout)
    sys.stderr.write(completed.stderr)
    if completed.returncode != 0:
        return completed.returncode

    results = parse_results(completed.stdout)
    if not results:
        print("error: no tile_streamer_fixture_result lines found", file=sys.stderr)
        return 1

    failed = False
    compared = 0
    for result in results:
        worker_count = int(result.get("worker_count", 0))
        if expected_worker_counts and worker_count not in expected_worker_counts:
            continue
        compared += 1
        actual = result.get("activation_ticks", {})
        if actual != expected:
            failed = True
            print(
                f"error: activation ticks differ for worker_count={worker_count}",
                file=sys.stderr,
            )
            print(diff_activation_ticks(expected, actual), file=sys.stderr)

    if failed:
        return 1
    if compared <= 0:
        print("error: no TileStreamer runs matched fixture worker_counts", file=sys.stderr)
        return 1
    print(f"ok: expected_activation_ticks matched for {compared} TileStreamer runs")
    return 0


def parse_results(stdout: str) -> list[dict]:
    results = []
    for line in stdout.splitlines():
        if line.startswith(RESULT_PREFIX):
            results.append(json.loads(line[len(RESULT_PREFIX) :]))
    return results


def expected_worker_count_set(fixture: dict) -> set[int]:
    worker_counts = fixture.get("worker_counts", [])
    if not isinstance(worker_counts, list):
        return set()
    out = set()
    for value in worker_counts:
        try:
            out.add(int(value))
        except (TypeError, ValueError):
            continue
    return out


def diff_activation_ticks(expected: dict, actual: dict) -> str:
    lines = []
    for key in sorted(set(expected) | set(actual)):
        if key not in expected:
            lines.append(f"- unexpected {key}: {actual[key]}")
        elif key not in actual:
            lines.append(f"- missing {key}: expected {expected[key]}")
        elif actual[key] != expected[key]:
            lines.append(f"- {key}: expected {expected[key]}, got {actual[key]}")
    return "\n".join(lines)


if __name__ == "__main__":
    sys.exit(main())
