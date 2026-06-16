#!/usr/bin/env python3
"""Run the windowed render frame-budget probe and validate its metric table."""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
GODOT_BIN = os.environ.get("GODOT_BIN", "/Applications/Godot.app/Contents/MacOS/Godot")
OUT_DIR = ROOT / "tests" / "out" / "render_frame_budget"
OUT_PATH = OUT_DIR / "spike_streamed.json"
EXPECTED_PHASES = (
    "baseline_empty_streamer",
    "initial_25_tile_burst",
    "east_shift_5_tile_burst",
    "steady_streamed_window",
)
EXPECTED_ACTIVATION_WAIT_MAX_FRAMES = {
    "initial_25_tile_burst": 7,
    "east_shift_5_tile_burst": 2,
}
EXPECTED_VISUAL_TILE_COMMITS_PER_FRAME = 4
EXPECTED_ACTIVE_VISIBLE_PRIMITIVES_MAX = 6000.0


def main() -> int:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    if OUT_PATH.exists():
        OUT_PATH.unlink()

    command = [
        GODOT_BIN,
        "--fixed-fps",
        "120",
        "--path",
        str(ROOT),
        "res://tools/render_frame_budget_probe.tscn",
        "--",
        "--render-runtime-skip-frame-cap",
        "--region=spike_1km",
        f"--out={_res_path(OUT_PATH)}",
    ]
    result = _run_probe(command)
    if result != 0:
        return result

    payload = _load_json(OUT_PATH)
    errors = _validate_payload(payload)
    if errors:
        for error in errors:
            print("fail: " + error, file=sys.stderr)
        return 1

    _print_summary(payload)
    return 0


