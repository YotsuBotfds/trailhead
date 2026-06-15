#!/usr/bin/env python3
"""Repeat current headless sim cases and compare their telemetry.

This is a spike-local harness for Phase V Wave S1. It does not change
production routes, goldens, project settings, or sim code. The comparison
reports byte-for-byte JSON stability when present, then enforces the D10
tolerance-based contract over parsed result data.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[3]
SPIKE_DIR = Path(__file__).resolve().parent
DEFAULT_GODOT_BIN = "/Applications/Godot.app/Contents/MacOS/Godot"

DEFAULT_TOLERANCES = {
    "position_m": 0.08,
    "velocity_mps": 0.25,
    "speed_mps": 0.20,
    "slip_deg": 2.0,
    "motor_rpm": 10.0,
    "surface_ticks": 2.0,
    "event_counts": 0.0,
    "generic_float": 1.0e-6,
}


@dataclass(frozen=True)
class Case:
    name: str
    description: str
    sim_args: tuple[str, ...]
    expected_tile_crossings_min: int = 0
    proxy_note: str = ""


CASES: dict[str, Case] = {
    "grown_corridor_seam_proxy": Case(
        name="grown_corridor_seam_proxy",
        description=(
            "Cedar Hollow PD route segment from pine_floor to far_mile_marker; "
            "covers repeated current HeightMapShape3D collision-tile boundary crossings."
        ),
        sim_args=(
            "--scene=cedar_hollow",
            "--controller=pd",
            "--route-segment=pine_floor_to_far_mile_marker",
            "--seed=12345",
            "--max-ticks=4000",
            "--stuck-window=120",
            "--stuck-min-progress=0.015",
        ),
        expected_tile_crossings_min=2,
        proxy_note=(
            "Proxy for seam continuity on the current preloaded 1x12 Cedar collision strip. "
            "This is not a true Phase V streaming seam or arbitrary 100 m seam shot."
        ),
    ),
    "clip_descent_speed_proxy": Case(
        name="clip_descent_speed_proxy",
        description=(
            "Scripted Cedar clip-descent probe; stresses descent speed, clearance, "
            "and chassis penetration metrics on the current terrain."
        ),
        sim_args=(
            "--scene=cedar_hollow",
            "--controller=scripted",
            "--scenario=clip_descent",
            "--spawn=overlook_ridge",
            "--target=old_cedar",
            "--seed=12345",
            "--max-ticks=500",
            "--stuck-window=120",
            "--stuck-min-progress=0.02",
        ),
        proxy_note=(
            "Proxy for top-speed/tunneling risk using the existing clip-descent hook. "
            "A true top-speed seam probe needs sim_runner support for arbitrary Cedar seam targets "
            "or a spike-only scene/controller hook."
        ),
    ),
}


class CompareStats:
    def __init__(self) -> None:
        self.max_position_error: float = 0.0
        self.max_velocity_error: float = 0.0
        self.max_speed_error: float = 0.0
        self.max_slip_error: float = 0.0
        self.max_motor_rpm_error: float = 0.0
        self.max_generic_error: float = 0.0
        self.compared_numbers: int = 0

    def as_dict(self) -> dict[str, Any]:
        return {
            "compared_numbers": self.compared_numbers,
            "max_position_error": self.max_position_error,
            "max_velocity_error": self.max_velocity_error,
            "max_speed_error": self.max_speed_error,
            "max_slip_error": self.max_slip_error,
            "max_motor_rpm_error": self.max_motor_rpm_error,
            "max_generic_error": self.max_generic_error,
        }


@dataclass(frozen=True)
class TerrainInfo:
    min_x: float
    min_z: float
    max_x: float
    max_z: float
    tile_size_x: float
    tile_size_z: float
    origin_x: int
    origin_z: int
    grid_x: int
    grid_z: int

    def tile_index_for_position(self, position: list[Any]) -> tuple[int, int] | None:
        if len(position) < 3:
            return None
        try:
            x = float(position[0])
            z = float(position[2])
        except (TypeError, ValueError):
            return None
        if x < self.min_x or x > self.max_x or z < self.min_z or z > self.max_z:
            return None
        local_x = (x - self.min_x) / self.tile_size_x
        local_z = (z - self.min_z) / self.tile_size_z
        tile_x_offset = min(max(int(math.floor(local_x)), 0), self.grid_x - 1)
        tile_z_offset = min(max(int(math.floor(local_z)), 0), self.grid_z - 1)
        return (self.origin_x + tile_x_offset, self.origin_z + tile_z_offset)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runs", type=int, default=20, help="Number of repeated runs per case.")
    parser.add_argument(
        "--case",
        action="append",
        choices=sorted(CASES.keys()),
        default=[],
        help="Case to run. May be passed more than once. Defaults to all cases.",
    )
    parser.add_argument(
        "--out-dir",
        type=Path,
        default=SPIKE_DIR / "out",
        help="Directory for generated JSON, logs, and summary.",
    )
    parser.add_argument(
        "--godot-bin",
        default=str(Path(DEFAULT_GODOT_BIN)),
        help="Godot executable. Defaults to GODOT_BIN env equivalent path used by project tools.",
    )
    parser.add_argument("--fixed-fps", type=int, default=120)
    args = parser.parse_args()

    if args.runs <= 0:
        print("fail: --runs must be positive", file=sys.stderr)
        return 2

    selected_cases = [CASES[name] for name in (args.case or sorted(CASES.keys()))]
    out_dir = args.out_dir if args.out_dir.is_absolute() else ROOT / args.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)

    project_settings = read_project_physics_settings()
    terrain_info = read_terrain_info()
    max_speed = read_game_config_float("max_speed")
    godot_version = read_godot_version(args.godot_bin)

    summary: dict[str, Any] = {
        "godot_bin": args.godot_bin,
        "godot_version": godot_version,
        "project_settings": project_settings,
        "game_config_max_speed_mps": max_speed,
        "fixed_fps": args.fixed_fps,
        "runs_per_case": args.runs,
        "tolerances": DEFAULT_TOLERANCES,
        "cases": [],
        "overall_pass": True,
    }

    print(f"Godot: {godot_version or args.godot_bin}")
    print(
        "Project physics: "
        f"engine={project_settings.get('physics_engine')} "
        f"ticks={project_settings.get('physics_ticks_per_second')}"
    )
    print(f"Output: {out_dir}")

    for case in selected_cases:
        case_summary = run_case(case, args.runs, args.godot_bin, args.fixed_fps, out_dir, terrain_info, max_speed)
        summary["cases"].append(case_summary)
        summary["overall_pass"] = bool(summary["overall_pass"]) and bool(case_summary["passed"])
        print_case_summary(case_summary)

    summary_path = out_dir / "summary.json"
    summary_path.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
    print(f"Summary: {summary_path}")
    if summary["overall_pass"]:
        print("PASS: parsed telemetry stayed within D10 tolerances for all repeated runs.")
        return 0
    print("FAIL: at least one repeated run diverged beyond tolerance or failed.", file=sys.stderr)
    return 1


def run_case(
    case: Case,
    runs: int,
    godot_bin: str,
    fixed_fps: int,
    out_dir: Path,
    terrain_info: TerrainInfo | None,
    max_speed: float | None,
) -> dict[str, Any]:
    case_dir = out_dir / case.name
    case_dir.mkdir(parents=True, exist_ok=True)
    for stale in case_dir.glob("run_*.*"):
        stale.unlink()

    run_paths: list[Path] = []
    run_data: list[dict[str, Any]] = []
    run_failures: list[dict[str, Any]] = []

    for index in range(1, runs + 1):
        output_path = case_dir / f"run_{index:03d}.json"
        log_path = case_dir / f"run_{index:03d}.log"
        command = [
            godot_bin,
            "--headless",
            "--fixed-fps",
            str(fixed_fps),
            "--path",
            ".",
            "res://scenes/sim_runner.tscn",
            "--",
            *case.sim_args,
            f"--out={output_path}",
        ]
        completed = subprocess.run(command, cwd=ROOT, text=True, capture_output=True, check=False)
        log_path.write_text(
            "$ " + " ".join(command) + "\n\n"
            + "stdout:\n" + completed.stdout
            + "\n\nstderr:\n" + completed.stderr
        )
        if completed.returncode != 0:
            run_failures.append(
                {
                    "run": index,
                    "kind": "process",
                    "returncode": completed.returncode,
                    "log": str(log_path),
                }
            )
            continue
        try:
            data = json.loads(output_path.read_text())
        except (OSError, json.JSONDecodeError) as exc:
            run_failures.append({"run": index, "kind": "json", "error": str(exc), "log": str(log_path)})
            continue
        if data.get("result") != "pass":
            run_failures.append(
                {
                    "run": index,
                    "kind": "sim_result",
                    "result": data.get("result"),
                    "log": str(log_path),
                    "output": str(output_path),
                }
            )
        run_paths.append(output_path)
        run_data.append(data)

    raw_hashes = [sha256_file(path) for path in run_paths]
    compare_errors: list[str] = []
    stats = CompareStats()
    if run_data:
        baseline = run_data[0]
        for index, data in enumerate(run_data[1:], start=2):
            compare_value(("run", str(index)), baseline, data, compare_errors, stats)

    topology_summaries = [
        summarize_topology(data, terrain_info, max_speed)
        for data in run_data
    ]
    min_tile_crossings = min(
        (int(item.get("tile_index_changes", 0)) for item in topology_summaries),
        default=0,
    )
    if case.expected_tile_crossings_min > 0 and min_tile_crossings < case.expected_tile_crossings_min:
        compare_errors.append(
            f"{case.name}: minimum tile crossings {min_tile_crossings} < "
            f"{case.expected_tile_crossings_min}"
        )

    unique_hashes = sorted(set(raw_hashes))
    passed = not run_failures and not compare_errors
    return {
        "name": case.name,
        "description": case.description,
        "proxy_note": case.proxy_note,
        "sim_args": list(case.sim_args),
        "run_count": len(run_data),
        "process_or_result_failures": run_failures,
        "raw_sha256_unique_count": len(unique_hashes),
        "byte_for_byte_identical": len(unique_hashes) == 1 and len(raw_hashes) == runs,
        "baseline_sha256": raw_hashes[0] if raw_hashes else None,
        "parsed_within_tolerance": not compare_errors,
        "compare_error_count": len(compare_errors),
        "compare_errors": compare_errors[:50],
        "compare_stats": stats.as_dict(),
        "topology": summarize_topology_set(topology_summaries),
        "baseline_output": str(run_paths[0]) if run_paths else None,
        "passed": passed,
    }


def compare_value(
    path: tuple[str, ...],
    expected: Any,
    actual: Any,
    errors: list[str],
    stats: CompareStats,
) -> None:
    if isinstance(expected, bool) or isinstance(actual, bool):
        if expected is not actual:
            errors.append(f"{'.'.join(path)} expected {expected!r}, got {actual!r}")
        return
    if expected is None or actual is None:
        if expected is not actual:
            errors.append(f"{'.'.join(path)} expected {expected!r}, got {actual!r}")
        return
    if isinstance(expected, str) or isinstance(actual, str):
        if expected != actual:
            errors.append(f"{'.'.join(path)} expected {expected!r}, got {actual!r}")
        return
    if isinstance(expected, int) and isinstance(actual, int):
        if expected != actual:
            errors.append(f"{'.'.join(path)} expected {expected!r}, got {actual!r}")
        return
    if is_number(expected) and is_number(actual):
        compare_number(path, float(expected), float(actual), errors, stats)
        return
    if isinstance(expected, list) and isinstance(actual, list):
        if len(expected) != len(actual):
            errors.append(f"{'.'.join(path)} length expected {len(expected)}, got {len(actual)}")
            return
        for index, (expected_item, actual_item) in enumerate(zip(expected, actual)):
            compare_value((*path, str(index)), expected_item, actual_item, errors, stats)
        return
    if isinstance(expected, dict) and isinstance(actual, dict):
        expected_keys = set(expected.keys())
        actual_keys = set(actual.keys())
        if expected_keys != actual_keys:
            missing = sorted(expected_keys - actual_keys)
            extra = sorted(actual_keys - expected_keys)
            errors.append(f"{'.'.join(path)} key mismatch missing={missing} extra={extra}")
            return
        for key in sorted(expected_keys):
            compare_value((*path, str(key)), expected[key], actual[key], errors, stats)
        return
    if expected != actual:
        errors.append(f"{'.'.join(path)} expected {expected!r}, got {actual!r}")


def compare_number(
    path: tuple[str, ...],
    expected: float,
    actual: float,
    errors: list[str],
    stats: CompareStats,
) -> None:
    stats.compared_numbers += 1
    delta = abs(expected - actual)
    tolerance, bucket = tolerance_for_path(path)
    if bucket == "position":
        stats.max_position_error = max(stats.max_position_error, delta)
    elif bucket == "velocity":
        stats.max_velocity_error = max(stats.max_velocity_error, delta)
    elif bucket == "speed":
        stats.max_speed_error = max(stats.max_speed_error, delta)
    elif bucket == "slip":
        stats.max_slip_error = max(stats.max_slip_error, delta)
    elif bucket == "motor_rpm":
        stats.max_motor_rpm_error = max(stats.max_motor_rpm_error, delta)
    else:
        stats.max_generic_error = max(stats.max_generic_error, delta)
    if delta > tolerance:
        errors.append(
            f"{'.'.join(path)} delta {delta:g} > {tolerance:g} "
            f"(expected {expected:g}, got {actual:g})"
        )


def tolerance_for_path(path: tuple[str, ...]) -> tuple[float, str]:
    text = ".".join(path)
    leaf = path[-1]
    if leaf in {
        "tick",
        "ticks",
        "seed",
        "wheel_contact_count",
        "front_contact_count",
        "rear_contact_count",
        "surface_event_count",
        "landmark_event_count",
        "flipped_event_count",
        "self_righted_event_count",
        "recovered_to_trail_event_count",
        "self_right_input_count",
        "waypoint_count",
        "stuck_window_ticks",
        "ebrake_ticks",
        "reverse_ticks",
        "compared_samples",
        "compared_slip_samples",
        "compared_motor_rpm_samples",
        "compared_surface_ticks",
        "compared_event_counts",
        "tick_delta",
    }:
        return 0.0, "generic"
    if "motor_rpm" in text:
        return DEFAULT_TOLERANCES["motor_rpm"], "motor_rpm"
    if (
        "position" in text
        or "bounds_" in text
        or "target" in text
        or "wheel_hit_point" in text
        or "clearance" in text
        or "penetration" in text
        or "displacement" in text
        or "distance" in text
    ):
        return DEFAULT_TOLERANCES["position_m"], "position"
    if "linear_velocity" in text or "angular_velocity" in text or "velocity" in text:
        return DEFAULT_TOLERANCES["velocity_mps"], "velocity"
    if "speed" in text or "yaw_rate" in text:
        return DEFAULT_TOLERANCES["speed_mps"], "speed"
    if "slip" in text or "pitch_deg" in text or "roll_deg" in text or "tilt_deg" in text or "heading" in text:
        return DEFAULT_TOLERANCES["slip_deg"], "slip"
    if "surface_contact_ticks" in text:
        return DEFAULT_TOLERANCES["surface_ticks"], "generic"
    return DEFAULT_TOLERANCES["generic_float"], "generic"


def summarize_topology(data: dict[str, Any], terrain_info: TerrainInfo | None, max_speed: float | None) -> dict[str, Any]:
    metrics = data.get("metrics", {})
    telemetry = data.get("telemetry", [])
    if not isinstance(metrics, dict):
        metrics = {}
    if not isinstance(telemetry, list):
        telemetry = []

    visited_tiles: list[tuple[int, int]] = []
    if terrain_info is not None:
        for row in telemetry:
            if not isinstance(row, dict):
                continue
            position = row.get("position", [])
            if not isinstance(position, list):
                continue
            tile_index = terrain_info.tile_index_for_position(position)
            if tile_index is not None:
                visited_tiles.append(tile_index)
    tile_changes = 0
    previous_tile: tuple[int, int] | None = None
    for tile_index in visited_tiles:
        if previous_tile is not None and tile_index != previous_tile:
            tile_changes += 1
        previous_tile = tile_index

    max_speed_seen = float(metrics.get("max_speed", 0.0) or 0.0)
    speed_ratio = None if max_speed is None or max_speed <= 0.0 else max_speed_seen / max_speed
    return {
        "ticks": data.get("ticks"),
        "telemetry_rows": len(telemetry),
        "result": data.get("result"),
        "max_speed_mps": max_speed_seen,
        "max_speed_ratio_of_GameConfig": speed_ratio,
        "chassis_clearance_sample_ticks": metrics.get("chassis_clearance_sample_ticks"),
        "min_chassis_clearance_m": metrics.get("min_chassis_clearance_m"),
        "max_chassis_penetration_m": metrics.get("max_chassis_penetration_m"),
        "unique_tile_indices": sorted([list(value) for value in set(visited_tiles)]),
        "tile_index_changes": tile_changes,
    }


def summarize_topology_set(items: list[dict[str, Any]]) -> dict[str, Any]:
    if not items:
        return {}
    keys = [
        "ticks",
        "telemetry_rows",
        "max_speed_mps",
        "max_speed_ratio_of_GameConfig",
        "chassis_clearance_sample_ticks",
        "min_chassis_clearance_m",
        "max_chassis_penetration_m",
        "tile_index_changes",
    ]
    summary: dict[str, Any] = {"runs": len(items)}
    for key in keys:
        values = [item.get(key) for item in items if isinstance(item.get(key), (int, float))]
        if values:
            summary[key] = {"min": min(values), "max": max(values)}
    unique_tiles = set()
    for item in items:
        for tile in item.get("unique_tile_indices", []):
            if isinstance(tile, list) and len(tile) == 2:
                unique_tiles.add((int(tile[0]), int(tile[1])))
    summary["unique_tile_indices_union"] = sorted([list(value) for value in unique_tiles])
    return summary


def read_project_physics_settings() -> dict[str, Any]:
    text = (ROOT / "project.godot").read_text()
    return {
        "physics_engine": match_string(text, r'3d/physics_engine="([^"]+)"'),
        "physics_ticks_per_second": match_int(text, r"common/physics_ticks_per_second=([0-9]+)"),
    }


def read_terrain_info() -> TerrainInfo | None:
    path = ROOT / "data/terrain/cedar_hollow_terrain_def.tres"
    try:
        text = path.read_text()
        bounds_min = match_vector2(text, r"bounds_min_xz = Vector2\(([^)]+)\)")
        bounds_max = match_vector2(text, r"bounds_max_xz = Vector2\(([^)]+)\)")
        tile_size = match_vector2(text, r"tile_size = Vector2\(([^)]+)\)")
        tile_grid = match_vector2i(text, r"tile_grid = Vector2i\(([^)]+)\)")
        origin = match_vector2i(text, r"tile_grid_origin = Vector2i\(([^)]+)\)")
    except OSError:
        return None
    if bounds_min is None or bounds_max is None or tile_size is None or tile_grid is None or origin is None:
        return None
    return TerrainInfo(
        min_x=bounds_min[0],
        min_z=bounds_min[1],
        max_x=bounds_max[0],
        max_z=bounds_max[1],
        tile_size_x=tile_size[0],
        tile_size_z=tile_size[1],
        origin_x=origin[0],
        origin_z=origin[1],
        grid_x=tile_grid[0],
        grid_z=tile_grid[1],
    )


def read_game_config_float(name: str) -> float | None:
    text = (ROOT / "autoload/game_config.gd").read_text()
    matched = re.search(rf"var {re.escape(name)}: float = ([0-9.+-]+)", text)
    if matched is None:
        return None
    return float(matched.group(1))


def read_godot_version(godot_bin: str) -> str:
    completed = subprocess.run([godot_bin, "--version"], text=True, capture_output=True, check=False)
    if completed.returncode != 0:
        return ""
    return completed.stdout.strip() or completed.stderr.strip()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def is_number(value: Any) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def match_string(text: str, pattern: str) -> str | None:
    matched = re.search(pattern, text)
    if matched is None:
        return None
    return matched.group(1)


def match_int(text: str, pattern: str) -> int | None:
    matched = re.search(pattern, text)
    if matched is None:
        return None
    return int(matched.group(1))


def match_vector2(text: str, pattern: str) -> tuple[float, float] | None:
    matched = re.search(pattern, text)
    if matched is None:
        return None
    parts = [part.strip() for part in matched.group(1).split(",")]
    if len(parts) != 2:
        return None
    return (float(parts[0]), float(parts[1]))


def match_vector2i(text: str, pattern: str) -> tuple[int, int] | None:
    matched = re.search(pattern, text)
    if matched is None:
        return None
    parts = [part.strip() for part in matched.group(1).split(",")]
    if len(parts) != 2:
        return None
    return (int(parts[0]), int(parts[1]))


def print_case_summary(case_summary: dict[str, Any]) -> None:
    topology = case_summary.get("topology", {})
    print(f"\ncase: {case_summary['name']}")
    print(f"  runs: {case_summary['run_count']}")
    print(f"  byte_identical: {case_summary['byte_for_byte_identical']}")
    print(f"  parsed_within_tolerance: {case_summary['parsed_within_tolerance']}")
    print(f"  unique_sha256: {case_summary['raw_sha256_unique_count']}")
    if topology:
        print(f"  max_speed_mps: {range_text(topology.get('max_speed_mps'))}")
        print(f"  max_chassis_penetration_m: {range_text(topology.get('max_chassis_penetration_m'))}")
        print(f"  tile_index_changes: {range_text(topology.get('tile_index_changes'))}")
        print(f"  visited_tiles: {topology.get('unique_tile_indices_union')}")
    if not case_summary["passed"]:
        print(f"  failures: {case_summary.get('compare_errors') or case_summary.get('process_or_result_failures')}")


def range_text(value: Any) -> str:
    if not isinstance(value, dict):
        return "n/a"
    return f"{value.get('min')}..{value.get('max')}"


if __name__ == "__main__":
    sys.exit(main())
