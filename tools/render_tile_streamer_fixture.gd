extends Node

const TerrainVisualStreamerScript: GDScript = preload("res://systems/render/terrain_visual_streamer.gd")
const TerrainVisualBuilderScript: GDScript = preload("res://systems/render/terrain_visual_builder.gd")
const REGION_ID: String = "spike_1km"
const FIRST_CELL: Vector2i = Vector2i(2, 2)
const SECOND_CELL: Vector2i = Vector2i(2, 3)
const FLOAT_EPSILON: float = 0.001
const WAIT_FRAMES: int = 180
const EXPECTED_STREAM_HLOD_MAX_PRIMITIVES: int = 5000
const EXPECTED_STREAM_MIDLOD_MIN_PRIMITIVES: int = 1000
const PRESSURE_CENTER_CELL: Vector2i = Vector2i(5, 5)
const PRESSURE_ACTIVE_RADIUS: int = 2
const MIDLOD_DRAIN_SLACK_FRAMES: int = 8

var _streamer: Node3D = null
var _errors: PackedStringArray = PackedStringArray()


func _ready() -> void:
	_streamer = TerrainVisualStreamerScript.new() as Node3D
	_streamer.name = "RenderTileStreamer"
	add_child(_streamer)
	call_deferred("_inspect")


func _inspect() -> void:
	if _streamer == null:
		_errors.append("failed to instantiate terrain visual streamer")
		_finish()
		return

	_streamer.call("configure_region", REGION_ID)
	_streamer.call("set_worker_count_for_tests", 0)
	_require_cell_count("configured empty", 0)
	_require_cells("configured active cells", [])
	_require_detail_root()
	_require_stream_midlod_root()
	_require_streamed_foliage_root()
	_require_pipeline_warmup()
	_require_stream_hlod(false)

	EventBus.world_tile_prefetched.emit(FIRST_CELL)
	_require_cell_count("first prefetch stays unattached", 0)
	_require_foliage_cell_count("first prefetch foliage stays unattached", 0)
	await _wait_for_ready_cell_count("first prefetch ready", 1)
	await _wait_for_ready_foliage_cell_count("first foliage prefetch ready", 1)
	_require_cell_count("first prefetch after ready stays unattached", 0)
	_require_foliage_cell_count("first foliage prefetch after ready stays unattached", 0)

	EventBus.world_tile_activated.emit(FIRST_CELL)
	await _wait_for_pending_commit_count("first activation pending commit", 1)
	await _wait_for_cell_count("first activation", 1)
	await _wait_for_foliage_cell_count("first foliage activation", 1)
	_require_cell_count("first activation", 1)
	_require_foliage_cell_count("first foliage activation", 1)
	_require_cells("first activation cells", [FIRST_CELL])
	_require_stream_hlod(true)
	await _wait_for_midlod_cell_count("first mid-LOD activation", 1)
	_require_midlod_cell_count_at_least("first mid-LOD activation", 1)
	_require_first_midlod_tile()
	_require_foliage_tile(FIRST_CELL)
	var first_tile: MeshInstance3D = _require_visual_tile(FIRST_CELL)
	var first_surface_count: int = 0
	var first_vertex_count: int = 0
	var first_index_count: int = 0
	var first_bounds: AABB = AABB()
	var first_materials_by_name: Dictionary[String, StandardMaterial3D] = {}
	var first_surface_index_material: ShaderMaterial = null
	if first_tile != null and first_tile.mesh != null:
		first_surface_count = first_tile.mesh.get_surface_count()
		first_vertex_count = _mesh_vertex_count(first_tile.mesh)
		first_index_count = _mesh_index_count(first_tile.mesh)
		first_bounds = first_tile.mesh.get_aabb()
		first_materials_by_name = _surface_materials_by_name(first_tile)
		first_surface_index_material = _surface_index_material_for_tile(first_tile)

	EventBus.world_tile_activated.emit(FIRST_CELL)
	_require_cell_count("duplicate activation", 1)
	_require_cells("duplicate activation cells", [FIRST_CELL])

	EventBus.world_tile_activated.emit(SECOND_CELL)
	_require_cell_count("second activation before deferred commit", 1)
	await _wait_for_cell_count("second activation", 2)
	await _wait_for_foliage_cell_count("second foliage activation", 2)
	_require_cell_count("second activation", 2)
	_require_foliage_cell_count("second foliage activation", 2)
	_require_cells("second activation cells", [FIRST_CELL, SECOND_CELL])
	var second_tile: MeshInstance3D = _require_visual_tile(SECOND_CELL)
	_require_surface_index_material_reused_or_fallback(first_surface_index_material, second_tile)
	_require_foliage_tile(SECOND_CELL)

	EventBus.world_tile_evicted.emit(FIRST_CELL)
	# FIX-4: visual/foliage free is now deferred across frames (player-invisible,
	# HLOD covers the far tile), so wait for the budgeted drain instead of asserting
	# the free synchronously. The remaining checks below then hold once drained.
	await _wait_for_cell_count("first eviction", 1)
	await _wait_for_foliage_cell_count("first foliage eviction", 1)
	_require_stream_hlod(true)
	_require_cells("first eviction cells", [SECOND_CELL])
	_require_no_visual_cell(FIRST_CELL)
	_require_no_foliage_cell(FIRST_CELL)
	_require_ready_cell_count("first eviction keeps prefetched payload", 0)
	_require_ready_foliage_cell_count("first eviction foliage ready cache", 0)

	EventBus.world_tile_evicted.emit(Vector2i(9, 9))
	_require_cell_count("unknown eviction", 1)
	_require_cells("unknown eviction cells", [SECOND_CELL])

	EventBus.world_tile_prefetched.emit(FIRST_CELL)
	await _wait_for_ready_cell_count("reactivation prefetch ready", 1)
	await _wait_for_ready_foliage_cell_count("reactivation foliage prefetch ready", 1)
	EventBus.world_tile_activated.emit(FIRST_CELL)
	await _wait_for_cell_count("reactivation", 2)
	await _wait_for_foliage_cell_count("reactivation foliage", 2)
	_require_cell_count("reactivation", 2)
	_require_foliage_cell_count("reactivation foliage", 2)
	_require_cells("reactivation cells", [FIRST_CELL, SECOND_CELL])
	var rebuilt_tile: MeshInstance3D = _require_visual_tile(FIRST_CELL)
	_require_rebuilt_tile(first_surface_count, first_vertex_count, first_index_count, first_bounds, rebuilt_tile)
	_require_cached_materials_reused(first_materials_by_name, rebuilt_tile)
	_require_surface_index_material_reused_or_fallback(first_surface_index_material, rebuilt_tile)

	EventBus.world_tile_evicted.emit(FIRST_CELL)
	EventBus.world_tile_unprefetched.emit(FIRST_CELL)
	_require_ready_cell_count("unprefetch drops inactive ready payload", 0)
	_require_ready_foliage_cell_count("unprefetch drops inactive foliage ready payload", 0)
	_require_pending_commit_count("unprefetch drops inactive pending commit", 0)
	EventBus.world_tile_activated.emit(FIRST_CELL)
	await _wait_for_cell_count("post-unprefetch activation", 2)
	await _wait_for_foliage_cell_count("post-unprefetch foliage activation", 2)
	_require_cell_count("post-unprefetch activation", 2)
	_require_foliage_cell_count("post-unprefetch foliage activation", 2)
	_require_visual_tile(FIRST_CELL)
	_require_foliage_tile(FIRST_CELL)

	await _exercise_midlod_commit_pressure()
	await _exercise_midlod_failure_retry_after_free()
	await _exercise_fullres_on_activation()
	await _exercise_fullres_on_inflight_prefetch_activation()

	_streamer.call("reset_stream")
	_require_cell_count("reset", 0)
	_require_foliage_cell_count("reset foliage", 0)
	_require_ready_cell_count("reset ready cache", 0)
	_require_midlod_cell_count("reset mid-LOD", 0)
	_require_ready_foliage_cell_count("reset foliage ready cache", 0)
	_require_cells("reset cells", [])
	EventBus.world_tile_activated.emit(FIRST_CELL)
	_require_cell_count("post-reset disconnected", 0)
	_finish()


