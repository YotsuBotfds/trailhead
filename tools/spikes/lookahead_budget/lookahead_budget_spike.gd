extends SceneTree

const TERRAIN_DEF_PATH: String = "res://data/terrain/cedar_hollow_terrain_def.tres"
const DEFAULT_OUT_PATH: String = "res://tools/spikes/lookahead_budget/lookahead_budget_results.json"
const PHASE_V_TILE_SIZE_M: float = 100.0
const ACTIVE_RADIUS: int = 2
const PREFETCH_RADIUS: int = 3
const MAX_SPEED_MPS: float = 8.0
const CURRENT_GRID_TILE_COUNT: int = 13
const MEDIUM_GRID_TILE_COUNT: int = 8
const LARGE_GRID_TILE_COUNT: int = 4
const HEAVY_GRID_TILE_COUNT: int = 2
const PHYSICS_SERVER_ACTIVE_LIMIT: int = 8

var _args: Dictionary[String, Variant] = {}
var _world_root: Node3D = null
var _physics_server_rids: Array[RID] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_args = _parse_args(OS.get_cmdline_user_args())
	var out_path: String = _arg_string("out", DEFAULT_OUT_PATH)
	var include_heavy: bool = _arg_bool("heavy", false)
	var repeat: int = maxi(_arg_int("repeat", 1), 1)

	_world_root = Node3D.new()
	_world_root.name = "LookaheadBudgetWorld"
	get_root().add_child(_world_root)
	await process_frame
	await physics_frame

	var started_usec: int = Time.get_ticks_usec()
	var results: Dictionary[String, Variant] = {
		"spike": "lookahead_budget",
		"godot_version": Engine.get_version_info().get("string", "unknown"),
		"physics_engine": ProjectSettings.get_setting("physics/3d/physics_engine", "unknown"),
		"physics_ticks_per_second": ProjectSettings.get_setting("physics/common/physics_ticks_per_second", 0),
		"inputs": {
			"phase_v_tile_size_m": PHASE_V_TILE_SIZE_M,
			"active_radius": ACTIVE_RADIUS,
			"prefetch_radius": PREFETCH_RADIUS,
			"max_speed_mps": MAX_SPEED_MPS,
			"repeat": repeat,
			"include_heavy": include_heavy
		},
		"current_terrain": _current_terrain_summary(),
		"budget_math": _budget_math(),
		"benchmarks": []
	}

	var benchmarks: Array[Variant] = []
	for run_index in range(repeat):
		benchmarks.append(await _measure_committed_resource_load(run_index))
		benchmarks.append(await _measure_synthetic_case("phasev_129x145_node_single_body", 129, 145, CURRENT_GRID_TILE_COUNT, "node_single_body", false, run_index))
		benchmarks.append(await _measure_synthetic_case("phasev_129x145_threaded_physics_server", 129, 145, CURRENT_GRID_TILE_COUNT, "physics_server_body", true, run_index))
		benchmarks.append(await _measure_synthetic_case("phasev_257x257_node_single_body", 257, 257, MEDIUM_GRID_TILE_COUNT, "node_single_body", false, run_index))
		benchmarks.append(await _measure_synthetic_case("phasev_257x257_threaded_physics_server", 257, 257, MEDIUM_GRID_TILE_COUNT, "physics_server_body", true, run_index))
		benchmarks.append(await _measure_synthetic_case("phasev_513x513_node_single_body", 513, 513, LARGE_GRID_TILE_COUNT, "node_single_body", false, run_index))
		benchmarks.append(await _measure_synthetic_case("phasev_513x513_threaded_physics_server", 513, 513, LARGE_GRID_TILE_COUNT, "physics_server_body", true, run_index))
		if include_heavy:
			benchmarks.append(await _measure_synthetic_case("phasev_1181x1181_node_single_body", 1181, 1181, HEAVY_GRID_TILE_COUNT, "node_single_body", false, run_index))
			benchmarks.append(await _measure_synthetic_case("phasev_1181x1181_threaded_physics_server", 1181, 1181, HEAVY_GRID_TILE_COUNT, "physics_server_body", true, run_index))
	results["benchmarks"] = benchmarks
	results["elapsed_ms"] = _us_to_ms(Time.get_ticks_usec() - started_usec)

	_write_json(out_path, results)
	print(JSON.stringify(results, "\t"))
	_cleanup_physics_server_rids()
	_world_root.queue_free()
	quit(0)


