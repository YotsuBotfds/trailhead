extends Node3D

const TerrainVisualBuilderScript: GDScript = preload("res://systems/render/terrain_visual_builder.gd")
const MAX_BUILD_WORKERS: int = 4
const MIDLOD_COMMIT_BUDGET_PER_FRAME: int = 2


class FoliageSubcommit:
	var cell: Vector2i = Vector2i.ZERO
	var cell_data: Variant = null
	var species_data: Variant = null


# Build workers compete with the main + render threads for PHYSICAL cores. On the
# M5 (4 perf cores / 10 logical) an 8-worker pool saturated every perf core and
# starved the render thread -> multi-hundred-ms freezes during build bursts. Size
# the pool to leave cores for main+render: ~ logical/4, clamped to [2, MAX].
const DEFAULT_WORKER_COUNT: int = 2

# L4 canyon-wall silhouette densification. The far stream HLOD is the whole-region
# silhouette mesh the visual builder emits beyond REGION_STREAM_MIDLOD_RANGE_END_M,
# built at REGION_STREAM_HLOD_SAMPLE_STEP (coarse ~20m quads) so 600m cliffs read as
# rounded dunes. This streamer-local override rebuilds cliff chunks at a finer step
# so distant walls keep a sheer silhouette. Region-gated to the real Zion corridor
# (the synthetic spike_1km test region keeps the builder mesh, preserving its HLOD
# primitive budget) and variance-gated so flat floor tiles keep the cheap coarse
# mesh. Best-effort: any tile load/build failure leaves the builder's mesh in place.
# Render-only — collision stays the committed HeightMapShape3D (D30/D35); the
# builder file is not edited (foliage lanes own it).
const STREAM_HLOD_DENSIFY_REGION_ID: String = "cedar_hollow_zion"
const STREAM_HLOD_DENSIFY_MIN_HEIGHT_VARIANCE_M: float = 40.0
const STREAM_HLOD_DENSIFY_SAMPLE_STEP: int = 5

var _region_id: String = ""
var _visual_root: Node3D = null
var _detail_root: Node3D = null
var _midlod_root: Node3D = null
var _foliage_root: Node3D = null
var _hlod_instance: MeshInstance3D = null
var _stream_generation: int = 0
var _worker_count: int = clampi(OS.get_processor_count() / 4, DEFAULT_WORKER_COUNT, MAX_BUILD_WORKERS)
var _configured: bool = false
var _events_connected: bool = false
var _hlod_dirty: bool = false
var _region_cells_by_cell: Dictionary[Vector2i, bool] = {}
var _active_cells: Dictionary[Vector2i, bool] = {}
var _desired_midlod_cells_by_cell: Dictionary[Vector2i, bool] = {}
var _visual_tiles_by_cell: Dictionary[Vector2i, Node3D] = {}
var _midlod_tiles_by_cell: Dictionary[Vector2i, Node3D] = {}
var _foliage_tiles_by_cell: Dictionary[Vector2i, Node3D] = {}
var _partial_foliage_tiles_by_cell: Dictionary[Vector2i, Node3D] = {}
var _ready_tile_data_by_cell: Dictionary[Vector2i, Variant] = {}
var _ready_midlod_data_by_cell: Dictionary[Vector2i, Variant] = {}
var _ready_foliage_data_by_cell: Dictionary[Vector2i, Variant] = {}
var _load_failures_by_cell: Dictionary[Vector2i, String] = {}
var _midlod_load_failures_by_cell: Dictionary[Vector2i, String] = {}
var _queued_builds: Dictionary[Vector2i, bool] = {}
var _queued_midlod_builds: Dictionary[Vector2i, bool] = {}
var _cancelled_builds: Dictionary[Vector2i, bool] = {}
var _cancelled_midlod_builds: Dictionary[Vector2i, bool] = {}
var _commit_queue: Array[Vector2i] = []
var _midlod_commit_queue: Array[Vector2i] = []
var _queued_commits: Dictionary[Vector2i, bool] = {}
var _queued_midlod_commits: Dictionary[Vector2i, bool] = {}
var _foliage_subcommit_queue: Array[FoliageSubcommit] = []
var _pending_foliage_subcommit_counts_by_cell: Dictionary[Vector2i, int] = {}
var _pending_free_cells: Array[Vector2i] = []
var _workers: Array[Thread] = []
var _work_mutex: Mutex = Mutex.new()
var _work_semaphore: Semaphore = Semaphore.new()
var _worker_should_stop: bool = false
var _build_queue: Array[Variant] = []
var _midlod_build_queue: Array[Variant] = []
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
	_region_cells_by_cell = _region_cell_lookup(_region_id)
	_visual_root = TerrainVisualBuilderScript.build_region_stream_root(self, _region_id)
	_detail_root = _visual_root.get_node_or_null(TerrainVisualBuilderScript.REGION_DETAIL_ROOT_NAME) as Node3D
	_midlod_root = _visual_root.get_node_or_null(TerrainVisualBuilderScript.REGION_STREAM_MIDLOD_ROOT_NAME) as Node3D
	_foliage_root = _visual_root.get_node_or_null(TerrainVisualBuilderScript.REGION_STREAMED_FOLIAGE_ROOT_NAME) as Node3D
	_hlod_instance = _visual_root.get_node_or_null(TerrainVisualBuilderScript.REGION_HLOD_NAME) as MeshInstance3D
	if _detail_root == null or _midlod_root == null or _foliage_root == null:
		_load_failures_by_cell[Vector2i.ZERO] = "region stream roots missing"
		_configured = false
		return
	_apply_stream_hlod_densification()
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
	for cell in _sorted_cells(_midlod_tiles_by_cell.keys()):
		_free_midlod_cell(cell)
	for cell in _sorted_cells(_foliage_tiles_by_cell.keys()):
		_free_foliage_cell(cell)
	for cell in _sorted_cells(_partial_foliage_tiles_by_cell.keys()):
		_free_foliage_cell(cell)
	_region_cells_by_cell.clear()
	_active_cells.clear()
	_desired_midlod_cells_by_cell.clear()
	_visual_tiles_by_cell.clear()
	_midlod_tiles_by_cell.clear()
	_foliage_tiles_by_cell.clear()
	_partial_foliage_tiles_by_cell.clear()
	_ready_tile_data_by_cell.clear()
	_ready_midlod_data_by_cell.clear()
	_ready_foliage_data_by_cell.clear()
	_load_failures_by_cell.clear()
	_midlod_load_failures_by_cell.clear()
	_queued_builds.clear()
	_queued_midlod_builds.clear()
	_cancelled_builds.clear()
	_cancelled_midlod_builds.clear()
	_commit_queue.clear()
	_midlod_commit_queue.clear()
	_queued_commits.clear()
	_queued_midlod_commits.clear()
	_foliage_subcommit_queue.clear()
	_pending_foliage_subcommit_counts_by_cell.clear()
	_pending_free_cells.clear()
	_clear_worker_queues()
	_configured = false
	_region_id = ""
	_detail_root = null
	_midlod_root = null
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
	var committed_visual_tiles: int = _drain_commit_queue()
	if committed_visual_tiles <= 0:
		_drain_foliage_subcommit_queue()
	_drain_midlod_commit_queue()
	_drain_pending_frees()


