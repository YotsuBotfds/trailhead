extends Node

const REGION_ID: String = "cedar_hollow_zion"
const PREWARM_START_CELL: Vector2i = Vector2i(50, 16)
const PREWARM_TARGET_CELL: Vector2i = Vector2i(54, 16)
const SYNC_START_CELL: Vector2i = Vector2i(15, 16)
const SYNC_TARGET_CELL: Vector2i = Vector2i(19, 16)
const SYNC_WORKER_COUNTS: Array[int] = [0, 1]
const PREWARM_WORKER_COUNT: int = 2
const TARGET_READY_TIMEOUT_TICKS: int = 600
const PREFETCH_READY_TIMEOUT_TICKS: int = 600
const TARGET_PREWARM_TIMEOUT_TICKS: int = 600
const QUIET_COOK_TIMEOUT_TICKS: int = 240
const TARGET_ACTIVATION_TIMEOUT_TICKS: int = 600
const CELL_CENTER_OFFSET: float = 0.5
const RESULT_PREFIX: String = "tile_streamer_prewarm_fixture_result="

var _streamer: Node = null
var _errors: PackedStringArray = PackedStringArray()
var _activation_cooks_by_cell: Dictionary[String, int] = {}
var _activation_ticks_by_cell: Dictionary[String, int] = {}
var _activation_events: Array[Variant] = []
var _case_results: Array[Variant] = []
var _physics_tick: int = 0
var _current_worker_count: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_streamer = get_node_or_null("/root/TileStreamer")
	if _streamer == null:
		_errors.append("TileStreamer autoload was not registered")
		_finish()
		return
	if not _streamer.has_method("collision_cooks_this_tick"):
		_errors.append("TileStreamer missing collision_cooks_this_tick")
		_finish()
		return
	if not _streamer.has_method("prewarmed_cells_for_tests"):
		_errors.append("TileStreamer missing prewarmed_cells_for_tests")
		_finish()
		return
	if not _validate_crossing_cells("prewarm", PREWARM_START_CELL, PREWARM_TARGET_CELL):
		_finish()
		return
	if not _validate_crossing_cells("sync", SYNC_START_CELL, SYNC_TARGET_CELL):
		_finish()
		return

	if not EventBus.world_tile_activated.is_connected(_on_world_tile_activated):
		EventBus.world_tile_activated.connect(_on_world_tile_activated)

	await _run_case(PREWARM_WORKER_COUNT, PREWARM_START_CELL, PREWARM_TARGET_CELL, true)
	for worker_count in SYNC_WORKER_COUNTS:
		await _run_case(worker_count, SYNC_START_CELL, SYNC_TARGET_CELL, false)
	_finish()


