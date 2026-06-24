extends Node3D

const TerrainVisualBuilderScript: GDScript = preload("res://systems/render/terrain_visual_builder.gd")
const MAX_BUILD_WORKERS: int = 7
const MIDLOD_COMMIT_BUDGET_PER_FRAME: int = 2

# Soft per-frame wall-clock budget (RENDER host — wall-clock is allowed here; this
# never touches the deterministic sim). The commit/subcommit drains already cap how
# MANY items they process per frame, but a burst of heavy commits (e.g. the cold-start
# reveal wave or a fast crossing into fresh tiles) can still blow a single frame's
# budget and read as a multi-second hitch. Each drain commits at least one item (so it
# never deadlocks on a single fat tile) then yields the rest of its work to the next
# frame once this many microseconds of the current frame have already been spent in the
# streamer's commit phase. ~4 ms leaves the frame headroom for sim+render.
const COMMIT_FRAME_BUDGET_USEC: int = 4000


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
var _worker_count: int = clampi(OS.get_processor_count() / 2, DEFAULT_WORKER_COUNT, MAX_BUILD_WORKERS)
var _configured: bool = false
var _events_connected: bool = false
var _hlod_dirty: bool = false
var _midlod_refresh_requested: bool = false
var _region_cells_by_cell: Dictionary[Vector2i, bool] = {}
var _active_cells: Dictionary[Vector2i, bool] = {}
var _desired_midlod_cells_by_cell: Dictionary[Vector2i, bool] = {}
var _visual_tiles_by_cell: Dictionary[Vector2i, Node3D] = {}
var _midlod_tiles_by_cell: Dictionary[Vector2i, Node3D] = {}
var _foliage_tiles_by_cell: Dictionary[Vector2i, Node3D] = {}
var _partial_foliage_tiles_by_cell: Dictionary[Vector2i, Node3D] = {}
var _ready_tile_data_by_cell: Dictionary[Vector2i, Variant] = {}
var _ready_tile_step_by_cell: Dictionary[Vector2i, int] = {}
var _ready_upgrade_tile_data_by_cell: Dictionary[Vector2i, Variant] = {}
var _ready_upgrade_tile_step_by_cell: Dictionary[Vector2i, int] = {}
var _ready_midlod_data_by_cell: Dictionary[Vector2i, Variant] = {}
var _ready_foliage_data_by_cell: Dictionary[Vector2i, Variant] = {}
# Distance-graded foliage LOD (the cell-crossing-freeze lever). A foliage tile carries both
# the dense near-field LOD0 cells (~56 instances/subcell) and the sparse far-silhouette LOD1
# cells (~4/subcell). When a cell is committed while OUTSIDE render_visual_foliage_radius_cells
# of the active center, only its LOD1 subcommits are enqueued and the full tile data is RETAINED
# here so the heavy LOD0 can be materialized later — IN PLACE, no rebuild — once the cell crosses
# into the radius (_enqueue_lod0_foliage_upgrade, driven from _on_world_tile_activated). Presence
# in this dict == "this cell is committed LOD1-only and its LOD0 is still pending". Erased the
# moment LOD0 is enqueued, on eviction/unprefetch/free, and on reset. Render-only, golden-neutral.
var _deferred_lod0_foliage_data_by_cell: Dictionary[Vector2i, Variant] = {}
var _committed_tile_step_by_cell: Dictionary[Vector2i, int] = {}
var _load_failures_by_cell: Dictionary[Vector2i, String] = {}
var _midlod_load_failures_by_cell: Dictionary[Vector2i, String] = {}
var _queued_builds: Dictionary[Vector2i, bool] = {}
var _queued_build_step_by_cell: Dictionary[Vector2i, int] = {}
var _queued_build_id_by_cell: Dictionary[Vector2i, int] = {}
var _queued_midlod_builds: Dictionary[Vector2i, bool] = {}
var _cancelled_builds: Dictionary[int, bool] = {}
var _cancelled_midlod_builds: Dictionary[Vector2i, bool] = {}
var _commit_queue: Array[Vector2i] = []
var _midlod_commit_queue: Array[Vector2i] = []
var _queued_commits: Dictionary[Vector2i, bool] = {}
var _queued_midlod_commits: Dictionary[Vector2i, bool] = {}
var _foliage_subcommit_queue: Array[FoliageSubcommit] = []
var _pending_foliage_subcommit_counts_by_cell: Dictionary[Vector2i, int] = {}
# Cells whose foliage subcommits have all completed (the tile subtree is fully built,
# DETACHED in _partial_foliage_tiles_by_cell) and are waiting to attach to the live
# _foliage_root. Drained at most render_visual_foliage_tile_finishes_per_frame per frame
# so a cell crossing — where several tiles finish together — does not burst the
# RenderingServer materialization into one multi-second dt spike. Render-only.
var _foliage_finish_queue: Array[Vector2i] = []
var _queued_foliage_finishes: Dictionary[Vector2i, bool] = {}
var _pending_free_cells: Array[Vector2i] = []
var _pending_free_midlod_cells: Array[Vector2i] = []
var _stream_hlod_queue: Array[Vector2i] = []
var _queued_stream_hlod_cells: Dictionary[Vector2i, bool] = {}
var _stream_hlod_chunks_by_cell: Dictionary[Vector2i, MeshInstance3D] = {}
var _stream_hlod_densify_queue: Array[Vector2i] = []
var _queued_stream_hlod_densify_cells: Dictionary[Vector2i, bool] = {}
var _densified_stream_hlod_cells: Dictionary[Vector2i, bool] = {}
var _stream_priority_center_cell: Vector2i = Vector2i.ZERO
var _stream_priority_has_center: bool = false
var _stream_priority_forward_cell_delta: Vector2i = Vector2i.ZERO
var _workers: Array[Thread] = []
var _work_mutex: Mutex = Mutex.new()
var _work_semaphore: Semaphore = Semaphore.new()
var _worker_should_stop: bool = false
var _next_visual_build_id: int = 0
var _commit_phase_start_usec: int = 0
var _build_queue: Array[Variant] = []
var _midlod_build_queue: Array[Variant] = []
var _stream_hlod_densify_build_queue: Array[Variant] = []
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
	_queue_stream_hlod_region()
	_drain_stream_hlod_queue()
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
	_midlod_refresh_requested = false
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
	_ready_tile_step_by_cell.clear()
	_ready_upgrade_tile_data_by_cell.clear()
	_ready_upgrade_tile_step_by_cell.clear()
	_ready_midlod_data_by_cell.clear()
	_ready_foliage_data_by_cell.clear()
	_deferred_lod0_foliage_data_by_cell.clear()
	_committed_tile_step_by_cell.clear()
	_load_failures_by_cell.clear()
	_midlod_load_failures_by_cell.clear()
	_queued_builds.clear()
	_queued_build_step_by_cell.clear()
	_queued_build_id_by_cell.clear()
	_queued_midlod_builds.clear()
	_cancelled_builds.clear()
	_cancelled_midlod_builds.clear()
	_commit_queue.clear()
	_midlod_commit_queue.clear()
	_queued_commits.clear()
	_queued_midlod_commits.clear()
	_foliage_subcommit_queue.clear()
	_pending_foliage_subcommit_counts_by_cell.clear()
	_foliage_finish_queue.clear()
	_queued_foliage_finishes.clear()
	_pending_free_cells.clear()
	_pending_free_midlod_cells.clear()
	_stream_hlod_queue.clear()
	_queued_stream_hlod_cells.clear()
	_stream_hlod_chunks_by_cell.clear()
	_stream_hlod_densify_queue.clear()
	_queued_stream_hlod_densify_cells.clear()
	_densified_stream_hlod_cells.clear()
	_stream_priority_center_cell = Vector2i.ZERO
	_stream_priority_has_center = false
	_stream_priority_forward_cell_delta = Vector2i.ZERO
	_clear_worker_queues()
	_next_visual_build_id = 0
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
	# Stamp the streamer's per-frame work-phase budget window HERE, at the very top, so
	# EVERY main-thread drain below — the stream-HLOD chunk decode included — shares one
	# soft COMMIT_FRAME_BUDGET_USEC (~4 ms). Previously the stamp was set only just before
	# the commit/foliage/mid-LOD drains, so the stream-HLOD drain ran first, ungated, and
	# its per-chunk PNG/heightmap decode (Image.load_from_file + mesh build) paid full main-
	# thread cost every frame on top of the commit budget. During the cold-start title-card
	# hold that compounded across the whole region manifest (~3k coarse silhouette chunks)
	# into a multi-second boot freeze. Sharing one window means a heavy HLOD decode now
	# yields the rest of the frame's streamer work to the next frame instead of stalling.
	# Render host only — wall-clock here never feeds the deterministic sim.
	_commit_phase_start_usec = Time.get_ticks_usec()
	if _hlod_dirty:
		_update_hlod_visibility()
		_hlod_dirty = false
	_drain_stream_hlod_queue()
	_drain_stream_hlod_densify_queue()
	if _midlod_refresh_requested:
		_midlod_refresh_requested = false
		_refresh_midlod_streaming()
	if _workers.is_empty():
		_process_build_queue_synchronously()
	_drain_worker_results()
	# Drain visual tiles AND foliage subcommits every frame. The old gate only drained
	# foliage when zero visual tiles committed that frame; while driving, visual tiles
	# commit continuously, so foliage starved to a trickle and the floor ahead of the
	# moving car stayed bare. Foliage drain is already bounded by its own per-frame budget
	# (GameConfig.render_visual_foliage_subcommits_per_frame), so ungating does not uncap work.
	# The commit/subcommit/mid-LOD drains share the soft wall-clock budget stamped above
	# (COMMIT_FRAME_BUDGET_USEC), so a burst spreads across frames instead of stalling one.
	_drain_commit_queue()
	_drain_foliage_subcommit_queue()
	# Attach fully-built (detached) foliage tiles to the live root at most N per frame.
	# Runs after the subcommit drain so tiles that finished THIS frame are eligible, and
	# shares the COMMIT_FRAME_BUDGET_USEC window so the materialization burst spreads
	# instead of stalling one frame. This is the cell-crossing-freeze fix.
	_drain_foliage_finish_queue()
	_drain_midlod_commit_queue()
	_drain_pending_frees()


