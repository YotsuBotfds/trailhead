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
var _surface_bog_enabled: bool = false
var _surface_bog_threshold: float = 0.0
var _last_stable_forward: Vector3 = Vector3.FORWARD


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
	_vehicle_contamination().call("reset")
	_update_state()


func self_right() -> void:
	if _body == null:
		return
	var t: Transform3D = _body.global_transform
	var forward: Vector3 = _last_stable_forward
	var right: Vector3 = forward.cross(Vector3.UP).normalized()
	t.basis = Basis(right, Vector3.UP, -forward)
	t.origin.y += GameConfig.self_right_lift
	_body.global_transform = t
	_body.linear_velocity *= GameConfig.self_right_velocity_retention
	_body.angular_velocity = Vector3.ZERO
	EventBus.vehicle_self_righted.emit()


func _physics_process(_delta: float) -> void:
	if _body == null:
		return
	_update_flip_events()
	if bool(_pending_input.get("self_right")) and _is_flipped():
		self_right()
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
	box.size = Vector3(0.18, 0.06, 0.30)
	collision.shape = box
	_body.add_child(collision)

	_add_wheel_ray(&"wheel_fl", Vector3(-0.08, 0.0, -0.10))
	_add_wheel_ray(&"wheel_fr", Vector3(0.08, 0.0, -0.10))
	_add_wheel_ray(&"wheel_rl", Vector3(-0.08, 0.0, 0.10))
	_add_wheel_ray(&"wheel_rr", Vector3(0.08, 0.0, 0.10))


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
	var bog_threshold_sum: float = 0.0
	var mud_residue_sum: float = 0.0
	var dust_residue_sum: float = 0.0
	var wetness_residue_sum: float = 0.0
	var bog_enabled: bool = false
	for i in range(_wheel_rays.size()):
		var ray: RayCast3D = _wheel_rays[i]
		ray.force_raycast_update()
		var has_contact: bool = ray.is_colliding()
		var wheel_contact: Array[bool] = _state.get("wheel_contact")
		wheel_contact[i] = has_contact
		_state.set("wheel_contact", wheel_contact)
		if not has_contact:
			var empty_surface: Array[StringName] = _state.get("wheel_surface")
			empty_surface[i] = &""
			_state.set("wheel_surface", empty_surface)
			continue
		contact_count += 1
		var hit_point: Vector3 = ray.get_collision_point()
		var dist: float = ray.global_position.distance_to(hit_point)
		var compression: float = clampf((ray_length - dist) / maxf(GameConfig.susp_travel, 0.001), 0.0, 1.0)
		var spring_force: float = compression * GameConfig.susp_stiffness
		var force_pos: Vector3 = hit_point - _body.global_position
		var center_of_mass_offset_world: Vector3 = _body.global_transform.basis * GameConfig.center_of_mass_offset
		var contact_arm: Vector3 = force_pos - center_of_mass_offset_world
		var contact_velocity: Vector3 = _body.linear_velocity + _body.angular_velocity.cross(contact_arm * GameConfig.susp_contact_angular_velocity_weight)
		var compression_velocity: float = -contact_velocity.dot(up)
		var damping_force: float = compression_velocity * GameConfig.susp_damping
		var max_damping_force: float = spring_force * GameConfig.susp_damping_force_ratio
		var suspension_force: float = maxf(0.0, spring_force + clampf(damping_force, -max_damping_force, max_damping_force))
		_body.apply_force(up * suspension_force, force_pos)
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
	_state.set("on_ground", contact_count > 0)
	if contact_count > 0:
		_surface_friction = friction_sum / float(contact_count)
		_surface_rolling_drag = rolling_drag_sum / float(contact_count)
		_surface_slip = slip_sum / float(contact_count)
		_surface_bog_enabled = bog_enabled
		_surface_bog_threshold = bog_threshold_sum / float(contact_count)
	else:
		_surface_friction = GameConfig.default_friction
		_surface_rolling_drag = GameConfig.default_rolling_drag
		_surface_slip = GameConfig.default_slip
		_surface_bog_enabled = false
		_surface_bog_threshold = GameConfig.default_bog_threshold
	_update_contamination(contact_count, mud_residue_sum, dust_residue_sum, wetness_residue_sum)
	_update_surface_event()


func _apply_drive_forces() -> void:
	var forward: Vector3 = -_body.global_transform.basis.z.normalized()
	var right: Vector3 = _body.global_transform.basis.x.normalized()
	var throttle: float = float(_pending_input.get("throttle"))
	var steer: float = float(_pending_input.get("steer"))
	var brake: float = float(_pending_input.get("brake"))
	var drive: Vector3 = forward * throttle * GameConfig.motor_torque * _surface_friction
	_body.apply_central_force(drive)
	if brake > 0.0:
		var brake_factor: float = clampf(1.0 - brake * GameConfig.brake_damping_per_second * GameConfig.FIXED_DT, 0.0, 1.0)
		_body.linear_velocity *= brake_factor
	if bool(_state.get("on_ground")):
		_apply_surface_drag()
	var lateral_speed: float = _body.linear_velocity.dot(right)
	var surface_grip: float = _surface_friction * maxf(1.0 - _surface_slip, GameConfig.surface_min_lateral_grip)
	var lateral_grip: float = GameConfig.default_friction * surface_grip
	if bool(_pending_input.get("ebrake")):
		lateral_grip *= GameConfig.ebrake_factor
	_body.apply_central_force(-right * lateral_speed * lateral_grip * GameConfig.lateral_grip_force)
	if bool(_state.get("on_ground")):
		_body.apply_torque(Vector3.UP * steer * GameConfig.steer_yaw_torque * surface_grip)
	if bool(_state.get("on_ground")) and throttle >= GameConfig.launch_wheelie_min_throttle and absf(steer) <= GameConfig.launch_wheelie_max_steer and _body.linear_velocity.length() <= GameConfig.launch_wheelie_speed_max:
		_body.apply_torque(right * GameConfig.launch_wheelie_torque)


func _apply_surface_drag() -> void:
	var velocity_flat: Vector3 = Vector3(_body.linear_velocity.x, 0.0, _body.linear_velocity.z)
	var speed: float = velocity_flat.length()
	if speed <= 0.001:
		return
	var drag: float = _surface_rolling_drag * GameConfig.surface_rolling_drag_force
	if _surface_bog_enabled and speed <= _surface_bog_threshold:
		drag += GameConfig.surface_bog_drag_force
	_body.apply_central_force(-velocity_flat.normalized() * drag * speed)


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
	_surface_bog_enabled = false
	_surface_bog_threshold = GameConfig.default_bog_threshold