func _measure_committed_resource_load(run_index: int) -> Dictionary[String, Variant]:
	var terrain_def: Resource = load(TERRAIN_DEF_PATH)
	var active_tiles: Array[Vector2i] = terrain_def.call("active_tile_indices")
	var collision_paths: Array[String] = terrain_def.get("collision_tile_paths")
	var load_us: Array[int] = []
	var node_bind_us: Array[int] = []
	var activation_us: Array[int] = []
	var settle_us: Array[int] = []
	var total_us: Array[int] = []
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "CommittedResourceBody_" + str(run_index)
	_world_root.add_child(body)
	await physics_frame

	var count: int = mini(active_tiles.size(), collision_paths.size())
	for i in range(count):
		var total_start: int = Time.get_ticks_usec()
		var load_start: int = Time.get_ticks_usec()
		var shape: HeightMapShape3D = ResourceLoader.load(collision_paths[i], "", ResourceLoader.CACHE_MODE_IGNORE) as HeightMapShape3D
		load_us.append(Time.get_ticks_usec() - load_start)
		if shape == null:
			continue
		var bind_start: int = Time.get_ticks_usec()
		var collision: CollisionShape3D = CollisionShape3D.new()
		collision.name = "CommittedCollision_" + str(i)
		collision.shape = shape
		collision.scale = _phase_v_scale(shape)
		collision.position = Vector3(float(i) * PHASE_V_TILE_SIZE_M, 0.0, 0.0)
		node_bind_us.append(Time.get_ticks_usec() - bind_start)
		var activation_start: int = Time.get_ticks_usec()
		body.add_child(collision)
		activation_us.append(Time.get_ticks_usec() - activation_start)
		var settle_start: int = Time.get_ticks_usec()
		await physics_frame
		settle_us.append(Time.get_ticks_usec() - settle_start)
		total_us.append(Time.get_ticks_usec() - total_start)

	body.queue_free()
	await physics_frame
	return {
		"label": "committed_resource_load_node_single_body",
		"run_index": run_index,
		"tile_count": count,
		"grid": _grid_summary_from_current(terrain_def),
		"activation_mode": "node_single_body",
		"source": "committed HeightMapShape3D .tres via ResourceLoader.CACHE_MODE_IGNORE",
		"stats": {
			"resource_load_ms": _stats_ms(load_us),
			"node_bind_ms": _stats_ms(node_bind_us),
			"activation_api_ms": _stats_ms(activation_us),
			"physics_frame_settle_ms": _stats_ms(settle_us),
			"total_per_tile_ms": _stats_ms(total_us)
		}
	}


