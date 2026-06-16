extends Node

const TerrainVisualStreamerScript: GDScript = preload("res://systems/render/terrain_visual_streamer.gd")
const TerrainVisualBuilderScript: GDScript = preload("res://systems/render/terrain_visual_builder.gd")
const REGION_ID: String = "spike_1km"
const FIRST_CELL: Vector2i = Vector2i(2, 2)
const SECOND_CELL: Vector2i = Vector2i(2, 3)
const FLOAT_EPSILON: float = 0.001

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
	_require_cell_count("configured empty", 0)
	_require_cells("configured active cells", [])
	_require_detail_root()

	EventBus.world_tile_activated.emit(FIRST_CELL)
	_require_cell_count("first activation", 1)
	_require_cells("first activation cells", [FIRST_CELL])
	var first_tile: MeshInstance3D = _require_visual_tile(FIRST_CELL)
	var first_surface_count: int = 0
	var first_bounds: AABB = AABB()
	if first_tile != null and first_tile.mesh != null:
		first_surface_count = first_tile.mesh.get_surface_count()
		first_bounds = first_tile.mesh.get_aabb()

	EventBus.world_tile_activated.emit(FIRST_CELL)
	_require_cell_count("duplicate activation", 1)
	_require_cells("duplicate activation cells", [FIRST_CELL])

	EventBus.world_tile_activated.emit(SECOND_CELL)
	_require_cell_count("second activation", 2)
	_require_cells("second activation cells", [FIRST_CELL, SECOND_CELL])
	_require_visual_tile(SECOND_CELL)

	EventBus.world_tile_evicted.emit(FIRST_CELL)
	_require_cell_count("first eviction", 1)
	_require_cells("first eviction cells", [SECOND_CELL])
	_require_no_visual_cell(FIRST_CELL)

	EventBus.world_tile_evicted.emit(Vector2i(9, 9))
	_require_cell_count("unknown eviction", 1)
	_require_cells("unknown eviction cells", [SECOND_CELL])

	EventBus.world_tile_activated.emit(FIRST_CELL)
	_require_cell_count("reactivation", 2)
	_require_cells("reactivation cells", [FIRST_CELL, SECOND_CELL])
	var rebuilt_tile: MeshInstance3D = _require_visual_tile(FIRST_CELL)
	_require_rebuilt_tile(first_surface_count, first_bounds, rebuilt_tile)

	_streamer.call("reset_stream")
	_require_cell_count("reset", 0)
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
		_errors.append("streamed visual cell should not reference a missing HLOD visibility parent: " + String(mesh_instance.name))
	if not mesh_instance.has_meta(TerrainVisualBuilderScript.TILE_INDEX_META):
		_errors.append("visual cell missing tile index metadata: " + String(mesh_instance.name))
	elif Vector2i(mesh_instance.get_meta(TerrainVisualBuilderScript.TILE_INDEX_META)) != cell:
		_errors.append("visual cell metadata expected " + str(cell) + ", got " + str(mesh_instance.get_meta(TerrainVisualBuilderScript.TILE_INDEX_META)))
	if mesh_instance.mesh == null:
		_errors.append("visual cell missing mesh: " + String(mesh_instance.name))
	elif mesh_instance.mesh.get_surface_count() <= 0:
		_errors.append("visual cell mesh has no surfaces: " + String(mesh_instance.name))
	var collision_count: int = _count_collision_objects(mesh_instance)
	if collision_count > 0:
		_errors.append("streamed visual cell should not create collision objects: " + String(mesh_instance.name))
	return mesh_instance


func _require_no_visual_cell(cell: Vector2i) -> void:
	var has_cell: bool = bool(_streamer.call("has_visual_cell", cell))
	if has_cell:
		_errors.append("visual cell should have been evicted: " + str(cell))


func _require_rebuilt_tile(expected_surface_count: int, expected_bounds: AABB, tile: MeshInstance3D) -> void:
	if tile == null or tile.mesh == null:
		return
	if tile.mesh.get_surface_count() != expected_surface_count:
		_errors.append("rebuilt tile surface count expected " + str(expected_surface_count) + ", got " + str(tile.mesh.get_surface_count()))
	var rebuilt_bounds: AABB = tile.mesh.get_aabb()
	if rebuilt_bounds.position.distance_to(expected_bounds.position) > FLOAT_EPSILON:
		_errors.append("rebuilt tile bounds position drifted")
	if rebuilt_bounds.size.distance_to(expected_bounds.size) > FLOAT_EPSILON:
		_errors.append("rebuilt tile bounds size drifted")


func _require_cell_count(label: String, expected_count: int) -> void:
	var observed_count: int = int(_streamer.call("visual_cell_count"))
	if observed_count != expected_count:
		_errors.append(label + " expected " + str(expected_count) + " visual cells, got " + str(observed_count))


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