func _require_detail_root() -> void:
	var terrain_root: Node = _streamer.get_node_or_null(TerrainVisualBuilderScript.REGION_ROOT_NAME)
	if terrain_root == null:
		_errors.append("streamer missing TerrainVisuals root")
		return
	var detail_root: Node = terrain_root.get_node_or_null(TerrainVisualBuilderScript.REGION_DETAIL_ROOT_NAME)
	if detail_root == null:
		_errors.append("streamer missing TerrainDetailTiles root")


func _require_stream_midlod_root() -> void:
	var terrain_root: Node = _streamer.get_node_or_null(TerrainVisualBuilderScript.REGION_ROOT_NAME)
	if terrain_root == null:
		return
	var midlod_root: Node = terrain_root.get_node_or_null(TerrainVisualBuilderScript.REGION_STREAM_MIDLOD_ROOT_NAME)
	if midlod_root == null:
		_errors.append("streamer missing TerrainMidLODTiles root")


func _require_streamed_foliage_root() -> void:
	var terrain_root: Node = _streamer.get_node_or_null(TerrainVisualBuilderScript.REGION_ROOT_NAME)
	if terrain_root == null:
		return
	var foliage_root: Node = terrain_root.get_node_or_null(TerrainVisualBuilderScript.REGION_STREAMED_FOLIAGE_ROOT_NAME)
	if foliage_root == null:
		_errors.append("streamer missing StreamedFoliageCells root")


func _require_pipeline_warmup() -> void:
	var terrain_root: Node = _streamer.get_node_or_null(TerrainVisualBuilderScript.REGION_ROOT_NAME)
	if terrain_root == null:
		return
	var warmup_root: Node = terrain_root.get_node_or_null(TerrainVisualBuilderScript.REGION_PIPELINE_WARMUP_ROOT_NAME)
	if warmup_root == null:
		_errors.append("streamer missing PipelineWarmup root")
		return
	var warmup_node: Node3D = warmup_root as Node3D
	if warmup_node == null:
		_errors.append("PipelineWarmup should be Node3D")
	elif not warmup_node.visible:
		_errors.append("PipelineWarmup should be visible for PSO warmup")
	if warmup_root.process_mode != Node.PROCESS_MODE_INHERIT:
		_errors.append("PipelineWarmup process_mode should be INHERIT")
	var terrain_material_count: int = _require_int_meta(
		warmup_root,
		TerrainVisualBuilderScript.PIPELINE_WARMUP_TERRAIN_MATERIAL_COUNT_META,
		"PipelineWarmup"
	)
	if terrain_material_count <= 0:
		_errors.append("PipelineWarmup terrain material count should be positive")
	var foliage_lod_count: int = _require_int_meta(
		warmup_root,
		TerrainVisualBuilderScript.PIPELINE_WARMUP_FOLIAGE_LOD_COUNT_META,
		"PipelineWarmup"
	)
	var expected_foliage_warmup_nodes: PackedStringArray = TerrainVisualBuilderScript.foliage_pipeline_warmup_node_names()
	if foliage_lod_count != expected_foliage_warmup_nodes.size():
		_errors.append("PipelineWarmup foliage warmup count expected " + str(expected_foliage_warmup_nodes.size()) + ", got " + str(foliage_lod_count))
	var terrain_warmup: MeshInstance3D = warmup_root.get_node_or_null(TerrainVisualBuilderScript.REGION_PIPELINE_WARMUP_TERRAIN_NAME) as MeshInstance3D
	if terrain_warmup == null:
		_errors.append("PipelineWarmup terrain child should be MeshInstance3D")
	elif terrain_warmup.mesh == null:
		_errors.append("PipelineWarmup terrain child missing mesh")
	elif terrain_warmup.mesh.get_surface_count() != terrain_material_count:
		_errors.append("PipelineWarmup terrain surface count expected " + str(terrain_material_count) + ", got " + str(terrain_warmup.mesh.get_surface_count()))
	for node_name in expected_foliage_warmup_nodes:
		_require_warmup_multimesh(
			warmup_root.get_node_or_null(node_name) as MultiMeshInstance3D,
			"PipelineWarmup " + node_name
		)
	var collision_count: int = _count_collision_objects(warmup_root)
	if collision_count > 0:
		_errors.append("PipelineWarmup should not contain collision objects: " + str(collision_count))


func _require_stream_hlod(expected_visible: bool) -> void:
	var terrain_root: Node = _streamer.get_node_or_null(TerrainVisualBuilderScript.REGION_ROOT_NAME)
	if terrain_root == null:
		return
	var hlod: MeshInstance3D = terrain_root.get_node_or_null(TerrainVisualBuilderScript.REGION_HLOD_NAME) as MeshInstance3D
	if hlod == null:
		_errors.append("streamer missing TerrainHLOD")
		return
	if hlod.mesh == null:
		_errors.append("streamed TerrainHLOD missing mesh")
	elif hlod.mesh.get_surface_count() <= 0:
		_errors.append("streamed TerrainHLOD mesh has no surfaces")
	elif _mesh_index_count(hlod.mesh) / 3 > EXPECTED_STREAM_HLOD_MAX_PRIMITIVES:
		_errors.append("streamed TerrainHLOD primitive count should stay <= " + str(EXPECTED_STREAM_HLOD_MAX_PRIMITIVES))
	if hlod.visible != expected_visible:
		_errors.append("streamed TerrainHLOD visible expected " + str(expected_visible) + ", got " + str(hlod.visible))
	if hlod.visibility_range_fade_mode != GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED:
		_errors.append("streamed TerrainHLOD visibility_range_fade_mode expected DISABLED")
	if absf(hlod.visibility_range_begin - TerrainVisualBuilderScript.REGION_STREAM_MIDLOD_RANGE_END_M) > FLOAT_EPSILON:
		_errors.append("streamed TerrainHLOD visibility_range_begin expected " + str(TerrainVisualBuilderScript.REGION_STREAM_MIDLOD_RANGE_END_M) + ", got " + str(hlod.visibility_range_begin))
	if absf(hlod.visibility_range_end) > FLOAT_EPSILON:
		_errors.append("streamed TerrainHLOD visibility_range_end should be open-ended")


