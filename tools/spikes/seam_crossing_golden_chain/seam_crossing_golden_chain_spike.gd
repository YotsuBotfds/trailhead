extends Node

const DEFAULT_OUT_PATH: String = "res://tools/spikes/seam_crossing_golden_chain/seam_crossing_golden_chain_results.json"
const DEFAULT_REPLAY_PATH: String = "res://tests/golden/cedar_hollow_segment_pine_floor_to_far_mile_marker_replay.json"
const CEDAR_ROUTE_PATH: String = "res://data/routes/cedar_hollow.tres"
const CEDAR_TERRAIN_DEF_PATH: String = "res://data/terrain/cedar_hollow_terrain_def.tres"
const POSITION_TOLERANCE_M: float = 0.08
const VELOCITY_TOLERANCE_MPS: float = 0.25
const SPEED_TOLERANCE_MPS: float = 0.20
const TARGET_SPLIT_TILE: Vector2i = Vector2i(0, -4)
const INVALID_TILE: Vector2i = Vector2i(999999, 999999)
const CedarHollowSceneResource: PackedScene = preload("res://scenes/cedar_hollow.tscn")
const VehicleScene: PackedScene = preload("res://scenes/vehicle.tscn")
const VehicleInputScript: GDScript = preload("res://systems/vehicle/vehicle_input.gd")
const SurfaceMapScript: GDScript = preload("res://systems/world/surface_map.gd")
const LandmarksScript: GDScript = preload("res://systems/world/landmarks.gd")

var _args: Dictionary[String, Variant] = {}
var _terrain_def: Resource = null


