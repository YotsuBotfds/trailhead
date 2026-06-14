extends Node

const CedarRoute: Resource = preload("res://data/routes/cedar_hollow.tres")
const CedarSurfaceVisualCatalog: Resource = preload("res://data/surface_visuals/cedar_hollow_surface_visuals.tres")
const SURFACE_DIR_PATH: String = "res://data/surfaces"
const EXPECTED_SURFACE_IDS: Array[StringName] = [
	&"loose_rock",
	&"mud",
	&"packed_dirt",
	&"packed_gravel",
	&"tall_grass",
	&"wet_stone",
	&"wood_plank"
]
const WET_DEFAULT_SURFACE_IDS: Array[StringName] = [
	&"mud",
	&"wet_stone"
]

var _errors: PackedStringArray = PackedStringArray()
var _surface_ids: Array[StringName] = []


func _ready() -> void:
	call_deferred("_inspect")


func _inspect() -> void:
	_inspect_surfaces()
	_inspect_surface_visuals()
	_inspect_cedar_route()
	_finish()


func _inspect_surfaces() -> void:
	var observed_ids: Array[StringName] = []
	_surface_ids.clear()
	var dir: DirAccess = DirAccess.open(SURFACE_DIR_PATH)
	if dir == null:
		_errors.append("failed to open surface directory: " + SURFACE_DIR_PATH)
		return
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var resource_path: String = SURFACE_DIR_PATH.path_join(file_name)
			var surface: Resource = load(resource_path)
			if surface == null:
				_errors.append("failed to load surface resource: " + resource_path)
			else:
				var expected_id: StringName = StringName(file_name.get_basename())
				_inspect_surface(surface, resource_path, expected_id)
				var surface_id: StringName = surface.get("id")
				if surface_id != &"":
					observed_ids.append(surface_id)
					_surface_ids.append(surface_id)
		file_name = dir.get_next()
	dir.list_dir_end()
	_require_unique_ids(observed_ids, "SurfaceDef")
	for expected_surface_id in EXPECTED_SURFACE_IDS:
		if not observed_ids.has(expected_surface_id):
			_errors.append("missing expected SurfaceDef: " + String(expected_surface_id))


func _inspect_surface_visuals() -> void:
	var visual_errors: PackedStringArray = CedarSurfaceVisualCatalog.call("validate", _surface_ids)
	for error in visual_errors:
		_errors.append("CedarSurfaceVisualCatalog: " + error)
	var variant_surface_ids: Array[StringName] = CedarSurfaceVisualCatalog.call("surface_ids_with_visual_variants")
	if variant_surface_ids.is_empty():
		_errors.append("CedarSurfaceVisualCatalog should include at least one visual-only variant sharing a SurfaceDef")
	_inspect_surface_visual_texture_paths()


func _inspect_surface_visual_texture_paths() -> void:
	var visual_defs: Array[Resource] = CedarSurfaceVisualCatalog.get("visual_defs")
	for i in range(visual_defs.size()):
		var visual_def: Resource = visual_defs[i]
		if visual_def == null:
			continue
		var visual_id: StringName = visual_def.get("id")
		var surface_id: StringName = visual_def.get("surface_id")
		var is_default: bool = bool(visual_def.get("default_for_surface"))
		var albedo_texture_path: String = visual_def.get("albedo_texture_path")
		var normal_texture_path: String = visual_def.get("normal_texture_path")
		var detail_albedo_texture_path: String = visual_def.get("detail_albedo_texture_path")
		var detail_normal_texture_path: String = visual_def.get("detail_normal_texture_path")
		var texture_uv_scale: Vector2 = visual_def.get("texture_uv_scale")
		var detail_uv_scale: Vector2 = visual_def.get("detail_uv_scale")
		var wetness: float = float(visual_def.get("wetness"))
		var normal_scale: float = float(visual_def.get("normal_scale"))
		if albedo_texture_path.is_empty():
			_errors.append("SurfaceVisualDef " + String(visual_id) + " should have an albedo texture path")
		if normal_texture_path.is_empty():
			_errors.append("SurfaceVisualDef " + String(visual_id) + " should have a normal texture path")
		if detail_albedo_texture_path.is_empty():
			_errors.append("SurfaceVisualDef " + String(visual_id) + " should have a detail albedo texture path")
		if detail_normal_texture_path.is_empty():
			_errors.append("SurfaceVisualDef " + String(visual_id) + " should have a detail normal texture path")
		if not bool(visual_def.get("triplanar")):
			_errors.append("SurfaceVisualDef " + String(visual_id) + " should enable triplanar terrain mapping")
		if detail_uv_scale.x <= texture_uv_scale.x or detail_uv_scale.y <= texture_uv_scale.y:
			_errors.append("SurfaceVisualDef " + String(visual_id) + " detail_uv_scale should be finer than texture_uv_scale")
		if normal_scale < 1.0:
			_errors.append("SurfaceVisualDef " + String(visual_id) + " normal_scale should keep normal maps visible")
		if is_default and WET_DEFAULT_SURFACE_IDS.has(surface_id) and wetness <= 0.0:
			_errors.append("SurfaceVisualDef " + String(visual_id) + " should use render wetness")
		if is_default and not WET_DEFAULT_SURFACE_IDS.has(surface_id) and wetness > 0.0:
			_errors.append("SurfaceVisualDef " + String(visual_id) + " should stay dry by default")


