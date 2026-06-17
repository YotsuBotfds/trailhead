extends Node3D

const HEIGHTMAP_FLOAT_BYTE_SIZE: int = 4
const DEFAULT_COLLISION_LAYER: int = 1
const DEFAULT_COLLISION_MASK: int = 1
const TILE_KEY_SEPARATOR: String = "_"
const HEIGHTMAP_SIDE_CAR_PATH: String = "tile.json"
const HEIGHTMAP_BIN_PATH: String = "heightmap.bin"
const DEFAULT_WORKER_COUNT: int = 1

var _region_id: String = ""
var _followed_node: Node3D = null
var _fixed_world_position: Vector3 = Vector3.ZERO
var _use_fixed_world_position: bool = false
var _last_sampled_world_position: Vector3 = Vector3.ZERO
var _has_last_sampled_world_position: bool = false
var _streaming_enabled: bool = false
var _current_cell: Vector2i = Vector2i.ZERO
var _stream_generation: int = 0
var _stream_tick: int = 0
var _worker_count: int = DEFAULT_WORKER_COUNT
var _forced_unready_ticks_by_cell: Dictionary[Vector2i, int] = {}

var _ready_flags: Dictionary[Vector2i, bool] = {}
var _heightmap_data_by_cell: Dictionary[Vector2i, Dictionary] = {}
var _active_shapes_by_cell: Dictionary[Vector2i, HeightMapShape3D] = {}
var _active_bodies_by_cell: Dictionary[Vector2i, RID] = {}
var _activated_ticks_by_cell: Dictionary[Vector2i, int] = {}
var _load_failures_by_cell: Dictionary[Vector2i, String] = {}
var _queued_builds: Dictionary[Vector2i, bool] = {}
var _cancelled_builds: Dictionary[Vector2i, bool] = {}
var _last_to_load: Array[Vector2i] = []
var _last_to_unload: Array[Vector2i] = []
var _workers: Array[Thread] = []
var _work_mutex: Mutex = Mutex.new()
var _work_semaphore: Semaphore = Semaphore.new()
var _result_semaphore: Semaphore = Semaphore.new()
var _worker_should_stop: bool = false
var _build_queue: Array[Variant] = []
var _result_queue: Array[Variant] = []


func _ready() -> void:
	set_physics_process(false)


func _exit_tree() -> void:
	reset()


func configure_region(new_region_id: String, vehicle_node: Node3D) -> void:
	reset()
	_region_id = new_region_id
	_followed_node = vehicle_node
	_use_fixed_world_position = false
	_streaming_enabled = true
	_start_workers()
	set_physics_process(true)


func configure_fixed_position(new_region_id: String, world_position: Vector3) -> void:
	reset()
	_region_id = new_region_id
	_fixed_world_position = world_position
	_use_fixed_world_position = true
	_streaming_enabled = true
	_start_workers()
	set_physics_process(true)


func set_fixed_world_position(world_position: Vector3) -> void:
	_fixed_world_position = world_position


func set_worker_count_for_tests(worker_count: int) -> void:
	_worker_count = maxi(worker_count, 0)


func is_streaming_enabled() -> bool:
	return _streaming_enabled


func is_collision_ready_at(world_position: Vector3) -> bool:
	return _active_bodies_by_cell.has(_cell_for_world_position(world_position))


func is_collision_settled_at(world_position: Vector3) -> bool:
	var cell: Vector2i = _cell_for_world_position(world_position)
	if not _active_bodies_by_cell.has(cell):
		return false
	if not _activated_ticks_by_cell.has(cell):
		return false
	return _stream_tick > _activated_ticks_by_cell[cell]


func collision_activation_tick_at(world_position: Vector3) -> int:
	var cell: Vector2i = _cell_for_world_position(world_position)
	if not _activated_ticks_by_cell.has(cell):
		return -1
	return _activated_ticks_by_cell[cell]


func current_stream_tick() -> int:
	return _stream_tick


func region_id() -> String:
	return _region_id


