class_name CedarHollowHost
extends Node3D

const CedarHollowSceneResource: PackedScene = preload("res://scenes/cedar_hollow.tscn")
const CedarRoute: Resource = preload("res://data/routes/cedar_hollow.tres")
const CEDAR_TERRAIN_DEF_PATH: String = "res://data/terrain/cedar_hollow_terrain_def.tres"
const CedarTerrainDef: Resource = preload("res://data/terrain/cedar_hollow_terrain_def.tres")
const VehicleScene: PackedScene = preload("res://scenes/vehicle.tscn")
const VehicleInputScript: GDScript = preload("res://systems/vehicle/vehicle_input.gd")
const TerrainVisualBuilderScript: GDScript = preload("res://systems/render/terrain_visual_builder.gd")
const GroundDetailVisualBuilderScript: GDScript = preload("res://systems/render/ground_detail_visual_builder.gd")
const FeatureVisualBuilderScript: GDScript = preload("res://systems/render/feature_visual_builder.gd")
const PropVisualBuilderScript: GDScript = preload("res://systems/render/prop_visual_builder.gd")
const ScatterVisualBuilderScript: GDScript = preload("res://systems/render/scatter_visual_builder.gd")
const BoundaryVisualBuilderScript: GDScript = preload("res://systems/render/boundary_visual_builder.gd")
const AtmosphereVisualBuilderScript: GDScript = preload("res://systems/render/atmosphere_visual_builder.gd")
const DustTiltShiftVisualBuilderScript: GDScript = preload("res://systems/render/dust_tilt_shift_visual_builder.gd")
const WaterVisualBuilderScript: GDScript = preload("res://systems/render/water_visual_builder.gd")
const ProceduralBuggyVisualScript: GDScript = preload("res://systems/render/procedural_buggy_visual.gd")
const VehicleResidueVisualScript: GDScript = preload("res://systems/render/vehicle_residue_visual.gd")
const VehicleJuiceRigScript: GDScript = preload("res://systems/render/vehicle_juice_rig.gd")
const CedarAudioRigScript: GDScript = preload("res://systems/render/cedar_audio_rig.gd")
const LandmarkHintHudScript: GDScript = preload("res://systems/render/landmark_hint_hud.gd")
const TerrainTrackVisualPainterScript: GDScript = preload("res://systems/render/terrain_track_visual_painter.gd")
const SurfaceMapScript: GDScript = preload("res://systems/world/surface_map.gd")
const CAMERA_MODE_CHASE: int = 0
const CAMERA_MODE_ORBIT: int = 1
const CAMERA_MODE_FPV: int = 2
const MOOD_DUSK: int = 0
const MOOD_DAWN: int = 1

var _world: Node3D = null
var _vehicle: Node = null
var _vehicle_input: RefCounted = VehicleInputScript.new()
var _camera: Camera3D = null
var _orbit_camera: Camera3D = null
var _fpv_camera: Camera3D = null
var _wheel_sockets: Array[Node3D] = []
var _vehicle_visual_root: Node = null
var _vehicle_residue_visual: RefCounted = VehicleResidueVisualScript.new()
var _wheel_spin: float = 0.0
var _camera_mode: int = CAMERA_MODE_CHASE
var _chase_camera_initialized: bool = false
var _chase_look_target_current: Vector3 = Vector3.ZERO
var _orbit_camera_initialized: bool = false
var _orbit_yaw_degrees: float = 0.0
var _landmark_hint_hud: CanvasLayer = null
var _world_environment: WorldEnvironment = null
var _sun: DirectionalLight3D = null
var _mood: int = MOOD_DUSK
var _terrain_track_painter: Node = null


func _ready() -> void:
	_ensure_default_input_map()
	_setup_surface_map()
	_setup_world()
	_spawn_vehicle()
	_setup_audio()
	_setup_environment()
	_setup_light()
	_setup_camera()
	_setup_vehicle_juice()
	AtmosphereVisualBuilderScript.configure_render_support(self, _vehicle, _camera, _orbit_camera, _fpv_camera)
	_setup_hud()


