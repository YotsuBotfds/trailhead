extends Node

const SPIKE_ROUTE_PATH: String = "res://data/routes/spike_1km_route.tres"
const SPIKE_LANDMARKS_PATH: String = "res://data/routes/spike_1km_landmarks.tres"
const SPIKE_TERRAIN_DEF_PATH: String = "res://data/terrain/spike_1km_terrain_def.tres"
const SPIKE_MANIFEST_PATH: String = "res://data/regions/spike_1km/collision_tiles_manifest.json"
const SPIKE_TILE_SIDECAR_PATH: String = "res://data/regions/spike_1km/tiles/%s/tile.json"
const SPIKE_SURFACE_ID_MAP_PATH: String = "res://data/terrain/spike_1km_surface_id.png"
const SPIKE_SURFACE_PALETTE_PATH: String = "res://data/surface_palettes/cedar_hollow_zion_surface_palette.tres"
const SPIKE_REGION_ID: String = "spike_1km"
const EXPECTED_TILE_SIZE_M: float = 100.0
const EXPECTED_GRID_SIZE: Vector2i = Vector2i(10, 10)
const EXPECTED_BOUNDS_MIN_XZ: Vector2 = Vector2(0.0, 0.0)
const EXPECTED_BOUNDS_MAX_XZ: Vector2 = Vector2(1000.0, 1000.0)
const EXPECTED_COLLISION_GRID: Vector2i = Vector2i(101, 101)
const EXPECTED_VISUAL_GRID: Vector2i = Vector2i(101, 101)
const EXPECTED_SURFACE_MAP_SIZE: Vector2i = Vector2i(1000, 1000)
const EXPECTED_TILE_SIZE_XZ: Vector2 = Vector2(100.0, 100.0)
const EXPECTED_SEGMENT_IDS: Array[StringName] = [
	&"west_gate_to_east_gate",
	&"east_gate_to_north_gate"
]
const SpikeRoute: Resource = preload(SPIKE_ROUTE_PATH)
const SpikeLandmarks: Resource = preload(SPIKE_LANDMARKS_PATH)
const SpikeTerrainDef: Resource = preload(SPIKE_TERRAIN_DEF_PATH)

var _errors: PackedStringArray = PackedStringArray()
var _manifest_tiles: Array[Vector2i] = []
var _manifest_surface_ids: Array[int] = []
var _manifest_tile_size_m: float = 0.0
var _manifest_grid_size: Vector2i = Vector2i.ZERO


func _ready() -> void:
	call_deferred("_inspect")


func _inspect() -> void:
	_inspect_manifest()
	_inspect_terrain_def_resource()
	_inspect_route_resource(SpikeRoute, "spike_1km route")
	_inspect_route_resource(SpikeLandmarks, "spike_1km landmarks")
	_inspect_landmark_resource_shape()
	_inspect_landmark_catalog_match()
	_inspect_segment_chain()
	_finish()


