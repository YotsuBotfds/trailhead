extends RefCounted

const ChaseCameraMath: GDScript = preload("res://systems/render/chase_camera_math.gd")

var initialized: bool = false
var look_target_current: Vector3 = Vector3.ZERO
var back_current: Vector3 = Vector3.ZERO
var up_current: Vector3 = Vector3.UP
var vehicle_y_current: float = 0.0
var _bank_current_deg: float = 0.0
var _pitch_current_deg: float = 0.0
# Stop-lock hysteresis state (host-only). True once the vehicle drops below
# cam_stop_lock_speed; stays true until speed exceeds cam_stop_lock_release_speed.
var _stop_locked: bool = false


func reset() -> void:
	initialized = false
	look_target_current = Vector3.ZERO
	back_current = Vector3.ZERO
	up_current = Vector3.UP
	vehicle_y_current = 0.0
	_bank_current_deg = 0.0
	_pitch_current_deg = 0.0
	_stop_locked = false


func update(camera: Camera3D, state: RefCounted, steer: float, delta: float, speed_fov_enabled: bool, is_current: bool, lateral_accel: float = 0.0, longitudinal_accel: float = 0.0) -> void:
	if camera == null or state == null:
		return
	var vehicle_position: Vector3 = state.get("position")
	var vehicle_basis: Basis = state.get("basis")
	var linear_velocity: Vector3 = state.get("linear_velocity")
	var angular_velocity: Vector3 = state.get("angular_velocity")
	var speed: float = linear_velocity.length()
	var yaw_speed: float = absf(angular_velocity.y)
	# Stop-lock hysteresis: enter below cam_stop_lock_speed, release above the
	# higher cam_stop_lock_release_speed so the lock doesn't chatter at the
	# threshold. Below the lock the vehicle's never-sleeping rigid body still
	# emits sub-tick basis/velocity jitter, which the 1:1 hard-follow + accel/delta
	# path amplifies into visible shake; freezing pose + accel terms kills it.
	var lock_speed: float = GameConfig.cam_stop_lock_speed
	var release_speed: float = GameConfig.cam_stop_lock_release_speed
	var yaw_release_speed: float = GameConfig.cam_stop_lock_yaw_speed
	if not _stop_locked:
		if initialized and speed < lock_speed and yaw_speed < yaw_release_speed:
			_stop_locked = true
	else:
		if speed > release_speed or yaw_speed >= yaw_release_speed:
			# Released: snap to the live pose this frame (do NOT lerp from the
			# stale frozen state -- that would swing the camera on takeoff).
			_stop_locked = false
	if not initialized or _stop_locked:
		# Frozen path: keep the prior camera transform/look/bank/pitch exactly.
		# We still re-apply camera.current/FOV so toggles remain responsive.
		if not initialized:
			var back_init: Vector3 = ChaseCameraMath.rod_back(vehicle_basis, back_current)
			var up_init: Vector3 = ChaseCameraMath.rod_up(vehicle_basis, back_init, up_current, GameConfig.cam_gimbal_up_smooth)
			var followed_init: Vector3 = _smoothed_follow_position(vehicle_position, delta)
			camera.global_position = followed_init + back_init * GameConfig.cam_distance + up_init * GameConfig.cam_height
			back_current = back_init
			up_current = up_init
			look_target_current = _look_target(camera, followed_init, back_current, up_current, steer)
			_bank_current_deg = 0.0
			_pitch_current_deg = 0.0
			initialized = true
		camera.look_at(look_target_current, up_current)
		camera.rotate(camera.basis.z, deg_to_rad(_bank_current_deg))
		camera.rotate(camera.basis.x, deg_to_rad(_pitch_current_deg))
	else:
		var back: Vector3 = ChaseCameraMath.rod_back(vehicle_basis, back_current)
		var up: Vector3 = ChaseCameraMath.rod_up(vehicle_basis, back, up_current, GameConfig.cam_gimbal_up_smooth)
		var followed_position: Vector3 = _smoothed_follow_position(vehicle_position, delta)
		var desired_position: Vector3 = followed_position + back * GameConfig.cam_distance + up * GameConfig.cam_height
		# Rigid follow of the gimbaled, vertically-softened target. The W10 spring-damp lerp
		# introduced lateral lag that, at speed, read as the camera "zooming far back" and let
		# it dip underground at certain angles — both reported regressions. Vertical smoothing
		# still happens in _smoothed_follow_position; the gimbal (rod_back/rod_up) still levels
		# the horizon. This keeps the steady chase the owner had before W10-camera.
		camera.global_position = desired_position
		back_current = back
		up_current = up
		look_target_current = _look_target(camera, followed_position, back_current, up_current, steer)
		camera.look_at(look_target_current, up_current)
		var roll_target_deg: float = clampf(
				-(lateral_accel * GameConfig.cam_bank_lateral_gain
						+ steer * GameConfig.cam_roll_steer_deg),
				-GameConfig.cam_bank_max_deg,
				GameConfig.cam_bank_max_deg
		)
		var pitch_target_deg: float = clampf(
				longitudinal_accel * GameConfig.cam_pitch_accel_gain,
				-GameConfig.cam_pitch_max_deg,
				GameConfig.cam_pitch_max_deg
		)
		var bank_alpha: float = clampf(GameConfig.cam_bank_smooth * delta, 0.0, 1.0)
		_bank_current_deg = lerpf(_bank_current_deg, roll_target_deg, bank_alpha)
		_pitch_current_deg = lerpf(_pitch_current_deg, pitch_target_deg, bank_alpha)
		camera.rotate(camera.basis.z, deg_to_rad(_bank_current_deg))
		camera.rotate(camera.basis.x, deg_to_rad(_pitch_current_deg))
	if speed_fov_enabled:
		camera.fov = GameConfig.get_fov_for_speed(speed)
	else:
		camera.fov = GameConfig.cam_fov_base
	camera.current = is_current


func _smoothed_follow_position(vehicle_position: Vector3, delta: float) -> Vector3:
	if not initialized:
		vehicle_y_current = vehicle_position.y
	else:
		var vertical_alpha: float = clampf(GameConfig.cam_vertical_follow_softness * delta, 0.0, 1.0)
		vehicle_y_current = lerpf(vehicle_y_current, vehicle_position.y, vertical_alpha)
		var max_drop_lag: float = maxf(GameConfig.cam_vertical_follow_max_drop_lag, 0.0)
		vehicle_y_current = minf(vehicle_y_current, vehicle_position.y + max_drop_lag)
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