func _physics_process(delta: float) -> void:
	if _vehicle == null:
		return
	_update_vehicle_input()
	_update_camera_input()
	_update_hud_input()
	_update_mood_input()
	_vehicle.call("apply_input", _vehicle_input)
	_update_visual_wheels(delta)
	_update_terrain_tracks()
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
	_ensure_action(&"map_toggle", [KEY_M])
	_ensure_action(&"mood_toggle", [KEY_N])
	_ensure_action(&"logbook_open", [KEY_TAB])
	_ensure_action(&"photograph", [KEY_F])


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
	if not bool(surface_map.call("configure_terrain_def", CEDAR_TERRAIN_DEF_PATH)):
		push_error("CedarHollowHost failed to configure terrain surface map")


func _setup_world() -> void:
	_world = CedarHollowSceneResource.instantiate() as Node3D
	if _world == null:
		return
	_world.name = "CedarHollow"
	add_child(_world)
	var terrain_root: Node3D = TerrainVisualBuilderScript.build_cedar_hollow(_world)
	GroundDetailVisualBuilderScript.build_cedar_hollow(_world)
	FeatureVisualBuilderScript.build_cedar_hollow(_world)
	PropVisualBuilderScript.build_cedar_hollow(_world)
	ScatterVisualBuilderScript.build_cedar_hollow(_world)
	BoundaryVisualBuilderScript.build_cedar_hollow(_world)
	WaterVisualBuilderScript.build_cedar_hollow(_world)
	_setup_terrain_tracks(terrain_root)


func _setup_terrain_tracks(terrain_root: Node3D) -> void:
	if terrain_root == null or not GameConfig.terrain_track_painter_enabled:
		return
	_terrain_track_painter = TerrainTrackVisualPainterScript.new() as Node
	if _terrain_track_painter == null:
		return
	_terrain_track_painter.name = "TerrainTrackVisualPainter"
	_world.add_child(_terrain_track_painter)
	_terrain_track_painter.call("configure", CedarTerrainDef.get("bounds_min_xz"), CedarTerrainDef.get("bounds_max_xz"))
	var track_texture: Texture2D = _terrain_track_painter.call("track_texture") as Texture2D
	var track_bounds_min: Vector2 = _terrain_track_painter.call("render_bounds_min")
	var track_bounds_max: Vector2 = _terrain_track_painter.call("render_bounds_max")
	TerrainVisualBuilderScript.apply_track_texture(terrain_root, track_texture, track_bounds_min, track_bounds_max)


func _spawn_vehicle() -> void:
	_vehicle = VehicleScene.instantiate()
	add_child(_vehicle)
	_vehicle.call("reset_to", CedarRoute.call("spawn_transform", &"trailhead"))
	var visual_builder: RefCounted = ProceduralBuggyVisualScript.new()
	visual_builder.call("attach", _vehicle)
	_collect_visual_wheels()


func _setup_light() -> void:
	_sun = DirectionalLight3D.new()
	_sun.name = "GoldenHourSun"
	add_child(_sun)
	_apply_mood()


func _setup_audio() -> void:
	var audio_rig: Node = CedarAudioRigScript.new()
	audio_rig.name = "CedarAudioRig"
	add_child(audio_rig)
	audio_rig.call("configure", _vehicle)


func _setup_environment() -> void:
	_world_environment = WorldEnvironment.new()
	_world_environment.name = "GoldenHourEnvironment"
	var environment: Environment = Environment.new()
	_world_environment.environment = environment
	add_child(_world_environment)
	_apply_mood()


func _setup_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "ChaseCamera"
	_camera.current = true
	_camera.fov = GameConfig.cam_fov_base
	_camera.far = GameConfig.cam_far
	add_child(_camera)
	_orbit_camera = Camera3D.new()
	_orbit_camera.name = "OrbitCamera"
	_orbit_camera.current = false
	_orbit_camera.fov = GameConfig.orbit_cam_fov
	_orbit_camera.far = GameConfig.orbit_cam_far
	add_child(_orbit_camera)
	_fpv_camera = Camera3D.new()
	_fpv_camera.name = "FpvCamera"
	_fpv_camera.current = false
	_fpv_camera.fov = GameConfig.fpv_cam_fov
	_fpv_camera.far = GameConfig.fpv_cam_far
	add_child(_fpv_camera)
	DustTiltShiftVisualBuilderScript.build(self, _camera, _orbit_camera, _fpv_camera)
	_orbit_yaw_degrees = GameConfig.orbit_cam_start_yaw_deg
	_update_camera(GameConfig.FIXED_DT)


