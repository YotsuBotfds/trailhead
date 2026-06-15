class_name SimRunner
extends Node

const DEFAULT_TARGET: Vector3 = Vector3(3.0, 0.0, 0.0)
const CEDAR_ROUTE_PATH: String = "res://data/routes/cedar_hollow.tres"
const CEDAR_TERRAIN_DEF_PATH: String = "res://data/terrain/cedar_hollow_terrain_def.tres"
const CedarHollowSceneResource: PackedScene = preload("res://scenes/cedar_hollow.tscn")
const CedarHollow10mSceneResource: PackedScene = preload("res://scenes/test_zion_10m.tscn")
const VehicleScene: PackedScene = preload("res://scenes/vehicle.tscn")
const VehicleInputScript: GDScript = preload("res://systems/vehicle/vehicle_input.gd")
const SurfaceMapScript: GDScript = preload("res://systems/world/surface_map.gd")
const FlatWorldBuilderScript: GDScript = preload("res://systems/world/flat_world_builder.gd")
const TerrainBuilderScript: GDScript = preload("res://systems/world/terrain_builder.gd")
const LandmarksScript: GDScript = preload("res://systems/world/landmarks.gd")
const PDWaypointControllerScript: GDScript = preload("res://systems/sim/controllers/pd_waypoint_controller.gd")
const ReplayControllerScript: GDScript = preload("res://systems/sim/controllers/replay_controller.gd")
const ScriptedFeelControllerScript: GDScript = preload("res://systems/sim/controllers/scripted_feel_controller.gd")

var _args: Dictionary[String, Variant] = {}
var _vehicle: Node = null
var _controller: RefCounted = null
var _surface_map: Node = null
var _route: Resource = null
var _landmarks: Node = null
# GDScript 4.6 cannot express key/value types inside Array[Dictionary].
var _telemetry: Array[Dictionary] = []
var _tick: int = 0
var _max_ticks: int = 6000
var _target: Vector3 = DEFAULT_TARGET
var _target_id: String = "flat_target"
var _target_radius: float = 0.0
var _route_segment_id: String = ""
var _waypoints: Array[Vector3] = []
var _controller_id: String = "pd"
var _scenario_id: String = ""
var _scene_id: String = "flat_plane"
var _spawn_id: String = "flat_spawn"
var _controller_config_error: String = ""
var _stuck_window_ticks: int = 180
var _stuck_min_progress: float = 0.05
# All sim-runner randomness must flow through this seeded RNG.
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
var _initial_position: Vector3 = Vector3.ZERO
var _initial_forward: Vector3 = Vector3.FORWARD
var _initial_control_right: Vector3 = Vector3.LEFT
var _initial_heading_deg: float = 0.0
var _self_right_heading_error_deg: float = 999999.0
var _self_right_heading_captured: bool = false
var _max_abs_slip_angle_deg: float = 0.0
var _max_y_position: float = -999999.0
var _max_pitch_deg: float = -999999.0
var _max_abs_roll_deg: float = 0.0
var _max_abs_yaw_rate: float = 0.0
var _contact_normal_sample_ticks: int = 0
var _max_contact_normal_tilt_deg: float = 0.0
var _contact_normal_min_y: float = 1.0
var _max_abs_lateral_speed: float = 0.0
var _final_abs_lateral_speed: float = 0.0
var _chassis_clearance_sample_ticks: int = 0
var _min_chassis_clearance_m: float = 999999.0
var _max_chassis_penetration_m: float = 0.0
var _steering_speed_low_sample_ticks: int = 0
var _steering_speed_mid_sample_ticks: int = 0
var _steering_speed_high_sample_ticks: int = 0
var _steering_speed_low_max_abs_yaw_rate: float = 0.0
var _steering_speed_mid_max_abs_yaw_rate: float = 0.0
var _steering_speed_high_max_abs_yaw_rate: float = 0.0
var _post_settle_min_y: float = 999999.0
var _post_settle_max_y: float = -999999.0
var _max_post_settle_vertical_speed: float = 0.0
var _resting_ride_height_sample_ticks: int = 0
var _resting_ride_height_all_contact_ticks: int = 0
var _resting_ride_height_min_y: float = 999999.0
var _resting_ride_height_max_y: float = -999999.0
var _resting_ride_height_final_y: float = 0.0
var _resting_ride_height_max_abs_vertical_speed: float = 0.0
var _max_speed: float = 0.0
var _previous_speed: float = 0.0
var _ebrake_ticks: int = 0
var _reverse_ticks: int = 0
var _min_initial_forward_displacement: float = 999999.0
var _max_initial_forward_displacement: float = 0.0
var _max_descent_from_initial: float = 0.0
var _max_reverse_distance: float = 0.0
var _max_flat_displacement_from_initial: float = 0.0
var _final_flat_displacement_from_initial: float = 0.0
var _min_control_right_displacement: float = 999999.0
var _max_control_right_displacement: float = -999999.0
var _final_control_right_displacement: float = 0.0
var _front_air_rear_contact_ticks: int = 0
var _surface_event_count: int = 0
var _landmark_event_count: int = 0
var _flipped_event_count: int = 0
var _self_righted_event_count: int = 0
var _recovered_to_trail_event_count: int = 0
var _max_recovery_displacement: float = 0.0
var _last_surface_event: StringName = &""
var _last_landmark_event: StringName = &""
var _surface_event_sequence: Array[String] = []
var _landmark_event_sequence: Array[String] = []
var _surface_contact_ticks: Dictionary[String, int] = {}
var _surface_speed_sum: Dictionary[String, float] = {}
var _surface_speed_delta_sum: Dictionary[String, float] = {}
var _surface_abs_slip_sum: Dictionary[String, float] = {}
var _surface_max_abs_slip: Dictionary[String, float] = {}
var _max_contamination_mud: float = 0.0
var _max_contamination_dust: float = 0.0
var _max_contamination_wetness: float = 0.0
var _final_vehicle_contamination: Dictionary[String, float] = {}


func _ready() -> void:
	set_physics_process(false)
	_args = _parse_args(OS.get_cmdline_user_args())
	_max_ticks = int(_args.get("max-ticks", 6000))
	_controller_id = String(_args.get("controller", "pd"))
	_scenario_id = String(_args.get("scenario", ""))
	_scene_id = String(_args.get("scene", "flat_plane"))
	_route = _load_route(_scene_id)
	_route_segment_id = String(_args.get("route-segment", ""))
	if _route != null:
		var route_errors: PackedStringArray = _route.call("validate")
		if route_errors.size() > 0:
			_finish_runner_error("Invalid route " + String(_route.get("scene_id")) + ": " + _join_packed_strings(route_errors, "; "))
			return
	if _route != null and _route_segment_id != "":
		if not bool(_route.call("has_segment", StringName(_route_segment_id))):
			_finish_runner_error("Unsupported route segment for route " + String(_route.get("scene_id")) + ": " + _route_segment_id)
			return
		if _args.has("spawn") or _args.has("target"):
			_finish_runner_error("Route segment owns spawn and target: " + _route_segment_id)
			return
		_spawn_id = String(_route.call("segment_spawn_id", StringName(_route_segment_id), &"trailhead"))
		_target_id = String(_route.call("segment_target_landmark_id", StringName(_route_segment_id), &"old_cedar"))
		if not _args.has("max-ticks"):
			_max_ticks = int(_route.call("segment_max_ticks_for", StringName(_route_segment_id), _max_ticks))
	else:
		_spawn_id = String(_args.get("spawn", "trailhead" if _route != null else "flat_spawn"))
		_target_id = String(_args.get("target", "old_cedar" if _route != null else "flat_target"))
	_stuck_window_ticks = maxi(int(_args.get("stuck-window", GameConfig.stuck_window_ticks)), 1)
	_stuck_min_progress = maxf(float(_args.get("stuck-min-progress", GameConfig.stuck_min_progress)), 0.0)
	if _route != null and not bool(_route.call("has_spawn", StringName(_spawn_id))):
		_finish_runner_error("Unsupported spawn for route " + String(_route.get("scene_id")) + ": " + _spawn_id)
		return
	if _route != null and not bool(_route.call("has_landmark", StringName(_target_id))):
		_finish_runner_error("Unsupported target for route " + String(_route.get("scene_id")) + ": " + _target_id)
		return
	_target = _parse_target(_target_id)
	_target_radius = _target_radius_for_id(_target_id)
	if _route != null and _route_segment_id != "":
		if not _args.has("target-radius"):
			_target_radius = float(_route.call("segment_target_radius_for", StringName(_route_segment_id), _target_radius))
		var segment_points_value: Variant = _route.call("segment_waypoint_path", StringName(_route_segment_id))
		if segment_points_value is Array:
			for point in segment_points_value:
				if point is Vector3:
					_waypoints.append(point)
	_rng.seed = int(_args.get("seed", 0))
	_connect_event_bus()
	_configure_flat_bounds()
	if not _setup_surface_map():
		return
	_setup_landmarks()
	_setup_flat_scene()
	call_deferred("_begin_run")


