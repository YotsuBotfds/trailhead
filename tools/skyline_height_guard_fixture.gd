extends Node

const TerrainVisualStreamerScript: GDScript = preload("res://systems/render/terrain_visual_streamer.gd")
const TerrainVisualBuilderScript: GDScript = preload("res://systems/render/terrain_visual_builder.gd")
const REGION_ID: String = "cedar_hollow_zion"
const MANIFEST_PATH: String = "res://data/regions/cedar_hollow_zion/collision_tiles_manifest.json"
const ACTIVE_CELLS: Array[Vector2i] = [
	Vector2i(8, 10),
	Vector2i(9, 10),
	Vector2i(10, 10),
	Vector2i(8, 11),
	Vector2i(9, 11),
	Vector2i(10, 11),
	Vector2i(8, 12),
	Vector2i(9, 12),
	Vector2i(10, 12),
]
const WAIT_FRAMES: int = 360
const FLOAT_EPSILON: float = 0.001
const HEIGHT_MARGIN_M: float = 0.30
const MAX_TRIANGLE_EDGE_SLOPE: float = 7.5
const MIN_TRIANGLE_EDGE_DELTA_M: float = 180.0

var _streamer: Node3D = null
var _height_ranges: Dictionary[Vector2i, Vector2] = {}
var _errors: PackedStringArray = PackedStringArray()


func _ready() -> void:
	_streamer = TerrainVisualStreamerScript.new() as Node3D
	_streamer.name = "SkylineZionStreamer"
	add_child(_streamer)
	call_deferred("_inspect")


func _inspect() -> void:
	_load_height_ranges()
	if _height_ranges.is_empty():
		_errors.append("failed to load Zion manifest height_ranges")
		_finish()
		return
	if _streamer == null:
		_errors.append("failed to instantiate terrain visual streamer")
		_finish()
		return

	_streamer.call("configure_region", REGION_ID)
	_streamer.call("set_worker_count_for_tests", 0)
	for cell in ACTIVE_CELLS:
		EventBus.world_tile_activated.emit(cell)
	await _wait_for_streamed_cells()

	var terrain_root: Node = _streamer.get_node_or_null(TerrainVisualBuilderScript.REGION_ROOT_NAME)
	if terrain_root == null:
		_errors.append("streamer missing TerrainVisuals root")
		_finish()
		return
	_inspect_terrain_vertices(terrain_root)
	_inspect_foliage_instances(terrain_root)
	_finish()


func _load_height_ranges() -> void:
	var manifest_file: FileAccess = FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if manifest_file == null:
		_errors.append("failed to open manifest: " + MANIFEST_PATH)
		return
	var parsed: Variant = JSON.parse_string(manifest_file.get_as_text())
	if not (parsed is Dictionary):
		_errors.append("manifest did not parse as Dictionary: " + MANIFEST_PATH)
		return
	var manifest: Dictionary = parsed
	var ranges_variant: Variant = manifest.get("height_ranges", {})
	if not (ranges_variant is Dictionary):
		_errors.append("manifest missing height_ranges")
		return
	var ranges: Dictionary = ranges_variant
	for key in ranges.keys():
		var key_string: String = String(key)
		var parts: PackedStringArray = key_string.split("_")
		if parts.size() != 2:
			continue
		var range_variant: Variant = ranges[key]
		if not (range_variant is Array):
			continue
		var range_array: Array = range_variant
		if range_array.size() < 2:
			continue
		var cell: Vector2i = Vector2i(int(parts[0]), int(parts[1]))
		_height_ranges[cell] = Vector2(float(range_array[0]), float(range_array[1]))


func _wait_for_streamed_cells() -> void:
	for _frame in range(WAIT_FRAMES):
		await get_tree().process_frame
		var visual_count: int = int(_streamer.call("visual_cell_count"))
		var foliage_count: int = int(_streamer.call("foliage_cell_count"))
		if visual_count >= ACTIVE_CELLS.size() and foliage_count >= ACTIVE_CELLS.size():
			return
	_errors.append(
		"timed out waiting for Zion streamed cells: visual="
		+ str(int(_streamer.call("visual_cell_count")))
		+ " foliage="
		+ str(int(_streamer.call("foliage_cell_count")))
	)