func _commit_frame_budget_exceeded() -> bool:
	# True once this frame's commit phase has already spent COMMIT_FRAME_BUDGET_USEC.
	# Callers always commit at least one item before consulting this, so a single fat
	# tile can never deadlock the queue — it just yields the remainder to next frame.
	# Headless fixtures busy-loop a single frame and rely on draining the whole queue
	# in one _process tick, so the budget is disabled under the headless DisplayServer.
	if DisplayServer.get_name() == "headless":
		return false
	return Time.get_ticks_usec() - _commit_phase_start_usec >= COMMIT_FRAME_BUDGET_USEC


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


func pending_foliage_finish_count() -> int:
	return _foliage_finish_queue.size()


func stream_hlod_committed_chunk_count() -> int:
	return _stream_hlod_chunks_by_cell.size()


func stream_hlod_pending_chunk_count() -> int:
	return _stream_hlod_queue.size()


func stream_hlod_manifest_chunk_count() -> int:
	return _region_cells_by_cell.size()


func foliage_cell_count() -> int:
	return _foliage_tiles_by_cell.size()


func has_ready_visual_cell(cell: Vector2i) -> bool:
	return _ready_tile_data_by_cell.has(cell)


func ready_visual_cell_sample_step(cell: Vector2i) -> int:
	return int(_ready_tile_step_by_cell.get(cell, -1))


func committed_visual_cell_sample_step(cell: Vector2i) -> int:
	return int(_committed_tile_step_by_cell.get(cell, -1))


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
	_update_stream_priority_from_active_cells()
	_hlod_dirty = true
	_resort_stream_hlod_queue()
	_queue_near_stream_hlod_densification()
	# Any cell activation can shift the active center and pull a previously LOD1-only foliage
	# tile into the dense foliage ring. Sweep the deferred set (mirrors the near-HLOD-densify
	# re-sweep above) and materialize the held-back LOD0 in place for cells that are now inside
	# render_visual_foliage_radius_cells — no rebuild, no empty pop. Render-only, golden-neutral.
	_promote_near_deferred_foliage_lod0()
	_request_midlod_refresh()
	# Decouple the heavy step-1 full-res VISUAL upgrade from the collision radius: only
	# active cells within render_visual_fullres_radius_cells (Chebyshev) of the active
	# center upgrade to full res. Outer active cells (still within STREAM_ACTIVE_RADIUS,
	# so collision is full res for them) stay at the coarse REGION_DETAIL_SAMPLE_STEP
	# visual mesh — cutting the per-cell-crossing full-res materialization and the
	# steady-state primitive count. Render-only; golden-neutral.
	var wants_fullres: bool = _is_cell_in_visual_fullres_radius(cell)
	if _visual_tiles_by_cell.has(cell):
		var committed_step: int = int(_committed_tile_step_by_cell.get(cell, TerrainVisualBuilderScript.REGION_DETAIL_SAMPLE_STEP))
		if committed_step <= TerrainVisualBuilderScript.REGION_DETAIL_FULLRES_SAMPLE_STEP:
			return
		if not wants_fullres:
			# Already committed at the coarse step and outside the full-res ring — leave
			# the coarse mesh in place (collision authority is unchanged).
			return
		if _ready_tile_data_by_cell.has(cell):
			var visible_ready_step: int = int(_ready_tile_step_by_cell.get(cell, TerrainVisualBuilderScript.REGION_DETAIL_SAMPLE_STEP))
			if visible_ready_step <= TerrainVisualBuilderScript.REGION_DETAIL_FULLRES_SAMPLE_STEP:
				_enqueue_ready_commit(cell)
				return
		_promote_ready_visual_upgrade(cell)
		_enqueue_build(cell, TerrainVisualBuilderScript.REGION_DETAIL_FULLRES_SAMPLE_STEP)
		if _workers.is_empty():
			_process_build_queue_synchronously()
			_drain_worker_results()
		return
	if _ready_tile_data_by_cell.has(cell):
		var ready_step: int = int(_ready_tile_step_by_cell.get(cell, TerrainVisualBuilderScript.REGION_DETAIL_SAMPLE_STEP))
		_enqueue_ready_commit(cell)
		if wants_fullres and ready_step > TerrainVisualBuilderScript.REGION_DETAIL_FULLRES_SAMPLE_STEP:
			_enqueue_build(cell, TerrainVisualBuilderScript.REGION_DETAIL_FULLRES_SAMPLE_STEP)
			if _workers.is_empty():
				_process_build_queue_synchronously()
				_drain_worker_results()
		return
	if _queued_builds.has(cell):
		var queued_step: int = int(_queued_build_step_by_cell.get(cell, TerrainVisualBuilderScript.REGION_DETAIL_SAMPLE_STEP))
		if queued_step <= TerrainVisualBuilderScript.REGION_DETAIL_FULLRES_SAMPLE_STEP:
			return
		# Keep the in-flight coarse prefetch. When it finishes, it can commit first
		# and seed the full-res upgrade without leaving an active-cell hole.
		return
	# Active cells are the vehicle-near loaded physics tiles (STREAM_ACTIVE_RADIUS
	# around the car). They MUST end up at full collision resolution (step=1) so the
	# visible ground matches the surface the wheels touch (the 5x downsample let the
	# visual mesh wander cm above/below the collision heightmap, reading as tire
	# sink/float). But building fullres FIRST serialized ~49 heavy step-1 GPU uploads
	# on the cold-start reveal path -> a multi-second boot freeze before the title
	# card lifts. Instead spawn the COARSE step (step=5) first so the world appears
	# fast; _drain_worker_results auto-chains the step=1 fullres UPGRADE the moment the
	# coarse build commits (see the sample_step > FULLRES branch there), so near tiles
	# still sharpen to collision-matched fullres over the next frames.
	_enqueue_build(cell, TerrainVisualBuilderScript.REGION_DETAIL_SAMPLE_STEP)
	if _workers.is_empty():
		_process_build_queue_synchronously()
		_drain_worker_results()


