extends Node

const REGION_ID: String = "spike_1km"
const START_CELL: Vector2i = Vector2i(4, 4)
const END_CELL: Vector2i = Vector2i(5, 4)
const ACTIVE_SET_READY_TIMEOUT_TICKS: int = 120
const ACTIVE_SET_CONVERGENCE_MARGIN_TICKS: int = 2
const PREFETCH_READY_TIMEOUT_TICKS: int = 120
const CELL_CENTER_OFFSET: float = 0.5
const WORKER_COUNT_ARG: String = "--tile-streamer-workers="

var _errors: PackedStringArray = PackedStringArray()
var _streamer: Node = null
var _activated_cells: Array[Vector2i] = []
var _evicted_cells: Array[Vector2i] = []
var _prefetched_cells: Array[Vector2i] = []
var _unprefetched_cells: Array[Vector2i] = []
var _activation_events: Array[Variant] = []
var _all_activated_keys: PackedStringArray = PackedStringArray()
var _all_prefetched_keys: PackedStringArray = PackedStringArray()
var _activation_ticks: Dictionary[String, int] = {}
var _prefetch_ticks: Dictionary[String, int] = {}
var _non_current_activation_counts_by_tick: Dictionary[int, int] = {}
var _physics_tick: int = 0
var _worker_count: int = 1
var _fixture_sort_origin_cell: Vector2i = Vector2i.ZERO


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var streamer: Node = get_node_or_null("/root/TileStreamer")
	if streamer == null:
		_errors.append("TileStreamer autoload was not registered")
		_finish(null)
		return
	_streamer = streamer

	_worker_count = _read_worker_count_arg()
	streamer.call("set_worker_count_for_tests", _worker_count)

	if not EventBus.world_tile_activated.is_connected(_on_world_tile_activated):
		EventBus.world_tile_activated.connect(_on_world_tile_activated)
	if not EventBus.world_tile_evicted.is_connected(_on_world_tile_evicted):
		EventBus.world_tile_evicted.connect(_on_world_tile_evicted)
	if not EventBus.world_tile_prefetched.is_connected(_on_world_tile_prefetched):
		EventBus.world_tile_prefetched.connect(_on_world_tile_prefetched)
	if not EventBus.world_tile_unprefetched.is_connected(_on_world_tile_unprefetched):
		EventBus.world_tile_unprefetched.connect(_on_world_tile_unprefetched)

	var expected_start_cells: Array[Vector2i] = _cells_in_radius(START_CELL, GameConfig.STREAM_ACTIVE_RADIUS)
	var expected_start_prefetch_cells: Array[Vector2i] = _cells_in_radius(START_CELL, GameConfig.STREAM_PREFETCH_RADIUS)
	streamer.call("configure_fixed_position", REGION_ID, _world_position_for_cell(START_CELL))
	await _wait_for_cells_ready(streamer, expected_start_cells, ACTIVE_SET_READY_TIMEOUT_TICKS)
	await _wait_for_active_set(
		streamer,
		expected_start_cells,
		_activation_convergence_timeout_ticks(expected_start_cells.size(), true)
	)
	await _wait_for_prefetch_ready(streamer, START_CELL)

	_require_cells("start active set", streamer.call("active_cells"), expected_start_cells)
	_require_cells_exact_order("start activation event order", _activated_cells, _activation_order_for_cells(START_CELL, expected_start_cells))
	_require_event_keys_include_cells("start prefetch event coverage", _all_prefetched_keys, expected_start_prefetch_cells)
	_require_int("start eviction event count", _evicted_cells.size(), 0)
	_require_activation_budget("start activation budget")
	_require_no_load_failures(streamer)

	_activated_cells.clear()
	_evicted_cells.clear()
	_prefetched_cells.clear()
	_unprefetched_cells.clear()
	var expected_end_cells: Array[Vector2i] = _cells_in_radius(END_CELL, GameConfig.STREAM_ACTIVE_RADIUS)
	var expected_loaded_cells: Array[Vector2i] = _cell_difference(expected_end_cells, expected_start_cells)
	var expected_evicted_cells: Array[Vector2i] = _cell_difference(expected_start_cells, expected_end_cells)
	var expected_end_prefetch_cells: Array[Vector2i] = _cells_in_radius(END_CELL, GameConfig.STREAM_PREFETCH_RADIUS)
	var expected_unprefetched_cells: Array[Vector2i] = _cell_difference(expected_start_prefetch_cells, expected_end_prefetch_cells)
	var end_position: Vector3 = _world_position_for_cell(END_CELL)
	var end_arrival_tick: int = _physics_tick + 1
	streamer.call("set_fixed_world_position", end_position)
	await _advance_physics_ticks(1)
	_require_current_cell("end current cell on arrival tick", streamer, END_CELL)
	_require_collision_ready_no_later("end current cell collision-ready on arrival tick", streamer, end_position, end_arrival_tick)
	await _wait_for_active_set(
		streamer,
		expected_end_cells,
		_activation_convergence_timeout_ticks(expected_loaded_cells.size(), false)
	)
	await _advance_physics_ticks(1)

	_require_cells("end active set", streamer.call("active_cells"), expected_end_cells)
	_require_cells_exact_order("end activation event order", _activated_cells, _activation_order_for_cells(END_CELL, expected_loaded_cells))
	_require_cells_exact_order("end eviction event order", _evicted_cells, expected_evicted_cells)
	_require_cells_exact_order("end unprefetch event order", _unprefetched_cells, expected_unprefetched_cells)
	var empty_cells: Array[Vector2i] = []
	_require_cells("last to_load", streamer.call("last_to_load"), empty_cells)
	_require_cells("last to_unload", streamer.call("last_to_unload"), empty_cells)
	await _wait_for_prefetch_ready(streamer, END_CELL)
	_require_bool("end ready flags include prefetch ring", _ready_includes_prefetch(streamer, END_CELL))
	_require_event_keys_include_cells("end prefetch event coverage", _all_prefetched_keys, expected_end_prefetch_cells)
	_require_activation_budget("end activation budget")
	_require_no_load_failures(streamer)

	_finish(streamer)


