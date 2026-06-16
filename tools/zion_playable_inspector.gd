extends Node

const CedarHollowPlayableScene: PackedScene = preload("res://scenes/cedar_hollow_playable.tscn")
const TerrainVisualBuilderScript: GDScript = preload("res://systems/render/terrain_visual_builder.gd")
const WaterVisualBuilderScript: GDScript = preload("res://systems/render/water_visual_builder.gd")
const SurfaceMapScript: GDScript = preload("res://systems/world/surface_map.gd")
const WATER_SHADER_PATH: String = "res://systems/render/water_visual.gdshader"
const ZION_REGION_ID: String = "cedar_hollow_zion"
const WORLD_REGION_ID_META: StringName = &"trailhead_world_region_id"
const SPAWN_POSITION: Vector3 = Vector3(1150.0, 1197.56, 800.0)
const SPAWN_YAW_DEGREES: float = -90.0
const EXPECTED_ACTIVE_VISUAL_CELLS: int = 25
const EXPECTED_CENTER_CELL: Vector2i = Vector2i(11, 8)
const WAIT_FRAMES: int = 1800
const POSITION_TOLERANCE_M: float = 0.45
const YAW_TOLERANCE_DEGREES: float = 1.0
const MIN_VISTA_CAMERA_FAR_M: float = 5000.0
const STRIP_ONLY_ROOTS: Array[String] = [
	"GroundDetailVisuals",
	"FeatureVisuals",
	"PropVisuals",
	"ScatterVisuals",
	"BoundaryVisuals",
]

var _scene_root: Node = null
var _errors: PackedStringArray = PackedStringArray()


func _ready() -> void:
	_scene_root = CedarHollowPlayableScene.instantiate()
	add_child(_scene_root)
	call_deferred("_inspect")


func _inspect() -> void:
	if _scene_root == null:
		_errors.append("failed to instantiate Zion playable scene")
		_finish()
		return
	var world: Node = _require_node(_scene_root, "CedarHollow")
	if world != null:
		_require_world_region(world)
		_require_no_strip_only_roots(world)
		_require_zion_water_visuals(world)
	var streamer: Node = _require_node(_scene_root, "CedarHollow/TerrainVisualStreamer")
	var visual_root: Node = _require_node(_scene_root, "CedarHollow/TerrainVisualStreamer/" + TerrainVisualBuilderScript.REGION_ROOT_NAME)
	if visual_root != null:
		_require_stream_roots(visual_root)
		_require_no_collision_objects(visual_root)
	_require_vehicle_spawn()
	_require_vista_camera_far()
	_require_surface_map()
	await _wait_for_streaming(streamer)
	_require_tile_streamer_active_set()
	_require_visual_streamer_state(streamer)
	_require_center_tile_inside_chase_camera_range(streamer)
	_finish()


func _require_world_region(world: Node) -> void:
	if not world.has_meta(WORLD_REGION_ID_META):
		_errors.append("Zion world is missing region id metadata")
		return
	var region_id: String = String(world.get_meta(WORLD_REGION_ID_META))
	if region_id != ZION_REGION_ID:
		_errors.append("Zion world region expected " + ZION_REGION_ID + ", got " + region_id)


func _require_no_strip_only_roots(world: Node) -> void:
	for root_name in STRIP_ONLY_ROOTS:
		if world.get_node_or_null(root_name) != null:
			_errors.append("Zion playable should not build strip-only root: " + root_name)
	if world.get_node_or_null("cedar_hollow_heightmap_collision") != null:
		_errors.append("Zion playable should not instantiate Cedar strip collision")


func _require_zion_water_visuals(world: Node) -> void:
	var water_root: Node = _require_node(world, WaterVisualBuilderScript.ROOT_NAME)
	if water_root == null:
		return
	_require_node(water_root, "virgin_river_west")
	_require_node(water_root, "virgin_river_east")
	for child in water_root.get_children():
		var water: MeshInstance3D = child as MeshInstance3D
		if water == null:
			continue
		if not water.is_in_group(WaterVisualBuilderScript.WATER_SURFACE_GROUP):
			_errors.append(String(water.name) + " should be in " + WaterVisualBuilderScript.WATER_SURFACE_GROUP)
		if _count_collision_objects(water) > 0:
			_errors.append(String(water.name) + " should be render-only and collision-free")
		var material: ShaderMaterial = water.material_override as ShaderMaterial
		if material == null or material.shader == null:
			_errors.append(String(water.name) + " should use water ShaderMaterial")
		elif material.shader.resource_path != WATER_SHADER_PATH:
			_errors.append(String(water.name) + " shader expected " + WATER_SHADER_PATH + ", got " + material.shader.resource_path)