func _require_int_meta(node: Node, meta_name: StringName, label: String) -> int:
	if not node.has_meta(meta_name):
		_errors.append(label + " missing metadata: " + String(meta_name))
		return 0
	return int(node.get_meta(meta_name))


func _require_warmup_multimesh(multimesh_instance: MultiMeshInstance3D, label: String) -> void:
	if multimesh_instance == null:
		_errors.append(label + " should be MultiMeshInstance3D")
		return
	if multimesh_instance.material_override == null:
		_errors.append(label + " missing material_override")
	elif _is_standard_material_warmup_label(label):
		if not (multimesh_instance.material_override is StandardMaterial3D):
			_errors.append(label + " should use StandardMaterial3D")
	elif not _is_grass_shader_material(multimesh_instance.material_override):
		_errors.append(label + " should use grass_billboard ShaderMaterial")
	if multimesh_instance.multimesh == null:
		_errors.append(label + " missing MultiMesh")
		return
	if multimesh_instance.multimesh.instance_count != 1:
		_errors.append(label + " instance_count expected 1, got " + str(multimesh_instance.multimesh.instance_count))
	if multimesh_instance.multimesh.mesh == null:
		_errors.append(label + " missing warmup mesh")


func _require_visual_tile(cell: Vector2i) -> MeshInstance3D:
	var node: Node = _streamer.call("visual_cell_node", cell) as Node
	var mesh_instance: MeshInstance3D = node as MeshInstance3D
	if mesh_instance == null:
		_errors.append("visual cell should be a MeshInstance3D: " + str(cell))
		return null
	var expected_name: String = TerrainVisualBuilderScript.region_detail_tile_node_name(REGION_ID, cell)
	if String(mesh_instance.name) != expected_name:
		_errors.append("visual cell name expected " + expected_name + ", got " + String(mesh_instance.name))
	if not mesh_instance.visibility_parent.is_empty():
		_errors.append("streamed visual cell should not use whole-region TerrainHLOD as visibility_parent: " + String(mesh_instance.name))
	var expected_origin: Vector3 = Vector3(
		(float(cell.x) + 0.5) * GameConfig.STREAM_TILE_SIZE_M,
		0.0,
		(float(cell.y) + 0.5) * GameConfig.STREAM_TILE_SIZE_M
	)
	if mesh_instance.position.distance_to(expected_origin) > FLOAT_EPSILON:
		_errors.append("streamed visual cell origin expected " + str(expected_origin) + ", got " + str(mesh_instance.position) + ": " + String(mesh_instance.name))
	if not mesh_instance.has_meta(TerrainVisualBuilderScript.VISIBILITY_RADIUS_META):
		_errors.append("streamed visual cell missing visibility radius metadata: " + String(mesh_instance.name))
	else:
		var visibility_radius: float = float(mesh_instance.get_meta(TerrainVisualBuilderScript.VISIBILITY_RADIUS_META))
		var expected_range_end: float = maxf(maxf(GameConfig.cam_far, GameConfig.vis_range_terrain) + visibility_radius, 0.0)
		if absf(mesh_instance.visibility_range_end - expected_range_end) > FLOAT_EPSILON:
			_errors.append("streamed visual cell visibility_range_end expected " + str(expected_range_end) + ", got " + str(mesh_instance.visibility_range_end) + ": " + String(mesh_instance.name))
	if mesh_instance.visibility_range_fade_mode != GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED:
		_errors.append("streamed visual cell visibility_range_fade_mode expected DISABLED, got " + str(mesh_instance.visibility_range_fade_mode) + ": " + String(mesh_instance.name))
	if mesh_instance.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_ON:
		_errors.append("streamed visual cell should cast shadows: " + String(mesh_instance.name))
	if not mesh_instance.has_meta(TerrainVisualBuilderScript.TILE_INDEX_META):
		_errors.append("visual cell missing tile index metadata: " + String(mesh_instance.name))
	elif Vector2i(mesh_instance.get_meta(TerrainVisualBuilderScript.TILE_INDEX_META)) != cell:
		_errors.append("visual cell metadata expected " + str(cell) + ", got " + str(mesh_instance.get_meta(TerrainVisualBuilderScript.TILE_INDEX_META)))
	if mesh_instance.mesh == null:
		_errors.append("visual cell missing mesh: " + String(mesh_instance.name))
	elif mesh_instance.mesh.get_surface_count() <= 0:
		_errors.append("visual cell mesh has no surfaces: " + String(mesh_instance.name))
	elif mesh_instance.mesh.get_surface_count() != 1:
		_errors.append("streamed visual cell terrain should collapse to one surface, got " + str(mesh_instance.mesh.get_surface_count()) + ": " + String(mesh_instance.name))
	else:
		var material: ShaderMaterial = mesh_instance.mesh.surface_get_material(0) as ShaderMaterial
		if material == null:
			_errors.append("streamed visual cell terrain should use the surface-index ShaderMaterial: " + String(mesh_instance.name))
		elif material.resource_name != TerrainVisualBuilderScript.TERRAIN_INDEX_MATERIAL_NAME:
			_errors.append("streamed visual cell material expected " + TerrainVisualBuilderScript.TERRAIN_INDEX_MATERIAL_NAME + ", got " + material.resource_name)
		else:
			var use_albedo_array: bool = bool(material.get_shader_parameter(TerrainVisualBuilderScript.USE_ALBEDO_ARRAY_UNIFORM))
			if not use_albedo_array:
				_errors.append("streamed visual cell material should enable the albedo Texture2DArray: " + String(mesh_instance.name))
			var albedo_array: Texture2DArray = material.get_shader_parameter(TerrainVisualBuilderScript.ALBEDO_ARRAY_UNIFORM) as Texture2DArray
			if albedo_array == null:
				_errors.append("streamed visual cell material missing albedo Texture2DArray: " + String(mesh_instance.name))
			var surface_texture: Texture2D = material.get_shader_parameter(TerrainVisualBuilderScript.SURFACE_ID_TEXTURE_UNIFORM) as Texture2D
			if surface_texture == null:
				_errors.append("streamed visual cell material missing surface ID texture: " + String(mesh_instance.name))
			var expected_control_origin: Vector2 = Vector2(float(cell.x) * GameConfig.STREAM_TILE_SIZE_M, float(cell.y) * GameConfig.STREAM_TILE_SIZE_M)
			var expected_control_size: Vector2 = Vector2(GameConfig.STREAM_TILE_SIZE_M, GameConfig.STREAM_TILE_SIZE_M)
			_require_instance_shader_vector2(mesh_instance, TerrainVisualBuilderScript.CONTROL_ORIGIN_XZ_UNIFORM, expected_control_origin, "streamed visual cell instance")
			_require_instance_shader_vector2(mesh_instance, TerrainVisualBuilderScript.CONTROL_SIZE_XZ_UNIFORM, expected_control_size, "streamed visual cell instance")
			_require_shader_color(material, TerrainVisualBuilderScript.ZION_SANDSTONE_COLOR_UNIFORM, "streamed visual cell material", String(mesh_instance.name))
			_require_shader_color(material, TerrainVisualBuilderScript.ZION_SAND_COLOR_UNIFORM, "streamed visual cell material", String(mesh_instance.name))
			_require_shader_float(material, TerrainVisualBuilderScript.ZION_STRATA_STRENGTH_UNIFORM, "streamed visual cell material", String(mesh_instance.name))
	var collision_count: int = _count_collision_objects(mesh_instance)
	if collision_count > 0:
		_errors.append("streamed visual cell should not create collision objects: " + String(mesh_instance.name))
	return mesh_instance


