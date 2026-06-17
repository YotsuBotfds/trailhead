class_name SurfaceMap
extends Node

const DEFAULT_SURFACE_ID: StringName = &"packed_dirt"
const TERRAIN_SURFACE_MAP_GROUP: StringName = &"terrain_surface_id_map"
const TERRAIN_SURFACE_OVERRIDE_RECTS_META: StringName = &"terrain_surface_override_rects"
const TERRAIN_SURFACE_WORLD_OFFSET_META: StringName = &"terrain_surface_world_offset"
const PNG_SIGNATURE: PackedByteArray = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]
const SOURCE_TAGGED: String = "tagged"
const SOURCE_TERRAIN: String = "terrain"
const SOURCE_FALLBACK: String = "fallback"

var _defs: Dictionary[StringName, Resource] = {}
var _fallback: Resource = null
var _source_counts: Dictionary[String, int] = {}
var _terrain_palette: Resource = null
var _terrain_def: Resource = null
var _terrain_surface_samples: PackedByteArray = PackedByteArray()
var _terrain_surface_width: int = 0
var _terrain_surface_height: int = 0
var _terrain_bounds_min: Vector2 = Vector2.ZERO
var _terrain_bounds_max: Vector2 = Vector2.ZERO
var _terrain_sampler_ready: bool = false
var _terrain_id_counts: Dictionary[String, int] = {}


func _ready() -> void:
	load_defs("res://data/surfaces/")
	_fallback = _get_def(DEFAULT_SURFACE_ID)
	reset_source_counts()
	GameManager.register_surface_map(self)


func load_defs(dir_path: String) -> void:
	_defs.clear()
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		push_error("SurfaceMap failed to open: " + dir_path)
		return
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var resource_path: String = dir_path.path_join(file_name)
			var loaded: Resource = load(resource_path)
			if loaded != null:
				var surface_id: StringName = loaded.get("id")
				if surface_id != &"":
					_defs[surface_id] = loaded
		file_name = dir.get_next()
	dir.list_dir_end()


func resolve_from_collider(collider: Object) -> Resource:
	var surface_id: StringName = surface_id_from_collider(collider)
	return def_for_id(surface_id)


func resolve_from_collider_at(collider: Object, world_position: Vector3) -> Resource:
	var surface_id: StringName = surface_id_from_collider_at(collider, world_position)
	return def_for_id(surface_id)


func def_for_id(surface_id: StringName) -> Resource:
	if _defs.has(surface_id):
		return _defs[surface_id]
	return _fallback


func surface_id_from_collider(collider: Object) -> StringName:
	var tagged_surface_id: StringName = _tagged_surface_id_from_collider(collider)
	if tagged_surface_id != &"":
		_increment_source_count(SOURCE_TAGGED)
		return tagged_surface_id
	_increment_source_count(SOURCE_FALLBACK)
	return DEFAULT_SURFACE_ID


func surface_id_from_collider_at(collider: Object, world_position: Vector3) -> StringName:
	var tagged_surface_id: StringName = _tagged_surface_id_from_collider(collider)
	if tagged_surface_id != &"":
		_increment_source_count(SOURCE_TAGGED)
		return tagged_surface_id
	var node: Node = collider as Node
	if node != null and node.is_in_group(TERRAIN_SURFACE_MAP_GROUP):
		if _terrain_sampler_ready:
			_increment_source_count(SOURCE_TERRAIN)
			var terrain_position: Vector3 = _terrain_position_for_collider(node, world_position)
			var override_surface_id: StringName = _surface_id_from_terrain_overrides(node, terrain_position)
			if override_surface_id != &"":
				return override_surface_id
			return surface_id_at_world_position(terrain_position, DEFAULT_SURFACE_ID)
		_increment_source_count(SOURCE_FALLBACK)
		return DEFAULT_SURFACE_ID
	if _terrain_sampler_ready:
		_increment_source_count(SOURCE_TERRAIN)
		return surface_id_at_world_position(world_position, DEFAULT_SURFACE_ID)
	_increment_source_count(SOURCE_FALLBACK)
	return DEFAULT_SURFACE_ID


