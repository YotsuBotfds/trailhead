extends Node3D

const TerrainVisualBuilderScript: GDScript = preload("res://systems/render/terrain_visual_builder.gd")
const MAX_BUILD_WORKERS: int = 4

# Build workers compete with the main + render threads for PHYSICAL cores. On the
# M5 (4 perf cores / 10 logical) an 8-worker pool saturated every perf core and
# starved the render thread -> multi-hundred-ms freezes during build bursts. Size
# the pool to leave cores for main+render: ~ logical/4, clamped to [2, MAX].
const DEFAULT_WORKER_COUNT: int = 2

var _region_id: String = ""
var _visual_root: Node3D = null
var _detail_root: Node3D = null
var _foliage_root: Node3D = null
var _hlod_instance: MeshInstance3D = null
var _stream_generation: int = 0
var _worker_count: int = clampi(OS.get_processor_count() / 4, DEFAULT_WORKER_COUNT, MAX_BUILD_WORKERS)
var _configured: bool = false
var _events_connected: bool = false
var _hlod_dirty: bool = false
var _active_cells: Dictionary[Vector2i, bool] = {}
var _visual_tiles_by_cell: Dictionary[Vector2i, Node3D] = {}
var _foliage_tiles_by_cell: Dictionary[Vector2i, Node3D] = {}
var _ready_tile_data_by_cell: Dictionary[Vector2i, Variant] = {}
var _ready_foliage_data_by_cell: Dictionary[Vector2i, Variant] = {}
var _load_failures_by_cell: Dictionary[Vector2i, String] = {}
var _queued_builds: Dictionary[Vector2i, bool] = {}
var _cancelled_builds: Dictionary[Vector2i, bool] = {}
var _commit_queue: Array[Vector2i] = []
var _queued_commits: Dictionary[Vector2i, bool] = {}
var _pending_free_cells: Array[Vector2i] = []
var _workers: Array[Thread] = []
var _work_mutex: Mutex = Mutex.new()
var _work_semaphore: Semaphore = Semaphore.new()
var _worker_should_stop: bool = false
var _build_queue: Array[Variant] = []
var _result_queue: Array[Variant] = []


func _ready() -> void:
	set_process(false)
	if _configured:
		_ensure_event_connections()


func _exit_tree() -> void:
	reset_stream()


func configure_region(new_region_id: String) -> void:
	reset_stream()
	_region_id = new_region_id
	_configured = not _region_id.is_empty()
	if not _configured:
		return
	_visual_root = TerrainVisualBuilderScript.build_region_stream_root(self, _region_id)
	_detail_root = _visual_root.get_node_or_null(TerrainVisualBuilderScript.REGION_DETAIL_ROOT_NAME) as Node3D
	_foliage_root = _visual_root.get_node_or_null(TerrainVisualBuilderScript.REGION_STREAMED_FOLIAGE_ROOT_NAME) as Node3D
	_hlod_instance = _visual_root.get_node_or_null(TerrainVisualBuilderScript.REGION_HLOD_NAME) as MeshInstance3D
	if _detail_root == null or _foliage_root == null:
		_load_failures_by_cell[Vector2i.ZERO] = "region stream roots missing"
		_configured = false
		return
	_hlod_dirty = true
	_ensure_event_connections()
	_start_workers()
	set_process(true)


func set_worker_count_for_tests(worker_count: int) -> void:
	_worker_count = maxi(worker_count, 0)
	if _configured:
		_start_workers()


func reset_stream() -> void:
	set_process(false)
	_hlod_dirty = false
	_stop_workers()
	_stream_generation += 1
	_disconnect_event_connections()
	for cell in _sorted_cells(_visual_tiles_by_cell.keys()):
		_free_visual_cell(cell)
	for cell in _sorted_cells(_foliage_tiles_by_cell.keys()):
		_free_foliage_cell(cell)
	_active_cells.clear()
	_visual_tiles_by_cell.clear()
	_foliage_tiles_by_cell.clear()
	_ready_tile_data_by_cell.clear()
	_ready_foliage_data_by_cell.clear()
	_load_failures_by_cell.clear()
	_queued_builds.clear()
	_cancelled_builds.clear()
	_commit_queue.clear()
	_queued_commits.clear()
	_pending_free_cells.clear()
	_clear_worker_queues()
	_configured = false
	_region_id = ""
	_detail_root = null
	_foliage_root = null
	_hlod_instance = null
	if _visual_root != null:
		remove_child(_visual_root)
		_visual_root.queue_free()
		_visual_root = null


