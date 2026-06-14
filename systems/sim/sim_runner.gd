class_name SimRunner
extends Node

const DEFAULT_TARGET: Vector3 = Vector3(3.0, 0.0, 0.0)
const CEDAR_ROUTE_PATH: String = "res://data/routes/cedar_hollow.tres"
const CedarHollowSceneResource: PackedScene = preload("res://scenes/cedar_hollow.tscn")
const VehicleScene: PackedScene = preload("res://scenes/vehicle.tscn")
const VehicleInputScript: GDScript = preload("res://systems/vehicle/vehicle_input.gd")
const FlatWorldBuilderScript: GDScript = preload("res://systems/world/flat_world_builder.gd")
const SurfaceMapScript: GDScript = preload("res://systems/world/surface_map.gd")
const TerrainBuilderScript: GDScript = preload("res://systems/world/terrain_builder.gd")
const PDWaypointControllerScript: GDScript = preload("res://systems/sim/controllers/pd_waypoint_controller.gd")
const ReplayControllerScript: GDScript = preload("res://systems/sim/controllers/replay_controller.gd")
const ScriptedFeelControllerScript: GDScript = preload("res://systems/sim/controllers/scripted_feel_controller.gd")

var _args: Dictionary = {}
var _vehicle: Node = null
var _controller: RefCounted = null
var _route: Resource = null
var _telemetry: Array[Dictionary] = []
var _tick: int = 0
var _max_ticks: int = 6000
var _target: Vector3 = DEFAULT_TARGET
var _target_id: String = "flat_target"
var _target_radius: float = 0.35
var _controller_id: String = "pd"
var _scenario_id: String = ""
var _scene_id: String = "flat_plane"
var _spawn_id: String = "flat_spawn"
var _stuck_window_ticks: int = 180
var _stuck_min_progress: float = 0.05
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _last_input: RefCounted = VehicleInputScript.new()
var _done: bool = false
var _bounds_min: Vector3 = Vector3.ZERO
var _bounds_max: Vector3 = Vector3.ZERO
var _position_history: Array[Vector3] = []
var _never_stuck: bool = true
var _stayed_in_bounds: bool = true
var _upright_or_recovered: bool = true
var _current_flipped_ticks: int = 0
var _max_flipped_ticks_seen: int = 0
var _min_progress_window: float = 999999.0
var _started_flipped: bool = false
var _self_right_input_count: int = 0
var _max_abs_slip_angle_deg: float = 0.0
var _max_pitch_deg: float = -999999.0
var _max_abs_roll_deg: float = 0.0
var _max_abs_yaw_rate: float = 0.0
var _max_speed: float = 0.0
var _previous_speed: float = 0.0
var _ebrake_ticks: int = 0
var _front_air_rear_contact_ticks: int = 0
var _surface_event_count: int = 0
var _flipped_event_count: int = 0
var _self_righted_event_count: int = 0
var _last_surface_event: StringName = &""
var _surface_event_sequence: Array[String] = []
var _surface_contact_ticks: Dictionary = {}
var _surface_speed_sum: Dictionary = {}
var _surface_speed_delta_sum: Dictionary = {}
var _surface_abs_slip_sum: Dictionary = {}
var _surface_max_abs_slip: Dictionary = {}


func _ready() -> void:
	set_physics_process(false)
	_args = _parse_args(OS.get_cmdline_user_args())
	_max_ticks = int(_args.get("max-ticks", 6000))
	_controller_id = String(_args.get("controller", "pd"))
	_scenario_id = String(_args.get("scenario", ""))
	_scene_id = String(_args.get("scene", "flat_plane"))
	_route = _load_route(_scene_id)
	_spawn_id = String(_args.get("spawn", "trailhead" if _route != null else "flat_spawn"))
	_stuck_window_ticks = maxi(int(_args.get("stuck-window", GameConfig.stuck_window_ticks)), 1)
	_stuck_min_progress = maxf(float(_args.get("stuck-min-progress", GameConfig.stuck_min_progress)), 0.0)
	_target_id = String(_args.get("target", "old_cedar" if _route != null else "flat_target"))
	if _route != null and not bool(_route.call("has_spawn", StringName(_spawn_id))):
		_finish_runner_error("Unsupported spawn for route " + String(_route.get("scene_id")) + ": " + _spawn_id)
		return
	if _route != null and not bool(_route.call("has_landmark", StringName(_target_id))):
		_finish_runner_error("Unsupported target for route " + String(_route.get("scene_id")) + ": " + _target_id)
		return
	_target = _parse_target(_target_id)
	_target_radius = _target_radius_for_id(_target_id)
	_rng.seed = int(_args.get("seed", 0))
	_connect_event_bus()
	_configure_flat_bounds()
	_setup_surface_map()
	_setup_flat_scene()
	call_deferred("_begin_run")


