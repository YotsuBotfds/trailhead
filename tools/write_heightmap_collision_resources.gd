extends SceneTree

const DEFAULT_MAP_WIDTH: int = 101
const DEFAULT_MAP_DEPTH: int = 101

var _args: Dictionary[String, Variant] = {}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_args = _parse_args(OS.get_cmdline_user_args())
	var manifest_path: String = _arg_string("manifest", "")
	if manifest_path.is_empty():
		push_error("Missing --manifest")
		quit(1)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not (parsed is Dictionary):
		push_error("Manifest root must be a dictionary: " + manifest_path)
		quit(1)
		return
	var manifest: Dictionary[String, Variant] = _string_key_dictionary(parsed)
	var map_width: int = int(manifest.get("map_width", DEFAULT_MAP_WIDTH))
	var map_depth: int = int(manifest.get("map_depth", DEFAULT_MAP_DEPTH))
	if map_width <= 1 or map_depth <= 1:
		push_error("Invalid heightmap dimensions")
		quit(1)
		return
	if not manifest.has("tiles") or not (manifest["tiles"] is Array):
		push_error("Manifest missing tiles array")
		quit(1)
		return
	for value: Variant in manifest["tiles"]:
		if not (value is Dictionary):
			push_error("Tile entry must be a dictionary")
			quit(1)
			return
		var tile: Dictionary[String, Variant] = _string_key_dictionary(value)
		if not _write_tile(tile, map_width, map_depth):
			quit(1)
			return
	print("ok: wrote " + str((manifest["tiles"] as Array).size()) + " HeightMapShape3D resources")
	quit(0)


func _write_tile(tile: Dictionary[String, Variant], map_width: int, map_depth: int) -> bool:
	var heightmap_path: String = String(tile.get("heightmap_path", ""))
	var collision_path: String = String(tile.get("collision_path", ""))
	if heightmap_path.is_empty() or collision_path.is_empty():
		push_error("Tile entry missing heightmap_path or collision_path")
		return false
	var data: PackedByteArray = _read_bytes(heightmap_path)
	var expected_bytes: int = map_width * map_depth * 4
	if data.size() != expected_bytes:
		push_error(heightmap_path + " byte size expected " + str(expected_bytes) + ", got " + str(data.size()))
		return false
	var values: PackedFloat32Array = data.to_float32_array()
	if values.size() != map_width * map_depth:
		push_error(heightmap_path + " float count does not match heightmap dimensions")
		return false
	var shape: HeightMapShape3D = HeightMapShape3D.new()
	shape.map_width = map_width
	shape.map_depth = map_depth
	shape.map_data = values
	var global_collision_path: String = _globalize_path(collision_path)
	var dir_error: Error = DirAccess.make_dir_recursive_absolute(global_collision_path.get_base_dir())
	if dir_error != OK:
		push_error("Failed to create collision dir: " + error_string(dir_error))
		return false
	var save_error: Error = ResourceSaver.save(shape, global_collision_path)
	if save_error != OK:
		push_error("Failed to save " + collision_path + ": " + error_string(save_error))
		return false
	return true


func _read_bytes(path: String) -> PackedByteArray:
	var global_path: String = _globalize_path(path)
	var file: FileAccess = FileAccess.open(global_path, FileAccess.READ)
	if file == null:
		return PackedByteArray()
	var data: PackedByteArray = file.get_buffer(file.get_length())
	file.close()
	return data


func _globalize_path(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	return path


func _arg_string(key: String, default_value: String) -> String:
	if not _args.has(key):
		return default_value
	return String(_args[key])


func _parse_args(args: PackedStringArray) -> Dictionary[String, Variant]:
	var parsed: Dictionary[String, Variant] = {}
	var index: int = 0
	while index < args.size():
		var raw_arg: String = args[index]
		var arg: String = String(raw_arg)
		if not arg.begins_with("--"):
			index += 1
			continue
		var trimmed: String = arg.trim_prefix("--")
		var separator: int = trimmed.find("=")
		if separator < 0:
			if index + 1 < args.size() and not String(args[index + 1]).begins_with("--"):
				parsed[trimmed] = String(args[index + 1])
				index += 2
				continue
			else:
				parsed[trimmed] = "true"
		else:
			parsed[trimmed.substr(0, separator)] = trimmed.substr(separator + 1)
		index += 1
	return parsed


func _string_key_dictionary(value: Variant) -> Dictionary[String, Variant]:
	var result: Dictionary[String, Variant] = {}
	if not (value is Dictionary):
		return result
	for key: Variant in value:
		result[String(key)] = value[key]
	return result