func active_visual_cells() -> Array[Vector2i]:
	return _sorted_cells(_visual_tiles_by_cell.keys())


func visual_cell_count() -> int:
	return _visual_tiles_by_cell.size()


func ready_visual_cell_count() -> int:
	return _ready_tile_data_by_cell.size()


func midlod_cell_count() -> int:
	return _midlod_tiles_by_cell.size()


func active_midlod_cells() -> Array[Vector2i]:
	return _sorted_cells(_midlod_tiles_by_cell.keys())


func desired_midlod_cell_count() -> int:
	return _desired_midlod_cells_by_cell.size()


func ready_midlod_cell_count() -> int:
	return _ready_midlod_data_by_cell.size()


func ready_foliage_cell_count() -> int:
	return _ready_foliage_data_by_cell.size()


func pending_visual_commit_count() -> int:
	return _commit_queue.size()


func pending_midlod_commit_count() -> int:
	return _midlod_commit_queue.size()


func pending_midlod_build_count() -> int:
	return _queued_midlod_builds.size()


func pending_foliage_subcommit_count() -> int:
	return _foliage_subcommit_queue.size()


func foliage_cell_count() -> int:
	return _foliage_tiles_by_cell.size()


func has_ready_visual_cell(cell: Vector2i) -> bool:
	return _ready_tile_data_by_cell.has(cell)


func has_ready_midlod_cell(cell: Vector2i) -> bool:
	return _ready_midlod_data_by_cell.has(cell)


func has_ready_foliage_cell(cell: Vector2i) -> bool:
	return _ready_foliage_data_by_cell.has(cell)


func has_visual_cell(cell: Vector2i) -> bool:
	return _visual_tiles_by_cell.has(cell)


func has_midlod_cell(cell: Vector2i) -> bool:
	return _midlod_tiles_by_cell.has(cell)


func has_foliage_cell(cell: Vector2i) -> bool:
	return _foliage_tiles_by_cell.has(cell)


func visual_cell_node(cell: Vector2i) -> Node3D:
	if not _visual_tiles_by_cell.has(cell):
		return null
	return _visual_tiles_by_cell[cell]


func midlod_cell_node(cell: Vector2i) -> Node3D:
	if not _midlod_tiles_by_cell.has(cell):
		return null
	return _midlod_tiles_by_cell[cell]


