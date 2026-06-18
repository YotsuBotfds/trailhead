extends RefCounted

const ChaseCameraMath: GDScript = preload("res://systems/render/chase_camera_math.gd")

var initialized: bool = false
var look_target_current: Vector3 = Vector3.ZERO
var back_current: Vector3 = Vector3.ZERO
var up_current: Vector3 = Vector3.UP
var vehicle_y_current: float = 0.0


func reset() -> void:
	initialized = false
	look_target_current = Vector3.ZERO
	back_current = Vector3.ZERO
	up_current = Vector3.UP
	vehicle_y_current = 0.0


func update(camera: Camera3D, state: RefCounted, steer: float, delta: float, speed_fov_enabled: bool, is_current: bool) -> void:
	if camera == null or state == null:
		return
	var vehicle_position: Vector3 = state.get("position")
	var vehicle_basis: Basis = state.get("basis")
	var back: Vector3 = ChaseCameraMath.rod_back(vehicle_basis, back_current)
	var up: Vector3 = ChaseCameraMath.rod_up(vehicle_basis, back, up_current, GameConfig.cam_gimbal_up_smooth)
	var followed_position: Vector3 = _smoothed_follow_position(vehicle_position, delta)
	var desired_position: Vector3 = followed_position + back * GameConfig.cam_distance + up * GameConfig.cam_height
	if not initialized:
		camera.global_position = desired_position
		back_current = back
		up_current = up
		look_target_current = _look_target(camera, followed_position, back_current, up_current, steer)
		initialized = true
	else:
		back_current = back
		up_current = up
		var xz_alpha: float = clampf(GameConfig.cam_spring_xz * delta, 0.0, 1.0)
		var y_alpha: float = clampf(GameConfig.cam_spring_vy * delta * 0.001, 0.0, 1.0)
		var target_xz: Vector3 = Vector3(desired_position.x, camera.global_position.y, desired_position.z)
		var target_y: Vector3 = Vector3(camera.global_position.x, desired_position.y, camera.global_position.z)
		camera.global_position = camera.global_position.lerp(target_xz, xz_alpha).lerp(target_y, y_alpha)
		# Anchor look target to current vehicle position so world-space lag cannot invert the chase view.
		look_target_current = _look_target(camera, followed_position, back_current, up_current, steer)
	camera.look_at(look_target_current, up_current)
	camera.rotate(camera.basis.z, -steer * deg_to_rad(GameConfig.cam_roll_steer_deg))
	if speed_fov_enabled:
		var linear_velocity: Vector3 = state.get("linear_velocity")
		camera.fov = GameConfig.get_fov_for_speed(linear_velocity.length())
	else:
		camera.fov = GameConfig.cam_fov_base
	camera.current = is_current


func _smoothed_follow_position(vehicle_position: Vector3, delta: float) -> Vector3:
	if not initialized:
		vehicle_y_current = vehicle_position.y
	else:
		var vertical_alpha: float = clampf(GameConfig.cam_vertical_follow_softness * delta, 0.0, 1.0)
		vehicle_y_current = lerpf(vehicle_y_current, vehicle_position.y, vertical_alpha)
	return Vector3(vehicle_position.x, vehicle_y_current, vehicle_position.z)


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