func _run_case(worker_count: int, start_cell: Vector2i, target_cell: Vector2i, expect_zero_cook: bool) -> void:
	_current_worker_count = worker_count
	_activation_cooks_by_cell.clear()
	_activation_ticks_by_cell.clear()
	_activation_events.clear()
	_physics_tick = 0

	_streamer.call("reset")
	_streamer.call("set_worker_count_for_tests", worker_count)
	_streamer.call("configure_fixed_position", REGION_ID, _world_position_for_cell(start_cell))

	if expect_zero_cook:
		await _wait_for_ready_cells(_cells_in_radius(start_cell, GameConfig.STREAM_PREFETCH_RADIUS), PREFETCH_READY_TIMEOUT_TICKS)
	else:
		await _wait_for_ready_cell(target_cell, TARGET_READY_TIMEOUT_TICKS)
	_require_no_load_failures("worker " + str(worker_count) + " start")
	_require_bool(
		"worker " + str(worker_count) + " target inactive before crossing",
		not bool(_streamer.call("is_collision_ready_at", _world_position_for_cell(target_cell)))
	)

	if expect_zero_cook:
		await _wait_for_prewarmed_cell(target_cell, TARGET_PREWARM_TIMEOUT_TICKS)
		await _wait_for_quiet_collision_cook_tick(QUIET_COOK_TIMEOUT_TICKS)
		_require_bool(
			"worker " + str(worker_count) + " target prewarmed before crossing",
			_prewarmed_cells().has(target_cell)
		)
	else:
		_require_cells_empty(
			"worker " + str(worker_count) + " prewarmed cells before crossing",
			_prewarmed_cells()
		)

	var target_position: Vector3 = _world_position_for_cell(target_cell)
	var expected_arrival_stream_tick: int = _stream_tick() + 1
	_streamer.call("set_fixed_world_position", target_position)
	await _advance_physics_ticks(1)
	_require_current_cell("worker " + str(worker_count) + " arrival current cell", target_cell)

	if expect_zero_cook:
		_require_activation_tick(
			"worker " + str(worker_count) + " target promoted on arrival tick",
			target_cell,
			expected_arrival_stream_tick
		)
		_require_activation_cooks_equal(
			"worker " + str(worker_count) + " target promotion cook count",
			target_cell,
			0
		)
		_require_bool(
			"worker " + str(worker_count) + " target prewarm consumed",
			not _prewarmed_cells().has(target_cell)
		)
	else:
		await _wait_for_activation(target_cell, TARGET_ACTIVATION_TIMEOUT_TICKS)
		_require_activation_cooks_at_least(
			"worker " + str(worker_count) + " target synchronous activation cook count",
			target_cell,
			1
		)

	_require_bool(
		"worker " + str(worker_count) + " target collision ready after activation",
		bool(_streamer.call("is_collision_ready_at", target_position))
	)
	_case_results.append({
		"worker_count": worker_count,
		"start_cell": _cell_key(start_cell),
		"target_cell": _cell_key(target_cell),
		"expect_zero_cook": expect_zero_cook,
		"target_activation_tick": int(_activation_ticks_by_cell.get(_cell_key(target_cell), -1)),
		"target_activation_cooks": int(_activation_cooks_by_cell.get(_cell_key(target_cell), -1)),
		"activation_events": _activation_events.duplicate(true),
	})
	_streamer.call("reset")


func _advance_physics_ticks(count: int) -> void:
	for _tick in range(count):
		await get_tree().physics_frame
		_physics_tick += 1


func _wait_for_ready_cell(cell: Vector2i, timeout_ticks: int) -> void:
	for _tick in range(timeout_ticks):
		if _ready_cells().has(cell):
			return
		await _advance_physics_ticks(1)
	_errors.append("ready timed out for " + _cell_key(cell))


func _wait_for_ready_cells(cells: Array[Vector2i], timeout_ticks: int) -> void:
	for _tick in range(timeout_ticks):
		if _ready_includes_cells(cells):
			return
		await _advance_physics_ticks(1)
	_errors.append("ready timed out for " + _cells_to_string(cells))


func _wait_for_prewarmed_cell(cell: Vector2i, timeout_ticks: int) -> void:
	for _tick in range(timeout_ticks):
		if _prewarmed_cells().has(cell):
			return
		await _advance_physics_ticks(1)
	_errors.append("prewarm timed out for " + _cell_key(cell))


func _wait_for_quiet_collision_cook_tick(timeout_ticks: int) -> void:
	for _tick in range(timeout_ticks):
		await _advance_physics_ticks(1)
		if _collision_cooks_this_tick() == 0:
			return
	_errors.append("quiet collision cook tick timed out")


func _wait_for_activation(cell: Vector2i, timeout_ticks: int) -> void:
	var key: String = _cell_key(cell)
	for _tick in range(timeout_ticks):
		if _activation_ticks_by_cell.has(key):
			return
		await _advance_physics_ticks(1)
	_errors.append("activation timed out for " + key)


func _on_world_tile_activated(cell: Vector2i) -> void:
	var key: String = _cell_key(cell)
	var stream_tick: int = _stream_tick()
	var cooks_this_tick: int = _collision_cooks_this_tick()
	if not _activation_ticks_by_cell.has(key):
		_activation_ticks_by_cell[key] = stream_tick
	if not _activation_cooks_by_cell.has(key):
		_activation_cooks_by_cell[key] = cooks_this_tick
	_activation_events.append({
		"worker_count": _current_worker_count,
		"physics_tick": _physics_tick,
		"stream_tick": stream_tick,
		"cell": key,
		"collision_cooks_this_tick": cooks_this_tick,
	})


func _require_no_load_failures(label: String) -> void:
	var failures: Dictionary[Vector2i, String] = _streamer.call("load_failures")
	if not failures.is_empty():
		_errors.append(label + " expected no load failures, got " + str(failures))


func _require_bool(label: String, actual: bool) -> void:
	if not actual:
		_errors.append(label)


