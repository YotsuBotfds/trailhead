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


func next_input(state: RefCounted) -> RefCounted:
	var input: RefCounted = VehicleInputScript.new()
	if scenario_id == "ebrake_drift":
		_fill_ebrake_drift(input)
	elif scenario_id == "launch_wheelie":
		_fill_launch_wheelie(input)
	elif scenario_id == "reverse_drive":
		_fill_reverse_drive(input)
	elif scenario_id == "reverse_steer_right":
		_fill_reverse_steer_right(input)
	elif scenario_id == "standstill_yaw_rate":
		_fill_standstill_yaw_rate(input)
	elif scenario_id == "offtrail_escape":
		_fill_offtrail_escape(input)
	elif scenario_id == "recover_to_trail":
		_fill_recover_to_trail(input)
	elif scenario_id == "hill_hold":
		_fill_hill_hold(input)
	elif scenario_id == "lateral_slide":
		_fill_lateral_slide(input)
	elif scenario_id == "suspension_drop":
		_fill_suspension_drop(input)
	elif scenario_id == "roll_stability":
		_fill_roll_stability(input)
	elif scenario_id == "steering_speed_ramp":
		_fill_steering_speed_ramp(input)
	elif scenario_id == "surface_sweep":
		_fill_surface_sweep(input)
	elif scenario_id == "clip_descent":
		_fill_clip_descent(input, state)
	elif scenario_id == "log_ramp":
		_fill_log_ramp(input, state)
	else:
		_done = true
		input.set("brake", GameConfig.scripted_stop_brake)
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
		input.set("steer", GameConfig.drift_probe_ebrake_steer)
		input.set("ebrake", true)
	elif _tick < recover_end_tick:
		input.set("throttle", GameConfig.drift_probe_recover_throttle)
		input.set("brake", GameConfig.drift_probe_recover_brake)
	else:
		input.set("brake", GameConfig.scripted_stop_brake)
		_done = true


func _fill_launch_wheelie(input: RefCounted) -> void:
	if _tick < GameConfig.wheelie_probe_ticks:
		input.set("throttle", GameConfig.wheelie_probe_throttle)
	else:
		input.set("brake", GameConfig.scripted_stop_brake)
		_done = true


func _fill_reverse_drive(input: RefCounted) -> void:
	if _tick < GameConfig.reverse_probe_ticks:
		input.set("throttle", GameConfig.reverse_probe_throttle)
	else:
		input.set("brake", GameConfig.scripted_stop_brake)
		_done = true


func _fill_reverse_steer_right(input: RefCounted) -> void:
	if _tick < GameConfig.reverse_steer_probe_ticks:
		input.set("throttle", GameConfig.reverse_steer_probe_throttle)
		input.set("steer", GameConfig.reverse_steer_probe_steer)
	else:
		input.set("brake", GameConfig.scripted_stop_brake)
		_done = true


func _fill_standstill_yaw_rate(input: RefCounted) -> void:
	if _tick < GameConfig.standstill_yaw_probe_ticks:
		input.set("steer", GameConfig.standstill_yaw_probe_steer)
	else:
		input.set("brake", GameConfig.scripted_stop_brake)
		_done = true


func _fill_offtrail_escape(input: RefCounted) -> void:
	if _tick < GameConfig.offtrail_escape_probe_ticks:
		input.set("throttle", GameConfig.offtrail_escape_probe_throttle)
	else:
		input.set("brake", GameConfig.scripted_stop_brake)
		_done = true


func _fill_recover_to_trail(input: RefCounted) -> void:
	var request_end_tick: int = GameConfig.recovery_probe_drive_ticks + GameConfig.recovery_probe_request_ticks
	if _tick < GameConfig.recovery_probe_drive_ticks:
		input.set("throttle", GameConfig.recovery_probe_throttle)
	elif _tick < request_end_tick:
		input.set("throttle", GameConfig.recovery_probe_throttle)
		input.set("self_right", true)
	else:
		input.set("brake", GameConfig.scripted_stop_brake)
		_done = true


func _fill_hill_hold(input: RefCounted) -> void:
	if _tick >= GameConfig.hill_hold_probe_ticks:
		input.set("brake", GameConfig.scripted_stop_brake)
		_done = true


