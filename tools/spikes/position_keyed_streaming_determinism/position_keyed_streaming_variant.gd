extends Node3D

signal sim_completed_run

const TILE_SIZE_M: float = 100.0
const ACTIVE_RADIUS: int = 2
const PREFETCH_RADIUS: int = 3
const ACTIVATION_CAP_PER_TICK: int = 5
const PHYSICS_TICKS_PER_SECOND: int = 120
const PROXY_SPEED_MPS: float = 8.0
const RUN_TICKS: int = 3300
const GRID_MIN_X: int = -3
const GRID_MAX_X: int = 5
const GRID_MIN_Y: int = -3
const GRID_MAX_Y: int = 3
const START_X_M: float = 50.0
const PROXY_Z_M: float = 25.0
const RAY_START_Y_M: float = 24.0
const RAY_END_Y_M: float = -24.0
const SLAB_THICKNESS_M: float = 2.0
const TRACE_INTERVAL_TICKS: int = 120
const VARIANT_PRE_PINNED: String = "pre_pinned"
const VARIANT_STREAMED: String = "streamed"

var final_result: Dictionary[String, Variant] = {}

var _variant_name: String = ""
var _worker_count: int = 0
var _run_index: int = 0
var _tick: int = 0
var _enqueue_sequence: int = 0
var _missed_activation_due_not_ready: int = 0
var _activation_sorted_per_tick: bool = true
var _activation_cap_respected: bool = true
var _completion_started: bool = false
var _last_center_cell: Vector2i = Vector2i(999999, 999999)

var _cell_by_key: Dictionary[String, Vector2i] = {}
var _shape_by_key: Dictionary[String, BoxShape3D] = {}
var _height_by_key: Dictionary[String, float] = {}
var _ready_tick_by_key: Dictionary[String, int] = {}
var _scheduled_ready_tick_by_key: Dictionary[String, int] = {}
var _scheduled_worker_by_key: Dictionary[String, int] = {}
var _body_by_key: Dictionary[String, RID] = {}
var _worker_available_tick: Array[int] = []
var _pending_keys: Array[String] = []
var _activated_cells: Array[Vector2i] = []
var _activation_tick_by_key: Dictionary[String, int] = {}
var _worker_ready_cells: Array[Vector2i] = []
var _activation_order: Array[Variant] = []
var _ready_order: Array[Variant] = []
var _trace: Array[Variant] = []


func configure(variant_name: String, worker_count: int, run_index: int) -> void:
	_variant_name = variant_name
	_worker_count = worker_count
	_run_index = run_index


func _ready() -> void:
	name = "PositionKeyedStreaming_" + _variant_name + "_" + str(_worker_count) + "_" + str(_run_index)
	_register_grid_cells()
	_initialize_worker_state()
	_initialize_ready_tiles()
	set_physics_process(true)


func _physics_process(_delta: float) -> void:
	if _completion_started:
		return

	_tick += 1
	var center_cell: Vector2i = _center_cell_for_tick(_tick)
	_complete_ready_jobs()
	_schedule_prefetch(center_cell)
	_activate_ready_cells(center_cell)
	_sample_trace_if_needed(center_cell)
	_last_center_cell = center_cell

	if _tick >= RUN_TICKS:
		_finish_run()


func _register_grid_cells() -> void:
	for cell_x in range(GRID_MIN_X, GRID_MAX_X + 1):
		for cell_y in range(GRID_MIN_Y, GRID_MAX_Y + 1):
			var cell: Vector2i = Vector2i(cell_x, cell_y)
			_cell_by_key[_key_for_cell(cell)] = cell


func _initialize_worker_state() -> void:
	var count: int = maxi(_worker_count, 1)
	_worker_available_tick.clear()
	for _index in range(count):
		_worker_available_tick.append(0)


func _initialize_ready_tiles() -> void:
	if _variant_name == VARIANT_PRE_PINNED:
		var all_cells: Array[Vector2i] = _all_grid_cells()
		for cell in all_cells:
			_mark_tile_ready(cell, 0, "pre_pinned", -1)
		return

	var initial_center: Vector2i = _center_cell_for_tick(0)
	var prewarmed_cells: Array[Vector2i] = _cells_in_radius(initial_center, PREFETCH_RADIUS)
	for cell in prewarmed_cells:
		_mark_tile_ready(cell, 0, "prewarm", -1)