func _require_cells_empty(label: String, cells: Array[Vector2i]) -> void:
	if not cells.is_empty():
		_errors.append(label + " expected none, got " + _cells_to_string(cells))


func _require_current_cell(label: String, expected_cell: Vector2i) -> void:
	var current_value: Variant = _streamer.call("current_cell")
	if not (current_value is Vector2i):
		_errors.append(label + " could not read current_cell")
		return
	var current_cell: Vector2i = current_value
	if current_cell != expected_cell:
		_errors.append(label + " expected " + str(expected_cell) + ", got " + str(current_cell))


func _require_activation_tick(label: String, cell: Vector2i, expected_tick: int) -> void:
	var key: String = _cell_key(cell)
	if not _activation_ticks_by_cell.has(key):
		_errors.append(label + " missing activation for " + key)
		return
	var actual_tick: int = _activation_ticks_by_cell[key]
	if actual_tick != expected_tick:
		_errors.append(label + " expected " + str(expected_tick) + ", got " + str(actual_tick))


func _require_activation_cooks_equal(label: String, cell: Vector2i, expected_cooks: int) -> void:
	var key: String = _cell_key(cell)
	if not _activation_cooks_by_cell.has(key):
		_errors.append(label + " missing activation cook count for " + key)
		return
	var actual_cooks: int = _activation_cooks_by_cell[key]
	if actual_cooks != expected_cooks:
		_errors.append(label + " expected " + str(expected_cooks) + ", got " + str(actual_cooks))


func _require_activation_cooks_at_least(label: String, cell: Vector2i, minimum_cooks: int) -> void:
	var key: String = _cell_key(cell)
	if not _activation_cooks_by_cell.has(key):
		_errors.append(label + " missing activation cook count for " + key)
		return
	var actual_cooks: int = _activation_cooks_by_cell[key]
	if actual_cooks < minimum_cooks:
		_errors.append(label + " expected >= " + str(minimum_cooks) + ", got " + str(actual_cooks))


func _ready_cells() -> Array[Vector2i]:
	return _variant_to_cell_array(_streamer.call("ready_cells"))


func _ready_includes_cells(cells: Array[Vector2i]) -> bool:
	var ready_cells: Array[Vector2i] = _ready_cells()
	for cell in cells:
		if not ready_cells.has(cell):
			return false
	return true


func _prewarmed_cells() -> Array[Vector2i]:
	return _variant_to_cell_array(_streamer.call("prewarmed_cells_for_tests"))


func _collision_cooks_this_tick() -> int:
	return int(_streamer.call("collision_cooks_this_tick"))


func _stream_tick() -> int:
	return int(_streamer.call("current_stream_tick"))


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


func _cell_key(cell: Vector2i) -> String:
	return str(cell.x) + "_" + str(cell.y)


func _validate_crossing_cells(label: String, start_cell: Vector2i, target_cell: Vector2i) -> bool:
	if not _cells_in_radius(start_cell, GameConfig.STREAM_PREFETCH_RADIUS).has(target_cell):
		_errors.append(label + " target cell must be inside the start prefetch ring")
		return false
	if _cells_in_radius(start_cell, GameConfig.STREAM_ACTIVE_RADIUS).has(target_cell):
		_errors.append(label + " target cell must be outside the start active ring")
		return false
	return true


func _finish() -> void:
	if EventBus.world_tile_activated.is_connected(_on_world_tile_activated):
		EventBus.world_tile_activated.disconnect(_on_world_tile_activated)
	if _streamer != null:
		_streamer.call("reset")
		_streamer = null

	if _errors.is_empty():
		var result: Dictionary[String, Variant] = {
			"region_id": REGION_ID,
			"prewarm_start_cell": _cell_key(PREWARM_START_CELL),
			"prewarm_target_cell": _cell_key(PREWARM_TARGET_CELL),
			"sync_start_cell": _cell_key(SYNC_START_CELL),
			"sync_target_cell": _cell_key(SYNC_TARGET_CELL),
			"cases": _case_results,
		}
		print(RESULT_PREFIX + JSON.stringify(result))
		print("ok: TileStreamer prewarm promotion avoids crossing-tick collision cook")
		get_tree().quit(0)
		return
	for error in _errors:
		push_error(error)
	get_tree().quit(1)
