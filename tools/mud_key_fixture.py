#!/usr/bin/env python3
"""Run the GL-3a Mud Key trigger headless fixture."""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
GODOT_BIN = os.environ.get("GODOT_BIN", "/Applications/Godot.app/Contents/MacOS/Godot")
SUCCESS_LINE = "ok: MudKeyTrigger enables the cluster only for a dirty first approach"
TEMP_SCRIPT = ROOT / "tools" / ".mud_key_fixture_tmp.gd"
TEMP_SCENE = ROOT / "tools" / ".mud_key_fixture_tmp.tscn"

FIXTURE_SCRIPT = r'''extends Node

const MudKeyTriggerScript: GDScript = preload("res://systems/world/mud_key_trigger.gd")
const VehicleStateScript: GDScript = preload("res://systems/vehicle/vehicle_state.gd")
const MudKeyClusterScene: PackedScene = preload("res://scenes/world/easter_eggs/mud_key_cluster.tscn")

var _errors: PackedStringArray = PackedStringArray()
var _event_count: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	if not EventBus.world_egg_triggered.is_connected(_on_world_egg_triggered):
		EventBus.world_egg_triggered.connect(_on_world_egg_triggered)
	_assert_dirty_first_approach_triggers_once()
	_assert_clean_first_approach_stays_disabled()
	_assert_clean_first_approach_is_latched()
	if EventBus.world_egg_triggered.is_connected(_on_world_egg_triggered):
		EventBus.world_egg_triggered.disconnect(_on_world_egg_triggered)
	if _errors.is_empty():
		print("ok: MudKeyTrigger enables the cluster only for a dirty first approach")
		get_tree().quit(0)
		return
	for error in _errors:
		push_error(error)
	get_tree().quit(1)


func _assert_dirty_first_approach_triggers_once() -> void:
	var start_events: int = _event_count
	var trigger: Node3D = _make_trigger("DirtyFirstApproach")
	var dirty_state: RefCounted = _make_state(Vector3(0.05, 0.0, 0.0), GameConfig.egg_mud_key_threshold + 0.05)
	var fired: bool = bool(trigger.call("sample_vehicle_state", dirty_state))
	if not fired:
		_errors.append("dirty first approach did not return true")
	if not bool(trigger.call("was_checked")):
		_errors.append("dirty first approach did not mark the trigger checked")
	if not bool(trigger.call("was_triggered")):
		_errors.append("dirty first approach did not mark the trigger fired")
	if not bool(trigger.call("cluster_enabled")):
		_errors.append("dirty first approach did not enable the cluster")
	var fired_again: bool = bool(trigger.call("sample_vehicle_state", dirty_state))
	if fired_again:
		_errors.append("dirty trigger returned true on a second sample")
	if _event_count != start_events + 1:
		_errors.append("dirty first approach expected one mud_key event, got " + str(_event_count - start_events))


func _assert_clean_first_approach_stays_disabled() -> void:
	var start_events: int = _event_count
	var trigger: Node3D = _make_trigger("CleanFirstApproach")
	var clean_state: RefCounted = _make_state(Vector3(0.05, 0.0, 0.0), GameConfig.egg_mud_key_threshold - 0.05)
	var fired: bool = bool(trigger.call("sample_vehicle_state", clean_state))
	if fired:
		_errors.append("clean first approach returned true")
	if not bool(trigger.call("was_checked")):
		_errors.append("clean first approach did not mark the trigger checked")
	if bool(trigger.call("was_triggered")):
		_errors.append("clean first approach marked the trigger fired")
	if bool(trigger.call("cluster_enabled")):
		_errors.append("clean first approach enabled the cluster")
	if _event_count != start_events:
		_errors.append("clean first approach emitted a mud_key event")


func _assert_clean_first_approach_is_latched() -> void:
	var start_events: int = _event_count
	var trigger: Node3D = _make_trigger("CleanThenDirtyApproach")
	var clean_state: RefCounted = _make_state(Vector3(0.05, 0.0, 0.0), 0.0)
	var dirty_state: RefCounted = _make_state(Vector3(0.05, 0.0, 0.0), 1.0)
	trigger.call("sample_vehicle_state", clean_state)
	var fired_late: bool = bool(trigger.call("sample_vehicle_state", dirty_state))
	if fired_late:
		_errors.append("dirty second approach fired after a clean first approach")
	if bool(trigger.call("was_triggered")):
		_errors.append("clean-then-dirty trigger marked itself fired")
	if bool(trigger.call("cluster_enabled")):
		_errors.append("clean-then-dirty trigger enabled the cluster")
	if _event_count != start_events:
		_errors.append("clean-then-dirty trigger emitted a mud_key event")


func _make_trigger(node_name: String) -> Node3D:
	var holder: Node3D = Node3D.new()
	holder.name = node_name
	add_child(holder)
	var cluster: Node3D = MudKeyClusterScene.instantiate() as Node3D
	if cluster == null:
		_errors.append(node_name + " could not instantiate MudKeyCluster")
		return holder
	holder.add_child(cluster)
	var trigger: Node3D = MudKeyTriggerScript.new() as Node3D
	if trigger == null:
		_errors.append(node_name + " could not instantiate MudKeyTrigger")
		return holder
	holder.add_child(trigger)
	trigger.call("configure", cluster)
	return trigger


func _make_state(vehicle_position: Vector3, mud_scalar: float) -> RefCounted:
	var state: RefCounted = VehicleStateScript.new()
	state.set("position", vehicle_position)
	var contamination: RefCounted = state.get("contamination") as RefCounted
	contamination.call("set_values", mud_scalar, 0.0, 0.0)
	return state


func _on_world_egg_triggered(egg_id: StringName) -> void:
	if egg_id == &"mud_key":
		_event_count += 1
'''

FIXTURE_SCENE = '''[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://tools/.mud_key_fixture_tmp.gd" id="1_fixture"]

[node name="MudKeyFixture" type="Node"]
script = ExtResource("1_fixture")
'''


def main() -> int:
    TEMP_SCRIPT.write_text(FIXTURE_SCRIPT, encoding="utf-8")
    TEMP_SCENE.write_text(FIXTURE_SCENE, encoding="utf-8")
    try:
        command = [
            GODOT_BIN,
            "--headless",
            "--fixed-fps",
            "120",
            "--path",
            str(ROOT),
            "res://tools/.mud_key_fixture_tmp.tscn",
        ]
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
        if SUCCESS_LINE not in output:
            print("fail: mud key fixture did not report success", file=sys.stderr)
            return 1
        return 0
    finally:
        TEMP_SCENE.unlink(missing_ok=True)
        TEMP_SCRIPT.unlink(missing_ok=True)


if __name__ == "__main__":
    sys.exit(main())