func _begin_run() -> void:
	_vehicle = VehicleScene.instantiate()
	add_child(_vehicle)
	_vehicle.call("reset_to", _spawn_transform(_spawn_id))
	var initial_state: RefCounted = _vehicle.call("get_state")
	_started_flipped = bool(initial_state.get("is_flipped"))
	var initial_basis: Basis = initial_state.get("basis")
	_initial_position = initial_state.get("position")
	_initial_forward = _horizontal_forward(initial_basis)
	_initial_control_right = -_horizontal_right(initial_basis)
	_initial_heading_deg = _heading_deg(initial_basis)
	_controller = _make_controller(_controller_id)
	if _controller == null:
		if _controller_config_error != "":
			_finish_runner_error(_controller_config_error)
		else:
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


func _parse_args(raw: PackedStringArray) -> Dictionary[String, Variant]:
	var out: Dictionary[String, Variant] = {}
	for arg in raw:
		var s: String = String(arg)
		if s.begins_with("--") and s.contains("="):
			var kv: PackedStringArray = s.substr(2).split("=", true, 1)
			if kv.size() == 2:
				out[kv[0]] = kv[1]
	return out


func _join_packed_strings(values: PackedStringArray, separator: String) -> String:
	var out: String = ""
	for i in range(values.size()):
		if i > 0:
			out += separator
		out += values[i]
	return out


func _load_route(scene_id: String) -> Resource:
	if scene_id == TerrainBuilderScript.CEDAR_SCENE_ID:
		return load(CEDAR_ROUTE_PATH) as Resource
	return null


func _make_controller(controller_id: String) -> RefCounted:
	if controller_id == "pd":
		var pd_controller: RefCounted = PDWaypointControllerScript.new()
		if _waypoints.is_empty():
			pd_controller.call("configure", _target, _target_radius)
		else:
			var points: Array[Vector3] = []
			for waypoint in _waypoints:
				points.append(waypoint)
			points.append(_target)
			var use_rough_throttle: bool = false
			if _route != null and _route_segment_id != "":
				use_rough_throttle = bool(_route.call("segment_uses_rough_throttle", StringName(_route_segment_id), false))
			pd_controller.call("configure_path_with_waypoint_radius", points, GameConfig.pd_waypoint_intermediate_radius, _target_radius, use_rough_throttle)
		return pd_controller
	if controller_id == "replay":
		var replay_controller: RefCounted = ReplayControllerScript.new()
		var replay_path: String = String(_args.get("replay", ""))
		if replay_path == "":
			_controller_config_error = "Replay controller requires --replay=<path>"
			return null
		if not bool(replay_controller.call("configure_from_file", replay_path)):
			_controller_config_error = String(replay_controller.call("last_error"))
			return null
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
	var fallback: float = GameConfig.default_target_radius
	if _route != null:
		fallback = float(_route.call("landmark_radius", StringName(target_id), fallback))
	return float(_args.get("target-radius", fallback))


func _spawn_transform(spawn_id: String) -> Transform3D:
	if _route != null:
		return _route.call("spawn_transform", StringName(spawn_id))
	if _scene_id == TerrainBuilderScript.CEDAR_HOLLOW_10M_SCENE_ID:
		return TerrainBuilderScript.cedar_hollow_10m_spawn_transform()
	if _scene_id == "heightmap_ramp_probe":
		return _heightmap_ramp_spawn_transform()
	if spawn_id == "flat_flipped":
		var flipped_basis: Basis = Basis(Vector3.FORWARD, PI)
		return Transform3D(flipped_basis, Vector3(0.0, GameConfig.flat_spawn_height, 0.0))
	if spawn_id == "flat_flipped_yawed":
		var yaw_basis: Basis = Basis(Vector3.UP, deg_to_rad(45.0))
		var flipped_basis: Basis = Basis(Vector3.FORWARD, PI)
		return Transform3D(yaw_basis * flipped_basis, Vector3(0.0, GameConfig.flat_spawn_height, 0.0))
	if spawn_id == "offtrail_tall_grass" or spawn_id == "offtrail_loose_rock":
		return Transform3D(Basis.IDENTITY, Vector3(0.0, GameConfig.flat_spawn_height, 0.0))
	if spawn_id == "hill_hold_grade" or spawn_id == "hill_hold_steep":
		var grade_deg: float = GameConfig.hill_hold_grade_deg
		if spawn_id == "hill_hold_steep":
			grade_deg = GameConfig.hill_hold_steep_grade_deg
		return Transform3D(Basis(Vector3.RIGHT, deg_to_rad(grade_deg)), Vector3(0.0, _hill_hold_spawn_height(grade_deg), 0.0))
	if spawn_id == "suspension_drop":
		return Transform3D(Basis.IDENTITY, Vector3(0.0, GameConfig.suspension_drop_spawn_height, 0.0))
	if spawn_id == "roll_stability_side_slope":
		return Transform3D(Basis.IDENTITY, Vector3(0.0, _tilted_ground_spawn_height(GameConfig.roll_stability_side_slope_deg, GameConfig.roll_stability_ground_size.y), 1.0))
	return Transform3D(Basis.IDENTITY, Vector3(0.0, GameConfig.flat_spawn_height, 0.0))


func _hill_hold_spawn_height(grade_deg: float) -> float:
	return _tilted_ground_spawn_height(grade_deg, GameConfig.hill_hold_ground_size.y)


func _heightmap_ramp_spawn_transform() -> Transform3D:
	var spawn_z: float = GameConfig.heightmap_ramp_probe_spawn_z
	var height: float = _heightmap_ramp_height_at_z(spawn_z)
	return Transform3D(Basis.IDENTITY, Vector3(0.0, height + _vehicle_spawn_clearance(_heightmap_ramp_grade_deg()), spawn_z))


func _heightmap_ramp_grade_deg() -> float:
	return rad_to_deg(atan(GameConfig.heightmap_ramp_probe_grade_percent * 0.01))


func _heightmap_ramp_height_at_z(z: float) -> float:
	return z * GameConfig.heightmap_ramp_probe_grade_percent * 0.01


func _tilted_ground_spawn_height(tilt_deg: float, ground_height: float) -> float:
	var tilt_cos: float = maxf(cos(deg_to_rad(tilt_deg)), 0.2)
	return (ground_height * 0.5 + _vehicle_spawn_ray_distance()) / tilt_cos


func _vehicle_spawn_clearance(tilt_deg: float) -> float:
	var tilt_cos: float = maxf(cos(deg_to_rad(tilt_deg)), 0.2)
	return _vehicle_spawn_ray_distance() / tilt_cos


func _vehicle_spawn_ray_distance() -> float:
	var ray_length: float = GameConfig.susp_rest_length + GameConfig.susp_travel + GameConfig.wheel_radius
	var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	var static_compression: float = clampf((GameConfig.chassis_mass * gravity * 0.25) / maxf(GameConfig.susp_stiffness, 0.001), 0.0, 1.0)
	return ray_length - static_compression * GameConfig.susp_travel


func _setup_flat_scene() -> void:
	if _scene_id == TerrainBuilderScript.CEDAR_SCENE_ID:
		var cedar_scene: Node = CedarHollowSceneResource.instantiate()
		cedar_scene.name = "CedarHollow"
		add_child(cedar_scene)
		return
	if _scene_id == TerrainBuilderScript.CEDAR_HOLLOW_10M_SCENE_ID:
		var cedar_10m_scene: Node = CedarHollow10mSceneResource.instantiate()
		cedar_10m_scene.name = "CedarHollow10m"
		cedar_10m_scene.set("host_preview_vehicle", false)
		add_child(cedar_10m_scene)
		return
	if _scene_id == "offtrail_escape":
		_setup_offtrail_escape_scene()
		return
	if _scene_id == "recovery_trap":
		_setup_recovery_trap_scene()
		return
	if _scene_id == "hill_hold_probe":
		_setup_hill_hold_probe_scene()
		return
	if _scene_id == "roll_stability_probe":
		_setup_roll_stability_probe_scene()
		return
	if _scene_id == "heightmap_ramp_probe":
		_setup_heightmap_ramp_probe_scene()
		return
	if _scene_id == "surface_strips":
		FlatWorldBuilderScript.build_surface_strip_collision(self)
		return
	if _scene_id == FlatWorldBuilderScript.TERRAIN_SURFACE_MAP_PROBE_SCENE_ID:
		FlatWorldBuilderScript.build_terrain_surface_map_probe_collision(self)
		return
	FlatWorldBuilderScript.build_collision(self)


func _setup_surface_map() -> bool:
	_surface_map = SurfaceMapScript.new()
	_surface_map.name = "SurfaceMap"
	add_child(_surface_map)
	if _uses_cedar_terrain_surface_map():
		if not bool(_surface_map.call("configure_terrain_def", CEDAR_TERRAIN_DEF_PATH)):
			_finish_runner_error("Failed to configure Cedar terrain surface map")
			return false
	return true


