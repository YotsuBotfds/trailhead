extends Node

const StreamerScript: GDScript = preload("res://systems/render/terrain_visual_streamer.gd")
const ScatterScript: GDScript = preload("res://systems/render/scatter_visual_builder.gd")
const Route: Resource = preload("res://data/routes/cedar_hollow_zion_stream_route.tres")

# Model an expensive commit without sleeps or machine-dependent time assertions.
# Every queue stays busy; one serviced queue exhausts the frame's time budget.
class BudgetProbe:
	extends "res://systems/render/terrain_visual_streamer.gd"
	var calls: Array[int] = []
	var budget_spent: bool = false
	func _has_pending_commit_work(_index: int) -> bool:
		return true
	func _commit_frame_budget_exceeded() -> bool:
		return not _headless and budget_spent
	func _record(index: int) -> int:
		calls.append(index)
		budget_spent = true
		return 1
	func _drain_stream_hlod_commit_queue() -> int:
		return _record(0)
	func _drain_stream_hlod_densify_commit_queue() -> int:
		return _record(1)
	func _drain_commit_queue() -> int:
		return _record(2)
	func _drain_foliage_subcommit_queue() -> void:
		_record(3)
	func _drain_foliage_finish_queue() -> int:
		return _record(4)
	func _drain_midlod_commit_queue() -> int:
		return _record(5)
	func _drain_pending_frees() -> void:
		_record(6)

# Unmodified streamer, typed so private helpers can be called directly. Never
# configured or added to the tree: no workers, no EventBus connections.
class StreamerProbe:
	extends "res://systems/render/terrain_visual_streamer.gd"

var _errors: PackedStringArray = PackedStringArray()


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_shared_budget()
	_check_retained_frees_are_not_commit_work()
	_check_native_cell_sort_parity()
	_check_stream_hlod_priority_sort_parity()
	_check_active_center_cache()
	_check_desired_midlod_cells_sorted()
	_check_near_densify_walk_parity()
	_check_foliage_subcommit_index()
	_check_scatter_spacing_equivalence()
	_check_upgrade_reuses_foliage()
	_measure_spawn_scatter()
	if _errors.is_empty():
		print("ok: streaming CPU regressions (shared budget, native sorts, center cache, densify walk, subcommit index, foliage reuse, scatter parity)")
	else:
		for error in _errors:
			push_error(error)
	get_tree().quit(0 if _errors.is_empty() else 1)


func _check_shared_budget() -> void:
	var probe: BudgetProbe = BudgetProbe.new()
	probe._headless = false
	for frame in range(14):
		probe.budget_spent = false
		var before: int = probe.calls.size()
		probe._drain_budgeted_commits()
		if probe.calls.size() != before + 1:
			_errors.append("shared budget should stop after one expensive queue in frame " + str(frame))
		elif probe.calls.back() != frame % 7:
			_errors.append("a continuously busy commit queue was starved")
	# Maintenance may already exhaust the budget, but one queue must still progress.
	probe.budget_spent = true
	var before: int = probe.calls.size()
	probe._drain_budgeted_commits()
	if probe.calls.size() != before + 1:
		_errors.append("expired maintenance budget must still permit one drain")
	probe._headless = true
	probe.calls.clear()
	probe._drain_budgeted_commits()
	if probe.calls != [0, 1, 2, 3, 4, 5, 6]:
		_errors.append("headless must preserve the original full drain order")
	probe.free()


func _check_retained_frees_are_not_commit_work() -> void:
	# A free queue holding only retained cells must not claim the scheduler's one
	# guaranteed over-deadline drain; an expired cell or a MidLOD free must.
	var probe: StreamerProbe = StreamerProbe.new()
	probe._headless = false
	probe._render_frame_index = 1000
	var cell: Vector2i = Vector2i(4, -3)
	probe._pending_free_cells.append(cell)
	probe._pending_free_queued_frame[cell] = 1000
	if probe._has_pending_commit_work(6):
		_errors.append("retained-only visual frees were reported as commit work")
	probe._pending_free_queued_frame[cell] = 0
	if not probe._has_pending_commit_work(6):
		_errors.append("an expired visual free was not reported as commit work")
	probe._pending_free_queued_frame[cell] = 1000
	probe._pending_free_midlod_cells.append(Vector2i(9, 9))
	if not probe._has_pending_commit_work(6):
		_errors.append("a MidLOD free was not reported as commit work")
	probe._pending_free_midlod_cells.clear()
	probe._headless = true
	if not probe._has_pending_commit_work(6):
		_errors.append("headless (no retention) must treat every pending free as work")
	probe.free()


