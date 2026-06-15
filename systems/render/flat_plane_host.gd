class_name FlatPlaneHost
extends Node3D

const VehicleScene: PackedScene = preload("res://scenes/vehicle.tscn")
const VehicleInputScript: GDScript = preload("res://systems/vehicle/vehicle_input.gd")
const ProceduralBuggyVisualScript: GDScript = preload("res://systems/render/procedural_buggy_visual.gd")
const VehicleResidueVisualScript: GDScript = preload("res://systems/render/vehicle_residue_visual.gd")
const AtmosphereVisualBuilderScript: GDScript = preload("res://systems/render/atmosphere_visual_builder.gd")
const DustTiltShiftVisualBuilderScript: GDScript = preload("res://systems/render/dust_tilt_shift_visual_builder.gd")
const FlatWorldBuilderScript: GDScript = preload("res://systems/world/flat_world_builder.gd")
const SurfaceMapScript: GDScript = preload("res://systems/world/surface_map.gd")

var _vehicle: Node = null
var _vehicle_input: RefCounted = VehicleInputScript.new()
var _camera: Camera3D = null
var _wheel_sockets: Array[Node3D] = []
var _vehicle_visual_root: Node = null
var _vehicle_residue_visual: RefCounted = VehicleResidueVisualScript.new()
var _wheel_spin: float = 0.0
var _camera_initialized: bool = false
var _chase_look_target_current: Vector3 = Vector3.ZERO


func _ready() -> void:
	_ensure_default_input_map()
	_setup_surface_map()
	_build_ground()
	_spawn_vehicle()
	_setup_light()
	_setup_camera()
	_setup_render_support()


func _physics_process(delta: float) -> void:
	if _vehicle == null:
		return
	_update_vehicle_input()
	_vehicle.call("apply_input", _vehicle_input)
	_update_visual_wheels(delta)
	_update_camera(delta)


func _ensure_default_input_map() -> void:
	_ensure_action(&"throttle", [KEY_W, KEY_UP])
	_ensure_action(&"brake", [KEY_S, KEY_DOWN])
	_ensure_action(&"reverse", [KEY_S, KEY_DOWN])
	_ensure_action(&"steer_left", [KEY_A, KEY_LEFT])
	_ensure_action(&"steer_right", [KEY_D, KEY_RIGHT])
	_ensure_action(&"ebrake", [KEY_SPACE])
	_ensure_action(&"self_right", [KEY_R])
	_ensure_action(&"cam_toggle", [KEY_C])


func _ensure_action(action_name: StringName, keycodes: Array[int]) -> void:
	var action_string: String = String(action_name)
	if not InputMap.has_action(action_string):
		InputMap.add_action(action_string, 0.2)
	if InputMap.action_get_events(action_string).size() > 0:
		return
	for keycode in keycodes:
		var event: InputEventKey = InputEventKey.new()
		event.physical_keycode = keycode
		InputMap.action_add_event(action_string, event)


func _build_ground() -> void:
	var ground: StaticBody3D = FlatWorldBuilderScript.build_collision(self)

	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.name = "GroundVisual"
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3(GameConfig.flat_ground_size.x, 0.04, GameConfig.flat_ground_size.z)
	mesh_instance.mesh = mesh
	mesh_instance.position = Vector3(GameConfig.flat_ground_center.x, -0.02, GameConfig.flat_ground_center.z)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.35, 0.29, 0.20)
	material.roughness = 0.9
	mesh_instance.material_override = material
	ground.add_child(mesh_instance)


func _setup_surface_map() -> void:
	var surface_map: Node = SurfaceMapScript.new()
	surface_map.name = "SurfaceMap"
	add_child(surface_map)


func _spawn_vehicle() -> void:
	_vehicle = VehicleScene.instantiate()
	add_child(_vehicle)
	_vehicle.call("reset_to", Transform3D(Basis.IDENTITY, Vector3(0.0, 0.12, 0.0)))
	var visual_builder: RefCounted = ProceduralBuggyVisualScript.new()
	visual_builder.call("attach", _vehicle)
	_collect_visual_wheels()


func _setup_light() -> void:
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-48.0, -35.0, 0.0)
	sun.light_energy = 2.5
	add_child(sun)


func _setup_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "ChaseCamera"
	_camera.current = true
	_camera.fov = GameConfig.cam_fov_base
	add_child(_camera)
	_update_camera(GameConfig.FIXED_DT)


func _setup_render_support() -> void:
	DustTiltShiftVisualBuilderScript.build(self, _camera, null, null)
	AtmosphereVisualBuilderScript.configure_render_support(self, _vehicle, _camera, null, null)


func _update_vehicle_input() -> void:
	var forward_throttle: float = Input.get_action_strength("throttle")
	var reverse_throttle: float = Input.get_action_strength("reverse")
	var brake_action: float = Input.get_action_strength("brake")
	var throttle: float = forward_throttle - reverse_throttle
	var brake: float = 0.0
	if forward_throttle > 0.0 or reverse_throttle <= 0.0:
		brake = brake_action
	var steer: float = Input.get_action_strength("steer_left") - Input.get_action_strength("steer_right")
	_vehicle_input.set("throttle", clampf(throttle, -1.0, 1.0))
	_vehicle_input.set("brake", brake)
	_vehicle_input.set("steer", clampf(steer, -1.0, 1.0))
	_vehicle_input.set("ebrake", Input.is_action_pressed("ebrake"))
	_vehicle_input.set("self_right", Input.is_action_just_pressed("self_right"))