func _uses_cedar_terrain_surface_map() -> bool:
	return _scene_id == TerrainBuilderScript.CEDAR_SCENE_ID or _scene_id == FlatWorldBuilderScript.TERRAIN_SURFACE_MAP_PROBE_SCENE_ID


func _setup_offtrail_escape_scene() -> void:
	var surface_id: StringName = &"tall_grass"
	if _spawn_id == "offtrail_loose_rock":
		surface_id = &"loose_rock"
	_build_sim_surface_box("offtrail_escape_ground", surface_id, GameConfig.flat_ground_center, GameConfig.flat_ground_size)


func _setup_recovery_trap_scene() -> void:
	_build_sim_surface_box("recovery_trap_ground", &"packed_dirt", GameConfig.flat_ground_center, GameConfig.flat_ground_size)
	_build_sim_surface_box("recovery_trap_wall", &"packed_dirt", GameConfig.recovery_trap_wall_center, GameConfig.recovery_trap_wall_size)


func _setup_hill_hold_probe_scene() -> void:
	var grade_deg: float = GameConfig.hill_hold_grade_deg
	if _spawn_id == "hill_hold_steep":
		grade_deg = GameConfig.hill_hold_steep_grade_deg
	_build_sim_surface_slope("hill_hold_ground", &"packed_dirt", grade_deg)


func _setup_roll_stability_probe_scene() -> void:
	_build_sim_surface_side_slope("roll_stability_ground", &"packed_dirt", GameConfig.roll_stability_side_slope_deg)


func _setup_heightmap_ramp_probe_scene() -> void:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "heightmap_ramp_ground__surf_packed_dirt"
	body.add_to_group("surf_packed_dirt")
	add_child(body)

	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.name = "Collision"
	var shape: HeightMapShape3D = HeightMapShape3D.new()
	var samples: int = maxi(GameConfig.heightmap_ramp_probe_grid_samples, 2)
	shape.map_width = samples
	shape.map_depth = samples
	var spacing: float = GameConfig.heightmap_ramp_probe_size_m / float(samples - 1)
	var half_size: float = GameConfig.heightmap_ramp_probe_size_m * 0.5
	var map_data: PackedFloat32Array = PackedFloat32Array()
	map_data.resize(samples * samples)
	for z_index in range(samples):
		var z_pos: float = -half_size + float(z_index) * spacing
		var height: float = _heightmap_ramp_height_at_z(z_pos)
		for x_index in range(samples):
			map_data[z_index * samples + x_index] = height
	shape.map_data = map_data
	collision.shape = shape
	collision.scale = Vector3(spacing, 1.0, spacing)
	body.add_child(collision)


func _build_sim_surface_box(prefix: String, surface_id: StringName, center: Vector3, size: Vector3) -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = prefix + "__surf_" + String(surface_id)
	body.add_to_group("surf_" + String(surface_id))
	add_child(body)

	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.name = "Collision"
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	collision.position = center
	body.add_child(collision)
	return body


func _build_sim_surface_slope(prefix: String, surface_id: StringName, grade_deg: float) -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = prefix + "__surf_" + String(surface_id)
	body.add_to_group("surf_" + String(surface_id))
	body.global_transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(grade_deg)), Vector3.ZERO)
	add_child(body)

	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.name = "Collision"
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = GameConfig.hill_hold_ground_size
	collision.shape = shape
	body.add_child(collision)
	return body


func _build_sim_surface_side_slope(prefix: String, surface_id: StringName, side_slope_deg: float) -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = prefix + "__surf_" + String(surface_id)
	body.add_to_group("surf_" + String(surface_id))
	body.global_transform = Transform3D(Basis(Vector3.FORWARD, deg_to_rad(side_slope_deg)), Vector3(0.0, 0.0, -2.0))
	add_child(body)

	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.name = "Collision"
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = GameConfig.roll_stability_ground_size
	collision.shape = shape
	body.add_child(collision)
	return body


func _setup_landmarks() -> void:
	if _route == null:
		return
	_landmarks = LandmarksScript.new()
	_landmarks.name = "Landmarks"
	add_child(_landmarks)
	_landmarks.call("configure", _route)


func _record(state: RefCounted, input: RefCounted) -> void:
	var state_position: Vector3 = state.get("position")
	if _landmarks != null:
		_landmarks.call("sample_position", state_position)
	var state_velocity: Vector3 = state.get("linear_velocity")
	var state_angular_velocity: Vector3 = state.get("angular_velocity")
	var state_basis: Basis = state.get("basis")
	var motor_rpm: float = float(state.get("motor_rpm"))
	var pitch_deg: float = _pitch_deg(state_basis)
	var roll_deg: float = _roll_deg(state_basis)
	var speed: float = state_velocity.length()
	var speed_delta: float = speed - _previous_speed
	var slip_angle_deg: float = _slip_angle_deg(state_basis, state_velocity)
	var yaw_rate: float = state_angular_velocity.dot(Vector3.UP)
	var right: Vector3 = state_basis.x.normalized()
	var lateral_speed: float = state_velocity.dot(right)
	var abs_lateral_speed: float = absf(lateral_speed)
	var input_throttle: float = float(input.get("throttle"))
	var wheel_contact: Variant = state.get("wheel_contact")
	var wheel_surface: Variant = state.get("wheel_surface")
	var wheel_hit_point: Variant = state.get("wheel_hit_point")
	var contact_normal: Vector3 = state.get("contact_normal")
	if contact_normal.length() <= GameConfig.self_right_forward_epsilon:
		contact_normal = Vector3.UP
	contact_normal = contact_normal.normalized()
	var contact_normal_tilt_deg: float = rad_to_deg(contact_normal.angle_to(Vector3.UP))
	var vehicle_contamination: Dictionary[String, float] = _vehicle_contamination_dictionary(state)
	var surface_id: StringName = _dominant_surface_from_array(wheel_surface)
	var front_contact_count: int = _contact_count(wheel_contact, 0, 2)
	var rear_contact_count: int = _contact_count(wheel_contact, 2, 4)
	var initial_forward_displacement: float = (state_position - _initial_position).dot(_initial_forward)
	var control_right_displacement: float = (state_position - _initial_position).dot(_initial_control_right)
	var descent_from_initial: float = _initial_position.y - state_position.y
	var flat_displacement_from_initial: float = Vector2(state_position.x - _initial_position.x, state_position.z - _initial_position.z).length()
	var row: Dictionary = {
		"tick": _tick,
		"position": _vec3_to_array(state_position),
		"linear_velocity": _vec3_to_array(state_velocity),
		"angular_velocity": _vec3_to_array(state_angular_velocity),
		"yaw_rate": yaw_rate,
		"lateral_speed": lateral_speed,
		"pitch_deg": pitch_deg,
		"roll_deg": roll_deg,
		"speed": speed,
		"speed_delta": speed_delta,
		"motor_rpm": motor_rpm,
		"initial_forward_displacement": initial_forward_displacement,
		"control_right_displacement": control_right_displacement,
		"flat_displacement_from_initial": flat_displacement_from_initial,
		"slip_angle_deg": slip_angle_deg,
		"wheel_contact_count": front_contact_count + rear_contact_count,
		"front_contact_count": front_contact_count,
		"rear_contact_count": rear_contact_count,
		"wheel_contact": _bool_array_to_array(wheel_contact),
		"wheel_surface": _surface_array_to_array(wheel_surface),
		"wheel_hit_point": _vec3_array_to_array(wheel_hit_point),
		"contact_normal": _vec3_to_array(contact_normal),
		"contact_normal_tilt_deg": contact_normal_tilt_deg,
		"surface_id": String(surface_id),
		"vehicle_contamination": vehicle_contamination,
		"on_ground": bool(state.get("on_ground")),
		"is_flipped": bool(state.get("is_flipped")),
		"input": {
			"throttle": input_throttle,
			"steer": float(input.get("steer")),
			"brake": float(input.get("brake")),
			"ebrake": bool(input.get("ebrake")),
			"self_right": bool(input.get("self_right"))
		}
	}
	_telemetry.append(row)
	_record_contamination_metrics(vehicle_contamination)
	if bool(input.get("self_right")):
		_self_right_input_count += 1
	if not _self_right_heading_captured and _self_righted_event_count > 0 and not bool(state.get("is_flipped")):
		_self_right_heading_error_deg = _angle_delta_abs_deg(_heading_deg(state_basis), _initial_heading_deg)
		_self_right_heading_captured = true
	if bool(input.get("ebrake")):
		_ebrake_ticks += 1
	if input_throttle < 0.0:
		_reverse_ticks += 1
	_min_initial_forward_displacement = minf(_min_initial_forward_displacement, initial_forward_displacement)
	_max_initial_forward_displacement = maxf(_max_initial_forward_displacement, initial_forward_displacement)
	_max_descent_from_initial = maxf(_max_descent_from_initial, descent_from_initial)
	_max_reverse_distance = maxf(_max_reverse_distance, -initial_forward_displacement)
	_max_flat_displacement_from_initial = maxf(_max_flat_displacement_from_initial, flat_displacement_from_initial)
	_final_flat_displacement_from_initial = flat_displacement_from_initial
	_min_control_right_displacement = minf(_min_control_right_displacement, control_right_displacement)
	_max_control_right_displacement = maxf(_max_control_right_displacement, control_right_displacement)
	_final_control_right_displacement = control_right_displacement
	if front_contact_count == 0 and rear_contact_count > 0:
		_front_air_rear_contact_ticks += 1
	_max_abs_slip_angle_deg = maxf(_max_abs_slip_angle_deg, absf(slip_angle_deg))
	_max_y_position = maxf(_max_y_position, state_position.y)
	_max_pitch_deg = maxf(_max_pitch_deg, pitch_deg)
	_max_abs_roll_deg = maxf(_max_abs_roll_deg, absf(roll_deg))
	_max_abs_yaw_rate = maxf(_max_abs_yaw_rate, absf(yaw_rate))
	_max_abs_lateral_speed = maxf(_max_abs_lateral_speed, abs_lateral_speed)
	_final_abs_lateral_speed = abs_lateral_speed
	if _uses_heightfield_clearance():
		_record_chassis_heightfield_clearance(state_position, state_basis)
	if _scenario_id == "steering_speed_ramp":
		_record_steering_speed_ramp_bucket(speed, absf(yaw_rate))
	if _scenario_id == "suspension_drop" and _tick >= GameConfig.suspension_drop_settle_start_tick:
		_post_settle_min_y = minf(_post_settle_min_y, state_position.y)
		_post_settle_max_y = maxf(_post_settle_max_y, state_position.y)
		_max_post_settle_vertical_speed = maxf(_max_post_settle_vertical_speed, absf(state_velocity.y))
	if _scenario_id == "resting_ride_height" and _tick >= GameConfig.resting_ride_height_settle_start_tick:
		_resting_ride_height_sample_ticks += 1
		_resting_ride_height_min_y = minf(_resting_ride_height_min_y, state_position.y)
		_resting_ride_height_max_y = maxf(_resting_ride_height_max_y, state_position.y)
		_resting_ride_height_final_y = state_position.y
		_resting_ride_height_max_abs_vertical_speed = maxf(_resting_ride_height_max_abs_vertical_speed, absf(state_velocity.y))
		if front_contact_count + rear_contact_count == 4:
			_resting_ride_height_all_contact_ticks += 1
	if front_contact_count + rear_contact_count > 0:
		_contact_normal_sample_ticks += 1
		_max_contact_normal_tilt_deg = maxf(_max_contact_normal_tilt_deg, contact_normal_tilt_deg)
		_contact_normal_min_y = minf(_contact_normal_min_y, contact_normal.y)
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
	if _scene_id == TerrainBuilderScript.CEDAR_HOLLOW_10M_SCENE_ID:
		_configure_local_probe_bounds()
		return
	if _scene_id == "heightmap_ramp_probe":
		_bounds_min = GameConfig.heightmap_ramp_probe_bounds_min
		_bounds_max = GameConfig.heightmap_ramp_probe_bounds_max
		return
	if _scene_id == "surface_strips":
		_bounds_min = GameConfig.surface_probe_bounds_min
		_bounds_max = GameConfig.surface_probe_bounds_max
		return
	if _uses_scenario_predicate():
		if _scene_id == "hill_hold_probe":
			_bounds_min = GameConfig.hill_hold_probe_bounds_min
			_bounds_max = GameConfig.hill_hold_probe_bounds_max
			return
		if _scene_id == "roll_stability_probe":
			_bounds_min = GameConfig.roll_stability_probe_bounds_min
			_bounds_max = GameConfig.roll_stability_probe_bounds_max
			return
		_bounds_min = GameConfig.flat_probe_bounds_min
		_bounds_max = GameConfig.flat_probe_bounds_max
		return
	var min_x: float = minf(0.0, _target.x) - 1.0
	var max_x: float = maxf(0.0, _target.x) + 1.0
	var min_z: float = minf(0.0, _target.z) - 1.0
	var max_z: float = maxf(0.0, _target.z) + 1.0
	_bounds_min = Vector3(min_x, GameConfig.flat_target_bounds_y_min, min_z)
	_bounds_max = Vector3(max_x, GameConfig.flat_target_bounds_y_max, max_z)


