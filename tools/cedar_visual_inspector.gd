extends Node

const CedarHollowPlayableScene: PackedScene = preload("res://scenes/cedar_hollow_playable.tscn")
const EXPECTED_BOARDWALK_SEGMENTS: int = 9
const EXPECTED_STEPPING_STONES: int = 5
const EXPECTED_TERRAIN_PATCHES: int = 20
const EXPECTED_GRASS_TUFTS: int = 18
const EXPECTED_BOULDERS: int = 5
const EXPECTED_BRANCHES: int = 5
const EXPECTED_PINECONES: int = 8
const EXPECTED_BOUNDARY_GRASS: int = 20
const EXPECTED_BOUNDARY_BOULDERS: int = 8
const EXPECTED_BOUNDARY_BRANCHES: int = 6
const FLOAT_EPSILON: float = 0.001
const FEATURE_TRANSFORM_TOLERANCE: float = 0.01
const FEATURE_COLLISION_ALIGNMENT_TOLERANCE: float = 0.05

var _scene_root: Node = null
var _errors: PackedStringArray = PackedStringArray()


func _ready() -> void:
	_scene_root = CedarHollowPlayableScene.instantiate()
	add_child(_scene_root)
	call_deferred("_inspect")


func _inspect() -> void:
	if _scene_root == null:
		_errors.append("failed to instantiate Cedar Hollow playable scene")
		_finish()
		return
	var terrain_root: Node = _require_node(_scene_root, "CedarHollow/TerrainVisuals")
	if terrain_root != null:
		_require_named_count(terrain_root, "terrain_patch_", EXPECTED_TERRAIN_PATCHES)
		var terrain_collision_count: int = _count_collision_objects(terrain_root)
		if terrain_collision_count > 0:
			_errors.append("TerrainVisuals contains collision objects: " + str(terrain_collision_count))
		var terrain_mesh_count: int = _count_mesh_instances(terrain_root)
		if terrain_mesh_count != EXPECTED_TERRAIN_PATCHES:
			_errors.append("expected " + str(EXPECTED_TERRAIN_PATCHES) + " terrain patch meshes, got " + str(terrain_mesh_count))
	var feature_root: Node = _require_node(_scene_root, "CedarHollow/FeatureVisuals")
	if feature_root != null:
		_require_named_count(feature_root, "boardwalk_segment_", EXPECTED_BOARDWALK_SEGMENTS)
		_require_named_count(feature_root, "stepping_stone_", EXPECTED_STEPPING_STONES)
		_require_named_count(feature_root, "culvert_pipe", 1)
		_require_named_count(feature_root, "log_ramp", 1)
		_require_node_position(feature_root, "boardwalk_segment_1", Vector3(3.25, 0.035, -4.31), FEATURE_TRANSFORM_TOLERANCE)
		_require_node_position(feature_root, "boardwalk_segment_9", Vector3(3.25, 0.035, -2.39), FEATURE_TRANSFORM_TOLERANCE)
		_require_node_scale(feature_root, "boardwalk_segment_1", Vector3(1.35, 1.0, 1.0), FLOAT_EPSILON)
		_require_node_position(feature_root, "culvert_pipe", Vector3(-4.35, -0.02, -3.05), FEATURE_TRANSFORM_TOLERANCE)
		_require_node_position(feature_root, "log_ramp", Vector3(1.3, -0.005, 0.16), FEATURE_TRANSFORM_TOLERANCE)
		_require_node_rotation(feature_root, "log_ramp", Vector3(0.0, 115.0, 0.0), FLOAT_EPSILON)
		_require_node_position(feature_root, "stepping_stone_1", Vector3(3.45, 0.01, -7.05), FEATURE_TRANSFORM_TOLERANCE)
		_require_node_position(feature_root, "stepping_stone_5", Vector3(5.0, 0.01, -7.2), FEATURE_TRANSFORM_TOLERANCE)
		var cedar_world: Node = _require_node(_scene_root, "CedarHollow")
		if cedar_world != null:
			_inspect_feature_collision_alignment(cedar_world, feature_root)
		var collision_count: int = _count_collision_objects(feature_root)
		if collision_count > 0:
			_errors.append("FeatureVisuals contains collision objects: " + str(collision_count))
		var mesh_count: int = _count_mesh_instances(feature_root)
		if mesh_count <= 0:
			_errors.append("FeatureVisuals contains no mesh instances")
	var prop_root: Node = _require_node(_scene_root, "CedarHollow/PropVisuals")
	if prop_root != null:
		_require_named_count(prop_root, "trail_sign", 1)
		_require_named_count(prop_root, "picnic_table", 1)
		_require_named_count(prop_root, "old_cedar_stump", 1)
		_require_named_count(prop_root, "fire_ring", 1)
		_require_named_count(prop_root, "hiking_boot", 1)
		_require_named_count(prop_root, "water_bottle", 1)
		_require_node_position(prop_root, "trail_sign", Vector3(0.72, 0.0, 0.25), FEATURE_TRANSFORM_TOLERANCE)
		_require_node_rotation(prop_root, "trail_sign", Vector3(0.0, -24.0, 0.0), FLOAT_EPSILON)
		_require_node_position(prop_root, "picnic_table", Vector3(-1.45, 0.0, 0.35), FEATURE_TRANSFORM_TOLERANCE)
		_require_node_rotation(prop_root, "picnic_table", Vector3(0.0, 18.0, 0.0), FLOAT_EPSILON)
		_require_node_position(prop_root, "old_cedar_stump", Vector3(0.0, 0.0, -5.25), FEATURE_TRANSFORM_TOLERANCE)
		_require_node_position(prop_root, "fire_ring", Vector3(-0.78, 0.0, 1.05), FEATURE_TRANSFORM_TOLERANCE)
		_require_node_position(prop_root, "hiking_boot", Vector3(0.75, 0.01, -4.65), FEATURE_TRANSFORM_TOLERANCE)
		_require_node_rotation(prop_root, "hiking_boot", Vector3(0.0, -32.0, 0.0), FLOAT_EPSILON)
		_require_node_position(prop_root, "water_bottle", Vector3(2.45, 0.0, -4.15), FEATURE_TRANSFORM_TOLERANCE)
		_require_node_rotation(prop_root, "water_bottle", Vector3(0.0, 17.0, 78.0), FLOAT_EPSILON)
		_require_label(prop_root, "trail_sign/label_old_cedar", "Old Cedar", 28)
		_require_label(prop_root, "trail_sign/label_creek", "Creek", 22)
		var prop_collision_count: int = _count_collision_objects(prop_root)
		if prop_collision_count > 0:
			_errors.append("PropVisuals contains collision objects: " + str(prop_collision_count))
		var prop_mesh_count: int = _count_mesh_instances(prop_root)
		if prop_mesh_count <= 0:
			_errors.append("PropVisuals contains no mesh instances")
	var scatter_root: Node = _require_node(_scene_root, "CedarHollow/ScatterVisuals")
	if scatter_root != null:
		_require_named_count(scatter_root, "grass_tuft_", EXPECTED_GRASS_TUFTS)
		_require_named_count(scatter_root, "boulder_", EXPECTED_BOULDERS)
		_require_named_count(scatter_root, "branch_", EXPECTED_BRANCHES)
		_require_named_count(scatter_root, "pinecone_", EXPECTED_PINECONES)
		var scatter_collision_count: int = _count_collision_objects(scatter_root)
		if scatter_collision_count > 0:
			_errors.append("ScatterVisuals contains collision objects: " + str(scatter_collision_count))
		var scatter_mesh_count: int = _count_mesh_instances(scatter_root)
		if scatter_mesh_count <= 0:
			_errors.append("ScatterVisuals contains no mesh instances")
	var boundary_root: Node = _require_node(_scene_root, "CedarHollow/BoundaryVisuals")
	if boundary_root != null:
		_require_named_count(boundary_root, "boundary_grass_", EXPECTED_BOUNDARY_GRASS)
		_require_named_count(boundary_root, "boundary_boulder_", EXPECTED_BOUNDARY_BOULDERS)
		_require_named_count(boundary_root, "boundary_branch_", EXPECTED_BOUNDARY_BRANCHES)
		var boundary_collision_count: int = _count_collision_objects(boundary_root)
		if boundary_collision_count > 0:
			_errors.append("BoundaryVisuals contains collision objects: " + str(boundary_collision_count))
		var boundary_mesh_count: int = _count_mesh_instances(boundary_root)
		if boundary_mesh_count <= 0:
			_errors.append("BoundaryVisuals contains no mesh instances")
	_require_node(_scene_root, "CedarHollow")
	var vehicle: Node = _require_node(_scene_root, "Vehicle")
	var chase_camera: Camera3D = _require_node(_scene_root, "ChaseCamera") as Camera3D
	var orbit_camera: Camera3D = _require_node(_scene_root, "OrbitCamera") as Camera3D
	var fpv_camera: Camera3D = _require_node(_scene_root, "FpvCamera") as Camera3D
	_inspect_camera_defaults(vehicle, chase_camera, orbit_camera, fpv_camera)
	_require_node(_scene_root, "SurfaceMap")
	var world_environment: WorldEnvironment = _require_node(_scene_root, "GoldenHourEnvironment") as WorldEnvironment
	if world_environment != null:
		_inspect_default_environment(world_environment)
	var sun: DirectionalLight3D = _require_node(_scene_root, "GoldenHourSun") as DirectionalLight3D
	if sun != null:
		_inspect_default_sun(sun)
	var audio_rig: Node = _require_node(_scene_root, "CedarAudioRig")
	if audio_rig != null:
		_inspect_audio_rig(audio_rig)
	var hud: Node = _require_node(_scene_root, "LandmarkHintHud")
	if hud != null:
		_inspect_hud_defaults(hud)
	_inspect_render_toggles(_scene_root, chase_camera, orbit_camera, fpv_camera, world_environment, sun, hud)
	_finish()


