class_name RaycastVehicleController
extends "res://systems/vehicle/vehicle_controller.gd"

const RaycastVehicleInputScript: GDScript = preload("res://systems/vehicle/vehicle_input.gd")
const RaycastVehicleStateScript: GDScript = preload("res://systems/vehicle/vehicle_state.gd")
const VehicleContaminationStateScript: GDScript = preload("res://systems/vehicle/vehicle_contamination_state.gd")

var _body: RigidBody3D = null
var _wheel_rays: Array[RayCast3D] = []
var _pending_input: RefCounted = RaycastVehicleInputScript.new()
var _state: RefCounted = RaycastVehicleStateScript.new()
var _was_flipped: bool = false
var _current_surface_id: StringName = &""
var _surface_friction: float = 0.0
var _surface_rolling_drag: float = 0.0
var _surface_slip: float = 0.0
var _surface_normal_load: float = 0.0
var _surface_contact_normal: Vector3 = Vector3.UP
var _surface_bog_enabled: bool = false
var _surface_bog_threshold: float = 0.0
var _last_stable_forward: Vector3 = Vector3.FORWARD
var _last_recovery_transform: Transform3D = Transform3D.IDENTITY
var _recovery_position_history: Array[Vector3] = []
var _recovery_transform_history: Array[Transform3D] = []
var _recovery_stuck: bool = false


func _ready() -> void:
	_reset_surface_cache()
	_build_physics_body()
	GameManager.register_vehicle(self)


func apply_input(input: RefCounted) -> void:
	_pending_input.set("throttle", clampf(float(input.get("throttle")), -1.0, 1.0))
	_pending_input.set("steer", clampf(float(input.get("steer")), -1.0, 1.0))
	_pending_input.set("brake", clampf(float(input.get("brake")), 0.0, 1.0))
	_pending_input.set("ebrake", bool(input.get("ebrake")))
	_pending_input.set("self_right", bool(input.get("self_right")))


func get_state() -> RefCounted:
	_update_state()
	return _state


func reset_to(spawn: Transform3D) -> void:
	if _body == null:
		return
	_body.global_transform = spawn
	_body.linear_velocity = Vector3.ZERO
	_body.angular_velocity = Vector3.ZERO
	_pending_input.call("clear")
	_was_flipped = false
	_current_surface_id = &""
	_last_stable_forward = _horizontal_forward(spawn.basis)
	_last_recovery_transform = _upright_transform(spawn.origin, _last_stable_forward)
	_recovery_position_history.clear()
	_recovery_transform_history.clear()
	_recovery_stuck = false
	_vehicle_contamination().call("reset")
	_update_state()


func self_right() -> void:
	if _body == null:
		return
	var from_position: Vector3 = _body.global_position
	var forward: Vector3 = _last_stable_forward
	var t: Transform3D = _upright_transform(from_position, forward)
	t.origin.y += GameConfig.self_right_lift
	_body.global_transform = t
	_body.linear_velocity *= GameConfig.self_right_velocity_retention
	_body.angular_velocity = Vector3.ZERO
	EventBus.vehicle_self_righted.emit()


func recover_to_trail() -> void:
	if _body == null or not GameConfig.recover_to_trail_enabled:
		return
	var from_position: Vector3 = _body.global_position
	var anchor: Transform3D = _last_recovery_transform
	var forward: Vector3 = _horizontal_forward(anchor.basis)
	var t: Transform3D = _upright_transform(anchor.origin, forward)
	t.origin.y += GameConfig.recover_lift
	_body.global_transform = t
	_body.linear_velocity *= GameConfig.recover_speed_retention
	_body.angular_velocity = Vector3.ZERO
	_last_stable_forward = forward
	_last_recovery_transform = _upright_transform(anchor.origin, forward)
	_recovery_position_history.clear()
	_recovery_transform_history.clear()
	_recovery_stuck = false
	EventBus.vehicle_recovered_to_trail.emit(from_position, t.origin)
	_update_state()


func _physics_process(_delta: float) -> void:
	if _body == null:
		return
	_update_flip_events()
	_update_recovery_tracking()
	if bool(_pending_input.get("self_right")):
		if _is_flipped():
			self_right()
		elif _recovery_stuck:
			recover_to_trail()
	_apply_wheel_forces()
	_apply_drive_forces()
	_apply_speed_limit()