func force_collision_unready_for_tests(cells: Array[Vector2i], delay_ticks: int) -> void:
	var sorted_cells: Array[Vector2i] = _copy_cells(cells)
	_sort_cells(sorted_cells)
	var safe_delay_ticks: int = maxi(delay_ticks, 0)
	for cell in sorted_cells:
		if safe_delay_ticks > 0:
			_forced_unready_ticks_by_cell[cell] = safe_delay_ticks
		else:
			_forced_unready_ticks_by_cell.erase(cell)
		_deactivate_cell_for_tests(cell)


func reset() -> void:
	set_physics_process(false)
	_stop_workers()
	_streaming_enabled = false
	_stream_generation += 1
	_stream_tick = 0
	_region_id = ""
	_followed_node = null
	_use_fixed_world_position = false
	_last_sampled_world_position = Vector3.ZERO
	_has_last_sampled_world_position = false
	_last_to_load.clear()
	_last_to_unload.clear()
	_unload_all_active_bodies()
	_ready_flags.clear()
	_heightmap_data_by_cell.clear()
	_active_shapes_by_cell.clear()
	_activated_ticks_by_cell.clear()
	_load_failures_by_cell.clear()
	_queued_builds.clear()
	_cancelled_builds.clear()
	_forced_unready_ticks_by_cell.clear()
	_clear_worker_queues()


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
	_stream_tick += 1

	var sampled_world_position: Vector3 = _sample_world_position()
	_current_cell = _cell_for_world_position(sampled_world_position)
	var desired_active_cells: Array[Vector2i] = _cells_in_radius(_current_cell, GameConfig.STREAM_ACTIVE_RADIUS)
	var desired_prefetch_cells: Array[Vector2i] = _prefetch_cells_for_sample(sampled_world_position, _current_cell)
	var current_active_cells: Array[Vector2i] = _sorted_body_cells()

	_last_to_load = _cell_difference(desired_active_cells, current_active_cells)
	_last_to_unload = _cell_difference(current_active_cells, desired_active_cells)

	_drain_worker_results()
	_process_unloads(_last_to_unload)
	_forget_ready_cells_outside_prefetch(desired_prefetch_cells)
	_cancel_prefetch_builds_outside(desired_prefetch_cells)
	_enqueue_builds_for_cells(desired_prefetch_cells)
	if _workers.is_empty():
		_process_build_queue_synchronously()
	_drain_worker_results()
	_process_loads(_last_to_load)
	_record_sampled_world_position(sampled_world_position)


func _process_unloads(cells: Array[Vector2i]) -> void:
	for cell in cells:
		if not _active_bodies_by_cell.has(cell):
			continue
		var body_rid: RID = _active_bodies_by_cell[cell]
		if body_rid.is_valid():
			PhysicsServer3D.body_set_space(body_rid, RID())
			PhysicsServer3D.free_rid(body_rid)
		_active_bodies_by_cell.erase(cell)
		_active_shapes_by_cell.erase(cell)
		_activated_ticks_by_cell.erase(cell)
		_ready_flags.erase(cell)
		_heightmap_data_by_cell.erase(cell)
		_cancel_build(cell)
		EventBus.world_tile_evicted.emit(cell)


func _process_loads(cells: Array[Vector2i]) -> void:
	var missing_cells: Array[Vector2i] = []
	for cell in cells:
		if not _ready_flags.has(cell):
			_enqueue_build(cell)
			missing_cells.append(cell)
	if not missing_cells.is_empty():
		return
	for cell in cells:
		if _should_withhold_activation_for_tests(cell):
			continue
		_activate_cell(cell)


func _activate_cell(cell: Vector2i) -> void:
	if _active_bodies_by_cell.has(cell):
		return
	if not _heightmap_data_by_cell.has(cell):
		return

	var shape: HeightMapShape3D = _shape_from_heightmap_data(_heightmap_data_by_cell[cell])
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
	_active_shapes_by_cell[cell] = shape
	_activated_ticks_by_cell[cell] = _stream_tick
	EventBus.world_tile_activated.emit(cell)


