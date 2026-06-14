class_name PDWaypointController
extends RefCounted

const VehicleInputScript: GDScript = preload("res://systems/vehicle/vehicle_input.gd")

var target_pos: Vector3 = Vector3.ZERO
var arrive_radius: float = 0.35
var _kp: float = 2.0
var _kd: float = 0.4
var _prev_err: float = 0.0
var _done: bool = false


func configure(target: Vector3, radius: float) -> void:
	target_pos = target
	arrive_radius = radius
	_prev_err = 0.0
	_done = false


func next_input(state: RefCounted) -> RefCounted:
	var input: RefCounted = VehicleInputScript.new()
	var state_position: Vector3 = state.get("position")
	var state_basis: Basis = state.get("basis")
	var is_flipped: bool = bool(state.get("is_flipped"))
	var to_target: Vector3 = target_pos - state_position
	to_target.y = 0.0
	if to_target.length() <= arrive_radius:
		_done = true
		input.set("brake", 1.0)
		return input
	var fwd: Vector3 = -state_basis.z
	fwd.y = 0.0
	if fwd.length() <= 0.001:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()
	var desired: Vector3 = to_target.normalized()
	var err: float = signf(fwd.cross(desired).y) * fwd.angle_to(desired)
	var d_err: float = err - _prev_err
	_prev_err = err
	var steer: float = clampf(_kp * err + _kd * d_err, -1.0, 1.0)
	input.set("steer", steer)
	input.set("throttle", clampf(1.0 - absf(steer) * 0.55, 0.15, 1.0))
	if is_flipped:
		input.set("self_right", true)
	return input


func is_done() -> bool:
	return _done
