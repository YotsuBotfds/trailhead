#!/usr/bin/env python3
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "tests" / "out"
GOLDEN_DIR = ROOT / "tests" / "golden"
SAMPLE_STRIDE = 10
TOLERANCES = {
    "ticks": 2,
    "position_m": 0.08,
    "velocity_mps": 0.25,
    "speed_mps": 0.20,
    "slip_deg": 2.0,
    "surface_ticks": 2,
    "event_counts": 0,
    "motor_rpm": 10.0,
}

GOLDENS = [
    ("flat_target", "flat_target.json", "flat_target_replay.json"),
    ("flat_flipped", "flat_flipped.json", "flat_flipped_replay.json"),
    ("cedar_hollow_old_cedar", "cedar_hollow_old_cedar.json", "cedar_hollow_old_cedar_replay.json"),
    ("cedar_hollow_overlook_ridge", "cedar_hollow_overlook_ridge.json", "cedar_hollow_overlook_ridge_replay.json"),
    ("cedar_hollow_bog_bottom", "cedar_hollow_bog_bottom.json", "cedar_hollow_bog_bottom_replay.json"),
    ("cedar_hollow_the_crossing", "cedar_hollow_the_crossing.json", "cedar_hollow_the_crossing_replay.json"),
    ("cedar_hollow_boardwalk_end", "cedar_hollow_boardwalk_end.json", "cedar_hollow_boardwalk_end_replay.json"),
    ("cedar_hollow_culvert_mouth", "cedar_hollow_culvert_mouth.json", "cedar_hollow_culvert_mouth_replay.json"),
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


def sample_from_row(row):
    return {
        "tick": int(row.get("tick", 0)),
        "position": [float(value) for value in row.get("position", [0.0, 0.0, 0.0])],
        "linear_velocity": [float(value) for value in row.get("linear_velocity", [0.0, 0.0, 0.0])],
        "speed": float(row.get("speed", 0.0)),
        "slip_angle_deg": float(row.get("slip_angle_deg", 0.0)),
        "motor_rpm": float(row.get("motor_rpm", 0.0)),
        "is_flipped": bool(row.get("is_flipped", False)),
    }


def sampled_telemetry(telemetry):
    samples = []
    final_tick = int(telemetry[-1].get("tick", len(telemetry) - 1))
    for row in telemetry:
        tick = int(row.get("tick", 0))
        if tick == 0 or tick == final_tick or tick % SAMPLE_STRIDE == 0:
            samples.append(sample_from_row(row))
    return samples


def metric_block(metrics):
    return {
        "surface_contact_ticks": metrics.get("surface_contact_ticks", {}),
        "surface_event_count": int(metrics.get("surface_event_count", 0)),
        "landmark_event_count": int(metrics.get("landmark_event_count", 0)),
        "flipped_event_count": int(metrics.get("flipped_event_count", 0)),
        "self_righted_event_count": int(metrics.get("self_righted_event_count", 0)),
        "recovered_to_trail_event_count": int(metrics.get("recovered_to_trail_event_count", 0)),
        "max_abs_slip_angle_deg": float(metrics.get("max_abs_slip_angle_deg", 0.0)),
        "max_abs_slip_angle_by_surface": metrics.get("max_abs_slip_angle_by_surface", {}),
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
        "tolerances": TOLERANCES,
        "predicates": data.get("predicates", {}),
        "metrics": metric_block(data.get("metrics", {})),
        "samples": sampled_telemetry(telemetry),
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