class ReplayRun:
	extends Node

	var label: String = ""
	var replay_inputs: Array[Dictionary] = []
	var route: Resource = null
	var terrain_def: Resource = null
	var spawn_transform: Transform3D = Transform3D.IDENTITY
	var start_tick: int = 0
	var end_tick: int = 0
	var inject_state: Dictionary = {}
	var finished: bool = false
	var result: Dictionary = {}

	var _surface_map: Node = null
	var _landmarks: Node = null
	var _vehicle: Node = null
	var _tick: int = 0
	var _telemetry: Array[Dictionary] = []
	var _surface_event_sequence: Array[String] = []
	var _landmark_event_sequence: Array[String] = []


	func _ready() -> void:
		set_physics_process(false)
		_tick = start_tick
		_connect_event_bus()
		_surface_map = SurfaceMapScript.new()
		_surface_map.name = "SurfaceMap"
		add_child(_surface_map)
		_landmarks = LandmarksScript.new()
		_landmarks.name = "Landmarks"
		add_child(_landmarks)
		_landmarks.call("configure", route)
		var cedar_scene: Node = CedarHollowSceneResource.instantiate()
		cedar_scene.name = "CedarHollow"
		add_child(cedar_scene)
		_vehicle = VehicleScene.instantiate()
		_vehicle.name = "Vehicle"
		add_child(_vehicle)
		call_deferred("_begin")


	func _exit_tree() -> void:
		_disconnect_event_bus()


	func _begin() -> void:
		if _surface_map == null or _vehicle == null:
			_finish_error("run setup failed")
			return
		if not bool(_surface_map.call("configure_terrain_def", CEDAR_TERRAIN_DEF_PATH)):
			_finish_error("failed to configure Cedar terrain surface map")
			return
		_vehicle.call("reset_to", spawn_transform)
		if not inject_state.is_empty():
			if not _inject_body_state():
				return
		set_physics_process(true)


	func _physics_process(_delta: float) -> void:
		if finished or _vehicle == null:
			return
		var state: RefCounted = _vehicle.call("get_state")
		_record(state)
		if _tick >= end_tick:
			_finish_ok()
			return
		if _tick < 0 or _tick >= replay_inputs.size():
			_finish_error("missing replay input at tick " + str(_tick))
			return
		var input_data: Dictionary = replay_inputs[_tick]
		var input: RefCounted = VehicleInputScript.new()
		input.set("throttle", clampf(float(input_data.get("throttle", 0.0)), -1.0, 1.0))
		input.set("steer", clampf(float(input_data.get("steer", 0.0)), -1.0, 1.0))
		input.set("brake", clampf(float(input_data.get("brake", 0.0)), 0.0, 1.0))
		input.set("ebrake", bool(input_data.get("ebrake", false)))
		input.set("self_right", bool(input_data.get("self_right", false)))
		_vehicle.call("apply_input", input)
		_tick += 1


	func _connect_event_bus() -> void:
		if not EventBus.vehicle_changed_surface.is_connected(_on_vehicle_changed_surface):
			EventBus.vehicle_changed_surface.connect(_on_vehicle_changed_surface)
		if not EventBus.world_reached_landmark.is_connected(_on_world_reached_landmark):
			EventBus.world_reached_landmark.connect(_on_world_reached_landmark)


	func _disconnect_event_bus() -> void:
		if EventBus.vehicle_changed_surface.is_connected(_on_vehicle_changed_surface):
			EventBus.vehicle_changed_surface.disconnect(_on_vehicle_changed_surface)
		if EventBus.world_reached_landmark.is_connected(_on_world_reached_landmark):
			EventBus.world_reached_landmark.disconnect(_on_world_reached_landmark)


	func _on_vehicle_changed_surface(surface_id: StringName) -> void:
		_surface_event_sequence.append(String(surface_id))


	func _on_world_reached_landmark(landmark_id: StringName) -> void:
		_landmark_event_sequence.append(String(landmark_id))


	func _record(state: RefCounted) -> void:
		var position: Vector3 = state.get("position")
		var basis: Basis = state.get("basis")
		var linear_velocity: Vector3 = state.get("linear_velocity")
		var angular_velocity: Vector3 = state.get("angular_velocity")
		var wheel_contact: Variant = state.get("wheel_contact")
		var wheel_surface: Variant = state.get("wheel_surface")
		var wheel_hit_point: Variant = state.get("wheel_hit_point")
		if _landmarks != null:
			_landmarks.call("sample_position", position)
		var row_collision_tiles: Array[Vector2i] = _state_collision_tiles(position, wheel_contact, wheel_hit_point)
		var row: Dictionary = {
			"tick": _tick,
			"position": _vec3_to_array(position),
			"basis": _basis_to_array(basis),
			"linear_velocity": _vec3_to_array(linear_velocity),
			"angular_velocity": _vec3_to_array(angular_velocity),
			"speed": linear_velocity.length(),
			"body_tile": _tile_to_array(_tile_for_position(position)),
			"collision_tiles": _tile_array_to_arrays(row_collision_tiles),
			"wheel_surface": _surface_array_to_array(wheel_surface)
		}
		_telemetry.append(row)


	func _state_collision_tiles(position: Vector3, wheel_contact: Variant, wheel_hit_point: Variant) -> Array[Vector2i]:
		var tiles: Array[Vector2i] = []
		_append_unique_tile(tiles, _tile_for_position(position))
		if not (wheel_contact is Array) or not (wheel_hit_point is Array):
			return tiles
		var contacts: Array = wheel_contact
		var points: Array = wheel_hit_point
		var count: int = mini(contacts.size(), points.size())
		for i in range(count):
			if not bool(contacts[i]):
				continue
			if not (points[i] is Vector3):
				continue
			_append_unique_tile(tiles, _tile_for_position(points[i]))
		return tiles


	func _append_unique_tile(tiles: Array[Vector2i], tile: Vector2i) -> void:
		if tile == INVALID_TILE:
			return
		if not tiles.has(tile):
			tiles.append(tile)


	func _tile_for_position(position: Vector3) -> Vector2i:
		if terrain_def == null:
			return INVALID_TILE
		var world_xz: Vector2 = Vector2(position.x, position.z)
		if not bool(terrain_def.call("contains_world_xz", world_xz)):
			return INVALID_TILE
		return terrain_def.call("tile_index_for_world_xz", world_xz)


	func _inject_body_state() -> bool:
		var body: RigidBody3D = _physics_body()
		if body == null:
			_finish_error("vehicle physics body not found for injection")
			return false
		var transform: Transform3D = inject_state.get("transform", Transform3D.IDENTITY)
		var linear_velocity: Vector3 = inject_state.get("linear_velocity", Vector3.ZERO)
		var angular_velocity: Vector3 = inject_state.get("angular_velocity", Vector3.ZERO)
		body.sleeping = false
		PhysicsServer3D.body_set_state(body.get_rid(), PhysicsServer3D.BODY_STATE_SLEEPING, false)
		PhysicsServer3D.body_set_state(body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, transform)
		PhysicsServer3D.body_set_state(body.get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, linear_velocity)
		PhysicsServer3D.body_set_state(body.get_rid(), PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, angular_velocity)
		body.global_transform = transform
		body.linear_velocity = linear_velocity
		body.angular_velocity = angular_velocity
		return true


	func _physics_body() -> RigidBody3D:
		if _vehicle == null:
			return null
		return _vehicle.get_node_or_null("PhysicsBody") as RigidBody3D


	func _finish_ok() -> void:
		set_physics_process(false)
		var snapshot: Dictionary = _snapshot()
		result = {
			"label": label,
			"start_tick": start_tick,
			"end_tick": end_tick,
			"rows": _telemetry,
			"snapshot": snapshot,
			"summary": _summary(snapshot),
			"events": {
				"vehicle_changed_surface": _surface_event_sequence,
				"world_reached_landmark": _landmark_event_sequence
			},
			"collision_tiles_manifest": _collision_tiles_manifest()
		}
		finished = true


	func _finish_error(message: String) -> void:
		set_physics_process(false)
		result = {
			"label": label,
			"start_tick": start_tick,
			"end_tick": end_tick,
			"error": message,
			"rows": _telemetry,
			"events": {
				"vehicle_changed_surface": _surface_event_sequence,
				"world_reached_landmark": _landmark_event_sequence
			},
			"collision_tiles_manifest": _collision_tiles_manifest()
		}
		finished = true


	func _snapshot() -> Dictionary:
		var body: RigidBody3D = _physics_body()
		if body == null:
			return {
				"transform": Transform3D.IDENTITY,
				"linear_velocity": Vector3.ZERO,
				"angular_velocity": Vector3.ZERO
			}
		return {
			"transform": body.global_transform,
			"linear_velocity": body.linear_velocity,
			"angular_velocity": body.angular_velocity
		}


	func _summary(snapshot: Dictionary) -> Dictionary:
		var transform: Transform3D = snapshot.get("transform", Transform3D.IDENTITY)
		var linear_velocity: Vector3 = snapshot.get("linear_velocity", Vector3.ZERO)
		var angular_velocity: Vector3 = snapshot.get("angular_velocity", Vector3.ZERO)
		return {
			"final_position": _vec3_to_array(transform.origin),
			"final_basis": _basis_to_array(transform.basis),
			"final_linear_velocity": _vec3_to_array(linear_velocity),
			"final_angular_velocity": _vec3_to_array(angular_velocity),
			"final_speed": linear_velocity.length(),
			"row_count": _telemetry.size()
		}


	func _collision_tiles_manifest() -> Dictionary:
		var body_tiles: Array[Vector2i] = []
		var contact_tiles: Array[Vector2i] = []
		var all_tiles: Array[Vector2i] = []
		var crossing_count: int = 0
		var previous_tile: Vector2i = INVALID_TILE
		for row in _telemetry:
			var body_tile: Vector2i = _tile_from_array(row.get("body_tile", []))
			if body_tile != INVALID_TILE:
				_append_unique_tile(body_tiles, body_tile)
				_append_unique_tile(all_tiles, body_tile)
				if previous_tile != INVALID_TILE and body_tile != previous_tile:
					crossing_count += 1
				previous_tile = body_tile
			var row_tiles: Variant = row.get("collision_tiles", [])
			if row_tiles is Array:
				for tile_value in row_tiles:
					var contact_tile: Vector2i = _tile_from_array(tile_value)
					_append_unique_tile(contact_tiles, contact_tile)
					_append_unique_tile(all_tiles, contact_tile)
		return {
			"body_tiles": _tile_array_to_arrays(body_tiles),
			"contact_tiles": _tile_array_to_arrays(contact_tiles),
			"collision_tiles": _tile_array_to_arrays(all_tiles),
			"body_tile_crossings": crossing_count
		}


	func _vec3_to_array(v: Vector3) -> Array[float]:
		return [v.x, v.y, v.z]


	func _basis_to_array(basis: Basis) -> Array[Variant]:
		return [
			_vec3_to_array(basis.x),
			_vec3_to_array(basis.y),
			_vec3_to_array(basis.z)
		]


	func _tile_to_array(tile: Vector2i) -> Array[int]:
		return [tile.x, tile.y]


	func _tile_from_array(value: Variant) -> Vector2i:
		if not (value is Array):
			return INVALID_TILE
		var values: Array = value
		if values.size() < 2:
			return INVALID_TILE
		return Vector2i(int(values[0]), int(values[1]))


	func _tile_array_to_arrays(tiles: Array[Vector2i]) -> Array[Variant]:
		var out: Array[Variant] = []
		for tile in tiles:
			out.append(_tile_to_array(tile))
		return out


	func _surface_array_to_array(values: Variant) -> Array[String]:
		var out: Array[String] = []
		if not (values is Array):
			return out
		for value in values:
			out.append(String(value))
		return out


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_args = _parse_args(OS.get_cmdline_user_args())
	var out_path: String = _arg_string("out", DEFAULT_OUT_PATH)
	var replay_path: String = _arg_string("replay", DEFAULT_REPLAY_PATH)
	var replay: Dictionary = _load_replay(replay_path)
	if replay.is_empty():
		get_tree().quit(2)
		return
	var replay_inputs: Array[Dictionary] = _replay_inputs(replay)
	if replay_inputs.is_empty():
		_fail("Replay has no inputs: " + replay_path)
		return
	_terrain_def = load(CEDAR_TERRAIN_DEF_PATH)
	if _terrain_def == null:
		_fail("Failed to load TerrainDef: " + CEDAR_TERRAIN_DEF_PATH)
		return
	var route: Resource = load(CEDAR_ROUTE_PATH)
	if route == null:
		_fail("Failed to load Cedar route: " + CEDAR_ROUTE_PATH)
		return
	var route_errors: PackedStringArray = route.call("validate")
	if route_errors.size() > 0:
		_fail("Invalid Cedar route: " + _join_errors(route_errors))
		return
	var spawn_id: StringName = StringName(String(replay.get("spawn", "pine_floor")))
	var spawn_transform: Transform3D = route.call("spawn_transform", spawn_id)
	var total_ticks: int = replay_inputs.size()

	var continuous: Dictionary = await _run_replay("single_full_crossing", replay_inputs, route, spawn_transform, 0, total_ticks, {})
	if continuous.has("error"):
		_write_failure(out_path, replay_path, replay, continuous)
		return
	var split_tick: int = _arg_int("split-tick", _first_tick_entering_tile(continuous.get("rows", []), TARGET_SPLIT_TILE))
	if split_tick <= 0 or split_tick >= total_ticks:
		split_tick = total_ticks / 2
	var segment_a: Dictionary = await _run_replay("segment_a", replay_inputs, route, spawn_transform, 0, split_tick, {})
	if segment_a.has("error"):
		_write_failure(out_path, replay_path, replay, segment_a)
		return
	var injection_state: Dictionary = segment_a.get("snapshot", {})
	var segment_b: Dictionary = await _run_replay("segment_b_injected", replay_inputs, route, spawn_transform, split_tick, total_ticks, injection_state)
	if segment_b.has("error"):
		_write_failure(out_path, replay_path, replay, segment_b)
		return

	var comparison: Dictionary = _compare_runs(continuous, segment_a, segment_b, split_tick)
	var passed: bool = bool(comparison.get("passed", false))
	var results: Dictionary = {
		"spike": "seam_crossing_golden_chain",
		"hypothesis": "Two chained Cedar replay segments with segment B body-state injection reproduce one full crossing within D10 tolerances.",
		"godot_version": Engine.get_version_info().get("string", "unknown"),
		"physics_engine": ProjectSettings.get_setting("physics/3d/physics_engine", "unknown"),
		"physics_ticks_per_second": ProjectSettings.get_setting("physics/common/physics_ticks_per_second", 0),
		"replay_path": replay_path,
		"replay_name": replay.get("name", ""),
		"route_segment": replay.get("route_segment", ""),
		"seed": int(replay.get("seed", 0)),
		"split": {
			"split_tick": split_tick,
			"target_split_tile": _tile_to_array(TARGET_SPLIT_TILE),
			"total_ticks": total_ticks
		},
		"tolerances": {
			"position_m": POSITION_TOLERANCE_M,
			"velocity_mps": VELOCITY_TOLERANCE_MPS,
			"speed_mps": SPEED_TOLERANCE_MPS
		},
		"single_full_crossing": _run_result_for_json(continuous),
		"segments": [
			_run_result_for_json(segment_a),
			_run_result_for_json(segment_b)
		],
		"comparison": comparison,
		"pass": passed,
		"limitations": [
			"Spike-local harness replays existing golden inputs instead of adding production sim_runner hooks.",
			"Segment B transfers transform, linear velocity, and angular velocity; render state and replay-controller state are not involved.",
			"Vehicle contamination and EventBus history are not injected because they do not affect current vehicle dynamics for this replay."
		],
		"production_recommendation": "Add a gated sim_runner hook that can export and import transform, linear_velocity, angular_velocity, and a collision_tiles manifest at segment boundaries, then run the existing golden comparison around the chained replay."
	}
	_write_json(out_path, results)
	print(JSON.stringify({
		"pass": passed,
		"out": out_path,
		"split_tick": split_tick,
		"final_position_delta_m": comparison.get("final_position_delta_m", null),
		"final_velocity_delta_mps": comparison.get("final_velocity_delta_mps", null),
		"final_speed_delta_mps": comparison.get("final_speed_delta_mps", null)
	}, "\t"))
	get_tree().quit(0 if passed else 1)