func _require_node(parent: Node, path: String) -> Node:
	var node: Node = parent.get_node_or_null(path)
	if node == null:
		_errors.append("missing node: " + path)
	return node


func _require_named_count(parent: Node, prefix: String, expected: int) -> void:
	var count: int = 0
	for child in parent.get_children():
		var child_name: String = child.name
		if child_name.begins_with(prefix):
			count += 1
	if count != expected:
		_errors.append("expected " + str(expected) + " nodes named " + prefix + "*, got " + str(count))


func _require_node_position(parent: Node, path: String, expected: Vector3, tolerance: float) -> void:
	var node: Node3D = _require_node(parent, path) as Node3D
	if node == null:
		return
	if node.position.distance_to(expected) > tolerance:
		_errors.append(path + " position expected " + str(expected) + ", got " + str(node.position))


func _require_node_rotation(parent: Node, path: String, expected: Vector3, tolerance: float) -> void:
	var node: Node3D = _require_node(parent, path) as Node3D
	if node == null:
		return
	if node.rotation_degrees.distance_to(expected) > tolerance:
		_errors.append(path + " rotation expected " + str(expected) + ", got " + str(node.rotation_degrees))


func _require_node_scale(parent: Node, path: String, expected: Vector3, tolerance: float) -> void:
	var node: Node3D = _require_node(parent, path) as Node3D
	if node == null:
		return
	if node.scale.distance_to(expected) > tolerance:
		_errors.append(path + " scale expected " + str(expected) + ", got " + str(node.scale))