func foliage_cell_node(cell: Vector2i) -> Node3D:
	if not _foliage_tiles_by_cell.has(cell):
		return null
	return _foliage_tiles_by_cell[cell]


func load_failures() -> Dictionary[Vector2i, String]:
	var copy: Dictionary[Vector2i, String] = {}
	for cell in _sorted_cells(_load_failures_by_cell.keys()):
		copy[cell] = _load_failures_by_cell[cell]
	for cell in _sorted_cells(_midlod_load_failures_by_cell.keys()):
		copy[cell] = _midlod_load_failures_by_cell[cell]
	return copy


func mark_midlod_load_failure_for_tests(cell: Vector2i, message: String) -> void:
	_midlod_load_failures_by_cell[cell] = message


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
	if not _configured or _detail_root == null or _midlod_root == null or _foliage_root == null:
		return
	_pending_free_cells.erase(cell)
	_active_cells[cell] = true
	_hlod_dirty = true
	_refresh_midlod_streaming()
	if _visual_tiles_by_cell.has(cell) and (_foliage_tiles_by_cell.has(cell) or _partial_foliage_tiles_by_cell.has(cell)):
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
	_refresh_midlod_streaming()
	_remove_queued_commit(cell)
	_remove_queued_foliage_subcommits(cell)
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
	_cancel_midlod_build(cell)
	_remove_queued_commit(cell)
	_remove_queued_midlod_commit(cell)
	_remove_queued_foliage_subcommits(cell)
	_ready_tile_data_by_cell.erase(cell)
	_ready_midlod_data_by_cell.erase(cell)
	_ready_foliage_data_by_cell.erase(cell)
	_load_failures_by_cell.erase(cell)
	_midlod_load_failures_by_cell.erase(cell)


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
		"kind": "visual",
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


func _refresh_midlod_streaming() -> void:
	if _midlod_root == null:
		return
	var desired_cells: Array[Vector2i] = _desired_midlod_cells()
	var desired_lookup: Dictionary[Vector2i, bool] = {}
	for cell in desired_cells:
		desired_lookup[cell] = true
	_desired_midlod_cells_by_cell = desired_lookup

	for cell in _sorted_cells(_midlod_tiles_by_cell.keys()):
		if not _desired_midlod_cells_by_cell.has(cell):
			_free_midlod_cell(cell)
	for cell in _sorted_cells(_ready_midlod_data_by_cell.keys()):
		if not _desired_midlod_cells_by_cell.has(cell):
			_ready_midlod_data_by_cell.erase(cell)
	for cell in _sorted_cells(_queued_midlod_builds.keys()):
		if not _desired_midlod_cells_by_cell.has(cell):
			_cancel_midlod_build(cell)
	for cell in _sorted_cells(_queued_midlod_commits.keys()):
		if not _desired_midlod_cells_by_cell.has(cell):
			_remove_queued_midlod_commit(cell)
	for cell in _sorted_cells(_midlod_load_failures_by_cell.keys()):
		if not _desired_midlod_cells_by_cell.has(cell):
			_midlod_load_failures_by_cell.erase(cell)

	var enqueued_count: int = 0
	for cell in desired_cells:
		if _midlod_tiles_by_cell.has(cell):
			continue
		if _ready_midlod_data_by_cell.has(cell):
			_enqueue_ready_midlod_commit(cell)
			continue
		if _queued_midlod_builds.has(cell) or _midlod_load_failures_by_cell.has(cell):
			continue
		_enqueue_midlod_build(cell)
		enqueued_count += 1

	if enqueued_count > 0 and _workers.is_empty():
		_process_build_queue_synchronously()
		_drain_worker_results()


func _desired_midlod_cells() -> Array[Vector2i]:
	var desired_cells: Array[Vector2i] = []
	if _active_cells.is_empty() or _region_cells_by_cell.is_empty():
		return desired_cells
	var center_cell: Vector2i = _active_cell_center()
	var tile_size_m: float = GameConfig.STREAM_TILE_SIZE_M
	var tile_radius: float = Vector2(tile_size_m, tile_size_m).length() * 0.5
	var max_distance: float = TerrainVisualBuilderScript.REGION_STREAM_MIDLOD_RANGE_END_M + tile_radius
	var cell_radius: int = maxi(int(ceil(max_distance / maxf(tile_size_m, 0.001))), 1)
	var center_xz: Vector2 = Vector2((float(center_cell.x) + 0.5) * tile_size_m, (float(center_cell.y) + 0.5) * tile_size_m)
	for y in range(center_cell.y - cell_radius, center_cell.y + cell_radius + 1):
		for x in range(center_cell.x - cell_radius, center_cell.x + cell_radius + 1):
			var cell: Vector2i = Vector2i(x, y)
			if _active_cells.has(cell):
				continue
			if not _region_cells_by_cell.has(cell):
				continue
			var cell_xz: Vector2 = Vector2((float(cell.x) + 0.5) * tile_size_m, (float(cell.y) + 0.5) * tile_size_m)
			if center_xz.distance_to(cell_xz) > max_distance:
				continue
			desired_cells.append(cell)
	desired_cells.sort_custom(Callable(self, "_cell_less"))
	return desired_cells