func _advance_physics_ticks(count: int) -> void:
	for _tick in range(count):
		await get_tree().physics_frame
		_physics_tick += 1


func _wait_for_prefetch_ready(streamer: Node, center_cell: Vector2i) -> void:
	for _tick in range(PREFETCH_READY_TIMEOUT_TICKS):
		if _ready_includes_prefetch(streamer, center_cell):
			return
		await _advance_physics_ticks(1)
	_errors.append("prefetch ready timed out for " + str(center_cell))


func _wait_for_cells_ready(streamer: Node, expected_cells: Array[Vector2i], timeout_ticks: int) -> void:
	for _tick in range(timeout_ticks):
		if _ready_includes_cells(streamer, expected_cells):
			return
		await _advance_physics_ticks(1)
	_errors.append("active cells ready timed out: " + _cells_to_string(expected_cells))


func _wait_for_active_set(streamer: Node, expected_cells: Array[Vector2i], timeout_ticks: int) -> void:
	for _tick in range(timeout_ticks):
		if _active_set_matches(streamer, expected_cells):
			return
		await _advance_physics_ticks(1)
	_errors.append("active-set convergence timed out: " + _cells_to_string(expected_cells))


func _on_world_tile_activated(cell: Vector2i) -> void:
	_activated_cells.append(cell)
	var key: String = _cell_key(cell)
	_all_activated_keys.append(key)
	if not _activation_ticks.has(key):
		_activation_ticks[key] = _physics_tick
	var current_cell: Vector2i = _current_streamer_cell()
	var is_current_cell: bool = cell == current_cell
	_activation_events.append({
		"tick": _physics_tick,
		"cell": key,
		"current_cell": _cell_key(current_cell),
		"is_current_cell": is_current_cell,
	})
	if not is_current_cell:
		var count: int = int(_non_current_activation_counts_by_tick.get(_physics_tick, 0)) + 1
		_non_current_activation_counts_by_tick[_physics_tick] = count


func _on_world_tile_evicted(cell: Vector2i) -> void:
	_evicted_cells.append(cell)