func _random_unique_cells(rng: RandomNumberGenerator, count: int, span: int) -> Array[Vector2i]:
	var lookup: Dictionary[Vector2i, bool] = {}
	var guard: int = 0
	while lookup.size() < count and guard < count * 20:
		lookup[Vector2i(rng.randi_range(-span, span), rng.randi_range(-span, span))] = true
		guard += 1
	var cells: Array[Vector2i] = []
	for cell: Vector2i in lookup:
		cells.append(cell)
	return cells


func _check_native_cell_sort_parity() -> void:
	var probe: StreamerProbe = StreamerProbe.new()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 150
	for trial in range(40):
		var span: int = [3, 40, 3000, 1000000][trial % 4]
		var cells: Array[Vector2i] = _random_unique_cells(rng, rng.randi_range(0, 200), span)
		var expected: Array[Vector2i] = []
		expected.assign(cells)
		expected.sort_custom(Callable(probe, "_cell_less"))
		if probe._sorted_cells(cells) != expected:
			_errors.append("native _sorted_cells order differs from _cell_less (trial " + str(trial) + ")")
			break
	# Full int32 range, negatives, and non-Vector2i entries (filtered as before).
	var extremes: Array[int] = [-2147483648, -2147483647, -1, 0, 1, 2147483646, 2147483647]
	var mixed: Array = ["skip", 7, null]
	var extreme_cells: Array[Vector2i] = []
	for x in extremes:
		for y in extremes:
			mixed.append(Vector2i(x, y))
			extreme_cells.append(Vector2i(x, y))
	extreme_cells.reverse()
	extreme_cells.sort_custom(Callable(probe, "_cell_less"))
	if probe._sorted_cells(mixed) != extreme_cells:
		_errors.append("native _sorted_cells mishandles int32 extremes or non-cell entries")
	# Informational: the boot-time region sort (Zion has ~3.1k cells).
	var region: Array[Vector2i] = []
	for x in range(-28, 28):
		for y in range(-28, 28):
			region.append(Vector2i(x, y))
	region.shuffle()
	var start_usec: int = Time.get_ticks_usec()
	probe._sorted_cells(region)
	var native_ms: float = float(Time.get_ticks_usec() - start_usec) / 1000.0
	var reference: Array[Vector2i] = []
	reference.assign(region)
	start_usec = Time.get_ticks_usec()
	reference.sort_custom(Callable(probe, "_cell_less"))
	var comparator_ms: float = float(Time.get_ticks_usec() - start_usec) / 1000.0
	print("streaming_cpu: sort ", region.size(), " cells native ms=", native_ms, " comparator ms=", comparator_ms)
	probe.free()


func _check_stream_hlod_priority_sort_parity() -> void:
	var probe: StreamerProbe = StreamerProbe.new()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 2611
	# Empty active set: plain _cell_less order.
	var cells: Array[Vector2i] = _random_unique_cells(rng, 150, 30)
	_expect_stream_hlod_sort_parity(probe, cells, "empty active set")
	# Active ring with and without a stream-priority center.
	for x in range(10, 17):
		for y in range(-9, -2):
			probe._set_active_cell(Vector2i(x, y))
	_expect_stream_hlod_sort_parity(probe, cells, "active center")
	probe._update_stream_priority_from_active_cells()
	for trial in range(12):
		_expect_stream_hlod_sort_parity(probe, _random_unique_cells(rng, rng.randi_range(0, 400), [6, 60, 4000][trial % 3]), "priority center trial " + str(trial))
	# Out of packable range: comparator fallback must still give the same order.
	var wide: Array[Vector2i] = _random_unique_cells(rng, 50, 40)
	wide.append(Vector2i(2000000, 3))
	wide.append(Vector2i(-5, -1500000))
	_expect_stream_hlod_sort_parity(probe, wide, "fallback range")
	# Informational: one activation-frame resort of a fresh Zion-sized queue.
	var region: Array[Vector2i] = []
	for x in range(-28, 28):
		for y in range(-28, 28):
			region.append(Vector2i(x, y))
	var reference: Array[Vector2i] = []
	reference.assign(region)
	var start_usec: int = Time.get_ticks_usec()
	probe._sort_cells_by_stream_hlod_priority(region)
	var native_ms: float = float(Time.get_ticks_usec() - start_usec) / 1000.0
	start_usec = Time.get_ticks_usec()
	reference.sort_custom(Callable(probe, "_stream_hlod_cell_less"))
	var comparator_ms: float = float(Time.get_ticks_usec() - start_usec) / 1000.0
	print("streaming_cpu: HLOD resort ", region.size(), " cells native ms=", native_ms, " comparator ms=", comparator_ms)
	probe.free()


