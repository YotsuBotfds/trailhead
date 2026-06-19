extends Node

const CedarHollowPlayableScene: PackedScene = preload("res://scenes/cedar_hollow_playable.tscn")
const CedarHollowHostScript: GDScript = preload("res://systems/render/cedar_hollow_host.gd")
const CedarRoute: Resource = preload("res://data/routes/cedar_hollow_zion_stream_route.tres")
const TerrainVisualBuilderScript: GDScript = preload("res://systems/render/terrain_visual_builder.gd")
const WaterVisualBuilderScript: GDScript = preload("res://systems/render/water_visual_builder.gd")
const SurfaceMapScript: GDScript = preload("res://systems/world/surface_map.gd")
const WATER_SHADER_PATH: String = "res://systems/render/water_visual.gdshader"
const ZION_REGION_ID: String = "cedar_hollow_zion"
const WORLD_REGION_ID_META: StringName = &"trailhead_world_region_id"
const EXPECTED_ACTIVE_VISUAL_CELLS: int = 25
const FOLIAGE_STEEP_AUDIT_CELL: Vector2i = Vector2i(22, 51)
const FOLIAGE_STREAM_WEST_AUDIT_CELL: Vector2i = Vector2i(11, 8)
const FOLIAGE_WOODLAND_AUDIT_CELL: Vector2i = Vector2i(0, 20)
const FOLIAGE_TALUS_AUDIT_CELL: Vector2i = Vector2i(20, 17)
const FOLIAGE_DOMINANT_SURFACE_MIN_SHARE: float = 0.95
const FOLIAGE_SLOPE_EPSILON: float = 0.0001
const FOLIAGE_MIN_STREAM_WEST_SCRUB_INSTANCES: int = 150
const FOLIAGE_MIN_WOODLAND_INSTANCES: int = 150
const FOLIAGE_MAX_TALUS_INSTANCES: int = 120
const FOLIAGE_MIN_WOODLAND_TO_TALUS_RATIO: float = 1.5
const WAIT_FRAMES: int = 1800
const POSITION_TOLERANCE_M: float = 0.45
const YAW_TOLERANCE_DEGREES: float = 1.0
const MIN_VISTA_CAMERA_FAR_M: float = 1200.0
const STRIP_ONLY_ROOTS: Array[String] = [
	"GroundDetailVisuals",
	"FeatureVisuals",
	"PropVisuals",
	"ScatterVisuals",
	"BoundaryVisuals",
]

var _scene_root: Node = null
var _errors: PackedStringArray = PackedStringArray()
var _expected_spawn_id: StringName = &""
var _expected_spawn_position: Vector3 = Vector3.ZERO
var _expected_spawn_yaw_degrees: float = 0.0
var _expected_center_cell: Vector2i = Vector2i.ZERO


func _ready() -> void:
	_resolve_expected_spawn()
	_scene_root = CedarHollowPlayableScene.instantiate()
	add_child(_scene_root)
	call_deferred("_inspect")


func _resolve_expected_spawn() -> void:
	_expected_spawn_id = CedarHollowHostScript.ZION_SPAWN_ID
	var spawn_transform: Transform3D = CedarRoute.call("spawn_transform", _expected_spawn_id)
	_expected_spawn_position = spawn_transform.origin
	_expected_spawn_yaw_degrees = rad_to_deg(spawn_transform.basis.get_euler().y)
	_expected_center_cell = Vector2i(
		int(floorf(_expected_spawn_position.x / GameConfig.STREAM_TILE_SIZE_M)),
		int(floorf(_expected_spawn_position.z / GameConfig.STREAM_TILE_SIZE_M))
	)


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
	_require_hud_overlays()
	await _wait_for_streaming(streamer)
	_require_tile_streamer_active_set()
	_require_visual_streamer_state(streamer)
	_require_center_tile_inside_chase_camera_range(streamer)
	_require_zion_foliage_placement_audits()
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
	_require_node(visual_root, TerrainVisualBuilderScript.REGION_STREAM_MIDLOD_ROOT_NAME)
	_require_node(visual_root, TerrainVisualBuilderScript.REGION_STREAMED_FOLIAGE_ROOT_NAME)
	var warmup_root: Node = _require_node(visual_root, TerrainVisualBuilderScript.REGION_PIPELINE_WARMUP_ROOT_NAME)
	if warmup_root != null:
		_require_pipeline_warmup(warmup_root)
	var hlod: MeshInstance3D = _require_node(visual_root, TerrainVisualBuilderScript.REGION_HLOD_NAME) as MeshInstance3D
	if hlod == null:
		_errors.append("Zion streamer TerrainHLOD should be MeshInstance3D")
	else:
		_require_stream_hlod(hlod)