func _configure_local_probe_bounds() -> void:
	var spawn_position: Vector3 = _spawn_transform(_spawn_id).origin
	var margin_xz: float = GameConfig.real_terrain_probe_bounds_margin_xz
	var margin_y: float = GameConfig.real_terrain_probe_bounds_margin_y
	_bounds_min = Vector3(
		minf(spawn_position.x, _target.x) - margin_xz,
		spawn_position.y - margin_y,
		minf(spawn_position.z, _target.z) - margin_xz
	)
	_bounds_max = Vector3(
		maxf(spawn_position.x, _target.x) + margin_xz,
		spawn_position.y + margin_y,
		maxf(spawn_position.z, _target.z) + margin_xz
	)


func _finish(passed: bool) -> void:
	set_physics_process(false)
	var path: String = String(_args.get("out", "tests/out/flat_target.json"))
	var reached_target: bool = false
	if _telemetry.size() > 0:
		var last_row: Dictionary = _telemetry[_telemetry.size() - 1]
		var last_position: Vector3 = _vec3_from_array(last_row.get("position", []), Vector3(INF, INF, INF))
		var target_delta: Vector3 = _target - last_position
		target_delta.y = 0.0
		reached_target = target_delta.length() <= _target_radius
	var target_predicate_passed: bool = reached_target if _requires_target() else true
	var scenario_predicate_passed: bool = _scenario_predicate_passed()
	var surface_event_observed: bool = _surface_event_count > 0
	var target_landmark_event_observed: bool = _target_landmark_event_observed()
	var event_bus_contract_passed: bool = _event_bus_contract_passed()
	var self_right_heading_preserved: bool = _self_right_heading_preserved()
	var never_stuck_predicate_passed: bool = _never_stuck or _recovered_to_trail_event_count > 0 or _scenario_id == "standstill_yaw_rate" or _scenario_id == "hill_hold" or _scenario_id == "lateral_slide" or _scenario_id == "suspension_drop" or _scenario_id == "resting_ride_height"
	var predicates: Dictionary = {
		"reached_target": target_predicate_passed,
		"scenario_passed": scenario_predicate_passed,
		"surface_event_observed": surface_event_observed,
		"target_landmark_event_observed": target_landmark_event_observed,
		"event_bus_contract": event_bus_contract_passed,
		"self_right_heading_preserved": self_right_heading_preserved,
		"never_stuck": never_stuck_predicate_passed,
		"upright_or_recovered": _upright_or_recovered,
		"stayed_in_bounds": _stayed_in_bounds
	}
	var golden_replay: Dictionary = _golden_replay_result(predicates)
	var golden_replay_matched: bool = bool(golden_replay.get("matched", true))
	predicates["golden_replay_matched"] = golden_replay_matched
	var all_predicates_passed: bool = target_predicate_passed and scenario_predicate_passed and surface_event_observed and target_landmark_event_observed and event_bus_contract_passed and self_right_heading_preserved and never_stuck_predicate_passed and _upright_or_recovered and _stayed_in_bounds and golden_replay_matched
	var result: Dictionary = {
		"scene": _scene_id,
		"controller": _controller_id,
		"scenario": _scenario_id,
		"route_segment": _route_segment_id,
		"spawn": _spawn_id,
		"target": _target_id,
		"seed": int(_args.get("seed", 0)),
		"ticks": _tick,
		"result": "pass" if (passed and all_predicates_passed) else "fail",
		"predicates": predicates,
		"metrics": {
			"target": _vec3_to_array(_target),
			"target_radius": _target_radius,
			"waypoint_count": _waypoints.size(),
			"bounds_min": _vec3_to_array(_bounds_min),
			"bounds_max": _vec3_to_array(_bounds_max),
			"max_flipped_ticks": _max_flipped_ticks_seen,
			"started_flipped": _started_flipped,
			"self_right_input_count": _self_right_input_count,
			"initial_heading_deg": _initial_heading_deg,
			"self_right_heading_error_deg": _self_right_heading_error_deg if _self_right_heading_captured else null,
			"max_abs_slip_angle_deg": _max_abs_slip_angle_deg,
			"max_y_position": _max_y_position,
			"max_pitch_deg": _max_pitch_deg,
			"max_abs_roll_deg": _max_abs_roll_deg,
			"max_abs_yaw_rate": _max_abs_yaw_rate,
			"contact_normal_sample_ticks": _contact_normal_sample_ticks,
			"max_contact_normal_tilt_deg": _max_contact_normal_tilt_deg,
			"contact_normal_min_y": _contact_normal_min_y,
			"max_abs_lateral_speed": _max_abs_lateral_speed,
			"final_abs_lateral_speed": _final_abs_lateral_speed,
			"chassis_clearance_sample_ticks": _chassis_clearance_sample_ticks,
			"min_chassis_clearance_m": _min_chassis_clearance_m if _min_chassis_clearance_m < 999998.0 else null,
			"max_chassis_penetration_m": _max_chassis_penetration_m,
			"steering_speed_low_sample_ticks": _steering_speed_low_sample_ticks,
			"steering_speed_mid_sample_ticks": _steering_speed_mid_sample_ticks,
			"steering_speed_high_sample_ticks": _steering_speed_high_sample_ticks,
			"steering_speed_low_max_abs_yaw_rate": _steering_speed_low_max_abs_yaw_rate,
			"steering_speed_mid_max_abs_yaw_rate": _steering_speed_mid_max_abs_yaw_rate,
			"steering_speed_high_max_abs_yaw_rate": _steering_speed_high_max_abs_yaw_rate,
			"post_settle_y_amplitude": _post_settle_y_amplitude(),
			"max_post_settle_vertical_speed": _max_post_settle_vertical_speed,
			"resting_ride_height_sample_ticks": _resting_ride_height_sample_ticks,
			"resting_ride_height_all_contact_ticks": _resting_ride_height_all_contact_ticks,
			"resting_ride_height_min_y": _resting_ride_height_min_y if _resting_ride_height_min_y < 999998.0 else null,
			"resting_ride_height_max_y": _resting_ride_height_max_y if _resting_ride_height_max_y > -999998.0 else null,
			"resting_ride_height_final_y": _resting_ride_height_final_y,
			"resting_ride_height_max_abs_vertical_speed": _resting_ride_height_max_abs_vertical_speed,
			"max_speed": _max_speed,
			"ebrake_ticks": _ebrake_ticks,
			"reverse_ticks": _reverse_ticks,
			"min_initial_forward_displacement": _min_initial_forward_displacement if _min_initial_forward_displacement < 999998.0 else null,
			"max_initial_forward_displacement": _max_initial_forward_displacement,
			"max_descent_from_initial": _max_descent_from_initial,
			"max_reverse_distance": _max_reverse_distance,
			"max_flat_displacement_from_initial": _max_flat_displacement_from_initial,
			"final_flat_displacement_from_initial": _final_flat_displacement_from_initial,
			"min_control_right_displacement": _min_control_right_displacement if _min_control_right_displacement < 999998.0 else null,
			"max_control_right_displacement": _max_control_right_displacement if _max_control_right_displacement > -999998.0 else null,
			"final_control_right_displacement": _final_control_right_displacement,
			"front_air_rear_contact_ticks": _front_air_rear_contact_ticks,
			"surface_event_count": _surface_event_count,
			"last_surface_event": String(_last_surface_event),
			"surface_event_sequence": _surface_event_sequence,
			"landmark_event_count": _landmark_event_count,
			"last_landmark_event": String(_last_landmark_event),
			"landmark_event_sequence": _landmark_event_sequence,
			"surface_contact_ticks": _surface_contact_ticks,
			"surface_source_counts": _surface_source_counts(),
			"vehicle_contamination": _final_vehicle_contamination,
			"max_vehicle_contamination": _max_vehicle_contamination_dictionary(),
			"avg_speed_by_surface": _surface_average_dictionary(_surface_speed_sum),
			"avg_speed_delta_by_surface": _surface_average_dictionary(_surface_speed_delta_sum),
			"max_abs_slip_angle_by_surface": _surface_max_abs_slip,
			"avg_abs_slip_angle_by_surface": _surface_average_dictionary(_surface_abs_slip_sum),
			"flipped_event_count": _flipped_event_count,
			"self_righted_event_count": _self_righted_event_count,
			"recovered_to_trail_event_count": _recovered_to_trail_event_count,
			"max_recovery_displacement": _max_recovery_displacement,
			"min_progress_window": _min_progress_window if _min_progress_window < 999998.0 else null,
			"stuck_window_ticks": _stuck_window_ticks,
			"stuck_min_progress": _stuck_min_progress,
			"golden_replay": golden_replay
		},
		"telemetry": _telemetry
	}
	_write_json(path, result)
	get_tree().quit(0 if result["result"] == "pass" else 1)