func _inspect_surface(surface: Resource, resource_path: String, expected_id: StringName) -> void:
	var surface_id: StringName = surface.get("id")
	if surface_id == &"":
		_errors.append(resource_path + " has empty id")
	elif surface_id != expected_id:
		_errors.append(resource_path + " id should match filename " + String(expected_id) + ", got " + String(surface_id))
	var display_name: String = surface.get("display_name")
	if display_name.strip_edges().is_empty():
		_errors.append(resource_path + " display_name should not be empty")
	_require_float_range(float(surface.get("friction")), 0.0, 2.0, resource_path + " friction")
	_require_float_range(float(surface.get("rolling_drag")), 0.0, 2.0, resource_path + " rolling_drag")
	_require_float_range(float(surface.get("slip")), 0.0, 1.0, resource_path + " slip")
	_require_float_range(float(surface.get("bog_threshold")), 0.0, 1.0, resource_path + " bog_threshold")
	_require_float_range(float(surface.get("mud_residue")), 0.0, 1.0, resource_path + " mud_residue")
	_require_float_range(float(surface.get("dust_residue")), 0.0, 1.0, resource_path + " dust_residue")
	_require_float_range(float(surface.get("wetness_residue")), 0.0, 1.0, resource_path + " wetness_residue")


func _inspect_cedar_route() -> void:
	var route_errors: PackedStringArray = CedarRoute.call("validate")
	for error in route_errors:
		_errors.append("cedar_hollow RouteDef: " + error)
	var scene_id: StringName = CedarRoute.get("scene_id")
	if scene_id != &"cedar_hollow":
		_errors.append("cedar_hollow RouteDef scene_id mismatch: " + String(scene_id))
	var bounds_min: Vector3 = CedarRoute.get("bounds_min")
	var bounds_max: Vector3 = CedarRoute.get("bounds_max")
	if bounds_min.x >= bounds_max.x or bounds_min.y >= bounds_max.y or bounds_min.z >= bounds_max.z:
		_errors.append("cedar_hollow RouteDef bounds are inverted")
	var spawn_ids: Array[StringName] = CedarRoute.get("spawn_ids")
	var spawn_positions: Array[Vector3] = CedarRoute.get("spawn_positions")
	var spawn_yaw_degrees: Array[float] = CedarRoute.get("spawn_yaw_degrees")
	var landmark_ids: Array[StringName] = CedarRoute.get("landmark_ids")
	var landmark_display_names: Array[String] = CedarRoute.get("landmark_display_names")
	var landmark_positions: Array[Vector3] = CedarRoute.get("landmark_positions")
	var landmark_radii: Array[float] = CedarRoute.get("landmark_radii")
	var segment_ids: Array[StringName] = CedarRoute.get("segment_ids")
	var segment_spawn_ids: Array[StringName] = CedarRoute.get("segment_spawn_ids")
	var segment_target_landmark_ids: Array[StringName] = CedarRoute.get("segment_target_landmark_ids")
	var segment_waypoint_offsets: Array[int] = CedarRoute.get("segment_waypoint_offsets")
	var segment_waypoint_counts: Array[int] = CedarRoute.get("segment_waypoint_counts")
	var segment_waypoints: Array[Vector3] = CedarRoute.get("segment_waypoints")
	var segment_max_ticks: Array[int] = CedarRoute.get("segment_max_ticks")
	var segment_target_radii: Array[float] = CedarRoute.get("segment_target_radii")
	var segment_rough_throttle: Array[bool] = CedarRoute.get("segment_rough_throttle")
	_require_exact_size(spawn_positions.size(), spawn_ids.size(), "spawn_positions")
	_require_exact_size(spawn_yaw_degrees.size(), spawn_ids.size(), "spawn_yaw_degrees")
	_require_exact_size(landmark_display_names.size(), landmark_ids.size(), "landmark_display_names")
	_require_exact_size(landmark_positions.size(), landmark_ids.size(), "landmark_positions")
	_require_exact_size(landmark_radii.size(), landmark_ids.size(), "landmark_radii")
	_require_exact_size(segment_spawn_ids.size(), segment_ids.size(), "segment_spawn_ids")
	_require_exact_size(segment_target_landmark_ids.size(), segment_ids.size(), "segment_target_landmark_ids")
	_require_exact_size(segment_waypoint_offsets.size(), segment_ids.size(), "segment_waypoint_offsets")
	_require_exact_size(segment_waypoint_counts.size(), segment_ids.size(), "segment_waypoint_counts")
	_require_exact_size(segment_max_ticks.size(), segment_ids.size(), "segment_max_ticks")
	_require_exact_size(segment_target_radii.size(), segment_ids.size(), "segment_target_radii")
	_require_exact_size(segment_rough_throttle.size(), segment_ids.size(), "segment_rough_throttle")
	_require_unique_ids(spawn_ids, "RouteDef spawn")
	_require_unique_ids(landmark_ids, "RouteDef landmark")
	_require_unique_ids(segment_ids, "RouteDef segment")
	for i in range(spawn_ids.size()):
		if i < spawn_positions.size():
			_require_position_inside_bounds(spawn_positions[i], bounds_min, bounds_max, "spawn " + String(spawn_ids[i]))
		if i < spawn_yaw_degrees.size():
			_require_float_range(spawn_yaw_degrees[i], -360.0, 360.0, "spawn " + String(spawn_ids[i]) + " yaw")
	for i in range(landmark_ids.size()):
		if i < landmark_display_names.size() and landmark_display_names[i].strip_edges().is_empty():
			_errors.append("landmark " + String(landmark_ids[i]) + " display name should not be empty")
		if i < landmark_positions.size():
			_require_position_inside_bounds(landmark_positions[i], bounds_min, bounds_max, "landmark " + String(landmark_ids[i]))
		if i < landmark_radii.size() and landmark_radii[i] <= 0.0:
			_errors.append("landmark " + String(landmark_ids[i]) + " radius should be positive")
	var covered_waypoints: int = 0
	for i in range(segment_ids.size()):
		var segment_id: StringName = segment_ids[i]
		if i < segment_spawn_ids.size() and not spawn_ids.has(segment_spawn_ids[i]):
			_errors.append("segment " + String(segment_id) + " spawn id is unknown")
		if i < segment_target_landmark_ids.size() and not landmark_ids.has(segment_target_landmark_ids[i]):
			_errors.append("segment " + String(segment_id) + " target landmark id is unknown")
		if i < segment_max_ticks.size() and segment_max_ticks[i] <= 0:
			_errors.append("segment " + String(segment_id) + " max ticks should be positive")
		if i < segment_target_radii.size() and segment_target_radii[i] <= 0.0:
			_errors.append("segment " + String(segment_id) + " target radius should be positive")
		if i < segment_waypoint_offsets.size() and i < segment_waypoint_counts.size():
			var offset: int = segment_waypoint_offsets[i]
			var count: int = segment_waypoint_counts[i]
			if offset != covered_waypoints:
				_errors.append("segment " + String(segment_id) + " waypoint offset should be contiguous")
			covered_waypoints += maxi(count, 0)
	for waypoint in segment_waypoints:
		_require_position_inside_bounds(waypoint, bounds_min, bounds_max, "segment waypoint")
	if covered_waypoints != segment_waypoints.size():
		_errors.append("segment waypoint ranges should cover every waypoint exactly once")


