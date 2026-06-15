extends Node3D

const HEIGHTMAP_FLOAT_BYTE_SIZE: int = 4
const DEFAULT_COLLISION_LAYER: int = 1
const DEFAULT_COLLISION_MASK: int = 1
const TILE_KEY_SEPARATOR: String = "_"
const HEIGHTMAP_SIDE_CAR_PATH: String = "tile.json"
const HEIGHTMAP_BIN_PATH: String = "heightmap.bin"

var _region_id: String = ""
var _followed_node: Node3D = null
var _fixed_world_position: Vector3 = Vector3.ZERO
var _use_fixed_world_position: bool = false
var _streaming_enabled: bool = false
var _current_cell: Vector2i = Vector2i.ZERO

var _ready_flags: Dictionary[Vector2i, bool] = {}
var _heightmap_shapes_by_cell: Dictionary[Vector2i, HeightMapShape3D] = {}
var _active_bodies_by_cell: Dictionary[Vector2i, RID] = {}
var _load_failures_by_cell: Dictionary[Vector2i, String] = {}
var _last_to_load: Array[Vector2i] = []
var _last_to_unload: Array[Vector2i] = []


func _ready() -> void:
	set_physics_process(false)


func configure_region(new_region_id: String, vehicle_node: Node3D) -> void:
	reset()
	_region_id = new_region_id
	_followed_node = vehicle_node
	_use_fixed_world_position = false
	_streaming_enabled = true
	set_physics_process(true)


func configure_fixed_position(new_region_id: String, world_position: Vector3) -> void:
	reset()
	_region_id = new_region_id
	_fixed_world_position = world_position
	_use_fixed_world_position = true
	_streaming_enabled = true
	set_physics_process(true)


func set_fixed_world_position(world_position: Vector3) -> void:
	_fixed_world_position = world_position


func reset() -> void:
	set_physics_process(false)
	_streaming_enabled = false
	_region_id = ""
	_followed_node = null
	_use_fixed_world_position = false
	_last_to_load.clear()
	_last_to_unload.clear()
	_unload_all_active_bodies()
	_ready_flags.clear()
	_heightmap_shapes_by_cell.clear()
	_load_failures_by_cell.clear()


func active_cells() -> Array[Vector2i]:
	return _sorted_body_cells()


func ready_cells() -> Array[Vector2i]:
	return _sorted_ready_cells()


func ready_flags() -> Dictionary[Vector2i, bool]:
	var copy: Dictionary[Vector2i, bool] = {}
	for cell in _sorted_ready_cells():
		copy[cell] = true
	return copy


func load_failures() -> Dictionary[Vector2i, String]:
	var copy: Dictionary[Vector2i, String] = {}
	var cells: Array[Vector2i] = _sorted_failure_cells()
	for cell in cells:
		copy[cell] = _load_failures_by_cell[cell]
	return copy


func current_cell() -> Vector2i:
	return _current_cell


func last_to_load() -> Array[Vector2i]:
	return _copy_cells(_last_to_load)


func last_to_unload() -> Array[Vector2i]:
	return _copy_cells(_last_to_unload)


func expected_active_cells_for_position(world_position: Vector3) -> Array[Vector2i]:
	return _cells_in_radius(_cell_for_world_position(world_position), GameConfig.STREAM_ACTIVE_RADIUS)


func expected_prefetch_cells_for_position(world_position: Vector3) -> Array[Vector2i]:
	return _cells_in_radius(_cell_for_world_position(world_position), GameConfig.STREAM_PREFETCH_RADIUS)


func _physics_process(_delta: float) -> void:
	if not _streaming_enabled:
		return
	if _region_id.is_empty():
		return

	_current_cell = _sample_current_cell()
	var desired_active_cells: Array[Vector2i] = _cells_in_radius(_current_cell, GameConfig.STREAM_ACTIVE_RADIUS)
	var desired_prefetch_cells: Array[Vector2i] = _cells_in_radius(_current_cell, GameConfig.STREAM_PREFETCH_RADIUS)
	var current_active_cells: Array[Vector2i] = _sorted_body_cells()

	_last_to_load = _cell_difference(desired_active_cells, current_active_cells)
	_last_to_unload = _cell_difference(current_active_cells, desired_active_cells)

	_process_unloads(_last_to_unload)
	_forget_ready_cells_outside_prefetch(desired_prefetch_cells)
	_build_ready_cells_inline(desired_prefetch_cells)
	_process_loads(_last_to_load)