func surface_id_at_world_position(world_position: Vector3, fallback: StringName = DEFAULT_SURFACE_ID) -> StringName:
	if not _terrain_sampler_ready or _terrain_palette == null or _terrain_surface_samples.is_empty():
		return fallback
	if _terrain_surface_width <= 0 or _terrain_surface_height <= 0:
		return fallback
	var uv: Vector2 = _surface_uv_for_world_position(world_position)
	var pixel_x: int = clampi(roundi(uv.x * float(_terrain_surface_width - 1)), 0, _terrain_surface_width - 1)
	var pixel_y: int = clampi(roundi(uv.y * float(_terrain_surface_height - 1)), 0, _terrain_surface_height - 1)
	var sample_index: int = pixel_y * _terrain_surface_width + pixel_x
	if sample_index < 0 or sample_index >= _terrain_surface_samples.size():
		return fallback
	var id_value: int = _terrain_surface_samples[sample_index]
	_increment_terrain_id_count(id_value)
	return StringName(_terrain_palette.call("surface_id_for", id_value, fallback))


func configure_terrain_palette(palette_path: String, bounds_min: Vector2, bounds_max: Vector2) -> bool:
	_reset_terrain_sampler()
	_terrain_bounds_min = bounds_min
	_terrain_bounds_max = bounds_max
	return _load_terrain_palette(palette_path)


func configure_terrain_def(terrain_def_path: String) -> bool:
	_reset_terrain_sampler()
	var terrain_def: Resource = load(terrain_def_path)
	if terrain_def == null:
		push_error("SurfaceMap failed to load TerrainDef: " + terrain_def_path)
		return false
	var terrain_errors: PackedStringArray = terrain_def.call("validate")
	if terrain_errors.size() > 0:
		push_error("SurfaceMap TerrainDef invalid: " + _join_errors(terrain_errors))
		return false
	_terrain_bounds_min = terrain_def.get("bounds_min_xz")
	_terrain_bounds_max = terrain_def.get("bounds_max_xz")
	var palette_path: String = terrain_def.get("surface_palette_path")
	if not _load_terrain_palette(palette_path):
		return false
	_terrain_def = terrain_def
	return true


func _reset_terrain_sampler() -> void:
	_terrain_palette = null
	_terrain_def = null
	_terrain_surface_samples = PackedByteArray()
	_terrain_surface_width = 0
	_terrain_surface_height = 0
	_terrain_sampler_ready = false
	_terrain_bounds_min = Vector2.ZERO
	_terrain_bounds_max = Vector2.ZERO


func _load_terrain_palette(palette_path: String) -> bool:
	var palette: Resource = load(palette_path)
	if palette == null:
		push_error("SurfaceMap failed to load terrain palette: " + palette_path)
		return false
	var palette_errors: PackedStringArray = palette.call("validate")
	if palette_errors.size() > 0:
		push_error("SurfaceMap terrain palette invalid: " + _join_errors(palette_errors))
		return false
	var missing_defs: PackedStringArray = _missing_surface_defs_for_palette(palette)
	if missing_defs.size() > 0:
		push_error("SurfaceMap terrain palette references missing SurfaceDef ids: " + _join_errors(missing_defs))
		return false
	var image_path: String = palette.get("image_path")
	if not _load_terrain_surface_id_png(image_path):
		push_error("SurfaceMap failed to load terrain surface-ID image: " + image_path)
		return false
	_terrain_palette = palette
	_terrain_sampler_ready = true
	return true


func _surface_uv_for_world_position(world_position: Vector3) -> Vector2:
	if _terrain_def != null:
		return _terrain_def.call("world_to_surface_uv", Vector2(world_position.x, world_position.z))
	var width_m: float = _terrain_bounds_max.x - _terrain_bounds_min.x
	var depth_m: float = _terrain_bounds_max.y - _terrain_bounds_min.y
	if width_m <= 0.001 or depth_m <= 0.001:
		return Vector2.ZERO
	return Vector2(
		clampf((world_position.x - _terrain_bounds_min.x) / width_m, 0.0, 1.0),
		clampf((_terrain_bounds_max.y - world_position.z) / depth_m, 0.0, 1.0)
	)


func is_terrain_sampler_ready() -> bool:
	return _terrain_sampler_ready


func reset_source_counts() -> void:
	_source_counts = {
		SOURCE_TAGGED: 0,
		SOURCE_TERRAIN: 0,
		SOURCE_FALLBACK: 0
	}
	_terrain_id_counts.clear()


func source_counts() -> Dictionary[String, int]:
	return _source_counts.duplicate()


func terrain_id_counts() -> Dictionary[String, int]:
	return _terrain_id_counts.duplicate()


