extends Node

const CedarHollowHostScript: GDScript = preload("res://systems/render/cedar_hollow_host.gd")
const CedarRoute: Resource = preload("res://data/routes/cedar_hollow_zion_stream_route.tres")
const TerrainVisualBuilderScript: GDScript = preload("res://systems/render/terrain_visual_builder.gd")
const TerrainVisualStreamerScript: GDScript = preload("res://systems/render/terrain_visual_streamer.gd")
const WaterVisualBuilderScript: GDScript = preload("res://systems/render/water_visual_builder.gd")

const REGION_ID: String = "cedar_hollow_zion"
const STREAM_WAIT_FRAMES: int = 2400
const MIN_STREAMED_ROOT_GEOMETRY: int = 1
const MIN_STREAMED_CELL_COUNT: int = 1
# The Zion spawn activates the host's full TileStreamer active set, and a healthy
# foliage tile contributes multiple species/LOD MultiMeshes. Four is deliberately
# below the expected first-green population while still catching empty or single-LOD
# foliage regressions.
const MIN_FOLIAGE_MULTIMESHES: int = 4
const MIN_WATER_RIBBONS: int = 2

var _host: Node3D = null
var _streamer: Node3D = null
var _water_root: Node3D = null
var _spawn_id: StringName = &""
var _spawn_position: Vector3 = Vector3.ZERO
var _active_cells: Array[Vector2i] = []
var _errors: PackedStringArray = PackedStringArray()


func _ready() -> void:
	_spawn_id = CedarHollowHostScript.ZION_SPAWN_ID
	var spawn_transform: Transform3D = CedarRoute.call("spawn_transform", _spawn_id)
	_spawn_position = spawn_transform.origin
	_host = Node3D.new()
	_host.name = "FidelityStructureHost"
	add_child(_host)
	_streamer = TerrainVisualStreamerScript.new() as Node3D
	if _streamer != null:
		_streamer.name = "TerrainVisualStreamer"
		_host.add_child(_streamer)
	_water_root = WaterVisualBuilderScript.build_zion_virgin_river(_host)
	call_deferred("_inspect")


func _inspect() -> void:
	if _host == null:
		_errors.append("fidelity fixture failed to create minimal host")
		_finish()
		return
	if _streamer == null:
		_errors.append("fidelity fixture failed to instantiate TerrainVisualStreamer")
		_finish()
		return

	TerrainVisualBuilderScript.clear_region_tile_data_cache_for_tests()
	TerrainVisualBuilderScript.clear_surface_index_tile_material_cache_for_tests()
	TerrainVisualBuilderScript.prewarm_surface_index_pipeline()
	_streamer.call("set_worker_count_for_tests", 0)
	_streamer.call("configure_region", REGION_ID)
	_active_cells = _expected_spawn_active_cells()
	if _active_cells.is_empty():
		_finish()
		return
	for cell in _active_cells:
		EventBus.world_tile_activated.emit(cell)

	await _wait_for_streaming_ready()
	_require_no_stream_load_failures()
	_require_streamer_counts()
	_require_structural_roots()
	_require_water_ribbons()
	_finish()


func _expected_spawn_active_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var tile_streamer: Node = get_node_or_null("/root/TileStreamer")
	if tile_streamer == null:
		_errors.append("fidelity fixture requires TileStreamer autoload to resolve Zion spawn cells")
		return cells
	if not tile_streamer.has_method("expected_active_cells_for_position"):
		_errors.append("TileStreamer missing expected_active_cells_for_position for Zion spawn cells")
		return cells
	var value: Variant = tile_streamer.call("expected_active_cells_for_position", _spawn_position)
	if not (value is Array):
		_errors.append("TileStreamer expected_active_cells_for_position returned non-Array: " + str(value))
		return cells
	for item in value:
		if item is Vector2i:
			cells.append(item)
	if cells.is_empty():
		_errors.append("Zion spawn " + String(_spawn_id) + " resolved zero active cells at " + str(_spawn_position))
	return cells