func _process(_delta: float) -> void:
	if not _configured:
		return
	if _hlod_dirty:
		_update_hlod_visibility()
		_hlod_dirty = false
	if _workers.is_empty():
		_process_build_queue_synchronously()
	_drain_worker_results()
	_drain_commit_queue()
	_drain_pending_frees()


func active_visual_cells() -> Array[Vector2i]:
	return _sorted_cells(_visual_tiles_by_cell.keys())


func visual_cell_count() -> int:
	return _visual_tiles_by_cell.size()


func ready_visual_cell_count() -> int:
	return _ready_tile_data_by_cell.size()


func ready_foliage_cell_count() -> int:
	return _ready_foliage_data_by_cell.size()


func pending_visual_commit_count() -> int:
	return _commit_queue.size()


func foliage_cell_count() -> int:
	return _foliage_tiles_by_cell.size()


func has_ready_visual_cell(cell: Vector2i) -> bool:
	return _ready_tile_data_by_cell.has(cell)


func has_ready_foliage_cell(cell: Vector2i) -> bool:
	return _ready_foliage_data_by_cell.has(cell)


func has_visual_cell(cell: Vector2i) -> bool:
	return _visual_tiles_by_cell.has(cell)


func has_foliage_cell(cell: Vector2i) -> bool:
	return _foliage_tiles_by_cell.has(cell)


func visual_cell_node(cell: Vector2i) -> Node3D:
	if not _visual_tiles_by_cell.has(cell):
		return null
	return _visual_tiles_by_cell[cell]


func foliage_cell_node(cell: Vector2i) -> Node3D:
	if not _foliage_tiles_by_cell.has(cell):
		return null
	return _foliage_tiles_by_cell[cell]


func load_failures() -> Dictionary[Vector2i, String]:
	var copy: Dictionary[Vector2i, String] = {}
	for cell in _sorted_cells(_load_failures_by_cell.keys()):
		copy[cell] = _load_failures_by_cell[cell]
	return copy


func _ensure_event_connections() -> void:
	if _events_connected:
		return
	if not EventBus.world_tile_activated.is_connected(_on_world_tile_activated):
		EventBus.world_tile_activated.connect(_on_world_tile_activated)
	if not EventBus.world_tile_evicted.is_connected(_on_world_tile_evicted):
		EventBus.world_tile_evicted.connect(_on_world_tile_evicted)
	if not EventBus.world_tile_prefetched.is_connected(_on_world_tile_prefetched):
		EventBus.world_tile_prefetched.connect(_on_world_tile_prefetched)
	if not EventBus.world_tile_unprefetched.is_connected(_on_world_tile_unprefetched):
		EventBus.world_tile_unprefetched.connect(_on_world_tile_unprefetched)
	_events_connected = true


func _disconnect_event_connections() -> void:
	if not _events_connected:
		return
	if EventBus.world_tile_activated.is_connected(_on_world_tile_activated):
		EventBus.world_tile_activated.disconnect(_on_world_tile_activated)
	if EventBus.world_tile_evicted.is_connected(_on_world_tile_evicted):
		EventBus.world_tile_evicted.disconnect(_on_world_tile_evicted)
	if EventBus.world_tile_prefetched.is_connected(_on_world_tile_prefetched):
		EventBus.world_tile_prefetched.disconnect(_on_world_tile_prefetched)
	if EventBus.world_tile_unprefetched.is_connected(_on_world_tile_unprefetched):
		EventBus.world_tile_unprefetched.disconnect(_on_world_tile_unprefetched)
	_events_connected = false


func _on_world_tile_activated(cell: Vector2i) -> void:
	if not _configured or _detail_root == null or _foliage_root == null:
		return
	_pending_free_cells.erase(cell)
	_active_cells[cell] = true
	_hlod_dirty = true
	if _visual_tiles_by_cell.has(cell) and _foliage_tiles_by_cell.has(cell):
		return
	if _ready_tile_data_by_cell.has(cell):
		_enqueue_ready_commit(cell)
		return
	if _queued_builds.has(cell):
		return
	_enqueue_build(cell)
	if _workers.is_empty():
		_process_build_queue_synchronously()
		_drain_worker_results()