func _require_float_range(value: float, min_value: float, max_value: float, label: String) -> void:
	if value < min_value or value > max_value:
		_errors.append(label + " expected range " + str(min_value) + ".." + str(max_value) + ", got " + str(value))


func _require_exact_size(actual: int, expected: int, label: String) -> void:
	if actual != expected:
		_errors.append(label + " expected " + str(expected) + " entries, got " + str(actual))


func _require_unique_ids(ids: Array[StringName], label: String) -> void:
	var seen: Array[StringName] = []
	for id in ids:
		if id == &"":
			_errors.append(label + " id should not be empty")
		if seen.has(id):
			_errors.append(label + " id should be unique: " + String(id))
		seen.append(id)


func _require_position_inside_bounds(position: Vector3, bounds_min: Vector3, bounds_max: Vector3, label: String) -> void:
	if position.x < bounds_min.x or position.x > bounds_max.x or position.y < bounds_min.y or position.y > bounds_max.y or position.z < bounds_min.z or position.z > bounds_max.z:
		_errors.append(label + " should be inside route bounds, got " + str(position))


func _finish() -> void:
	if _errors.is_empty():
		print("ok: surface, surface visual, and Cedar route resources are valid")
		get_tree().quit(0)
		return
	for error in _errors:
		push_error(error)
	get_tree().quit(1)