func _terrain_position_for_collider(node: Node, world_position: Vector3) -> Vector3:
	var offset: Vector2 = _terrain_world_offset_for_collider(node)
	return Vector3(world_position.x - offset.x, world_position.y, world_position.z - offset.y)


func _terrain_world_offset_for_collider(node: Node) -> Vector2:
	if not node.has_meta(TERRAIN_SURFACE_WORLD_OFFSET_META):
		return Vector2.ZERO
	var value: Variant = node.get_meta(TERRAIN_SURFACE_WORLD_OFFSET_META)
	if value is Vector2:
		return value
	if value is Vector3:
		return Vector2(value.x, value.z)
	return Vector2.ZERO


func _tagged_surface_id_from_collider(collider: Object) -> StringName:
	var node: Node = collider as Node
	if node == null:
		return &""
	for group_name in node.get_groups():
		var group_string: String = String(group_name)
		if group_string.begins_with("surf_"):
			return StringName(group_string.substr(5))
	var node_name: String = node.name
	var marker_index: int = node_name.find("__surf_")
	if marker_index != -1:
		return StringName(node_name.substr(marker_index + 7))
	return &""


func _surface_id_from_terrain_overrides(node: Node, world_position: Vector3) -> StringName:
	if not node.has_meta(TERRAIN_SURFACE_OVERRIDE_RECTS_META):
		return &""
	var overrides_value: Variant = node.get_meta(TERRAIN_SURFACE_OVERRIDE_RECTS_META)
	if not (overrides_value is Array):
		return &""
	var point: Vector2 = Vector2(world_position.x, world_position.z)
	for value in overrides_value:
		if not (value is Dictionary):
			continue
		var override_data: Dictionary = value
		var surface_id: StringName = StringName(override_data.get("surface_id", &""))
		if surface_id == &"":
			continue
		var center: Vector2 = override_data.get("center", Vector2.ZERO)
		var axis_x: Vector2 = override_data.get("axis_x", Vector2.RIGHT)
		var axis_z: Vector2 = override_data.get("axis_z", Vector2.UP)
		var half_extents: Vector2 = override_data.get("half_extents", Vector2.ZERO)
		if _point_in_oriented_rect(point, center, axis_x, axis_z, half_extents):
			return surface_id
	return &""


func _point_in_oriented_rect(point: Vector2, center: Vector2, axis_x: Vector2, axis_z: Vector2, half_extents: Vector2) -> bool:
	if half_extents.x <= 0.0 or half_extents.y <= 0.0:
		return false
	if axis_x.length() <= 0.001 or axis_z.length() <= 0.001:
		return false
	var relative: Vector2 = point - center
	var local_x: float = relative.dot(axis_x.normalized())
	var local_z: float = relative.dot(axis_z.normalized())
	return absf(local_x) <= half_extents.x and absf(local_z) <= half_extents.y


func fallback() -> Resource:
	return _fallback


func _get_def(surface_id: StringName) -> Resource:
	if _defs.has(surface_id):
		return _defs[surface_id]
	return null


func _missing_surface_defs_for_palette(palette: Resource) -> PackedStringArray:
	var missing: PackedStringArray = PackedStringArray()
	var surface_ids: Array[StringName] = palette.get("surface_ids")
	for surface_id in surface_ids:
		if not _defs.has(surface_id):
			missing.append(String(surface_id))
	return missing


func _increment_source_count(source_id: String) -> void:
	_source_counts[source_id] = int(_source_counts.get(source_id, 0)) + 1


func _increment_terrain_id_count(id_value: int) -> void:
	var key: String = str(id_value)
	_terrain_id_counts[key] = int(_terrain_id_counts.get(key, 0)) + 1


func _load_terrain_surface_id_png(path: String) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var bytes: PackedByteArray = file.get_buffer(file.get_length())
	file.close()
	return _decode_terrain_surface_id_png(bytes)