func _shape_from_heightmap_data(heightmap_data: Dictionary) -> HeightMapShape3D:
	var shape: HeightMapShape3D = HeightMapShape3D.new()
	shape.map_width = int(heightmap_data["width"])
	shape.map_depth = int(heightmap_data["depth"])
	shape.map_data = heightmap_data["map_data"] as PackedFloat32Array
	return shape


func _load_heightmap_data(cell: Vector2i, sidecar_path: String, heightmap_path: String) -> Dictionary:
	var result: Dictionary = {
		"ok": false,
		"cell": cell,
		"message": "",
		"width": 0,
		"depth": 0,
		"map_data": PackedFloat32Array(),
	}
	if not FileAccess.file_exists(sidecar_path):
		result["message"] = "missing tile sidecar: " + sidecar_path
		return result

	var file: FileAccess = FileAccess.open(sidecar_path, FileAccess.READ)
	if file == null:
		result["message"] = "could not open tile sidecar: " + sidecar_path
		return result
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		result["message"] = "tile sidecar is not a JSON object: " + sidecar_path
		return result

	var sidecar: Dictionary[Variant, Variant] = parsed as Dictionary[Variant, Variant]
	if not sidecar.has("heightmap"):
		result["message"] = "tile sidecar missing heightmap object: " + sidecar_path
		return result
	var heightmap_info: Dictionary[Variant, Variant] = sidecar["heightmap"] as Dictionary[Variant, Variant]
	if not heightmap_info.has("shape"):
		result["message"] = "tile sidecar missing heightmap.shape: " + sidecar_path
		return result
	var shape_value: Variant = heightmap_info["shape"]
	if not (shape_value is Array):
		result["message"] = "tile sidecar heightmap.shape is not an array: " + sidecar_path
		return result
	var shape_array: Array = shape_value as Array
	if shape_array.size() != 2:
		result["message"] = "tile sidecar heightmap.shape must have two entries: " + sidecar_path
		return result

	var depth: int = int(shape_array[0])
	var width: int = int(shape_array[1])
	if width <= 1 or depth <= 1:
		result["message"] = "tile heightmap shape must be at least 2x2: " + sidecar_path
		return result

	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(heightmap_path)
	var expected_byte_count: int = width * depth * HEIGHTMAP_FLOAT_BYTE_SIZE
	if bytes.size() != expected_byte_count:
		result["message"] = (
			"heightmap byte count "
			+ str(bytes.size())
			+ " != "
			+ str(expected_byte_count)
			+ ": "
			+ heightmap_path
		)
		return result

	var map_data: PackedFloat32Array = bytes.to_float32_array()
	if map_data.size() != width * depth:
		result["message"] = "heightmap float count mismatch: " + heightmap_path
		return result

	result["ok"] = true
	result["width"] = width
	result["depth"] = depth
	result["map_data"] = map_data
	return result


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
		_heightmap_data_by_cell.erase(cell)
		EventBus.world_tile_unprefetched.emit(cell)


func _cancel_prefetch_builds_outside(desired_prefetch_cells: Array[Vector2i]) -> void:
	var queued_cells: Array[Vector2i] = []
	for cell in _queued_builds.keys():
		queued_cells.append(cell)
	_sort_cells(queued_cells)
	for cell in queued_cells:
		if desired_prefetch_cells.has(cell):
			continue
		if _active_bodies_by_cell.has(cell):
			continue
		_cancel_build(cell)


func _enqueue_builds_for_cells(cells: Array[Vector2i]) -> void:
	for cell in cells:
		_enqueue_build(cell)


func _enqueue_build(cell: Vector2i) -> void:
	if _ready_flags.has(cell):
		return
	if _active_bodies_by_cell.has(cell):
		return
	if _queued_builds.has(cell):
		return
	if _load_failures_by_cell.has(cell):
		return

	_queued_builds[cell] = true
	var job: Dictionary = {
		"cell": cell,
		"generation": _stream_generation,
		"sidecar_path": _tile_sidecar_path(cell),
		"heightmap_path": _tile_heightmap_path(cell),
	}
	_work_mutex.lock()
	_cancelled_builds.erase(cell)
	_build_queue.append(job)
	_work_mutex.unlock()
	_work_semaphore.post()