func _complete_ready_jobs() -> void:
	if _pending_keys.is_empty():
		return

	var still_pending: Array[String] = []
	for key in _pending_keys:
		if not _scheduled_ready_tick_by_key.has(key):
			continue
		var ready_tick: int = _scheduled_ready_tick_by_key[key]
		if ready_tick <= _tick:
			if not _cell_by_key.has(key):
				continue
			var worker_index: int = -1
			if _scheduled_worker_by_key.has(key):
				worker_index = _scheduled_worker_by_key[key]
			_mark_tile_ready(_cell_by_key[key], _tick, "worker", worker_index)
		else:
			still_pending.append(key)
	_pending_keys = still_pending


func _schedule_prefetch(center_cell: Vector2i) -> void:
	if _variant_name == VARIANT_PRE_PINNED:
		return

	var cells: Array[Vector2i] = _cells_in_radius(center_cell, PREFETCH_RADIUS)
	for cell in cells:
		var key: String = _key_for_cell(cell)
		if _ready_tick_by_key.has(key) or _scheduled_ready_tick_by_key.has(key):
			continue
		_schedule_worker_job(cell)


func _schedule_worker_job(cell: Vector2i) -> void:
	var key: String = _key_for_cell(cell)
	var worker_index: int = _enqueue_sequence % maxi(_worker_count, 1)
	var available_tick: int = _worker_available_tick[worker_index]
	var start_tick: int = maxi(_tick, available_tick)
	var duration_ticks: int = _build_duration_ticks(cell, _worker_count, _enqueue_sequence)
	var ready_tick: int = start_tick + duration_ticks
	_worker_available_tick[worker_index] = ready_tick
	_scheduled_ready_tick_by_key[key] = ready_tick
	_scheduled_worker_by_key[key] = worker_index
	_pending_keys.append(key)
	_enqueue_sequence += 1


func _build_duration_ticks(cell: Vector2i, worker_count: int, sequence: int) -> int:
	var mixed: int = (
		cell.x * 73856093
		+ cell.y * 19349663
		+ worker_count * 83492791
		+ sequence * 2654435761
	)
	return 2 + _positive_mod(mixed, 31)


func _mark_tile_ready(cell: Vector2i, ready_tick: int, source: String, worker_index: int) -> void:
	var key: String = _key_for_cell(cell)
	if _ready_tick_by_key.has(key):
		return

	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(TILE_SIZE_M, SLAB_THICKNESS_M, TILE_SIZE_M)
	_shape_by_key[key] = shape
	_height_by_key[key] = _height_for_cell(cell)
	_ready_tick_by_key[key] = ready_tick
	if source == "worker":
		_worker_ready_cells.append(cell)
	_ready_order.append({
		"tick": ready_tick,
		"cell": _cell_to_array(cell),
		"key": key,
		"source": source,
		"worker": worker_index
	})


func _activate_ready_cells(center_cell: Vector2i) -> void:
	var desired_cells: Array[Vector2i] = _cells_in_radius(center_cell, ACTIVE_RADIUS)
	var ready_pending: Array[Vector2i] = []
	var not_ready_count: int = 0
	for cell in desired_cells:
		var key: String = _key_for_cell(cell)
		if _body_by_key.has(key):
			continue
		if _ready_tick_by_key.has(key):
			ready_pending.append(cell)
		else:
			not_ready_count += 1
	_missed_activation_due_not_ready += not_ready_count
	if ready_pending.is_empty():
		return

	_sort_cells(ready_pending)
	var activation_count: int = mini(ready_pending.size(), ACTIVATION_CAP_PER_TICK)
	if activation_count > ACTIVATION_CAP_PER_TICK:
		_activation_cap_respected = false
	var selected_cells: Array[Vector2i] = []
	for index in range(activation_count):
		selected_cells.append(ready_pending[index])
	_activation_sorted_per_tick = _activation_sorted_per_tick and _cells_are_sorted(selected_cells)
	for cell in selected_cells:
		_activate_cell(cell)


