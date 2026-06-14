class_name PDWaypointController
extends RefCounted

const VehicleInputScript: GDScript = preload("res://systems/vehicle/vehicle_input.gd")

var target_pos: Vector3 = Vector3.ZERO
var arrive_radius: float = 0.35
var intermediate_radius: float = 0.35
var _kp: float = 2.0
var _kd: float = 0.4
var _prev_err: float = 0.0
var _done: bool = false
var _use_rough_throttle: bool = false
var _points: Array[Vector3] = []
var _target_index: int = 0


func configure(target: Vector3, radius: float) -> void:
	var points: Array[Vector3] = [target]
	configure_path(points, radius)


func configure_path(points: Array[Vector3], radius: float) -> void:
	configure_path_with_waypoint_radius(points, radius, radius, false)


func configure_path_with_waypoint_radius(points: Array[Vector3], waypoint_radius: float, final_radius: float, use_rough_throttle: bool) -> void:
	_points.clear()
	for point in points:
		_points.append(point)
	if _points.is_empty():
		_points.append(Vector3.ZERO)
	_target_index = 0
	target_pos = _points[_target_index]
	intermediate_radius = waypoint_radius
	arrive_radius = final_radius
	_use_rough_throttle = use_rough_throttle
	_prev_err = 0.0
	_done = false


func next_input(state: RefCounted) -> RefCounted:
	var input: RefCounted = VehicleInputScript.new()
	var state_position: Vector3 = state.get("position")
	var state_basis: Basis = state.get("basis")
	var is_flipped: bool = bool(state.get("is_flipped"))
	var to_target: Vector3 = target_pos - state_position
	to_target.y = 0.0
	while to_target.length() <= _current_arrive_radius() and _target_index < _points.size() - 1:
		_target_index += 1
		target_pos = _points[_target_index]
		_prev_err = 0.0
		to_target = target_pos - state_position
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
	var throttle: float = _throttle_for_steer(steer, bool(state.get("on_ground")))
	input.set("throttle", throttle)
	if is_flipped:
		input.set("self_right", true)
	return input


func is_done() -> bool:
	return _done


func _current_arrive_radius() -> float:
	if _target_index >= _points.size() - 1:
		return arrive_radius
	return intermediate_radius


func _throttle_for_steer(steer: float, on_ground: bool) -> float:
	if not _use_rough_throttle:
		return clampf(1.0 - absf(steer) * GameConfig.pd_waypoint_default_steer_throttle_drop, GameConfig.pd_waypoint_default_min_throttle, 1.0)
	var throttle: float = clampf(1.0 - absf(steer) * GameConfig.pd_waypoint_steer_throttle_drop, GameConfig.pd_waypoint_min_throttle, 1.0)
	if not on_ground:
		throttle = minf(throttle, GameConfig.pd_waypoint_air_throttle)
	return throttle