func _require_label(parent: Node, path: String, expected_text: String, expected_font_size: int) -> void:
	var label: Label3D = _require_node(parent, path) as Label3D
	if label == null:
		return
	if label.text != expected_text:
		_errors.append(path + " text expected " + expected_text + ", got " + label.text)
	if label.font_size != expected_font_size:
		_errors.append(path + " font_size expected " + str(expected_font_size) + ", got " + str(label.font_size))


func _inspect_feature_collision_alignment(cedar_world: Node, feature_root: Node) -> void:
	_require_node_xz_matches_body(feature_root, "boardwalk_segment_5", cedar_world, "boardwalk__surf_wood_plank", FEATURE_COLLISION_ALIGNMENT_TOLERANCE)
	_require_node_xz_matches_body(feature_root, "culvert_pipe", cedar_world, "culvert_mouth_floor__surf_packed_dirt", FEATURE_COLLISION_ALIGNMENT_TOLERANCE)
	_require_node_xz_matches_body(feature_root, "log_ramp", cedar_world, "log_ramp__surf_wood_plank", FEATURE_COLLISION_ALIGNMENT_TOLERANCE)
	_require_node_inside_body_xz(feature_root, "boardwalk_segment_1", cedar_world, "boardwalk__surf_wood_plank", FEATURE_COLLISION_ALIGNMENT_TOLERANCE)
	_require_node_inside_body_xz(feature_root, "boardwalk_segment_9", cedar_world, "boardwalk__surf_wood_plank", FEATURE_COLLISION_ALIGNMENT_TOLERANCE)
	_require_node_inside_body_xz(feature_root, "stepping_stone_1", cedar_world, "wet_stone_crossing__surf_wet_stone", FEATURE_COLLISION_ALIGNMENT_TOLERANCE)
	_require_node_inside_body_xz(feature_root, "stepping_stone_5", cedar_world, "wet_stone_crossing__surf_wet_stone", FEATURE_COLLISION_ALIGNMENT_TOLERANCE)