func _require_pipeline_warmup(warmup_root: Node) -> void:
	var foliage_warmup_count: int = _require_int_meta(
		warmup_root,
		TerrainVisualBuilderScript.PIPELINE_WARMUP_FOLIAGE_LOD_COUNT_META,
		"PipelineWarmup"
	)
	var expected_foliage_warmup_nodes: PackedStringArray = TerrainVisualBuilderScript.foliage_pipeline_warmup_node_names()
	if foliage_warmup_count != expected_foliage_warmup_nodes.size():
		_errors.append("PipelineWarmup foliage warmup count expected " + str(expected_foliage_warmup_nodes.size()) + ", got " + str(foliage_warmup_count))
	for node_name in expected_foliage_warmup_nodes:
		var warmup_instance: MultiMeshInstance3D = _require_node(warmup_root, node_name) as MultiMeshInstance3D
		if warmup_instance == null:
			_errors.append("PipelineWarmup " + node_name + " should be MultiMeshInstance3D")
			continue
		if warmup_instance.multimesh == null:
			_errors.append("PipelineWarmup " + node_name + " missing MultiMesh")
		elif warmup_instance.multimesh.mesh == null:
			_errors.append("PipelineWarmup " + node_name + " missing mesh")
		if warmup_instance.material_override == null:
			_errors.append("PipelineWarmup " + node_name + " missing material")


func _require_int_meta(node: Node, meta_name: StringName, label: String) -> int:
	if not node.has_meta(meta_name):
		_errors.append(label + " missing metadata: " + String(meta_name))
		return 0
	return int(node.get_meta(meta_name))


func _require_stream_hlod(hlod: MeshInstance3D) -> void:
	var chunks: Array[MeshInstance3D] = []
	_collect_stream_hlod_chunks(hlod, chunks)
	if chunks.size() <= 1:
		_errors.append("Zion streamer TerrainHLOD should be chunked into localized tile HLODs")
	for chunk in chunks:
		_require_stream_hlod_chunk(chunk)
	var center_chunk: MeshInstance3D = _stream_hlod_chunk_for_cell(chunks, _expected_center_cell)
	if center_chunk == null:
		_errors.append("Zion streamer TerrainHLOD missing chunk for spawn cell " + str(_expected_center_cell))
		return
	var center_origin_xz: Vector2 = Vector2(center_chunk.global_position.x, center_chunk.global_position.z)
	var spawn_xz: Vector2 = Vector2(_expected_spawn_position.x, _expected_spawn_position.z)
	var spawn_distance: float = center_origin_xz.distance_to(spawn_xz)
	if spawn_distance + POSITION_TOLERANCE_M >= center_chunk.visibility_range_begin:
		_errors.append(
			"Zion spawn HLOD chunk should remain begin-gated under the car: distance="
			+ str(spawn_distance)
			+ " begin="
			+ str(center_chunk.visibility_range_begin)
		)


func _collect_stream_hlod_chunks(parent: Node, chunks: Array[MeshInstance3D]) -> void:
	var mesh_instance: MeshInstance3D = parent as MeshInstance3D
	if mesh_instance != null and _is_stream_hlod_chunk(mesh_instance):
		chunks.append(mesh_instance)
	for child in parent.get_children():
		_collect_stream_hlod_chunks(child, chunks)


func _is_stream_hlod_chunk(chunk: MeshInstance3D) -> bool:
	if chunk == null or not chunk.has_meta(TerrainVisualBuilderScript.REGION_LOD_META):
		return false
	return String(chunk.get_meta(TerrainVisualBuilderScript.REGION_LOD_META)) == "stream_hlod"


func _stream_hlod_chunk_for_cell(chunks: Array[MeshInstance3D], cell: Vector2i) -> MeshInstance3D:
	for chunk in chunks:
		if not chunk.has_meta(TerrainVisualBuilderScript.TILE_INDEX_META):
			continue
		if Vector2i(chunk.get_meta(TerrainVisualBuilderScript.TILE_INDEX_META)) == cell:
			return chunk
	return null