func _finish_runner_error(message: String) -> void:
	set_physics_process(false)
	var path: String = String(_args.get("out", "tests/out/flat_target.json"))
	var result: Dictionary = {
		"scene": _scene_id,
		"controller": _controller_id,
		"scenario": _scenario_id,
		"route_segment": _route_segment_id,
		"spawn": _spawn_id,
		"target": _target_id,
		"seed": int(_args.get("seed", 0)),
		"ticks": _tick,
		"result": "error",
		"error": message,
		"predicates": {
			"reached_target": false,
			"scenario_passed": false,
			"surface_event_observed": false,
			"target_landmark_event_observed": false,
			"event_bus_contract": false,
			"self_right_heading_preserved": false,
			"never_stuck": false,
			"upright_or_recovered": false,
			"stayed_in_bounds": false
		},
		"metrics": {},
		"telemetry": _telemetry
	}
	_write_json(path, result)
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
	if _scenario_id == "reverse_drive":
		return _reverse_ticks >= GameConfig.reverse_min_ticks and _max_reverse_distance >= GameConfig.reverse_min_distance
	if _scenario_id == "reverse_steer_right":
		return _reverse_ticks >= GameConfig.reverse_min_ticks \
			and _max_reverse_distance >= GameConfig.reverse_steer_min_reverse_distance \
			and _final_control_right_displacement >= GameConfig.reverse_steer_min_control_right_displacement \
			and _max_flipped_ticks_seen == 0
	if _scenario_id == "standstill_yaw_rate":
		var yaw_rate_limit: float = GameConfig.steer_inplace_yaw_rate_max * GameConfig.standstill_yaw_probe_max_multiplier
		return _max_abs_yaw_rate <= yaw_rate_limit and _max_abs_yaw_rate >= GameConfig.standstill_yaw_probe_min_rate
	if _scenario_id == "offtrail_escape":
		return _max_initial_forward_displacement >= GameConfig.offtrail_escape_min_distance
	if _scenario_id == "recover_to_trail":
		return _recovered_to_trail_event_count > 0 and _max_recovery_displacement >= GameConfig.recover_event_min_displacement and _max_flipped_ticks_seen == 0
	if _scenario_id == "hill_hold":
		if _spawn_id == "hill_hold_steep":
			return _final_flat_displacement_from_initial >= GameConfig.hill_hold_steep_min_creep and _final_flat_displacement_from_initial <= GameConfig.hill_hold_steep_max_creep and _max_flipped_ticks_seen == 0
		return _max_flat_displacement_from_initial <= GameConfig.hill_hold_max_drift and _max_flipped_ticks_seen == 0
	if _scenario_id == "lateral_slide":
		return _max_abs_lateral_speed >= GameConfig.lateral_slide_min_peak_lateral_speed and _final_abs_lateral_speed <= GameConfig.lateral_slide_max_final_lateral_speed and _max_flipped_ticks_seen == 0
	if _scenario_id == "suspension_drop":
		return _max_speed >= GameConfig.suspension_drop_min_peak_speed \
			and _contact_normal_sample_ticks >= GameConfig.suspension_drop_min_contact_ticks \
			and _post_settle_y_amplitude() <= GameConfig.suspension_drop_max_settle_y_amplitude \
			and _max_post_settle_vertical_speed <= GameConfig.suspension_drop_max_settle_vertical_speed \
			and _max_flipped_ticks_seen == 0
	if _scenario_id == "resting_ride_height":
		return _resting_ride_height_predicate_passed()
	if _scenario_id == "roll_stability":
		return _max_initial_forward_displacement >= GameConfig.roll_stability_min_forward_distance and _contact_normal_sample_ticks >= GameConfig.roll_stability_min_contact_ticks and _max_contact_normal_tilt_deg >= GameConfig.roll_stability_min_contact_normal_tilt_deg and _max_abs_roll_deg <= GameConfig.roll_stability_max_abs_roll_deg and _max_flipped_ticks_seen == 0
	if _scenario_id == "real_terrain_flat_segment":
		return _real_terrain_flat_segment_predicate_passed()
	if _scenario_id == "steering_speed_ramp":
		return _steering_speed_ramp_predicate_passed()
	if _scenario_id == "clip_descent":
		return _clip_descent_predicate_passed()
	if _scenario_id == "surface_sweep":
		return _surface_sweep_predicate_passed()
	if _scenario_id == "log_ramp":
		return _log_ramp_predicate_passed()
	return false