func _on_world_tile_evicted(cell: Vector2i) -> void:
	if not _configured:
		return
	_active_cells.erase(cell)
	_update_stream_priority_from_active_cells()
	_hlod_dirty = true
	_queue_near_stream_hlod_densification()
	_request_midlod_refresh()
	_remove_queued_commit(cell)
	_remove_queued_foliage_subcommits(cell)
	_remove_queued_foliage_finish(cell)
	_deferred_lod0_foliage_data_by_cell.erase(cell)
	_ready_upgrade_tile_data_by_cell.erase(cell)
	_ready_upgrade_tile_step_by_cell.erase(cell)
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
	# Prefetched cells are distant (beyond STREAM_ACTIVE_RADIUS): keep the cheap
	# 5x downsample (REGION_DETAIL_SAMPLE_STEP). Full-res is reserved for active
	# vehicle-near tiles (see _on_world_tile_activated).
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
	_ready_tile_step_by_cell.erase(cell)
	_ready_upgrade_tile_data_by_cell.erase(cell)
	_ready_upgrade_tile_step_by_cell.erase(cell)
	_ready_midlod_data_by_cell.erase(cell)
	_ready_foliage_data_by_cell.erase(cell)
	_deferred_lod0_foliage_data_by_cell.erase(cell)
	_committed_tile_step_by_cell.erase(cell)
	_load_failures_by_cell.erase(cell)
	_midlod_load_failures_by_cell.erase(cell)


func _enqueue_build(cell: Vector2i, sample_step: int = TerrainVisualBuilderScript.REGION_DETAIL_SAMPLE_STEP) -> void:
	if _visual_tiles_by_cell.has(cell):
		var committed_step: int = int(_committed_tile_step_by_cell.get(cell, TerrainVisualBuilderScript.REGION_DETAIL_SAMPLE_STEP))
		if committed_step <= sample_step:
			return
	if _ready_tile_data_by_cell.has(cell):
		var ready_step: int = int(_ready_tile_step_by_cell.get(cell, TerrainVisualBuilderScript.REGION_DETAIL_SAMPLE_STEP))
		if ready_step <= sample_step:
			return
	if _ready_upgrade_tile_step_by_cell.has(cell):
		var upgrade_step: int = int(_ready_upgrade_tile_step_by_cell.get(cell, TerrainVisualBuilderScript.REGION_DETAIL_SAMPLE_STEP))
		if upgrade_step <= sample_step:
			return
	if _queued_builds.has(cell):
		return
	if _load_failures_by_cell.has(cell):
		return
	_queued_builds[cell] = true
	_queued_build_step_by_cell[cell] = sample_step
	_next_visual_build_id += 1
	var build_id: int = _next_visual_build_id
	_queued_build_id_by_cell[cell] = build_id
	var job: Dictionary = {
		"build_id": build_id,
		"cell": cell,
		"generation": _stream_generation,
		"kind": "visual",
		"region_id": _region_id,
		"sample_step": sample_step,
	}
	_work_mutex.lock()
	_build_queue.append(job)
	_work_mutex.unlock()
	_work_semaphore.post()


func _cancel_build(cell: Vector2i) -> void:
	if not _queued_builds.has(cell):
		return
	var build_id: int = int(_queued_build_id_by_cell.get(cell, -1))
	_queued_builds.erase(cell)
	_queued_build_step_by_cell.erase(cell)
	_queued_build_id_by_cell.erase(cell)
	_work_mutex.lock()
	if build_id >= 0:
		_cancelled_builds[build_id] = true
	_work_mutex.unlock()


func _request_midlod_refresh() -> void:
	_midlod_refresh_requested = true


func _queue_midlod_free(cell: Vector2i) -> void:
	if _pending_free_midlod_cells.has(cell):
		return
	_pending_free_midlod_cells.append(cell)


