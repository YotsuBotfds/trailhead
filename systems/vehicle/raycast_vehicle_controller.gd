class_name RaycastVehicleController
extends "res://systems/vehicle/vehicle_controller.gd"

const WHEEL_COUNT: int = 4
const RaycastVehicleInputScript: GDScript = preload("res://systems/vehicle/vehicle_input.gd")
const RaycastVehicleStateScript: GDScript = preload("res://systems/vehicle/vehicle_state.gd")

var _body: RigidBody3D = null
var _wheel_rays: Array[RayCast3D] = []
var _pending_input: RefCounted = RaycastVehicleInputScript.new()
var _state: RefCounted = RaycastVehicleStateScript.new()
var _was_flipped: bool = false
var _current_surface_id: StringName = &""


func _ready() -> void:
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
	_update_state()


func self_right() -> void:
	if _body == null:
		return
	var t: Transform3D = _body.global_transform
	t.basis = Basis.IDENTITY
	t.origin.y += 0.12
	_body.global_transform = t
	_body.linear_velocity *= 0.25
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
	_update_flip_events()


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
		_body.apply_force(up * spring_force, force_pos)
		var wheel_surface: Array[StringName] = _state.get("wheel_surface")
		wheel_surface[i] = &"packed_dirt"
		_state.set("wheel_surface", wheel_surface)
	_state.set("on_ground", contact_count > 0)
	_update_surface_event()


func _apply_drive_forces() -> void:
	var forward: Vector3 = -_body.global_transform.basis.z.normalized()
	var right: Vector3 = _body.global_transform.basis.x.normalized()
	var throttle: float = float(_pending_input.get("throttle"))
	var steer: float = float(_pending_input.get("steer"))
	var brake: float = float(_pending_input.get("brake"))
	var drive: Vector3 = forward * throttle * GameConfig.motor_torque
	_body.apply_central_force(drive)
	if brake > 0.0:
		var brake_factor: float = clampf(1.0 - brake * GameConfig.brake_damping_per_tick, 0.0, 1.0)
		_body.linear_velocity *= brake_factor
	var lateral_speed: float = _body.linear_velocity.dot(right)
	var lateral_grip: float = GameConfig.default_friction
	if bool(_pending_input.get("ebrake")):
		lateral_grip *= GameConfig.ebrake_factor
	_body.apply_central_force(-right * lateral_speed * lateral_grip * GameConfig.lateral_grip_force)
	if bool(_state.get("on_ground")):
		_body.apply_torque(Vector3.UP * steer * GameConfig.steer_yaw_torque)
	if bool(_state.get("on_ground")) and throttle >= GameConfig.launch_wheelie_min_throttle and absf(steer) <= GameConfig.launch_wheelie_max_steer and _body.linear_velocity.length() <= GameConfig.launch_wheelie_speed_max:
		_body.apply_torque(right * GameConfig.launch_wheelie_torque)


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
	for surface_id in wheel_surface:
		if surface_id != &"":
			return surface_id
	return &""


func _update_state() -> void:
	if _body == null:
		return
	_state.set("position", _body.global_position)
	_state.set("basis", _body.global_transform.basis)
	_state.set("linear_velocity", _body.linear_velocity)
	_state.set("angular_velocity", _body.angular_velocity)
	_state.set("is_flipped", _is_flipped())
	_state.set("motor_rpm", absf(float(_pending_input.get("throttle"))) * GameConfig.max_speed * 100.0)


func _is_flipped() -> bool:
	if _body == null:
		return false
	return _body.global_transform.basis.y.dot(Vector3.UP) < 0.0