func _begin_run() -> void:
	_vehicle = VehicleScene.instantiate()
	add_child(_vehicle)
	_vehicle.call("reset_to", _spawn_transform(_spawn_id))
	var initial_state: RefCounted = _vehicle.call("get_state")
	_started_flipped = bool(initial_state.get("is_flipped"))
	_controller = _make_controller(_controller_id)
	if _controller == null:
		_finish_runner_error("Unsupported controller: " + _controller_id)
		return
	set_physics_process(true)


func _physics_process(_delta: float) -> void:
	if _done or _vehicle == null or _controller == null:
		return
	var state: RefCounted = _vehicle.call("get_state")
	_record(state, _last_input)
	if _has_reached_target(state) or bool(_controller.call("is_done")):
		_done = true
		_finish(true)
		return
	if _tick >= _max_ticks:
		_done = true
		_finish(false)
		return
	var input: RefCounted = _controller.call("next_input", state)
	_vehicle.call("apply_input", input)
	_last_input = input
	_tick += 1


func _parse_args(raw: PackedStringArray) -> Dictionary:
	var out: Dictionary = {}
	for arg in raw:
		var s: String = String(arg)
		if s.begins_with("--") and s.contains("="):
			var kv: PackedStringArray = s.substr(2).split("=", true, 1)
			if kv.size() == 2:
				out[kv[0]] = kv[1]
	return out


func _load_route(scene_id: String) -> Resource:
	if scene_id == TerrainBuilderScript.CEDAR_SCENE_ID:
		return load(CEDAR_ROUTE_PATH) as Resource
	return null


func _make_controller(controller_id: String) -> RefCounted:
	if controller_id == "pd":
		var pd_controller: RefCounted = PDWaypointControllerScript.new()
		pd_controller.call("configure", _target, _target_radius)
		return pd_controller
	if controller_id == "replay":
		var replay_controller: RefCounted = ReplayControllerScript.new()
		replay_controller.call("configure_empty")
		return replay_controller
	if controller_id == "scripted":
		var scripted_controller: RefCounted = ScriptedFeelControllerScript.new()
		scripted_controller.call("configure", _scenario_id)
		return scripted_controller
	return null


func _parse_target(target_id: String) -> Vector3:
	if _route != null:
		return _route.call("landmark_position", StringName(target_id))
	if target_id == "flat_target" or target_id == "":
		return DEFAULT_TARGET
	var parts: PackedStringArray = target_id.split(",", false)
	if parts.size() == 3:
		return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
	return DEFAULT_TARGET


func _target_radius_for_id(target_id: String) -> float:
	var fallback: float = 0.35
	if _route != null:
		fallback = float(_route.call("landmark_radius", StringName(target_id), fallback))
	return float(_args.get("target-radius", fallback))


func _spawn_transform(spawn_id: String) -> Transform3D:
	if _route != null:
		return _route.call("spawn_transform", StringName(spawn_id))
	if spawn_id == "flat_flipped":
		var flipped_basis: Basis = Basis(Vector3.FORWARD, PI)
		return Transform3D(flipped_basis, Vector3(0.0, 0.12, 0.0))
	return Transform3D(Basis.IDENTITY, Vector3(0.0, 0.12, 0.0))


func _setup_flat_scene() -> void:
	if _scene_id == TerrainBuilderScript.CEDAR_SCENE_ID:
		var cedar_scene: Node = CedarHollowSceneResource.instantiate()
		cedar_scene.name = "CedarHollow"
		add_child(cedar_scene)
		return
	if _scene_id == "surface_strips":
		FlatWorldBuilderScript.build_surface_strip_collision(self)
		return
	FlatWorldBuilderScript.build_collision(self)


func _setup_surface_map() -> void:
	var surface_map: Node = SurfaceMapScript.new()
	surface_map.name = "SurfaceMap"
	add_child(surface_map)