func _inspect_manifest() -> void:
	var file: FileAccess = FileAccess.open(SPIKE_MANIFEST_PATH, FileAccess.READ)
	if file == null:
		_errors.append("failed to open spike manifest: " + SPIKE_MANIFEST_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		_errors.append("spike manifest is not a dictionary")
		return
	var manifest: Dictionary = parsed
	if String(manifest.get("region_id", "")) != SPIKE_REGION_ID:
		_errors.append("spike manifest region_id mismatch: " + String(manifest.get("region_id", "")))
	var tile_size_value: Variant = manifest.get("tile_size_m", 0.0)
	if not _is_number(tile_size_value):
		_errors.append("spike manifest tile_size_m is not numeric")
	else:
		_manifest_tile_size_m = float(tile_size_value)
		if absf(_manifest_tile_size_m - EXPECTED_TILE_SIZE_M) > 0.001:
			_errors.append("spike manifest tile_size_m mismatch: " + str(_manifest_tile_size_m))
	_manifest_grid_size = _vector2i_from_pair(manifest.get("grid_size_tiles", []), "grid_size_tiles")
	if _manifest_grid_size != EXPECTED_GRID_SIZE:
		_errors.append("spike manifest grid_size_tiles mismatch: " + str(_manifest_grid_size))
	_manifest_tiles = _tiles_from_manifest(manifest.get("tiles", []))
	if _manifest_tiles.size() != EXPECTED_GRID_SIZE.x * EXPECTED_GRID_SIZE.y:
		_errors.append("spike manifest expected 100 tiles, got " + str(_manifest_tiles.size()))
	_manifest_surface_ids = _surface_ids_from_counts(manifest.get("surface_id_counts", {}))


func _inspect_terrain_def_resource() -> void:
	if SpikeTerrainDef == null:
		_errors.append("spike_1km TerrainDef failed to load: " + SPIKE_TERRAIN_DEF_PATH)
		return
	if StringName(SpikeTerrainDef.get("id")) != &"spike_1km":
		_errors.append("spike_1km TerrainDef id mismatch: " + String(SpikeTerrainDef.get("id")))
	if StringName(SpikeTerrainDef.get("scene_id")) != &"spike_1km":
		_errors.append("spike_1km TerrainDef scene_id mismatch: " + String(SpikeTerrainDef.get("scene_id")))
	if Vector2(SpikeTerrainDef.get("bounds_min_xz")) != EXPECTED_BOUNDS_MIN_XZ:
		_errors.append("spike_1km TerrainDef bounds_min_xz mismatch")
	if Vector2(SpikeTerrainDef.get("bounds_max_xz")) != EXPECTED_BOUNDS_MAX_XZ:
		_errors.append("spike_1km TerrainDef bounds_max_xz mismatch")
	if Vector2i(SpikeTerrainDef.get("tile_grid")) != EXPECTED_GRID_SIZE:
		_errors.append("spike_1km TerrainDef tile_grid mismatch")
	if Vector2i(SpikeTerrainDef.get("tile_grid_origin")) != Vector2i.ZERO:
		_errors.append("spike_1km TerrainDef tile_grid_origin mismatch")
	if Vector2(SpikeTerrainDef.get("tile_size")) != EXPECTED_TILE_SIZE_XZ:
		_errors.append("spike_1km TerrainDef tile_size mismatch")
	if Vector2i(SpikeTerrainDef.get("collision_grid")) != EXPECTED_COLLISION_GRID:
		_errors.append("spike_1km TerrainDef collision_grid mismatch")
	if Vector2i(SpikeTerrainDef.get("visual_grid")) != EXPECTED_VISUAL_GRID:
		_errors.append("spike_1km TerrainDef visual_grid mismatch")
	if Vector2i(SpikeTerrainDef.get("surface_map_size")) != EXPECTED_SURFACE_MAP_SIZE:
		_errors.append("spike_1km TerrainDef surface_map_size mismatch")
	_require_terrain_tiles_match_manifest()
	_require_terrain_surface_paths()
	_require_terrain_collision_paths()
	_require_terrain_validation_passes()


func _require_terrain_tiles_match_manifest() -> void:
	var active_tiles: Array[Vector2i] = SpikeTerrainDef.call("active_tile_indices")
	if active_tiles.size() != EXPECTED_GRID_SIZE.x * EXPECTED_GRID_SIZE.y:
		_errors.append("spike_1km TerrainDef expected 100 active tiles, got " + str(active_tiles.size()))
	for tile in active_tiles:
		if not _manifest_tiles.has(tile):
			_errors.append("spike_1km TerrainDef active tile missing from manifest: " + str(tile))
	for tile in _manifest_tiles:
		if not active_tiles.has(tile):
			_errors.append("spike manifest tile missing from TerrainDef active tiles: " + str(tile))


func _require_terrain_surface_paths() -> void:
	var palette_path: String = SpikeTerrainDef.get("surface_palette_path")
	if palette_path != SPIKE_SURFACE_PALETTE_PATH:
		_errors.append("spike_1km TerrainDef surface_palette_path mismatch: " + palette_path)
	var palette: Resource = load(palette_path) as Resource
	if palette == null:
		_errors.append("spike_1km TerrainDef surface palette failed to load: " + palette_path)
	else:
		for id_value in _manifest_surface_ids:
			if not bool(palette.call("has_surface_id_value", id_value)):
				_errors.append("spike_1km surface palette does not resolve surface ID value: " + str(id_value))
	var surface_id_map_path: String = SpikeTerrainDef.get("surface_id_map_path")
	if surface_id_map_path != SPIKE_SURFACE_ID_MAP_PATH:
		_errors.append("spike_1km TerrainDef surface_id_map_path should point at stitched spike surface map: " + surface_id_map_path)
	elif not FileAccess.file_exists(surface_id_map_path):
		_errors.append("spike_1km TerrainDef surface_id_map_path does not exist: " + surface_id_map_path)


func _require_terrain_collision_paths() -> void:
	var active_tiles: Array[Vector2i] = SpikeTerrainDef.call("active_tile_indices")
	var collision_tile_paths: Array[String] = SpikeTerrainDef.get("collision_tile_paths")
	if collision_tile_paths.size() != active_tiles.size():
		_errors.append("spike_1km TerrainDef collision_tile_paths should match active tile count")
	for i in range(collision_tile_paths.size()):
		var path: String = collision_tile_paths[i]
		if path.is_empty():
			_errors.append("spike_1km TerrainDef collision tile path is empty")
			continue
		if i < active_tiles.size():
			var expected_path: String = _collision_path_for_tile(active_tiles[i])
			if path != expected_path:
				_errors.append("spike_1km TerrainDef collision path order mismatch at " + str(i) + ": " + path + " != " + expected_path)
		if not ResourceLoader.exists(path):
			_errors.append("spike_1km TerrainDef collision tile path does not exist: " + path)
			continue
		var shape: HeightMapShape3D = load(path) as HeightMapShape3D
		if shape == null:
			_errors.append("spike_1km TerrainDef collision tile did not load as HeightMapShape3D: " + path)
			continue
		if shape.map_width != EXPECTED_COLLISION_GRID.x or shape.map_depth != EXPECTED_COLLISION_GRID.y:
			_errors.append("spike_1km TerrainDef collision tile grid mismatch: " + path)


func _require_terrain_validation_passes() -> void:
	var terrain_errors: PackedStringArray = SpikeTerrainDef.call("validate")
	for error in terrain_errors:
		_errors.append("spike_1km TerrainDef validate: " + error)


func _inspect_route_resource(route: Resource, label: String) -> void:
	if route == null:
		_errors.append(label + " failed to load")
		return
	var route_errors: PackedStringArray = route.call("validate")
	for error in route_errors:
		_errors.append(label + " RouteDef: " + error)
	if StringName(route.get("scene_id")) != &"spike_1km":
		_errors.append(label + " scene_id mismatch: " + String(route.get("scene_id")))
	var terrain_def_path: String = route.get("terrain_def_path")
	if terrain_def_path != SPIKE_TERRAIN_DEF_PATH:
		_errors.append(label + " terrain_def_path should point at local spike TerrainDef: " + terrain_def_path)
	elif not ResourceLoader.exists(terrain_def_path):
		_errors.append(label + " terrain_def_path should point at a loadable .tres resource")
	var bounds_min: Vector3 = route.get("bounds_min")
	var bounds_max: Vector3 = route.get("bounds_max")
	if bounds_min != Vector3(0.0, -2.0, 0.0) or bounds_max != Vector3(1000.0, 2.0, 1000.0):
		_errors.append(label + " bounds should cover the committed 10x10 spike region")
	_require_positions_inside_bounds(route.get("spawn_positions"), bounds_min, bounds_max, label + " spawn")
	_require_positions_inside_bounds(route.get("landmark_positions"), bounds_min, bounds_max, label + " landmark")
	_require_positions_inside_bounds(route.get("segment_waypoints"), bounds_min, bounds_max, label + " waypoint")
	_require_unique_ids(route.get("spawn_ids"), label + " spawn")
	_require_unique_ids(route.get("landmark_ids"), label + " landmark")
	_require_unique_ids(route.get("segment_ids"), label + " segment")


func _inspect_landmark_resource_shape() -> void:
	var segment_ids: Array[StringName] = SpikeLandmarks.get("segment_ids")
	var spawn_ids: Array[StringName] = SpikeLandmarks.get("spawn_ids")
	if not segment_ids.is_empty():
		_errors.append("spike_1km landmarks resource should not define route segments")
	if not spawn_ids.is_empty():
		_errors.append("spike_1km landmarks resource should not define spawns")


func _inspect_landmark_catalog_match() -> void:
	_require_same_string_name_array(
		SpikeRoute.get("landmark_ids"),
		SpikeLandmarks.get("landmark_ids"),
		"landmark_ids"
	)
	_require_same_string_array(
		SpikeRoute.get("landmark_display_names"),
		SpikeLandmarks.get("landmark_display_names"),
		"landmark_display_names"
	)
	_require_same_vector3_array(
		SpikeRoute.get("landmark_positions"),
		SpikeLandmarks.get("landmark_positions"),
		"landmark_positions"
	)
	_require_same_float_array(
		SpikeRoute.get("landmark_radii"),
		SpikeLandmarks.get("landmark_radii"),
		"landmark_radii"
	)


func _inspect_segment_chain() -> void:
	var segment_ids: Array[StringName] = SpikeRoute.get("segment_ids")
	if segment_ids.size() < 2:
		_errors.append("spike route should define at least two consecutive segments")
		return
	for expected_segment_id in EXPECTED_SEGMENT_IDS:
		if not segment_ids.has(expected_segment_id):
			_errors.append("spike route missing segment " + String(expected_segment_id))
	var first_target: StringName = SpikeRoute.call("segment_target_landmark_id", &"west_gate_to_east_gate", &"")
	var second_spawn: StringName = SpikeRoute.call("segment_spawn_id", &"east_gate_to_north_gate", &"")
	if first_target != second_spawn:
		_errors.append("spike route segments are not consecutive: first target " + String(first_target) + ", second spawn " + String(second_spawn))
	_require_segment_crosses_cell_pair(&"west_gate_to_east_gate", Vector2i(4, 4), Vector2i(5, 4))
	_require_segment_crosses_cell_pair(&"east_gate_to_north_gate", Vector2i(5, 4), Vector2i(5, 5))


func _require_segment_crosses_cell_pair(segment_id: StringName, from_cell: Vector2i, to_cell: Vector2i) -> void:
	var points: Array[Vector3] = _segment_points(segment_id)
	if points.size() < 2:
		_errors.append("segment " + String(segment_id) + " should have at least two sample points")
		return
	var found_crossing: bool = false
	for point in points:
		var cell: Vector2i = _cell_for_point(point)
		if not _manifest_tiles.has(cell):
			_errors.append("segment " + String(segment_id) + " point " + str(point) + " resolves outside spike manifest cell " + str(cell))
		else:
			_require_tile_sidecar(cell)
	for i in range(points.size() - 1):
		var left_cell: Vector2i = _cell_for_point(points[i])
		var right_cell: Vector2i = _cell_for_point(points[i + 1])
		if left_cell == from_cell and right_cell == to_cell:
			found_crossing = true
	if not found_crossing:
		_errors.append("segment " + String(segment_id) + " did not cross expected seam " + str(from_cell) + " -> " + str(to_cell))


func _segment_points(segment_id: StringName) -> Array[Vector3]:
	var points: Array[Vector3] = []
	var spawn_id: StringName = SpikeRoute.call("segment_spawn_id", segment_id, &"")
	if spawn_id != &"":
		var spawn_transform: Transform3D = SpikeRoute.call("spawn_transform", spawn_id)
		points.append(spawn_transform.origin)
	var waypoints_value: Variant = SpikeRoute.call("segment_waypoint_path", segment_id)
	if waypoints_value is Array:
		var waypoints: Array = waypoints_value
		for waypoint in waypoints:
			if waypoint is Vector3:
				points.append(waypoint)
	var target_id: StringName = SpikeRoute.call("segment_target_landmark_id", segment_id, &"")
	if target_id != &"":
		points.append(SpikeRoute.call("landmark_position", target_id))
	return points


func _cell_for_point(point: Vector3) -> Vector2i:
	if _manifest_tile_size_m <= 0.0:
		return Vector2i(-999999, -999999)
	return Vector2i(
		int(floor(point.x / _manifest_tile_size_m)),
		int(floor(point.z / _manifest_tile_size_m))
	)


func _require_tile_sidecar(cell: Vector2i) -> void:
	var path: String = SPIKE_TILE_SIDECAR_PATH % _tile_key(cell)
	if not FileAccess.file_exists(path):
		_errors.append("missing tile sidecar for route cell " + str(cell) + ": " + path)


func _tiles_from_manifest(value: Variant) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	if not (value is Array):
		_errors.append("spike manifest tiles should be an array")
		return tiles
	var raw_tiles: Array = value
	for i in range(raw_tiles.size()):
		var tile: Vector2i = _vector2i_from_pair(raw_tiles[i], "tiles[" + str(i) + "]")
		if not tiles.has(tile):
			tiles.append(tile)
	return tiles


func _surface_ids_from_counts(value: Variant) -> Array[int]:
	var ids: Array[int] = []
	if not (value is Dictionary):
		_errors.append("spike manifest surface_id_counts should be a dictionary")
		return ids
	var counts_by_tile: Dictionary = value
	for tile_key in counts_by_tile.keys():
		var counts_value: Variant = counts_by_tile[tile_key]
		if not (counts_value is Dictionary):
			_errors.append("spike manifest surface_id_counts tile should be a dictionary: " + String(tile_key))
			continue
		var counts: Dictionary = counts_value
		for id_key in counts.keys():
			var id_value: int = int(String(id_key))
			if not ids.has(id_value):
				ids.append(id_value)
	ids.sort()
	return ids


func _vector2i_from_pair(value: Variant, label: String) -> Vector2i:
	if not (value is Array):
		_errors.append("spike manifest " + label + " should be an array")
		return Vector2i.ZERO
	var values: Array = value
	if values.size() != 2 or not _is_number(values[0]) or not _is_number(values[1]):
		_errors.append("spike manifest " + label + " should be a two-number array")
		return Vector2i.ZERO
	return Vector2i(int(values[0]), int(values[1]))


func _require_positions_inside_bounds(value: Variant, bounds_min: Vector3, bounds_max: Vector3, label: String) -> void:
	if not (value is Array):
		_errors.append(label + " positions should be an array")
		return
	var positions: Array = value
	for i in range(positions.size()):
		if not (positions[i] is Vector3):
			_errors.append(label + " position " + str(i) + " should be Vector3")
			continue
		var position: Vector3 = positions[i]
		if position.x < bounds_min.x or position.x > bounds_max.x or position.y < bounds_min.y or position.y > bounds_max.y or position.z < bounds_min.z or position.z > bounds_max.z:
			_errors.append(label + " position " + str(i) + " outside bounds: " + str(position))


func _require_unique_ids(value: Variant, label: String) -> void:
	if not (value is Array):
		_errors.append(label + " ids should be an array")
		return
	var ids: Array = value
	var seen: Array[StringName] = []
	for id_value in ids:
		var id: StringName = StringName(id_value)
		if id == &"":
			_errors.append(label + " id should not be empty")
		if seen.has(id):
			_errors.append(label + " id should be unique: " + String(id))
		seen.append(id)


func _require_same_string_name_array(left_value: Variant, right_value: Variant, label: String) -> void:
	var left: Array[StringName] = _string_name_array(left_value)
	var right: Array[StringName] = _string_name_array(right_value)
	if left.size() != right.size():
		_errors.append("spike landmark " + label + " size mismatch")
		return
	for i in range(left.size()):
		if left[i] != right[i]:
			_errors.append("spike landmark " + label + " mismatch at " + str(i))


func _require_same_string_array(left_value: Variant, right_value: Variant, label: String) -> void:
	var left: Array[String] = _string_array(left_value)
	var right: Array[String] = _string_array(right_value)
	if left.size() != right.size():
		_errors.append("spike landmark " + label + " size mismatch")
		return
	for i in range(left.size()):
		if left[i] != right[i]:
			_errors.append("spike landmark " + label + " mismatch at " + str(i))


func _require_same_vector3_array(left_value: Variant, right_value: Variant, label: String) -> void:
	var left: Array[Vector3] = _vector3_array(left_value)
	var right: Array[Vector3] = _vector3_array(right_value)
	if left.size() != right.size():
		_errors.append("spike landmark " + label + " size mismatch")
		return
	for i in range(left.size()):
		if left[i] != right[i]:
			_errors.append("spike landmark " + label + " mismatch at " + str(i))


func _require_same_float_array(left_value: Variant, right_value: Variant, label: String) -> void:
	var left: Array[float] = _float_array(left_value)
	var right: Array[float] = _float_array(right_value)
	if left.size() != right.size():
		_errors.append("spike landmark " + label + " size mismatch")
		return
	for i in range(left.size()):
		if absf(left[i] - right[i]) > 0.0001:
			_errors.append("spike landmark " + label + " mismatch at " + str(i))


func _string_name_array(value: Variant) -> Array[StringName]:
	var out: Array[StringName] = []
	if not (value is Array):
		return out
	var values: Array = value
	for item in values:
		out.append(StringName(item))
	return out


func _string_array(value: Variant) -> Array[String]:
	var out: Array[String] = []
	if not (value is Array):
		return out
	var values: Array = value
	for item in values:
		out.append(String(item))
	return out


func _vector3_array(value: Variant) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if not (value is Array):
		return out
	var values: Array = value
	for item in values:
		if item is Vector3:
			out.append(item)
	return out


func _float_array(value: Variant) -> Array[float]:
	var out: Array[float] = []
	if not (value is Array):
		return out
	var values: Array = value
	for item in values:
		if _is_number(item):
			out.append(float(item))
	return out


func _tile_key(cell: Vector2i) -> String:
	return str(cell.x) + "_" + str(cell.y)


func _collision_path_for_tile(cell: Vector2i) -> String:
	return "res://data/collision/spike_1km_tile_CX" + _two_digit(cell.x) + "_CZ" + _two_digit(cell.y) + ".res"


func _two_digit(value: int) -> String:
	if value < 10:
		return "0" + str(value)
	return str(value)


func _is_number(value: Variant) -> bool:
	var value_type: int = typeof(value)
	return value_type == TYPE_INT or value_type == TYPE_FLOAT


func _finish() -> void:
	if _errors.is_empty():
		print("ok: spike_1km RouteDef and landmark resources cross committed tile seams")
		get_tree().quit(0)
		return
	for error in _errors:
		push_error(error)
	get_tree().quit(1)
