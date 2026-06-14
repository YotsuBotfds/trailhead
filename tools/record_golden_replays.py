#!/usr/bin/env python3
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "tests" / "out"
GOLDEN_DIR = ROOT / "tests" / "golden"

GOLDENS = [
    ("flat_target", "flat_target.json", "flat_target_replay.json"),
    ("flat_flipped", "flat_flipped.json", "flat_flipped_replay.json"),
    ("cedar_hollow_old_cedar", "cedar_hollow_old_cedar.json", "cedar_hollow_old_cedar_replay.json"),
    (
        "cedar_hollow_segment_trailhead_to_culvert_mouth",
        "cedar_hollow_segment_trailhead_to_culvert_mouth.json",
        "cedar_hollow_segment_trailhead_to_culvert_mouth_replay.json",
    ),
    (
        "cedar_hollow_segment_overlook_to_old_cedar",
        "cedar_hollow_segment_overlook_to_old_cedar.json",
        "cedar_hollow_segment_overlook_to_old_cedar_replay.json",
    ),
]


def input_from_row(row):
    data = row["input"]
    return {
        "throttle": float(data.get("throttle", 0.0)),
        "steer": float(data.get("steer", 0.0)),
        "brake": float(data.get("brake", 0.0)),
        "ebrake": bool(data.get("ebrake", False)),
        "self_right": bool(data.get("self_right", False)),
    }


def build_replay(name, source_path):
    data = json.loads(source_path.read_text())
    if data.get("result") != "pass":
        raise SystemExit(f"cannot record failing run for {name}: {source_path}")
    telemetry = data.get("telemetry", [])
    if len(telemetry) < 2:
        raise SystemExit(f"not enough telemetry rows for {name}: {source_path}")
    return {
        "format": "trailhead_replay_v1",
        "name": name,
        "source": str(source_path.relative_to(ROOT)),
        "scene": data.get("scene", ""),
        "controller": data.get("controller", ""),
        "scenario": data.get("scenario", ""),
        "route_segment": data.get("route_segment", ""),
        "spawn": data.get("spawn", ""),
        "target": data.get("target", ""),
        "seed": int(data.get("seed", 0)),
        "ticks": int(data.get("ticks", 0)),
        "inputs": [input_from_row(row) for row in telemetry[1:]],
    }


def main():
    GOLDEN_DIR.mkdir(parents=True, exist_ok=True)
    for name, source_name, output_name in GOLDENS:
        source_path = OUT_DIR / source_name
        if not source_path.exists():
            raise SystemExit(f"missing source run for {name}: {source_path}")
        replay = build_replay(name, source_path)
        output_path = GOLDEN_DIR / output_name
        output_path.write_text(json.dumps(replay, indent="\t") + "\n")
        print(f"wrote: {output_path.relative_to(ROOT)} ({len(replay['inputs'])} inputs)")


if __name__ == "__main__":
    main()