func _run_replay(
	label: String,
	replay_inputs: Array[Dictionary],
	route: Resource,
	spawn_transform: Transform3D,
	start_tick: int,
	end_tick: int,
	inject_state: Dictionary
) -> Dictionary:
	var runner: Node = ReplayRun.new()
	runner.set("label", label)
	runner.set("replay_inputs", replay_inputs)
	runner.set("route", route)
	runner.set("terrain_def", _terrain_def)
	runner.set("spawn_transform", spawn_transform)
	runner.set("start_tick", start_tick)
	runner.set("end_tick", end_tick)
	runner.set("inject_state", inject_state)
	get_tree().root.add_child(runner)
	while not bool(runner.get("finished")):
		await get_tree().physics_frame
	var result: Dictionary = runner.get("result")
	runner.queue_free()
	await get_tree().process_frame
	await get_tree().physics_frame
	return result


func _compare_runs(
	continuous: Dictionary,
	segment_a: Dictionary,
	segment_b: Dictionary,
	split_tick: int
) -> Dictionary:
	var continuous_rows: Array = continuous.get("rows", [])
	var chain_rows: Array[Dictionary] = []
	var segment_a_rows: Array = segment_a.get("rows", [])
	var segment_b_rows: Array = segment_b.get("rows", [])
	for row in segment_a_rows:
		if row is Dictionary:
			chain_rows.append(row)
	for row in segment_b_rows:
		if row is Dictionary and int(row.get("tick", -1)) > split_tick:
			chain_rows.append(row)
	var continuous_by_tick: Dictionary = _rows_by_tick(continuous_rows)
	var chain_by_tick: Dictionary = _rows_by_tick(chain_rows)
	var max_position_delta: float = 0.0
	var max_velocity_delta: float = 0.0
	var max_speed_delta: float = 0.0
	var compared_rows: int = 0
	for tick in chain_by_tick.keys():
		if not continuous_by_tick.has(tick):
			continue
		var continuous_row: Dictionary = continuous_by_tick[tick]
		var chain_row: Dictionary = chain_by_tick[tick]
		max_position_delta = maxf(max_position_delta, _vec3_array_distance(continuous_row.get("position", []), chain_row.get("position", [])))
		max_velocity_delta = maxf(max_velocity_delta, _vec3_array_distance(continuous_row.get("linear_velocity", []), chain_row.get("linear_velocity", [])))
		max_speed_delta = maxf(max_speed_delta, absf(float(continuous_row.get("speed", 0.0)) - float(chain_row.get("speed", 0.0))))
		compared_rows += 1
	var continuous_final: Dictionary = _last_row(continuous_rows)
	var chain_final: Dictionary = _last_row(chain_rows)
	var final_position_delta: float = _vec3_array_distance(continuous_final.get("position", []), chain_final.get("position", []))
	var final_velocity_delta: float = _vec3_array_distance(continuous_final.get("linear_velocity", []), chain_final.get("linear_velocity", []))
	var final_speed_delta: float = absf(float(continuous_final.get("speed", 0.0)) - float(chain_final.get("speed", 0.0)))
	var passed: bool = final_position_delta <= POSITION_TOLERANCE_M and final_velocity_delta <= VELOCITY_TOLERANCE_MPS and final_speed_delta <= SPEED_TOLERANCE_MPS
	return {
		"passed": passed,
		"compared_rows": compared_rows,
		"chain_rows": chain_rows.size(),
		"single_rows": continuous_rows.size(),
		"final_position_delta_m": final_position_delta,
		"final_velocity_delta_mps": final_velocity_delta,
		"final_speed_delta_mps": final_speed_delta,
		"max_position_delta_m": max_position_delta,
		"max_velocity_delta_mps": max_velocity_delta,
		"max_speed_delta_mps": max_speed_delta,
		"final_single": continuous_final,
		"final_chain": chain_final
	}


