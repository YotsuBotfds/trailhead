extends Node

const REGION_ID: String = "spike_1km"
const START_CELL: Vector2i = Vector2i(4, 4)
const END_CELL: Vector2i = Vector2i(5, 4)
const START_SETTLE_TICKS: int = 5
const END_SETTLE_TICKS: int = 5
const CELL_CENTER_OFFSET: float = 0.5

var _errors: PackedStringArray = PackedStringArray()
var _activated_cells: Array[Vector2i] = []
var _evicted_cells: Array[Vector2i] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var streamer: Node = get_node_or_null("/root/TileStreamer")
	if streamer == null:
		_errors.append("TileStreamer autoload was not registered")
		_finish(null)
		return

	if not EventBus.world_tile_activated.is_connected(_on_world_tile_activated):
		EventBus.world_tile_activated.connect(_on_world_tile_activated)
	if not EventBus.world_tile_evicted.is_connected(_on_world_tile_evicted):
		EventBus.world_tile_evicted.connect(_on_world_tile_evicted)

	streamer.call("configure_fixed_position", REGION_ID, _world_position_for_cell(START_CELL))
	await _advance_physics_ticks(START_SETTLE_TICKS)

	var expected_start_cells: Array[Vector2i] = _cells_in_radius(START_CELL, GameConfig.STREAM_ACTIVE_RADIUS)
	_require_cells("start active set", streamer.call("active_cells"), expected_start_cells)
	_require_cells("start activation event order", _activated_cells, expected_start_cells)
	_require_int("start eviction event count", _evicted_cells.size(), 0)
	_require_bool("start ready flags include prefetch ring", _ready_includes_prefetch(streamer, START_CELL))
	_require_no_load_failures(streamer)

	_activated_cells.clear()
	_evicted_cells.clear()
	streamer.call("set_fixed_world_position", _world_position_for_cell(END_CELL))
	await _advance_physics_ticks(END_SETTLE_TICKS)

	var expected_end_cells: Array[Vector2i] = _cells_in_radius(END_CELL, GameConfig.STREAM_ACTIVE_RADIUS)
	var expected_loaded_cells: Array[Vector2i] = _cell_difference(expected_end_cells, expected_start_cells)
	var expected_evicted_cells: Array[Vector2i] = _cell_difference(expected_start_cells, expected_end_cells)
	_require_cells("end active set", streamer.call("active_cells"), expected_end_cells)
	_require_cells("end activation event order", _activated_cells, expected_loaded_cells)
	_require_cells("end eviction event order", _evicted_cells, expected_evicted_cells)
	var empty_cells: Array[Vector2i] = []
	_require_cells("last to_load", streamer.call("last_to_load"), empty_cells)
	_require_cells("last to_unload", streamer.call("last_to_unload"), empty_cells)
	_require_bool("end ready flags include prefetch ring", _ready_includes_prefetch(streamer, END_CELL))
	_require_no_load_failures(streamer)

	_finish(streamer)


func _advance_physics_ticks(count: int) -> void:
	for _tick in range(count):
		await get_tree().physics_frame


func _on_world_tile_activated(cell: Vector2i) -> void:
	_activated_cells.append(cell)


func _on_world_tile_evicted(cell: Vector2i) -> void:
	_evicted_cells.append(cell)


func _ready_includes_prefetch(streamer: Node, center_cell: Vector2i) -> bool:
	var ready_cells: Array[Vector2i] = _variant_to_cell_array(streamer.call("ready_cells"))
	var expected_prefetch_cells: Array[Vector2i] = _cells_in_radius(center_cell, GameConfig.STREAM_PREFETCH_RADIUS)
	for cell in expected_prefetch_cells:
		if not ready_cells.has(cell):
			return false
	return true


func _require_no_load_failures(streamer: Node) -> void:
	var failures: Dictionary[Vector2i, String] = streamer.call("load_failures")
	if not failures.is_empty():
		_errors.append("expected no TileStreamer load failures, got " + str(failures))


func _require_cells(label: String, observed_value: Variant, expected_cells: Array[Vector2i]) -> void:
	var observed_cells: Array[Vector2i] = _variant_to_cell_array(observed_value)
	_sort_cells(observed_cells)
	var sorted_expected: Array[Vector2i] = _copy_cells(expected_cells)
	_sort_cells(sorted_expected)
	if observed_cells.size() != sorted_expected.size():
		_errors.append(
			label
			+ " expected "
			+ str(sorted_expected.size())
			+ " cells, got "
			+ str(observed_cells.size())
			+ ": "
			+ _cells_to_string(observed_cells)
		)
		return
	for index in range(sorted_expected.size()):
		if observed_cells[index] != sorted_expected[index]:
			_errors.append(
				label
				+ " mismatch at index "
				+ str(index)
				+ ": expected "
				+ str(sorted_expected[index])
				+ ", got "
				+ str(observed_cells[index])
			)
			return


func _require_int(label: String, actual: int, expected: int) -> void:
	if actual != expected:
		_errors.append(label + " expected " + str(expected) + ", got " + str(actual))


func _require_bool(label: String, actual: bool) -> void:
	if not actual:
		_errors.append(label)


func _finish(streamer: Node) -> void:
	if EventBus.world_tile_activated.is_connected(_on_world_tile_activated):
		EventBus.world_tile_activated.disconnect(_on_world_tile_activated)
	if EventBus.world_tile_evicted.is_connected(_on_world_tile_evicted):
		EventBus.world_tile_evicted.disconnect(_on_world_tile_evicted)
	if streamer != null:
		streamer.call("reset")

	if _errors.is_empty():
		print("ok: TileStreamer active set and sorted lifecycle events")
		get_tree().quit(0)
		return
	for error in _errors:
		push_error(error)
	get_tree().quit(1)


func _world_position_for_cell(cell: Vector2i) -> Vector3:
	var tile_size_m: float = GameConfig.STREAM_TILE_SIZE_M
	return Vector3(
		(float(cell.x) + CELL_CENTER_OFFSET) * tile_size_m,
		0.0,
		(float(cell.y) + CELL_CENTER_OFFSET) * tile_size_m
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


func _variant_to_cell_array(value: Variant) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if not (value is Array):
		return cells
	var raw_cells: Array = value as Array
	for item in raw_cells:
		if item is Vector2i:
			cells.append(item)
	_sort_cells(cells)
	return cells


func _copy_cells(cells: Array[Vector2i]) -> Array[Vector2i]:
	var copy: Array[Vector2i] = []
	for cell in cells:
		copy.append(cell)
	return copy


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
	return ", ".join(parts)