func _require_stream_roots(visual_root: Node) -> void:
	_require_node(visual_root, TerrainVisualBuilderScript.REGION_DETAIL_ROOT_NAME)
	_require_node(visual_root, TerrainVisualBuilderScript.REGION_STREAMED_FOLIAGE_ROOT_NAME)
	_require_node(visual_root, TerrainVisualBuilderScript.REGION_PIPELINE_WARMUP_ROOT_NAME)
	var hlod: MeshInstance3D = _require_node(visual_root, TerrainVisualBuilderScript.REGION_HLOD_NAME) as MeshInstance3D
	if hlod == null:
		_errors.append("Zion streamer TerrainHLOD should be MeshInstance3D")
	elif hlod.mesh == null:
		_errors.append("Zion streamer TerrainHLOD is missing mesh")


func _require_vehicle_spawn() -> void:
	var vehicle: Node = _require_node(_scene_root, "Vehicle")
	if vehicle == null:
		return
	var state: RefCounted = vehicle.call("get_state")
	if state == null:
		_errors.append("Zion vehicle state is unavailable")
		return
	var position: Vector3 = state.get("position")
	if position.distance_to(SPAWN_POSITION) > POSITION_TOLERANCE_M:
		_errors.append("Zion vehicle spawn expected " + str(SPAWN_POSITION) + ", got " + str(position))
	var basis: Basis = state.get("basis")
	var yaw_degrees: float = rad_to_deg(basis.get_euler().y)
	if absf(angle_difference(deg_to_rad(SPAWN_YAW_DEGREES), deg_to_rad(yaw_degrees))) > deg_to_rad(YAW_TOLERANCE_DEGREES):
		_errors.append("Zion vehicle yaw expected " + str(SPAWN_YAW_DEGREES) + ", got " + str(yaw_degrees))


func _require_surface_map() -> void:
	var surface_map: Node = _require_node(_scene_root, "SurfaceMap")
	if surface_map == null:
		return
	if not bool(surface_map.call("is_terrain_sampler_ready")):
		_errors.append("Zion playable SurfaceMap terrain sampler is not ready")


func _require_vista_camera_far() -> void:
	_require_camera_far(_scene_root.get_node_or_null("ChaseCamera") as Camera3D, "ChaseCamera", GameConfig.cam_far)
	_require_camera_far(_scene_root.get_node_or_null("OrbitCamera") as Camera3D, "OrbitCamera", GameConfig.orbit_cam_far)
	_require_camera_far(_scene_root.get_node_or_null("FpvCamera") as Camera3D, "FpvCamera", GameConfig.fpv_cam_far)


func _require_camera_far(camera: Camera3D, label: String, expected_far: float) -> void:
	if camera == null:
		_errors.append("Zion playable missing " + label)
		return
	if camera.far + POSITION_TOLERANCE_M < MIN_VISTA_CAMERA_FAR_M:
		_errors.append(label + " far plane should be vista-forward, got " + str(camera.far))
	if absf(camera.far - expected_far) > POSITION_TOLERANCE_M:
		_errors.append(label + " far plane expected " + str(expected_far) + ", got " + str(camera.far))


func _wait_for_streaming(streamer: Node) -> void:
	if streamer == null:
		return
	for _i in range(WAIT_FRAMES):
		if _streaming_ready(streamer):
			return
		await get_tree().physics_frame
		await get_tree().process_frame
	_errors.append(
		"Zion playable streaming timed out: active="
		+ str(_tile_streamer_active_cells().size())
		+ " visual="
		+ str(int(streamer.call("visual_cell_count")))
		+ " foliage="
		+ str(int(streamer.call("foliage_cell_count")))
	)


func _streaming_ready(streamer: Node) -> bool:
	if _tile_streamer_active_cells().size() != EXPECTED_ACTIVE_VISUAL_CELLS:
		return false
	if int(streamer.call("visual_cell_count")) != EXPECTED_ACTIVE_VISUAL_CELLS:
		return false
	if int(streamer.call("foliage_cell_count")) != EXPECTED_ACTIVE_VISUAL_CELLS:
		return false
	return true


