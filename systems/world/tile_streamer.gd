extends Node3D

const HEIGHTMAP_FLOAT_BYTE_SIZE: int = 4
const DEFAULT_COLLISION_LAYER: int = 1
const DEFAULT_COLLISION_MASK: int = 1
const TILE_KEY_SEPARATOR: String = "_"
const COLLISION_TILES_MANIFEST_PATH: String = "collision_tiles_manifest.json"
const HEIGHTMAP_SIDE_CAR_PATH: String = "tile.json"
const HEIGHTMAP_BIN_PATH: String = "heightmap.bin"
const DEFAULT_WORKER_COUNT: int = 2
# Collision builds are the gate on the streaming-collision freeze: the vehicle
# is pinned until the HeightMapShape3D for the cell it enters is built + drained.
# More production workers ⇒ that build finishes sooner ⇒ a shorter freeze. The
# ceiling is raised (was 3) to spend more of a fat host's cores on collision so
# the cell under the car never waits behind the prefetch ring. This changes only
# how MANY workers race the same build queue, never WHICH tiles exist nor the
# deterministic worker<2 activation order (those paths are worker-count agnostic
# / synchronous).
const MAX_WORKER_COUNT: int = 6
const WORKER_CORES_PER_WORKER: int = 2

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
var _worker_count: int = clampi(OS.get_processor_count() / WORKER_CORES_PER_WORKER, DEFAULT_WORKER_COUNT, MAX_WORKER_COUNT)
var _forced_unready_ticks_by_cell: Dictionary[Vector2i, int] = {}
var _withheld_cells_previous_tick: Dictionary[Vector2i, bool] = {}
var _withheld_cells_current_tick: Dictionary[Vector2i, bool] = {}
var _sort_origin_cell: Vector2i = Vector2i.ZERO
var _cell_distance_less_callable: Callable = Callable()
var _has_manifest_tile_cells: bool = false
var _manifest_tile_cells: Dictionary[Vector2i, bool] = {}

var _ready_flags: Dictionary[Vector2i, bool] = {}
var _heightmap_data_by_cell: Dictionary[Vector2i, Dictionary] = {}
var _active_shapes_by_cell: Dictionary[Vector2i, HeightMapShape3D] = {}
var _active_bodies_by_cell: Dictionary[Vector2i, RID] = {}
var _activated_ticks_by_cell: Dictionary[Vector2i, int] = {}
var _load_failures_by_cell: Dictionary[Vector2i, String] = {}
var _queued_builds: Dictionary[Vector2i, bool] = {}
var _cancelled_builds: Dictionary[Vector2i, bool] = {}
var _prebuild_queue: Array[Vector2i] = []
var _prebuilt_shapes_by_cell: Dictionary[Vector2i, HeightMapShape3D] = {}
var _pending_eviction_cells: Array[Vector2i] = []
var _pending_evictions_by_cell: Dictionary[Vector2i, bool] = {}
var _last_to_load: Array[Vector2i] = []
var _last_to_unload: Array[Vector2i] = []
var _workers: Array[Thread] = []
var _work_mutex: Mutex = Mutex.new()
var _work_semaphore: Semaphore = Semaphore.new()
var _result_semaphore: Semaphore = Semaphore.new()
var _worker_should_stop: bool = false
var _build_queue: Array[Variant] = []
var _result_queue: Array[Variant] = []
var _result_drains_remaining_this_tick: int = 0


func _ready() -> void:
	_cell_distance_less_callable = Callable(self, "_cell_distance_less")
	set_physics_process(false)


func _exit_tree() -> void:
	reset()


func configure_region(new_region_id: String, vehicle_node: Node3D) -> void:
	reset()
	_region_id = new_region_id
	_followed_node = vehicle_node
	_use_fixed_world_position = false
	_streaming_enabled = true
	_load_region_tile_manifest()
	_start_workers()
	set_physics_process(true)


func configure_fixed_position(new_region_id: String, world_position: Vector3) -> void:
	reset()
	_region_id = new_region_id
	_fixed_world_position = world_position
	_use_fixed_world_position = true
	_streaming_enabled = true
	_load_region_tile_manifest()
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