func _clip_descent_predicate_passed() -> bool:
	return _chassis_clearance_sample_ticks >= GameConfig.clip_descent_min_clearance_samples and _max_chassis_penetration_m <= GameConfig.clip_descent_max_chassis_penetration and _max_speed >= GameConfig.clip_descent_min_speed and _max_descent_from_initial >= GameConfig.clip_descent_min_descent and _max_flipped_ticks_seen == 0


func _steering_speed_ramp_predicate_passed() -> bool:
	var min_ticks: int = GameConfig.steering_speed_probe_min_bucket_ticks
	if _steering_speed_low_sample_ticks < min_ticks or _steering_speed_mid_sample_ticks < min_ticks or _steering_speed_high_sample_ticks < min_ticks:
		return false
	var slack: float = GameConfig.steering_speed_probe_monotone_slack
	if _steering_speed_low_max_abs_yaw_rate > _steering_speed_mid_max_abs_yaw_rate + slack:
		return false
	if _steering_speed_mid_max_abs_yaw_rate > _steering_speed_high_max_abs_yaw_rate + slack:
		return false
	if _steering_speed_high_max_abs_yaw_rate < _steering_speed_low_max_abs_yaw_rate + GameConfig.steering_speed_probe_min_high_yaw_gain:
		return false
	return _max_flipped_ticks_seen == 0


func _real_terrain_flat_segment_predicate_passed() -> bool:
	return _max_initial_forward_displacement >= GameConfig.real_terrain_flat_segment_distance_m \
		and _contact_normal_sample_ticks >= GameConfig.real_terrain_flat_segment_min_contact_ticks \
		and _max_flipped_ticks_seen == 0


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


func _log_ramp_predicate_passed() -> bool:
	var wood_ticks: int = int(_surface_contact_ticks.get("wood_plank", 0))
	return wood_ticks >= GameConfig.log_ramp_min_wood_ticks and _max_y_position >= GameConfig.log_ramp_min_peak_y and _max_pitch_deg >= GameConfig.log_ramp_min_peak_pitch_deg


func _post_settle_y_amplitude() -> float:
	if _post_settle_min_y > 999998.0 or _post_settle_max_y < -999998.0:
		return 999999.0
	return _post_settle_max_y - _post_settle_min_y


func _resting_ride_height_predicate_passed() -> bool:
	return _resting_ride_height_sample_ticks >= GameConfig.resting_ride_height_min_sample_ticks \
		and _resting_ride_height_all_contact_ticks == _resting_ride_height_sample_ticks \
		and _resting_ride_height_min_y >= GameConfig.resting_ride_height_min_y \
		and _resting_ride_height_max_y <= GameConfig.resting_ride_height_max_y \
		and _max_flipped_ticks_seen == 0


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


func _horizontal_forward(basis: Basis) -> Vector3:
	var forward: Vector3 = -basis.z
	forward.y = 0.0
	if forward.length() <= GameConfig.reverse_probe_forward_epsilon:
		return Vector3.FORWARD
	return forward.normalized()


func _horizontal_right(basis: Basis) -> Vector3:
	var right: Vector3 = basis.x
	right.y = 0.0
	if right.length() <= GameConfig.reverse_probe_forward_epsilon:
		return Vector3.RIGHT
	return right.normalized()


func _heading_deg(basis: Basis) -> float:
	var forward: Vector3 = _horizontal_forward(basis)
	return rad_to_deg(atan2(forward.x, -forward.z))


func _angle_delta_abs_deg(a: float, b: float) -> float:
	var delta: float = a - b
	while delta > 180.0:
		delta -= 360.0
	while delta < -180.0:
		delta += 360.0
	return absf(delta)


func _contact_count(wheel_contact: Variant, start_index: int, end_index: int) -> int:
	if not (wheel_contact is Array):
		return 0
	var count: int = 0
	for i in range(start_index, end_index):
		if i < wheel_contact.size() and bool(wheel_contact[i]):
			count += 1
	return count


func _bool_array_to_array(values: Variant) -> Array[bool]:
	var out: Array[bool] = []
	if not (values is Array):
		return out
	for value in values:
		out.append(bool(value))
	return out


func _surface_array_to_array(values: Variant) -> Array[String]:
	var out: Array[String] = []
	if not (values is Array):
		return out
	for value in values:
		out.append(String(value))
	return out


func _vec3_array_to_array(values: Variant) -> Array[Variant]:
	var out: Array[Variant] = []
	if not (values is Array):
		return out
	for value in values:
		if value is Vector3:
			out.append(_vec3_to_array(value))
		else:
			out.append(_vec3_to_array(Vector3.ZERO))
	return out


func _vehicle_contamination_dictionary(state: RefCounted) -> Dictionary[String, float]:
	var out: Dictionary[String, float] = {}
	var contamination: RefCounted = state.get("contamination") as RefCounted
	if contamination == null:
		out["mud"] = 0.0
		out["dust"] = 0.0
		out["wetness"] = 0.0
		return out
	out["mud"] = float(contamination.get("mud"))
	out["dust"] = float(contamination.get("dust"))
	out["wetness"] = float(contamination.get("wetness"))
	return out


func _record_contamination_metrics(contamination: Dictionary[String, float]) -> void:
	var mud: float = float(contamination.get("mud", 0.0))
	var dust: float = float(contamination.get("dust", 0.0))
	var wetness: float = float(contamination.get("wetness", 0.0))
	_max_contamination_mud = maxf(_max_contamination_mud, mud)
	_max_contamination_dust = maxf(_max_contamination_dust, dust)
	_max_contamination_wetness = maxf(_max_contamination_wetness, wetness)
	_final_vehicle_contamination.clear()
	_final_vehicle_contamination["mud"] = mud
	_final_vehicle_contamination["dust"] = dust
	_final_vehicle_contamination["wetness"] = wetness


func _record_chassis_heightfield_clearance(position: Vector3, basis: Basis) -> void:
	var half_size: Vector3 = GameConfig.chassis_collision_size * 0.5
	var local_points: Array[Vector3] = [
		Vector3(-half_size.x, -half_size.y, -half_size.z),
		Vector3(half_size.x, -half_size.y, -half_size.z),
		Vector3(-half_size.x, -half_size.y, half_size.z),
		Vector3(half_size.x, -half_size.y, half_size.z),
		Vector3(0.0, -half_size.y, 0.0)
	]
	var sampled_this_tick: bool = false
	for local_point in local_points:
		var world_point: Vector3 = position + basis * local_point
		if not _heightfield_contains(world_point.x, world_point.z):
			continue
		var terrain_height: float = _heightfield_height(world_point.x, world_point.z)
		var clearance: float = world_point.y - terrain_height
		_min_chassis_clearance_m = minf(_min_chassis_clearance_m, clearance)
		_max_chassis_penetration_m = maxf(_max_chassis_penetration_m, maxf(0.0, -clearance))
		sampled_this_tick = true
	if sampled_this_tick:
		_chassis_clearance_sample_ticks += 1


func _uses_heightfield_clearance() -> bool:
	return _scene_id == TerrainBuilderScript.CEDAR_SCENE_ID \
		or _scene_id == TerrainBuilderScript.CEDAR_HOLLOW_10M_SCENE_ID \
		or _scene_id == "heightmap_ramp_probe"


func _heightfield_contains(x: float, z: float) -> bool:
	if _scene_id == "heightmap_ramp_probe":
		var half_size: float = GameConfig.heightmap_ramp_probe_size_m * 0.5
		return x >= -half_size and x <= half_size and z >= -half_size and z <= half_size
	var terrain_def: Resource = _heightfield_terrain_def()
	if terrain_def == null:
		return false
	var terrain_xz: Vector2 = Vector2(x, z) - _heightfield_horizontal_offset()
	return bool(terrain_def.call("contains_world_xz", terrain_xz))


func _heightfield_height(x: float, z: float) -> float:
	if _scene_id == "heightmap_ramp_probe":
		return _heightmap_ramp_height_at_z(z)
	var terrain_def: Resource = _heightfield_terrain_def()
	if terrain_def == null:
		return 0.0
	return TerrainBuilderScript.heightmap_height_at_world_xz(terrain_def, Vector2(x, z), _heightfield_horizontal_offset())


func _heightfield_terrain_def() -> Resource:
	if _scene_id == TerrainBuilderScript.CEDAR_SCENE_ID:
		return TerrainBuilderScript.cedar_terrain_def()
	if _scene_id == TerrainBuilderScript.CEDAR_HOLLOW_10M_SCENE_ID:
		return TerrainBuilderScript.cedar_hollow_10m_terrain_def()
	return null


func _heightfield_horizontal_offset() -> Vector2:
	if _scene_id == TerrainBuilderScript.CEDAR_HOLLOW_10M_SCENE_ID:
		return TerrainBuilderScript.cedar_hollow_10m_horizontal_offset()
	return Vector2.ZERO