def _run_probe(command: list[str]) -> int:
    print("run: windowed render frame budget probe")
    completed = subprocess.run(
        command,
        cwd=ROOT,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    sys.stdout.write(completed.stdout)
    if completed.returncode != 0:
        return int(completed.returncode)
    if "SCRIPT ERROR:" in completed.stdout or "Parse Error:" in completed.stdout:
        return 1
    if "ok: render frame budget probe wrote" not in completed.stdout:
        print("fail: probe did not report a completed output write", file=sys.stderr)
        return 1
    return 0


def _load_json(path: Path) -> dict[str, Any]:
    if not path.exists():
        raise SystemExit(f"missing expected output: {_display(path)}")
    data = json.loads(path.read_text())
    if not isinstance(data, dict):
        raise SystemExit(f"output was not a JSON object: {_display(path)}")
    return data


def _validate_payload(payload: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    if payload.get("schema") != "trailhead.render_frame_budget.v1":
        errors.append("unexpected schema")
    if payload.get("region_id") != "spike_1km":
        errors.append("unexpected region_id")
    runtime = payload.get("render_runtime")
    if not isinstance(runtime, dict):
        errors.append("missing render_runtime")
    else:
        if runtime.get("frame_cap_enabled") is not True:
            errors.append("render frame cap should be enabled")
        if int(runtime.get("target_max_fps", 0)) != 60:
            errors.append("render target_max_fps should be 60")
        if int(runtime.get("visual_tile_commits_per_frame", 0)) != EXPECTED_VISUAL_TILE_COMMITS_PER_FRAME:
            errors.append("render visual_tile_commits_per_frame should be " + str(EXPECTED_VISUAL_TILE_COMMITS_PER_FRAME))
        if runtime.get("frame_cap_skip_requested") is not True:
            errors.append("render frame-budget probe should skip runtime frame cap")
        if runtime.get("frame_cap_applied") is not False:
            errors.append("render frame cap should not apply to fixed-fps frame-budget probes")
        if runtime.get("dynamic_resolution_enabled") is not True:
            errors.append("render dynamic resolution should be enabled")
        if runtime.get("dynamic_resolution_installed") is not False:
            errors.append("render dynamic resolution should not install in fixed-fps frame-budget probes")
    phases = payload.get("phases")
    if not isinstance(phases, list):
        errors.append("phases should be a list")
        return errors
    observed_names = tuple(phase.get("name") for phase in phases if isinstance(phase, dict))
    if observed_names != EXPECTED_PHASES:
        errors.append(f"phase names expected {EXPECTED_PHASES!r}, got {observed_names!r}")
    for phase in phases:
        if not isinstance(phase, dict):
            errors.append("phase entry should be an object")
            continue
        errors.extend(_validate_phase(phase))
    if int(payload.get("final_visual_cells", 0)) != 25:
        errors.append("final_visual_cells should be 25 after the shifted active window")
    return errors


def _validate_phase(phase: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    name = str(phase.get("name", "<missing>"))
    if int(phase.get("frames", 0)) <= 0:
        errors.append(name + " should record at least one frame")
    if "activation_cpu_ms" not in phase:
        errors.append(name + " missing activation_cpu_ms")
    if "prefetch_cpu_ms" not in phase:
        errors.append(name + " missing prefetch_cpu_ms")
    errors.extend(_validate_ready_wait(phase.get("prefetch_ready_wait"), name + ".prefetch_ready_wait", active_expected=name != "baseline_empty_streamer" and name != "steady_streamed_window"))
    errors.extend(_validate_ready_wait(phase.get("activation_ready_wait"), name + ".activation_ready_wait", active_expected=name != "baseline_empty_streamer" and name != "steady_streamed_window"))
    if not isinstance(phase.get("viewport_gpu_timing_available"), bool):
        errors.append(name + " missing viewport_gpu_timing_available")
    timing = phase.get("timing_ms")
    if not isinstance(timing, dict):
        errors.append(name + " missing timing_ms")
    else:
        for key in ("frame_wall", "viewport_cpu", "viewport_gpu", "process_monitor", "physics_monitor"):
            errors.extend(_validate_stats(timing.get(key), name + ".timing_ms." + key))
    render_info = phase.get("render_info")
    if not isinstance(render_info, dict):
        errors.append(name + " missing render_info")
    else:
        for bucket in ("visible", "shadow", "canvas"):
            bucket_value = render_info.get(bucket)
            if not isinstance(bucket_value, dict):
                errors.append(name + ".render_info." + bucket + " missing")
                continue
            for key in ("draw_calls", "primitives", "objects"):
                errors.extend(_validate_stats(bucket_value.get(key), name + ".render_info." + bucket + "." + key))
        total = render_info.get("performance_total")
        if not isinstance(total, dict):
            errors.append(name + ".render_info.performance_total missing")
        else:
            for key in ("draw_calls", "objects"):
                errors.extend(_validate_stats(total.get(key), name + ".render_info.performance_total." + key))
        active_cells = int(phase.get("active_visual_cells", 0))
        visible_bucket = render_info.get("visible")
        if active_cells > 0 and isinstance(visible_bucket, dict):
            draw_stats = visible_bucket.get("draw_calls")
            if isinstance(draw_stats, dict) and float(draw_stats.get("avg", 0.0)) <= 0.0:
                errors.append(name + " should render visible draw calls when streamed visual cells are active")
            primitive_stats = visible_bucket.get("primitives")
            if isinstance(primitive_stats, dict) and float(primitive_stats.get("avg", 0.0)) > EXPECTED_ACTIVE_VISIBLE_PRIMITIVES_MAX:
                errors.append(name + " visible primitives should stay <= " + _fmt(EXPECTED_ACTIVE_VISIBLE_PRIMITIVES_MAX))
        errors.extend(_validate_activation_wait(phase, active_cells))
    memory = phase.get("memory_mb")
    if not isinstance(memory, dict):
        errors.append(name + " missing memory_mb")
    else:
        errors.extend(_validate_stats(memory.get("render_video"), name + ".memory_mb.render_video"))
    return errors


def _validate_ready_wait(value: Any, label: str, active_expected: bool) -> list[str]:
    if not isinstance(value, dict):
        return [label + " should be an object"]
    if not active_expected and not value:
        return []
    errors: list[str] = []
    for key in ("frames", "wall_ms"):
        metric = value.get(key)
        if not isinstance(metric, (int, float)):
            errors.append(label + "." + key + " should be numeric")
        elif float(metric) < 0.0:
            errors.append(label + "." + key + " should be non-negative")
    return errors


def _validate_activation_wait(phase: dict[str, Any], active_cells: int) -> list[str]:
    name = str(phase.get("name", "<missing>"))
    activation_wait = phase.get("activation_ready_wait")
    if active_cells <= 0 or not isinstance(activation_wait, dict):
        return []
    if "frames" not in activation_wait:
        if name in EXPECTED_ACTIVATION_WAIT_MAX_FRAMES:
            return [name + " activation_ready_wait.frames missing"]
        return []
    frames = int(activation_wait.get("frames", -1))
    if name in EXPECTED_ACTIVATION_WAIT_MAX_FRAMES:
        if frames <= 0:
            return [name + " should drain ready tile commits over at least one bounded frame"]
        max_frames = EXPECTED_ACTIVATION_WAIT_MAX_FRAMES[name]
        if frames > max_frames:
            return [name + " activation wait should stay <= " + str(max_frames) + " frames, got " + str(frames)]
    elif frames != 0:
        return [name + " should not wait for activation commits"]
    return []


def _validate_stats(value: Any, label: str) -> list[str]:
    errors: list[str] = []
    if not isinstance(value, dict):
        return [label + " should be a stats object"]
    for key in ("min", "max", "avg", "p50", "p95"):
        metric = value.get(key)
        if not isinstance(metric, (int, float)):
            errors.append(label + "." + key + " should be numeric")
        elif float(metric) < 0.0:
            errors.append(label + "." + key + " should be non-negative")
    return errors


def _print_summary(payload: dict[str, Any]) -> None:
    print("ok: render frame budget metrics -> " + _display(OUT_PATH))
    print("phase,active,gpu_timing,prefetch_cpu_ms,activation_cpu_ms,prefetch_wait_frames,activation_wait_frames,wall_p95_ms,viewport_cpu_p95_ms,viewport_gpu_p95_ms,render_video_mb_avg,visible_draw_avg,shadow_draw_avg,total_draw_avg")
    for phase in payload["phases"]:
        timing = phase["timing_ms"]
        render_info = phase["render_info"]
        print(
            ",".join(
                [
                    str(phase["name"]),
                    str(phase["active_visual_cells"]),
                    "yes" if phase["viewport_gpu_timing_available"] else "no",
                    _fmt(phase["prefetch_cpu_ms"]),
                    _fmt(phase["activation_cpu_ms"]),
                    str(int(phase["prefetch_ready_wait"].get("frames", 0))),
                    str(int(phase["activation_ready_wait"].get("frames", 0))),
                    _fmt(timing["frame_wall"]["p95"]),
                    _fmt(timing["viewport_cpu"]["p95"]),
                    _fmt(timing["viewport_gpu"]["p95"]),
                    _fmt(phase["memory_mb"]["render_video"]["avg"]),
                    _fmt(render_info["visible"]["draw_calls"]["avg"]),
                    _fmt(render_info["shadow"]["draw_calls"]["avg"]),
                    _fmt(render_info["performance_total"]["draw_calls"]["avg"]),
                ]
            )
        )


def _fmt(value: Any) -> str:
    return f"{float(value):.3f}"


def _res_path(path: Path) -> str:
    return "res://" + path.relative_to(ROOT).as_posix()


def _display(path: Path) -> str:
    try:
        return str(path.relative_to(ROOT))
    except ValueError:
        return str(path)


if __name__ == "__main__":
    sys.exit(main())