func _wait_for_streaming_ready() -> void:
	for _frame_index in range(STREAM_WAIT_FRAMES):
		await get_tree().physics_frame
		await get_tree().process_frame
		if _streaming_ready():
			print(
				"ok: streaming readiness gate met for "
				+ String(_spawn_id)
				+ " within "
				+ str(STREAM_WAIT_FRAMES)
				+ " frames (visual="
				+ str(_visual_cell_count())
				+ " foliage="
				+ str(_foliage_cell_count())
				+ " midlod="
				+ str(_midlod_cell_count())
				+ ")"
			)
			return
	_errors.append(
		"streaming readiness timed out after "
		+ str(STREAM_WAIT_FRAMES)
		+ " frames; expected visual>0 foliage>0 midlod>0 pending_midlod_commit=0 pending_midlod_build=0, got visual="
		+ str(_visual_cell_count())
		+ " foliage="
		+ str(_foliage_cell_count())
		+ " midlod="
		+ str(_midlod_cell_count())
		+ " pending_midlod_commit="
		+ str(_pending_midlod_commit_count())
		+ " pending_midlod_build="
		+ str(_pending_midlod_build_count())
	)


func _streaming_ready() -> bool:
	return _visual_cell_count() > 0 \
		and _foliage_cell_count() > 0 \
		and _midlod_cell_count() > 0 \
		and _pending_midlod_commit_count() == 0 \
		and _pending_midlod_build_count() == 0


func _require_no_stream_load_failures() -> void:
	var failures: Dictionary = _streamer.call("load_failures")
	if not failures.is_empty():
		_errors.append("TerrainVisualStreamer load failures after Zion spawn stream: " + str(failures))
		return
	print("ok: TerrainVisualStreamer reported no load failures")


func _require_streamer_counts() -> void:
	var visual_count: int = _visual_cell_count()
	var foliage_count: int = _foliage_cell_count()
	var midlod_count: int = _midlod_cell_count()
	if visual_count < MIN_STREAMED_CELL_COUNT:
		_errors.append("visual_cell_count expected >= " + str(MIN_STREAMED_CELL_COUNT) + ", got " + str(visual_count))
	else:
		print("ok: visual_cell_count >= " + str(MIN_STREAMED_CELL_COUNT) + " (got " + str(visual_count) + ")")
	if foliage_count < MIN_STREAMED_CELL_COUNT:
		_errors.append("foliage_cell_count expected >= " + str(MIN_STREAMED_CELL_COUNT) + ", got " + str(foliage_count))
	else:
		print("ok: foliage_cell_count >= " + str(MIN_STREAMED_CELL_COUNT) + " (got " + str(foliage_count) + ")")
	if midlod_count < MIN_STREAMED_CELL_COUNT:
		_errors.append("midlod_cell_count expected >= " + str(MIN_STREAMED_CELL_COUNT) + ", got " + str(midlod_count))
	else:
		print("ok: midlod_cell_count >= " + str(MIN_STREAMED_CELL_COUNT) + " (got " + str(midlod_count) + ")")


func _require_structural_roots() -> void:
	var terrain_root: Node = _require_child(_streamer, TerrainVisualBuilderScript.REGION_ROOT_NAME, "streamer")
	if terrain_root == null:
		return
	var detail_root: Node = _require_child(terrain_root, TerrainVisualBuilderScript.REGION_DETAIL_ROOT_NAME, TerrainVisualBuilderScript.REGION_ROOT_NAME)
	var midlod_root: Node = _require_child(terrain_root, TerrainVisualBuilderScript.REGION_STREAM_MIDLOD_ROOT_NAME, TerrainVisualBuilderScript.REGION_ROOT_NAME)
	var hlod_root: Node = _require_child(terrain_root, TerrainVisualBuilderScript.REGION_HLOD_NAME, TerrainVisualBuilderScript.REGION_ROOT_NAME)
	var foliage_root: Node = _streamed_foliage_root(terrain_root)

	_require_geometry_floor(detail_root, TerrainVisualBuilderScript.REGION_DETAIL_ROOT_NAME, false)
	_require_geometry_floor(midlod_root, TerrainVisualBuilderScript.REGION_STREAM_MIDLOD_ROOT_NAME, false)
	_require_hlod_root(hlod_root)
	_require_foliage_root(foliage_root)


func _require_child(parent: Node, child_name: String, parent_label: String) -> Node:
	if parent == null:
		_errors.append("cannot resolve " + child_name + " under null " + parent_label)
		return null
	var child: Node = parent.get_node_or_null(child_name)
	if child == null:
		_errors.append(parent_label + " missing child named " + child_name)
	return child