func _active_cell_center() -> Vector2i:
	if _active_cells.is_empty():
		return Vector2i.ZERO
	var sum_x: int = 0
	var sum_y: int = 0
	for cell in _sorted_cells(_active_cells.keys()):
		sum_x += cell.x
		sum_y += cell.y
	var count: int = maxi(_active_cells.size(), 1)
	return Vector2i(
		int(floorf(float(sum_x) / float(count) + 0.5)),
		int(floorf(float(sum_y) / float(count) + 0.5))
	)


func _enqueue_midlod_build(cell: Vector2i) -> void:
	if _midlod_tiles_by_cell.has(cell):
		return
	if _ready_midlod_data_by_cell.has(cell):
		return
	if _queued_midlod_builds.has(cell):
		return
	if _midlod_load_failures_by_cell.has(cell):
		return
	if not _desired_midlod_cells_by_cell.has(cell):
		return
	_queued_midlod_builds[cell] = true
	var job: Dictionary = {
		"cell": cell,
		"generation": _stream_generation,
		"kind": "midlod",
		"region_id": _region_id,
	}
	_work_mutex.lock()
	_cancelled_midlod_builds.erase(cell)
	_midlod_build_queue.append(job)
	_work_mutex.unlock()
	_work_semaphore.post()


func _cancel_midlod_build(cell: Vector2i) -> void:
	if not _queued_midlod_builds.has(cell):
		return
	_queued_midlod_builds.erase(cell)
	_work_mutex.lock()
	_cancelled_midlod_builds[cell] = true
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
		var kind: String = String(result.get("kind", "visual"))
		if kind == "midlod":
			_drain_midlod_worker_result(result)
			continue
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


func _drain_midlod_worker_result(result: Dictionary) -> void:
	var cell: Vector2i = result["cell"] as Vector2i
	var generation: int = int(result["generation"])
	if generation != _stream_generation:
		return
	_work_mutex.lock()
	var was_cancelled: bool = _cancelled_midlod_builds.has(cell)
	if was_cancelled:
		_cancelled_midlod_builds.erase(cell)
	_work_mutex.unlock()
	if was_cancelled:
		return
	if not _queued_midlod_builds.has(cell):
		return
	_queued_midlod_builds.erase(cell)
	if not bool(result["ok"]):
		_record_midlod_load_failure(cell, String(result["message"]))
		return
	if not _desired_midlod_cells_by_cell.has(cell):
		return
	_ready_midlod_data_by_cell[cell] = result["midlod_tile_data"]
	_enqueue_ready_midlod_commit(cell)


func _enqueue_ready_commit(cell: Vector2i) -> void:
	if _queued_commits.has(cell):
		return
	if _visual_tiles_by_cell.has(cell) and _foliage_tiles_by_cell.has(cell):
		return
	if not _ready_tile_data_by_cell.has(cell):
		return
	_queued_commits[cell] = true
	_commit_queue.append(cell)


func _enqueue_ready_midlod_commit(cell: Vector2i) -> void:
	if _queued_midlod_commits.has(cell):
		return
	if _midlod_tiles_by_cell.has(cell):
		return
	if not _ready_midlod_data_by_cell.has(cell):
		return
	if not _desired_midlod_cells_by_cell.has(cell):
		return
	_queued_midlod_commits[cell] = true
	_midlod_commit_queue.append(cell)


func _remove_queued_commit(cell: Vector2i) -> void:
	if not _queued_commits.has(cell):
		return
	_queued_commits.erase(cell)
	_commit_queue.erase(cell)


func _remove_queued_midlod_commit(cell: Vector2i) -> void:
	if not _queued_midlod_commits.has(cell):
		return
	_queued_midlod_commits.erase(cell)
	_midlod_commit_queue.erase(cell)


func _remove_queued_foliage_subcommits(cell: Vector2i) -> void:
	if _foliage_subcommit_queue.is_empty() and not _pending_foliage_subcommit_counts_by_cell.has(cell):
		return
	var retained_queue: Array[FoliageSubcommit] = []
	for subcommit in _foliage_subcommit_queue:
		if subcommit.cell != cell:
			retained_queue.append(subcommit)
	_foliage_subcommit_queue = retained_queue
	_pending_foliage_subcommit_counts_by_cell.erase(cell)