func _refresh_midlod_streaming() -> void:
	if _midlod_root == null:
		return
	var desired_cells: Array[Vector2i] = _desired_midlod_cells()
	var desired_lookup: Dictionary[Vector2i, bool] = {}
	for cell in desired_cells:
		desired_lookup[cell] = true
		_pending_free_midlod_cells.erase(cell)
	_desired_midlod_cells_by_cell = desired_lookup

	for cell in _sorted_cells(_midlod_tiles_by_cell.keys()):
		if not _desired_midlod_cells_by_cell.has(cell):
			_queue_midlod_free(cell)
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
	var cell_radius: int = maxi(int(ceilf(max_distance / maxf(tile_size_m, 0.001))), 1)
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
		if kind == "stream_hlod_densify":
			_drain_stream_hlod_densify_worker_result(result)
			continue
		var cell: Vector2i = result["cell"] as Vector2i
		var generation: int = int(result["generation"])
		if generation != _stream_generation:
			continue
		var build_id: int = int(result.get("build_id", -1))
		_work_mutex.lock()
		var was_cancelled: bool = _cancelled_builds.has(build_id)
		if was_cancelled:
			_cancelled_builds.erase(build_id)
		_work_mutex.unlock()
		if was_cancelled:
			continue
		if not _queued_builds.has(cell):
			continue
		var queued_build_id: int = int(_queued_build_id_by_cell.get(cell, -1))
		if queued_build_id != build_id:
			continue
		_queued_builds.erase(cell)
		_queued_build_step_by_cell.erase(cell)
		_queued_build_id_by_cell.erase(cell)
		if not bool(result["ok"]):
			_record_load_failure(cell, String(result["message"]))
			continue
		var sample_step: int = int(result.get("sample_step", TerrainVisualBuilderScript.REGION_DETAIL_SAMPLE_STEP))
		if _ready_tile_data_by_cell.has(cell):
			var ready_step: int = int(_ready_tile_step_by_cell.get(cell, TerrainVisualBuilderScript.REGION_DETAIL_SAMPLE_STEP))
			if ready_step <= sample_step:
				if _active_cells.has(cell):
					_enqueue_ready_commit(cell)
				# Auto-chain the step-1 full-res upgrade only for active cells inside the
				# visual full-res ring; outer active cells keep the coarse mesh (collision
				# stays full res for them). Render-only; golden-neutral.
				if sample_step > TerrainVisualBuilderScript.REGION_DETAIL_FULLRES_SAMPLE_STEP and _active_cells.has(cell) and _is_cell_in_visual_fullres_radius(cell):
					_enqueue_build(cell, TerrainVisualBuilderScript.REGION_DETAIL_FULLRES_SAMPLE_STEP)
				continue
			if _queued_commits.has(cell) and not _visual_tiles_by_cell.has(cell):
				_ready_upgrade_tile_data_by_cell[cell] = result["visual_tile_data"]
				_ready_upgrade_tile_step_by_cell[cell] = sample_step
				continue
		if _visual_tiles_by_cell.has(cell):
			var committed_step: int = int(_committed_tile_step_by_cell.get(cell, TerrainVisualBuilderScript.REGION_DETAIL_SAMPLE_STEP))
			if committed_step <= sample_step:
				continue
		_ready_tile_data_by_cell[cell] = result["visual_tile_data"]
		_ready_tile_step_by_cell[cell] = sample_step
		if result.has("foliage_tile_data") and result["foliage_tile_data"] != null:
			_ready_foliage_data_by_cell[cell] = result["foliage_tile_data"]
		if _active_cells.has(cell):
			_enqueue_ready_commit(cell)
			# Chain the step-1 full-res upgrade only inside the visual full-res ring;
			# outer active cells keep the coarse mesh. Render-only; golden-neutral.
			if sample_step > TerrainVisualBuilderScript.REGION_DETAIL_FULLRES_SAMPLE_STEP and _is_cell_in_visual_fullres_radius(cell):
				_enqueue_build(cell, TerrainVisualBuilderScript.REGION_DETAIL_FULLRES_SAMPLE_STEP)


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
	if not _ready_tile_data_by_cell.has(cell):
		return
	var ready_step: int = int(_ready_tile_step_by_cell.get(cell, TerrainVisualBuilderScript.REGION_DETAIL_SAMPLE_STEP))
	if _visual_tiles_by_cell.has(cell):
		var committed_step: int = int(_committed_tile_step_by_cell.get(cell, TerrainVisualBuilderScript.REGION_DETAIL_SAMPLE_STEP))
		if committed_step <= ready_step and _foliage_tiles_by_cell.has(cell):
			return
	_queued_commits[cell] = true
	_commit_queue.append(cell)


func _promote_ready_visual_upgrade(cell: Vector2i) -> void:
	if not _ready_upgrade_tile_data_by_cell.has(cell):
		return
	var upgrade_step: int = int(_ready_upgrade_tile_step_by_cell.get(cell, TerrainVisualBuilderScript.REGION_DETAIL_SAMPLE_STEP))
	if _visual_tiles_by_cell.has(cell):
		var committed_step: int = int(_committed_tile_step_by_cell.get(cell, TerrainVisualBuilderScript.REGION_DETAIL_SAMPLE_STEP))
		if committed_step <= upgrade_step:
			_ready_upgrade_tile_data_by_cell.erase(cell)
			_ready_upgrade_tile_step_by_cell.erase(cell)
			return
	_ready_tile_data_by_cell[cell] = _ready_upgrade_tile_data_by_cell[cell]
	_ready_tile_step_by_cell[cell] = upgrade_step
	_ready_upgrade_tile_data_by_cell.erase(cell)
	_ready_upgrade_tile_step_by_cell.erase(cell)
	if _active_cells.has(cell):
		_enqueue_ready_commit(cell)


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


func _remove_queued_foliage_finish(cell: Vector2i) -> void:
	if not _queued_foliage_finishes.has(cell):
		return
	_queued_foliage_finishes.erase(cell)
	_foliage_finish_queue.erase(cell)


func _drain_commit_queue() -> int:
	if _commit_queue.is_empty():
		return 0
	var commit_budget: int = maxi(GameConfig.render_visual_tile_commits_per_frame, 1)
	_commit_queue.sort_custom(Callable(self, "_visual_commit_cell_less"))
	var committed_count: int = 0
	while committed_count < commit_budget and not _commit_queue.is_empty():
		var cell: Vector2i = _commit_queue.pop_front()
		_queued_commits.erase(cell)
		if not _active_cells.has(cell):
			continue
		_commit_ready_cell(cell)
		committed_count += 1
		if _commit_frame_budget_exceeded():
			break
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
		if _commit_frame_budget_exceeded():
			break
	return committed_count


func _commit_ready_cell(cell: Vector2i) -> void:
	if _ready_tile_data_by_cell.has(cell):
		var sample_step: int = int(_ready_tile_step_by_cell.get(cell, TerrainVisualBuilderScript.REGION_DETAIL_SAMPLE_STEP))
		_commit_visual_tile(cell, _ready_tile_data_by_cell[cell], sample_step)
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
		# Resolve the tile root from the partial (still assembling) OR the live (already
		# attached) tile. A deferred-LOD0 upgrade enqueues subcommits for a cell whose tile may
		# already be live, so adding a species cell directly to the attached root materializes
		# that one MultiMesh in place — budgeted by this same per-frame subcommit drain.
		var tile_root: Node3D = null
		if _partial_foliage_tiles_by_cell.has(subcommit.cell):
			tile_root = _partial_foliage_tiles_by_cell[subcommit.cell]
		elif _foliage_tiles_by_cell.has(subcommit.cell):
			tile_root = _foliage_tiles_by_cell[subcommit.cell]
		if tile_root == null:
			continue
		TerrainVisualBuilderScript.add_region_foliage_species_cell_from_data(tile_root, subcommit.cell_data, subcommit.species_data)
		_finish_foliage_subcommit(subcommit.cell)
		committed_count += 1
		if _commit_frame_budget_exceeded():
			break


func _drain_pending_frees() -> void:
	if _pending_free_cells.is_empty() and _pending_free_midlod_cells.is_empty():
		return
	var free_budget: int = maxi(GameConfig.render_visual_tile_frees_per_frame, 1)
	var freed_count: int = 0
	while freed_count < free_budget and not _pending_free_cells.is_empty():
		var cell: Vector2i = _pending_free_cells.pop_front()
		_free_visual_cell(cell)
		_free_foliage_cell(cell)
		freed_count += 1
	while freed_count < free_budget and not _pending_free_midlod_cells.is_empty():
		var cell: Vector2i = _pending_free_midlod_cells.pop_front()
		_free_midlod_cell(cell)
		freed_count += 1