func _decode_terrain_surface_id_png(bytes: PackedByteArray) -> bool:
	_terrain_surface_samples = PackedByteArray()
	_terrain_surface_width = 0
	_terrain_surface_height = 0
	if bytes.size() < 24:
		return false
	for i in range(PNG_SIGNATURE.size()):
		if bytes[i] != PNG_SIGNATURE[i]:
			return false
	var offset: int = 8
	var width: int = 0
	var height: int = 0
	var bit_depth: int = 0
	var color_type: int = 0
	var idat: PackedByteArray = PackedByteArray()
	while offset + 8 <= bytes.size():
		var chunk_length: int = _read_u32_be(bytes, offset)
		offset += 4
		var chunk_type: String = _chunk_type(bytes, offset)
		offset += 4
		if offset + chunk_length + 4 > bytes.size():
			return false
		var chunk_data: PackedByteArray = bytes.slice(offset, offset + chunk_length)
		offset += chunk_length + 4
		if chunk_type == "IHDR":
			width = _read_u32_be(chunk_data, 0)
			height = _read_u32_be(chunk_data, 4)
			bit_depth = chunk_data[8]
			color_type = chunk_data[9]
			var interlace: int = chunk_data[12]
			if interlace != 0:
				return false
		elif chunk_type == "IDAT":
			idat.append_array(chunk_data)
		elif chunk_type == "IEND":
			break
	if width <= 0 or height <= 0 or bit_depth != 8:
		return false
	var channels: int = _channels_for_color_type(color_type)
	if channels <= 0:
		return false
	var raw: PackedByteArray = idat.decompress_dynamic(-1, FileAccess.COMPRESSION_DEFLATE)
	var expected_size: int = (width * channels + 1) * height
	if raw.size() != expected_size:
		return false
	var stride: int = width * channels
	var previous: PackedByteArray = PackedByteArray()
	previous.resize(stride)
	var raw_offset: int = 0
	var samples: PackedByteArray = PackedByteArray()
	samples.resize(width * height)
	for y in range(height):
		var filter_type: int = raw[raw_offset]
		raw_offset += 1
		var row: PackedByteArray = raw.slice(raw_offset, raw_offset + stride)
		raw_offset += stride
		if not _unfilter_png_row(row, previous, channels, filter_type):
			return false
		for x in range(width):
			samples[y * width + x] = row[x * channels]
		previous = row
	_terrain_surface_samples = samples
	_terrain_surface_width = width
	_terrain_surface_height = height
	return true


func _unfilter_png_row(row: PackedByteArray, previous: PackedByteArray, bytes_per_pixel: int, filter_type: int) -> bool:
	if filter_type == 0:
		return true
	if filter_type == 1:
		for index in range(row.size()):
			var left: int = row[index - bytes_per_pixel] if index >= bytes_per_pixel else 0
			row[index] = (row[index] + left) & 0xff
		return true
	if filter_type == 2:
		for index in range(row.size()):
			row[index] = (row[index] + previous[index]) & 0xff
		return true
	if filter_type == 3:
		for index in range(row.size()):
			var left: int = row[index - bytes_per_pixel] if index >= bytes_per_pixel else 0
			var up: int = previous[index]
			row[index] = (row[index] + ((left + up) / 2)) & 0xff
		return true
	if filter_type == 4:
		for index in range(row.size()):
			var left: int = row[index - bytes_per_pixel] if index >= bytes_per_pixel else 0
			var up: int = previous[index]
			var up_left: int = previous[index - bytes_per_pixel] if index >= bytes_per_pixel else 0
			row[index] = (row[index] + _paeth(left, up, up_left)) & 0xff
		return true
	return false


func _paeth(left: int, up: int, up_left: int) -> int:
	var p: int = left + up - up_left
	var pa: int = absi(p - left)
	var pb: int = absi(p - up)
	var pc: int = absi(p - up_left)
	if pa <= pb and pa <= pc:
		return left
	if pb <= pc:
		return up
	return up_left


func _channels_for_color_type(color_type: int) -> int:
	match color_type:
		0:
			return 1
		2:
			return 3
		3:
			return 1
		4:
			return 2
		6:
			return 4
		_:
			return 0


func _chunk_type(bytes: PackedByteArray, offset: int) -> String:
	return String.chr(bytes[offset]) + String.chr(bytes[offset + 1]) + String.chr(bytes[offset + 2]) + String.chr(bytes[offset + 3])


func _read_u32_be(bytes: PackedByteArray, offset: int) -> int:
	return (bytes[offset] << 24) | (bytes[offset + 1] << 16) | (bytes[offset + 2] << 8) | bytes[offset + 3]


func _join_errors(errors: PackedStringArray) -> String:
	var out: String = ""
	for i in range(errors.size()):
		if i > 0:
			out += "; "
		out += errors[i]
	return out