func _inspect_terrain_vertices(root: Node) -> void:
	var mesh_instance: MeshInstance3D = root as MeshInstance3D
	if mesh_instance != null and mesh_instance.mesh != null and mesh_instance.has_meta(TerrainVisualBuilderScript.TILE_INDEX_META):
		var cell: Vector2i = _tile_cell_meta(mesh_instance)
		_inspect_mesh_vertices(mesh_instance, cell)
	for child in root.get_children():
		_inspect_terrain_vertices(child)


func _inspect_mesh_vertices(mesh_instance: MeshInstance3D, cell: Vector2i) -> void:
	if not _height_ranges.has(cell):
		# Pipeline-warmup / non-region nodes use a sentinel cell with no manifest range; skip.
		return
	var height_range: Vector2 = _height_ranges[cell]
	var mesh: Mesh = mesh_instance.mesh
	for surface_index in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for vertex_index in range(vertices.size()):
			var world_vertex: Vector3 = mesh_instance.global_transform * vertices[vertex_index]
			_require_y_in_range(world_vertex.y, height_range, "terrain vertex " + String(mesh_instance.name) + " surface " + str(surface_index) + " vertex " + str(vertex_index))
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for index_offset in range(0, indices.size(), 3):
			if index_offset + 2 >= indices.size():
				continue
			var a_index: int = indices[index_offset]
			var b_index: int = indices[index_offset + 1]
			var c_index: int = indices[index_offset + 2]
			if a_index < 0 or b_index < 0 or c_index < 0 or a_index >= vertices.size() or b_index >= vertices.size() or c_index >= vertices.size():
				_errors.append("terrain triangle index outside vertex array: " + String(mesh_instance.name) + " surface " + str(surface_index) + " offset " + str(index_offset))
				continue
			var a: Vector3 = mesh_instance.global_transform * vertices[a_index]
			var b: Vector3 = mesh_instance.global_transform * vertices[b_index]
			var c: Vector3 = mesh_instance.global_transform * vertices[c_index]
			_require_edge_delta(a, b, "terrain triangle edge AB " + String(mesh_instance.name) + " surface " + str(surface_index) + " offset " + str(index_offset))
			_require_edge_delta(b, c, "terrain triangle edge BC " + String(mesh_instance.name) + " surface " + str(surface_index) + " offset " + str(index_offset))
			_require_edge_delta(c, a, "terrain triangle edge CA " + String(mesh_instance.name) + " surface " + str(surface_index) + " offset " + str(index_offset))


func _inspect_foliage_instances(root: Node) -> void:
	var multimesh_instance: MultiMeshInstance3D = root as MultiMeshInstance3D
	if multimesh_instance != null and multimesh_instance.multimesh != null:
		var cell: Vector2i = _tile_cell_for_node(multimesh_instance)
		_inspect_multimesh_instances(multimesh_instance, cell)
	for child in root.get_children():
		_inspect_foliage_instances(child)


func _inspect_multimesh_instances(multimesh_instance: MultiMeshInstance3D, cell: Vector2i) -> void:
	if not _height_ranges.has(cell):
		# Pipeline-warmup / non-region foliage nodes use a sentinel cell with no manifest range; skip.
		return
	var height_range: Vector2 = _height_ranges[cell]
	var multimesh: MultiMesh = multimesh_instance.multimesh
	var custom_aabb: AABB = multimesh.custom_aabb
	var label: String = "foliage multimesh " + String(multimesh_instance.name)
	_require_foliage_custom_aabb(custom_aabb, multimesh_instance.global_transform, height_range, label)


func _tile_cell_for_node(node: Node) -> Vector2i:
	var current: Node = node
	while current != null:
		if current.has_meta(TerrainVisualBuilderScript.TILE_INDEX_META):
			return _tile_cell_meta(current)
		current = current.get_parent()
	return Vector2i(-999999, -999999)


func _tile_cell_meta(node: Node) -> Vector2i:
	var meta: Variant = node.get_meta(TerrainVisualBuilderScript.TILE_INDEX_META)
	if meta is Vector2i:
		return meta
	return Vector2i(-999999, -999999)