func _on_world_tile_prefetched(cell: Vector2i) -> void:
	_prefetched_cells.append(cell)
	var key: String = _cell_key(cell)
	_all_prefetched_keys.append(key)
	if not _prefetch_ticks.has(key):
		_prefetch_ticks[key] = _physics_tick


func _on_world_tile_unprefetched(cell: Vector2i) -> void:
	_unprefetched_cells.append(cell)


func _ready_includes_prefetch(streamer: Node, center_cell: Vector2i) -> bool:
	var ready_cells: Array[Vector2i] = _variant_to_cell_array(streamer.call("ready_cells"))
	var expected_prefetch_cells: Array[Vector2i] = _cells_in_radius(center_cell, GameConfig.STREAM_PREFETCH_RADIUS)
	for cell in expected_prefetch_cells:
		if not ready_cells.has(cell):
			return false
	return true


func _ready_includes_cells(streamer: Node, expected_cells: Array[Vector2i]) -> bool:
	var ready_cells: Array[Vector2i] = _variant_to_cell_array(streamer.call("ready_cells"))
	for cell in expected_cells:
		if not ready_cells.has(cell):
			return false
	return true


func _active_set_matches(streamer: Node, expected_cells: Array[Vector2i]) -> bool:
	var active_cells: Array[Vector2i] = _variant_to_cell_array(streamer.call("active_cells"))
	var sorted_expected: Array[Vector2i] = _copy_cells(expected_cells)
	_sort_cells(sorted_expected)
	if active_cells.size() != sorted_expected.size():
		return false
	for index in range(sorted_expected.size()):
		if active_cells[index] != sorted_expected[index]:
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