func _rows_by_tick(rows: Array) -> Dictionary:
	var out: Dictionary = {}
	for row_value in rows:
		if not (row_value is Dictionary):
			continue
		var row: Dictionary = row_value
		out[int(row.get("tick", -1))] = row
	return out


func _last_row(rows: Array) -> Dictionary:
	if rows.is_empty():
		return {}
	var last_value: Variant = rows[rows.size() - 1]
	if last_value is Dictionary:
		return last_value
	return {}


func _first_tick_entering_tile(rows_value: Variant, target_tile: Vector2i) -> int:
	if not (rows_value is Array):
		return -1
	var rows: Array = rows_value
	for row_value in rows:
		if not (row_value is Dictionary):
			continue
		var row: Dictionary = row_value
		if _tile_from_array(row.get("body_tile", [])) == target_tile:
			return int(row.get("tick", -1))
	return -1


func _run_result_for_json(run_result: Dictionary) -> Dictionary:
	var summary: Variant = run_result.get("summary", {})
	var events: Variant = run_result.get("events", {})
	var manifest: Variant = run_result.get("collision_tiles_manifest", {})
	var rows: Array = run_result.get("rows", [])
	return {
		"label": run_result.get("label", ""),
		"start_tick": run_result.get("start_tick", 0),
		"end_tick": run_result.get("end_tick", 0),
		"summary": summary,
		"events": events,
		"collision_tiles_manifest": manifest,
		"row_count": rows.size()
	}


