#!/usr/bin/env python3
"""Probe Trailhead golden replay fidelity under faster-than-realtime runner modes."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[3]
DEFAULT_GODOT = "/Applications/Godot.app/Contents/MacOS/Godot"
DEFAULT_REPLAY = "tests/golden/cedar_hollow_segment_trailhead_to_culvert_mouth_replay.json"
PHYSICS_TICKS_PER_SECOND = 120.0

SUITE_ARGS_BY_REPLAY = {
    "flat_target_replay.json": {
        "max_ticks": 440,
        "stuck_window": 120,
        "stuck_min_progress": 0.05,
    },
    "flat_flipped_replay.json": {
        "max_ticks": 840,
        "stuck_window": 120,
        "stuck_min_progress": 0.05,
    },
    "cedar_hollow_old_cedar_replay.json": {
        "max_ticks": 720,
        "stuck_window": 120,
        "stuck_min_progress": 0.05,
    },
    "cedar_hollow_overlook_ridge_replay.json": {
        "max_ticks": 1040,
        "stuck_window": 120,
        "stuck_min_progress": 0.05,
    },
    "cedar_hollow_bog_bottom_replay.json": {
        "max_ticks": 840,
        "stuck_window": 120,
        "stuck_min_progress": 0.05,
    },
    "cedar_hollow_the_crossing_replay.json": {
        "max_ticks": 1240,
        "stuck_window": 120,
        "stuck_min_progress": 0.05,
        "target_radius": 0.15,
    },
    "cedar_hollow_boardwalk_end_replay.json": {
        "max_ticks": 840,
        "stuck_window": 120,
        "stuck_min_progress": 0.05,
        "target_radius": 0.25,
    },
    "cedar_hollow_culvert_mouth_replay.json": {
        "max_ticks": 1040,
        "stuck_window": 120,
        "stuck_min_progress": 0.05,
    },
    "cedar_hollow_segment_trailhead_to_culvert_mouth_replay.json": {
        "max_ticks": 1040,
        "stuck_window": 120,
        "stuck_min_progress": 0.05,
    },
    "cedar_hollow_segment_overlook_to_old_cedar_replay.json": {
        "max_ticks": 3200,
        "stuck_window": 120,
        "stuck_min_progress": 0.015,
    },
    "cedar_hollow_segment_overlook_to_ridge_gate_replay.json": {
        "max_ticks": 900,
        "stuck_window": 120,
        "stuck_min_progress": 0.015,
    },
    "cedar_hollow_segment_ridge_gate_to_pine_floor_replay.json": {
        "max_ticks": 2200,
        "stuck_window": 120,
        "stuck_min_progress": 0.015,
    },
    "cedar_hollow_segment_pine_floor_to_far_mile_marker_replay.json": {
        "max_ticks": 4000,
        "stuck_window": 120,
        "stuck_min_progress": 0.015,
    },
}


VARIANTS = [
    {
        "name": "normal_no_fixed_fps",
        "description": "Headless replay without --fixed-fps; expected to be wall-clock throttled by normal engine timing.",
        "engine_args": [],
        "required": True,
    },
    {
        "name": "suite_fixed_fps_120",
        "description": "Current suite mode: --fixed-fps 120 disables real-time synchronization while preserving the 120 Hz physics tick contract.",
        "engine_args": ["--fixed-fps", "120"],
        "required": True,
    },
    {
        "name": "timescale4_fixed_fps480",
        "description": "CLI-only time-scale candidate: --fixed-fps 480 --time-scale 4.0. This is exploratory and is allowed to fail.",
        "engine_args": ["--fixed-fps", "480", "--time-scale", "4.0"],
        "required": False,
    },
]


def project_relative(path: Path) -> str:
    try:
        return str(path.resolve().relative_to(ROOT))
    except ValueError:
        return str(path)


def load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        value = json.load(handle)
    if not isinstance(value, dict):
        raise ValueError(f"{path} root is not an object")
    return value


def runner_args(replay_path: Path, replay: dict[str, Any]) -> list[str]:
    suite_args = SUITE_ARGS_BY_REPLAY.get(replay_path.name, {})
    max_ticks = int(suite_args.get("max_ticks", int(replay.get("ticks", 0)) + 20))
    stuck_window = int(suite_args.get("stuck_window", 120))
    stuck_min_progress = float(suite_args.get("stuck_min_progress", 0.05))
    args = [
        f"--scene={replay.get('scene', '')}",
        "--controller=replay",
        f"--replay={project_relative(replay_path)}",
        f"--seed={int(replay.get('seed', 0))}",
        f"--max-ticks={max_ticks}",
        f"--stuck-window={stuck_window}",
        f"--stuck-min-progress={stuck_min_progress}",
    ]
    route_segment = str(replay.get("route_segment", ""))
    if route_segment:
        args.append(f"--route-segment={route_segment}")
    else:
        args.extend(
            [
                f"--spawn={replay.get('spawn', '')}",
                f"--target={replay.get('target', '')}",
            ]
        )
        if "target_radius" in suite_args:
            args.append(f"--target-radius={suite_args['target_radius']}")
    return args


def run_variant(
    godot_bin: str,
    out_dir: Path,
    variant: dict[str, Any],
    replay_args: list[str],
) -> dict[str, Any]:
    name = str(variant["name"])
    output_path = out_dir / f"{name}.json"
    log_path = out_dir / f"{name}.log"
    command = [
        godot_bin,
        "--headless",
        *list(variant["engine_args"]),
        "--path",
        ".",
        "res://scenes/sim_runner.tscn",
        "--",
        *replay_args,
        f"--out={project_relative(output_path)}",
    ]
    started = time.perf_counter()
    completed = subprocess.run(
        command,
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    wall_seconds = time.perf_counter() - started
    log_path.write_text(completed.stdout, encoding="utf-8")
    result: dict[str, Any] = {
        "name": name,
        "description": variant["description"],
        "required": bool(variant["required"]),
        "command": command,
        "exit_code": completed.returncode,
        "wall_seconds": wall_seconds,
        "output_path": project_relative(output_path),
        "log_path": project_relative(log_path),
        "json_loaded": False,
    }
    if output_path.exists():
        data = load_json(output_path)
        metrics = data.get("metrics", {})
        if not isinstance(metrics, dict):
            metrics = {}
        golden = metrics.get("golden_replay", {})
        if not isinstance(golden, dict):
            golden = {}
        ticks = int(data.get("ticks", 0))
        sim_seconds = ticks / PHYSICS_TICKS_PER_SECOND
        result.update(
            {
                "json_loaded": True,
                "result": data.get("result"),
                "ticks": ticks,
                "sim_seconds": sim_seconds,
                "faster_than_realtime": wall_seconds < sim_seconds,
                "sim_seconds_per_wall_second": sim_seconds / wall_seconds if wall_seconds > 0.0 else None,
                "golden_replay_matched": bool(data.get("predicates", {}).get("golden_replay_matched", False))
                if isinstance(data.get("predicates", {}), dict)
                else False,
                "golden_replay": {
                    "matched": bool(golden.get("matched", False)),
                    "expected_ticks": golden.get("expected_ticks"),
                    "tick_delta": golden.get("tick_delta"),
                    "compared_samples": golden.get("compared_samples"),
                    "compared_surface_ticks": golden.get("compared_surface_ticks"),
                    "compared_event_counts": golden.get("compared_event_counts"),
                    "max_position_error": golden.get("max_position_error"),
                    "max_velocity_error": golden.get("max_velocity_error"),
                    "max_speed_error": golden.get("max_speed_error"),
                    "max_slip_error": golden.get("max_slip_error"),
                    "max_motor_rpm_error": golden.get("max_motor_rpm_error"),
                    "failures": golden.get("failures", []),
                },
                "telemetry": data.get("telemetry", []),
                "metrics": metrics,
            }
        )
    return result


def vec3_distance(a_value: Any, b_value: Any) -> float:
    if not isinstance(a_value, list) or not isinstance(b_value, list):
        return float("inf")
    if len(a_value) < 3 or len(b_value) < 3:
        return float("inf")
    dx = float(a_value[0]) - float(b_value[0])
    dy = float(a_value[1]) - float(b_value[1])
    dz = float(a_value[2]) - float(b_value[2])
    return (dx * dx + dy * dy + dz * dz) ** 0.5


def telemetry_diff(reference: dict[str, Any], candidate: dict[str, Any]) -> dict[str, Any]:
    reference_rows = reference.get("telemetry", [])
    candidate_rows = candidate.get("telemetry", [])
    if not isinstance(reference_rows, list):
        reference_rows = []
    if not isinstance(candidate_rows, list):
        candidate_rows = []
    rows_compared = min(len(reference_rows), len(candidate_rows))
    diff = {
        "reference": reference["name"],
        "candidate": candidate["name"],
        "reference_rows": len(reference_rows),
        "candidate_rows": len(candidate_rows),
        "rows_compared": rows_compared,
        "ticks_equal": reference.get("ticks") == candidate.get("ticks"),
        "telemetry_rows_equal": len(reference_rows) == len(candidate_rows),
        "max_position_delta_m": 0.0,
        "max_velocity_delta_mps": 0.0,
        "max_speed_delta_mps": 0.0,
        "max_slip_delta_deg": 0.0,
        "max_motor_rpm_delta": 0.0,
        "surface_contact_ticks_equal": False,
        "surface_event_sequence_equal": False,
        "landmark_event_sequence_equal": False,
    }
    for index in range(rows_compared):
        ref_row = reference_rows[index]
        cand_row = candidate_rows[index]
        if not isinstance(ref_row, dict) or not isinstance(cand_row, dict):
            continue
        diff["max_position_delta_m"] = max(
            float(diff["max_position_delta_m"]),
            vec3_distance(ref_row.get("position", []), cand_row.get("position", [])),
        )
        diff["max_velocity_delta_mps"] = max(
            float(diff["max_velocity_delta_mps"]),
            vec3_distance(ref_row.get("linear_velocity", []), cand_row.get("linear_velocity", [])),
        )
        diff["max_speed_delta_mps"] = max(
            float(diff["max_speed_delta_mps"]),
            abs(float(ref_row.get("speed", 0.0)) - float(cand_row.get("speed", 0.0))),
        )
        diff["max_slip_delta_deg"] = max(
            float(diff["max_slip_delta_deg"]),
            abs(float(ref_row.get("slip_angle_deg", 0.0)) - float(cand_row.get("slip_angle_deg", 0.0))),
        )
        diff["max_motor_rpm_delta"] = max(
            float(diff["max_motor_rpm_delta"]),
            abs(float(ref_row.get("motor_rpm", 0.0)) - float(cand_row.get("motor_rpm", 0.0))),
        )
    reference_metrics = reference.get("metrics", {})
    candidate_metrics = candidate.get("metrics", {})
    if isinstance(reference_metrics, dict) and isinstance(candidate_metrics, dict):
        diff["surface_contact_ticks_equal"] = reference_metrics.get("surface_contact_ticks", {}) == candidate_metrics.get(
            "surface_contact_ticks", {}
        )
        diff["surface_event_sequence_equal"] = reference_metrics.get("surface_event_sequence", []) == candidate_metrics.get(
            "surface_event_sequence", []
        )
        diff["landmark_event_sequence_equal"] = reference_metrics.get("landmark_event_sequence", []) == candidate_metrics.get(
            "landmark_event_sequence", []
        )
    return diff


def printable_command(command: list[str]) -> str:
    return " ".join(command)


def strip_heavy_payload(result: dict[str, Any]) -> dict[str, Any]:
    stripped = dict(result)
    stripped.pop("telemetry", None)
    stripped.pop("metrics", None)
    return stripped


def write_summary(out_dir: Path, replay_path: Path, results: list[dict[str, Any]], diffs: list[dict[str, Any]]) -> Path:
    summary_path = out_dir / "latest_summary.json"
    summary = {
        "replay": project_relative(replay_path),
        "physics_ticks_per_second_assumed": PHYSICS_TICKS_PER_SECOND,
        "variants": [strip_heavy_payload(result) for result in results],
        "diffs_against_normal": diffs,
    }
    summary_path.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    return summary_path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot-bin", default=os.environ.get("GODOT_BIN", DEFAULT_GODOT))
    parser.add_argument("--replay", default=DEFAULT_REPLAY)
    parser.add_argument("--out-dir", default="tools/spikes/fast_step_fidelity/out")
    parser.add_argument(
        "--skip-timescale-candidate",
        action="store_true",
        help="Run only the normal and current-suite fixed-fps variants.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    godot_bin = args.godot_bin
    replay_path = (ROOT / args.replay).resolve()
    out_dir = (ROOT / args.out_dir).resolve()
    if not replay_path.exists():
        print(f"fail: replay not found: {project_relative(replay_path)}", file=sys.stderr)
        return 2
    if not Path(godot_bin).exists():
        print(f"fail: Godot binary not found: {godot_bin}", file=sys.stderr)
        return 2
    out_dir.mkdir(parents=True, exist_ok=True)
    replay = load_json(replay_path)
    replay_run_args = runner_args(replay_path, replay)
    variants = VARIANTS
    if args.skip_timescale_candidate:
        variants = [variant for variant in variants if variant["name"] != "timescale4_fixed_fps480"]
    results = []
    print(f"replay: {project_relative(replay_path)}")
    print(f"out_dir: {project_relative(out_dir)}")
    for variant in variants:
        result = run_variant(godot_bin, out_dir, variant, replay_run_args)
        results.append(result)
        golden = result.get("golden_replay", {})
        print(
            f"{result['name']}: exit={result['exit_code']} result={result.get('result')} "
            f"wall={result['wall_seconds']:.3f}s sim={result.get('sim_seconds')}s "
            f"fast_factor={result.get('sim_seconds_per_wall_second')} "
            f"golden_matched={golden.get('matched')}"
        )
        if result["exit_code"] != 0:
            failures = golden.get("failures", [])
            if failures:
                print(f"  failures: {'; '.join(str(value) for value in failures[:4])}")
    reference = next((result for result in results if result["name"] == "normal_no_fixed_fps" and result.get("json_loaded")), None)
    diffs = []
    if reference is not None:
        for result in results:
            if result is reference or not result.get("json_loaded"):
                continue
            diff = telemetry_diff(reference, result)
            diffs.append(diff)
            print(
                f"diff normal->{result['name']}: rows={diff['rows_compared']} "
                f"pos={diff['max_position_delta_m']:.9g} vel={diff['max_velocity_delta_mps']:.9g} "
                f"speed={diff['max_speed_delta_mps']:.9g} slip={diff['max_slip_delta_deg']:.9g} "
                f"rpm={diff['max_motor_rpm_delta']:.9g} ticks_equal={diff['ticks_equal']}"
            )
    summary_path = write_summary(out_dir, replay_path, results, diffs)
    print(f"summary: {project_relative(summary_path)}")
    required_failures = [
        result
        for result in results
        if result.get("required")
        and (result.get("exit_code") != 0 or result.get("result") != "pass" or not result.get("golden_replay_matched"))
    ]
    if required_failures:
        print("fail: required variant failed", file=sys.stderr)
        for failure in required_failures:
            print(f"- {failure['name']} exit={failure['exit_code']} result={failure.get('result')}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