func _cancel_build(cell: Vector2i) -> void:
	if not _queued_builds.has(cell):
		return
	_queued_builds.erase(cell)
	_work_mutex.lock()
	_cancelled_builds[cell] = true
	_work_mutex.unlock()


func _drain_worker_results() -> void:
	var results: Array[Dictionary] = []
	_work_mutex.lock()
	for result in _result_queue:
		results.append(result)
	_result_queue.clear()
	_work_mutex.unlock()

	results.sort_custom(Callable(self, "_build_result_less"))
	for result in results:
		var cell: Vector2i = result["cell"] as Vector2i
		var generation: int = int(result["generation"])
		if generation != _stream_generation:
			continue
		_work_mutex.lock()
		var was_cancelled: bool = _cancelled_builds.has(cell)
		if was_cancelled:
			_cancelled_builds.erase(cell)
		_work_mutex.unlock()
		if was_cancelled:
			continue
		if not _queued_builds.has(cell):
			continue
		_queued_builds.erase(cell)
		if not bool(result["ok"]):
			_record_load_failure(cell, String(result["message"]))
			continue
		_heightmap_data_by_cell[cell] = result
		_ready_flags[cell] = true
		EventBus.world_tile_prefetched.emit(cell)


func _build_result_less(left: Dictionary, right: Dictionary) -> bool:
	var left_cell: Vector2i = left["cell"] as Vector2i
	var right_cell: Vector2i = right["cell"] as Vector2i
	return _cell_less(left_cell, right_cell)


func _start_workers() -> void:
	_stop_workers()
	_worker_should_stop = false
	if _worker_count == 0:
		return
	for _index in range(_worker_count):
		var thread: Thread = Thread.new()
		var start_error: Error = thread.start(Callable(self, "_worker_loop"))
		if start_error != OK:
			push_error("TileStreamer worker start failed: " + error_string(start_error))
			continue
		_workers.append(thread)


func _stop_workers() -> void:
	if _workers.is_empty():
		return
	_work_mutex.lock()
	_worker_should_stop = true
	_work_mutex.unlock()
	for _index in range(_workers.size()):
		_work_semaphore.post()
	for thread in _workers:
		thread.wait_to_finish()
	_workers.clear()
	_worker_should_stop = false


func _process_build_queue_synchronously() -> void:
	while true:
		var job: Dictionary = {}
		_work_mutex.lock()
		if not _build_queue.is_empty():
			job = _build_queue.pop_front() as Dictionary
		_work_mutex.unlock()

		if job.is_empty():
			return

		var cell: Vector2i = job["cell"] as Vector2i
		var generation: int = int(job["generation"])
		_work_mutex.lock()
		var should_skip: bool = _worker_should_stop or generation != _stream_generation or _cancelled_builds.has(cell)
		_work_mutex.unlock()
		if should_skip:
			continue

		var result: Dictionary = _load_heightmap_data(
			cell,
			String(job["sidecar_path"]),
			String(job["heightmap_path"])
		)
		result["generation"] = generation

		_work_mutex.lock()
		if not _worker_should_stop and generation == _stream_generation and not _cancelled_builds.has(cell):
			_result_queue.append(result)
		_work_mutex.unlock()


func _clear_worker_queues() -> void:
	_work_mutex.lock()
	_build_queue.clear()
	_result_queue.clear()
	_work_mutex.unlock()


func _worker_loop() -> void:
	while true:
		_work_semaphore.wait()

		var job: Dictionary = {}
		_work_mutex.lock()
		if _worker_should_stop:
			_work_mutex.unlock()
			return
		if not _build_queue.is_empty():
			job = _build_queue.pop_front() as Dictionary
		_work_mutex.unlock()

		if job.is_empty():
			continue

		var cell: Vector2i = job["cell"] as Vector2i
		var generation: int = int(job["generation"])
		_work_mutex.lock()
		var should_skip: bool = _worker_should_stop or generation != _stream_generation or _cancelled_builds.has(cell)
		_work_mutex.unlock()
		if should_skip:
			continue

		var result: Dictionary = _load_heightmap_data(
			cell,
			String(job["sidecar_path"]),
			String(job["heightmap_path"])
		)
		result["generation"] = generation

		_work_mutex.lock()
		if not _worker_should_stop and generation == _stream_generation and not _cancelled_builds.has(cell):
			_result_queue.append(result)
			_result_semaphore.post()
		_work_mutex.unlock()