func _record_steering_speed_ramp_bucket(speed: float, abs_yaw_rate: float) -> void:
	if speed >= GameConfig.steering_speed_probe_low_min_speed and speed <= GameConfig.steering_speed_probe_low_max_speed:
		_steering_speed_low_sample_ticks += 1
		_steering_speed_low_max_abs_yaw_rate = maxf(_steering_speed_low_max_abs_yaw_rate, abs_yaw_rate)
	elif speed >= GameConfig.steering_speed_probe_mid_min_speed and speed <= GameConfig.steering_speed_probe_mid_max_speed:
		_steering_speed_mid_sample_ticks += 1
		_steering_speed_mid_max_abs_yaw_rate = maxf(_steering_speed_mid_max_abs_yaw_rate, abs_yaw_rate)
	elif speed >= GameConfig.steering_speed_probe_high_min_speed:
		_steering_speed_high_sample_ticks += 1
		_steering_speed_high_max_abs_yaw_rate = maxf(_steering_speed_high_max_abs_yaw_rate, abs_yaw_rate)


func _max_vehicle_contamination_dictionary() -> Dictionary[String, float]:
	var out: Dictionary[String, float] = {}
	out["mud"] = _max_contamination_mud
	out["dust"] = _max_contamination_dust
	out["wetness"] = _max_contamination_wetness
	return out


func _dominant_surface_from_array(values: Variant) -> StringName:
	if not (values is Array):
		return &""
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


func _surface_source_counts() -> Dictionary:
	if _surface_map == null:
		return {}
	return _surface_map.call("source_counts")


func _surface_sequence_contains(expected: Array[String]) -> bool:
	var expected_index: int = 0
	for surface_id in _surface_event_sequence:
		if expected_index < expected.size() and surface_id == expected[expected_index]:
			expected_index += 1
	return expected_index == expected.size()


func _golden_replay_result(predicates: Dictionary) -> Dictionary:
	var failures: Array[String] = []
	var result: Dictionary = {
		"matched": true,
		"expected_ticks": null,
		"tick_delta": 0,
		"compared_samples": 0,
		"compared_slip_samples": 0,
		"compared_motor_rpm_samples": 0,
		"compared_surface_ticks": 0,
		"compared_event_counts": 0,
		"max_position_error": 0.0,
		"max_velocity_error": 0.0,
		"max_speed_error": 0.0,
		"max_slip_error": 0.0,
		"max_motor_rpm_error": 0.0,
		"failures": failures
	}
	if _controller_id != "replay" or _controller == null:
		return result
	var expected_ticks: int = int(_controller.call("expected_ticks"))
	var tolerances: Dictionary = _controller.call("expected_tolerances")
	var expected_samples_value: Variant = _controller.call("expected_samples")
	var expected_predicates: Dictionary = _controller.call("expected_predicates")
	var replay_data: Dictionary = _replay_fixture_data(failures)
	var tick_tolerance: int = int(tolerances.get("ticks", GameConfig.golden_tick_tolerance))
	var position_tolerance: float = float(tolerances.get("position_m", GameConfig.golden_position_tolerance_m))
	var velocity_tolerance: float = float(tolerances.get("velocity_mps", GameConfig.golden_velocity_tolerance_mps))
	var speed_tolerance: float = float(tolerances.get("speed_mps", GameConfig.golden_speed_tolerance_mps))
	var slip_tolerance: float = float(tolerances.get("slip_deg", tolerances.get("slip_angle_deg", GameConfig.golden_slip_tolerance_deg)))
	var motor_rpm_tolerance: float = float(tolerances.get("motor_rpm", GameConfig.golden_motor_rpm_tolerance))
	var surface_tick_tolerance: int = int(tolerances.get("surface_ticks", tolerances.get("surface_contact_ticks", GameConfig.golden_surface_tick_tolerance)))
	var event_count_tolerance: int = int(tolerances.get("event_counts", GameConfig.golden_event_count_tolerance))
	var tick_delta: int = absi(_tick - expected_ticks)
	result["expected_ticks"] = expected_ticks
	result["tick_delta"] = tick_delta
	result["tolerances"] = {
		"ticks": tick_tolerance,
		"position_m": position_tolerance,
		"velocity_mps": velocity_tolerance,
		"speed_mps": speed_tolerance,
		"slip_deg": slip_tolerance,
		"surface_ticks": surface_tick_tolerance,
		"event_counts": event_count_tolerance,
		"motor_rpm": motor_rpm_tolerance
	}
	if tick_delta > tick_tolerance:
		failures.append("tick delta " + str(tick_delta) + " exceeded tolerance " + str(tick_tolerance))
	for key in expected_predicates.keys():
		if key == "golden_replay_matched":
			continue
		if not predicates.has(key):
			failures.append("missing expected predicate: " + String(key))
			continue
		var expected_predicate: bool = bool(expected_predicates[key])
		var actual_predicate: bool = bool(predicates[key])
		if actual_predicate != expected_predicate:
			failures.append("predicate " + String(key) + " expected " + str(expected_predicate) + " got " + str(actual_predicate))
	if expected_samples_value is Array:
		for value in expected_samples_value:
			if not (value is Dictionary):
				continue
			var sample: Dictionary = value
			var sample_tick: int = int(sample.get("tick", -1))
			var row: Dictionary = _telemetry_row_for_tick(sample_tick)
			if row.is_empty():
				failures.append("missing telemetry row for golden sample tick " + str(sample_tick))
				continue
			var position_error: float = _vec3_array_distance(sample.get("position", []), row.get("position", []))
			var velocity_error: float = _vec3_array_distance(sample.get("linear_velocity", []), row.get("linear_velocity", []))
			var speed_error: float = absf(float(sample.get("speed", 0.0)) - float(row.get("speed", 0.0)))
			result["compared_samples"] = int(result["compared_samples"]) + 1
			result["max_position_error"] = maxf(float(result["max_position_error"]), position_error)
			result["max_velocity_error"] = maxf(float(result["max_velocity_error"]), velocity_error)
			result["max_speed_error"] = maxf(float(result["max_speed_error"]), speed_error)
			if position_error > position_tolerance:
				failures.append("position error at tick " + str(sample_tick) + " was " + str(position_error) + " > " + str(position_tolerance))
			if velocity_error > velocity_tolerance:
				failures.append("velocity error at tick " + str(sample_tick) + " was " + str(velocity_error) + " > " + str(velocity_tolerance))
			if speed_error > speed_tolerance:
				failures.append("speed error at tick " + str(sample_tick) + " was " + str(speed_error) + " > " + str(speed_tolerance))
			if sample.has("slip_angle_deg"):
				var slip_error: float = absf(float(sample.get("slip_angle_deg", 0.0)) - float(row.get("slip_angle_deg", 0.0)))
				result["compared_slip_samples"] = int(result["compared_slip_samples"]) + 1
				result["max_slip_error"] = maxf(float(result["max_slip_error"]), slip_error)
				if slip_error > slip_tolerance:
					failures.append("slip error at tick " + str(sample_tick) + " was " + str(slip_error) + " > " + str(slip_tolerance))
			if sample.has("motor_rpm"):
				var motor_rpm_error: float = absf(float(sample.get("motor_rpm", 0.0)) - float(row.get("motor_rpm", 0.0)))
				result["compared_motor_rpm_samples"] = int(result["compared_motor_rpm_samples"]) + 1
				result["max_motor_rpm_error"] = maxf(float(result["max_motor_rpm_error"]), motor_rpm_error)
				if motor_rpm_error > motor_rpm_tolerance:
					failures.append("motor_rpm error at tick " + str(sample_tick) + " was " + str(motor_rpm_error) + " > " + str(motor_rpm_tolerance))
			if sample.has("is_flipped") and bool(sample.get("is_flipped", false)) != bool(row.get("is_flipped", false)):
				failures.append("is_flipped mismatch at tick " + str(sample_tick) + " expected " + str(bool(sample.get("is_flipped", false))) + " got " + str(bool(row.get("is_flipped", false))))
	if expected_samples_value is Array and expected_samples_value.size() > 0 and int(result["compared_samples"]) <= 0:
		failures.append("no golden samples were compared")
	if replay_data.has("metrics") and replay_data["metrics"] is Dictionary:
		var expected_metrics: Dictionary = replay_data["metrics"]
		_compare_golden_metric_block(expected_metrics, result, failures, surface_tick_tolerance, event_count_tolerance, slip_tolerance)
	result["matched"] = failures.is_empty()
	result["failures"] = failures
	return result