func _require_first_midlod_tile() -> void:
	var terrain_root: Node = _streamer.get_node_or_null(TerrainVisualBuilderScript.REGION_ROOT_NAME)
	if terrain_root == null:
		return
	var midlod_root: Node = terrain_root.get_node_or_null(TerrainVisualBuilderScript.REGION_STREAM_MIDLOD_ROOT_NAME)
	if midlod_root == null:
		return
	var midlod_tile: MeshInstance3D = null
	for child in midlod_root.get_children():
		var mesh_instance: MeshInstance3D = child as MeshInstance3D
		if mesh_instance != null:
			midlod_tile = mesh_instance
			break
	if midlod_tile == null:
		_errors.append("TerrainMidLODTiles should contain at least one MeshInstance3D")
		return
	_require_midlod_tile(midlod_tile)


func _require_midlod_tile(midlod_tile: MeshInstance3D) -> void:
	if not midlod_tile.has_meta(TerrainVisualBuilderScript.REGION_LOD_META):
		_errors.append(String(midlod_tile.name) + " missing mid-LOD metadata")
	elif String(midlod_tile.get_meta(TerrainVisualBuilderScript.REGION_LOD_META)) != "stream_midlod":
		_errors.append(String(midlod_tile.name) + " mid-LOD metadata expected stream_midlod, got " + String(midlod_tile.get_meta(TerrainVisualBuilderScript.REGION_LOD_META)))
	if not midlod_tile.has_meta(TerrainVisualBuilderScript.TILE_INDEX_META):
		_errors.append(String(midlod_tile.name) + " missing mid-LOD tile metadata")
	if absf(midlod_tile.visibility_range_begin - GameConfig.vis_range_terrain) > FLOAT_EPSILON:
		_errors.append(String(midlod_tile.name) + " mid-LOD visibility_range_begin expected " + str(GameConfig.vis_range_terrain) + ", got " + str(midlod_tile.visibility_range_begin))
	if midlod_tile.has_meta(TerrainVisualBuilderScript.VISIBILITY_RADIUS_META):
		var visibility_radius: float = float(midlod_tile.get_meta(TerrainVisualBuilderScript.VISIBILITY_RADIUS_META))
		var expected_range_end: float = TerrainVisualBuilderScript.REGION_STREAM_MIDLOD_RANGE_END_M + visibility_radius
		if absf(midlod_tile.visibility_range_end - expected_range_end) > FLOAT_EPSILON:
			_errors.append(String(midlod_tile.name) + " mid-LOD visibility_range_end expected " + str(expected_range_end) + ", got " + str(midlod_tile.visibility_range_end))
	else:
		_errors.append(String(midlod_tile.name) + " missing mid-LOD visibility radius metadata")
	if midlod_tile.visibility_range_fade_mode != GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED:
		_errors.append(String(midlod_tile.name) + " mid-LOD visibility_range_fade_mode expected DISABLED")
	if midlod_tile.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
		_errors.append(String(midlod_tile.name) + " mid-LOD should not cast shadows")
	if midlod_tile.mesh == null:
		_errors.append(String(midlod_tile.name) + " mid-LOD missing mesh")
	elif midlod_tile.mesh.get_surface_count() != 1:
		_errors.append(String(midlod_tile.name) + " mid-LOD should collapse to one surface, got " + str(midlod_tile.mesh.get_surface_count()))
	else:
		var primitive_count: int = _mesh_index_count(midlod_tile.mesh) / 3
		if primitive_count < EXPECTED_STREAM_MIDLOD_MIN_PRIMITIVES:
			_errors.append(String(midlod_tile.name) + " mid-LOD primitive count should exceed coarse HLOD density, got " + str(primitive_count))
		var material: ShaderMaterial = midlod_tile.mesh.surface_get_material(0) as ShaderMaterial
		if material == null:
			_errors.append(String(midlod_tile.name) + " mid-LOD should use surface-index ShaderMaterial")
		elif material.resource_name != TerrainVisualBuilderScript.TERRAIN_INDEX_MATERIAL_NAME:
			_errors.append(String(midlod_tile.name) + " mid-LOD material expected " + TerrainVisualBuilderScript.TERRAIN_INDEX_MATERIAL_NAME + ", got " + material.resource_name)
	if _count_collision_objects(midlod_tile) > 0:
		_errors.append(String(midlod_tile.name) + " mid-LOD should not create collision objects")