func _measure_synthetic_case(
	label: String,
	width: int,
	depth: int,
	tile_count: int,
	activation_mode: String,
	threaded_build: bool,
	run_index: int
) -> Dictionary[String, Variant]:
	var data_build_us: Array[int] = []
	var shape_commit_us: Array[int] = []
	var threaded_shape_wall_us: Array[int] = []
	var activation_us: Array[int] = []
	var settle_us: Array[int] = []
	var total_us: Array[int] = []
	var collision_root: StaticBody3D = null
	if activation_mode == "node_single_body":
		collision_root = StaticBody3D.new()
		collision_root.name = label + "_Body_" + str(run_index)
		_world_root.add_child(collision_root)
		await physics_frame

	var count: int = tile_count
	if activation_mode == "physics_server_body":
		count = mini(tile_count, PHYSICS_SERVER_ACTIVE_LIMIT)
	for tile_index in range(count):
		var total_start: int = Time.get_ticks_usec()
		var shape: HeightMapShape3D = null
		if threaded_build:
			var thread_start: int = Time.get_ticks_usec()
			var thread: Thread = Thread.new()
			var start_error: Error = thread.start(Callable(self, "_thread_build_shape").bind(width, depth))
			if start_error != OK:
				push_error("Thread start failed for " + label + ": " + error_string(start_error))
				shape = _build_shape(width, depth, data_build_us, shape_commit_us)
			else:
				var built_shape: Variant = thread.wait_to_finish()
				threaded_shape_wall_us.append(Time.get_ticks_usec() - thread_start)
				shape = built_shape as HeightMapShape3D
		else:
			shape = _build_shape(width, depth, data_build_us, shape_commit_us)
		if shape == null:
			continue

		var activation_start: int = Time.get_ticks_usec()
		if activation_mode == "physics_server_body":
			var rid: RID = _activate_physics_server_body(shape, tile_index)
			_physics_server_rids.append(rid)
		elif collision_root != null:
			var collision: CollisionShape3D = CollisionShape3D.new()
			collision.name = "SyntheticCollision_" + str(tile_index)
			collision.shape = shape
			collision.scale = _phase_v_scale(shape)
			collision.position = Vector3(float(tile_index) * PHASE_V_TILE_SIZE_M, 0.0, 0.0)
			collision_root.add_child(collision)
		activation_us.append(Time.get_ticks_usec() - activation_start)

		var settle_start: int = Time.get_ticks_usec()
		await physics_frame
		settle_us.append(Time.get_ticks_usec() - settle_start)
		total_us.append(Time.get_ticks_usec() - total_start)

	if collision_root != null:
		collision_root.queue_free()
	_cleanup_physics_server_rids()
	await physics_frame

	return {
		"label": label,
		"run_index": run_index,
		"tile_count": count,
		"grid": {
			"map_width": width,
			"map_depth": depth,
			"samples": width * depth,
			"tile_size_m": PHASE_V_TILE_SIZE_M,
			"sample_spacing_x_m": PHASE_V_TILE_SIZE_M / float(maxi(width - 1, 1)),
			"sample_spacing_z_m": PHASE_V_TILE_SIZE_M / float(maxi(depth - 1, 1))
		},
		"activation_mode": activation_mode,
		"source": "synthetic deterministic height data",
		"threaded_build": threaded_build,
		"stats": {
			"data_build_ms": _stats_ms(data_build_us),
			"shape_commit_ms": _stats_ms(shape_commit_us),
			"threaded_shape_wall_ms": _stats_ms(threaded_shape_wall_us),
			"activation_api_ms": _stats_ms(activation_us),
			"physics_frame_settle_ms": _stats_ms(settle_us),
			"total_per_tile_ms": _stats_ms(total_us)
		}
	}


func _build_shape(width: int, depth: int, data_build_us: Array[int], shape_commit_us: Array[int]) -> HeightMapShape3D:
	var data_start: int = Time.get_ticks_usec()
	var map_data: PackedFloat32Array = _build_height_data(width, depth)
	data_build_us.append(Time.get_ticks_usec() - data_start)
	var shape_start: int = Time.get_ticks_usec()
	var shape: HeightMapShape3D = HeightMapShape3D.new()
	shape.map_width = width
	shape.map_depth = depth
	shape.map_data = map_data
	shape_commit_us.append(Time.get_ticks_usec() - shape_start)
	return shape


func _thread_build_shape(width: int, depth: int) -> HeightMapShape3D:
	var ignored_data_us: Array[int] = []
	var ignored_shape_us: Array[int] = []
	return _build_shape(width, depth, ignored_data_us, ignored_shape_us)