func _drain_commit_queue() -> int:
	if _commit_queue.is_empty():
		return 0
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
	return committed_count


func _drain_midlod_commit_queue() -> int:
	if _midlod_commit_queue.is_empty():
		return 0
	var commit_budget: int = maxi(MIDLOD_COMMIT_BUDGET_PER_FRAME, 1)
	_midlod_commit_queue.sort_custom(Callable(self, "_cell_less"))
	var committed_count: int = 0
	while committed_count < commit_budget and not _midlod_commit_queue.is_empty():
		var cell: Vector2i = _midlod_commit_queue.pop_front()
		_queued_midlod_commits.erase(cell)
		if not _desired_midlod_cells_by_cell.has(cell):
			_ready_midlod_data_by_cell.erase(cell)
			continue
		if not _ready_midlod_data_by_cell.has(cell):
			continue
		_commit_midlod_tile(cell, _ready_midlod_data_by_cell[cell])
		committed_count += 1
	return committed_count


func _commit_ready_cell(cell: Vector2i) -> void:
	if _ready_tile_data_by_cell.has(cell):
		_commit_visual_tile(cell, _ready_tile_data_by_cell[cell])
	if _ready_foliage_data_by_cell.has(cell) and _visual_tiles_by_cell.has(cell):
		_begin_foliage_tile_commit(cell, _ready_foliage_data_by_cell[cell])


func _drain_foliage_subcommit_queue() -> void:
	if _foliage_subcommit_queue.is_empty():
		return
	var subcommit_budget: int = maxi(GameConfig.render_visual_foliage_subcommits_per_frame, 1)
	var committed_count: int = 0
	while committed_count < subcommit_budget and not _foliage_subcommit_queue.is_empty():
		var subcommit: FoliageSubcommit = _foliage_subcommit_queue.pop_front()
		if not _active_cells.has(subcommit.cell):
			continue
		var tile_root: Node3D = null
		if _partial_foliage_tiles_by_cell.has(subcommit.cell):
			tile_root = _partial_foliage_tiles_by_cell[subcommit.cell]
		if tile_root == null:
			continue
		TerrainVisualBuilderScript.add_region_foliage_species_cell_from_data(tile_root, subcommit.cell_data, subcommit.species_data)
		_finish_foliage_subcommit(subcommit.cell)
		committed_count += 1


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


func _commit_midlod_tile(cell: Vector2i, midlod_tile_data: Variant) -> void:
	if _midlod_root == null:
		return
	if _midlod_tiles_by_cell.has(cell):
		return
	if not _desired_midlod_cells_by_cell.has(cell):
		_ready_midlod_data_by_cell.erase(cell)
		return
	var midlod_tile: MeshInstance3D = TerrainVisualBuilderScript.region_stream_midlod_tile_from_data(_midlod_root, midlod_tile_data)
	if midlod_tile == null:
		_midlod_load_failures_by_cell[cell] = "mid-LOD tile failed to load"
		return
	_midlod_tiles_by_cell[cell] = midlod_tile
	_ready_midlod_data_by_cell.erase(cell)
	_midlod_load_failures_by_cell.erase(cell)


func _update_hlod_visibility() -> void:
	var has_active_cells: bool = _active_cells.size() > 0
	if _hlod_instance != null:
		_hlod_instance.visible = has_active_cells
	if _midlod_root != null:
		_midlod_root.visible = has_active_cells


func _apply_stream_hlod_densification() -> void:
	if _region_id != STREAM_HLOD_DENSIFY_REGION_ID:
		return
	if _hlod_instance == null:
		return
	var chunks: Array[MeshInstance3D] = []
	_collect_stream_hlod_chunks(_hlod_instance, chunks)
	for chunk in chunks:
		_densify_stream_hlod_chunk(chunk)


func _collect_stream_hlod_chunks(parent: Node, chunks: Array[MeshInstance3D]) -> void:
	var mesh_instance: MeshInstance3D = parent as MeshInstance3D
	if mesh_instance != null and _is_stream_hlod_chunk(mesh_instance):
		chunks.append(mesh_instance)
	for child in parent.get_children():
		_collect_stream_hlod_chunks(child, chunks)


func _is_stream_hlod_chunk(chunk: MeshInstance3D) -> bool:
	if chunk == null or not chunk.has_meta(TerrainVisualBuilderScript.REGION_LOD_META):
		return false
	return String(chunk.get_meta(TerrainVisualBuilderScript.REGION_LOD_META)) == "stream_hlod"