func _build_physics_body() -> void:
	_body = RigidBody3D.new()
	_body.name = "PhysicsBody"
	_body.mass = GameConfig.chassis_mass
	_body.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	_body.center_of_mass = GameConfig.center_of_mass_offset
	add_child(_body)

	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.name = "Collision"
	var box: BoxShape3D = BoxShape3D.new()
	box.size = GameConfig.chassis_collision_size
	collision.shape = box
	_body.add_child(collision)

	_add_wheel_ray(&"wheel_fl", Vector3(-GameConfig.wheel_half_track, 0.0, -GameConfig.wheel_half_base))
	_add_wheel_ray(&"wheel_fr", Vector3(GameConfig.wheel_half_track, 0.0, -GameConfig.wheel_half_base))
	_add_wheel_ray(&"wheel_rl", Vector3(-GameConfig.wheel_half_track, 0.0, GameConfig.wheel_half_base))
	_add_wheel_ray(&"wheel_rr", Vector3(GameConfig.wheel_half_track, 0.0, GameConfig.wheel_half_base))


func _add_wheel_ray(wheel_name: StringName, local_position: Vector3) -> void:
	var ray: RayCast3D = RayCast3D.new()
	ray.name = String(wheel_name)
	ray.position = local_position
	ray.target_position = Vector3.DOWN * (GameConfig.susp_rest_length + GameConfig.susp_travel + GameConfig.wheel_radius)
	ray.enabled = true
	_body.add_child(ray)
	_wheel_rays.append(ray)