func _setup_vehicle_juice() -> void:
	var juice_rig: Node = VehicleJuiceRigScript.new()
	juice_rig.name = "VehicleJuiceRig"
	add_child(juice_rig)
	juice_rig.call("configure", _vehicle, _camera, _vehicle_visual_root as Node3D)


func _setup_hud() -> void:
	_landmark_hint_hud = LandmarkHintHudScript.new() as CanvasLayer
	_landmark_hint_hud.name = "LandmarkHintHud"
	_landmark_hint_hud.visible = GameConfig.minimap_enabled_by_default
	add_child(_landmark_hint_hud)
	_landmark_hint_hud.call("configure", CedarRoute, _vehicle)


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


func _update_camera_input() -> void:
	if not Input.is_action_just_pressed("cam_toggle"):
		return
	cycle_camera_mode()


func cycle_camera_mode() -> void:
	if _camera_mode == CAMERA_MODE_CHASE:
		_camera_mode = CAMERA_MODE_ORBIT
		_update_camera(GameConfig.FIXED_DT)
		return
	if _camera_mode == CAMERA_MODE_ORBIT:
		_camera_mode = CAMERA_MODE_FPV
		_update_camera(GameConfig.FIXED_DT)
		return
	_camera_mode = CAMERA_MODE_CHASE
	_update_camera(GameConfig.FIXED_DT)


func _update_hud_input() -> void:
	if _landmark_hint_hud == null or not Input.is_action_just_pressed("map_toggle"):
		return
	toggle_landmark_hint_hud()


func toggle_landmark_hint_hud() -> void:
	if _landmark_hint_hud == null:
		return
	_landmark_hint_hud.visible = not _landmark_hint_hud.visible


func _update_mood_input() -> void:
	if not Input.is_action_just_pressed("mood_toggle"):
		return
	toggle_mood()


func toggle_mood() -> void:
	if _mood == MOOD_DUSK:
		_mood = MOOD_DAWN
	else:
		_mood = MOOD_DUSK
	_apply_mood()


func _apply_mood() -> void:
	if _sun != null:
		if _mood == MOOD_DAWN:
			_sun.rotation_degrees = GameConfig.dawn_sun_rotation_degrees
			_sun.light_energy = GameConfig.dawn_sun_energy
			_sun.light_color = GameConfig.dawn_sun_color
		else:
			_sun.rotation_degrees = GameConfig.dusk_sun_rotation_degrees
			_sun.light_energy = GameConfig.dusk_sun_energy
			_sun.light_color = GameConfig.dusk_sun_color
	if _world_environment == null or _world_environment.environment == null:
		return
	var environment: Environment = _world_environment.environment
	environment.background_mode = Environment.BG_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.fog_enabled = true
	if _mood == MOOD_DAWN:
		environment.background_color = GameConfig.dawn_background_color
		environment.ambient_light_color = GameConfig.dawn_ambient_color
		environment.ambient_light_energy = GameConfig.dawn_ambient_energy
		environment.fog_density = GameConfig.dawn_fog_density
		environment.fog_light_color = GameConfig.dawn_fog_light_color
	else:
		environment.background_color = GameConfig.dusk_background_color
		environment.ambient_light_color = GameConfig.dusk_ambient_color
		environment.ambient_light_energy = GameConfig.dusk_ambient_energy
		environment.fog_density = GameConfig.dusk_fog_density
		environment.fog_light_color = GameConfig.dusk_fog_light_color
	AtmosphereVisualBuilderScript.apply_mood(_world_environment, _sun, _mood)


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


func _update_terrain_tracks() -> void:
	if _terrain_track_painter == null:
		return
	var state: RefCounted = _vehicle.call("get_state")
	_terrain_track_painter.call("apply_vehicle_state", state, GameConfig.FIXED_DT)


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
	if _vehicle == null:
		return
	var state: RefCounted = _vehicle.call("get_state")
	_update_chase_camera(delta, state)
	_update_orbit_camera(delta, state)
	_update_fpv_camera(state)