func _densify_stream_hlod_chunk(chunk: MeshInstance3D) -> void:
	if chunk == null or not chunk.has_meta(TerrainVisualBuilderScript.TILE_INDEX_META):
		return
	var cell: Vector2i = Vector2i(chunk.get_meta(TerrainVisualBuilderScript.TILE_INDEX_META))
	var height_variance_m: float = _stream_hlod_tile_height_variance_m(cell)
	if height_variance_m < STREAM_HLOD_DENSIFY_MIN_HEIGHT_VARIANCE_M:
		return
	var tile_data: Variant = _load_stream_hlod_densify_tile(cell)
	if tile_data == null:
		return
	var tile_size_m: float = float(tile_data.tile_size_m)
	var tile_origin_xz: Vector2 = Vector2((float(cell.x) + 0.5) * tile_size_m, (float(cell.y) + 0.5) * tile_size_m)
	var mesh_data: Variant = TerrainVisualBuilderScript.build_region_surface_index_mesh_data(
		tile_data,
		STREAM_HLOD_DENSIFY_SAMPLE_STEP,
		String(tile_data.key) + "_stream_terrain_hlod_densify_mesh",
		tile_origin_xz
	)
	if mesh_data == null:
		return
	var mesh: ArrayMesh = TerrainVisualBuilderScript.region_mesh_from_data(mesh_data)
	if mesh == null or mesh.get_surface_count() <= 0:
		return
	chunk.mesh = mesh
	TerrainVisualBuilderScript.apply_region_mesh_instance_parameters(chunk, mesh_data)


func _stream_hlod_tile_height_variance_m(cell: Vector2i) -> float:
	var sidecar_path: String = _stream_hlod_tile_sidecar_path(cell)
	var sidecar_text: String = FileAccess.get_file_as_string(sidecar_path)
	if sidecar_text.is_empty():
		return -1.0
	var parsed: Variant = JSON.parse_string(sidecar_text)
	if not (parsed is Dictionary):
		return -1.0
	var sidecar: Dictionary = parsed as Dictionary
	var heightmap_info: Dictionary = sidecar.get("heightmap", {}) as Dictionary
	if heightmap_info == null or not heightmap_info.has("min_y") or not heightmap_info.has("max_y"):
		return -1.0
	return float(heightmap_info["max_y"]) - float(heightmap_info["min_y"])


func _load_stream_hlod_densify_tile(cell: Vector2i) -> Variant:
	var sidecar_path: String = _stream_hlod_tile_sidecar_path(cell)
	var sidecar_text: String = FileAccess.get_file_as_string(sidecar_path)
	if sidecar_text.is_empty():
		push_error("TerrainVisualStreamer HLOD densify sidecar failed to load: " + sidecar_path)
		return null
	var parsed: Variant = JSON.parse_string(sidecar_text)
	if not (parsed is Dictionary):
		push_error("TerrainVisualStreamer HLOD densify sidecar malformed: " + sidecar_path)
		return null
	var sidecar: Dictionary = parsed as Dictionary
	var heightmap_info: Dictionary = sidecar.get("heightmap", {}) as Dictionary
	var surface_info: Dictionary = sidecar.get("surface_id", {}) as Dictionary
	if heightmap_info == null or surface_info == null:
		push_error("TerrainVisualStreamer HLOD densify sidecar missing render data: " + sidecar_path)
		return null
	if not (heightmap_info.has("shape") and heightmap_info.has("path")) or not surface_info.has("path"):
		push_error("TerrainVisualStreamer HLOD densify sidecar missing shape/path: " + sidecar_path)
		return null
	var shape_value: Variant = heightmap_info["shape"]
	if not (shape_value is Array):
		push_error("TerrainVisualStreamer HLOD densify sidecar shape not array: " + sidecar_path)
		return null
	var shape_array: Array = shape_value as Array
	if shape_array.size() != 2:
		push_error("TerrainVisualStreamer HLOD densify sidecar shape size != 2: " + sidecar_path)
		return null
	var tile_directory: String = _stream_hlod_tile_directory(cell)
	var heightmap_path: String = tile_directory.path_join(String(heightmap_info["path"]))
	var surface_id_path: String = tile_directory.path_join(String(surface_info["path"]))
	var height_bytes: PackedByteArray = FileAccess.get_file_as_bytes(heightmap_path)
	var tile_size_m: float = float(sidecar.get("tile_size_m", GameConfig.STREAM_TILE_SIZE_M))
	var depth: int = int(shape_array[0])
	var width: int = int(shape_array[1])
	var expected_bytes: int = width * depth * TerrainVisualBuilderScript.HEIGHTMAP_FLOAT_BYTE_SIZE
	if height_bytes.size() != expected_bytes:
		push_error("TerrainVisualStreamer HLOD densify heightmap byte mismatch: " + heightmap_path)
		return null
	var tile_data: Variant = TerrainVisualBuilderScript.RegionTileData.new()
	tile_data.cell = cell
	tile_data.key = str(cell.x) + "_" + str(cell.y)
	tile_data.tile_size_m = tile_size_m
	tile_data.depth = depth
	tile_data.width = width
	tile_data.heightmap_path = heightmap_path
	tile_data.surface_id_path = surface_id_path
	tile_data.heights = height_bytes.to_float32_array()
	if tile_data.heights.size() != width * depth:
		push_error("TerrainVisualStreamer HLOD densify heightmap float mismatch: " + heightmap_path)
		return null
	var surface_image: Image = Image.load_from_file(ProjectSettings.globalize_path(surface_id_path))
	if surface_image == null or surface_image.is_empty():
		push_error("TerrainVisualStreamer HLOD densify surface_id image failed: " + surface_id_path)
		return null
	tile_data.surface_image = surface_image
	return tile_data


