class_name TerrainDef
extends Resource

const MIN_EXTENT: float = 0.001
const SIZE_EPSILON: float = 0.001

@export var id: StringName = &""
@export var scene_id: StringName = &""
@export var bounds_min_xz: Vector2 = Vector2.ZERO
@export var bounds_max_xz: Vector2 = Vector2.ZERO
@export var tile_grid: Vector2i = Vector2i(1, 1)
@export var tile_grid_origin: Vector2i = Vector2i.ZERO
@export var tile_size: Vector2 = Vector2.ONE
@export var tile_indices: Array[Vector2i] = []
@export var collision_grid: Vector2i = Vector2i(1, 1)
@export var visual_grid: Vector2i = Vector2i(1, 1)
@export var surface_map_size: Vector2i = Vector2i(1, 1)
@export var surface_palette_path: String = ""
@export var surface_id_map_path: String = ""
@export var collision_tile_paths: Array[String] = []
@export var visual_tile_paths: Array[String] = []
@export var feature_override_surface_ids: Array[StringName] = []
@export var feature_override_centers: Array[Vector2] = []
@export var feature_override_axes_x: Array[Vector2] = []
@export var feature_override_axes_z: Array[Vector2] = []
@export var feature_override_half_extents: Array[Vector2] = []
@export var route_section_ids: Array[StringName] = []


func validate() -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	var active_tiles: Array[Vector2i] = _validate_core_data(errors)
	_validate_sim_data(errors, active_tiles)
	return errors


func validate_render() -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	var active_tiles: Array[Vector2i] = _validate_core_data(errors)
	_validate_render_data(errors, active_tiles)
	return errors


func _validate_core_data(errors: PackedStringArray) -> Array[Vector2i]:
	if id == &"":
		errors.append("id is empty")
	if scene_id == &"":
		errors.append("scene_id is empty")
	var size: Vector2 = extent_size()
	if size.x <= MIN_EXTENT or size.y <= MIN_EXTENT:
		errors.append("bounds must have positive X/Z extent")
	if tile_grid.x <= 0 or tile_grid.y <= 0:
		errors.append("tile_grid must be positive")
	if tile_size.x <= MIN_EXTENT or tile_size.y <= MIN_EXTENT:
		errors.append("tile_size must be positive")
	if tile_grid.x > 0 and tile_grid.y > 0:
		var expected_tile_size: Vector2 = Vector2(size.x / float(tile_grid.x), size.y / float(tile_grid.y))
		if absf(tile_size.x - expected_tile_size.x) > SIZE_EPSILON or absf(tile_size.y - expected_tile_size.y) > SIZE_EPSILON:
			errors.append("tile_size must match extent divided by tile_grid")
	var active_tiles: Array[Vector2i] = active_tile_indices()
	if active_tiles.is_empty():
		errors.append("at least one active tile is required")
	var seen_tiles: Array[Vector2i] = []
	for tile_index in active_tiles:
		if not _tile_index_in_grid(tile_index):
			errors.append("tile index outside tile_grid: " + str(tile_index))
		if seen_tiles.has(tile_index):
			errors.append("duplicate tile index: " + str(tile_index))
		seen_tiles.append(tile_index)
	return active_tiles


func _validate_sim_data(errors: PackedStringArray, active_tiles: Array[Vector2i]) -> void:
	if collision_grid.x <= 1 or collision_grid.y <= 1:
		errors.append("collision_grid must be at least 2x2")
	if surface_map_size.x <= 1 or surface_map_size.y <= 1:
		errors.append("surface_map_size must be at least 2x2")
	if surface_palette_path.is_empty():
		errors.append("surface_palette_path is empty")
	elif not ResourceLoader.exists(surface_palette_path):
		errors.append("surface_palette_path does not exist: " + surface_palette_path)
	if surface_id_map_path.is_empty():
		errors.append("surface_id_map_path is empty")
	elif not _surface_id_map_path_exists(surface_id_map_path):
		errors.append("surface_id_map_path does not exist: " + surface_id_map_path)
	if collision_tile_paths.size() != active_tiles.size():
		errors.append("collision_tile_paths must match active tile count")
	for path in collision_tile_paths:
		if path.is_empty():
			errors.append("collision tile path is empty")
		elif not ResourceLoader.exists(path):
			errors.append("collision tile path does not exist: " + path)
	_validate_feature_overrides(errors)
	if route_section_ids.is_empty():
		errors.append("route_section_ids is empty")
	for route_section_id in route_section_ids:
		if route_section_id == &"":
			errors.append("route_section_ids contains an empty id")