func _collect_visual_wheels() -> void:
	_wheel_sockets.clear()
	_vehicle_visual_root = null
	var body: Node = _vehicle.get_node_or_null("PhysicsBody")
	if body == null:
		return
	var visual_root: Node = body.get_node_or_null("VisualRoot")
	if visual_root == null:
		return
	_vehicle_visual_root = visual_root
	var names: Array[String] = [
		"wheel_front_left",
		"wheel_front_right",
		"wheel_rear_left",
		"wheel_rear_right"
	]
	for socket_name in names:
		var socket: Node3D = visual_root.get_node_or_null(socket_name) as Node3D
		if socket != null:
			_wheel_sockets.append(socket)


func _update_visual_wheels(delta: float) -> void:
	var state: RefCounted = _vehicle.call("get_state")
	_update_vehicle_residue_visual(state)
	if _wheel_sockets.is_empty():
		return
	var speed: float = float(state.call("speed"))
	var spin_step: float = speed * delta / maxf(GameConfig.wheel_radius, 0.001)
	var throttle: float = float(_vehicle_input.get("throttle"))
	if throttle < 0.0:
		spin_step *= -1.0
	_wheel_spin += spin_step
	var steer: float = float(_vehicle_input.get("steer"))
	var steer_angle: float = deg_to_rad(GameConfig.steer_limit_deg) * steer
	for socket in _wheel_sockets:
		var is_front: bool = socket.name.begins_with("wheel_front")
		socket.rotation = Vector3(0.0, steer_angle if is_front else 0.0, 0.0)
		var wheel_mesh: Node3D = _wheel_mesh_for_socket(socket)
		if wheel_mesh != null:
			wheel_mesh.rotation = Vector3(_wheel_spin, 0.0, deg_to_rad(90.0))


func _update_vehicle_residue_visual(state: RefCounted) -> void:
	if _vehicle_visual_root == null:
		return
	_vehicle_residue_visual.call("apply_state", _vehicle_visual_root, state)


func _wheel_mesh_for_socket(socket: Node3D) -> Node3D:
	var named_mesh: Node3D = socket.get_node_or_null("wheel_mesh") as Node3D
	if named_mesh != null:
		return named_mesh
	for child in socket.get_children():
		var mesh_child: MeshInstance3D = child as MeshInstance3D
		if mesh_child != null:
			return mesh_child
	return null


func _update_camera(delta: float) -> void:
	if _camera == null or _vehicle == null:
		return
	var state: RefCounted = _vehicle.call("get_state")
	var vehicle_position: Vector3 = state.get("position")
	var vehicle_basis: Basis = state.get("basis")
	var back: Vector3 = vehicle_basis.z.normalized()
	var forward: Vector3 = -vehicle_basis.z.normalized()
	var steer: float = clampf(float(_vehicle_input.get("steer")), -1.0, 1.0)
	var desired_position: Vector3 = vehicle_position + back * GameConfig.cam_distance + Vector3.UP * GameConfig.cam_height
	if not _camera_initialized:
		_camera.global_position = desired_position
		_chase_look_target_current = _chase_camera_look_target(vehicle_position, vehicle_basis, forward, steer)
		_camera_initialized = true
	else:
		var follow_alpha_y: float = _chase_camera_follow_alpha(delta, GameConfig.cam_spring_vy)
		var current_position: Vector3 = _camera.global_position
		current_position.x = desired_position.x
		current_position.y = lerpf(current_position.y, desired_position.y, follow_alpha_y)
		current_position.z = desired_position.z
		_camera.global_position = current_position
		var raw_look_target: Vector3 = _chase_camera_look_target(vehicle_position, vehicle_basis, forward, steer)
		var look_alpha: float = _chase_camera_follow_alpha(delta, GameConfig.cam_look_spring)
		_chase_look_target_current = _chase_look_target_current.lerp(raw_look_target, look_alpha)
	_camera.look_at(_chase_look_target_current, Vector3.UP)
	_camera.fov = GameConfig.cam_fov_base


func _chase_camera_follow_alpha(delta: float, spring: float) -> float:
	return clampf(1.0 - exp(-maxf(spring, 0.0) * delta), 0.0, 1.0)


func _chase_camera_look_target(vehicle_position: Vector3, vehicle_basis: Basis, forward: Vector3, steer: float) -> Vector3:
	var lateral: Vector3 = vehicle_basis.x.normalized()
	var target: Vector3 = vehicle_position \
		+ forward * GameConfig.cam_look_ahead \
		+ lateral * steer * GameConfig.cam_look_turn_bias
	if _camera == null:
		return target
	var flat_delta: Vector3 = Vector3(target.x - _camera.global_position.x, 0.0, target.z - _camera.global_position.z)
	var horizontal_distance: float = maxf(flat_delta.length(), 0.001)
	target.y = _camera.global_position.y + tan(deg_to_rad(GameConfig.cam_pitch_deg)) * horizontal_distance
	return target