func _record(state: RefCounted, input: RefCounted) -> void:
	var state_position: Vector3 = state.get("position")
	var state_velocity: Vector3 = state.get("linear_velocity")
	var state_angular_velocity: Vector3 = state.get("angular_velocity")
	var state_basis: Basis = state.get("basis")
	var pitch_deg: float = _pitch_deg(state_basis)
	var roll_deg: float = _roll_deg(state_basis)
	var speed: float = state_velocity.length()
	var speed_delta: float = speed - _previous_speed
	var slip_angle_deg: float = _slip_angle_deg(state_basis, state_velocity)
	var yaw_rate: float = state_angular_velocity.dot(Vector3.UP)
	var wheel_contact: Array = state.get("wheel_contact")
	var wheel_surface: Array = state.get("wheel_surface")
	var surface_id: StringName = _dominant_surface_from_array(wheel_surface)
	var front_contact_count: int = _contact_count(wheel_contact, 0, 2)
	var rear_contact_count: int = _contact_count(wheel_contact, 2, 4)
	var row: Dictionary = {
		"tick": _tick,
		"position": _vec3_to_array(state_position),
		"linear_velocity": _vec3_to_array(state_velocity),
		"angular_velocity": _vec3_to_array(state_angular_velocity),
		"yaw_rate": yaw_rate,
		"pitch_deg": pitch_deg,
		"roll_deg": roll_deg,
		"speed": speed,
		"speed_delta": speed_delta,
		"slip_angle_deg": slip_angle_deg,
		"wheel_contact_count": front_contact_count + rear_contact_count,
		"front_contact_count": front_contact_count,
		"rear_contact_count": rear_contact_count,
		"wheel_contact": _bool_array_to_array(wheel_contact),
		"wheel_surface": _surface_array_to_array(wheel_surface),
		"surface_id": String(surface_id),
		"on_ground": bool(state.get("on_ground")),
		"is_flipped": bool(state.get("is_flipped")),
		"input": {
			"throttle": float(input.get("throttle")),
			"steer": float(input.get("steer")),
			"brake": float(input.get("brake")),
			"ebrake": bool(input.get("ebrake")),
			"self_right": bool(input.get("self_right"))
		}
	}
	_telemetry.append(row)
	if bool(input.get("self_right")):
		_self_right_input_count += 1
	if bool(input.get("ebrake")):
		_ebrake_ticks += 1
	if front_contact_count == 0 and rear_contact_count > 0:
		_front_air_rear_contact_ticks += 1
	_max_abs_slip_angle_deg = maxf(_max_abs_slip_angle_deg, absf(slip_angle_deg))
	_max_pitch_deg = maxf(_max_pitch_deg, pitch_deg)
	_max_abs_roll_deg = maxf(_max_abs_roll_deg, absf(roll_deg))
	_max_abs_yaw_rate = maxf(_max_abs_yaw_rate, absf(yaw_rate))
	_max_speed = maxf(_max_speed, speed)
	if surface_id != &"" and _tick >= GameConfig.surface_probe_warmup_ticks:
		_record_surface_metrics(surface_id, speed, speed_delta, absf(slip_angle_deg))
	_previous_speed = speed
	_update_predicates(state_position, bool(state.get("is_flipped")))


func _update_predicates(state_position: Vector3, is_flipped: bool) -> void:
	_update_bounds_predicate(state_position)
	_update_flip_predicate(is_flipped)
	_update_stuck_predicate(state_position)


func _update_bounds_predicate(state_position: Vector3) -> void:
	if state_position.x < _bounds_min.x or state_position.x > _bounds_max.x:
		_stayed_in_bounds = false
	if state_position.y < _bounds_min.y or state_position.y > _bounds_max.y:
		_stayed_in_bounds = false
	if state_position.z < _bounds_min.z or state_position.z > _bounds_max.z:
		_stayed_in_bounds = false


func _update_flip_predicate(is_flipped: bool) -> void:
	if is_flipped:
		_current_flipped_ticks += 1
	else:
		_current_flipped_ticks = 0
	_max_flipped_ticks_seen = maxi(_max_flipped_ticks_seen, _current_flipped_ticks)
	if _current_flipped_ticks > GameConfig.max_flipped_ticks:
		_upright_or_recovered = false


func _update_stuck_predicate(state_position: Vector3) -> void:
	_position_history.append(state_position)
	var window_ticks: int = _stuck_window_ticks
	if _position_history.size() <= window_ticks:
		return
	var previous_index: int = _position_history.size() - window_ticks - 1
	var previous_position: Vector3 = _position_history[previous_index]
	var current_flat: Vector3 = Vector3(state_position.x, 0.0, state_position.z)
	var previous_flat: Vector3 = Vector3(previous_position.x, 0.0, previous_position.z)
	var progress: float = current_flat.distance_to(previous_flat)
	_min_progress_window = minf(_min_progress_window, progress)
	if progress < _stuck_min_progress:
		_never_stuck = false