func _require_foliage_tile(cell: Vector2i) -> Node3D:
	var node: Node = _streamer.call("foliage_cell_node", cell) as Node
	var foliage_tile: Node3D = node as Node3D
	if foliage_tile == null:
		_errors.append("foliage cell should be a Node3D: " + str(cell))
		return null
	var multimesh_count: int = 0
	var foliage_instance_count: int = 0
	var lod_counts: Dictionary[String, int] = {}
	for child in foliage_tile.get_children():
		var multimesh_instance: MultiMeshInstance3D = child as MultiMeshInstance3D
		if multimesh_instance == null:
			continue
		multimesh_count += 1
		if not multimesh_instance.has_meta(TerrainVisualBuilderScript.REGION_LOD_META):
			_errors.append("foliage child missing LOD metadata: " + String(child.name))
			continue
		var region_lod: String = String(multimesh_instance.get_meta(TerrainVisualBuilderScript.REGION_LOD_META))
		lod_counts[region_lod] = int(lod_counts.get(region_lod, 0)) + 1
		if multimesh_instance.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			_errors.append("foliage child should not cast shadows: " + String(child.name))
		var material: Material = multimesh_instance.material_override
		if _is_source_material_foliage_child(multimesh_instance):
			# GLB foliage (cottonwood/willow/juniper/yucca) intentionally renders with NO
			# material_override at runtime: the StandardMaterial3D baked into the GLB mesh's
			# first surface is what draws. Verify that surface material is in place instead of
			# requiring an override.
			if material != null:
				_errors.append("GLB foliage child should render via mesh surface material, not override: " + String(child.name))
			elif multimesh_instance.multimesh == null or multimesh_instance.multimesh.mesh == null or multimesh_instance.multimesh.mesh.get_surface_count() <= 0:
				_errors.append("GLB foliage child missing mesh surface for material: " + String(child.name))
			elif not (multimesh_instance.multimesh.mesh.surface_get_material(0) is StandardMaterial3D):
				_errors.append("GLB foliage child mesh surface should use StandardMaterial3D: " + String(child.name))
		elif material == null:
			_errors.append("foliage child missing material_override: " + String(child.name))
		elif _is_boulder_foliage_child(multimesh_instance):
			if not (material is StandardMaterial3D):
				_errors.append("boulder foliage child should use StandardMaterial3D: " + String(child.name))
		elif not _is_grass_shader_material(material):
			_errors.append("foliage child should use grass_billboard ShaderMaterial: " + String(child.name))
		if not multimesh_instance.has_meta(TerrainVisualBuilderScript.VISIBILITY_RADIUS_META):
			_errors.append("foliage child missing visibility radius metadata: " + String(child.name))
		if multimesh_instance.multimesh == null:
			_errors.append("foliage child missing MultiMesh: " + String(child.name))
		else:
			var multimesh: MultiMesh = multimesh_instance.multimesh
			foliage_instance_count += multimesh.instance_count
			if not multimesh.use_custom_data:
				_errors.append("foliage child should enable MultiMesh custom data for wind: " + String(child.name))
			elif multimesh.custom_aabb.size == Vector3.ZERO:
				_errors.append("foliage child missing custom_aabb: " + String(child.name))
			elif multimesh.custom_aabb.size.x < GameConfig.STREAM_TILE_SIZE_M - FLOAT_EPSILON or multimesh.custom_aabb.size.z < GameConfig.STREAM_TILE_SIZE_M - FLOAT_EPSILON:
				_errors.append("foliage child custom_aabb should span the stream tile: " + String(child.name))
			elif multimesh.mesh == null:
				_errors.append("foliage child missing shared mesh: " + String(child.name))
	if multimesh_count < 2:
		_errors.append("foliage cell should contain MultiMeshInstance3D species/LOD children: " + str(cell) + ", got " + str(multimesh_count))
	if int(lod_counts.get("foliage_lod0", 0)) <= 0:
		_errors.append("foliage cell should contain foliage_lod0 children: " + str(cell))
	if int(lod_counts.get("foliage_lod1", 0)) <= 0:
		_errors.append("foliage cell should contain foliage_lod1 children: " + str(cell))
	if foliage_instance_count <= 0:
		_errors.append("foliage cell should contain nonzero MultiMesh instances: " + str(cell))
	return foliage_tile


func _exercise_midlod_commit_pressure() -> void:
	_configure_streamer_for_pressure_fixture()
	var pressure_cells: Array[Vector2i] = _pressure_active_cells()
	if pressure_cells.is_empty():
		_errors.append("mid-LOD pressure fixture found no active cells")
		return
	for cell in pressure_cells:
		EventBus.world_tile_activated.emit(cell)

	var initial_pending_midlod: int = int(_streamer.call("pending_midlod_commit_count"))
	var desired_midlod: int = int(_streamer.call("desired_midlod_cell_count"))
	if desired_midlod <= 0:
		_errors.append("mid-LOD pressure fixture expected desired mid-LOD cells")
		return
	if initial_pending_midlod <= 0:
		_errors.append("mid-LOD pressure fixture expected queued mid-LOD commits")
		return

	var pressure_frames: int = 0
	var completed_while_pressured: bool = false
	var max_frames: int = initial_pending_midlod + MIDLOD_DRAIN_SLACK_FRAMES
	for _frame_index in range(max_frames):
		var had_pressure: bool = _has_visual_or_foliage_commit_pressure()
		if had_pressure:
			pressure_frames += 1
		await get_tree().process_frame
		if int(_streamer.call("pending_midlod_commit_count")) == 0 and int(_streamer.call("ready_midlod_cell_count")) == 0:
			completed_while_pressured = _has_visual_or_foliage_commit_pressure()
			break

	if pressure_frames <= 0:
		_errors.append("mid-LOD pressure fixture never observed visual/foliage pressure")
	if not completed_while_pressured:
		_errors.append("mid-LOD commits did not finish while visual/foliage pressure was still active")
	if int(_streamer.call("pending_midlod_commit_count")) != 0:
		_errors.append("mid-LOD commit queue should drain under visual/foliage pressure, pending=" + str(_streamer.call("pending_midlod_commit_count")) + " initial=" + str(initial_pending_midlod))
	if int(_streamer.call("ready_midlod_cell_count")) != 0:
		_errors.append("ready mid-LOD cache should drain under visual/foliage pressure, ready=" + str(_streamer.call("ready_midlod_cell_count")))
	if int(_streamer.call("midlod_cell_count")) != desired_midlod:
		_errors.append("mid-LOD pressure fixture expected " + str(desired_midlod) + " committed cells, got " + str(_streamer.call("midlod_cell_count")))


func _exercise_midlod_failure_retry_after_free() -> void:
	_configure_streamer_for_pressure_fixture()
	EventBus.world_tile_activated.emit(PRESSURE_CENTER_CELL)
	await _wait_for_midlod_cell_count("mid-LOD retry seed", 1)
	var midlod_cells: Array[Vector2i] = _variant_to_cell_array(_streamer.call("active_midlod_cells"))
	if midlod_cells.is_empty():
		_errors.append("mid-LOD retry fixture could not find a committed mid-LOD cell")
		return
	var retry_cell: Vector2i = midlod_cells[0]
	_streamer.call("mark_midlod_load_failure_for_tests", retry_cell, "simulated transient mid-LOD failure")
	_streamer.call("_free_midlod_cell", retry_cell)
	_streamer.call("_refresh_midlod_streaming")
	if int(_streamer.call("pending_midlod_build_count")) <= 0 and not bool(_streamer.call("has_ready_midlod_cell", retry_cell)):
		_errors.append("mid-LOD retry fixture expected a new build after free/re-entry: " + str(retry_cell))
	await _wait_for_midlod_cell("mid-LOD retry after transient failure", retry_cell)


