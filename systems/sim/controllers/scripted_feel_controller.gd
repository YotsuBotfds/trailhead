class_name ScriptedFeelController
extends RefCounted

const VehicleInputScript: GDScript = preload("res://systems/vehicle/vehicle_input.gd")

var scenario_id: String = "ebrake_drift"
var _tick: int = 0
var _done: bool = false


func configure(id: String) -> void:
	scenario_id = id
	_tick = 0
	_done = false


func next_input(_state: RefCounted) -> RefCounted:
	var input: RefCounted = VehicleInputScript.new()
	if scenario_id == "ebrake_drift":
		_fill_ebrake_drift(input)
	elif scenario_id == "launch_wheelie":
		_fill_launch_wheelie(input)
	elif scenario_id == "surface_sweep":
		_fill_surface_sweep(input)
	else:
		_done = true
		input.set("brake", 1.0)
	_tick += 1
	return input


func is_done() -> bool:
	return _done


func _fill_ebrake_drift(input: RefCounted) -> void:
	var drift_start_tick: int = GameConfig.drift_probe_accel_ticks
	var drift_end_tick: int = drift_start_tick + GameConfig.drift_probe_ebrake_ticks
	var recover_end_tick: int = drift_end_tick + GameConfig.drift_probe_recover_ticks
	if _tick < drift_start_tick:
		input.set("throttle", GameConfig.drift_probe_accel_throttle)
	elif _tick < drift_end_tick:
		input.set("throttle", GameConfig.drift_probe_ebrake_throttle)
		input.set("steer", 1.0)
		input.set("ebrake", true)
	elif _tick < recover_end_tick:
		input.set("throttle", 0.2)
		input.set("brake", 0.2)
	else:
		input.set("brake", 1.0)
		_done = true


func _fill_launch_wheelie(input: RefCounted) -> void:
	if _tick < GameConfig.wheelie_probe_ticks:
		input.set("throttle", 1.0)
	else:
		input.set("brake", 1.0)
		_done = true


func _fill_surface_sweep(input: RefCounted) -> void:
	if _tick < GameConfig.surface_probe_ticks:
		input.set("throttle", GameConfig.surface_probe_throttle)
		if _tick >= GameConfig.surface_probe_steer_start_tick:
			input.set("steer", GameConfig.surface_probe_steer)
	else:
		input.set("brake", 1.0)
		_done = true