func _require_stream_hlod_chunk(chunk: MeshInstance3D) -> void:
	if chunk.mesh == null:
		_errors.append(String(chunk.name) + " is missing mesh")
		return
	if chunk.mesh.get_surface_count() <= 0:
		_errors.append(String(chunk.name) + " mesh has no surfaces")
	if not _is_stream_hlod_chunk(chunk):
		_errors.append(String(chunk.name) + " missing stream_hlod metadata")
	if not chunk.has_meta(TerrainVisualBuilderScript.TILE_INDEX_META):
		_errors.append(String(chunk.name) + " missing HLOD tile metadata")
	else:
		var cell: Vector2i = Vector2i(chunk.get_meta(TerrainVisualBuilderScript.TILE_INDEX_META))
		var expected_origin: Vector3 = Vector3(
			(float(cell.x) + 0.5) * GameConfig.STREAM_TILE_SIZE_M,
			0.0,
			(float(cell.y) + 0.5) * GameConfig.STREAM_TILE_SIZE_M
		)
		var observed_xz: Vector2 = Vector2(chunk.global_position.x, chunk.global_position.z)
		var expected_xz: Vector2 = Vector2(expected_origin.x, expected_origin.z)
		if observed_xz.distance_to(Vector2.ZERO) <= POSITION_TOLERANCE_M:
			_errors.append(String(chunk.name) + " HLOD origin should not be world zero")
		if observed_xz.distance_to(expected_xz) > POSITION_TOLERANCE_M:
			_errors.append(String(chunk.name) + " HLOD origin expected " + str(expected_origin) + ", got " + str(chunk.global_position))
	if absf(chunk.visibility_range_begin - TerrainVisualBuilderScript.REGION_STREAM_MIDLOD_RANGE_END_M) > POSITION_TOLERANCE_M:
		_errors.append(String(chunk.name) + " HLOD visibility_range_begin expected " + str(TerrainVisualBuilderScript.REGION_STREAM_MIDLOD_RANGE_END_M) + ", got " + str(chunk.visibility_range_begin))
	if absf(chunk.visibility_range_end) > POSITION_TOLERANCE_M:
		_errors.append(String(chunk.name) + " HLOD visibility_range_end should be open-ended")
	if chunk.visibility_range_fade_mode != GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED:
		_errors.append(String(chunk.name) + " HLOD visibility_range_fade_mode expected DISABLED")
	for surface_index in range(chunk.mesh.get_surface_count()):
		var material: ShaderMaterial = chunk.mesh.surface_get_material(surface_index) as ShaderMaterial
		if material == null:
			_errors.append(String(chunk.name) + " HLOD surface " + str(surface_index) + " should use surface-index ShaderMaterial")
			continue
		if material.resource_name != TerrainVisualBuilderScript.TERRAIN_INDEX_MATERIAL_NAME:
			_errors.append(String(chunk.name) + " HLOD material expected " + TerrainVisualBuilderScript.TERRAIN_INDEX_MATERIAL_NAME + ", got " + material.resource_name)
		var surface_id_texture: Texture2D = material.get_shader_parameter(TerrainVisualBuilderScript.SURFACE_ID_TEXTURE_UNIFORM) as Texture2D
		if surface_id_texture == null:
			_errors.append(String(chunk.name) + " HLOD surface-index material missing surface ID texture")