func _expect_stream_hlod_sort_parity(probe: StreamerProbe, cells: Array[Vector2i], label: String) -> void:
	var expected: Array[Vector2i] = []
	expected.assign(cells)
	expected.sort_custom(Callable(probe, "_stream_hlod_cell_less"))
	var actual: Array[Vector2i] = []
	actual.assign(cells)
	actual.reverse()
	probe._sort_cells_by_stream_hlod_priority(actual)
	if actual != expected:
		_errors.append("native stream-HLOD priority sort differs from _stream_hlod_cell_less (" + label + ")")


func _reference_active_center(active: Dictionary[Vector2i, bool]) -> Vector2i:
	if active.is_empty():
		return Vector2i.ZERO
	var sum_x: int = 0
	var sum_y: int = 0
	for cell: Vector2i in active:
		sum_x += cell.x
		sum_y += cell.y
	return Vector2i(
		int(floorf(float(sum_x) / float(active.size()) + 0.5)),
		int(floorf(float(sum_y) / float(active.size()) + 0.5))
	)


func _check_active_center_cache() -> void:
	var probe: StreamerProbe = StreamerProbe.new()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 49
	if probe._active_cell_center() != Vector2i.ZERO:
		_errors.append("empty active set must center at zero")
	for step in range(300):
		var cell: Vector2i = Vector2i(rng.randi_range(-12, 12), rng.randi_range(-12, 12))
		if rng.randi_range(0, 2) == 0:
			probe._erase_active_cell(cell)
		else:
			probe._set_active_cell(cell)
		if step % 97 == 96:
			probe._clear_active_cells()
		# Query twice: the second hit comes from the cache.
		var expected: Vector2i = _reference_active_center(probe._active_cells)
		if probe._active_cell_center() != expected or probe._active_cell_center() != expected:
			_errors.append("cached active center went stale at step " + str(step))
			break
	probe.free()


func _check_desired_midlod_cells_sorted() -> void:
	var probe: StreamerProbe = StreamerProbe.new()
	for x in range(-5, 30):
		for y in range(-8, 26):
			probe._region_cells_by_cell[Vector2i(x, y)] = true
	for x in range(7, 14):
		for y in range(5, 12):
			probe._set_active_cell(Vector2i(x, y))
	var desired: Array[Vector2i] = probe._desired_midlod_cells()
	var expected: Array[Vector2i] = []
	expected.assign(desired)
	expected.sort_custom(Callable(probe, "_cell_less"))
	if desired.is_empty() or desired != expected:
		_errors.append("_desired_midlod_cells must stay non-empty and in _cell_less order")
	for cell in desired:
		if probe._active_cells.has(cell) and probe._is_cell_in_visual_detail_radius(cell):
			_errors.append("_desired_midlod_cells included an active detail cell")
			break
	probe.free()