func _build_height_data(width: int, depth: int) -> PackedFloat32Array:
	var values: PackedFloat32Array = PackedFloat32Array()
	var sample_count: int = width * depth
	values.resize(sample_count)
	var index: int = 0
	for z_index in range(depth):
		var z_t: float = float(z_index) / float(maxi(depth - 1, 1))
		for x_index in range(width):
			var x_t: float = float(x_index) / float(maxi(width - 1, 1))
			values[index] = (
				sin(x_t * 18.0) * 0.11
				+ cos(z_t * 15.0) * 0.07
				+ sin((x_t + z_t) * 31.0) * 0.025
			)
			index += 1
	return values


func _activate_physics_server_body(shape: HeightMapShape3D, tile_index: int) -> RID:
	var body_rid: RID = PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(body_rid, PhysicsServer3D.BODY_MODE_STATIC)
	var origin: Vector3 = Vector3(float(tile_index) * PHASE_V_TILE_SIZE_M, 0.0, 0.0)
	var transform: Transform3D = Transform3D(Basis(), origin)
	PhysicsServer3D.body_add_shape(body_rid, shape.get_rid(), transform)
	PhysicsServer3D.body_set_space(body_rid, _world_root.get_world_3d().space)
	return body_rid


func _cleanup_physics_server_rids() -> void:
	for rid in _physics_server_rids:
		if rid.is_valid():
			PhysicsServer3D.free_rid(rid)
	_physics_server_rids.clear()


func _phase_v_scale(shape: HeightMapShape3D) -> Vector3:
	return Vector3(
		PHASE_V_TILE_SIZE_M / float(maxi(shape.map_width - 1, 1)),
		1.0,
		PHASE_V_TILE_SIZE_M / float(maxi(shape.map_depth - 1, 1))
	)


func _current_terrain_summary() -> Dictionary[String, Variant]:
	var terrain_def: Resource = load(TERRAIN_DEF_PATH)
	var collision_grid: Vector2i = terrain_def.get("collision_grid")
	var tile_size: Vector2 = terrain_def.get("tile_size")
	var active_tiles: Array[Vector2i] = terrain_def.call("active_tile_indices")
	var spacing_x: float = tile_size.x / float(maxi(collision_grid.x - 1, 1))
	var spacing_z: float = tile_size.y / float(maxi(collision_grid.y - 1, 1))
	return {
		"path": TERRAIN_DEF_PATH,
		"active_tiles": active_tiles.size(),
		"tile_size_m": {"x": tile_size.x, "z": tile_size.y},
		"collision_grid": {"x": collision_grid.x, "z": collision_grid.y},
		"sample_spacing_m": {"x": spacing_x, "z": spacing_z},
		"density_preserving_phase_v_grid": {
			"x": int(ceil(PHASE_V_TILE_SIZE_M / spacing_x)) + 1,
			"z": int(ceil(PHASE_V_TILE_SIZE_M / spacing_z)) + 1
		}
	}


func _grid_summary_from_current(terrain_def: Resource) -> Dictionary[String, Variant]:
	var collision_grid: Vector2i = terrain_def.get("collision_grid")
	return {
		"map_width": collision_grid.x,
		"map_depth": collision_grid.y,
		"samples": collision_grid.x * collision_grid.y,
		"tile_size_m": PHASE_V_TILE_SIZE_M,
		"sample_spacing_x_m": PHASE_V_TILE_SIZE_M / float(maxi(collision_grid.x - 1, 1)),
		"sample_spacing_z_m": PHASE_V_TILE_SIZE_M / float(maxi(collision_grid.y - 1, 1))
	}