func _has_reached_target(state: RefCounted) -> bool:
	var state_position: Vector3 = state.get("position")
	var delta: Vector3 = _target - state_position
	delta.y = 0.0
	return delta.length() <= _target_radius


func _configure_flat_bounds() -> void:
	if _route != null:
		_bounds_min = _route.get("bounds_min")
		_bounds_max = _route.get("bounds_max")
		return
	if _scene_id == "surface_strips":
		_bounds_min = GameConfig.surface_probe_bounds_min
		_bounds_max = GameConfig.surface_probe_bounds_max
		return
	if _uses_scenario_predicate():
		_bounds_min = GameConfig.flat_probe_bounds_min
		_bounds_max = GameConfig.flat_probe_bounds_max
		return
	var min_x: float = minf(0.0, _target.x) - 1.0
	var max_x: float = maxf(0.0, _target.x) + 1.0
	var min_z: float = minf(0.0, _target.z) - 1.0
	var max_z: float = maxf(0.0, _target.z) + 1.0
	_bounds_min = Vector3(min_x, -1.0, min_z)
	_bounds_max = Vector3(max_x, 2.0, max_z)


func _finish(passed: bool) -> void:
	set_physics_process(false)
	var path: String = String(_args.get("out", "tests/out/flat_target.json"))
	var reached_target: bool = false
	if _telemetry.size() > 0:
		var last_row: Dictionary = _telemetry[_telemetry.size() - 1]
		var last_position_data: Array = last_row["position"]
		var last_position: Vector3 = Vector3(
			float(last_position_data[0]),
			float(last_position_data[1]),
			float(last_position_data[2])
		)
		var target_delta: Vector3 = _target - last_position
		target_delta.y = 0.0
		reached_target = target_delta.length() <= _target_radius
	var target_predicate_passed: bool = reached_target if _requires_target() else true
	var scenario_predicate_passed: bool = _scenario_predicate_passed()
	var surface_event_observed: bool = _surface_event_count > 0
	var event_bus_contract_passed: bool = _event_bus_contract_passed()
	var all_predicates_passed: bool = target_predicate_passed and scenario_predicate_passed and surface_event_observed and event_bus_contract_passed and _never_stuck and _upright_or_recovered and _stayed_in_bounds
	var result: Dictionary = {
		"scene": _scene_id,
		"controller": _controller_id,
		"scenario": _scenario_id,
		"spawn": _spawn_id,
		"target": _target_id,
		"seed": int(_args.get("seed", 0)),
		"ticks": _tick,
		"result": "pass" if (passed and all_predicates_passed) else "fail",
		"predicates": {
			"reached_target": target_predicate_passed,
			"scenario_passed": scenario_predicate_passed,
			"surface_event_observed": surface_event_observed,
			"event_bus_contract": event_bus_contract_passed,
			"never_stuck": _never_stuck,
			"upright_or_recovered": _upright_or_recovered,
			"stayed_in_bounds": _stayed_in_bounds
		},
		"metrics": {
			"target": _vec3_to_array(_target),
			"target_radius": _target_radius,
			"bounds_min": _vec3_to_array(_bounds_min),
			"bounds_max": _vec3_to_array(_bounds_max),
			"max_flipped_ticks": _max_flipped_ticks_seen,
			"started_flipped": _started_flipped,
			"self_right_input_count": _self_right_input_count,
			"max_abs_slip_angle_deg": _max_abs_slip_angle_deg,
			"max_pitch_deg": _max_pitch_deg,
			"max_abs_roll_deg": _max_abs_roll_deg,
			"max_abs_yaw_rate": _max_abs_yaw_rate,
			"max_speed": _max_speed,
			"ebrake_ticks": _ebrake_ticks,
			"front_air_rear_contact_ticks": _front_air_rear_contact_ticks,
			"surface_event_count": _surface_event_count,
			"last_surface_event": String(_last_surface_event),
			"surface_event_sequence": _surface_event_sequence,
			"surface_contact_ticks": _surface_contact_ticks,
			"avg_speed_by_surface": _surface_average_dictionary(_surface_speed_sum),
			"avg_speed_delta_by_surface": _surface_average_dictionary(_surface_speed_delta_sum),
			"max_abs_slip_angle_by_surface": _surface_max_abs_slip,
			"avg_abs_slip_angle_by_surface": _surface_average_dictionary(_surface_abs_slip_sum),
			"flipped_event_count": _flipped_event_count,
			"self_righted_event_count": _self_righted_event_count,
			"min_progress_window": _min_progress_window if _min_progress_window < 999998.0 else null,
			"stuck_window_ticks": _stuck_window_ticks,
			"stuck_min_progress": _stuck_min_progress
		},
		"telemetry": _telemetry
	}
	_write_json(path, result)
	EventBus.sim_completed_run.emit(_target_id, bool(result["result"] == "pass"))
	get_tree().quit(0 if result["result"] == "pass" else 1)