func _replay_fixture_data(failures: Array[String]) -> Dictionary:
	var replay_path: String = String(_args.get("replay", ""))
	if replay_path == "":
		return {}
	var file: FileAccess = FileAccess.open(_resolve_project_path(replay_path), FileAccess.READ)
	if file == null:
		failures.append("failed to open replay metadata: " + replay_path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		failures.append("replay metadata root is not a dictionary: " + replay_path)
		return {}
	return parsed


func _resolve_project_path(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://") or path.begins_with("/"):
		return path
	return "res://" + path


func _compare_golden_metric_block(expected_metrics: Dictionary, result: Dictionary, failures: Array[String], surface_tick_tolerance: int, event_count_tolerance: int, slip_tolerance: float) -> void:
	if expected_metrics.has("surface_contact_ticks") and expected_metrics["surface_contact_ticks"] is Dictionary:
		var expected_surface_ticks: Dictionary = expected_metrics["surface_contact_ticks"]
		_compare_golden_int_dictionary("surface_contact_ticks", expected_surface_ticks, _surface_contact_ticks, surface_tick_tolerance, result, failures)
	var event_count_keys: Array[String] = ["surface_event_count", "landmark_event_count", "flipped_event_count", "self_righted_event_count", "recovered_to_trail_event_count"]
	for key in event_count_keys:
		if expected_metrics.has(key):
			var actual_value: int = 0
			if key == "surface_event_count":
				actual_value = _surface_event_count
			elif key == "landmark_event_count":
				actual_value = _landmark_event_count
			elif key == "flipped_event_count":
				actual_value = _flipped_event_count
			elif key == "self_righted_event_count":
				actual_value = _self_righted_event_count
			elif key == "recovered_to_trail_event_count":
				actual_value = _recovered_to_trail_event_count
			_compare_golden_int_metric(key, int(expected_metrics[key]), actual_value, event_count_tolerance, result, failures)
	if expected_metrics.has("max_abs_slip_angle_deg"):
		_compare_golden_float_metric("max_abs_slip_angle_deg", float(expected_metrics["max_abs_slip_angle_deg"]), _max_abs_slip_angle_deg, slip_tolerance, result, failures)
	if expected_metrics.has("max_abs_slip_angle_by_surface") and expected_metrics["max_abs_slip_angle_by_surface"] is Dictionary:
		var expected_surface_slip: Dictionary = expected_metrics["max_abs_slip_angle_by_surface"]
		_compare_golden_float_dictionary("max_abs_slip_angle_by_surface", expected_surface_slip, _surface_max_abs_slip, slip_tolerance, result, failures)


func _compare_golden_int_metric(metric_name: String, expected_value: int, actual_value: int, tolerance: int, result: Dictionary, failures: Array[String]) -> void:
	var delta: int = absi(actual_value - expected_value)
	result["compared_event_counts"] = int(result["compared_event_counts"]) + 1
	if delta > tolerance:
		failures.append(metric_name + " delta " + str(delta) + " exceeded tolerance " + str(tolerance) + " expected " + str(expected_value) + " got " + str(actual_value))


func _compare_golden_float_metric(metric_name: String, expected_value: float, actual_value: float, tolerance: float, result: Dictionary, failures: Array[String]) -> void:
	var delta: float = absf(actual_value - expected_value)
	result["max_slip_error"] = maxf(float(result["max_slip_error"]), delta)
	if delta > tolerance:
		failures.append(metric_name + " delta " + str(delta) + " exceeded tolerance " + str(tolerance) + " expected " + str(expected_value) + " got " + str(actual_value))


func _compare_golden_int_dictionary(metric_name: String, expected_values: Dictionary, actual_values: Dictionary, tolerance: int, result: Dictionary, failures: Array[String]) -> void:
	for key in _dictionary_key_union(expected_values, actual_values):
		var expected_value: int = int(expected_values.get(key, 0))
		var actual_value: int = int(actual_values.get(key, 0))
		var delta: int = absi(actual_value - expected_value)
		result["compared_surface_ticks"] = int(result["compared_surface_ticks"]) + 1
		if delta > tolerance:
			failures.append(metric_name + "." + key + " delta " + str(delta) + " exceeded tolerance " + str(tolerance) + " expected " + str(expected_value) + " got " + str(actual_value))


func _compare_golden_float_dictionary(metric_name: String, expected_values: Dictionary, actual_values: Dictionary, tolerance: float, result: Dictionary, failures: Array[String]) -> void:
	for key in _dictionary_key_union(expected_values, actual_values):
		var expected_value: float = float(expected_values.get(key, 0.0))
		var actual_value: float = float(actual_values.get(key, 0.0))
		var delta: float = absf(actual_value - expected_value)
		result["max_slip_error"] = maxf(float(result["max_slip_error"]), delta)
		if delta > tolerance:
			failures.append(metric_name + "." + key + " delta " + str(delta) + " exceeded tolerance " + str(tolerance) + " expected " + str(expected_value) + " got " + str(actual_value))


func _dictionary_key_union(a: Dictionary, b: Dictionary) -> Array[String]:
	var keys: Array[String] = []
	for key_value in a.keys():
		var key: String = String(key_value)
		if not keys.has(key):
			keys.append(key)
	for other_key_value in b.keys():
		var other_key: String = String(other_key_value)
		if not keys.has(other_key):
			keys.append(other_key)
	return keys


func _telemetry_row_for_tick(tick: int) -> Dictionary:
	if tick >= 0 and tick < _telemetry.size():
		var row: Dictionary = _telemetry[tick]
		if int(row.get("tick", -1)) == tick:
			return row
	for value in _telemetry:
		var row: Dictionary = value
		if int(row.get("tick", -1)) == tick:
			return row
	return {}


func _vec3_array_distance(expected_value: Variant, actual_value: Variant) -> float:
	if not _is_vec3_array(expected_value) or not _is_vec3_array(actual_value):
		return INF
	var expected_vector: Vector3 = _vec3_from_array(expected_value, Vector3.ZERO)
	var actual_vector: Vector3 = _vec3_from_array(actual_value, Vector3.ZERO)
	return expected_vector.distance_to(actual_vector)


func _is_vec3_array(value: Variant) -> bool:
	if not (value is Array):
		return false
	return value.size() >= 3


func _vec3_from_array(value: Variant, fallback: Vector3) -> Vector3:
	if not _is_vec3_array(value):
		return fallback
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


func _connect_event_bus() -> void:
	if not EventBus.vehicle_changed_surface.is_connected(_on_vehicle_changed_surface):
		EventBus.vehicle_changed_surface.connect(_on_vehicle_changed_surface)
	if not EventBus.world_reached_landmark.is_connected(_on_world_reached_landmark):
		EventBus.world_reached_landmark.connect(_on_world_reached_landmark)
	if not EventBus.vehicle_flipped_over.is_connected(_on_vehicle_flipped_over):
		EventBus.vehicle_flipped_over.connect(_on_vehicle_flipped_over)
	if not EventBus.vehicle_self_righted.is_connected(_on_vehicle_self_righted):
		EventBus.vehicle_self_righted.connect(_on_vehicle_self_righted)
	if not EventBus.vehicle_recovered_to_trail.is_connected(_on_vehicle_recovered_to_trail):
		EventBus.vehicle_recovered_to_trail.connect(_on_vehicle_recovered_to_trail)


func _event_bus_contract_passed() -> bool:
	if _spawn_id == "flat_flipped" or _spawn_id == "flat_flipped_yawed":
		return _flipped_event_count > 0 and _self_righted_event_count > 0
	if _scenario_id == "recover_to_trail":
		return _recovered_to_trail_event_count > 0
	return true


func _self_right_heading_preserved() -> bool:
	if _spawn_id != "flat_flipped_yawed":
		return true
	if not _self_right_heading_captured:
		return false
	return _self_right_heading_error_deg <= GameConfig.self_right_heading_tolerance_deg


func _target_landmark_event_observed() -> bool:
	if _uses_scenario_predicate():
		return true
	if _route == null:
		return true
	return _landmark_event_sequence.has(_target_id)


func _on_vehicle_changed_surface(surface_id: StringName) -> void:
	_surface_event_count += 1
	_last_surface_event = surface_id
	var surface_string: String = String(surface_id)
	if _surface_event_sequence.is_empty() or _surface_event_sequence[_surface_event_sequence.size() - 1] != surface_string:
		_surface_event_sequence.append(surface_string)


func _on_world_reached_landmark(landmark_id: StringName) -> void:
	_landmark_event_count += 1
	_last_landmark_event = landmark_id
	var landmark_string: String = String(landmark_id)
	if _landmark_event_sequence.is_empty() or _landmark_event_sequence[_landmark_event_sequence.size() - 1] != landmark_string:
		_landmark_event_sequence.append(landmark_string)


func _on_vehicle_flipped_over() -> void:
	_flipped_event_count += 1


func _on_vehicle_self_righted() -> void:
	_self_righted_event_count += 1


func _on_vehicle_recovered_to_trail(from_position: Vector3, to_position: Vector3) -> void:
	_recovered_to_trail_event_count += 1
	var from_flat: Vector3 = Vector3(from_position.x, 0.0, from_position.z)
	var to_flat: Vector3 = Vector3(to_position.x, 0.0, to_position.z)
	_max_recovery_displacement = maxf(_max_recovery_displacement, from_flat.distance_to(to_flat))