func _apply_wheel_forces() -> void:
	var up: Vector3 = _body.global_transform.basis.y.normalized()
	var ray_length: float = GameConfig.susp_rest_length + GameConfig.susp_travel + GameConfig.wheel_radius
	var contact_count: int = 0
	var friction_sum: float = 0.0
	var rolling_drag_sum: float = 0.0
	var slip_sum: float = 0.0
	var normal_load_sum: float = 0.0
	var normal_sum: Vector3 = Vector3.ZERO
	var bog_threshold_sum: float = 0.0
	var mud_residue_sum: float = 0.0
	var dust_residue_sum: float = 0.0
	var wetness_residue_sum: float = 0.0
	var bog_enabled: bool = false
	var wheel_compressions: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var wheel_force_positions: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	var wheel_contacts: Array[bool] = [false, false, false, false]
	for i in range(_wheel_rays.size()):
		var ray: RayCast3D = _wheel_rays[i]
		ray.force_raycast_update()
		var has_contact: bool = ray.is_colliding()
		wheel_contacts[i] = has_contact
		var wheel_contact: Array[bool] = _state.get("wheel_contact")
		wheel_contact[i] = has_contact
		_state.set("wheel_contact", wheel_contact)
		if not has_contact:
			var empty_surface: Array[StringName] = _state.get("wheel_surface")
			empty_surface[i] = &""
			_state.set("wheel_surface", empty_surface)
			var empty_hit_points: Array[Vector3] = _state.get("wheel_hit_point")
			empty_hit_points[i] = Vector3.ZERO
			_state.set("wheel_hit_point", empty_hit_points)
			continue
		contact_count += 1
		var hit_point: Vector3 = ray.get_collision_point()
		var hit_normal: Vector3 = ray.get_collision_normal()
		if hit_normal.length() <= GameConfig.self_right_forward_epsilon:
			hit_normal = Vector3.UP
		normal_sum += hit_normal.normalized()
		var wheel_hit_points: Array[Vector3] = _state.get("wheel_hit_point")
		wheel_hit_points[i] = hit_point
		_state.set("wheel_hit_point", wheel_hit_points)
		var dist: float = ray.global_position.distance_to(hit_point)
		var compression: float = clampf((ray_length - dist) / maxf(GameConfig.susp_travel, 0.001), 0.0, 1.0)
		var spring_force: float = compression * GameConfig.susp_stiffness
		var force_pos: Vector3 = hit_point - _body.global_position
		wheel_compressions[i] = compression
		wheel_force_positions[i] = force_pos
		var center_of_mass_offset_world: Vector3 = _body.global_transform.basis * GameConfig.center_of_mass_offset
		var contact_arm: Vector3 = force_pos - center_of_mass_offset_world
		var contact_velocity: Vector3 = _body.linear_velocity + _body.angular_velocity.cross(contact_arm * GameConfig.susp_contact_angular_velocity_weight)
		var compression_velocity: float = -contact_velocity.dot(up)
		var damping_force: float = compression_velocity * GameConfig.susp_damping
		var max_damping_force: float = spring_force * GameConfig.susp_damping_force_ratio
		var suspension_force: float = maxf(0.0, spring_force + clampf(damping_force, -max_damping_force, max_damping_force))
		_body.apply_force(up * suspension_force, force_pos)
		normal_load_sum += suspension_force
		var surface_def: Resource = _resolve_surface_def(ray.get_collider(), hit_point)
		var surface_id: StringName = _surface_id(surface_def)
		var wheel_surface: Array[StringName] = _state.get("wheel_surface")
		wheel_surface[i] = surface_id
		_state.set("wheel_surface", wheel_surface)
		friction_sum += _surface_float(surface_def, "friction", GameConfig.default_friction)
		rolling_drag_sum += _surface_float(surface_def, "rolling_drag", GameConfig.default_rolling_drag)
		slip_sum += _surface_float(surface_def, "slip", GameConfig.default_slip)
		bog_threshold_sum += _surface_float(surface_def, "bog_threshold", GameConfig.default_bog_threshold)
		mud_residue_sum += _surface_float(surface_def, "mud_residue", 0.0)
		dust_residue_sum += _surface_float(surface_def, "dust_residue", 0.0)
		wetness_residue_sum += _surface_float(surface_def, "wetness_residue", 0.0)
		if _surface_bool(surface_def, "bog_enabled", false):
			bog_enabled = true
	_apply_anti_roll(wheel_compressions, wheel_force_positions, wheel_contacts, up)
	_state.set("on_ground", contact_count > 0)
	if contact_count > 0:
		_surface_friction = friction_sum / float(contact_count)
		_surface_rolling_drag = rolling_drag_sum / float(contact_count)
		_surface_slip = slip_sum / float(contact_count)
		_surface_normal_load = normal_load_sum
		_surface_contact_normal = normal_sum.normalized() if normal_sum.length() > GameConfig.self_right_forward_epsilon else Vector3.UP
		_surface_bog_enabled = bog_enabled
		_surface_bog_threshold = bog_threshold_sum / float(contact_count)
	else:
		_surface_friction = GameConfig.default_friction
		_surface_rolling_drag = GameConfig.default_rolling_drag
		_surface_slip = GameConfig.default_slip
		_surface_normal_load = 0.0
		_surface_contact_normal = Vector3.UP
		_surface_bog_enabled = false
		_surface_bog_threshold = GameConfig.default_bog_threshold
	_state.set("contact_normal", _surface_contact_normal)
	_update_contamination(contact_count, mud_residue_sum, dust_residue_sum, wetness_residue_sum)
	_update_surface_event()


func _apply_anti_roll(wheel_compressions: Array[float], wheel_force_positions: Array[Vector3], wheel_contacts: Array[bool], up: Vector3) -> void:
	if GameConfig.anti_roll_stiffness <= 0.0:
		return
	_apply_anti_roll_pair(0, 1, wheel_compressions, wheel_force_positions, wheel_contacts, up)
	_apply_anti_roll_pair(2, 3, wheel_compressions, wheel_force_positions, wheel_contacts, up)


func _apply_anti_roll_pair(left_index: int, right_index: int, wheel_compressions: Array[float], wheel_force_positions: Array[Vector3], wheel_contacts: Array[bool], up: Vector3) -> void:
	if not wheel_contacts[left_index] or not wheel_contacts[right_index]:
		return
	var compression_delta: float = wheel_compressions[left_index] - wheel_compressions[right_index]
	var anti_roll_force: Vector3 = up * compression_delta * GameConfig.anti_roll_stiffness
	_body.apply_force(anti_roll_force, wheel_force_positions[left_index])
	_body.apply_force(-anti_roll_force, wheel_force_positions[right_index])