func _require_node_xz_matches_body(visual_parent: Node, visual_path: String, body_parent: Node, body_path: String, tolerance: float) -> void:
	var visual: Node3D = _require_node(visual_parent, visual_path) as Node3D
	var body: Node3D = _require_node(body_parent, body_path) as Node3D
	if visual == null or body == null:
		return
	var delta: Vector2 = Vector2(visual.global_position.x - body.global_position.x, visual.global_position.z - body.global_position.z)
	if delta.length() > tolerance:
		_errors.append(visual_path + " should align with " + body_path + " in XZ, delta was " + str(delta.length()))


func _require_node_inside_body_xz(visual_parent: Node, visual_path: String, body_parent: Node, body_path: String, margin: float) -> void:
	var visual: Node3D = _require_node(visual_parent, visual_path) as Node3D
	var body: Node3D = _require_node(body_parent, body_path) as Node3D
	if visual == null or body == null:
		return
	var collision: CollisionShape3D = body.get_node_or_null("Collision") as CollisionShape3D
	if collision == null:
		_errors.append(body_path + " is missing Collision")
		return
	var box: BoxShape3D = collision.shape as BoxShape3D
	if box == null:
		_errors.append(body_path + " Collision should use BoxShape3D")
		return
	var local_position: Vector3 = body.global_transform.affine_inverse() * visual.global_position
	var half_x: float = box.size.x * 0.5 + margin
	var half_z: float = box.size.z * 0.5 + margin
	if absf(local_position.x) > half_x or absf(local_position.z) > half_z:
		_errors.append(visual_path + " should sit inside " + body_path + " XZ bounds, local position was " + str(local_position))


func _inspect_default_environment(world_environment: WorldEnvironment) -> void:
	var environment: Environment = world_environment.environment
	if environment == null:
		_errors.append("GoldenHourEnvironment has no Environment resource")
		return
	if environment.background_color != GameConfig.dusk_background_color:
		_errors.append("GoldenHourEnvironment should start in dusk background color")
	if absf(environment.fog_density - GameConfig.dusk_fog_density) > FLOAT_EPSILON:
		_errors.append("GoldenHourEnvironment should start in dusk fog density")


func _inspect_default_sun(sun: DirectionalLight3D) -> void:
	if sun.light_color != GameConfig.dusk_sun_color:
		_errors.append("GoldenHourSun should start in dusk color")
	if absf(sun.light_energy - GameConfig.dusk_sun_energy) > FLOAT_EPSILON:
		_errors.append("GoldenHourSun should start in dusk energy")