func terrain_collision_mask() -> int:
	return DEFAULT_COLLISION_LAYER


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
	_prebuild_queue.clear()
	_prebuilt_shapes_by_cell.clear()
	_pending_eviction_cells.clear()
	_pending_evictions_by_cell.clear()
	_forced_unready_ticks_by_cell.clear()
	_withheld_cells_previous_tick.clear()
	_withheld_cells_current_tick.clear()
	_sort_origin_cell = Vector2i.ZERO
	_has_manifest_tile_cells = false
	_manifest_tile_cells.clear()
	_result_drains_remaining_this_tick = 0
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
	_reset_result_drain_budget()
	_begin_withhold_tracking_tick()
	_drain_prebuild_queue()

	var sampled_world_position: Vector3 = _sample_world_position()
	_current_cell = _cell_for_world_position(sampled_world_position)
	var desired_active_cells: Array[Vector2i] = _cells_in_radius(_current_cell, GameConfig.STREAM_ACTIVE_RADIUS)
	var desired_prefetch_cells: Array[Vector2i] = _prefetch_cells_for_sample(sampled_world_position, _current_cell)
	# Production (≥2 worker, following a moving body) only: extend the prefetch
	# frontier one row EARLY, gated on the car's fractional progress through the
	# current cell, so the row of cells the ring would otherwise gain in a burst AT
	# the crossing instead joins the ring partway through the traversal and warms
	# (worker decode + main-thread prebuild) gradually under the existing per-tick
	# budgets. Merged into desired_prefetch_cells so the early row is enqueued AND
	# protected from the prefetch-eviction/cancel passes below. No-op (empty) on the
	# fixed-position / worker<2 paths, so every golden + fixture is byte-identical.
	_merge_continuous_prefetch_extension(desired_prefetch_cells, sampled_world_position, _current_cell)
	var travel_ahead_prebuild_cells: Array[Vector2i] = _travel_ahead_prebuild_cells(sampled_world_position, _current_cell)
	var current_active_cells: Array[Vector2i] = _sorted_body_cells()

	_last_to_load = _cell_difference(desired_active_cells, current_active_cells)
	_last_to_unload = _cell_difference(current_active_cells, desired_active_cells)

	_drain_worker_results()
	_prioritize_prebuilds_for_cells(travel_ahead_prebuild_cells)
	_cancel_pending_evictions_for_cells(desired_active_cells)
	_process_unloads(_last_to_unload)
	_forget_ready_cells_outside_prefetch(desired_prefetch_cells)
	_cancel_prefetch_builds_outside(desired_prefetch_cells)
	_enqueue_builds_for_cells(travel_ahead_prebuild_cells)
	_enqueue_builds_for_cells(desired_prefetch_cells)
	# Prioritize the active ring (the cell under the vehicle + its immediate
	# neighbors) ahead of the wider prefetch ring so the collision build that
	# gates the streaming freeze finishes first. Travel-ahead leads are applied
	# last → they sit at the very front, the current cell right behind. Both
	# helpers no-op when no production workers are running, so the deterministic
	# worker<2 / synchronous path is byte-identical.
	_prioritize_active_ring_builds(desired_active_cells)
	_prioritize_queued_builds_for_cells(travel_ahead_prebuild_cells)
	if _workers.is_empty():
		_process_build_queue_synchronously()
	_drain_worker_results()
	_prioritize_active_ring_prebuilds(desired_active_cells)
	_prioritize_prebuilds_for_cells(travel_ahead_prebuild_cells)
	_process_loads(_last_to_load)
	_record_sampled_world_position(sampled_world_position)


func _process_unloads(cells: Array[Vector2i]) -> void:
	for cell in cells:
		if not _active_bodies_by_cell.has(cell):
			continue
		if _pending_evictions_by_cell.has(cell):
			continue
		_pending_evictions_by_cell[cell] = true
		_pending_eviction_cells.append(cell)
	_drain_pending_evictions()