func _require_tile_streamer_active_set() -> void:
	var active_cells: Array[Vector2i] = _tile_streamer_active_cells()
	if active_cells.size() != EXPECTED_ACTIVE_VISUAL_CELLS:
		_errors.append("TileStreamer active cell count expected " + str(EXPECTED_ACTIVE_VISUAL_CELLS) + ", got " + str(active_cells.size()))
	if not active_cells.has(EXPECTED_CENTER_CELL):
		_errors.append("TileStreamer active cells should include spawn center cell " + str(EXPECTED_CENTER_CELL))
	var failures: Dictionary = _tile_streamer_failures()
	if not failures.is_empty():
		_errors.append("TileStreamer load failures: " + str(failures))


func _require_visual_streamer_state(streamer: Node) -> void:
	if streamer == null:
		return
	if int(streamer.call("visual_cell_count")) != EXPECTED_ACTIVE_VISUAL_CELLS:
		_errors.append("Zion visual cell count expected " + str(EXPECTED_ACTIVE_VISUAL_CELLS) + ", got " + str(int(streamer.call("visual_cell_count"))))
	if int(streamer.call("foliage_cell_count")) != EXPECTED_ACTIVE_VISUAL_CELLS:
		_errors.append("Zion foliage cell count expected " + str(EXPECTED_ACTIVE_VISUAL_CELLS) + ", got " + str(int(streamer.call("foliage_cell_count"))))
	if not bool(streamer.call("has_visual_cell", EXPECTED_CENTER_CELL)):
		_errors.append("Zion streamer missing visual center cell " + str(EXPECTED_CENTER_CELL))
	if not bool(streamer.call("has_foliage_cell", EXPECTED_CENTER_CELL)):
		_errors.append("Zion streamer missing foliage center cell " + str(EXPECTED_CENTER_CELL))
	var center_tile: MeshInstance3D = streamer.call("visual_cell_node", EXPECTED_CENTER_CELL) as MeshInstance3D
	if center_tile == null:
		_errors.append("Zion center visual cell should be MeshInstance3D")
	elif center_tile.mesh == null:
		_errors.append("Zion center visual cell is missing mesh")
	var failures: Dictionary = streamer.call("load_failures")
	if not failures.is_empty():
		_errors.append("Zion visual streamer load failures: " + str(failures))


func _require_center_tile_inside_chase_camera_range(streamer: Node) -> void:
	if streamer == null:
		return
	var camera: Camera3D = _scene_root.get_node_or_null("ChaseCamera") as Camera3D
	if camera == null:
		return
	var tile: MeshInstance3D = streamer.call("visual_cell_node", EXPECTED_CENTER_CELL) as MeshInstance3D
	if tile == null or tile.mesh == null:
		return
	var global_aabb: AABB = tile.global_transform * tile.mesh.get_aabb()
	var center_distance: float = camera.global_position.distance_to(global_aabb.get_center())
	if center_distance > camera.far:
		_errors.append("Zion center visual tile is beyond ChaseCamera far plane: distance=" + str(center_distance) + " far=" + str(camera.far))


func _tile_streamer_active_cells() -> Array[Vector2i]:
	var streamer: Node = get_node_or_null("/root/TileStreamer")
	var cells: Array[Vector2i] = []
	if streamer == null:
		_errors.append("Zion playable requires TileStreamer autoload")
		return cells
	var value: Variant = streamer.call("active_cells")
	if value is Array:
		for item in value:
			if item is Vector2i:
				cells.append(item)
	return cells


func _tile_streamer_failures() -> Dictionary:
	var streamer: Node = get_node_or_null("/root/TileStreamer")
	if streamer == null:
		return {}
	return streamer.call("load_failures")


func _require_no_collision_objects(parent: Node) -> void:
	var collision_count: int = _count_collision_objects(parent)
	if collision_count > 0:
		_errors.append("Zion streamed visuals should not contain collision objects: " + str(collision_count))


func _count_collision_objects(parent: Node) -> int:
	var count: int = 0
	if parent is CollisionObject3D or parent is CollisionShape3D:
		count += 1
	for child in parent.get_children():
		count += _count_collision_objects(child)
	return count


func _require_node(parent: Node, path: String) -> Node:
	if parent == null:
		_errors.append("cannot resolve node on null parent: " + path)
		return null
	var node: Node = parent.get_node_or_null(path)
	if node == null:
		_errors.append("missing node: " + path)
	return node


func _finish() -> void:
	if _errors.size() > 0:
		for error in _errors:
			push_error(error)
		_cleanup()
		get_tree().quit(1)
		return
	print("ok: Zion playable streams terrain and foliage around stream_west")
	_cleanup()
	get_tree().quit(0)


func _cleanup() -> void:
	if _scene_root != null:
		_scene_root.queue_free()
		_scene_root = null
