extends Node

const CedarPalette: Resource = preload("res://data/surface_palettes/cedar_hollow_terrain.tres")
const PNG_SIGNATURE: PackedByteArray = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]
const PNG_IDAT_COMPRESSION_ZLIB: int = FileAccess.COMPRESSION_DEFLATE # Godot 4.6 has no COMPRESSION_ZLIB enum.

var _errors: PackedStringArray = PackedStringArray()


func _ready() -> void:
	call_deferred("_inspect")


func _inspect() -> void:
	var palette_errors: PackedStringArray = CedarPalette.call("validate")
	for error in palette_errors:
		_errors.append(error)
	_require_surface_resources()
	_require_png_ids_match_palette()
	_finish()


func _require_surface_resources() -> void:
	var surface_ids: Array[StringName] = CedarPalette.get("surface_ids")
	for surface_id in surface_ids:
		var path: String = "res://data/surfaces/" + String(surface_id) + ".tres"
		if not ResourceLoader.exists(path):
			_errors.append("missing surface resource for palette id: " + String(surface_id))
			continue
		var surface: Resource = load(path)
		if surface == null:
			_errors.append("failed to load surface resource: " + path)
			continue
		var loaded_id: StringName = surface.get("id")
		if loaded_id != surface_id:
			_errors.append(path + " id expected " + String(surface_id) + ", got " + String(loaded_id))


func _require_png_ids_match_palette() -> void:
	var image_path: String = CedarPalette.get("image_path")
	if image_path.is_empty():
		return
	var file: FileAccess = FileAccess.open(image_path, FileAccess.READ)
	if file == null:
		_errors.append("failed to open surface-ID PNG: " + image_path)
		return
	var bytes: PackedByteArray = file.get_buffer(file.get_length())
	var observed_ids: Array[int] = _read_png_unique_samples(bytes)
	var expected_ids: Array[int] = CedarPalette.get("id_values")
	observed_ids.sort()
	expected_ids.sort()
	if observed_ids.size() != expected_ids.size():
		_errors.append("surface-ID PNG expected " + str(expected_ids.size()) + " ids, got " + str(observed_ids.size()))
		return
	for i in range(expected_ids.size()):
		if observed_ids[i] != expected_ids[i]:
			_errors.append("surface-ID PNG ids expected " + str(expected_ids) + ", got " + str(observed_ids))
			return


func _read_png_unique_samples(bytes: PackedByteArray) -> Array[int]:
	var ids: Array[int] = []
	if bytes.size() < 24:
		_errors.append("surface-ID PNG too small")
		return ids
	for i in range(PNG_SIGNATURE.size()):
		if bytes[i] != PNG_SIGNATURE[i]:
			_errors.append("surface-ID PNG has invalid signature")
			return ids
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
		var chunk_data: PackedByteArray = bytes.slice(offset, offset + chunk_length)
		offset += chunk_length + 4
		if chunk_type == "IHDR":
			width = _read_u32_be(chunk_data, 0)
			height = _read_u32_be(chunk_data, 4)
			bit_depth = chunk_data[8]
			color_type = chunk_data[9]
			var interlace: int = chunk_data[12]
			if interlace != 0:
				_errors.append("surface-ID PNG must be non-interlaced")
				return ids
		elif chunk_type == "IDAT":
			idat.append_array(chunk_data)
		elif chunk_type == "IEND":
			break
	if width <= 0 or height <= 0:
		_errors.append("surface-ID PNG has invalid dimensions")
		return ids
	if bit_depth != 8:
		_errors.append("surface-ID PNG must use 8-bit channels")
		return ids
	var channels: int = _channels_for_color_type(color_type)
	if channels <= 0:
		_errors.append("surface-ID PNG has unsupported color type: " + str(color_type))
		return ids
	var raw: PackedByteArray = idat.decompress_dynamic(-1, PNG_IDAT_COMPRESSION_ZLIB)
	var expected_size: int = (width * channels + 1) * height
	if raw.size() != expected_size:
		_errors.append("surface-ID PNG payload size expected " + str(expected_size) + ", got " + str(raw.size()))
		return ids
	var stride: int = width * channels
	var previous: PackedByteArray = PackedByteArray()
	previous.resize(stride)
	var raw_offset: int = 0
	for _y in range(height):
		var filter_type: int = raw[raw_offset]
		raw_offset += 1
		var row: PackedByteArray = raw.slice(raw_offset, raw_offset + stride)
		raw_offset += stride
		_unfilter_png_row(row, previous, channels, filter_type)
		for x in range(width):
			var value: int = row[x * channels]
			if not ids.has(value):
				ids.append(value)
		previous = row
	return ids


func _unfilter_png_row(row: PackedByteArray, previous: PackedByteArray, bytes_per_pixel: int, filter_type: int) -> void:
	if filter_type == 0:
		return
	if filter_type == 1:
		for index in range(row.size()):
			var left: int = row[index - bytes_per_pixel] if index >= bytes_per_pixel else 0
			row[index] = (row[index] + left) & 0xff
		return
	if filter_type == 2:
		for index in range(row.size()):
			row[index] = (row[index] + previous[index]) & 0xff
		return
	if filter_type == 3:
		for index in range(row.size()):
			var left: int = row[index - bytes_per_pixel] if index >= bytes_per_pixel else 0
			var up: int = previous[index]
			row[index] = (row[index] + ((left + up) / 2)) & 0xff
		return
	if filter_type == 4:
		for index in range(row.size()):
			var left: int = row[index - bytes_per_pixel] if index >= bytes_per_pixel else 0
			var up: int = previous[index]
			var up_left: int = previous[index - bytes_per_pixel] if index >= bytes_per_pixel else 0
			row[index] = (row[index] + _paeth(left, up, up_left)) & 0xff
		return
	_errors.append("surface-ID PNG has unsupported filter type: " + str(filter_type))


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


func _finish() -> void:
	if _errors.is_empty():
		print("ok: Cedar terrain surface palette matches surface resources and surface-ID PNG")
		get_tree().quit(0)
		return
	for error in _errors:
		push_error(error)
	get_tree().quit(1)