func _apply_drive_forces() -> void:
	var forward: Vector3 = -_body.global_transform.basis.z.normalized()
	var right: Vector3 = _body.global_transform.basis.x.normalized()
	var throttle: float = float(_pending_input.get("throttle"))
	var steer: float = float(_pending_input.get("steer"))
	var brake: float = float(_pending_input.get("brake"))
	var on_ground: bool = bool(_state.get("on_ground"))
	_apply_traction_force(forward, throttle)
	if on_ground and brake > 0.0:
		var brake_factor: float = clampf(1.0 - brake * GameConfig.brake_damping_per_second * GameConfig.FIXED_DT, 0.0, 1.0)
		_body.linear_velocity *= brake_factor
	if on_ground:
		_apply_surface_drag()
		_apply_hill_hold(throttle, brake)
	if on_ground:
		var surface_grip: float = _surface_friction * maxf(1.0 - _surface_slip, GameConfig.surface_min_lateral_grip)
		var lateral_grip: float = surface_grip
		if bool(_pending_input.get("ebrake")):
			lateral_grip *= GameConfig.ebrake_factor
		_apply_lateral_grip(right, lateral_grip)
		_apply_steering_torque(steer, surface_grip)
	if on_ground and throttle >= GameConfig.launch_wheelie_min_throttle and absf(steer) <= GameConfig.launch_wheelie_max_steer and _body.linear_velocity.length() <= GameConfig.launch_wheelie_speed_max:
		_body.apply_torque(right * GameConfig.launch_wheelie_torque)


func _apply_traction_force(forward: Vector3, throttle: float) -> void:
	if not bool(_state.get("on_ground")) or absf(throttle) <= GameConfig.self_right_forward_epsilon:
		return
	var requested_force: float = absf(throttle) * maxf(GameConfig.motor_torque, GameConfig.traction_base_force)
	var traction_ceiling: float = maxf(0.0, _surface_friction * _surface_normal_load * GameConfig.traction_grip_force_ceiling_scale)
	var delivered_force: float = minf(requested_force, traction_ceiling)
	if delivered_force <= 0.0:
		return
	_body.apply_central_force(forward * signf(throttle) * delivered_force)


func _apply_hill_hold(throttle: float, brake: float) -> void:
	if absf(throttle) > GameConfig.self_right_forward_epsilon or brake > GameConfig.self_right_forward_epsilon or bool(_pending_input.get("ebrake")):
		return
	var normal: Vector3 = _surface_contact_normal
	if normal.length() <= GameConfig.self_right_forward_epsilon:
		normal = Vector3.UP
	normal = normal.normalized()
	var velocity_plane: Vector3 = _body.linear_velocity - normal * _body.linear_velocity.dot(normal)
	var static_limit: float = maxf(0.0, _surface_friction * GameConfig.hold_static_mu_scale * _surface_normal_load)
	var kinetic_limit: float = maxf(0.0, _surface_friction * GameConfig.hold_kinetic_mu_scale * _surface_normal_load)
	if velocity_plane.length() > GameConfig.v_stick:
		if kinetic_limit > 0.0:
			_body.apply_central_force(-velocity_plane.normalized() * kinetic_limit)
		return
	var gravity: Vector3 = GameConfig.GRAVITY_VECTOR
	var gravity_plane: Vector3 = gravity - normal * gravity.dot(normal)
	var requested_force: Vector3 = -_body.mass * ((velocity_plane / GameConfig.FIXED_DT) + gravity_plane)
	var hold_limit: float = static_limit
	if requested_force.length() > static_limit:
		hold_limit = kinetic_limit
	if hold_limit <= 0.0:
		return
	_body.apply_central_force(requested_force.limit_length(hold_limit))


func _apply_lateral_grip(right: Vector3, surface_grip: float) -> void:
	var lateral_speed: float = _body.linear_velocity.dot(right)
	var requested_force: Vector3 = -right * lateral_speed * (_body.mass / GameConfig.FIXED_DT)
	var max_lateral_force: float = maxf(0.0, surface_grip * _surface_normal_load * GameConfig.lateral_grip_force)
	if max_lateral_force <= 0.0:
		return
	_body.apply_central_force(requested_force.limit_length(max_lateral_force))


