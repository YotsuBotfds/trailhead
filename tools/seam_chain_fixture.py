#!/usr/bin/env python3
import json
import math
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GODOT_BIN = os.environ.get("GODOT_BIN", "/Applications/Godot.app/Contents/MacOS/Godot")
OUT_DIR = ROOT / os.environ.get("OUT_DIR", "tests/out")

FULL_REPLAY = "tests/golden/cedar_hollow_segment_pine_floor_to_far_mile_marker_replay.json"
CHAIN_REPLAY = "tests/golden/cedar_hollow_segment_pine_floor_to_far_mile_marker_chain.json"
ROUTE_SEGMENT = "pine_floor_to_far_mile_marker"

POSITION_TOLERANCE_M = 0.08
VELOCITY_TOLERANCE_MPS = 0.25
SPEED_TOLERANCE_MPS = 0.20


def main() -> int:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    full_out = OUT_DIR / "seam_chain_full.json"
    chain_out = OUT_DIR / "seam_chain_chain.json"

    full_result = run_sim(full_out, FULL_REPLAY, 4000)
    if full_result != 0:
        return full_result
    chain_result = run_sim(chain_out, CHAIN_REPLAY, 1000)
    if chain_result != 0:
        return chain_result

    full = load_json(full_out)
    chain = load_json(chain_out)
    fixture = load_json(ROOT / CHAIN_REPLAY)

    errors = []
    for label, data in [("full", full), ("chain", chain)]:
        if data.get("result") != "pass":
            errors.append(f"{label} run result is {data.get('result')!r}, expected 'pass'")

    split_tick = int(fixture.get("chain_split_tick", -1))
    if split_tick < 0:
        errors.append(f"{CHAIN_REPLAY} missing non-negative chain_split_tick")
        split_tick = 0

    chain_tick = int(chain.get("ticks", -1))
    if chain_tick < 0:
        errors.append("chain output missing non-negative ticks")
        chain_tick = 0

    full_row = row_for_tick(full, split_tick + chain_tick, "full", errors)
    chain_row = row_for_tick(chain, chain_tick, "chain", errors)
    if errors:
        return report_failures(errors)

    position_delta = vector_distance(full_row["position"], chain_row["position"])
    velocity_delta = vector_distance(full_row["linear_velocity"], chain_row["linear_velocity"])
    speed_delta = abs(float(full_row["speed"]) - float(chain_row["speed"]))

    if position_delta > POSITION_TOLERANCE_M:
        errors.append(
            f"position delta {position_delta:.9f} > {POSITION_TOLERANCE_M:.3f} m"
        )
    if velocity_delta > VELOCITY_TOLERANCE_MPS:
        errors.append(
            f"velocity delta {velocity_delta:.9f} > {VELOCITY_TOLERANCE_MPS:.3f} m/s"
        )
    if speed_delta > SPEED_TOLERANCE_MPS:
        errors.append(f"speed delta {speed_delta:.9f} > {SPEED_TOLERANCE_MPS:.3f} m/s")

    if errors:
        return report_failures(errors)

    print(
        "ok: seam chain final-state deltas "
        f"position={position_delta:.9f}m "
        f"velocity={velocity_delta:.9f}m/s "
        f"speed={speed_delta:.9f}m/s"
    )
    return 0


def run_sim(out_path: Path, replay_path: str, max_ticks: int) -> int:
    command = [
        GODOT_BIN,
        "--headless",
        "--fixed-fps",
        "120",
        "--path",
        str(ROOT),
        "res://scenes/sim_runner.tscn",
        "--",
        "--scene=cedar_hollow",
        "--controller=replay",
        f"--replay={replay_path}",
        f"--route-segment={ROUTE_SEGMENT}",
        "--seed=12345",
        f"--max-ticks={max_ticks}",
        "--stuck-window=120",
        "--stuck-min-progress=0.015",
        f"--out={out_path}",
    ]
    print(f"run: {out_path}")
    completed = subprocess.run(command, cwd=ROOT, text=True, capture_output=True)
    sys.stdout.write(completed.stdout)
    sys.stderr.write(completed.stderr)
    if completed.returncode != 0:
        print(
            f"error: SimRunner failed for {replay_path} with exit {completed.returncode}",
            file=sys.stderr,
        )
    return completed.returncode


def load_json(path: Path) -> dict:
    return json.loads(path.read_text())


def row_for_tick(data: dict, tick: int, label: str, errors: list[str]) -> dict:
    telemetry = data.get("telemetry", [])
    if not isinstance(telemetry, list):
        errors.append(f"{label} telemetry is not an array")
        return {}
    for row in telemetry:
        if isinstance(row, dict) and int(row.get("tick", -1)) == tick:
            return row
    errors.append(f"{label} telemetry missing tick {tick}")
    return {}


def vector_distance(left: list[float], right: list[float]) -> float:
    return math.sqrt(sum((float(a) - float(b)) ** 2.0 for a, b in zip(left, right)))


def report_failures(errors: list[str]) -> int:
    print("fail: seam chain final-state comparison", file=sys.stderr)
    for error in errors:
        print(f"- {error}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