func _validate_render_data(errors: PackedStringArray, active_tiles: Array[Vector2i]) -> void:
	if visual_grid.x <= 1 or visual_grid.y <= 1:
		errors.append("visual_grid must be at least 2x2")
	if visual_tile_paths.size() != active_tiles.size():
		errors.append("visual_tile_paths must match active tile count")
	for path in visual_tile_paths:
		if path.is_empty():
			errors.append("visual tile path is empty")
		elif not FileAccess.file_exists(path):
			errors.append("visual tile path does not exist: " + path)


func _surface_id_map_path_exists(path: String) -> bool:
	return FileAccess.file_exists(path) or ResourceLoader.exists(path)


func extent_size() -> Vector2:
	return bounds_max_xz - bounds_min_xz


func center_xz() -> Vector2:
	return (bounds_min_xz + bounds_max_xz) * 0.5


func contains_world_xz(world_xz: Vector2) -> bool:
	return world_xz.x >= bounds_min_xz.x and world_xz.x <= bounds_max_xz.x and world_xz.y >= bounds_min_xz.y and world_xz.y <= bounds_max_xz.y


func tile_bounds(tile_index: Vector2i) -> Rect2:
	var grid_offset: Vector2i = tile_index - tile_grid_origin
	var tile_min: Vector2 = bounds_min_xz + Vector2(float(grid_offset.x) * tile_size.x, float(grid_offset.y) * tile_size.y)
	return Rect2(tile_min, tile_size)


func tile_index_for_world_xz(world_xz: Vector2) -> Vector2i:
	if tile_grid.x <= 0 or tile_grid.y <= 0 or tile_size.x <= MIN_EXTENT or tile_size.y <= MIN_EXTENT:
		return Vector2i.ZERO
	var local: Vector2 = world_xz - bounds_min_xz
	return Vector2i(
		tile_grid_origin.x + clampi(int(floor(local.x / tile_size.x)), 0, tile_grid.x - 1),
		tile_grid_origin.y + clampi(int(floor(local.y / tile_size.y)), 0, tile_grid.y - 1)
	)


func world_to_surface_uv(world_xz: Vector2) -> Vector2:
	var size: Vector2 = extent_size()
	if size.x <= MIN_EXTENT or size.y <= MIN_EXTENT:
		return Vector2.ZERO
	return Vector2(
		clampf((world_xz.x - bounds_min_xz.x) / size.x, 0.0, 1.0),
		clampf((bounds_max_xz.y - world_xz.y) / size.y, 0.0, 1.0)
	)


func world_to_heightmap_uv(world_xz: Vector2) -> Vector2:
	var size: Vector2 = extent_size()
	if size.x <= MIN_EXTENT or size.y <= MIN_EXTENT:
		return Vector2.ZERO
	return Vector2(
		clampf((world_xz.x - bounds_min_xz.x) / size.x, 0.0, 1.0),
		clampf((world_xz.y - bounds_min_xz.y) / size.y, 0.0, 1.0)
	)


func world_to_tile_heightmap_uv(world_xz: Vector2, tile_index: Vector2i) -> Vector2:
	var bounds: Rect2 = tile_bounds(tile_index)
	if bounds.size.x <= MIN_EXTENT or bounds.size.y <= MIN_EXTENT:
		return Vector2.ZERO
	return Vector2(
		clampf((world_xz.x - bounds.position.x) / bounds.size.x, 0.0, 1.0),
		clampf((world_xz.y - bounds.position.y) / bounds.size.y, 0.0, 1.0)
	)