func _require_y_in_range(y: float, height_range: Vector2, label: String) -> void:
	if not is_finite(y):
		_errors.append(label + " Y not finite: " + str(y))
		return
	if y < height_range.x - HEIGHT_MARGIN_M or y > height_range.y + HEIGHT_MARGIN_M:
		_errors.append(label + " Y outside manifest range " + str(height_range) + " margin " + str(HEIGHT_MARGIN_M) + ": " + str(y))


func _require_edge_delta(a: Vector3, b: Vector3, label: String) -> void:
	var horizontal_distance: float = Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))
	var max_allowed_delta: float = maxf(horizontal_distance * MAX_TRIANGLE_EDGE_SLOPE, MIN_TRIANGLE_EDGE_DELTA_M)
	var y_delta: float = absf(a.y - b.y)
	if y_delta > max_allowed_delta:
		_errors.append(label + " exceeds relative seam delta: dy=" + str(y_delta) + " allowed=" + str(max_allowed_delta) + " a=" + str(a) + " b=" + str(b))


func _require_foliage_custom_aabb(custom_aabb: AABB, world_transform: Transform3D, height_range: Vector2, label: String) -> void:
	if custom_aabb.size == Vector3.ZERO:
		_errors.append(label + " missing custom_aabb")
		return
	if not _aabb_is_finite(custom_aabb):
		_errors.append(label + " custom_aabb is not finite: " + str(custom_aabb))
		return
	if custom_aabb.size.x <= 0.0 or custom_aabb.size.y <= 0.0 or custom_aabb.size.z <= 0.0:
		_errors.append(label + " custom_aabb should have positive size: " + str(custom_aabb))
		return
	var max_horizontal_size: float = (
		TerrainVisualBuilderScript.REGION_FOLIAGE_CELL_SIZE_M
		+ 2.0 * (TerrainVisualBuilderScript._foliage_max_lod0_horizontal_radius() + TerrainVisualBuilderScript.REGION_FOLIAGE_CULL_MARGIN)
	)
	if custom_aabb.size.x > max_horizontal_size + FLOAT_EPSILON or custom_aabb.size.z > max_horizontal_size + FLOAT_EPSILON:
		_errors.append(label + " custom_aabb horizontal size exceeds tight cell bound " + str(max_horizontal_size) + ": " + str(custom_aabb))
	var world_y_range: Vector2 = _aabb_world_y_range(custom_aabb, world_transform)
	if not is_finite(world_y_range.x) or not is_finite(world_y_range.y):
		_errors.append(label + " custom_aabb world-Y span is not finite: " + str(world_y_range))
		return
	var min_allowed_y: float = height_range.x - HEIGHT_MARGIN_M
	var max_allowed_y: float = (
		height_range.y
		+ TerrainVisualBuilderScript._foliage_max_lod0_height()
		+ TerrainVisualBuilderScript.REGION_FOLIAGE_CULL_MARGIN * 2.0
		+ HEIGHT_MARGIN_M
	)
	if world_y_range.x < min_allowed_y or world_y_range.x > max_allowed_y or world_y_range.y < min_allowed_y or world_y_range.y > max_allowed_y:
		_errors.append(label + " custom_aabb world-Y span outside manifest range " + str(height_range) + " plus foliage height/margin: " + str(world_y_range))


func _aabb_world_y_range(aabb: AABB, world_transform: Transform3D) -> Vector2:
	var min_y: float = INF
	var max_y: float = -INF
	for x_index in range(2):
		for y_index in range(2):
			for z_index in range(2):
				var corner: Vector3 = aabb.position + Vector3(
					aabb.size.x if x_index == 1 else 0.0,
					aabb.size.y if y_index == 1 else 0.0,
					aabb.size.z if z_index == 1 else 0.0
				)
				var world_corner: Vector3 = world_transform * corner
				min_y = minf(min_y, world_corner.y)
				max_y = maxf(max_y, world_corner.y)
	return Vector2(min_y, max_y)


func _aabb_is_finite(aabb: AABB) -> bool:
	return _vector3_is_finite(aabb.position) and _vector3_is_finite(aabb.size)


func _vector3_is_finite(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)


func _finish() -> void:
	if _errors.is_empty():
		print("ok: skyline Zion streamed geometry bounds")
		get_tree().quit(0)
		return
	for error in _errors:
		push_error(error)
	get_tree().quit(1)