func _fill_lateral_slide(input: RefCounted) -> void:
	var steer_end_tick: int = GameConfig.lateral_slide_accel_ticks + GameConfig.lateral_slide_steer_ticks
	var settle_end_tick: int = steer_end_tick + GameConfig.lateral_slide_settle_ticks
	if _tick < GameConfig.lateral_slide_accel_ticks:
		input.set("throttle", GameConfig.lateral_slide_throttle)
	elif _tick < steer_end_tick:
		input.set("throttle", GameConfig.lateral_slide_ebrake_throttle)
		input.set("steer", GameConfig.lateral_slide_steer)
		input.set("ebrake", true)
	elif _tick < settle_end_tick:
		pass
	else:
		input.set("brake", GameConfig.scripted_stop_brake)
		_done = true


func _fill_suspension_drop(input: RefCounted) -> void:
	if _tick >= GameConfig.suspension_drop_probe_ticks:
		input.set("brake", GameConfig.scripted_stop_brake)
		_done = true


func _fill_roll_stability(input: RefCounted) -> void:
	if _tick < GameConfig.roll_stability_probe_ticks:
		input.set("throttle", GameConfig.roll_stability_probe_throttle)
	else:
		input.set("brake", GameConfig.scripted_stop_brake)
		_done = true


func _fill_steering_speed_ramp(input: RefCounted) -> void:
	if _tick < GameConfig.steering_speed_probe_ticks:
		input.set("throttle", GameConfig.steering_speed_probe_throttle)
		input.set("steer", GameConfig.steering_speed_probe_steer)
	else:
		input.set("brake", GameConfig.scripted_stop_brake)
		_done = true


func _fill_surface_sweep(input: RefCounted) -> void:
	if _tick < GameConfig.surface_probe_ticks:
		input.set("throttle", GameConfig.surface_probe_throttle)
		if _tick >= GameConfig.surface_probe_steer_start_tick:
			input.set("steer", GameConfig.surface_probe_steer)
	else:
		input.set("brake", GameConfig.scripted_stop_brake)
		_done = true


func _fill_log_ramp(input: RefCounted, state: RefCounted) -> void:
	if _tick >= GameConfig.log_ramp_probe_ticks:
		input.set("brake", GameConfig.scripted_stop_brake)
		_done = true
		return
	var state_position: Vector3 = state.get("position")
	var state_basis: Basis = state.get("basis")
	var to_target: Vector3 = GameConfig.log_ramp_probe_target - state_position
	to_target.y = 0.0
	var fwd: Vector3 = -state_basis.z
	fwd.y = 0.0
	if fwd.length() <= GameConfig.log_ramp_probe_forward_epsilon:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()
	var desired: Vector3 = Vector3.FORWARD
	if to_target.length() > GameConfig.log_ramp_probe_forward_epsilon:
		desired = to_target.normalized()
	var heading_error: float = signf(fwd.cross(desired).y) * fwd.angle_to(desired)
	input.set("steer", clampf(heading_error * GameConfig.log_ramp_probe_steer_gain, -1.0, 1.0))
	input.set("throttle", GameConfig.log_ramp_probe_throttle)


func _fill_clip_descent(input: RefCounted, state: RefCounted) -> void:
	if _tick >= GameConfig.clip_descent_probe_ticks:
		input.set("brake", GameConfig.scripted_stop_brake)
		_done = true
		return
	var state_position: Vector3 = state.get("position")
	var state_basis: Basis = state.get("basis")
	var to_target: Vector3 = GameConfig.clip_descent_probe_target - state_position
	to_target.y = 0.0
	var fwd: Vector3 = -state_basis.z
	fwd.y = 0.0
	if fwd.length() <= GameConfig.log_ramp_probe_forward_epsilon:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()
	var desired: Vector3 = Vector3.FORWARD
	if to_target.length() > GameConfig.log_ramp_probe_forward_epsilon:
		desired = to_target.normalized()
	var heading_error: float = signf(fwd.cross(desired).y) * fwd.angle_to(desired)
	input.set("steer", clampf(heading_error * GameConfig.clip_descent_probe_steer_gain, -1.0, 1.0))
	input.set("throttle", GameConfig.clip_descent_probe_throttle)