func _stream_hlod_tile_directory(cell: Vector2i) -> String:
	return GameConfig.STREAM_TILE_DATA_BASE.path_join(_region_id).path_join("tiles").path_join(str(cell.x) + "_" + str(cell.y))


func _stream_hlod_tile_sidecar_path(cell: Vector2i) -> String:
	return _stream_hlod_tile_directory(cell).path_join(TerrainVisualBuilderScript.REGION_TILE_SIDE_CAR_FILE)


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


func _begin_foliage_tile_commit(cell: Vector2i, foliage_tile_data: Variant) -> void:
	if _foliage_root == null:
		return
	if _foliage_tiles_by_cell.has(cell) or _partial_foliage_tiles_by_cell.has(cell):
		return
	if foliage_tile_data == null or not bool(foliage_tile_data.ok):
		_ready_foliage_data_by_cell.erase(cell)
		return
	var foliage_tile: Node3D = TerrainVisualBuilderScript.region_foliage_tile_root_from_data(_foliage_root, foliage_tile_data) as Node3D
	if foliage_tile == null:
		_ready_foliage_data_by_cell.erase(cell)
		return
	_partial_foliage_tiles_by_cell[cell] = foliage_tile
	_ready_foliage_data_by_cell.erase(cell)

	var subcommit_count: int = 0
	for cell_data in foliage_tile_data.cells:
		if cell_data == null:
			continue
		for species_data in cell_data.species:
			if species_data == null or bool(species_data.transforms.is_empty()):
				continue
			var subcommit: FoliageSubcommit = FoliageSubcommit.new()
			subcommit.cell = cell
			subcommit.cell_data = cell_data
			subcommit.species_data = species_data
			_foliage_subcommit_queue.append(subcommit)
			subcommit_count += 1
	if subcommit_count <= 0:
		_finish_foliage_tile_commit(cell)
		return
	_pending_foliage_subcommit_counts_by_cell[cell] = subcommit_count


func _finish_foliage_subcommit(cell: Vector2i) -> void:
	if not _pending_foliage_subcommit_counts_by_cell.has(cell):
		return
	var remaining_count: int = _pending_foliage_subcommit_counts_by_cell[cell] - 1
	if remaining_count > 0:
		_pending_foliage_subcommit_counts_by_cell[cell] = remaining_count
		return
	_finish_foliage_tile_commit(cell)


func _finish_foliage_tile_commit(cell: Vector2i) -> void:
	if not _partial_foliage_tiles_by_cell.has(cell):
		_pending_foliage_subcommit_counts_by_cell.erase(cell)
		return
	var foliage_tile: Node3D = _partial_foliage_tiles_by_cell[cell]
	_partial_foliage_tiles_by_cell.erase(cell)
	_pending_foliage_subcommit_counts_by_cell.erase(cell)
	if _active_cells.has(cell):
		_foliage_tiles_by_cell[cell] = foliage_tile
		return
	if foliage_tile != null:
		if foliage_tile.get_parent() != null:
			foliage_tile.get_parent().remove_child(foliage_tile)
		foliage_tile.queue_free()


func _record_load_failure(cell: Vector2i, message: String) -> void:
	if _load_failures_by_cell.has(cell):
		return
	_load_failures_by_cell[cell] = message
	push_error(message)


func _record_midlod_load_failure(cell: Vector2i, message: String) -> void:
	if _midlod_load_failures_by_cell.has(cell):
		return
	_midlod_load_failures_by_cell[cell] = message
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
	# Low priority in the real (windowed) game so macOS schedules build workers onto
	# efficiency cores, leaving the perf cores for main+render (kills the stutter
	# carpet). Headless test fixtures busy-loop the main thread and would starve
	# low-priority workers, so use NORMAL there.
	var worker_priority: int = Thread.PRIORITY_LOW
	if DisplayServer.get_name() == "headless":
		worker_priority = Thread.PRIORITY_NORMAL
	for _index in range(_worker_count):
		var thread: Thread = Thread.new()
		var start_error: Error = thread.start(Callable(self, "_worker_loop"), worker_priority)
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
		job = _pop_next_build_job_locked()
		_work_mutex.unlock()

		if job.is_empty():
			return

		var result: Dictionary = _build_worker_result(job)
		_work_mutex.lock()
		if not _worker_should_stop:
			_result_queue.append(result)
		_work_mutex.unlock()