func _require_cells_exact_order(label: String, observed_value: Variant, expected_cells: Array[Vector2i]) -> void:
	var observed_cells: Array[Vector2i] = _variant_to_cell_array_unsorted(observed_value)
	if observed_cells.size() != expected_cells.size():
		_errors.append(
			label
			+ " expected "
			+ str(expected_cells.size())
			+ " cells, got "
			+ str(observed_cells.size())
			+ ": "
			+ _cells_to_string(observed_cells)
		)
		return
	for index in range(expected_cells.size()):
		if observed_cells[index] != expected_cells[index]:
			_errors.append(
				label
				+ " mismatch at index "
				+ str(index)
				+ ": expected "
				+ str(expected_cells[index])
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


func _require_current_cell(label: String, streamer: Node, expected_cell: Vector2i) -> void:
	var current_value: Variant = streamer.call("current_cell")
	if not (current_value is Vector2i):
		_errors.append(label + " could not read current_cell")
		return
	var current_cell: Vector2i = current_value
	if current_cell != expected_cell:
		_errors.append(label + " expected " + str(expected_cell) + ", got " + str(current_cell))


func _require_collision_ready_no_later(label: String, streamer: Node, world_position: Vector3, latest_tick: int) -> void:
	if not bool(streamer.call("is_collision_ready_at", world_position)):
		_errors.append(label + " expected ready collision at " + str(world_position))
		return
	var activation_tick: int = int(streamer.call("collision_activation_tick_at", world_position))
	if activation_tick < 0:
		_errors.append(label + " missing activation tick at " + str(world_position))
		return
	if activation_tick > latest_tick:
		_errors.append(label + " expected activation <= " + str(latest_tick) + ", got " + str(activation_tick))


func _require_activation_budget(label: String) -> void:
	var budget: int = _activation_budget()
	var ticks: Array[int] = []
	for tick_value in _non_current_activation_counts_by_tick.keys():
		ticks.append(int(tick_value))
	ticks.sort()
	for tick in ticks:
		var count: int = _non_current_activation_counts_by_tick[tick]
		if count > budget:
			_errors.append(label + " tick " + str(tick) + " activated " + str(count) + " non-current cells, budget " + str(budget))


func _require_event_keys_include_cells(label: String, observed_keys: PackedStringArray, expected_cells: Array[Vector2i]) -> void:
	var missing: PackedStringArray = PackedStringArray()
	for cell in expected_cells:
		var key: String = _cell_key(cell)
		if not observed_keys.has(key):
			missing.append(key)
	if not missing.is_empty():
		_errors.append(label + " missing keys: " + ", ".join(missing))


func _finish(streamer: Node) -> void:
	if EventBus.world_tile_activated.is_connected(_on_world_tile_activated):
		EventBus.world_tile_activated.disconnect(_on_world_tile_activated)
	if EventBus.world_tile_evicted.is_connected(_on_world_tile_evicted):
		EventBus.world_tile_evicted.disconnect(_on_world_tile_evicted)
	if EventBus.world_tile_prefetched.is_connected(_on_world_tile_prefetched):
		EventBus.world_tile_prefetched.disconnect(_on_world_tile_prefetched)
	if EventBus.world_tile_unprefetched.is_connected(_on_world_tile_unprefetched):
		EventBus.world_tile_unprefetched.disconnect(_on_world_tile_unprefetched)
	if streamer != null:
		streamer.call("reset")
	_streamer = null

	if _errors.is_empty():
		var result: Dictionary = {
			"worker_count": _worker_count,
			"activation_order": _all_activated_keys,
			"activation_ticks": _activation_ticks,
			"activation_events": _activation_events,
			"non_current_activation_counts_by_tick": _non_current_activation_counts_by_tick,
			"prefetch_order": _all_prefetched_keys,
			"prefetch_ticks": _prefetch_ticks,
		}
		print("tile_streamer_fixture_result=" + JSON.stringify(result))
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


func _variant_to_cell_array_unsorted(value: Variant) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if not (value is Array):
		return cells
	var raw_cells: Array = value as Array
	for item in raw_cells:
		if item is Vector2i:
			cells.append(item)
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


func _activation_order_for_cells(origin_cell: Vector2i, cells: Array[Vector2i]) -> Array[Vector2i]:
	var ordered_cells: Array[Vector2i] = []
	if cells.has(origin_cell):
		ordered_cells.append(origin_cell)
	var remaining_cells: Array[Vector2i] = []
	for cell in cells:
		if cell != origin_cell:
			remaining_cells.append(cell)
	_fixture_sort_origin_cell = origin_cell
	remaining_cells.sort_custom(Callable(self, "_cell_distance_less"))
	for cell in remaining_cells:
		ordered_cells.append(cell)
	return ordered_cells


func _cell_distance_less(left: Vector2i, right: Vector2i) -> bool:
	var left_distance: int = maxi(absi(left.x - _fixture_sort_origin_cell.x), absi(left.y - _fixture_sort_origin_cell.y))
	var right_distance: int = maxi(absi(right.x - _fixture_sort_origin_cell.x), absi(right.y - _fixture_sort_origin_cell.y))
	if left_distance == right_distance:
		return _cell_less(left, right)
	return left_distance < right_distance


func _activation_convergence_timeout_ticks(cell_count: int, includes_current_cell: bool) -> int:
	var non_current_cell_count: int = cell_count
	if includes_current_cell:
		non_current_cell_count = maxi(cell_count - 1, 0)
	var budgeted_ticks: int = _ceil_div(non_current_cell_count, _activation_budget())
	return maxi(budgeted_ticks + ACTIVE_SET_CONVERGENCE_MARGIN_TICKS, 1)


func _ceil_div(numerator: int, denominator: int) -> int:
	var safe_denominator: int = maxi(denominator, 1)
	if numerator <= 0:
		return 0
	return int((numerator + safe_denominator - 1) / safe_denominator)


func _activation_budget() -> int:
	return maxi(GameConfig.stream_collision_activations_per_tick, 1)


func _current_streamer_cell() -> Vector2i:
	if _streamer == null:
		return Vector2i.ZERO
	var current_value: Variant = _streamer.call("current_cell")
	if current_value is Vector2i:
		return current_value
	return Vector2i.ZERO


func _cells_to_string(cells: Array[Vector2i]) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for cell in cells:
		parts.append(str(cell))
	return ", ".join(parts)


func _read_worker_count_arg() -> int:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(WORKER_COUNT_ARG):
			return maxi(int(arg.substr(WORKER_COUNT_ARG.length())), 0)
	return 1


func _cell_key(cell: Vector2i) -> String:
	return str(cell.x) + "_" + str(cell.y)