func _load_replay(path: String) -> Dictionary:
	var text: String = FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("Failed to read replay: " + path)
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_error("Replay root is not a dictionary: " + path)
		return {}
	return parsed


func _replay_inputs(replay: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var inputs_value: Variant = replay.get("inputs", [])
	if not (inputs_value is Array):
		return out
	var inputs: Array = inputs_value
	for value in inputs:
		if value is Dictionary:
			out.append(value)
	return out


func _parse_args(raw: PackedStringArray) -> Dictionary[String, Variant]:
	var out: Dictionary[String, Variant] = {}
	for arg in raw:
		var s: String = String(arg)
		if s.begins_with("--") and s.contains("="):
			var kv: PackedStringArray = s.substr(2).split("=", true, 1)
			if kv.size() == 2:
				out[kv[0]] = kv[1]
	return out


func _arg_string(key: String, fallback: String) -> String:
	return String(_args.get(key, fallback))


func _arg_int(key: String, fallback: int) -> int:
	return int(_args.get(key, fallback))


func _write_failure(out_path: String, replay_path: String, replay: Dictionary, failure: Dictionary) -> void:
	var result: Dictionary = {
		"spike": "seam_crossing_golden_chain",
		"replay_path": replay_path,
		"replay_name": replay.get("name", ""),
		"pass": false,
		"failure": _run_result_for_json(failure),
		"error": failure.get("error", "unknown failure")
	}
	_write_json(out_path, result)
	push_error(String(result.get("error", "unknown failure")))
	get_tree().quit(1)


func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(2)


func _write_json(path: String, result: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Failed to write spike output: " + path)
		get_tree().quit(2)
		return
	file.store_string(JSON.stringify(result, "\t") + "\n")
	file.close()


func _join_errors(errors: PackedStringArray) -> String:
	var out: String = ""
	for i in range(errors.size()):
		if i > 0:
			out += "; "
		out += errors[i]
	return out


func _vec3_array_distance(a_value: Variant, b_value: Variant) -> float:
	var a: Vector3 = _vec3_from_array(a_value)
	var b: Vector3 = _vec3_from_array(b_value)
	return a.distance_to(b)


func _vec3_from_array(value: Variant) -> Vector3:
	if not (value is Array):
		return Vector3.ZERO
	var values: Array = value
	if values.size() < 3:
		return Vector3.ZERO
	return Vector3(float(values[0]), float(values[1]), float(values[2]))


func _tile_to_array(tile: Vector2i) -> Array[int]:
	return [tile.x, tile.y]


func _tile_from_array(value: Variant) -> Vector2i:
	if not (value is Array):
		return INVALID_TILE
	var values: Array = value
	if values.size() < 2:
		return INVALID_TILE
	return Vector2i(int(values[0]), int(values[1]))
