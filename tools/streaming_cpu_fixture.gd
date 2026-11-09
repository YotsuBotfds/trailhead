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

var _errors: PackedStringArray = PackedStringArray()


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_shared_budget()
	_check_scatter_spacing_equivalence()
	_check_upgrade_reuses_foliage()
	_measure_spawn_scatter()
	if _errors.is_empty():
		print("ok: streaming CPU regressions (shared budget, foliage reuse, scatter parity)")
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