func _require_first_midlod_tile() -> void:
	var midlod_root: Node = _scene_root.get_node_or_null("CedarHollow/TerrainVisualStreamer/" + TerrainVisualBuilderScript.REGION_ROOT_NAME + "/" + TerrainVisualBuilderScript.REGION_STREAM_MIDLOD_ROOT_NAME)
	if midlod_root == null:
		_errors.append("Zion streamer missing TerrainMidLODTiles root")
		return
	var midlod_tile: MeshInstance3D = null
	for child in midlod_root.get_children():
		var mesh_instance: MeshInstance3D = child as MeshInstance3D
		if mesh_instance != null:
			midlod_tile = mesh_instance
			break
	if midlod_tile == null:
		_errors.append("Zion TerrainMidLODTiles should contain at least one MeshInstance3D")
		return
	if not midlod_tile.has_meta(TerrainVisualBuilderScript.REGION_LOD_META):
		_errors.append(String(midlod_tile.name) + " missing mid-LOD metadata")
	elif String(midlod_tile.get_meta(TerrainVisualBuilderScript.REGION_LOD_META)) != "stream_midlod":
		_errors.append(String(midlod_tile.name) + " mid-LOD metadata expected stream_midlod")
	if absf(midlod_tile.visibility_range_begin - GameConfig.vis_range_terrain) > POSITION_TOLERANCE_M:
		_errors.append(String(midlod_tile.name) + " mid-LOD visibility_range_begin expected " + str(GameConfig.vis_range_terrain) + ", got " + str(midlod_tile.visibility_range_begin))
	if not midlod_tile.has_meta(TerrainVisualBuilderScript.VISIBILITY_RADIUS_META):
		_errors.append(String(midlod_tile.name) + " missing mid-LOD visibility radius metadata")
	else:
		var visibility_radius: float = float(midlod_tile.get_meta(TerrainVisualBuilderScript.VISIBILITY_RADIUS_META))
		var expected_range_end: float = TerrainVisualBuilderScript.REGION_STREAM_MIDLOD_RANGE_END_M + visibility_radius
		if absf(midlod_tile.visibility_range_end - expected_range_end) > POSITION_TOLERANCE_M:
			_errors.append(String(midlod_tile.name) + " mid-LOD visibility_range_end expected " + str(expected_range_end) + ", got " + str(midlod_tile.visibility_range_end))
	if midlod_tile.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
		_errors.append(String(midlod_tile.name) + " mid-LOD should not cast shadows")
	if midlod_tile.mesh == null:
		_errors.append(String(midlod_tile.name) + " mid-LOD missing mesh")
	elif midlod_tile.mesh.get_surface_count() <= 0:
		_errors.append(String(midlod_tile.name) + " mid-LOD mesh has no surfaces")
	if _count_collision_objects(midlod_tile) > 0:
		_errors.append(String(midlod_tile.name) + " mid-LOD should be render-only and collision-free")


func _require_vehicle_spawn() -> void:
	var vehicle: Node = _require_node(_scene_root, "Vehicle")
	if vehicle == null:
		return
	var state: RefCounted = vehicle.call("get_state")
	if state == null:
		_errors.append("Zion vehicle state is unavailable")
		return
	var position: Vector3 = state.get("position")
	if position.distance_to(_expected_spawn_position) > POSITION_TOLERANCE_M:
		_errors.append("Zion vehicle spawn expected " + str(_expected_spawn_position) + ", got " + str(position))
	var basis: Basis = state.get("basis")
	var yaw_degrees: float = rad_to_deg(basis.get_euler().y)
	if absf(angle_difference(deg_to_rad(_expected_spawn_yaw_degrees), deg_to_rad(yaw_degrees))) > deg_to_rad(YAW_TOLERANCE_DEGREES):
		_errors.append("Zion vehicle yaw expected " + str(_expected_spawn_yaw_degrees) + ", got " + str(yaw_degrees))


func _require_surface_map() -> void:
	var surface_map: Node = _require_node(_scene_root, "SurfaceMap")
	if surface_map == null:
		return
	if not bool(surface_map.call("is_terrain_sampler_ready")):
		_errors.append("Zion playable SurfaceMap terrain sampler is not ready")


func _require_hud_overlays() -> void:
	var speed_hud: Node = _require_node(_scene_root, "SpeedHud")
	if speed_hud != null:
		if not (speed_hud is CanvasLayer):
			_errors.append("SpeedHud should be a CanvasLayer")
		if speed_hud.get_node_or_null("SpeedHudPanel") == null:
			_errors.append("SpeedHud should spawn its draw panel after setup")
		if GameConfig.speed_hud_enabled and not speed_hud.visible:
			_errors.append("SpeedHud should be visible when speed_hud_enabled is true")
	var controls_hint: Node = _require_node(_scene_root, "ControlsHintHud")
	if controls_hint != null:
		if not (controls_hint is CanvasLayer):
			_errors.append("ControlsHintHud should be a CanvasLayer")
		if controls_hint.get_node_or_null("ControlsHintPanel") == null:
			_errors.append("ControlsHintHud should spawn its draw panel after setup")
		if GameConfig.controls_hint_hud_enabled and not controls_hint.visible:
			_errors.append("ControlsHintHud should be visible when controls_hint_hud_enabled is true")
	var debug_overlay: Node = _require_node(_scene_root, "DebugOverlayHud")
	if debug_overlay != null:
		if not (debug_overlay is CanvasLayer):
			_errors.append("DebugOverlayHud should be a CanvasLayer")
		if debug_overlay.get_node_or_null("DebugOverlayPanel") == null:
			_errors.append("DebugOverlayHud should spawn its draw panel after setup")
		if debug_overlay.visible:
			_errors.append("DebugOverlayHud should default off")


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
		+ " midlod="
		+ str(int(streamer.call("midlod_cell_count")))
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
	if int(streamer.call("midlod_cell_count")) <= 0:
		return false
	return true