func _inspect_camera_defaults(vehicle: Node, chase_camera: Camera3D, orbit_camera: Camera3D, fpv_camera: Camera3D) -> void:
	if vehicle == null or chase_camera == null or orbit_camera == null or fpv_camera == null:
		return
	var state: RefCounted = vehicle.call("get_state")
	var vehicle_position: Vector3 = state.get("position")
	if not chase_camera.current:
		_errors.append("ChaseCamera should be current by default")
	if orbit_camera.current:
		_errors.append("OrbitCamera should not be current by default")
	if fpv_camera.current:
		_errors.append("FpvCamera should not be current by default")
	if absf(chase_camera.fov - GameConfig.cam_fov_base) > FLOAT_EPSILON:
		_errors.append("ChaseCamera should start at base FOV")
	if absf(orbit_camera.fov - GameConfig.orbit_cam_fov) > FLOAT_EPSILON:
		_errors.append("OrbitCamera should start at orbit FOV")
	if absf(fpv_camera.fov - GameConfig.fpv_cam_fov) > FLOAT_EPSILON:
		_errors.append("FpvCamera should start at FPV FOV")
	if chase_camera.global_position.y <= vehicle_position.y:
		_errors.append("ChaseCamera should start above the vehicle")
	if chase_camera.global_position.z <= vehicle_position.z:
		_errors.append("ChaseCamera should start behind the trailhead spawn")
	if orbit_camera.global_position.y <= vehicle_position.y:
		_errors.append("OrbitCamera should start above the vehicle")
	if orbit_camera.global_position.distance_to(vehicle_position) <= GameConfig.orbit_cam_distance:
		_errors.append("OrbitCamera should start outside its horizontal orbit radius")
	if fpv_camera.global_position.y <= vehicle_position.y:
		_errors.append("FpvCamera should start above the vehicle")
	if fpv_camera.global_position.z >= vehicle_position.z:
		_errors.append("FpvCamera should start ahead of the trailhead spawn")


func _inspect_hud_defaults(hud: Node) -> void:
	if hud.visible:
		_errors.append("LandmarkHintHud should be hidden by default")
	var minimap: Control = _require_node(hud, "MinimapView") as Control
	if minimap == null:
		return
	var expected_position: Vector2 = Vector2(GameConfig.minimap_margin, GameConfig.minimap_margin)
	var expected_size: Vector2 = Vector2(GameConfig.minimap_size, GameConfig.minimap_size)
	if minimap.position.distance_to(expected_position) > FLOAT_EPSILON:
		_errors.append("MinimapView position expected " + str(expected_position) + ", got " + str(minimap.position))
	if minimap.size.distance_to(expected_size) > FLOAT_EPSILON:
		_errors.append("MinimapView size expected " + str(expected_size) + ", got " + str(minimap.size))


func _inspect_render_toggles(host: Node, chase_camera: Camera3D, orbit_camera: Camera3D, fpv_camera: Camera3D, world_environment: WorldEnvironment, sun: DirectionalLight3D, hud: Node) -> void:
	if host == null:
		return
	if chase_camera != null and orbit_camera != null and fpv_camera != null:
		host.call("cycle_camera_mode")
		_require_current_camera("orbit toggle", chase_camera, orbit_camera, fpv_camera, orbit_camera)
		host.call("cycle_camera_mode")
		_require_current_camera("fpv toggle", chase_camera, orbit_camera, fpv_camera, fpv_camera)
		host.call("cycle_camera_mode")
		_require_current_camera("chase toggle", chase_camera, orbit_camera, fpv_camera, chase_camera)
	if hud != null:
		host.call("toggle_landmark_hint_hud")
		if not hud.visible:
			_errors.append("LandmarkHintHud should become visible after toggle")
		host.call("toggle_landmark_hint_hud")
		if hud.visible:
			_errors.append("LandmarkHintHud should hide after second toggle")
	if world_environment != null and sun != null:
		host.call("toggle_mood")
		_require_dawn_mood(world_environment, sun)
		host.call("toggle_mood")
		_inspect_default_environment(world_environment)
		_inspect_default_sun(sun)