func _exercise_fullres_on_activation() -> void:
	# Regression: prefetch builds at step=5; activating that cell must discard the
	# coarse data and rebuild at REGION_DETAIL_FULLRES_SAMPLE_STEP (step=1) so the
	# visual mesh aligns with the physics heightmap the wheels touch.
	_streamer.call("reset_stream")
	_streamer.call("configure_region", REGION_ID)
	_streamer.call("set_worker_count_for_tests", 0)

	# Step 1: prefetch → step=5 build lands in the ready cache.
	EventBus.world_tile_prefetched.emit(FIRST_CELL)
	await _wait_for_ready_cell_count("fullres-on-activation: prefetch ready", 1)
	var prefetch_step: int = int(_streamer.call("ready_visual_cell_sample_step", FIRST_CELL))
	if prefetch_step != TerrainVisualBuilderScript.REGION_DETAIL_SAMPLE_STEP:
		_errors.append("fullres-on-activation: prefetch should produce step=" + str(TerrainVisualBuilderScript.REGION_DETAIL_SAMPLE_STEP) + " data, got step=" + str(prefetch_step))

	# Step 2: activate → fix should discard the coarse ready data and rebuild at fullres.
	# The synchronous build path (worker_count=0) may immediately place fullres data in
	# the ready cache during the activation handler; what matters is that the committed
	# tile is dense (step=1), not coarse (step=5).
	EventBus.world_tile_activated.emit(FIRST_CELL)
	# Wait for the fullres build to land and commit.
	await _wait_for_cell_count("fullres-on-activation: fullres tile committed", 1)

	# Step 3: the committed tile must be full-res.
	# For the spike_1km tile data, step=1 produces far more vertices than step=5.
	# step=5 tile: approx (tile_samples/5 + 1)^2 vertices — for a 512-sample tile ~103^2=10609.
	# step=1 tile: approx (tile_samples + 1)^2 vertices — for a 512-sample tile ~513^2=263169.
	# Even a conservative 64-sample tile gives step=1 → 65^2=4225 vs step=5 → 14^2=196.
	# We assert a safe minimum that only a step=1 build can satisfy.
	const FULLRES_VERTEX_MIN: int = 4000
	var fullres_tile: MeshInstance3D = _streamer.call("visual_cell_node", FIRST_CELL) as MeshInstance3D
	if fullres_tile == null or fullres_tile.mesh == null:
		_errors.append("fullres-on-activation: committed tile or mesh is null")
		return
	var fullres_vertex_count: int = _mesh_vertex_count(fullres_tile.mesh)
	if fullres_vertex_count < FULLRES_VERTEX_MIN:
		_errors.append("fullres-on-activation: expected fullres (>=" + str(FULLRES_VERTEX_MIN) + " verts), got " + str(fullres_vertex_count) + " — coarse step=5 data may have committed instead")


func _exercise_fullres_on_inflight_prefetch_activation() -> void:
	# Regression: prefetch queued a step=5 worker build, activation arrived before
	# that worker finished, and the activation handler returned early because a
	# build was already queued. The worker then committed coarse step=5 terrain
	# for an active cell and never upgraded it.
	_streamer.call("reset_stream")
	_streamer.call("configure_region", REGION_ID)
	_streamer.call("set_worker_count_for_tests", 1)

	var step5_data: Variant = TerrainVisualBuilderScript.build_region_visual_tile_data(
		REGION_ID,
		FIRST_CELL,
		TerrainVisualBuilderScript.REGION_DETAIL_SAMPLE_STEP
	)
	var step1_data: Variant = TerrainVisualBuilderScript.build_region_visual_tile_data(
		REGION_ID,
		FIRST_CELL,
		TerrainVisualBuilderScript.REGION_DETAIL_FULLRES_SAMPLE_STEP
	)
	if step5_data == null or not bool(step5_data.ok) or step5_data.mesh == null:
		_errors.append("inflight-prefetch activation: failed to build reference step=5 tile")
		return
	if step1_data == null or not bool(step1_data.ok) or step1_data.mesh == null:
		_errors.append("inflight-prefetch activation: failed to build reference step=1 tile")
		return
	var step5_vertex_count: int = _mesh_vertex_count(step5_data.mesh)
	var step1_vertex_count: int = _mesh_vertex_count(step1_data.mesh)
	if step1_vertex_count <= step5_vertex_count:
		_errors.append("inflight-prefetch activation: reference step=1 vertex count " + str(step1_vertex_count) + " should exceed step=5 " + str(step5_vertex_count))
		return

	EventBus.world_tile_prefetched.emit(FIRST_CELL)
	EventBus.world_tile_activated.emit(FIRST_CELL)
	await _wait_for_cell_count("inflight-prefetch activation: fullres tile committed", 1)
	await _wait_for_foliage_cell_count("inflight-prefetch activation: foliage committed", 1)

	var committed_tile: MeshInstance3D = _streamer.call("visual_cell_node", FIRST_CELL) as MeshInstance3D
	if committed_tile == null or committed_tile.mesh == null:
		_errors.append("inflight-prefetch activation: committed tile or mesh is null")
		return
	var committed_vertex_count: int = _mesh_vertex_count(committed_tile.mesh)
	if committed_vertex_count < step1_vertex_count:
		_errors.append("inflight-prefetch activation: committed vertex count " + str(committed_vertex_count) + " should be >= step=1 reference " + str(step1_vertex_count))
	if committed_vertex_count <= step5_vertex_count:
		_errors.append("inflight-prefetch activation: committed vertex count " + str(committed_vertex_count) + " should be > step=5 reference " + str(step5_vertex_count))


func _configure_streamer_for_pressure_fixture() -> void:
	_streamer.call("reset_stream")
	_streamer.call("configure_region", REGION_ID)
	_streamer.call("set_worker_count_for_tests", 0)


func _pressure_active_cells() -> Array[Vector2i]:
	var region_cells: Dictionary[Vector2i, bool] = _region_cell_lookup()
	var cells: Array[Vector2i] = []
	for y in range(PRESSURE_CENTER_CELL.y - PRESSURE_ACTIVE_RADIUS, PRESSURE_CENTER_CELL.y + PRESSURE_ACTIVE_RADIUS + 1):
		for x in range(PRESSURE_CENTER_CELL.x - PRESSURE_ACTIVE_RADIUS, PRESSURE_CENTER_CELL.x + PRESSURE_ACTIVE_RADIUS + 1):
			var cell: Vector2i = Vector2i(x, y)
			if region_cells.has(cell):
				cells.append(cell)
	_sort_cells(cells)
	return cells


func _region_cell_lookup() -> Dictionary[Vector2i, bool]:
	var lookup: Dictionary[Vector2i, bool] = {}
	var cells: Array[Vector2i] = TerrainVisualBuilderScript.region_tile_cells(REGION_ID)
	for cell in cells:
		lookup[cell] = true
	return lookup