func _budget_math() -> Dictionary[String, Variant]:
	var active_diameter: int = ACTIVE_RADIUS * 2 + 1
	var prefetch_diameter: int = PREFETCH_RADIUS * 2 + 1
	var straight_prefetch_delta_tiles: int = prefetch_diameter
	var diagonal_prefetch_delta_tiles: int = prefetch_diameter * 2 - 1
	var straight_active_delta_tiles: int = active_diameter
	var diagonal_active_delta_tiles: int = active_diameter * 2 - 1
	var seconds_per_tile: float = PHASE_V_TILE_SIZE_M / MAX_SPEED_MPS
	return {
		"active_tile_count": active_diameter * active_diameter,
		"prefetch_tile_count": prefetch_diameter * prefetch_diameter,
		"straight_prefetch_delta_tiles_per_crossing": straight_prefetch_delta_tiles,
		"diagonal_prefetch_delta_tiles_per_crossing": diagonal_prefetch_delta_tiles,
		"straight_active_delta_tiles_per_crossing": straight_active_delta_tiles,
		"diagonal_active_delta_tiles_per_crossing": diagonal_active_delta_tiles,
		"seconds_per_100m_tile_at_max_speed": seconds_per_tile,
		"one_ring_prefetch_lead_seconds": seconds_per_tile,
		"active_radius_lead_seconds": seconds_per_tile * float(ACTIVE_RADIUS)
	}


func _stats_ms(values: Array[int]) -> Dictionary[String, Variant]:
	if values.is_empty():
		return {
			"count": 0,
			"min": 0.0,
			"median": 0.0,
			"p95": 0.0,
			"max": 0.0,
			"mean": 0.0
		}
	var sorted_values: Array[int] = []
	var total_us: int = 0
	for value in values:
		sorted_values.append(value)
		total_us += value
	sorted_values.sort()
	var count: int = sorted_values.size()
	return {
		"count": count,
		"min": _us_to_ms(sorted_values[0]),
		"median": _us_to_ms(_percentile_us(sorted_values, 0.50)),
		"p95": _us_to_ms(_percentile_us(sorted_values, 0.95)),
		"max": _us_to_ms(sorted_values[count - 1]),
		"mean": _us_to_ms(total_us) / float(count)
	}


func _percentile_us(sorted_values: Array[int], percentile: float) -> int:
	if sorted_values.is_empty():
		return 0
	var raw_index: int = int(ceil(float(sorted_values.size()) * percentile)) - 1
	var index: int = clampi(raw_index, 0, sorted_values.size() - 1)
	return sorted_values[index]


func _us_to_ms(value_us: int) -> float:
	return float(value_us) / 1000.0


func _parse_args(raw: PackedStringArray) -> Dictionary[String, Variant]:
	var parsed: Dictionary[String, Variant] = {}
	for arg in raw:
		var s: String = String(arg)
		if s.begins_with("--") and s.contains("="):
			var kv: PackedStringArray = s.substr(2).split("=", true, 1)
			if kv.size() == 2:
				parsed[kv[0]] = kv[1]
	return parsed


func _arg_string(key: String, default_value: String) -> String:
	if not _args.has(key):
		return default_value
	return String(_args[key])


func _arg_bool(key: String, default_value: bool) -> bool:
	if not _args.has(key):
		return default_value
	var value: String = String(_args[key]).to_lower()
	return value == "true" or value == "1" or value == "yes"


func _arg_int(key: String, default_value: int) -> int:
	if not _args.has(key):
		return default_value
	return int(_args[key])


func _write_json(path: String, data: Dictionary[String, Variant]) -> void:
	var global_path: String = ProjectSettings.globalize_path(path) if path.begins_with("res://") else path
	var parent_dir: String = global_path.get_base_dir()
	var dir_error: Error = DirAccess.make_dir_recursive_absolute(parent_dir)
	if dir_error != OK:
		push_error("Failed to create output directory " + parent_dir + ": " + error_string(dir_error))
		return
	var file: FileAccess = FileAccess.open(global_path, FileAccess.WRITE)
	if file == null:
		push_error("Failed to open output path: " + global_path)
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.store_string("\n")
	file.close()
