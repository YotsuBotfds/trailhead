extends RefCounted

const ChaseCameraMath: GDScript = preload("res://systems/render/chase_camera_math.gd")

var initialized: bool = false
var look_target_current: Vector3 = Vector3.ZERO
var back_current: Vector3 = Vector3.ZERO


func reset() -> void:
	initialized = false
	look_target_current = Vector3.ZERO
	back_current = Vector3.ZERO


func update(camera: Camera3D, state: RefCounted, steer: float, delta: float, speed_fov_enabled: bool, is_current: bool) -> void:
	if camera == null or state == null:
		return
	var vehicle_position: Vector3 = state.get("position")
	var vehicle_basis: Basis = state.get("basis")
	var back: Vector3 = ChaseCameraMath.rod_back(vehicle_basis, back_current)
	var forward: Vector3 = -back
	var desired_position: Vector3 = vehicle_position + back * GameConfig.cam_distance + Vector3.UP * GameConfig.cam_height
	if not initialized:
		camera.global_position = desired_position
		back_current = back
		look_target_current = _look_target(camera, vehicle_position, vehicle_basis, forward, steer)
		initialized = true
	else:
		var yaw_alpha: float = _follow_alpha(delta, GameConfig.cam_yaw_spring)
		if back_current.dot(back) < -0.999:
			back_current = back
		else:
			back_current = back_current.slerp(back, yaw_alpha).normalized()
		var smoothed_desired: Vector3 = vehicle_position + back_current * GameConfig.cam_distance + Vector3.UP * GameConfig.cam_height
		var follow_alpha_y: float = _follow_alpha(delta, GameConfig.cam_spring_vy)
		var current_position: Vector3 = camera.global_position
		current_position.x = smoothed_desired.x
		current_position.y = lerpf(current_position.y, smoothed_desired.y, follow_alpha_y)
		current_position.z = smoothed_desired.z
		camera.global_position = current_position
		# Anchor look target to current vehicle position so world-space lag cannot invert the chase view.
		look_target_current = _look_target(camera, vehicle_position, vehicle_basis, forward, steer)
	camera.look_at(look_target_current, Vector3.UP)
	if speed_fov_enabled:
		var linear_velocity: Vector3 = state.get("linear_velocity")
		camera.fov = GameConfig.get_fov_for_speed(linear_velocity.length())
	else:
		camera.fov = GameConfig.cam_fov_base
	camera.current = is_current


func _follow_alpha(delta: float, spring: float) -> float:
	return clampf(1.0 - exp(-maxf(spring, 0.0) * delta), 0.0, 1.0)


func _look_target(camera: Camera3D, vehicle_position: Vector3, vehicle_basis: Basis, forward: Vector3, steer: float) -> Vector3:
	var lateral: Vector3 = vehicle_basis.x.normalized()
	var target: Vector3 = vehicle_position \
		+ forward * GameConfig.cam_look_ahead \
		+ lateral * clampf(steer, -1.0, 1.0) * GameConfig.cam_look_turn_bias
	var flat_delta: Vector3 = Vector3(target.x - camera.global_position.x, 0.0, target.z - camera.global_position.z)
	var horizontal_distance: float = maxf(flat_delta.length(), 0.001)
	target.y = camera.global_position.y + tan(deg_to_rad(GameConfig.cam_pitch_deg)) * horizontal_distance
	return target
