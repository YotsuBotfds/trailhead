class_name CedarHollowHost
extends Node3D

const CedarHollowSceneResource: PackedScene = preload("res://scenes/cedar_hollow.tscn")
const CedarRoute: Resource = preload("res://data/routes/cedar_hollow.tres")
const VehicleScene: PackedScene = preload("res://scenes/vehicle.tscn")
const VehicleInputScript: GDScript = preload("res://systems/vehicle/vehicle_input.gd")
const FeatureVisualBuilderScript: GDScript = preload("res://systems/render/feature_visual_builder.gd")
const PropVisualBuilderScript: GDScript = preload("res://systems/render/prop_visual_builder.gd")
const ProceduralBuggyVisualScript: GDScript = preload("res://systems/render/procedural_buggy_visual.gd")
const SurfaceMapScript: GDScript = preload("res://systems/world/surface_map.gd")

var _world: Node3D = null
var _vehicle: Node = null
var _vehicle_input: RefCounted = VehicleInputScript.new()
var _camera: Camera3D = null
var _wheel_sockets: Array[Node3D] = []
var _wheel_spin: float = 0.0


func _ready() -> void:
	_ensure_default_input_map()
	_setup_surface_map()
	_setup_world()
	_spawn_vehicle()
	_setup_light()
	_setup_camera()


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


func _setup_surface_map() -> void:
	var surface_map: Node = SurfaceMapScript.new()
	surface_map.name = "SurfaceMap"
	add_child(surface_map)


func _setup_world() -> void:
	_world = CedarHollowSceneResource.instantiate() as Node3D
	if _world == null:
		return
	_world.name = "CedarHollow"
	add_child(_world)
	FeatureVisualBuilderScript.build_cedar_hollow(_world)
	PropVisualBuilderScript.build_cedar_hollow(_world)


func _spawn_vehicle() -> void:
	_vehicle = VehicleScene.instantiate()
	add_child(_vehicle)
	_vehicle.call("reset_to", CedarRoute.call("spawn_transform", &"trailhead"))
	var visual_builder: RefCounted = ProceduralBuggyVisualScript.new()
	visual_builder.call("attach", _vehicle)
	_collect_visual_wheels()


func _setup_light() -> void:
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.name = "GoldenHourSun"
	sun.rotation_degrees = Vector3(-34.0, -48.0, 0.0)
	sun.light_energy = 2.8
	sun.light_color = Color(1.0, 0.78, 0.52)
	add_child(sun)


func _setup_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "ChaseCamera"
	_camera.current = true
	_camera.fov = GameConfig.cam_fov_base
	add_child(_camera)
	_update_camera(GameConfig.FIXED_DT)


func _update_vehicle_input() -> void:
	var throttle: float = Input.get_action_strength("throttle")
	var brake: float = Input.get_action_strength("brake")
	var steer: float = Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")
	_vehicle_input.set("throttle", throttle)
	_vehicle_input.set("brake", brake)
	_vehicle_input.set("steer", clampf(steer, -1.0, 1.0))
	_vehicle_input.set("ebrake", Input.is_action_pressed("ebrake"))
	_vehicle_input.set("self_right", Input.is_action_just_pressed("self_right"))


func _collect_visual_wheels() -> void:
	_wheel_sockets.clear()
	var body: Node = _vehicle.get_node_or_null("PhysicsBody")
	if body == null:
		return
	var visual_root: Node = body.get_node_or_null("VisualRoot")
	if visual_root == null:
		return
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
	if _wheel_sockets.is_empty():
		return
	var state: RefCounted = _vehicle.call("get_state")
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
		var wheel_mesh: Node3D = socket.get_node_or_null("wheel_mesh") as Node3D
		if wheel_mesh != null:
			wheel_mesh.rotation = Vector3(_wheel_spin, 0.0, deg_to_rad(90.0))


func _update_camera(delta: float) -> void:
	if _camera == null or _vehicle == null:
		return
	var state: RefCounted = _vehicle.call("get_state")
	var vehicle_position: Vector3 = state.get("position")
	var vehicle_basis: Basis = state.get("basis")
	var back: Vector3 = vehicle_basis.z.normalized()
	var forward: Vector3 = -vehicle_basis.z.normalized()
	var desired_position: Vector3 = vehicle_position + back * GameConfig.cam_distance + Vector3.UP * GameConfig.cam_height
	var follow_alpha: float = clampf(GameConfig.cam_spring * delta, 0.0, 1.0)
	_camera.global_position = _camera.global_position.lerp(desired_position, follow_alpha)
	_camera.look_at(vehicle_position + forward * GameConfig.cam_look_ahead, Vector3.UP)
	_camera.fov = GameConfig.get_fov_for_speed(float(state.call("speed")))