func _check_near_densify_walk_parity() -> void:
	# Dense (square walk) and sparse (sorted-key fallback) chunk sets must queue the
	# same cells in the same order as the original sort-every-chunk scan.
	for dense in [true, false]:
		var probe: StreamerProbe = StreamerProbe.new()
		probe._region_id = "cedar_hollow_zion"
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = 7 if dense else 8
		if dense:
			for x in range(-20, 25):
				for y in range(-18, 27):
					if rng.randi_range(0, 9) != 0:
						probe._stream_hlod_chunks_by_cell[Vector2i(x, y)] = null
		else:
			# 40 unique cells (i mod 13, 5i mod 11), mostly inside the radius.
			for i in range(40):
				probe._stream_hlod_chunks_by_cell[Vector2i(i % 13 - 4, (i * 5) % 11 - 2)] = null
		var chunk_cells: Array[Vector2i] = []
		for cell: Vector2i in probe._stream_hlod_chunks_by_cell:
			chunk_cells.append(cell)
		for index in range(0, chunk_cells.size(), 5):
			probe._densified_stream_hlod_cells[chunk_cells[index]] = true
		for index in range(2, chunk_cells.size(), 7):
			probe._queued_stream_hlod_densify_cells[chunk_cells[index]] = true
		for x in range(1, 4):
			for y in range(2, 5):
				probe._set_active_cell(Vector2i(x, y))
		probe._update_stream_priority_from_active_cells()
		var center: Vector2i = probe._stream_hlod_active_center_cell()
		var radius: int = maxi(GameConfig.render_stream_hlod_densify_radius, 1)
		chunk_cells.sort_custom(Callable(probe, "_cell_less"))
		var expected: Array[Vector2i] = []
		for cell in chunk_cells:
			if probe._densified_stream_hlod_cells.has(cell) or probe._queued_stream_hlod_densify_cells.has(cell):
				continue
			if absi(cell.x - center.x) > radius or absi(cell.y - center.y) > radius:
				continue
			expected.append(cell)
		probe._queue_near_stream_hlod_densification()
		if expected.is_empty() or probe._stream_hlod_densify_queue != expected:
			_errors.append("near densify queue changed (" + ("square walk" if dense else "sparse fallback") + ")")
		probe.free()


func _check_foliage_subcommit_index() -> void:
	var probe: StreamerProbe = StreamerProbe.new()
	var a: Vector2i = Vector2i(1, 1)
	var b: Vector2i = Vector2i(-2, 3)
	var c: Vector2i = Vector2i(5, -7)
	var absent: Vector2i = Vector2i(40, 40)
	for cell in [a, a, b, a, c, b, a]:
		probe._push_foliage_subcommit(cell, null, null)
	probe._pop_foliage_subcommit()
	_expect_subcommit_index(probe, [a, b, a, c, b, a], "after pop")
	probe._pending_foliage_subcommit_counts_by_cell[absent] = 3
	probe._remove_queued_foliage_subcommits(absent)
	if probe._pending_foliage_subcommit_counts_by_cell.has(absent):
		_errors.append("removing a cell with no queued subcommits must still clear its pending count")
	_expect_subcommit_index(probe, [a, b, a, c, b, a], "after no-op removal")
	probe._pending_foliage_subcommit_counts_by_cell[b] = 2
	probe._remove_queued_foliage_subcommits(b)
	if probe._pending_foliage_subcommit_counts_by_cell.has(b):
		_errors.append("removing queued subcommits must clear the pending count")
	_expect_subcommit_index(probe, [a, a, c, a], "after removal")
	while not probe._foliage_subcommit_queue.is_empty():
		probe._pop_foliage_subcommit()
	_expect_subcommit_index(probe, [], "after drain")
	probe.free()


func _expect_subcommit_index(probe: StreamerProbe, expected_cells: Array, label: String) -> void:
	var actual_cells: Array = []
	var recount: Dictionary[Vector2i, int] = {}
	for subcommit in probe._foliage_subcommit_queue:
		actual_cells.append(subcommit.cell)
		recount[subcommit.cell] = int(recount.get(subcommit.cell, 0)) + 1
	if actual_cells != expected_cells:
		_errors.append("foliage subcommit queue order changed " + label)
	if probe._queued_foliage_subcommits_by_cell != recount:
		_errors.append("foliage subcommit index out of sync " + label)


func _check_scatter_spacing_equivalence() -> void:
	for spacing in [1.0, 1.55, 3.2, 5.4]:
		var placed: Array[Vector2] = []
		var buckets: Dictionary[Vector2i, Variant] = {}
		# Exact boundaries, negative coordinates and points either side of a boundary.
		var candidates: Array[Vector2] = [Vector2.ZERO, Vector2(spacing, 0.0), Vector2(-spacing, 0.0), Vector2(spacing - 0.0001, 0.0), Vector2(-spacing + 0.0001, 0.0)]
		for i in range(2000):
			candidates.append(Vector2(float((i * 367) % 7919) * 0.021 - 83.0, float((i * 941) % 7927) * 0.019 - 75.0))
		for candidate in candidates:
			var expected: bool = true
			for point in placed:
				if point.distance_to(candidate) < spacing:
					expected = false
					break
			var actual: bool = ScatterScript._zion_desert_spacing_allowed(buckets, candidate, spacing)
			if actual != expected:
				_errors.append("scatter spacing changed at " + str(candidate) + " spacing=" + str(spacing))
				return
			if expected:
				placed.append(candidate)
				ScatterScript._zion_desert_record_placement(buckets, candidate, spacing)


