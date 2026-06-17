extends RefCounted

const ChaseCameraMath: GDScript = preload("res://systems/render/chase_camera_math.gd")

var initialized: bool = false
var look_target_current: Vector3 = Vector3.ZERO
var back_current: Vector3 = Vector3.ZERO
var up_current: Vector3 = Vector3.UP


func reset() -> void:
	initialized = false
	look_target_current = Vector3.ZERO
	back_current = Vector3.ZERO
	up_current = Vector3.UP


func update(camera: Camera3D, state: RefCounted, steer: float, _delta: float, speed_fov_enabled: bool, is_current: bool) -> void:
	if camera == null or state == null:
		return
	var vehicle_position: Vector3 = state.get("position")
	var vehicle_basis: Basis = state.get("basis")
	var back: Vector3 = ChaseCameraMath.rod_back(vehicle_basis, back_current)
	var up: Vector3 = ChaseCameraMath.rod_up(vehicle_basis, back, up_current)
	var desired_position: Vector3 = vehicle_position + back * GameConfig.cam_distance + up * GameConfig.cam_height
	if not initialized:
		camera.global_position = desired_position
		back_current = back
		up_current = up
		look_target_current = _look_target(camera, vehicle_position, back_current, up_current, steer)
		initialized = true
	else:
		back_current = back
		up_current = up
		camera.global_position = desired_position
		# Anchor look target to current vehicle position so world-space lag cannot invert the chase view.
		look_target_current = _look_target(camera, vehicle_position, back_current, up_current, steer)
	camera.look_at(look_target_current, up_current)
	if speed_fov_enabled:
		var linear_velocity: Vector3 = state.get("linear_velocity")
		camera.fov = GameConfig.get_fov_for_speed(linear_velocity.length())
	else:
		camera.fov = GameConfig.cam_fov_base
	camera.current = is_current


func _look_target(camera: Camera3D, vehicle_position: Vector3, back: Vector3, up: Vector3, steer: float) -> Vector3:
	var forward: Vector3 = -back
	var lateral: Vector3 = up.cross(back)
	if lateral.length() < 0.01:
		lateral = Vector3.RIGHT
	else:
		lateral = lateral.normalized()
	var target: Vector3 = vehicle_position \
		+ forward * GameConfig.cam_look_ahead \
		+ lateral * clampf(steer, -1.0, 1.0) * GameConfig.cam_look_turn_bias
	var sight_delta: Vector3 = target - camera.global_position
	var planar_delta: Vector3 = sight_delta - up * sight_delta.dot(up)
	var planar_distance: float = maxf(planar_delta.length(), 0.001)
	var desired_up_offset: float = tan(deg_to_rad(GameConfig.cam_pitch_deg)) * planar_distance
	var current_up_offset: float = sight_delta.dot(up)
	target += up * (desired_up_offset - current_up_offset)
	return target
