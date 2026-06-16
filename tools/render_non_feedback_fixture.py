#!/usr/bin/env python3
"""Assert that loading the render tile streamer does not perturb sim telemetry."""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
GODOT_BIN = os.environ.get("GODOT_BIN", "/Applications/Godot.app/Contents/MacOS/Godot")
OUT_DIR = ROOT / "tests" / "out" / "render_non_feedback"
HEADLESS_OUTPUT = OUT_DIR / "spike_headless.json"
RENDER_OUTPUT = OUT_DIR / "spike_render.json"
RENDER_SUCCESS_LINE = "render_non_feedback_runner: visual tiles active="

SIM_ARGS = [
    "--stream-route=spike_1km_route",
    "--segment=west_gate_to_east_gate",
    "--controller=pd",
    "--stream-workers=0",
    "--seed=12345",
    "--max-ticks=3000",
    "--stuck-window=240",
    "--stuck-min-progress=0.02",
]


def main() -> int:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    _remove_stale_outputs()

    headless_command = [
        GODOT_BIN,
        "--headless",
        "--fixed-fps",
        "120",
        "--path",
        str(ROOT),
        "res://scenes/sim_runner.tscn",
        "--",
        *SIM_ARGS,
        f"--out={_res_path(HEADLESS_OUTPUT)}",
    ]
    render_command = [
        GODOT_BIN,
        "--fixed-fps",
        "120",
        "--path",
        str(ROOT),
        "res://tools/render_non_feedback_runner.tscn",
        "--",
        *SIM_ARGS,
        "--render-runtime-skip-frame-cap",
        "--render-region=spike_1km",
        f"--out={_res_path(RENDER_OUTPUT)}",
    ]

    headless_result = _run("headless sim-only", headless_command)
    if headless_result != 0:
        return headless_result
    render_result = _run("windowed render-hosted", render_command)
    if render_result != 0:
        return render_result

    headless = _load_json(HEADLESS_OUTPUT)
    rendered = _load_json(RENDER_OUTPUT)
    errors = _compare_outputs(headless, rendered)
    if errors:
        for error in errors:
            print("fail: " + error, file=sys.stderr)
        return 1

    telemetry_rows = len(headless.get("telemetry", []))
    print(
        "ok: render non-feedback telemetry identity "
        f"rows={telemetry_rows} route={headless.get('stream_route', '')}"
    )
    return 0


def _remove_stale_outputs() -> None:
    for path in (HEADLESS_OUTPUT, RENDER_OUTPUT):
        if path.exists():
            path.unlink()


def _run(label: str, command: list[str]) -> int:
    print("run: " + label)
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
    if label == "windowed render-hosted" and RENDER_SUCCESS_LINE not in output:
        print("fail: render-hosted run did not report active visual tiles", file=sys.stderr)
        return 1
    return 0


def _load_json(path: Path) -> dict[str, Any]:
    if not path.exists():
        raise SystemExit(f"missing expected output: {_display(path)}")
    data = json.loads(path.read_text())
    if not isinstance(data, dict):
        raise SystemExit(f"output was not a JSON object: {_display(path)}")
    return data


def _compare_outputs(headless: dict[str, Any], rendered: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    if headless.get("result") != "pass":
        errors.append("headless run did not pass")
    if rendered.get("result") != "pass":
        errors.append("render-hosted run did not pass")

    for key in ("scene", "controller", "scenario", "stream_route", "route_segment", "spawn", "target", "seed", "ticks"):
        if headless.get(key) != rendered.get(key):
            errors.append(f"{key} differed: headless={headless.get(key)!r} render={rendered.get(key)!r}")

    for key in ("predicates", "metrics", "telemetry"):
        if headless.get(key) != rendered.get(key):
            errors.append(key + " differed between headless and render-hosted runs")
            _write_diff_artifact(key, headless.get(key), rendered.get(key))
    return errors


def _write_diff_artifact(key: str, headless_value: Any, render_value: Any) -> None:
    diff_path = OUT_DIR / f"{key}_diff.json"
    payload = {
        "key": key,
        "headless": headless_value,
        "render": render_value,
    }
    diff_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
    print("diff: " + _display(diff_path), file=sys.stderr)


def _res_path(path: Path) -> str:
    return "res://" + path.relative_to(ROOT).as_posix()


def _display(path: Path) -> str:
    try:
        return str(path.relative_to(ROOT))
    except ValueError:
        return str(path)


if __name__ == "__main__":
    sys.exit(main())