func _process_unloads(cells: Array[Vector2i]) -> void:
	for cell in cells:
		if not _active_bodies_by_cell.has(cell):
			continue
		var body_rid: RID = _active_bodies_by_cell[cell]
		if body_rid.is_valid():
			PhysicsServer3D.body_set_space(body_rid, RID())
			PhysicsServer3D.free_rid(body_rid)
		_active_bodies_by_cell.erase(cell)
		_ready_flags.erase(cell)
		_heightmap_shapes_by_cell.erase(cell)
		EventBus.world_tile_evicted.emit(cell)


func _process_loads(cells: Array[Vector2i]) -> void:
	for cell in cells:
		if not _ready_flags.has(cell):
			_build_ready_cell_inline(cell)
		if not _ready_flags.has(cell):
			return
		_activate_cell(cell)


func _build_ready_cells_inline(cells: Array[Vector2i]) -> void:
	for cell in cells:
		if _ready_flags.has(cell):
			continue
		_build_ready_cell_inline(cell)


func _build_ready_cell_inline(cell: Vector2i) -> void:
	if _load_failures_by_cell.has(cell):
		return
	var shape: HeightMapShape3D = _load_heightmap_shape(cell)
	if shape == null:
		return
	_heightmap_shapes_by_cell[cell] = shape
	_ready_flags[cell] = true