func _clear_worker_queues() -> void:
	_work_mutex.lock()
	_build_queue.clear()
	_midlod_build_queue.clear()
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
		job = _pop_next_build_job_locked()
		_work_mutex.unlock()

		if job.is_empty():
			continue

		var result: Dictionary = _build_worker_result(job)
		var cell: Vector2i = result["cell"] as Vector2i
		var generation: int = int(result["generation"])
		var kind: String = String(result.get("kind", "visual"))
		_work_mutex.lock()
		if not _worker_should_stop and generation == _stream_generation and not _worker_result_is_cancelled_locked(kind, cell):
			_result_queue.append(result)
		_work_mutex.unlock()


func _pop_next_build_job_locked() -> Dictionary:
	if not _build_queue.is_empty():
		return _build_queue.pop_front() as Dictionary
	if not _midlod_build_queue.is_empty():
		return _midlod_build_queue.pop_front() as Dictionary
	return {}


func _worker_result_is_cancelled_locked(kind: String, cell: Vector2i) -> bool:
	if kind == "midlod":
		return _cancelled_midlod_builds.has(cell)
	return _cancelled_builds.has(cell)


func _build_worker_result(job: Dictionary) -> Dictionary:
	var kind: String = String(job.get("kind", "visual"))
	if kind == "midlod":
		return _build_midlod_tile_result(job)
	return _build_visual_tile_result(job)


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
			"kind": "visual",
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
		"kind": "visual",
		"message": message,
		"visual_tile_data": visual_tile_data,
		"foliage_tile_data": foliage_tile_data,
	}


func _build_midlod_tile_result(job: Dictionary) -> Dictionary:
	var cell: Vector2i = job["cell"] as Vector2i
	var generation: int = int(job["generation"])
	var region_id: String = String(job["region_id"])

	_work_mutex.lock()
	var should_skip: bool = _worker_should_stop or generation != _stream_generation or _cancelled_midlod_builds.has(cell)
	_work_mutex.unlock()
	if should_skip:
		return {
			"ok": false,
			"cell": cell,
			"generation": generation,
			"kind": "midlod",
			"message": "mid-LOD tile build cancelled: " + str(cell),
			"midlod_tile_data": null,
		}

	var midlod_tile_data: Variant = TerrainVisualBuilderScript.build_region_stream_midlod_tile_data(region_id, cell)
	var ok: bool = midlod_tile_data != null and bool(midlod_tile_data.ok)
	var message: String = ""
	if not ok and midlod_tile_data != null:
		message = String(midlod_tile_data.message)
	if message.is_empty():
		message = "mid-LOD tile failed to build: " + region_id + " " + str(cell)
	return {
		"ok": ok,
		"cell": cell,
		"generation": generation,
		"kind": "midlod",
		"message": message,
		"midlod_tile_data": midlod_tile_data,
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


func _free_midlod_cell(cell: Vector2i) -> void:
	_remove_queued_midlod_commit(cell)
	_ready_midlod_data_by_cell.erase(cell)
	_midlod_load_failures_by_cell.erase(cell)
	if not _midlod_tiles_by_cell.has(cell):
		return
	var midlod_tile: Node3D = _midlod_tiles_by_cell[cell]
	_midlod_tiles_by_cell.erase(cell)
	if midlod_tile == null:
		return
	if midlod_tile.get_parent() != null:
		midlod_tile.get_parent().remove_child(midlod_tile)
	midlod_tile.queue_free()


func _free_foliage_cell(cell: Vector2i) -> void:
	_remove_queued_foliage_subcommits(cell)
	var foliage_tile: Node3D = null
	if _foliage_tiles_by_cell.has(cell):
		foliage_tile = _foliage_tiles_by_cell[cell]
		_foliage_tiles_by_cell.erase(cell)
	elif _partial_foliage_tiles_by_cell.has(cell):
		foliage_tile = _partial_foliage_tiles_by_cell[cell]
		_partial_foliage_tiles_by_cell.erase(cell)
	if foliage_tile != null:
		if foliage_tile.get_parent() != null:
			foliage_tile.get_parent().remove_child(foliage_tile)
		foliage_tile.queue_free()


func _region_cell_lookup(region_id: String) -> Dictionary[Vector2i, bool]:
	var lookup: Dictionary[Vector2i, bool] = {}
	var cells: Array[Vector2i] = TerrainVisualBuilderScript.region_tile_cells(region_id)
	for cell in cells:
		lookup[cell] = true
	return lookup


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