func _commit_visual_tile(cell: Vector2i, visual_tile_data: Variant, sample_step: int) -> void:
	if _detail_root == null:
		return
	var previous_visual_tile: Node3D = null
	if _visual_tiles_by_cell.has(cell):
		var committed_step: int = int(_committed_tile_step_by_cell.get(cell, TerrainVisualBuilderScript.REGION_DETAIL_SAMPLE_STEP))
		if committed_step <= sample_step:
			_ready_tile_data_by_cell.erase(cell)
			_ready_tile_step_by_cell.erase(cell)
			_promote_ready_visual_upgrade(cell)
			return
		previous_visual_tile = _visual_tiles_by_cell[cell]
	var visual_tile: MeshInstance3D = TerrainVisualBuilderScript.region_visual_tile_from_data(_detail_root, visual_tile_data, _hlod_instance)
	if visual_tile == null:
		_load_failures_by_cell[cell] = "visual tile failed to load"
		return
	_visual_tiles_by_cell[cell] = visual_tile
	_committed_tile_step_by_cell[cell] = sample_step
	_ready_tile_data_by_cell.erase(cell)
	_ready_tile_step_by_cell.erase(cell)
	_load_failures_by_cell.erase(cell)
	if previous_visual_tile != null:
		if previous_visual_tile.get_parent() != null:
			previous_visual_tile.get_parent().remove_child(previous_visual_tile)
		previous_visual_tile.queue_free()
		visual_tile.name = visual_tile_data.node_name
	_promote_ready_visual_upgrade(cell)


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


func _queue_stream_hlod_region() -> void:
	_stream_hlod_queue.clear()
	_queued_stream_hlod_cells.clear()
	for cell in _sorted_cells(_region_cells_by_cell.keys()):
		_stream_hlod_queue.append(cell)
		_queued_stream_hlod_cells[cell] = true
	_resort_stream_hlod_queue()


func _resort_stream_hlod_queue() -> void:
	if _stream_hlod_queue.size() <= 1:
		return
	_stream_hlod_queue.sort_custom(Callable(self, "_stream_hlod_cell_less"))


func _stream_hlod_cell_less(left: Vector2i, right: Vector2i) -> bool:
	if _active_cells.is_empty():
		return _cell_less(left, right)
	var center: Vector2i = _active_cell_center()
	var left_distance: int = absi(left.x - center.x) + absi(left.y - center.y)
	var right_distance: int = absi(right.x - center.x) + absi(right.y - center.y)
	if left_distance == right_distance:
		return _cell_less(left, right)
	return left_distance < right_distance


func _drain_stream_hlod_queue() -> int:
	if _hlod_instance == null or _stream_hlod_queue.is_empty():
		return 0
	var commit_budget: int = maxi(GameConfig.render_stream_hlod_commits_per_frame, 1)
	var committed_count: int = 0
	while committed_count < commit_budget and not _stream_hlod_queue.is_empty():
		var cell: Vector2i = _stream_hlod_queue.pop_front()
		_queued_stream_hlod_cells.erase(cell)
		if _stream_hlod_chunks_by_cell.has(cell):
			continue
		var chunk: MeshInstance3D = TerrainVisualBuilderScript.region_stream_hlod_chunk_for_cell(_region_id, cell)
		if chunk == null:
			_load_failures_by_cell[cell] = "stream HLOD chunk failed to build: " + _region_id + " " + str(cell)
			continue
		_attach_stream_hlod_chunk(cell, chunk)
		committed_count += 1
		# Each HLOD chunk decode (heightmap bytes + Image.load_from_file PNG + coarse mesh
		# build) is the single heaviest main-thread step in this drain. Once at least one
		# chunk has committed this frame, yield the rest to the next frame if the streamer's
		# shared per-frame wall-clock budget (stamped at the top of _process) is already
		# spent — so a fat decode during the cold-start manifest sweep can't stall the frame
		# into the boot freeze. Headless disables the budget, so fixtures still drain the
		# full per-frame commit_budget in one tick. Render host only — never feeds the sim.
		if _commit_frame_budget_exceeded():
			break
	return committed_count


func _attach_stream_hlod_chunk(cell: Vector2i, chunk: MeshInstance3D) -> void:
	if _hlod_instance == null:
		return
	var tile_origin_xz: Vector2 = Vector2((float(cell.x) + 0.5) * GameConfig.STREAM_TILE_SIZE_M, (float(cell.y) + 0.5) * GameConfig.STREAM_TILE_SIZE_M)
	if _stream_hlod_chunks_by_cell.is_empty():
		_hlod_instance.mesh = chunk.mesh
		_hlod_instance.position = Vector3(tile_origin_xz.x, 0.0, tile_origin_xz.y)
		_hlod_instance.set_meta(TerrainVisualBuilderScript.REGION_LOD_META, "stream_hlod")
		_hlod_instance.set_meta(TerrainVisualBuilderScript.VISIBILITY_RADIUS_META, chunk.get_meta(TerrainVisualBuilderScript.VISIBILITY_RADIUS_META))
		_hlod_instance.set_meta(TerrainVisualBuilderScript.TILE_INDEX_META, cell)
		_hlod_instance.set_meta(TerrainVisualBuilderScript.TILE_PATH_META, chunk.get_meta(TerrainVisualBuilderScript.TILE_PATH_META))
		_hlod_instance.set_meta(TerrainVisualBuilderScript.TILE_SURFACE_ID_PATH_META, chunk.get_meta(TerrainVisualBuilderScript.TILE_SURFACE_ID_PATH_META))
		_hlod_instance.set_instance_shader_parameter(
			TerrainVisualBuilderScript.CONTROL_ORIGIN_XZ_UNIFORM,
			chunk.get_instance_shader_parameter(TerrainVisualBuilderScript.CONTROL_ORIGIN_XZ_UNIFORM)
		)
		_hlod_instance.set_instance_shader_parameter(
			TerrainVisualBuilderScript.CONTROL_SIZE_XZ_UNIFORM,
			chunk.get_instance_shader_parameter(TerrainVisualBuilderScript.CONTROL_SIZE_XZ_UNIFORM)
		)
		chunk.queue_free()
		_stream_hlod_chunks_by_cell[cell] = _hlod_instance
	else:
		chunk.position = Vector3(tile_origin_xz.x - _hlod_instance.position.x, 0.0, tile_origin_xz.y - _hlod_instance.position.z)
		_hlod_instance.add_child(chunk)
		_stream_hlod_chunks_by_cell[cell] = chunk
	_queue_stream_hlod_densification(cell)