func _has_visual_or_foliage_commit_pressure() -> bool:
	if int(_streamer.call("pending_visual_commit_count")) > 0:
		return true
	return int(_streamer.call("pending_foliage_subcommit_count")) > 0


func _is_grass_shader_material(material: Material) -> bool:
	var shader_material: ShaderMaterial = material as ShaderMaterial
	if shader_material == null or shader_material.shader == null:
		return false
	return shader_material.shader.resource_path == "res://systems/render/grass_billboard.gdshader"


func _is_standard_material_warmup_label(label: String) -> bool:
	# Boulder (procedural StandardMaterial3D) and the four GLB foliage species
	# (cottonwood/willow/juniper/yucca) warm a StandardMaterial3D; grass and
	# riparian_grass warm the grass_billboard ShaderMaterial and fall through.
	return label.find("_boulder") >= 0 or label.find("_cottonwood") >= 0 or label.find("_willow") >= 0 or label.find("_juniper") >= 0 or label.find("_yucca") >= 0


func _is_boulder_foliage_child(multimesh_instance: MultiMeshInstance3D) -> bool:
	if not multimesh_instance.has_meta(&"trailhead_foliage_species"):
		return false
	return StringName(String(multimesh_instance.get_meta(&"trailhead_foliage_species"))) == &"boulder"


func _is_source_material_foliage_child(multimesh_instance: MultiMeshInstance3D) -> bool:
	if not multimesh_instance.has_meta(&"trailhead_foliage_species"):
		return false
	var species: StringName = StringName(String(multimesh_instance.get_meta(&"trailhead_foliage_species")))
	return species == &"cottonwood" or species == &"willow" or species == &"juniper" or species == &"yucca"


func _require_shader_color(material: ShaderMaterial, parameter_name: StringName, label: String, node_name: String) -> void:
	var value: Variant = material.get_shader_parameter(parameter_name)
	if not (value is Color):
		_errors.append(label + " " + node_name + " missing Color shader parameter " + String(parameter_name))


func _require_shader_float(material: ShaderMaterial, parameter_name: StringName, label: String, node_name: String) -> void:
	var value: Variant = material.get_shader_parameter(parameter_name)
	if not (value is float):
		_errors.append(label + " " + node_name + " missing float shader parameter " + String(parameter_name))


func _require_shader_vector2(material: ShaderMaterial, parameter_name: StringName, expected: Vector2, label: String, node_name: String) -> void:
	var value: Variant = material.get_shader_parameter(parameter_name)
	if not (value is Vector2):
		_errors.append(label + " " + node_name + " missing Vector2 shader parameter " + String(parameter_name))
		return
	var observed: Vector2 = Vector2(value)
	if observed.distance_to(expected) > FLOAT_EPSILON:
		_errors.append(label + " " + node_name + " " + String(parameter_name) + " expected " + str(expected) + ", got " + str(observed))


func _require_instance_shader_vector2(mesh_instance: MeshInstance3D, parameter_name: StringName, expected: Vector2, label: String) -> void:
	var value: Variant = mesh_instance.get_instance_shader_parameter(parameter_name)
	if not (value is Vector2):
		_errors.append(label + " " + String(mesh_instance.name) + " missing Vector2 shader parameter " + String(parameter_name))
		return
	var observed: Vector2 = Vector2(value)
	if observed.distance_to(expected) > FLOAT_EPSILON:
		_errors.append(label + " " + String(mesh_instance.name) + " " + String(parameter_name) + " expected " + str(expected) + ", got " + str(observed))


func _require_no_visual_cell(cell: Vector2i) -> void:
	var has_cell: bool = bool(_streamer.call("has_visual_cell", cell))
	if has_cell:
		_errors.append("visual cell should have been evicted: " + str(cell))


func _require_no_foliage_cell(cell: Vector2i) -> void:
	var has_cell: bool = bool(_streamer.call("has_foliage_cell", cell))
	if has_cell:
		_errors.append("foliage cell should have been evicted: " + str(cell))


func _require_rebuilt_tile(expected_surface_count: int, expected_vertex_count: int, expected_index_count: int, expected_bounds: AABB, tile: MeshInstance3D) -> void:
	if tile == null or tile.mesh == null:
		return
	if tile.mesh.get_surface_count() != expected_surface_count:
		_errors.append("rebuilt tile surface count expected " + str(expected_surface_count) + ", got " + str(tile.mesh.get_surface_count()))
	var rebuilt_vertex_count: int = _mesh_vertex_count(tile.mesh)
	if rebuilt_vertex_count != expected_vertex_count:
		_errors.append("rebuilt tile vertex count expected " + str(expected_vertex_count) + ", got " + str(rebuilt_vertex_count))
	var rebuilt_index_count: int = _mesh_index_count(tile.mesh)
	if rebuilt_index_count != expected_index_count:
		_errors.append("rebuilt tile index count expected " + str(expected_index_count) + ", got " + str(rebuilt_index_count))
	var rebuilt_bounds: AABB = tile.mesh.get_aabb()
	if rebuilt_bounds.position.distance_to(expected_bounds.position) > FLOAT_EPSILON:
		_errors.append("rebuilt tile bounds position drifted")
	if rebuilt_bounds.size.distance_to(expected_bounds.size) > FLOAT_EPSILON:
		_errors.append("rebuilt tile bounds size drifted")


func _mesh_vertex_count(mesh: Mesh) -> int:
	var count: int = 0
	for surface_index in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
		count += vertices.size()
	return count


func _mesh_index_count(mesh: Mesh) -> int:
	var count: int = 0
	for surface_index in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(surface_index)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
		count += indices.size()
	return count


func _require_cached_materials_reused(expected_materials_by_name: Dictionary[String, StandardMaterial3D], tile: MeshInstance3D) -> void:
	if tile == null:
		return
	var observed_materials_by_name: Dictionary[String, StandardMaterial3D] = _surface_materials_by_name(tile)
	for material_name in expected_materials_by_name.keys():
		if not observed_materials_by_name.has(material_name):
			_errors.append("rebuilt tile missing material " + material_name)
			continue
		var expected_material: StandardMaterial3D = expected_materials_by_name[material_name]
		var observed_material: StandardMaterial3D = observed_materials_by_name[material_name]
		if observed_material != expected_material:
			_errors.append("rebuilt tile material " + material_name + " should reuse the cached StandardMaterial3D")


func _require_surface_index_material_reused_or_fallback(expected_material: ShaderMaterial, tile: MeshInstance3D) -> void:
	if expected_material == null or tile == null:
		return
	var observed_material: ShaderMaterial = _surface_index_material_for_tile(tile)
	if observed_material == null:
		_errors.append("tile missing surface-index ShaderMaterial")
	elif observed_material != expected_material and observed_material.shader != expected_material.shader:
		_errors.append("tile surface-index fallback material should reuse the cached Shader resource")