func _apply_steering_torque(steer: float, surface_grip: float) -> void:
	if absf(steer) <= GameConfig.self_right_forward_epsilon and absf(_body.angular_velocity.dot(Vector3.UP)) <= GameConfig.self_right_forward_epsilon:
		return
	var forward: Vector3 = -_body.global_transform.basis.z.normalized()
	var speed: float = Vector3(_body.linear_velocity.x, 0.0, _body.linear_velocity.z).length()
	_clamp_inplace_yaw_rate(speed)
	var speed_scale: float = _steer_yaw_speed_scale(speed)
	var current_yaw_rate: float = _body.angular_velocity.dot(Vector3.UP)
	var reverse_direction: float = -1.0 if _body.linear_velocity.dot(forward) < -maxf(GameConfig.steer_reverse_velocity_threshold, 0.0) else 1.0
	var target_yaw_rate: float = steer * reverse_direction * GameConfig.steer_max_yaw_rate * speed_scale
	if speed <= GameConfig.v_stick:
		var inplace_limit: float = maxf(GameConfig.steer_inplace_yaw_rate_max, 0.0)
		target_yaw_rate = clampf(target_yaw_rate, -inplace_limit, inplace_limit)
	var grip_scale: float = maxf(surface_grip, GameConfig.surface_min_lateral_grip)
	var response_scale: float = _steer_yaw_response_scale(speed)
	var corrective_torque: float = (target_yaw_rate - current_yaw_rate) * GameConfig.steer_yaw_torque * response_scale
	var damping_torque: float = -current_yaw_rate * GameConfig.steer_yaw_damping
	var max_yaw_torque: float = GameConfig.steer_yaw_torque * grip_scale * response_scale
	var yaw_torque: float = clampf((corrective_torque + damping_torque) * grip_scale, -max_yaw_torque, max_yaw_torque)
	_body.apply_torque(Vector3.UP * yaw_torque)


func _steer_yaw_speed_scale(speed: float) -> float:
	var half_speed: float = maxf(GameConfig.steer_speed_half, GameConfig.self_right_forward_epsilon)
	var speed_scale: float = speed / (speed + half_speed)
	if speed <= GameConfig.v_stick:
		speed_scale = maxf(speed_scale, GameConfig.steer_low_speed_pivot_scale)
	return clampf(speed_scale, 0.0, 1.0)


func _steer_yaw_response_scale(speed: float) -> float:
	var falloff: float = maxf(GameConfig.steer_high_speed_falloff, 0.0)
	if falloff <= GameConfig.self_right_forward_epsilon:
		return 1.0
	return clampf(1.0 / (1.0 + speed * falloff), 0.0, 1.0)


func _clamp_inplace_yaw_rate(speed: float) -> void:
	if speed > GameConfig.v_stick:
		return
	var yaw_rate_limit: float = maxf(GameConfig.steer_inplace_yaw_rate_max, 0.0)
	var current_yaw_rate: float = _body.angular_velocity.dot(Vector3.UP)
	if yaw_rate_limit <= GameConfig.self_right_forward_epsilon:
		_body.angular_velocity -= Vector3.UP * current_yaw_rate
		return
	if absf(current_yaw_rate) <= yaw_rate_limit:
		return
	var capped_yaw_rate: float = signf(current_yaw_rate) * yaw_rate_limit
	_body.angular_velocity -= Vector3.UP * (current_yaw_rate - capped_yaw_rate)


func _apply_surface_drag() -> void:
	var velocity_flat: Vector3 = Vector3(_body.linear_velocity.x, 0.0, _body.linear_velocity.z)
	var speed: float = velocity_flat.length()
	if speed <= 0.001:
		return
	var drag: float = _surface_rolling_drag * GameConfig.surface_rolling_drag_force
	var relief_scale: float = _surface_drag_relief_scale()
	drag *= relief_scale
	if _surface_bog_enabled and speed <= _surface_bog_threshold:
		drag += GameConfig.surface_bog_drag_force * relief_scale
	_body.apply_central_force(-velocity_flat.normalized() * drag * speed)