func _check_upgrade_reuses_foliage() -> void:
	var streamer: Node3D = StreamerScript.new() as Node3D
	add_child(streamer)
	streamer.set("_region_id", "spike_1km")
	const CELL: Vector2i = Vector2i(2, 2)
	streamer.call("_enqueue_build", CELL, 5)
	var queue: Array = streamer.get("_build_queue")
	var coarse_job: Dictionary = queue.pop_front()
	if not bool(coarse_job.get("build_foliage", false)):
		_errors.append("first tile load must generate foliage")
	var coarse: Dictionary = streamer.call("_build_visual_tile_result", coarse_job)
	if not bool(coarse.get("ok", false)) or coarse.get("foliage_tile_data") == null:
		_errors.append("coarse tile must produce terrain and foliage")
		streamer.free()
		return
	var results: Array = streamer.get("_result_queue")
	results.append(coarse)
	streamer.call("_drain_worker_results")
	streamer.call("_enqueue_build", CELL, 1)
	var upgrade_job: Dictionary = queue.pop_front()
	if bool(upgrade_job.get("build_foliage", true)):
		_errors.append("full-res upgrade should reuse prefetched foliage")
	var start_usec: int = Time.get_ticks_usec()
	var upgrade: Dictionary = streamer.call("_build_visual_tile_result", upgrade_job)
	print("streaming_cpu: terrain-only upgrade ms=", float(Time.get_ticks_usec() - start_usec) / 1000.0)
	if not bool(upgrade.get("ok", false)) or upgrade.get("foliage_tile_data") != null:
		_errors.append("terrain-only upgrade must produce terrain without another foliage payload")
	results.append(upgrade)
	streamer.call("_drain_worker_results")
	var ready_foliage: Dictionary = streamer.get("_ready_foliage_data_by_cell")
	if ready_foliage.get(CELL) != coarse.get("foliage_tile_data"):
		_errors.append("upgrade replaced or lost the original foliage payload")
	# Once attachment begins, the ready payload is consumed. Both partial/live
	# nodes and a retained deferred-LOD0 payload must still prevent regeneration.
	ready_foliage.clear()
	var ready_terrain: Dictionary = streamer.get("_ready_tile_data_by_cell")
	ready_terrain.clear()
	for cache_name in ["_partial_foliage_tiles_by_cell", "_foliage_tiles_by_cell", "_deferred_lod0_foliage_data_by_cell"]:
		var cache: Dictionary = streamer.get(cache_name)
		var placeholder: Node3D = Node3D.new()
		cache[CELL] = coarse.get("foliage_tile_data") if cache_name == "_deferred_lod0_foliage_data_by_cell" else placeholder
		streamer.call("_enqueue_build", CELL, 1)
		var retained_job: Dictionary = queue.pop_front()
		if bool(retained_job.get("build_foliage", true)):
			_errors.append("upgrade ignored retained foliage in " + cache_name)
		streamer.call("_cancel_build", CELL)
		cache.erase(CELL)
		placeholder.free()
	streamer.free()


func _measure_spawn_scatter() -> void:
	var spawn: Transform3D = Route.call("spawn_transform", &"zion_wall_vista")
	var tiles: Dictionary[Vector2i, Variant] = {}
	var cells: Array[Vector2i] = ScatterScript.zion_desert_spawn_apron_cells(spawn)
	for cell in cells:
		tiles[cell] = ScatterScript.load_zion_desert_spawn_apron_tile_cell("cedar_hollow_zion", cell)
	var parent: Node3D = Node3D.new()
	add_child(parent)
	var root: Node3D = ScatterScript.create_zion_desert_spawn_apron_root(parent, spawn)
	var start_usec: int = Time.get_ticks_usec()
	var grass: int = ScatterScript.add_zion_desert_spawn_apron_grass(root, tiles, spawn)
	print("streaming_cpu: spawn grass ms=", float(Time.get_ticks_usec() - start_usec) / 1000.0, " instances=", grass)
	var branches: int = ScatterScript.add_zion_desert_spawn_apron_branches(root, tiles, spawn)
	var boulders: int = ScatterScript.add_zion_desert_spawn_apron_boulders(root, tiles, spawn)
	if grass != 620 or branches != 190 or boulders != 96:
		_errors.append("spawn scatter instance counts changed")
	parent.free()