func _on_world_tile_evicted(cell: Vector2i) -> void:
	if not _configured:
		return
	_active_cells.erase(cell)
	_hlod_dirty = true
	_remove_queued_commit(cell)
	if not _pending_free_cells.has(cell):
		_pending_free_cells.append(cell)
	_load_failures_by_cell.erase(cell)


func _on_world_tile_prefetched(cell: Vector2i) -> void:
	if not _configured:
		return
	if _ready_tile_data_by_cell.has(cell):
		return
	if _visual_tiles_by_cell.has(cell):
		return
	if _queued_builds.has(cell):
		return
	_enqueue_build(cell)
	if _workers.is_empty():
		_process_build_queue_synchronously()
		_drain_worker_results()


func _on_world_tile_unprefetched(cell: Vector2i) -> void:
	if not _configured:
		return
	if _active_cells.has(cell):
		return
	_cancel_build(cell)
	_remove_queued_commit(cell)
	_ready_tile_data_by_cell.erase(cell)
	_ready_foliage_data_by_cell.erase(cell)
	_load_failures_by_cell.erase(cell)


func _enqueue_build(cell: Vector2i) -> void:
	if _visual_tiles_by_cell.has(cell):
		return
	if _ready_tile_data_by_cell.has(cell):
		return
	if _queued_builds.has(cell):
		return
	if _load_failures_by_cell.has(cell):
		return
	_queued_builds[cell] = true
	var job: Dictionary = {
		"cell": cell,
		"generation": _stream_generation,
		"region_id": _region_id,
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
		_ready_tile_data_by_cell[cell] = result["visual_tile_data"]
		_ready_foliage_data_by_cell[cell] = result["foliage_tile_data"]
		if _active_cells.has(cell):
			_enqueue_ready_commit(cell)


func _enqueue_ready_commit(cell: Vector2i) -> void:
	if _queued_commits.has(cell):
		return
	if _visual_tiles_by_cell.has(cell) and _foliage_tiles_by_cell.has(cell):
		return
	if not _ready_tile_data_by_cell.has(cell):
		return
	_queued_commits[cell] = true
	_commit_queue.append(cell)


func _remove_queued_commit(cell: Vector2i) -> void:
	if not _queued_commits.has(cell):
		return
	_queued_commits.erase(cell)
	_commit_queue.erase(cell)


func _drain_commit_queue() -> void:
	if _commit_queue.is_empty():
		return
	var commit_budget: int = maxi(GameConfig.render_visual_tile_commits_per_frame, 1)
	_commit_queue.sort_custom(Callable(self, "_cell_less"))
	var committed_count: int = 0
	while committed_count < commit_budget and not _commit_queue.is_empty():
		var cell: Vector2i = _commit_queue.pop_front()
		_queued_commits.erase(cell)
		if not _active_cells.has(cell):
			continue
		_commit_ready_cell(cell)
		committed_count += 1


func _commit_ready_cell(cell: Vector2i) -> void:
	if _ready_tile_data_by_cell.has(cell):
		_commit_visual_tile(cell, _ready_tile_data_by_cell[cell])
	if _ready_foliage_data_by_cell.has(cell):
		_commit_foliage_tile(cell, _ready_foliage_data_by_cell[cell])


func _drain_pending_frees() -> void:
	if _pending_free_cells.is_empty():
		return
	var free_budget: int = maxi(GameConfig.render_visual_tile_frees_per_frame, 1)
	var freed_count: int = 0
	while freed_count < free_budget and not _pending_free_cells.is_empty():
		var cell: Vector2i = _pending_free_cells.pop_front()
		_free_visual_cell(cell)
		_free_foliage_cell(cell)
		freed_count += 1


func _commit_visual_tile(cell: Vector2i, visual_tile_data: Variant) -> void:
	if _detail_root == null:
		return
	if _visual_tiles_by_cell.has(cell):
		return
	var visual_tile: MeshInstance3D = TerrainVisualBuilderScript.region_visual_tile_from_data(_detail_root, visual_tile_data, _hlod_instance)
	if visual_tile == null:
		_load_failures_by_cell[cell] = "visual tile failed to load"
		return
	_visual_tiles_by_cell[cell] = visual_tile
	_ready_tile_data_by_cell.erase(cell)
	_load_failures_by_cell.erase(cell)


func _update_hlod_visibility() -> void:
	if _hlod_instance == null:
		return
	_hlod_instance.visible = _active_cells.size() > 0


func _commit_foliage_tile(cell: Vector2i, foliage_tile_data: Variant) -> void:
	if _foliage_root == null:
		return
	if _foliage_tiles_by_cell.has(cell):
		return
	var foliage_tile: Node3D = TerrainVisualBuilderScript.region_foliage_tile_from_data(_foliage_root, foliage_tile_data) as Node3D
	if foliage_tile == null:
		_ready_foliage_data_by_cell.erase(cell)
		return
	_foliage_tiles_by_cell[cell] = foliage_tile
	_ready_foliage_data_by_cell.erase(cell)


func _record_load_failure(cell: Vector2i, message: String) -> void:
	if _load_failures_by_cell.has(cell):
		return
	_load_failures_by_cell[cell] = message
	push_error(message)


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
			push_error("TerrainVisualStreamer worker start failed: " + error_string(start_error))
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

		var result: Dictionary = _build_visual_tile_result(job)
		_work_mutex.lock()
		if not _worker_should_stop:
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

		var result: Dictionary = _build_visual_tile_result(job)
		var cell: Vector2i = result["cell"] as Vector2i
		var generation: int = int(result["generation"])
		_work_mutex.lock()
		if not _worker_should_stop and generation == _stream_generation and not _cancelled_builds.has(cell):
			_result_queue.append(result)
		_work_mutex.unlock()


func _build_visual_tile_result(job: Dictionary) -> Dictionary:
	var cell: Vector2i = job["cell"] as Vector2i
	var generation: int = int(job["generation"])
	var region_id: String = String(job["region_id"])

	_work_mutex.lock()
	var should_skip: bool = _worker_should_stop or generation != _stream_generation or _cancelled_builds.has(cell)
	_work_mutex.unlock()
	if should_skip:
		return {
			"ok": false,
			"cell": cell,
			"generation": generation,
			"message": "visual tile build cancelled: " + str(cell),
			"visual_tile_data": null,
		}

	var visual_tile_data: Variant = TerrainVisualBuilderScript.build_region_visual_tile_data(region_id, cell)
	var foliage_tile_data: Variant = TerrainVisualBuilderScript.build_region_foliage_tile_data(region_id, cell)
	var ok: bool = visual_tile_data != null and bool(visual_tile_data.ok)
	var message: String = ""
	if not ok and visual_tile_data != null:
		message = String(visual_tile_data.message)
	if ok and foliage_tile_data != null and not bool(foliage_tile_data.ok):
		message = String(foliage_tile_data.message)
	if message.is_empty():
		message = "visual tile failed to build: " + region_id + " " + str(cell)
	return {
		"ok": ok,
		"cell": cell,
		"generation": generation,
		"message": message,
		"visual_tile_data": visual_tile_data,
		"foliage_tile_data": foliage_tile_data,
	}


func _free_visual_cell(cell: Vector2i) -> void:
	if not _visual_tiles_by_cell.has(cell):
		return
	var visual_tile: Node3D = _visual_tiles_by_cell[cell]
	_visual_tiles_by_cell.erase(cell)
	if visual_tile == null:
		return
	if visual_tile.get_parent() != null:
		visual_tile.get_parent().remove_child(visual_tile)
	visual_tile.queue_free()


func _free_foliage_cell(cell: Vector2i) -> void:
	if not _foliage_tiles_by_cell.has(cell):
		return
	var foliage_tile: Node3D = _foliage_tiles_by_cell[cell]
	_foliage_tiles_by_cell.erase(cell)
	if foliage_tile == null:
		return
	if foliage_tile.get_parent() != null:
		foliage_tile.get_parent().remove_child(foliage_tile)
	foliage_tile.queue_free()


func _sorted_cells(value: Array) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for item in value:
		if item is Vector2i:
			cells.append(item)
	cells.sort_custom(Callable(self, "_cell_less"))
	return cells


func _cell_less(left: Vector2i, right: Vector2i) -> bool:
	if left.x == right.x:
		return left.y < right.y
	return left.x < right.x