func _finish_runner_error(message: String) -> void:
	set_physics_process(false)
	var path: String = String(_args.get("out", "tests/out/flat_target.json"))
	var result: Dictionary = {
		"scene": _scene_id,
		"controller": _controller_id,
		"scenario": _scenario_id,
		"spawn": _spawn_id,
		"target": _target_id,
		"seed": int(_args.get("seed", 0)),
		"ticks": _tick,
		"result": "error",
		"error": message,
		"predicates": {
			"reached_target": false,
			"surface_event_observed": false,
			"event_bus_contract": false,
			"never_stuck": false,
			"upright_or_recovered": false,
			"stayed_in_bounds": false
		},
		"metrics": {},
		"telemetry": _telemetry
	}
	_write_json(path, result)
	EventBus.sim_completed_run.emit(_target_id, false)
	get_tree().quit(2)


func _write_json(path: String, result: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Failed to write sim output: " + path)
		get_tree().quit(2)
		return
	file.store_string(JSON.stringify(result, "\t"))
	file.close()


func _vec3_to_array(v: Vector3) -> Array[float]:
	return [v.x, v.y, v.z]


func _requires_target() -> bool:
	return not _uses_scenario_predicate()


func _uses_scenario_predicate() -> bool:
	return _controller_id == "scripted" and _scenario_id != ""


func _scenario_predicate_passed() -> bool:
	if not _uses_scenario_predicate():
		return true
	if _scenario_id == "ebrake_drift":
		return _max_abs_slip_angle_deg >= GameConfig.drift_min_peak_slip_angle_deg and _max_abs_yaw_rate >= GameConfig.drift_min_yaw_rate and _ebrake_ticks >= GameConfig.drift_min_ebrake_ticks and _max_speed >= GameConfig.drift_min_speed
	if _scenario_id == "launch_wheelie":
		return _max_pitch_deg >= GameConfig.wheelie_min_peak_pitch_deg and _front_air_rear_contact_ticks >= GameConfig.wheelie_min_front_air_rear_contact_ticks and _max_flipped_ticks_seen == 0
	if _scenario_id == "surface_sweep":
		return _surface_sweep_predicate_passed()
	return false


func _surface_sweep_predicate_passed() -> bool:
	var expected: Array[String] = ["packed_dirt", "tall_grass", "mud", "wet_stone"]
	if not _surface_sequence_contains(expected):
		return false
	for surface_id in expected:
		if int(_surface_contact_ticks.get(surface_id, 0)) < GameConfig.surface_probe_min_ticks_per_surface:
			return false
	var avg_speed: Dictionary = _surface_average_dictionary(_surface_speed_sum)
	var avg_speed_delta: Dictionary = _surface_average_dictionary(_surface_speed_delta_sum)
	var max_slip: Dictionary = _surface_max_abs_slip
	var packed_delta: float = float(avg_speed_delta.get("packed_dirt", 0.0))
	var grass_delta: float = float(avg_speed_delta.get("tall_grass", 0.0))
	var mud_delta: float = float(avg_speed_delta.get("mud", 0.0))
	var packed_slip: float = float(max_slip.get("packed_dirt", 0.0))
	var wet_stone_slip: float = float(max_slip.get("wet_stone", 0.0))
	if avg_speed.is_empty() or packed_delta <= 0.0:
		return false
	if grass_delta >= packed_delta or mud_delta >= grass_delta:
		return false
	if mud_delta > packed_delta - GameConfig.surface_probe_min_mud_speed_delta_drop:
		return false
	if wet_stone_slip < packed_slip + GameConfig.surface_probe_min_wet_stone_slip_gain:
		return false
	return true


func _pitch_deg(basis: Basis) -> float:
	var forward: Vector3 = -basis.z.normalized()
	return rad_to_deg(asin(clampf(forward.y, -1.0, 1.0)))


func _roll_deg(basis: Basis) -> float:
	var right: Vector3 = basis.x.normalized()
	return rad_to_deg(asin(clampf(right.y, -1.0, 1.0)))


func _slip_angle_deg(basis: Basis, velocity: Vector3) -> float:
	var forward: Vector3 = -basis.z
	var forward_flat: Vector3 = Vector3(forward.x, 0.0, forward.z)
	var velocity_flat: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	if forward_flat.length() <= 0.001 or velocity_flat.length() <= 0.001:
		return 0.0
	forward_flat = forward_flat.normalized()
	velocity_flat = velocity_flat.normalized()
	var sign: float = signf(forward_flat.cross(velocity_flat).y)
	return rad_to_deg(forward_flat.angle_to(velocity_flat)) * sign


func _contact_count(wheel_contact: Array, start_index: int, end_index: int) -> int:
	var count: int = 0
	for i in range(start_index, end_index):
		if i < wheel_contact.size() and bool(wheel_contact[i]):
			count += 1
	return count


func _bool_array_to_array(values: Array) -> Array[bool]:
	var out: Array[bool] = []
	for value in values:
		out.append(bool(value))
	return out


func _surface_array_to_array(values: Array) -> Array[String]:
	var out: Array[String] = []
	for value in values:
		out.append(String(value))
	return out


func _dominant_surface_from_array(values: Array) -> StringName:
	var counts: Dictionary = {}
	var best_surface_id: StringName = &""
	var best_count: int = 0
	for value in values:
		var surface_id: StringName = StringName(value)
		if surface_id != &"":
			var current_count: int = int(counts.get(surface_id, 0)) + 1
			counts[surface_id] = current_count
			if current_count > best_count:
				best_surface_id = surface_id
				best_count = current_count
	return best_surface_id


func _record_surface_metrics(surface_id: StringName, speed: float, speed_delta: float, abs_slip_angle_deg: float) -> void:
	var key: String = String(surface_id)
	_surface_contact_ticks[key] = int(_surface_contact_ticks.get(key, 0)) + 1
	_surface_speed_sum[key] = float(_surface_speed_sum.get(key, 0.0)) + speed
	_surface_speed_delta_sum[key] = float(_surface_speed_delta_sum.get(key, 0.0)) + speed_delta
	_surface_abs_slip_sum[key] = float(_surface_abs_slip_sum.get(key, 0.0)) + abs_slip_angle_deg
	_surface_max_abs_slip[key] = maxf(float(_surface_max_abs_slip.get(key, 0.0)), abs_slip_angle_deg)


func _surface_average_dictionary(sums: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key in _surface_contact_ticks.keys():
		var ticks: int = int(_surface_contact_ticks[key])
		if ticks > 0:
			out[key] = float(sums.get(key, 0.0)) / float(ticks)
	return out


func _surface_sequence_contains(expected: Array[String]) -> bool:
	var expected_index: int = 0
	for surface_id in _surface_event_sequence:
		if expected_index < expected.size() and surface_id == expected[expected_index]:
			expected_index += 1
	return expected_index == expected.size()


func _connect_event_bus() -> void:
	if not EventBus.vehicle_changed_surface.is_connected(_on_vehicle_changed_surface):
		EventBus.vehicle_changed_surface.connect(_on_vehicle_changed_surface)
	if not EventBus.vehicle_flipped_over.is_connected(_on_vehicle_flipped_over):
		EventBus.vehicle_flipped_over.connect(_on_vehicle_flipped_over)
	if not EventBus.vehicle_self_righted.is_connected(_on_vehicle_self_righted):
		EventBus.vehicle_self_righted.connect(_on_vehicle_self_righted)


func _event_bus_contract_passed() -> bool:
	if _spawn_id == "flat_flipped":
		return _flipped_event_count > 0 and _self_righted_event_count > 0
	return true


func _on_vehicle_changed_surface(surface_id: StringName) -> void:
	_surface_event_count += 1
	_last_surface_event = surface_id
	var surface_string: String = String(surface_id)
	if _surface_event_sequence.is_empty() or _surface_event_sequence[_surface_event_sequence.size() - 1] != surface_string:
		_surface_event_sequence.append(surface_string)


func _on_vehicle_flipped_over() -> void:
	_flipped_event_count += 1


func _on_vehicle_self_righted() -> void:
	_self_righted_event_count += 1