func _apply_stream_hlod_densification() -> void:
	if _region_id != STREAM_HLOD_DENSIFY_REGION_ID:
		return
	if _hlod_instance == null:
		return
	var chunks: Array[MeshInstance3D] = []
	_collect_stream_hlod_chunks(_hlod_instance, chunks)
	for chunk in chunks:
		if chunk.has_meta(TerrainVisualBuilderScript.TILE_INDEX_META):
			_queue_stream_hlod_densification(Vector2i(chunk.get_meta(TerrainVisualBuilderScript.TILE_INDEX_META)))


func _queue_near_stream_hlod_densification() -> void:
	if _region_id != STREAM_HLOD_DENSIFY_REGION_ID:
		return
	for cell in _sorted_cells(_stream_hlod_chunks_by_cell.keys()):
		_queue_stream_hlod_densification(cell)


func _queue_stream_hlod_densification(cell: Vector2i) -> void:
	if _region_id != STREAM_HLOD_DENSIFY_REGION_ID:
		return
	if not _stream_hlod_chunks_by_cell.has(cell):
		return
	if _densified_stream_hlod_cells.has(cell) or _queued_stream_hlod_densify_cells.has(cell):
		return
	if not _is_cell_in_stream_hlod_densify_radius(cell):
		return
	_stream_hlod_densify_queue.append(cell)
	_queued_stream_hlod_densify_cells[cell] = true


func _is_cell_in_stream_hlod_densify_radius(cell: Vector2i) -> bool:
	if _active_cells.is_empty():
		return false
	var center: Vector2i = _active_cell_center()
	var radius: int = maxi(GameConfig.render_stream_hlod_densify_radius, 1)
	return absi(cell.x - center.x) <= radius and absi(cell.y - center.y) <= radius


func _is_cell_in_visual_fullres_radius(cell: Vector2i) -> bool:
	# Gate the step-1 full-res VISUAL upgrade (REGION_DETAIL_FULLRES_SAMPLE_STEP) to a
	# small Chebyshev ring around the active center, decoupling the heavy full-res
	# visual radius from the collision radius (STREAM_ACTIVE_RADIUS). Active cells
	# outside this ring stay committed at the coarse REGION_DETAIL_SAMPLE_STEP — render
	# only, collision is unaffected (every active cell still gets its full-res
	# HeightMapShape3D from the collision streamer; D30/D35). Mirrors the densify-radius
	# helper above; uses _active_cell_center() (== the just-activated cell when it is
	# the sole active cell, as in the fullres fixtures, so the near cell still upgrades).
	var center: Vector2i = _active_cell_center()
	var radius: int = maxi(GameConfig.render_visual_fullres_radius_cells, 0)
	return absi(cell.x - center.x) <= radius and absi(cell.y - center.y) <= radius


func _is_cell_in_foliage_radius(cell: Vector2i) -> bool:
	# Gate the heavy near-field foliage LOD0 to a small Chebyshev ring around the active
	# center. Cells outside the ring commit only the sparse LOD1 silhouette; their LOD0 is
	# deferred (retained) and materialized in place once they cross in. Mirrors the visual
	# full-res / HLOD-densify radius helpers; uses _active_cell_center() (== the just-
	# activated cell when it is the sole active cell, so a single near cell still gets LOD0,
	# as the foliage fixtures rely on). Render-only, golden-neutral.
	var center: Vector2i = _active_cell_center()
	var radius: int = maxi(GameConfig.render_visual_foliage_radius_cells, 0)
	return absi(cell.x - center.x) <= radius and absi(cell.y - center.y) <= radius


func _drain_stream_hlod_densify_queue() -> int:
	if _stream_hlod_densify_queue.is_empty():
		return 0
	var commit_budget: int = maxi(GameConfig.render_stream_hlod_commits_per_frame, 1)
	var dispatched_count: int = 0
	while dispatched_count < commit_budget and not _stream_hlod_densify_queue.is_empty():
		var cell: Vector2i = _stream_hlod_densify_queue.pop_front()
		if not _stream_hlod_chunks_by_cell.has(cell) or _densified_stream_hlod_cells.has(cell):
			_queued_stream_hlod_densify_cells.erase(cell)
			continue
		_enqueue_stream_hlod_densify_build(cell)
		dispatched_count += 1
	return dispatched_count


func _enqueue_stream_hlod_densify_build(cell: Vector2i) -> void:
	var job: Dictionary = {
		"cell": cell,
		"generation": _stream_generation,
		"kind": "stream_hlod_densify",
		"region_id": _region_id,
	}
	_work_mutex.lock()
	_stream_hlod_densify_build_queue.append(job)
	_work_mutex.unlock()
	_work_semaphore.post()


func _drain_stream_hlod_densify_worker_result(result: Dictionary) -> void:
	var cell: Vector2i = result["cell"] as Vector2i
	var generation: int = int(result["generation"])
	if generation != _stream_generation:
		return
	if not _queued_stream_hlod_densify_cells.has(cell):
		return
	_queued_stream_hlod_densify_cells.erase(cell)
	if _densified_stream_hlod_cells.has(cell):
		return
	if not _stream_hlod_chunks_by_cell.has(cell):
		return
	_densified_stream_hlod_cells[cell] = true
	if not bool(result["ok"]):
		var message: String = String(result.get("message", ""))
		if not message.is_empty():
			push_error(message)
		return
	if bool(result.get("skipped", false)):
		return
	var chunk: MeshInstance3D = _stream_hlod_chunks_by_cell[cell] as MeshInstance3D
	if chunk == null:
		return
	var mesh: ArrayMesh = result["mesh"] as ArrayMesh
	var mesh_data: Variant = result["mesh_data"]
	if mesh == null or mesh.get_surface_count() <= 0 or mesh_data == null:
		return
	TerrainVisualBuilderScript.apply_region_mesh_materials(mesh, mesh_data)
	chunk.mesh = mesh
	TerrainVisualBuilderScript.apply_region_mesh_instance_parameters(chunk, mesh_data)


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
		_ready_foliage_data_by_cell.erase(cell)
		return
	if foliage_tile_data == null or not bool(foliage_tile_data.ok):
		_ready_foliage_data_by_cell.erase(cell)
		return
	var foliage_tile: Node3D = TerrainVisualBuilderScript.region_foliage_tile_root_from_data(_foliage_root, foliage_tile_data, false) as Node3D
	if foliage_tile == null:
		_ready_foliage_data_by_cell.erase(cell)
		return
	_partial_foliage_tiles_by_cell[cell] = foliage_tile
	_ready_foliage_data_by_cell.erase(cell)

	# Distance-graded foliage LOD. Cells INSIDE render_visual_foliage_radius_cells commit the
	# full LOD0 (dense near-field) + LOD1 (sparse silhouette). Cells beyond it commit ONLY LOD1
	# now — the heavy LOD0 (the bulk of the per-crossing materialization) is deferred and the
	# full tile data retained so LOD0 can be added IN PLACE the moment the cell enters the ring
	# (_promote_near_deferred_foliage_lod0). Foliage is still PRESENT everywhere (no empty pop).
	var commit_lod0: bool = _is_cell_in_foliage_radius(cell)
	if not commit_lod0:
		_deferred_lod0_foliage_data_by_cell[cell] = foliage_tile_data
	var subcommit_count: int = 0
	for cell_data in foliage_tile_data.cells:
		if cell_data == null:
			continue
		if not commit_lod0 and int(cell_data.lod_index) == 0:
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
		_queue_foliage_tile_finish(cell)
		return
	_pending_foliage_subcommit_counts_by_cell[cell] = subcommit_count