func active_tile_indices() -> Array[Vector2i]:
	if not tile_indices.is_empty():
		return tile_indices.duplicate()
	var indices: Array[Vector2i] = []
	for tile_z in range(tile_grid_origin.y, tile_grid_origin.y + maxi(tile_grid.y, 0)):
		for tile_x in range(tile_grid_origin.x, tile_grid_origin.x + maxi(tile_grid.x, 0)):
			indices.append(Vector2i(tile_x, tile_z))
	return indices


func tile_array_index(tile_index: Vector2i) -> int:
	var active_tiles: Array[Vector2i] = active_tile_indices()
	for i in range(active_tiles.size()):
		if active_tiles[i] == tile_index:
			return i
	return -1


func collision_tile_path_for_tile(tile_index: Vector2i) -> String:
	var index: int = tile_array_index(tile_index)
	if index < 0 or index >= collision_tile_paths.size():
		return ""
	return collision_tile_paths[index]


func visual_tile_path_for_tile(tile_index: Vector2i) -> String:
	var index: int = tile_array_index(tile_index)
	if index < 0 or index >= visual_tile_paths.size():
		return ""
	return visual_tile_paths[index]


func surface_override_rects() -> Array[Variant]:
	var overrides: Array[Variant] = []
	var count: int = mini(mini(mini(mini(
		feature_override_surface_ids.size(),
		feature_override_centers.size()
	), feature_override_axes_x.size()), feature_override_axes_z.size()), feature_override_half_extents.size())
	for i in range(count):
		overrides.append({
			"surface_id": feature_override_surface_ids[i],
			"center": feature_override_centers[i],
			"axis_x": feature_override_axes_x[i],
			"axis_z": feature_override_axes_z[i],
			"half_extents": feature_override_half_extents[i]
		})
	return overrides


func _validate_feature_overrides(errors: PackedStringArray) -> void:
	var expected_count: int = feature_override_surface_ids.size()
	_require_same_size(errors, feature_override_centers.size(), expected_count, "feature_override_centers", "feature_override_surface_ids")
	_require_same_size(errors, feature_override_axes_x.size(), expected_count, "feature_override_axes_x", "feature_override_surface_ids")
	_require_same_size(errors, feature_override_axes_z.size(), expected_count, "feature_override_axes_z", "feature_override_surface_ids")
	_require_same_size(errors, feature_override_half_extents.size(), expected_count, "feature_override_half_extents", "feature_override_surface_ids")
	for i in range(expected_count):
		if feature_override_surface_ids[i] == &"":
			errors.append("feature override surface id is empty at index " + str(i))
		if i < feature_override_axes_x.size() and feature_override_axes_x[i].length() <= MIN_EXTENT:
			errors.append("feature override axis_x is degenerate at index " + str(i))
		if i < feature_override_axes_z.size() and feature_override_axes_z[i].length() <= MIN_EXTENT:
			errors.append("feature override axis_z is degenerate at index " + str(i))
		if i < feature_override_half_extents.size() and (feature_override_half_extents[i].x <= MIN_EXTENT or feature_override_half_extents[i].y <= MIN_EXTENT):
			errors.append("feature override half_extents must be positive at index " + str(i))


func _require_same_size(errors: PackedStringArray, actual: int, expected: int, actual_name: String, expected_name: String) -> void:
	if actual != expected:
		errors.append(actual_name + " must have the same length as " + expected_name)


func _tile_index_in_grid(tile_index: Vector2i) -> bool:
	return (
		tile_index.x >= tile_grid_origin.x
		and tile_index.x < tile_grid_origin.x + tile_grid.x
		and tile_index.y >= tile_grid_origin.y
		and tile_index.y < tile_grid_origin.y + tile_grid.y
	)