func _activate_cell(cell: Vector2i) -> void:
	var key: String = _key_for_cell(cell)
	if not _shape_by_key.has(key) or not _height_by_key.has(key):
		return

	var shape: BoxShape3D = _shape_by_key[key]
	var height: float = _height_by_key[key]
	var origin: Vector3 = Vector3(
		(float(cell.x) + 0.5) * TILE_SIZE_M,
		height - SLAB_THICKNESS_M * 0.5,
		(float(cell.y) + 0.5) * TILE_SIZE_M
	)
	var body_rid: RID = PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(body_rid, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_collision_layer(body_rid, 1)
	PhysicsServer3D.body_set_collision_mask(body_rid, 1)
	PhysicsServer3D.body_add_shape(body_rid, shape.get_rid(), Transform3D(Basis(), origin))
	PhysicsServer3D.body_set_space(body_rid, get_world_3d().space)

	_body_by_key[key] = body_rid
	_activated_cells.append(cell)
	_activation_tick_by_key[key] = _tick
	_activation_order.append({
		"tick": _tick,
		"cell": _cell_to_array(cell),
		"key": key
	})


func _sample_trace_if_needed(center_cell: Vector2i) -> void:
	var center_changed: bool = center_cell != _last_center_cell
	var is_interval: bool = _tick % TRACE_INTERVAL_TICKS == 0
	var is_startup: bool = _tick <= 8
	var is_final: bool = _tick == RUN_TICKS
	if not center_changed and not is_interval and not is_startup and not is_final:
		return

	var position: Vector3 = _proxy_position_for_tick(_tick)
	var expected_cell: Vector2i = _cell_for_position(position)
	var expected_height: float = _height_for_cell(expected_cell)
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()
	query.from = Vector3(position.x, RAY_START_Y_M, position.z)
	query.to = Vector3(position.x, RAY_END_Y_M, position.z)
	query.collision_mask = 1

	var hit: Dictionary[Variant, Variant] = get_world_3d().direct_space_state.intersect_ray(query)
	var hit_position: Vector3 = Vector3.ZERO
	var hit_y: Variant = null
	var height_error: Variant = null
	if hit.has("position"):
		hit_position = hit["position"] as Vector3
		hit_y = hit_position.y
		height_error = hit_position.y - expected_height

	_trace.append({
		"tick": _tick,
		"center_cell": _cell_to_array(center_cell),
		"position_xz": [_round_float(position.x), _round_float(position.z)],
		"expected_cell": _cell_to_array(expected_cell),
		"expected_height": _round_float(expected_height),
		"hit": not hit.is_empty(),
		"hit_y": hit_y if hit_y == null else _round_float(float(hit_y)),
		"height_error": height_error if height_error == null else _round_float(float(height_error)),
		"active_tiles": _body_by_key.size(),
		"ready_tiles": _ready_tick_by_key.size()
	})


func _finish_run() -> void:
	_completion_started = true
	set_physics_process(false)
	final_result = {
		"variant": _variant_name,
		"workers": _worker_count,
		"run_index": _run_index,
		"tile_size_m": TILE_SIZE_M,
		"active_radius": ACTIVE_RADIUS,
		"prefetch_radius": PREFETCH_RADIUS,
		"activation_cap_per_tick": ACTIVATION_CAP_PER_TICK,
		"proxy_speed_mps": PROXY_SPEED_MPS,
		"run_ticks": RUN_TICKS,
		"grid": {
			"min": [GRID_MIN_X, GRID_MIN_Y],
			"max": [GRID_MAX_X, GRID_MAX_Y],
			"count": _cell_by_key.size()
		},
		"ready_order": _ready_order,
		"ready_worker_order_is_cell_sorted": _ready_worker_order_is_cell_sorted(),
		"activation_order": _activation_order,
		"activation_count": _activation_order.size(),
		"activation_ticks_sorted": _activation_ticks_sorted(),
		"activation_sorted_per_tick": _activation_sorted_per_tick,
		"activation_cap_respected": _activation_cap_respected,
		"missed_activation_due_not_ready": _missed_activation_due_not_ready,
		"trace": _trace
	}
	_cleanup_bodies()
	sim_completed_run.emit()


func _cleanup_bodies() -> void:
	for key in _body_by_key.keys():
		var rid: RID = _body_by_key[String(key)]
		if rid.is_valid():
			PhysicsServer3D.body_set_space(rid, RID())
			PhysicsServer3D.free_rid(rid)
	_body_by_key.clear()


func _activation_ticks_sorted() -> Array[Variant]:
	var activated_cells: Array[Vector2i] = []
	for cell in _activated_cells:
		activated_cells.append(cell)
	_sort_cells(activated_cells)

	var records: Array[Variant] = []
	for cell in activated_cells:
		var key: String = _key_for_cell(cell)
		var tick_value: int = -1
		if _activation_tick_by_key.has(key):
			tick_value = _activation_tick_by_key[key]
		records.append({
			"cell": _cell_to_array(cell),
			"key": key,
			"tick": tick_value
		})
	return records


func _ready_worker_order_is_cell_sorted() -> bool:
	var worker_cells: Array[Vector2i] = []
	for cell in _worker_ready_cells:
		worker_cells.append(cell)
	if worker_cells.size() <= 1:
		return true
	return _cells_are_sorted(worker_cells)


func _all_grid_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for cell_x in range(GRID_MIN_X, GRID_MAX_X + 1):
		for cell_y in range(GRID_MIN_Y, GRID_MAX_Y + 1):
			cells.append(Vector2i(cell_x, cell_y))
	_sort_cells(cells)
	return cells


func _cells_in_radius(center_cell: Vector2i, radius: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for cell_x in range(center_cell.x - radius, center_cell.x + radius + 1):
		for cell_y in range(center_cell.y - radius, center_cell.y + radius + 1):
			var cell: Vector2i = Vector2i(cell_x, cell_y)
			if _cell_in_grid(cell):
				cells.append(cell)
	_sort_cells(cells)
	return cells


func _cell_in_grid(cell: Vector2i) -> bool:
	return (
		cell.x >= GRID_MIN_X
		and cell.x <= GRID_MAX_X
		and cell.y >= GRID_MIN_Y
		and cell.y <= GRID_MAX_Y
	)


func _center_cell_for_tick(tick: int) -> Vector2i:
	return _cell_for_position(_proxy_position_for_tick(tick))


func _proxy_position_for_tick(tick: int) -> Vector3:
	var seconds: float = float(tick) / float(PHYSICS_TICKS_PER_SECOND)
	return Vector3(START_X_M + PROXY_SPEED_MPS * seconds, 0.0, PROXY_Z_M)


func _cell_for_position(position: Vector3) -> Vector2i:
	return Vector2i(int(floor(position.x / TILE_SIZE_M)), int(floor(position.z / TILE_SIZE_M)))


func _height_for_cell(cell: Vector2i) -> float:
	return sin(float(cell.x) * 0.37) * 0.35 + cos(float(cell.y) * 0.41) * 0.22 + float(_positive_mod(cell.x - cell.y, 5)) * 0.015


func _sort_cells(cells: Array[Vector2i]) -> void:
	cells.sort_custom(Callable(self, "_cell_less"))


func _cell_less(left: Vector2i, right: Vector2i) -> bool:
	if left.x == right.x:
		return left.y < right.y
	return left.x < right.x


func _cells_are_sorted(cells: Array[Vector2i]) -> bool:
	if cells.size() <= 1:
		return true
	for index in range(1, cells.size()):
		if _cell_less(cells[index], cells[index - 1]):
			return false
	return true


func _key_for_cell(cell: Vector2i) -> String:
	return str(cell.x) + "," + str(cell.y)


func _cell_to_array(cell: Vector2i) -> Array[int]:
	return [cell.x, cell.y]


func _positive_mod(value: int, modulus: int) -> int:
	var result: int = value % modulus
	if result < 0:
		result += modulus
	return result


func _round_float(value: float) -> float:
	return snappedf(value, 0.000001)