func _process_loads(cells: Array[Vector2i]) -> void:
	var has_missing_cells: bool = false
	for cell in cells:
		if not _ready_flags.has(cell):
			_enqueue_build(cell)
			has_missing_cells = true
	# Multi-worker production activates ready cells (including the cell under the
	# car) even while other cells are still building, so a fast car never stalls
	# on a fringe-cell load (the accel-freeze fix). Single-/zero-worker configs —
	# every headless golden, including the workers=1 Zion surface drives — keep
	# the original all-or-nothing gate so their deterministic baselines are
	# byte-identical.
	if _worker_count < 2 and has_missing_cells:
		return
	var checked_cells: Dictionary[Vector2i, bool] = {}
	if cells.has(_current_cell):
		checked_cells[_current_cell] = true
		if not _should_withhold_activation_for_tests(_current_cell):
			_activate_cell(_current_cell)

	var remaining_cells: Array[Vector2i] = []
	for cell in cells:
		if cell == _current_cell:
			continue
		remaining_cells.append(cell)
	_sort_cells_by_distance_from_current(remaining_cells)

	var budget_remaining: int = maxi(GameConfig.stream_collision_activations_per_tick, 1)
	for cell in remaining_cells:
		if budget_remaining <= 0:
			break
		checked_cells[cell] = true
		if _should_withhold_activation_for_tests(cell):
			continue
		if _activate_cell(cell):
			budget_remaining -= 1

	if budget_remaining <= 0:
		_activate_just_cleared_withheld_cells(remaining_cells, checked_cells)


func _activate_cell(cell: Vector2i) -> bool:
	if _active_bodies_by_cell.has(cell):
		return false
	if not _heightmap_data_by_cell.has(cell):
		return false

	var shape: HeightMapShape3D
	var prebuilt_shape: Variant = _prebuilt_shapes_by_cell.get(cell, null)
	if prebuilt_shape == null:
		if cell != _current_cell:
			_enqueue_prebuild(cell)
			return false
		shape = _shape_from_heightmap_data(_heightmap_data_by_cell[cell])
	else:
		shape = prebuilt_shape as HeightMapShape3D
		_prebuilt_shapes_by_cell.erase(cell)
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
	return true


func _shape_from_heightmap_data(heightmap_data: Dictionary) -> HeightMapShape3D:
	var shape: HeightMapShape3D = HeightMapShape3D.new()
	shape.map_width = int(heightmap_data["width"])
	shape.map_depth = int(heightmap_data["depth"])
	shape.map_data = heightmap_data["map_data"] as PackedFloat32Array
	return shape


