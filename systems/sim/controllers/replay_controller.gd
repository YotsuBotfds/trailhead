class_name ReplayController
extends RefCounted

const VehicleInputScript: GDScript = preload("res://systems/vehicle/vehicle_input.gd")

var _inputs: Array[Dictionary] = []
var _expected_samples: Array = []
var _expected_tolerances: Dictionary = {}
var _expected_predicates: Dictionary = {}
var _expected_ticks: int = 0
var _tick: int = 0
var _done: bool = true
var _last_error: String = ""


func configure_empty() -> void:
	_inputs.clear()
	_expected_samples.clear()
	_expected_tolerances.clear()
	_expected_predicates.clear()
	_expected_ticks = 0
	_tick = 0
	_done = true
	_last_error = ""


func configure_from_file(path: String) -> bool:
	_inputs.clear()
	_tick = 0
	_done = false
	_last_error = ""
	var resolved_path: String = _resolve_path(path)
	var file: FileAccess = FileAccess.open(resolved_path, FileAccess.READ)
	if file == null:
		_last_error = "failed to open replay file: " + path
		_done = true
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		_last_error = "replay file root is not a dictionary: " + path
		_done = true
		return false
	var data: Dictionary = parsed
	if not data.has("inputs") or not (data["inputs"] is Array):
		_last_error = "replay file missing inputs array: " + path
		_done = true
		return false
	var raw_inputs: Array = data["inputs"]
	for value in raw_inputs:
		if value is Dictionary:
			_inputs.append(value)
	if _inputs.is_empty():
		_last_error = "replay file has no input rows: " + path
		_done = true
		return false
	_expected_ticks = int(data.get("ticks", _inputs.size()))
	if data.has("samples") and data["samples"] is Array:
		_expected_samples = data["samples"]
	if data.has("tolerances") and data["tolerances"] is Dictionary:
		_expected_tolerances = data["tolerances"]
	if data.has("predicates") and data["predicates"] is Dictionary:
		_expected_predicates = data["predicates"]
	return true


func next_input(_state: RefCounted) -> RefCounted:
	var input: RefCounted = VehicleInputScript.new()
	if _tick >= _inputs.size():
		_done = true
		return input
	var row: Dictionary = _inputs[_tick]
	input.set("throttle", float(row.get("throttle", 0.0)))
	input.set("steer", float(row.get("steer", 0.0)))
	input.set("brake", float(row.get("brake", 0.0)))
	input.set("ebrake", bool(row.get("ebrake", false)))
	input.set("self_right", bool(row.get("self_right", false)))
	_tick += 1
	if _tick >= _inputs.size():
		_done = true
	return input


func is_done() -> bool:
	return _done


func last_error() -> String:
	return _last_error


func expected_ticks() -> int:
	return _expected_ticks


func expected_samples() -> Array:
	return _expected_samples


func expected_tolerances() -> Dictionary:
	return _expected_tolerances


func expected_predicates() -> Dictionary:
	return _expected_predicates


func _resolve_path(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://") or path.begins_with("/"):
		return path
	return "res://" + path
