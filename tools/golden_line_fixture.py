#!/usr/bin/env python3
"""Run the GL-3b golden-line tracker fixture in headless Godot."""

import os
import pathlib
import subprocess
import sys


ROOT = pathlib.Path(__file__).resolve().parents[1]
GODOT_BIN = os.environ.get("GODOT_BIN", "/Applications/Godot.app/Contents/MacOS/Godot")
OUT_DIR = ROOT / "tests" / "out"
SIM_OUTPUT = OUT_DIR / "golden_line_bog_bottom_fixture.json"
FIXTURE_SCRIPT = OUT_DIR / "golden_line_fixture.gd"
FIXTURE_SCENE = OUT_DIR / "golden_line_fixture.tscn"


SCRIPT_SOURCE = r'''extends Node

const GoldenLineTrackerScript: GDScript = preload("res://systems/sim/golden_line_tracker.gd")
const GoldenLineGhostScript: GDScript = preload("res://systems/render/golden_line_ghost.gd")
const TELEMETRY_PATH: String = "res://tests/out/golden_line_bog_bottom_fixture.json"

var _errors: PackedStringArray = PackedStringArray()
var _events: Array[Variant] = []


func _ready() -> void:
	if not EventBus.world_golden_line_matched.is_connected(_on_world_golden_line_matched):
		EventBus.world_golden_line_matched.connect(_on_world_golden_line_matched)
	call_deferred("_run")


func _run() -> void:
	_assert_golden_path_fires_once()
	_assert_drifted_path_never_fires()
	_assert_ghost_receives_signal()
	if EventBus.world_golden_line_matched.is_connected(_on_world_golden_line_matched):
		EventBus.world_golden_line_matched.disconnect(_on_world_golden_line_matched)
	_finish()


func _assert_golden_path_fires_once() -> void:
	_events.clear()
	var tracker: Node = GoldenLineTrackerScript.new() as Node
	add_child(tracker)
	tracker.call("configure", "res://tests/golden/cedar_hollow_bog_bottom_replay.json", &"bog_bottom", 0)
	if int(tracker.call("sample_count")) < 2:
		_errors.append("tracker did not load the Bog Bottom golden samples: " + String(tracker.call("load_error")))
		tracker.queue_free()
		return
	var rows: Array[Variant] = _telemetry_rows()
	if rows.is_empty():
		_errors.append("fixture sim telemetry was empty")
		tracker.queue_free()
		return
	var window_ticks: int = int(tracker.call("match_window_ticks"))
	for index in range(rows.size()):
		var row: Variant = rows[index]
		var tick: int = int(row.get("tick", -1))
		var position: Vector3 = _vec3_from_array(row.get("position", []))
		var fired: bool = bool(tracker.call("sample_position", position, tick))
		if index < window_ticks - 1 and fired:
			_errors.append("golden path fired early at tick " + str(tick))
		if fired:
			break
	if _events.size() != 1:
		_errors.append("golden path emitted " + str(_events.size()) + " events, expected 1")
	else:
		var event: Variant = _events[0]
		if StringName(event.get("segment_id", &"")) != &"bog_bottom":
			_errors.append("golden path segment was " + String(event.get("segment_id", &"")) + ", expected bog_bottom")
		if int(event.get("sim_tick", -1)) < window_ticks - 1:
			_errors.append("golden path match tick was too early: " + str(event.get("sim_tick", -1)))
	for row in rows:
		var tick: int = int(row.get("tick", -1))
		var position: Vector3 = _vec3_from_array(row.get("position", []))
		tracker.call("sample_position", position, tick)
	if _events.size() != 1:
		_errors.append("golden path emitted duplicate events after match")
	tracker.queue_free()


func _assert_drifted_path_never_fires() -> void:
	_events.clear()
	var tracker: Node = GoldenLineTrackerScript.new() as Node
	add_child(tracker)
	tracker.call("configure", "res://tests/golden/cedar_hollow_bog_bottom_replay.json", &"bog_bottom_drifted", 0)
	var drift: Vector3 = Vector3(GameConfig.golden_position_tolerance_m + 0.02, 0.0, 0.0)
	for row in _telemetry_rows():
		var tick: int = int(row.get("tick", -1))
		var position: Vector3 = _vec3_from_array(row.get("position", [])) + drift
		var fired: bool = bool(tracker.call("sample_position", position, tick))
		if fired:
			_errors.append("drifted path fired at tick " + str(tick))
	if _events.size() != 0:
		_errors.append("drifted path emitted " + str(_events.size()) + " events, expected 0")
	if int(tracker.call("consecutive_match_ticks")) != 0:
		_errors.append("drifted path retained consecutive match ticks")
	tracker.queue_free()


func _assert_ghost_receives_signal() -> void:
	_events.clear()
	var ghost: Node = GoldenLineGhostScript.new() as Node
	add_child(ghost)
	EventBus.world_golden_line_matched.emit(&"ghost_fixture", 123)
	if not bool(ghost.call("is_active")):
		_errors.append("ghost did not become active after signal")
	if StringName(ghost.call("last_segment_id")) != &"ghost_fixture":
		_errors.append("ghost segment did not match signal payload")
	if int(ghost.call("last_match_tick")) != 123:
		_errors.append("ghost tick did not match signal payload")
	if int(ghost.call("fade_ticks_remaining")) != GameConfig.egg_dev_line_ghost_fade_ticks:
		_errors.append("ghost fade ticks did not use GameConfig")
	ghost.queue_free()


func _telemetry_rows() -> Array[Variant]:
	var file: FileAccess = FileAccess.open(ProjectSettings.globalize_path(TELEMETRY_PATH), FileAccess.READ)
	if file == null:
		_errors.append("could not open telemetry fixture output")
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		_errors.append("telemetry fixture output was not a dictionary")
		return []
	var rows: Variant = parsed.get("telemetry", [])
	if not (rows is Array):
		_errors.append("telemetry fixture output did not contain telemetry rows")
		return []
	return rows


func _vec3_from_array(value: Variant) -> Vector3:
	if not (value is Array) or value.size() < 3:
		return Vector3(INF, INF, INF)
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


func _on_world_golden_line_matched(segment_id: StringName, sim_tick: int) -> void:
	_events.append({
		"segment_id": segment_id,
		"sim_tick": sim_tick
	})


func _finish() -> void:
	if _errors.is_empty():
		print("ok: golden line tracker and ghost fixture")
		get_tree().quit(0)
		return
	for error in _errors:
		push_error(error)
	get_tree().quit(1)
'''


SCENE_SOURCE = '''[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://tests/out/golden_line_fixture.gd" id="1_fixture"]

[node name="GoldenLineFixture" type="Node"]
script = ExtResource("1_fixture")
'''


def main() -> int:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    sim_command = [
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
        "--replay=tests/golden/cedar_hollow_bog_bottom_replay.json",
        "--spawn=trailhead",
        "--target=bog_bottom",
        "--seed=12345",
        "--max-ticks=840",
        "--stuck-window=120",
        "--stuck-min-progress=0.05",
        f"--out={SIM_OUTPUT.relative_to(ROOT)}",
    ]
    sim_result = subprocess.run(sim_command, cwd=ROOT, check=False)
    if sim_result.returncode != 0:
        return sim_result.returncode
    FIXTURE_SCRIPT.write_text(SCRIPT_SOURCE)
    FIXTURE_SCENE.write_text(SCENE_SOURCE)
    command = [
        GODOT_BIN,
        "--headless",
        "--fixed-fps",
        "120",
        "--path",
        str(ROOT),
        "res://tests/out/golden_line_fixture.tscn",
    ]
    return subprocess.run(command, cwd=ROOT, check=False).returncode


if __name__ == "__main__":
    sys.exit(main())