func _surface_drag_relief_scale() -> float:
	if _surface_friction >= GameConfig.default_friction:
		return 1.0
	var default_friction: float = maxf(GameConfig.default_friction, GameConfig.self_right_forward_epsilon)
	var friction_scale: float = clampf(_surface_friction / default_friction, 0.0, 1.0)
	var relief_strength: float = clampf(GameConfig.offtrail_drag_relief, 0.0, 1.0)
	return lerpf(1.0, friction_scale, relief_strength)


func _apply_speed_limit() -> void:
	var speed: float = _body.linear_velocity.length()
	if speed > GameConfig.max_speed:
		_body.linear_velocity = _body.linear_velocity.normalized() * GameConfig.max_speed


func _update_flip_events() -> void:
	var flipped: bool = _is_flipped()
	if flipped and not _was_flipped:
		EventBus.vehicle_flipped_over.emit()
	_was_flipped = flipped


func _update_surface_event() -> void:
	var surface_id: StringName = _dominant_contact_surface()
	if surface_id == &"" or surface_id == _current_surface_id:
		return
	_current_surface_id = surface_id
	EventBus.vehicle_changed_surface.emit(surface_id)


func _update_recovery_tracking() -> void:
	if not GameConfig.recover_to_trail_enabled:
		_recovery_stuck = false
		return
	var current_transform: Transform3D = _body.global_transform
	_recovery_position_history.append(current_transform.origin)
	_recovery_transform_history.append(current_transform)
	var window_ticks: int = maxi(GameConfig.recover_stuck_window_ticks, 1)
	while _recovery_position_history.size() > window_ticks + 1:
		_recovery_position_history.pop_front()
	while _recovery_transform_history.size() > window_ticks + 1:
		_recovery_transform_history.pop_front()
	_recovery_stuck = false
	if _recovery_position_history.size() <= window_ticks:
		return
	var previous_position: Vector3 = _recovery_position_history[0]
	var current_position: Vector3 = current_transform.origin
	var current_flat: Vector3 = Vector3(current_position.x, 0.0, current_position.z)
	var previous_flat: Vector3 = Vector3(previous_position.x, 0.0, previous_position.z)
	var progress: float = current_flat.distance_to(previous_flat)
	var stable: bool = _stable_wheel_contact_count() >= GameConfig.self_right_stable_contact_count and current_transform.basis.y.dot(Vector3.UP) >= GameConfig.self_right_stable_upright_dot
	if stable and progress >= GameConfig.recover_min_progress:
		var anchor_transform: Transform3D = _recovery_transform_history[0]
		var forward: Vector3 = _horizontal_forward(anchor_transform.basis)
		_last_recovery_transform = _upright_transform(anchor_transform.origin, forward)
	var throttle: float = absf(float(_pending_input.get("throttle")))
	if bool(_state.get("on_ground")) and throttle >= GameConfig.recover_min_throttle and progress < GameConfig.recover_min_progress:
		_recovery_stuck = true


func _dominant_contact_surface() -> StringName:
	var wheel_surface: Array[StringName] = _state.get("wheel_surface")
	var counts: Dictionary = {}
	var best_surface_id: StringName = &""
	var best_count: int = 0
	for surface_id in wheel_surface:
		if surface_id != &"":
			var current_count: int = int(counts.get(surface_id, 0)) + 1
			counts[surface_id] = current_count
			if current_count > best_count:
				best_surface_id = surface_id
				best_count = current_count
	return best_surface_id


func _resolve_surface_def(collider: Object, world_position: Vector3) -> Resource:
	var surface_map: Node = GameManager.active_surface_map
	if surface_map != null:
		var resolved: Resource = surface_map.call("resolve_from_collider_at", collider, world_position) as Resource
		if resolved != null:
			return resolved
	return null


func _surface_id(surface_def: Resource) -> StringName:
	if surface_def == null:
		return &"packed_dirt"
	var id_value: StringName = surface_def.get("id")
	if id_value == &"":
		return &"packed_dirt"
	return id_value