func _streamed_foliage_root(terrain_root: Node) -> Node:
	var foliage_root: Node = terrain_root.get_node_or_null(TerrainVisualBuilderScript.REGION_STREAMED_FOLIAGE_ROOT_NAME)
	if foliage_root != null:
		return foliage_root
	foliage_root = terrain_root.get_node_or_null(TerrainVisualBuilderScript.REGION_FOLIAGE_ROOT_NAME)
	if foliage_root == null:
		_errors.append(
			TerrainVisualBuilderScript.REGION_ROOT_NAME
			+ " missing foliage root named "
			+ TerrainVisualBuilderScript.REGION_STREAMED_FOLIAGE_ROOT_NAME
			+ " or "
			+ TerrainVisualBuilderScript.REGION_FOLIAGE_ROOT_NAME
		)
	return foliage_root


func _require_geometry_floor(root: Node, label: String, include_root: bool) -> void:
	if root == null:
		return
	var geometry_count: int = _count_geometry_with_content(root, include_root)
	if geometry_count < MIN_STREAMED_ROOT_GEOMETRY:
		_errors.append(label + " expected >= " + str(MIN_STREAMED_ROOT_GEOMETRY) + " GeometryInstance3D with mesh content, got " + str(geometry_count))
		return
	print("ok: " + label + " has streamed geometry descendants (got " + str(geometry_count) + ")")


func _require_hlod_root(hlod_root: Node) -> void:
	if hlod_root == null:
		return
	var committed_chunks: int = int(_streamer.call("stream_hlod_committed_chunk_count"))
	var geometry_count: int = _count_geometry_with_content(hlod_root, true)
	var named_chunk_count: int = _count_hlod_named_nodes(hlod_root)
	if committed_chunks < MIN_STREAMED_ROOT_GEOMETRY:
		_errors.append("stream-HLOD committed chunk count expected >= " + str(MIN_STREAMED_ROOT_GEOMETRY) + ", got " + str(committed_chunks))
	if geometry_count < MIN_STREAMED_ROOT_GEOMETRY:
		_errors.append(TerrainVisualBuilderScript.REGION_HLOD_NAME + " expected >= " + str(MIN_STREAMED_ROOT_GEOMETRY) + " GeometryInstance3D with mesh content, got " + str(geometry_count))
	if named_chunk_count < MIN_STREAMED_ROOT_GEOMETRY:
		_errors.append(
			TerrainVisualBuilderScript.REGION_HLOD_NAME
			+ " expected canonical HLOD node names using "
			+ TerrainVisualBuilderScript.REGION_HLOD_TILE_NAME_PREFIX
			+ ", got "
			+ str(named_chunk_count)
		)
	if committed_chunks >= MIN_STREAMED_ROOT_GEOMETRY and geometry_count >= MIN_STREAMED_ROOT_GEOMETRY and named_chunk_count >= MIN_STREAMED_ROOT_GEOMETRY:
		print(
			"ok: "
			+ TerrainVisualBuilderScript.REGION_HLOD_NAME
			+ " has committed stream-HLOD geometry (chunks="
			+ str(committed_chunks)
			+ " geometry="
			+ str(geometry_count)
			+ ")"
		)


func _require_foliage_root(foliage_root: Node) -> void:
	if foliage_root == null:
		return
	_require_geometry_floor(foliage_root, String(foliage_root.name), false)
	var multimesh_count: int = _count_foliage_multimeshes(foliage_root)
	var instance_count: int = _count_foliage_instances(foliage_root)
	if multimesh_count < MIN_FOLIAGE_MULTIMESHES:
		_errors.append(
			"foliage MultiMeshInstance3D count expected >= "
			+ str(MIN_FOLIAGE_MULTIMESHES)
			+ ", got "
			+ str(multimesh_count)
			+ " (instances="
			+ str(instance_count)
			+ ")"
		)
		return
	print(
		"ok: foliage MultiMeshInstance3D count >= "
		+ str(MIN_FOLIAGE_MULTIMESHES)
		+ " (got "
		+ str(multimesh_count)
		+ ", instances="
		+ str(instance_count)
		+ ")"
	)