func _surface_index_material_for_tile(tile: MeshInstance3D) -> ShaderMaterial:
	if tile == null or tile.mesh == null or tile.mesh.get_surface_count() <= 0:
		return null
	return tile.mesh.surface_get_material(0) as ShaderMaterial


func _surface_materials_by_name(tile: MeshInstance3D) -> Dictionary[String, StandardMaterial3D]:
	var materials_by_name: Dictionary[String, StandardMaterial3D] = {}
	if tile.mesh == null:
		return materials_by_name
	for surface_index in range(tile.mesh.get_surface_count()):
		var material: StandardMaterial3D = tile.get_surface_override_material(surface_index) as StandardMaterial3D
		if material == null:
			continue
		materials_by_name[material.resource_name] = material
	return materials_by_name


func _require_cell_count(label: String, expected_count: int) -> void:
	var observed_count: int = int(_streamer.call("visual_cell_count"))
	if observed_count != expected_count:
		_errors.append(label + " expected " + str(expected_count) + " visual cells, got " + str(observed_count))


func _require_midlod_cell_count(label: String, expected_count: int) -> void:
	var observed_count: int = int(_streamer.call("midlod_cell_count"))
	if observed_count != expected_count:
		_errors.append(label + " expected " + str(expected_count) + " mid-LOD cells, got " + str(observed_count))


func _require_midlod_cell_count_at_least(label: String, expected_minimum: int) -> void:
	var observed_count: int = int(_streamer.call("midlod_cell_count"))
	if observed_count < expected_minimum:
		_errors.append(label + " expected at least " + str(expected_minimum) + " mid-LOD cells, got " + str(observed_count))


func _require_ready_cell_count(label: String, expected_count: int) -> void:
	var observed_count: int = int(_streamer.call("ready_visual_cell_count"))
	if observed_count != expected_count:
		_errors.append(label + " expected " + str(expected_count) + " ready visual cells, got " + str(observed_count))


func _require_foliage_cell_count(label: String, expected_count: int) -> void:
	var observed_count: int = int(_streamer.call("foliage_cell_count"))
	if observed_count != expected_count:
		_errors.append(label + " expected " + str(expected_count) + " foliage cells, got " + str(observed_count))


func _require_ready_foliage_cell_count(label: String, expected_count: int) -> void:
	var observed_count: int = int(_streamer.call("ready_foliage_cell_count"))
	if observed_count != expected_count:
		_errors.append(label + " expected " + str(expected_count) + " ready foliage cells, got " + str(observed_count))


func _require_pending_commit_count(label: String, expected_count: int) -> void:
	var observed_count: int = int(_streamer.call("pending_visual_commit_count"))
	if observed_count != expected_count:
		_errors.append(label + " expected " + str(expected_count) + " pending visual commits, got " + str(observed_count))


func _wait_for_cell_count(label: String, expected_count: int) -> void:
	for _frame_index in range(WAIT_FRAMES):
		if int(_streamer.call("visual_cell_count")) == expected_count:
			return
		await get_tree().process_frame
	_require_cell_count(label, expected_count)


func _wait_for_midlod_cell_count(label: String, expected_minimum: int) -> void:
	for _frame_index in range(WAIT_FRAMES):
		if int(_streamer.call("midlod_cell_count")) >= expected_minimum:
			return
		await get_tree().process_frame
	_require_midlod_cell_count_at_least(label, expected_minimum)


func _wait_for_midlod_cell(label: String, cell: Vector2i) -> void:
	for _frame_index in range(WAIT_FRAMES):
		if bool(_streamer.call("has_midlod_cell", cell)):
			return
		await get_tree().process_frame
	_errors.append(label + " expected committed mid-LOD cell " + str(cell))


func _wait_for_foliage_cell_count(label: String, expected_count: int) -> void:
	for _frame_index in range(WAIT_FRAMES):
		if int(_streamer.call("foliage_cell_count")) == expected_count:
			return
		await get_tree().process_frame
	_require_foliage_cell_count(label, expected_count)


func _wait_for_ready_cell_count(label: String, expected_count: int) -> void:
	for _frame_index in range(WAIT_FRAMES):
		if int(_streamer.call("ready_visual_cell_count")) == expected_count:
			return
		await get_tree().process_frame
	_require_ready_cell_count(label, expected_count)


func _wait_for_ready_foliage_cell_count(label: String, expected_count: int) -> void:
	for _frame_index in range(WAIT_FRAMES):
		if int(_streamer.call("ready_foliage_cell_count")) == expected_count:
			return
		await get_tree().process_frame
	_require_ready_foliage_cell_count(label, expected_count)


func _wait_for_pending_commit_count(label: String, expected_count: int) -> void:
	for _frame_index in range(WAIT_FRAMES):
		if int(_streamer.call("pending_visual_commit_count")) == expected_count:
			return
		await get_tree().process_frame
	_require_pending_commit_count(label, expected_count)


func _require_cells(label: String, expected_cells: Array[Vector2i]) -> void:
	var observed_cells: Array[Vector2i] = _variant_to_cell_array(_streamer.call("active_visual_cells"))
	var sorted_expected: Array[Vector2i] = _copy_cells(expected_cells)
	_sort_cells(sorted_expected)
	if not _cells_equal(observed_cells, sorted_expected):
		_errors.append(label + " expected " + _cells_to_string(sorted_expected) + ", got " + _cells_to_string(observed_cells))


func _variant_to_cell_array(value: Variant) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if not (value is Array):
		return cells
	for item in value:
		if item is Vector2i:
			cells.append(item)
	_sort_cells(cells)
	return cells


func _copy_cells(cells: Array[Vector2i]) -> Array[Vector2i]:
	var copy: Array[Vector2i] = []
	for cell in cells:
		copy.append(cell)
	return copy


func _cells_equal(left: Array[Vector2i], right: Array[Vector2i]) -> bool:
	if left.size() != right.size():
		return false
	for index in range(left.size()):
		if left[index] != right[index]:
			return false
	return true


func _sort_cells(cells: Array[Vector2i]) -> void:
	cells.sort_custom(Callable(self, "_cell_less"))


func _cell_less(left: Vector2i, right: Vector2i) -> bool:
	if left.x == right.x:
		return left.y < right.y
	return left.x < right.x


func _cells_to_string(cells: Array[Vector2i]) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for cell in cells:
		parts.append(str(cell))
	return "[" + ", ".join(parts) + "]"


func _count_collision_objects(parent: Node) -> int:
	var count: int = 0
	if parent is CollisionObject3D:
		count += 1
	for child in parent.get_children():
		count += _count_collision_objects(child)
	return count


func _finish() -> void:
	if _errors.is_empty():
		print("ok: render tile streamer lifecycle")
		get_tree().quit(0)
		return
	for error in _errors:
		push_error(error)
	get_tree().quit(1)