func _surface_float(surface_def: Resource, property_name: StringName, fallback: float) -> float:
	if surface_def == null:
		return fallback
	return float(surface_def.get(property_name))


func _surface_bool(surface_def: Resource, property_name: StringName, fallback: bool) -> bool:
	if surface_def == null:
		return fallback
	return bool(surface_def.get(property_name))


func _update_contamination(contact_count: int, mud_residue_sum: float, dust_residue_sum: float, wetness_residue_sum: float) -> void:
	var target_mud: float = 0.0
	var target_dust: float = 0.0
	var target_wetness: float = 0.0
	if contact_count > 0:
		target_mud = mud_residue_sum / float(contact_count)
		target_dust = dust_residue_sum / float(contact_count)
		target_wetness = wetness_residue_sum / float(contact_count)
	var contamination: RefCounted = _vehicle_contamination()
	contamination.set("mud", _residue_step(float(contamination.get("mud")), target_mud))
	contamination.set("dust", _residue_step(float(contamination.get("dust")), target_dust))
	contamination.set("wetness", _residue_step(float(contamination.get("wetness")), target_wetness))


func _residue_step(current: float, target: float) -> float:
	var step: float = GameConfig.vehicle_contamination_pickup_per_second * GameConfig.FIXED_DT
	if target < current:
		step = GameConfig.vehicle_contamination_decay_per_second * GameConfig.FIXED_DT
	var delta: float = target - current
	if absf(delta) <= step:
		return clampf(target, 0.0, 1.0)
	return clampf(current + signf(delta) * step, 0.0, 1.0)


func _vehicle_contamination() -> RefCounted:
	var contamination: RefCounted = _state.get("contamination") as RefCounted
	if contamination == null:
		contamination = VehicleContaminationStateScript.new()
		_state.set("contamination", contamination)
	return contamination


func _update_state() -> void:
	if _body == null:
		return
	if _stable_wheel_contact_count() >= GameConfig.self_right_stable_contact_count and _body.global_transform.basis.y.dot(Vector3.UP) >= GameConfig.self_right_stable_upright_dot:
		_last_stable_forward = _horizontal_forward(_body.global_transform.basis)
	_state.set("position", _body.global_position)
	_state.set("basis", _body.global_transform.basis)
	_state.set("linear_velocity", _body.linear_velocity)
	_state.set("angular_velocity", _body.angular_velocity)
	_state.set("is_flipped", _is_flipped())
	_state.set("motor_rpm", absf(float(_pending_input.get("throttle"))) * GameConfig.max_speed * GameConfig.motor_rpm_speed_scale)


func _is_flipped() -> bool:
	if _body == null:
		return false
	return _body.global_transform.basis.y.dot(Vector3.UP) < GameConfig.self_right_min_upright_dot


func _horizontal_forward(basis: Basis) -> Vector3:
	var forward: Vector3 = -basis.z
	forward.y = 0.0
	if forward.length() <= GameConfig.self_right_forward_epsilon:
		return Vector3.FORWARD
	return forward.normalized()


func _upright_transform(origin: Vector3, forward: Vector3) -> Transform3D:
	var safe_forward: Vector3 = forward
	safe_forward.y = 0.0
	if safe_forward.length() <= GameConfig.self_right_forward_epsilon:
		safe_forward = Vector3.FORWARD
	safe_forward = safe_forward.normalized()
	var right: Vector3 = safe_forward.cross(Vector3.UP).normalized()
	return Transform3D(Basis(right, Vector3.UP, -safe_forward), origin)


func _stable_wheel_contact_count() -> int:
	var wheel_contact: Array[bool] = _state.get("wheel_contact")
	var count: int = 0
	for has_contact in wheel_contact:
		if bool(has_contact):
			count += 1
	return count


func _reset_surface_cache() -> void:
	_surface_friction = GameConfig.default_friction
	_surface_rolling_drag = GameConfig.default_rolling_drag
	_surface_slip = GameConfig.default_slip
	_surface_normal_load = 0.0
	_surface_contact_normal = Vector3.UP
	_surface_bog_enabled = false
	_surface_bog_threshold = GameConfig.default_bog_threshold
	_state.set("contact_normal", _surface_contact_normal)