func _require_water_ribbons() -> void:
	if _water_root == null:
		_errors.append("Zion water is expected in the minimal render host, but WaterVisualBuilder returned null")
		return
	var water_count: int = _count_water_ribbons(_water_root)
	if water_count < MIN_WATER_RIBBONS:
		_errors.append("Zion water ribbons expected >= " + str(MIN_WATER_RIBBONS) + ", got " + str(water_count))
		return
	print("ok: Zion water ribbon nodes exist (got " + str(water_count) + ")")


func _count_geometry_with_content(root: Node, include_root: bool) -> int:
	var count: int = 0
	if include_root and _is_geometry_with_content(root):
		count += 1
	for child in root.get_children():
		if _is_geometry_with_content(child):
			count += 1
		count += _count_geometry_with_content(child, false)
	return count


func _is_geometry_with_content(node: Node) -> bool:
	var multimesh_instance: MultiMeshInstance3D = node as MultiMeshInstance3D
	if multimesh_instance != null:
		return multimesh_instance.multimesh != null \
			and multimesh_instance.multimesh.mesh != null \
			and multimesh_instance.multimesh.instance_count > 0
	var mesh_instance: MeshInstance3D = node as MeshInstance3D
	if mesh_instance != null:
		return mesh_instance.mesh != null and mesh_instance.mesh.get_surface_count() > 0
	return false


func _count_hlod_named_nodes(root: Node) -> int:
	var count: int = 0
	var node_name: String = String(root.name)
	if node_name == TerrainVisualBuilderScript.REGION_HLOD_NAME or node_name.begins_with(TerrainVisualBuilderScript.REGION_HLOD_TILE_NAME_PREFIX):
		count += 1
	for child in root.get_children():
		count += _count_hlod_named_nodes(child)
	return count


func _count_foliage_multimeshes(root: Node) -> int:
	var count: int = 0
	var multimesh_instance: MultiMeshInstance3D = root as MultiMeshInstance3D
	if multimesh_instance != null and _is_geometry_with_content(multimesh_instance):
		count += 1
	for child in root.get_children():
		count += _count_foliage_multimeshes(child)
	return count


func _count_foliage_instances(root: Node) -> int:
	var count: int = 0
	var multimesh_instance: MultiMeshInstance3D = root as MultiMeshInstance3D
	if multimesh_instance != null and multimesh_instance.multimesh != null:
		count += multimesh_instance.multimesh.instance_count
	for child in root.get_children():
		count += _count_foliage_instances(child)
	return count


func _count_water_ribbons(root: Node) -> int:
	var count: int = 0
	var mesh_instance: MeshInstance3D = root as MeshInstance3D
	if mesh_instance != null:
		var node_name: String = String(mesh_instance.name)
		if (node_name.findn("river") >= 0 or node_name.findn("water") >= 0) \
				and mesh_instance.is_in_group(WaterVisualBuilderScript.WATER_SURFACE_GROUP) \
				and mesh_instance.mesh != null \
				and mesh_instance.mesh.get_surface_count() > 0:
			count += 1
	for child in root.get_children():
		count += _count_water_ribbons(child)
	return count


func _visual_cell_count() -> int:
	return int(_streamer.call("visual_cell_count")) if _streamer != null else 0


func _foliage_cell_count() -> int:
	return int(_streamer.call("foliage_cell_count")) if _streamer != null else 0


func _midlod_cell_count() -> int:
	return int(_streamer.call("midlod_cell_count")) if _streamer != null else 0


func _pending_midlod_commit_count() -> int:
	return int(_streamer.call("pending_midlod_commit_count")) if _streamer != null else -1


func _pending_midlod_build_count() -> int:
	return int(_streamer.call("pending_midlod_build_count")) if _streamer != null else -1


func _finish() -> void:
	if _errors.size() > 0:
		for error in _errors:
			push_error(error)
		_cleanup()
		get_tree().quit(1)
		return
	print("ok: structural fidelity fixture completed for Zion spawn " + String(_spawn_id))
	_cleanup()
	get_tree().quit(0)


func _cleanup() -> void:
	if _streamer != null:
		_streamer.call("reset_stream")
	if _host != null:
		_host.queue_free()
		_host = null
	_streamer = null
	_water_root = null