func _load_heightmap_data(cell: Vector2i, sidecar_path: String, heightmap_path: String, build_shape: bool) -> Dictionary:
	var result: Dictionary = {
		"ok": false,
		"cell": cell,
		"message": "",
		"width": 0,
		"depth": 0,
		"map_data": PackedFloat32Array(),
		"shape": null,
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
	# Only build the HeightMapShape3D here when the caller wants it inline
	# (worker<2 / synchronous golden path). In the production ≥2-worker path the
	# build is deferred to the main-thread prebuild queue to keep the heavy
	# deferred `shape_set_data` flush off the cell-crossing physics tick.
	if build_shape:
		result["shape"] = _shape_from_heightmap_data(result)
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
		_remove_prebuild_state(cell)
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
	if _has_manifest_tile_cells and not _manifest_tile_cells.has(cell):
		return
	if _ready_flags.has(cell):
		return
	if _active_bodies_by_cell.has(cell):
		return
	if _queued_builds.has(cell):
		return
	if _load_failures_by_cell.has(cell):
		return

	_queued_builds[cell] = true
	# Production (≥2 workers) defers the HeightMapShape3D realization to the
	# MAIN-thread prebuild queue (drained as cells become ready, ahead of the
	# car) instead of building it on the worker. A worker-side `map_data =`
	# assignment is command-queued by PhysicsServer3DWrapMT and the heavy
	# heightfield `shape_set_data` build only executes later, batched, on the
	# main physics thread — that batched flush at a cell crossing IS the
	# multi-second freeze.
	# The single-/zero-worker path keeps the worker/synchronous inline build so
	# its deterministic golden baselines (activation order/ticks) stay
	# byte-identical (the shape is consumed directly at activation there).
	var build_shape_on_load: bool = _worker_count < 2
	var job: Dictionary = {
		"cell": cell,
		"generation": _stream_generation,
		"sidecar_path": _tile_sidecar_path(cell),
		"heightmap_path": _tile_heightmap_path(cell),
		"build_shape": build_shape_on_load,
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


func _prioritize_queued_builds_for_cells(cells: Array[Vector2i]) -> void:
	if _workers.is_empty():
		return
	if cells.is_empty():
		return
	_work_mutex.lock()
	for index in range(cells.size() - 1, -1, -1):
		var cell: Vector2i = cells[index]
		var priority_job_index: int = -1
		var priority_job: Dictionary = {}
		for job_index in range(_build_queue.size()):
			var job: Dictionary = _build_queue[job_index] as Dictionary
			if not job.has("cell") or not job.has("generation"):
				continue
			var job_cell: Vector2i = job["cell"] as Vector2i
			var generation: int = int(job["generation"])
			if job_cell == cell and generation == _stream_generation:
				priority_job_index = job_index
				priority_job = job
				break
		if priority_job_index < 0:
			continue
		_build_queue.remove_at(priority_job_index)
		_build_queue.push_front(priority_job)
	_work_mutex.unlock()


# Nearest-cell-first. The shared prioritizers iterate this list in REVERSE and
# push_front each match, so the farthest cell is pushed first and the current
# cell last → the current cell (then its closest neighbors) ends up at the very
# front of the build/prebuild queue.
func _active_ring_priority_order(cells: Array[Vector2i]) -> Array[Vector2i]:
	var ordered: Array[Vector2i] = _copy_cells(cells)
	_sort_origin_cell = _current_cell
	ordered.sort_custom(_cell_distance_less_callable)
	return ordered


func _prioritize_active_ring_builds(cells: Array[Vector2i]) -> void:
	if _workers.is_empty():
		return
	if cells.is_empty():
		return
	_prioritize_queued_builds_for_cells(_active_ring_priority_order(cells))


func _prioritize_active_ring_prebuilds(cells: Array[Vector2i]) -> void:
	if _workers.is_empty():
		return
	if cells.is_empty():
		return
	_prioritize_prebuilds_for_cells(_active_ring_priority_order(cells))


func _reset_result_drain_budget() -> void:
	if _workers.is_empty():
		_result_drains_remaining_this_tick = 0
		return
	_result_drains_remaining_this_tick = maxi(GameConfig.stream_collision_result_drains_per_tick, 1)


func _drain_worker_results() -> void:
	var results: Array[Dictionary] = []
	_work_mutex.lock()
	if _workers.is_empty():
		for result in _result_queue:
			results.append(result)
		_result_queue.clear()
	else:
		var budget: int = maxi(_result_drains_remaining_this_tick, 0)
		while budget > 0 and not _result_queue.is_empty():
			results.append(_result_queue.pop_front() as Dictionary)
			budget -= 1
		_result_drains_remaining_this_tick = budget
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
		var result_shape: Variant = result.get("shape", null)
		if result_shape != null and not _active_bodies_by_cell.has(cell):
			_prebuilt_shapes_by_cell[cell] = result_shape as HeightMapShape3D
		else:
			_enqueue_prebuild(cell)
		EventBus.world_tile_prefetched.emit(cell)


func _drain_prebuild_queue() -> void:
	var budget: int = _prebuild_drain_budget()
	while budget > 0 and not _prebuild_queue.is_empty():
		var cell: Vector2i = _prebuild_queue.pop_front()
		if (
			_ready_flags.has(cell)
			and _heightmap_data_by_cell.has(cell)
			and not _active_bodies_by_cell.has(cell)
			and not _prebuilt_shapes_by_cell.has(cell)
		):
			_prebuilt_shapes_by_cell[cell] = _shape_from_heightmap_data(_heightmap_data_by_cell[cell])
			budget -= 1


func _prebuild_drain_budget() -> int:
	# In the production ≥2-worker path the prebuild queue is the ONLY place the
	# HeightMapShape3D is realized (the worker no longer builds it — see
	# `_enqueue_build`), so it must keep pace with the rate cells become ready
	# (the result-drain cap). Cells become ready gradually as the car approaches
	# (the prefetch ring leads ~400 m), so draining at that cap warms them as
	# they arrive — never a backlog that bursts on a crossing tick — while the
	# fixed-position bulk fill (spawn / the workers≥2 fixture) still converges
	# inside the activation budget window. The worker<2 / synchronous path builds
	# the shape inline at load, so its prebuild queue is a no-op and keeps the
	# GameConfig per-tick budget (golden baselines unchanged).
	if _worker_count < 2:
		return maxi(GameConfig.stream_collision_prebuild_per_tick, 0)
	return maxi(GameConfig.stream_collision_result_drains_per_tick, 1)


func _enqueue_prebuild(cell: Vector2i) -> void:
	if not _can_prebuild_cell(cell):
		return
	if _prebuild_queue.has(cell):
		return
	_prebuild_queue.append(cell)


func _prioritize_prebuilds_for_cells(cells: Array[Vector2i]) -> void:
	if _workers.is_empty():
		return
	for index in range(cells.size() - 1, -1, -1):
		_prioritize_prebuild(cells[index])


func _prioritize_prebuild(cell: Vector2i) -> void:
	if not _can_prebuild_cell(cell):
		return
	_prebuild_queue.erase(cell)
	_prebuild_queue.push_front(cell)


func _can_prebuild_cell(cell: Vector2i) -> bool:
	if _active_bodies_by_cell.has(cell):
		return false
	if not _ready_flags.has(cell):
		return false
	if not _heightmap_data_by_cell.has(cell):
		return false
	if _prebuilt_shapes_by_cell.has(cell):
		return false
	return true


func _remove_prebuild_state(cell: Vector2i) -> void:
	_prebuild_queue.erase(cell)
	_prebuilt_shapes_by_cell.erase(cell)


func _cancel_pending_evictions_for_cells(cells: Array[Vector2i]) -> void:
	for cell in cells:
		_pending_evictions_by_cell.erase(cell)


func _drain_pending_evictions() -> void:
	var budget: int = maxi(GameConfig.stream_collision_evictions_per_tick, 0)
	while budget > 0 and not _pending_eviction_cells.is_empty():
		var cell: Vector2i = _pending_eviction_cells.pop_front()
		if not _pending_evictions_by_cell.has(cell):
			continue
		_pending_evictions_by_cell.erase(cell)
		_evict_cell_now(cell)
		budget -= 1


func _evict_cell_now(cell: Vector2i) -> void:
	if not _active_bodies_by_cell.has(cell):
		return
	var body_rid: RID = _active_bodies_by_cell[cell]
	if body_rid.is_valid():
		PhysicsServer3D.body_set_space(body_rid, RID())
		PhysicsServer3D.free_rid(body_rid)
	_active_bodies_by_cell.erase(cell)
	_active_shapes_by_cell.erase(cell)
	_activated_ticks_by_cell.erase(cell)
	_ready_flags.erase(cell)
	_heightmap_data_by_cell.erase(cell)
	_remove_prebuild_state(cell)
	_cancel_build(cell)
	EventBus.world_tile_evicted.emit(cell)


func _begin_withhold_tracking_tick() -> void:
	_withheld_cells_previous_tick.clear()
	for cell in _withheld_cells_current_tick.keys():
		_withheld_cells_previous_tick[cell] = true
	_withheld_cells_current_tick.clear()


func _activate_just_cleared_withheld_cells(cells: Array[Vector2i], checked_cells: Dictionary[Vector2i, bool]) -> void:
	for cell in cells:
		if checked_cells.has(cell):
			continue
		if not _withheld_cells_previous_tick.has(cell):
			continue
		checked_cells[cell] = true
		if _should_withhold_activation_for_tests(cell):
			continue
		_activate_cell(cell)


func _build_result_less(left: Dictionary, right: Dictionary) -> bool:
	var left_cell: Vector2i = left["cell"] as Vector2i
	var right_cell: Vector2i = right["cell"] as Vector2i
	return _cell_less(left_cell, right_cell)


func _load_region_tile_manifest() -> void:
	_has_manifest_tile_cells = false
	_manifest_tile_cells.clear()
	var manifest_path: String = _region_path().path_join(COLLISION_TILES_MANIFEST_PATH)
	if not FileAccess.file_exists(manifest_path):
		push_error("missing collision tile manifest: " + manifest_path)
		return
	var file: FileAccess = FileAccess.open(manifest_path, FileAccess.READ)
	if file == null:
		push_error("could not open collision tile manifest: " + manifest_path)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		push_error("collision tile manifest is not a JSON object: " + manifest_path)
		return
	var manifest: Dictionary[Variant, Variant] = parsed as Dictionary[Variant, Variant]
	if not manifest.has("tiles"):
		push_error("collision tile manifest missing tiles: " + manifest_path)
		return
	var tiles_value: Variant = manifest["tiles"]
	if not (tiles_value is Array):
		push_error("collision tile manifest tiles is not an array: " + manifest_path)
		return
	var tiles: Array = tiles_value as Array
	for tile_value in tiles:
		if not (tile_value is Array):
			push_error("collision tile manifest tile entry is not an array: " + manifest_path)
			_manifest_tile_cells.clear()
			return
		var tile: Array = tile_value as Array
		if tile.size() != 2:
			push_error("collision tile manifest tile entry must have two values: " + manifest_path)
			_manifest_tile_cells.clear()
			return
		_manifest_tile_cells[Vector2i(int(tile[0]), int(tile[1]))] = true
	_has_manifest_tile_cells = true


func _start_workers() -> void:
	_stop_workers()
	_worker_should_stop = false
	if _worker_count == 0:
		return
	var worker_priority: int = Thread.PRIORITY_NORMAL
	for _index in range(_worker_count):
		var thread: Thread = Thread.new()
		var start_error: Error = thread.start(Callable(self, "_worker_loop"), worker_priority)
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
			String(job["heightmap_path"]),
			bool(job.get("build_shape", true))
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
			String(job["heightmap_path"]),
			bool(job.get("build_shape", true))
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
	var travel_delta: Vector3 = _travel_delta_for_sample(world_position)
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


func _travel_ahead_prebuild_cells(world_position: Vector3, center_cell: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if _workers.is_empty():
		return cells
	if _use_fixed_world_position:
		return cells
	var travel_delta: Vector3 = _travel_delta_for_sample(world_position)
	if travel_delta.length() < GameConfig.STREAM_PREFETCH_TRAVEL_MIN_DISTANCE_M:
		return cells
	var travel_cell_step: Vector2i = _travel_cell_step(travel_delta)
	if travel_cell_step == Vector2i.ZERO:
		return cells
	var lead_cells: int = _speed_scaled_prebuild_lead_cells(_horizontal_speed_mps(travel_delta))
	for step in range(1, lead_cells + 1):
		cells.append(center_cell + Vector2i(travel_cell_step.x * step, travel_cell_step.y * step))
	return cells


func _merge_continuous_prefetch_extension(
	desired_prefetch_cells: Array[Vector2i],
	world_position: Vector3,
	center_cell: Vector2i
) -> void:
	# Production-only continuous frontier. The prefetch ring is keyed to the integer
	# current cell, so it gains a full leading row in one tick at every crossing —
	# that row's worker decode + main-thread prebuild burst IS the residual stall.
	# Once the car is past STREAM_CONTINUOUS_PREFETCH_LEAD_FRACTION of the way
	# through the current cell (toward the boundary it is driving at), pull the
	# prefetch ring that WILL be centered one cell ahead into the desired set so its
	# new leading row is requested early and warms gradually under the existing
	# per-tick result-drain/prebuild budgets. No-op on the fixed-position / worker<2
	# paths (golden + fixture byte-identical) and a no-op until the lead fraction is
	# crossed, so the requested cells only ever advance forward — never a set the
	# baseline paths could observe.
	if _workers.is_empty():
		return
	if _use_fixed_world_position:
		return
	var travel_delta: Vector3 = _travel_delta_for_sample(world_position)
	if travel_delta.length() < GameConfig.STREAM_PREFETCH_TRAVEL_MIN_DISTANCE_M:
		return
	var travel_cell_step: Vector2i = _travel_cell_step(travel_delta)
	if travel_cell_step == Vector2i.ZERO:
		return
	if _cell_progress_fraction(world_position, travel_cell_step) < GameConfig.STREAM_CONTINUOUS_PREFETCH_LEAD_FRACTION:
		return
	var ahead_center: Vector2i = center_cell + travel_cell_step
	_append_unique_cells(desired_prefetch_cells, _cells_in_radius(ahead_center, GameConfig.STREAM_PREFETCH_RADIUS))
	_sort_cells(desired_prefetch_cells)


func _cell_progress_fraction(world_position: Vector3, travel_cell_step: Vector2i) -> float:
	# Fraction in [0, 1] of the way the car is through the current cell toward the
	# boundary it is driving at, along the dominant travel axis. Pure position math
	# (no wall-clock / RNG). 0 just after a crossing, ~1 just before the next one.
	var tile_size_m: float = maxf(GameConfig.STREAM_TILE_SIZE_M, 0.001)
	var axis_value: float = world_position.x
	var axis_step: int = travel_cell_step.x
	if travel_cell_step.x == 0:
		axis_value = world_position.z
		axis_step = travel_cell_step.y
	var local_fraction: float = (axis_value - floor(axis_value / tile_size_m) * tile_size_m) / tile_size_m
	local_fraction = clampf(local_fraction, 0.0, 1.0)
	if axis_step < 0:
		return 1.0 - local_fraction
	return local_fraction


func _travel_delta_for_sample(world_position: Vector3) -> Vector3:
	if not _workers.is_empty():
		var followed_velocity: Vector3 = _followed_horizontal_velocity()
		if followed_velocity.length() > 0.0:
			return followed_velocity * GameConfig.FIXED_DT
	if not _has_last_sampled_world_position:
		return Vector3.ZERO
	var travel_delta: Vector3 = world_position - _last_sampled_world_position
	travel_delta.y = 0.0
	return travel_delta


func _followed_horizontal_velocity() -> Vector3:
	if _use_fixed_world_position:
		return Vector3.ZERO
	if _followed_node == null:
		return Vector3.ZERO
	var rigid_body: RigidBody3D = _followed_node as RigidBody3D
	if rigid_body != null:
		return Vector3(rigid_body.linear_velocity.x, 0.0, rigid_body.linear_velocity.z)
	var character_body: CharacterBody3D = _followed_node as CharacterBody3D
	if character_body != null:
		return Vector3(character_body.velocity.x, 0.0, character_body.velocity.z)
	return Vector3.ZERO


func _horizontal_speed_mps(travel_delta: Vector3) -> float:
	if not _workers.is_empty():
		var followed_velocity: Vector3 = _followed_horizontal_velocity()
		if followed_velocity.length() > 0.0:
			return followed_velocity.length()
	if not _has_last_sampled_world_position:
		return 0.0
	return travel_delta.length() / maxf(GameConfig.FIXED_DT, 0.001)


func _speed_scaled_prebuild_lead_cells(horizontal_speed_mps: float) -> int:
	if horizontal_speed_mps <= 0.0:
		return 0
	var speed_ratio: float = clampf(horizontal_speed_mps / maxf(GameConfig.max_speed, 0.001), 0.0, 1.0)
	var radius: int = maxi(GameConfig.STREAM_PREFETCH_RADIUS, 0)
	var lead_cells: int = int(ceilf(float(radius) * speed_ratio))
	return clampi(lead_cells, 0, radius)


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
	_withheld_cells_current_tick[cell] = true
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


func _sort_cells_by_distance_from_current(cells: Array[Vector2i]) -> void:
	_sort_origin_cell = _current_cell
	cells.sort_custom(_cell_distance_less_callable)


func _cell_less(left: Vector2i, right: Vector2i) -> bool:
	if left.x == right.x:
		return left.y < right.y
	return left.x < right.x


func _cell_distance_less(left: Vector2i, right: Vector2i) -> bool:
	var left_distance: int = maxi(absi(left.x - _sort_origin_cell.x), absi(left.y - _sort_origin_cell.y))
	var right_distance: int = maxi(absi(right.x - _sort_origin_cell.x), absi(right.y - _sort_origin_cell.y))
	if left_distance == right_distance:
		return _cell_less(left, right)
	return left_distance < right_distance


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