func _require_tile_streamer_active_set() -> void:
	var active_cells: Array[Vector2i] = _tile_streamer_active_cells()
	if active_cells.size() != EXPECTED_ACTIVE_VISUAL_CELLS:
		_errors.append("TileStreamer active cell count expected " + str(EXPECTED_ACTIVE_VISUAL_CELLS) + ", got " + str(active_cells.size()))
	if not active_cells.has(_expected_center_cell):
		_errors.append("TileStreamer active cells should include spawn center cell " + str(_expected_center_cell))
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
	if int(streamer.call("midlod_cell_count")) <= 0:
		_errors.append("Zion streamer should commit at least one mid-LOD cell")
	if not bool(streamer.call("has_visual_cell", _expected_center_cell)):
		_errors.append("Zion streamer missing visual center cell " + str(_expected_center_cell))
	if not bool(streamer.call("has_foliage_cell", _expected_center_cell)):
		_errors.append("Zion streamer missing foliage center cell " + str(_expected_center_cell))
	var center_tile: MeshInstance3D = streamer.call("visual_cell_node", _expected_center_cell) as MeshInstance3D
	if center_tile == null:
		_errors.append("Zion center visual cell should be MeshInstance3D")
	elif center_tile.mesh == null:
		_errors.append("Zion center visual cell is missing mesh")
	elif not center_tile.visibility_parent.is_empty():
		_errors.append("Zion center visual cell should not use TerrainHLOD as visibility_parent")
	elif center_tile.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_ON:
		_errors.append("Zion center visual cell should cast shadows")
	_require_first_midlod_tile()
	var failures: Dictionary = streamer.call("load_failures")
	if not failures.is_empty():
		_errors.append("Zion visual streamer load failures: " + str(failures))


func _require_center_tile_inside_chase_camera_range(streamer: Node) -> void:
	if streamer == null:
		return
	var camera: Camera3D = _scene_root.get_node_or_null("ChaseCamera") as Camera3D
	if camera == null:
		return
	var tile: MeshInstance3D = streamer.call("visual_cell_node", _expected_center_cell) as MeshInstance3D
	if tile == null or tile.mesh == null:
		return
	var global_aabb: AABB = tile.global_transform * tile.mesh.get_aabb()
	var center_distance: float = camera.global_position.distance_to(global_aabb.get_center())
	if center_distance > camera.far:
		_errors.append("Zion center visual tile is beyond ChaseCamera far plane: distance=" + str(center_distance) + " far=" + str(camera.far))