func _promote_near_deferred_foliage_lod0() -> void:
	# Materialize the deferred near-field LOD0 for every cell that is now both active and
	# inside the dense foliage ring. Called on each activation (the active center may have
	# shifted, pulling previously LOD1-only tiles into the ring). Snapshot the keys first so
	# the upgrade can mutate the deferred dict mid-iteration.
	if _deferred_lod0_foliage_data_by_cell.is_empty():
		return
	for cell in _sorted_cells(_deferred_lod0_foliage_data_by_cell.keys()):
		if not _active_cells.has(cell):
			continue
		if not _is_cell_in_foliage_radius(cell):
			continue
		_enqueue_lod0_foliage_upgrade(cell)


func _enqueue_lod0_foliage_upgrade(cell: Vector2i) -> void:
	# In-place upgrade: enqueue the held-back LOD0 subcommits for a cell whose foliage tile is
	# already partial (still assembling) or live (attached). The subcommit drain resolves the
	# root from either dict and adds the LOD0 species, budgeted per frame like any subcommit —
	# so the deferred dense foliage materializes spread across frames, never a rebuild and
	# never an empty hole (the LOD1 silhouette was already in place). Render-only.
	if not _deferred_lod0_foliage_data_by_cell.has(cell):
		return
	var foliage_tile_data: Variant = _deferred_lod0_foliage_data_by_cell[cell]
	_deferred_lod0_foliage_data_by_cell.erase(cell)
	if foliage_tile_data == null:
		return
	# Only upgrade tiles that actually exist (partial or live); if the tile was freed before the
	# upgrade fired, the deferred entry is simply dropped.
	if not _partial_foliage_tiles_by_cell.has(cell) and not _foliage_tiles_by_cell.has(cell):
		return
	var added_count: int = 0
	for cell_data in foliage_tile_data.cells:
		if cell_data == null:
			continue
		if int(cell_data.lod_index) != 0:
			continue
		for species_data in cell_data.species:
			if species_data == null or bool(species_data.transforms.is_empty()):
				continue
			var subcommit: FoliageSubcommit = FoliageSubcommit.new()
			subcommit.cell = cell
			subcommit.cell_data = cell_data
			subcommit.species_data = species_data
			_foliage_subcommit_queue.append(subcommit)
			added_count += 1
	if added_count <= 0:
		return
	# If the tile is still assembling (LOD1 subcommits not all drained yet), fold the LOD0
	# subcommits into the pending count so the tile-finish waits for them too. If the tile has
	# already finished its LOD1 subcommits (live or finish-queued), no pending count exists and
	# the LOD0 subcommits drain straight into the existing root — no finish step is owed.
	if _pending_foliage_subcommit_counts_by_cell.has(cell):
		_pending_foliage_subcommit_counts_by_cell[cell] += added_count


func _finish_foliage_subcommit(cell: Vector2i) -> void:
	if not _pending_foliage_subcommit_counts_by_cell.has(cell):
		return
	var remaining_count: int = _pending_foliage_subcommit_counts_by_cell[cell] - 1
	if remaining_count > 0:
		_pending_foliage_subcommit_counts_by_cell[cell] = remaining_count
		return
	_pending_foliage_subcommit_counts_by_cell.erase(cell)
	_queue_foliage_tile_finish(cell)


# Enqueue a fully-built (DETACHED) foliage tile for live attachment. The actual
# add_child into _foliage_root — the step that makes the RenderingServer materialize
# every MultiMesh in the tile — is deferred to _drain_foliage_finish_queue, which
# attaches at most render_visual_foliage_tile_finishes_per_frame tiles per frame. This
# spreads the per-crossing materialization burst (several tiles finishing together)
# across frames instead of stalling one. Render-only, golden-neutral.
func _queue_foliage_tile_finish(cell: Vector2i) -> void:
	if not _partial_foliage_tiles_by_cell.has(cell):
		return
	if _queued_foliage_finishes.has(cell):
		return
	_foliage_finish_queue.append(cell)
	_queued_foliage_finishes[cell] = true


func _drain_foliage_finish_queue() -> int:
	if _foliage_finish_queue.is_empty():
		return 0
	var finish_budget: int = maxi(GameConfig.render_visual_foliage_tile_finishes_per_frame, 1)
	var finished_count: int = 0
	while finished_count < finish_budget and not _foliage_finish_queue.is_empty():
		var cell: Vector2i = _foliage_finish_queue.pop_front()
		_queued_foliage_finishes.erase(cell)
		if not _partial_foliage_tiles_by_cell.has(cell):
			continue
		_finish_foliage_tile_commit(cell)
		finished_count += 1
		if _commit_frame_budget_exceeded():
			break
	return finished_count


func _finish_foliage_tile_commit(cell: Vector2i) -> void:
	if not _partial_foliage_tiles_by_cell.has(cell):
		_pending_foliage_subcommit_counts_by_cell.erase(cell)
		return
	var foliage_tile: Node3D = _partial_foliage_tiles_by_cell[cell]
	_partial_foliage_tiles_by_cell.erase(cell)
	_pending_foliage_subcommit_counts_by_cell.erase(cell)
	if foliage_tile == null:
		return
	if _active_cells.has(cell):
		if foliage_tile.get_parent() == null:
			if _foliage_root == null:
				foliage_tile.queue_free()
				return
			_foliage_root.add_child(foliage_tile)
		_foliage_tiles_by_cell[cell] = foliage_tile
		return
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
	_stream_hlod_densify_build_queue.clear()
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
		var generation: int = int(result["generation"])
		_work_mutex.lock()
		if not _worker_should_stop and generation == _stream_generation and not _worker_result_is_cancelled_locked(result):
			_result_queue.append(result)
		_work_mutex.unlock()


func _pop_next_build_job_locked() -> Dictionary:
	if not _build_queue.is_empty():
		return _build_queue.pop_front() as Dictionary
	if not _midlod_build_queue.is_empty():
		return _midlod_build_queue.pop_front() as Dictionary
	if not _stream_hlod_densify_build_queue.is_empty():
		return _stream_hlod_densify_build_queue.pop_front() as Dictionary
	return {}


func _worker_result_is_cancelled_locked(result: Dictionary) -> bool:
	var kind: String = String(result.get("kind", "visual"))
	var cell: Vector2i = result["cell"] as Vector2i
	if kind == "midlod":
		return _cancelled_midlod_builds.has(cell)
	if kind == "stream_hlod_densify":
		return false
	var build_id: int = int(result.get("build_id", -1))
	return _cancelled_builds.has(build_id)


func _build_worker_result(job: Dictionary) -> Dictionary:
	var kind: String = String(job.get("kind", "visual"))
	if kind == "midlod":
		return _build_midlod_tile_result(job)
	if kind == "stream_hlod_densify":
		return _build_stream_hlod_densify_result(job)
	return _build_visual_tile_result(job)