func _unload_all_active_bodies() -> void:
	var cells: Array[Vector2i] = _sorted_body_cells()
	for cell in cells:
		var body_rid: RID = _active_bodies_by_cell[cell]
		if body_rid.is_valid():
			PhysicsServer3D.body_set_space(body_rid, RID())
			PhysicsServer3D.free_rid(body_rid)
	_active_bodies_by_cell.clear()
	_active_shapes_by_cell.clear()
	_activated_ticks_by_cell.clear()


func _sample_current_cell() -> Vector2i:
	return _cell_for_world_position(_sample_world_position())


func _sample_world_position() -> Vector3:
	if _use_fixed_world_position:
		return _fixed_world_position
	if _followed_node != null:
		return _followed_node.global_position
	return global_position


func _record_sampled_world_position(world_position: Vector3) -> void:
	_last_sampled_world_position = world_position
	_has_last_sampled_world_position = true


func _prefetch_cells_for_sample(world_position: Vector3, center_cell: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = _cells_in_radius(center_cell, GameConfig.STREAM_PREFETCH_RADIUS)
	if _use_fixed_world_position:
		return cells
	if not _has_last_sampled_world_position:
		return cells
	var travel_delta: Vector3 = world_position - _last_sampled_world_position
	travel_delta.y = 0.0
	if travel_delta.length() < GameConfig.STREAM_PREFETCH_TRAVEL_MIN_DISTANCE_M:
		return cells
	var travel_cell_step: Vector2i = _travel_cell_step(travel_delta)
	if travel_cell_step == Vector2i.ZERO:
		return cells
	var lookahead_cells: int = maxi(GameConfig.STREAM_PREFETCH_TRAVEL_LOOKAHEAD_CELLS, 0)
	for step in range(1, lookahead_cells + 1):
		var bias_center: Vector2i = center_cell + Vector2i(travel_cell_step.x * step, travel_cell_step.y * step)
		_append_unique_cells(cells, _cells_in_radius(bias_center, GameConfig.STREAM_ACTIVE_RADIUS))
	_sort_cells(cells)
	return cells


func _travel_cell_step(travel_delta: Vector3) -> Vector2i:
	if absf(travel_delta.x) >= absf(travel_delta.z):
		if absf(travel_delta.x) < GameConfig.STREAM_PREFETCH_TRAVEL_MIN_DISTANCE_M:
			return Vector2i.ZERO
		return Vector2i(int(signf(travel_delta.x)), 0)
	if absf(travel_delta.z) < GameConfig.STREAM_PREFETCH_TRAVEL_MIN_DISTANCE_M:
		return Vector2i.ZERO
	return Vector2i(0, int(signf(travel_delta.z)))


func _append_unique_cells(cells: Array[Vector2i], cells_to_add: Array[Vector2i]) -> void:
	for cell in cells_to_add:
		if not cells.has(cell):
			cells.append(cell)


func _should_withhold_activation_for_tests(cell: Vector2i) -> bool:
	if not _forced_unready_ticks_by_cell.has(cell):
		return false
	var remaining_ticks: int = _forced_unready_ticks_by_cell[cell]
	if remaining_ticks <= 0:
		_forced_unready_ticks_by_cell.erase(cell)
		return false
	_forced_unready_ticks_by_cell[cell] = remaining_ticks - 1
	return true


func _deactivate_cell_for_tests(cell: Vector2i) -> void:
	if not _active_bodies_by_cell.has(cell):
		return
	var body_rid: RID = _active_bodies_by_cell[cell]
	if body_rid.is_valid():
		PhysicsServer3D.body_set_space(body_rid, RID())
		PhysicsServer3D.free_rid(body_rid)
	_active_bodies_by_cell.erase(cell)
	_active_shapes_by_cell.erase(cell)
	_activated_ticks_by_cell.erase(cell)


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