func _require_zion_foliage_placement_audits() -> void:
	var steep_audit: Dictionary[String, Variant] = TerrainVisualBuilderScript.build_region_foliage_tile_audit(ZION_REGION_ID, FOLIAGE_STEEP_AUDIT_CELL)
	if _require_foliage_audit_ok(steep_audit, "steep foliage audit"):
		var steep_instance_count: int = int(steep_audit.get("instance_count", 0))
		if steep_instance_count <= 0:
			_errors.append("steep foliage audit should still place nonzero accepted instances")
		var slope_rejected_count: int = int(steep_audit.get("slope_rejected_count", 0))
		if slope_rejected_count <= 0:
			_errors.append("steep foliage audit should reject at least one candidate by slope")
		var slope_violation_count: int = int(steep_audit.get("slope_violation_count", 0))
		if slope_violation_count != 0:
			_errors.append("steep foliage audit placed " + str(slope_violation_count) + " instances below the slope normal gate")
		var min_accepted_normal_y: float = float(steep_audit.get("min_accepted_normal_y", 1.0))
		if min_accepted_normal_y + FOLIAGE_SLOPE_EPSILON < TerrainVisualBuilderScript.FOLIAGE_MAX_SLOPE_NORMAL_Y:
			_errors.append(
				"steep foliage audit min accepted normal.y expected >= "
				+ str(TerrainVisualBuilderScript.FOLIAGE_MAX_SLOPE_NORMAL_Y)
				+ ", got "
				+ str(min_accepted_normal_y)
			)

	var stream_west_audit: Dictionary[String, Variant] = TerrainVisualBuilderScript.build_region_foliage_tile_audit(ZION_REGION_ID, FOLIAGE_STREAM_WEST_AUDIT_CELL)
	if _require_foliage_audit_ok(stream_west_audit, "stream west foliage audit"):
		_require_foliage_dominant_surface(stream_west_audit, "stream west foliage audit", 6)
		_require_foliage_species_present(stream_west_audit, "stream west foliage audit", "grass")
		var stream_west_grass_count: int = int(stream_west_audit.get("grass_instance_count", 0))
		if stream_west_grass_count < FOLIAGE_MIN_STREAM_WEST_SCRUB_INSTANCES:
			_errors.append("stream west foliage audit expected scrub on the drivable corridor, got " + str(stream_west_grass_count))

	var woodland_audit: Dictionary[String, Variant] = TerrainVisualBuilderScript.build_region_foliage_tile_audit(ZION_REGION_ID, FOLIAGE_WOODLAND_AUDIT_CELL)
	var talus_audit: Dictionary[String, Variant] = TerrainVisualBuilderScript.build_region_foliage_tile_audit(ZION_REGION_ID, FOLIAGE_TALUS_AUDIT_CELL)
	var woodland_ok: bool = _require_foliage_audit_ok(woodland_audit, "woodland foliage audit")
	var talus_ok: bool = _require_foliage_audit_ok(talus_audit, "talus foliage audit")
	if woodland_ok:
		_require_foliage_dominant_surface(woodland_audit, "woodland foliage audit", 3)
		_require_foliage_species_present(woodland_audit, "woodland foliage audit", "juniper")
	if talus_ok:
		_require_foliage_dominant_surface(talus_audit, "talus foliage audit", 4)
		_require_foliage_species_present(talus_audit, "talus foliage audit", "yucca")
		_require_foliage_species_present(talus_audit, "talus foliage audit", "boulder")
	if not woodland_ok or not talus_ok:
		return

	var woodland_instance_count: int = int(woodland_audit.get("instance_count", 0))
	var talus_instance_count: int = int(talus_audit.get("instance_count", 0))
	if woodland_instance_count < FOLIAGE_MIN_WOODLAND_INSTANCES:
		_errors.append("woodland foliage audit expected dense class-3 placement, got " + str(woodland_instance_count))
	if talus_instance_count > FOLIAGE_MAX_TALUS_INSTANCES:
		_errors.append("talus foliage audit expected sparse class-4 placement, got " + str(talus_instance_count))
	if float(woodland_instance_count) <= float(talus_instance_count) * FOLIAGE_MIN_WOODLAND_TO_TALUS_RATIO:
		_errors.append(
			"woodland foliage audit should be materially denser than talus: woodland="
			+ str(woodland_instance_count)
			+ " talus="
			+ str(talus_instance_count)
		)


func _require_foliage_audit_ok(audit: Dictionary[String, Variant], label: String) -> bool:
	if bool(audit.get("ok", false)):
		return true
	_errors.append(label + " failed: " + String(audit.get("message", "")))
	return false


func _require_foliage_dominant_surface(audit: Dictionary[String, Variant], label: String, expected_surface_id_value: int) -> void:
	var observed_surface_id_value: int = int(audit.get("dominant_surface_id_value", 0))
	if observed_surface_id_value != expected_surface_id_value:
		_errors.append(label + " expected dominant surface " + str(expected_surface_id_value) + ", got " + str(observed_surface_id_value))
	var observed_share: float = float(audit.get("dominant_surface_share", 0.0))
	if observed_share < FOLIAGE_DOMINANT_SURFACE_MIN_SHARE:
		_errors.append(label + " dominant surface share expected >= " + str(FOLIAGE_DOMINANT_SURFACE_MIN_SHARE) + ", got " + str(observed_share))


func _require_foliage_species_present(audit: Dictionary[String, Variant], label: String, species_id: String) -> void:
	var instance_count: int = int(audit.get(species_id + "_instance_count", 0))
	if instance_count <= 0:
		_errors.append(label + " expected " + species_id + " instances, got " + str(instance_count))


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
	print("ok: Zion playable streams terrain and foliage around " + String(_expected_spawn_id))
	_cleanup()
	get_tree().quit(0)


func _cleanup() -> void:
	if _scene_root != null:
		_scene_root.queue_free()
		_scene_root = null