func _build_visual_tile_result(job: Dictionary) -> Dictionary:
	var build_id: int = int(job.get("build_id", -1))
	var cell: Vector2i = job["cell"] as Vector2i
	var generation: int = int(job["generation"])
	var region_id: String = String(job["region_id"])

	_work_mutex.lock()
	var should_skip: bool = _worker_should_stop or generation != _stream_generation or _cancelled_builds.has(build_id)
	_work_mutex.unlock()
	if should_skip:
		return {
			"ok": false,
			"build_id": build_id,
			"cell": cell,
			"generation": generation,
			"kind": "visual",
			"message": "visual tile build cancelled: " + str(cell),
			"visual_tile_data": null,
		}

	var sample_step: int = int(job.get("sample_step", TerrainVisualBuilderScript.REGION_DETAIL_SAMPLE_STEP))
	var visual_tile_data: Variant = TerrainVisualBuilderScript.build_region_visual_tile_data(region_id, cell, sample_step)
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
		"build_id": build_id,
		"cell": cell,
		"generation": generation,
		"kind": "visual",
		"message": message,
		"visual_tile_data": visual_tile_data,
		"foliage_tile_data": foliage_tile_data,
		"sample_step": sample_step,
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


func _build_stream_hlod_densify_result(job: Dictionary) -> Dictionary:
	var cell: Vector2i = job["cell"] as Vector2i
	var generation: int = int(job["generation"])
	var region_id: String = String(job["region_id"])

	_work_mutex.lock()
	var should_skip: bool = _worker_should_stop or generation != _stream_generation
	_work_mutex.unlock()
	if should_skip:
		return {
			"ok": false,
			"cell": cell,
			"generation": generation,
			"kind": "stream_hlod_densify",
			"message": "stream HLOD densify cancelled: " + str(cell),
			"mesh": null,
			"mesh_data": null,
			"skipped": true,
		}

	var tile_data: Variant = TerrainVisualBuilderScript._load_region_tile(region_id, cell)
	if tile_data == null:
		return {
			"ok": false,
			"cell": cell,
			"generation": generation,
			"kind": "stream_hlod_densify",
			"message": "stream HLOD densify tile failed to load: " + region_id + " " + str(cell),
			"mesh": null,
			"mesh_data": null,
			"skipped": false,
		}

	var height_variance_m: float = _stream_hlod_tile_height_variance_from_data(tile_data)
	if height_variance_m < STREAM_HLOD_DENSIFY_MIN_HEIGHT_VARIANCE_M:
		return {
			"ok": true,
			"cell": cell,
			"generation": generation,
			"kind": "stream_hlod_densify",
			"message": "",
			"mesh": null,
			"mesh_data": null,
			"skipped": true,
		}

	var tile_size_m: float = float(tile_data.tile_size_m)
	var tile_origin_xz: Vector2 = Vector2((float(cell.x) + 0.5) * tile_size_m, (float(cell.y) + 0.5) * tile_size_m)
	var mesh_data: Variant = TerrainVisualBuilderScript.build_region_surface_index_mesh_data(
		tile_data,
		STREAM_HLOD_DENSIFY_SAMPLE_STEP,
		String(tile_data.key) + "_stream_terrain_hlod_densify_mesh",
		tile_origin_xz
	)
	if mesh_data == null or mesh_data.surfaces.size() <= 0:
		return {
			"ok": false,
			"cell": cell,
			"generation": generation,
			"kind": "stream_hlod_densify",
			"message": "stream HLOD densify mesh had no surfaces: " + region_id + " " + str(cell),
			"mesh": null,
			"mesh_data": null,
			"skipped": false,
		}
	var mesh: ArrayMesh = TerrainVisualBuilderScript.region_mesh_from_data(mesh_data, false)
	if mesh == null or mesh.get_surface_count() <= 0:
		return {
			"ok": false,
			"cell": cell,
			"generation": generation,
			"kind": "stream_hlod_densify",
			"message": "stream HLOD densify ArrayMesh failed: " + region_id + " " + str(cell),
			"mesh": null,
			"mesh_data": mesh_data,
			"skipped": false,
		}
	return {
		"ok": true,
		"cell": cell,
		"generation": generation,
		"kind": "stream_hlod_densify",
		"message": "",
		"mesh": mesh,
		"mesh_data": mesh_data,
		"skipped": false,
	}


func _stream_hlod_tile_height_variance_from_data(tile_data: Variant) -> float:
	if tile_data == null:
		return -1.0
	var heights: PackedFloat32Array = tile_data.heights
	if heights.is_empty():
		return -1.0
	var min_height: float = float(heights[0])
	var max_height: float = min_height
	for value in heights:
		var height: float = float(value)
		min_height = minf(min_height, height)
		max_height = maxf(max_height, height)
	return max_height - min_height


func _free_visual_cell(cell: Vector2i) -> void:
	if not _visual_tiles_by_cell.has(cell):
		_committed_tile_step_by_cell.erase(cell)
		return
	var visual_tile: Node3D = _visual_tiles_by_cell[cell]
	_visual_tiles_by_cell.erase(cell)
	_committed_tile_step_by_cell.erase(cell)
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
	_remove_queued_foliage_finish(cell)
	_deferred_lod0_foliage_data_by_cell.erase(cell)
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


func _update_stream_priority_from_active_cells() -> void:
	if _active_cells.is_empty():
		_stream_priority_center_cell = Vector2i.ZERO
		_stream_priority_has_center = false
		_stream_priority_forward_cell_delta = Vector2i.ZERO
		return
	var next_center: Vector2i = _active_cell_center()
	if _stream_priority_has_center:
		var delta: Vector2i = next_center - _stream_priority_center_cell
		if delta != Vector2i.ZERO:
			_stream_priority_forward_cell_delta = Vector2i(
				clampi(delta.x, -1, 1),
				clampi(delta.y, -1, 1)
			)
	else:
		_stream_priority_has_center = true
	_stream_priority_center_cell = next_center


func _visual_commit_cell_less(left: Vector2i, right: Vector2i) -> bool:
	if _active_cells.is_empty():
		return _cell_less(left, right)
	var center: Vector2i = _stream_priority_center_cell
	if not _stream_priority_has_center:
		center = _active_cell_center()
	var left_distance: int = absi(left.x - center.x) + absi(left.y - center.y)
	var right_distance: int = absi(right.x - center.x) + absi(right.y - center.y)
	if left_distance != right_distance:
		return left_distance < right_distance
	if _stream_priority_forward_cell_delta != Vector2i.ZERO:
		var left_offset: Vector2i = left - center
		var right_offset: Vector2i = right - center
		var left_forward: int = left_offset.x * _stream_priority_forward_cell_delta.x + left_offset.y * _stream_priority_forward_cell_delta.y
		var right_forward: int = right_offset.x * _stream_priority_forward_cell_delta.x + right_offset.y * _stream_priority_forward_cell_delta.y
		if left_forward != right_forward:
			return left_forward > right_forward
	return _cell_less(left, right)


func _cell_less(left: Vector2i, right: Vector2i) -> bool:
	if left.x == right.x:
		return left.y < right.y
	return left.x < right.x