func _require_current_camera(context: String, chase_camera: Camera3D, orbit_camera: Camera3D, fpv_camera: Camera3D, expected: Camera3D) -> void:
	if chase_camera.current != (chase_camera == expected):
		_errors.append(context + " ChaseCamera current state was wrong")
	if orbit_camera.current != (orbit_camera == expected):
		_errors.append(context + " OrbitCamera current state was wrong")
	if fpv_camera.current != (fpv_camera == expected):
		_errors.append(context + " FpvCamera current state was wrong")


func _require_dawn_mood(world_environment: WorldEnvironment, sun: DirectionalLight3D) -> void:
	if world_environment.environment == null:
		_errors.append("GoldenHourEnvironment has no Environment resource for dawn toggle")
		return
	var environment: Environment = world_environment.environment
	if environment.background_color != GameConfig.dawn_background_color:
		_errors.append("GoldenHourEnvironment should switch to dawn background color")
	if absf(environment.fog_density - GameConfig.dawn_fog_density) > FLOAT_EPSILON:
		_errors.append("GoldenHourEnvironment should switch to dawn fog density")
	if sun.light_color != GameConfig.dawn_sun_color:
		_errors.append("GoldenHourSun should switch to dawn color")
	if absf(sun.light_energy - GameConfig.dawn_sun_energy) > FLOAT_EPSILON:
		_errors.append("GoldenHourSun should switch to dawn energy")


func _inspect_audio_rig(audio_rig: Node) -> void:
	var surface_callable: Callable = Callable(audio_rig, "_on_vehicle_changed_surface")
	if not EventBus.vehicle_changed_surface.is_connected(surface_callable):
		_errors.append("CedarAudioRig should listen for vehicle_changed_surface")
	_require_audio_generator(audio_rig, "MotorWhine")
	_require_audio_generator(audio_rig, "TireTexture")
	_require_audio_generator(audio_rig, "AmbientBed")
	_require_audio_generator(audio_rig, "CreekBed")
	_require_audio_generator(audio_rig, "PlankKnock")


func _require_audio_generator(parent: Node, path: String) -> void:
	var player: AudioStreamPlayer = _require_node(parent, path) as AudioStreamPlayer
	if player == null:
		return
	var stream: AudioStreamGenerator = player.stream as AudioStreamGenerator
	if stream == null:
		_errors.append(path + " should use an AudioStreamGenerator")
		return
	if absf(stream.mix_rate - GameConfig.audio_mix_rate) > FLOAT_EPSILON:
		_errors.append(path + " mix_rate expected " + str(GameConfig.audio_mix_rate) + ", got " + str(stream.mix_rate))
	if absf(stream.buffer_length - GameConfig.audio_buffer_length) > FLOAT_EPSILON:
		_errors.append(path + " buffer_length expected " + str(GameConfig.audio_buffer_length) + ", got " + str(stream.buffer_length))
	if player.playing:
		_errors.append(path + " should not auto-play in headless inspection")


func _count_collision_objects(parent: Node) -> int:
	var count: int = 0
	for child in parent.get_children():
		if child is CollisionObject3D:
			count += 1
		count += _count_collision_objects(child)
	return count


func _count_mesh_instances(parent: Node) -> int:
	var count: int = 0
	for child in parent.get_children():
		if child is MeshInstance3D:
			count += 1
		count += _count_mesh_instances(child)
	return count


func _finish() -> void:
	if _errors.is_empty():
		print("ok: Cedar Hollow terrain, visuals, cameras, mood, audio, and landmark HUD nodes instantiated")
		if _scene_root != null:
			_scene_root.queue_free()
		await get_tree().process_frame
		get_tree().quit(0)
		return
	for error in _errors:
		push_error(error)
	if _scene_root != null:
		_scene_root.queue_free()
	await get_tree().process_frame
	get_tree().quit(1)