func _activate_cell(cell: Vector2i) -> void:
	if _active_bodies_by_cell.has(cell):
		return
	if not _heightmap_shapes_by_cell.has(cell):
		return

	var shape: HeightMapShape3D = _heightmap_shapes_by_cell[cell]
	var body_rid: RID = PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(body_rid, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_collision_layer(body_rid, DEFAULT_COLLISION_LAYER)
	PhysicsServer3D.body_set_collision_mask(body_rid, DEFAULT_COLLISION_MASK)
	PhysicsServer3D.body_add_shape(
		body_rid,
		shape.get_rid(),
		Transform3D(Basis().scaled(_heightmap_collision_scale(shape)), _tile_center_world_position(cell))
	)
	PhysicsServer3D.body_set_space(body_rid, _physics_space())
	_active_bodies_by_cell[cell] = body_rid
	EventBus.world_tile_activated.emit(cell)


func _load_heightmap_shape(cell: Vector2i) -> HeightMapShape3D:
	var sidecar_path: String = _tile_sidecar_path(cell)
	if not FileAccess.file_exists(sidecar_path):
		_record_load_failure(cell, "missing tile sidecar: " + sidecar_path)
		return null

	var file: FileAccess = FileAccess.open(sidecar_path, FileAccess.READ)
	if file == null:
		_record_load_failure(cell, "could not open tile sidecar: " + sidecar_path)
		return null
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		_record_load_failure(cell, "tile sidecar is not a JSON object: " + sidecar_path)
		return null

	var sidecar: Dictionary[Variant, Variant] = parsed as Dictionary[Variant, Variant]
	if not sidecar.has("heightmap"):
		_record_load_failure(cell, "tile sidecar missing heightmap object: " + sidecar_path)
		return null
	var heightmap_info: Dictionary[Variant, Variant] = sidecar["heightmap"] as Dictionary[Variant, Variant]
	if not heightmap_info.has("shape"):
		_record_load_failure(cell, "tile sidecar missing heightmap.shape: " + sidecar_path)
		return null
	var shape_value: Variant = heightmap_info["shape"]
	if not (shape_value is Array):
		_record_load_failure(cell, "tile sidecar heightmap.shape is not an array: " + sidecar_path)
		return null
	var shape_array: Array = shape_value as Array
	if shape_array.size() != 2:
		_record_load_failure(cell, "tile sidecar heightmap.shape must have two entries: " + sidecar_path)
		return null

	var depth: int = int(shape_array[0])
	var width: int = int(shape_array[1])
	if width <= 1 or depth <= 1:
		_record_load_failure(cell, "tile heightmap shape must be at least 2x2: " + sidecar_path)
		return null

	var heightmap_path: String = _tile_heightmap_path(cell)
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(heightmap_path)
	var expected_byte_count: int = width * depth * HEIGHTMAP_FLOAT_BYTE_SIZE
	if bytes.size() != expected_byte_count:
		_record_load_failure(
			cell,
			"heightmap byte count " + str(bytes.size()) + " != " + str(expected_byte_count) + ": " + heightmap_path
		)
		return null

	var map_data: PackedFloat32Array = bytes.to_float32_array()
	if map_data.size() != width * depth:
		_record_load_failure(cell, "heightmap float count mismatch: " + heightmap_path)
		return null

	var shape: HeightMapShape3D = HeightMapShape3D.new()
	shape.map_width = width
	shape.map_depth = depth
	shape.map_data = map_data
	return shape


func _record_load_failure(cell: Vector2i, message: String) -> void:
	if _load_failures_by_cell.has(cell):
		return
	_load_failures_by_cell[cell] = message
	push_error(message)


func _forget_ready_cells_outside_prefetch(desired_prefetch_cells: Array[Vector2i]) -> void:
	var ready_cells_to_check: Array[Vector2i] = _sorted_ready_cells()
	for cell in ready_cells_to_check:
		if desired_prefetch_cells.has(cell):
			continue
		if _active_bodies_by_cell.has(cell):
			continue
		_ready_flags.erase(cell)
		_heightmap_shapes_by_cell.erase(cell)


func _unload_all_active_bodies() -> void:
	var cells: Array[Vector2i] = _sorted_body_cells()
	for cell in cells:
		var body_rid: RID = _active_bodies_by_cell[cell]
		if body_rid.is_valid():
			PhysicsServer3D.body_set_space(body_rid, RID())
			PhysicsServer3D.free_rid(body_rid)
	_active_bodies_by_cell.clear()


func _sample_current_cell() -> Vector2i:
	return _cell_for_world_position(_sample_world_position())


func _sample_world_position() -> Vector3:
	if _use_fixed_world_position:
		return _fixed_world_position
	if _followed_node != null:
		return _followed_node.global_position
	return global_position


func _cell_for_world_position(world_position: Vector3) -> Vector2i:
	var tile_size_m: float = GameConfig.STREAM_TILE_SIZE_M
	return Vector2i(
		int(floor(world_position.x / tile_size_m)),
		int(floor(world_position.z / tile_size_m))
	)


func _cells_in_radius(center_cell: Vector2i, radius: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for cell_x in range(center_cell.x - radius, center_cell.x + radius + 1):
		for cell_y in range(center_cell.y - radius, center_cell.y + radius + 1):
			cells.append(Vector2i(cell_x, cell_y))
	_sort_cells(cells)
	return cells


func _cell_difference(left_cells: Array[Vector2i], right_cells: Array[Vector2i]) -> Array[Vector2i]:
	var difference: Array[Vector2i] = []
	for cell in left_cells:
		if not right_cells.has(cell):
			difference.append(cell)
	_sort_cells(difference)
	return difference


func _sort_cells(cells: Array[Vector2i]) -> void:
	cells.sort_custom(Callable(self, "_cell_less"))


func _cell_less(left: Vector2i, right: Vector2i) -> bool:
	if left.x == right.x:
		return left.y < right.y
	return left.x < right.x


func _sorted_body_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for cell in _active_bodies_by_cell.keys():
		cells.append(cell)
	_sort_cells(cells)
	return cells


func _sorted_ready_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for cell in _ready_flags.keys():
		cells.append(cell)
	_sort_cells(cells)
	return cells


func _sorted_failure_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for cell in _load_failures_by_cell.keys():
		cells.append(cell)
	_sort_cells(cells)
	return cells


func _copy_cells(cells: Array[Vector2i]) -> Array[Vector2i]:
	var copy: Array[Vector2i] = []
	for cell in cells:
		copy.append(cell)
	return copy


func _heightmap_collision_scale(shape: HeightMapShape3D) -> Vector3:
	return Vector3(
		GameConfig.STREAM_TILE_SIZE_M / float(maxi(shape.map_width - 1, 1)),
		1.0,
		GameConfig.STREAM_TILE_SIZE_M / float(maxi(shape.map_depth - 1, 1))
	)


func _tile_center_world_position(cell: Vector2i) -> Vector3:
	var tile_size_m: float = GameConfig.STREAM_TILE_SIZE_M
	return Vector3(
		(float(cell.x) + 0.5) * tile_size_m,
		0.0,
		(float(cell.y) + 0.5) * tile_size_m
	)


func _physics_space() -> RID:
	if _followed_node != null:
		return _followed_node.get_world_3d().space
	return get_world_3d().space


func _tile_sidecar_path(cell: Vector2i) -> String:
	return _tile_directory_path(cell).path_join(HEIGHTMAP_SIDE_CAR_PATH)


func _tile_heightmap_path(cell: Vector2i) -> String:
	return _tile_directory_path(cell).path_join(HEIGHTMAP_BIN_PATH)


func _tile_directory_path(cell: Vector2i) -> String:
	return _region_path().path_join("tiles").path_join(_tile_key(cell))


func _region_path() -> String:
	return GameConfig.STREAM_TILE_DATA_BASE.path_join(_region_id)


func _tile_key(cell: Vector2i) -> String:
	return str(cell.x) + TILE_KEY_SEPARATOR + str(cell.y)