func _update_chase_camera(delta: float, state: RefCounted) -> void:
	if _camera == null:
		return
	var vehicle_position: Vector3 = state.get("position")
	var vehicle_basis: Basis = state.get("basis")
	var back: Vector3 = vehicle_basis.z.normalized()
	var forward: Vector3 = -vehicle_basis.z.normalized()
	var steer: float = clampf(float(_vehicle_input.get("steer")), -1.0, 1.0)
	var desired_position: Vector3 = vehicle_position + back * GameConfig.cam_distance + Vector3.UP * GameConfig.cam_height
	if not _chase_camera_initialized:
		_camera.global_position = desired_position
		_chase_look_target_current = _chase_camera_look_target(vehicle_position, vehicle_basis, forward, steer)
		_chase_camera_initialized = true
	else:
		var follow_alpha_xz: float = _chase_camera_follow_alpha(delta, GameConfig.cam_spring_xz)
		var follow_alpha_y: float = _chase_camera_follow_alpha(delta, GameConfig.cam_spring_vy)
		var current_position: Vector3 = _camera.global_position
		current_position.x = lerpf(current_position.x, desired_position.x, follow_alpha_xz)
		current_position.y = lerpf(current_position.y, desired_position.y, follow_alpha_y)
		current_position.z = lerpf(current_position.z, desired_position.z, follow_alpha_xz)
		_camera.global_position = current_position
		var raw_look_target: Vector3 = _chase_camera_look_target(vehicle_position, vehicle_basis, forward, steer)
		var look_alpha: float = _chase_camera_follow_alpha(delta, GameConfig.cam_look_spring)
		_chase_look_target_current = _chase_look_target_current.lerp(raw_look_target, look_alpha)
	_camera.look_at(_chase_look_target_current, Vector3.UP)
	_camera.fov = GameConfig.get_fov_for_speed(float(state.call("speed")))
	_camera.current = _camera_mode == CAMERA_MODE_CHASE


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


func _update_orbit_camera(delta: float, state: RefCounted) -> void:
	if _orbit_camera == null:
		return
	var vehicle_position: Vector3 = state.get("position")
	if _camera_mode == CAMERA_MODE_ORBIT:
		_orbit_yaw_degrees += GameConfig.orbit_cam_speed_deg * delta
	var yaw_radians: float = deg_to_rad(_orbit_yaw_degrees)
	var orbit_offset: Vector3 = Vector3(sin(yaw_radians), 0.0, cos(yaw_radians)) * GameConfig.orbit_cam_distance
	var desired_position: Vector3 = vehicle_position + orbit_offset + Vector3.UP * GameConfig.orbit_cam_height
	var follow_alpha: float = clampf(GameConfig.orbit_cam_spring * delta, 0.0, 1.0)
	if not _orbit_camera_initialized:
		_orbit_camera.global_position = desired_position
		_orbit_camera_initialized = true
	else:
		_orbit_camera.global_position = _orbit_camera.global_position.lerp(desired_position, follow_alpha)
	_orbit_camera.look_at(vehicle_position + Vector3.UP * GameConfig.orbit_cam_look_height, Vector3.UP)
	_orbit_camera.fov = GameConfig.orbit_cam_fov
	_orbit_camera.current = _camera_mode == CAMERA_MODE_ORBIT


func _update_fpv_camera(state: RefCounted) -> void:
	if _fpv_camera == null:
		return
	var vehicle_position: Vector3 = state.get("position")
	var vehicle_basis: Basis = state.get("basis")
	var forward: Vector3 = -vehicle_basis.z.normalized()
	var up: Vector3 = vehicle_basis.y.normalized()
	_fpv_camera.global_position = vehicle_position + forward * GameConfig.fpv_cam_forward + up * GameConfig.fpv_cam_height
	_fpv_camera.look_at(vehicle_position + forward * GameConfig.fpv_cam_look_ahead + up * GameConfig.fpv_cam_look_height, Vector3.UP)
	_fpv_camera.fov = GameConfig.fpv_cam_fov
	_fpv_camera.current = _camera_mode == CAMERA_MODE_FPV
