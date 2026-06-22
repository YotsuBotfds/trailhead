extends RefCounted
# Headless-safe GLB wheel-radius reader. Parses assets/models/vehicle/rc_buggy.glb
# directly (magic `glTF` -> JSON chunk -> accessors -> mesh `wheel_tire` POSITION
# min/max) and returns the real rolling radius. No rendering, no import cache, no
# Godot scene load: pure FileAccess + JSON, so it runs under --headless.
#
# Purpose: the old `_require_visual_wheel_socket_contact_follow` inspector check
# was self-cancelling (it fabricated a hit point at `expected_y - wheel_radius`
# and procedural_buggy_visual added `+ wheel_radius` back, so ANY value passed).
# This reader is the de-circularized authority: it reads the mesh's actual
# bounding-box radius and lets the inspectors assert GameConfig.wheel_radius
# matches it. Now a drift in EITHER the mesh OR the constant turns the
# inspector red instead of staying silently green.

const VEHICLE_GLB_PATH: String = "res://assets/models/vehicle/rc_buggy.glb"
const WHEEL_TIRE_MESH_NAME: String = "wheel_tire"
const GLB_MAGIC: PackedByteArray = [0x67, 0x6C, 0x54, 0x46]  # "glTF"
const JSON_CHUNK_TYPE: int = 0x4E4F534A  # "JSON" little-endian
const NOT_FOUND: float = -1.0


static func read_wheel_radius() -> float:
	# Returns the X/Z half-extent (rolling radius) of the `wheel_tire` mesh in the
	# vehicle GLB, in meters. The mesh is authored with the axle along Y (the host
	# rotates it 90 deg about Z at runtime to stand the wheel up, so the in-GLB
	# X/Z extent IS the rolling radius). Returns NOT_FOUND on any parse failure.
	var path: String = VEHICLE_GLB_PATH
	var res_path: String = path
	if path.begins_with("res://"):
		res_path = path.substr(6)
	var file: FileAccess = FileAccess.open(res_path, FileAccess.READ)
	if file == null:
		return NOT_FOUND
	var bytes: PackedByteArray = file.get_buffer(file.get_length())
	file.close()
	if bytes.size() < 20:
		return NOT_FOUND
	for i in range(4):
		if bytes[i] != GLB_MAGIC[i]:
			return NOT_FOUND
	var total_length: int = _read_u32(bytes, 8)
	if total_length <= 12 or total_length > bytes.size():
		return NOT_FOUND
	var offset: int = 12
	var gltf: Dictionary = {}
	while offset + 8 <= total_length:
		var chunk_length: int = _read_u32(bytes, offset)
		var chunk_type: int = _read_u32(bytes, offset + 4)
		offset += 8
		if chunk_length < 0 or offset + chunk_length > total_length:
			return NOT_FOUND
		if chunk_type == JSON_CHUNK_TYPE:
			var raw: PackedByteArray = bytes.slice(offset, offset + chunk_length)
			var text: String = raw.get_string_from_utf8()
			# glTF spec: the JSON chunk is padded with trailing 0x20 spaces (and may
			# carry a trailing NUL); JSON.parse_string tolerates trailing whitespace,
			# so no explicit strip is needed.
			var parsed: Variant = JSON.parse_string(text)
			if typeof(parsed) == TYPE_DICTIONARY:
				gltf = parsed
			break
		offset += chunk_length
	if gltf.is_empty():
		return NOT_FOUND
	return _wheel_tire_radius_from_gltf(gltf)


static func _wheel_tire_radius_from_gltf(gltf: Dictionary) -> float:
	var meshes: Array = gltf.get("meshes", [])
	var accessors: Array = gltf.get("accessors", [])
	if meshes.is_empty() or accessors.is_empty():
		return NOT_FOUND
	for mesh in meshes:
		if typeof(mesh) != TYPE_DICTIONARY:
			continue
		var name: String = String(mesh.get("name", ""))
		if name != WHEEL_TIRE_MESH_NAME:
			continue
		var primitives: Array = mesh.get("primitives", [])
		if primitives.is_empty():
			return NOT_FOUND
		var prim: Dictionary = primitives[0]
		var attributes: Dictionary = prim.get("attributes", {})
		var position_index: int = int(attributes.get("POSITION", -1))
		if position_index < 0 or position_index >= accessors.size():
			return NOT_FOUND
		var accessor: Dictionary = accessors[position_index]
		var a_min: Array = accessor.get("min", [])
		var a_max: Array = accessor.get("max", [])
		if a_min.size() < 3 or a_max.size() < 3:
			return NOT_FOUND
		# In-GLB axle is along Y (half-width 0.017); rolling radius = X/Z half-extent.
		var half_x: float = (float(a_max[0]) - float(a_min[0])) * 0.5
		var half_z: float = (float(a_max[2]) - float(a_min[2])) * 0.5
		# The mesh is round: X and Z agree. Use the larger as the rolling radius
		# (guards against a future non-circular tire where the contact direction
		# is the relevant one).
		return maxf(half_x, half_z)
	return NOT_FOUND


static func _read_u32(bytes: PackedByteArray, offset: int) -> int:
	return int(bytes[offset]) | (int(bytes[offset + 1]) << 8) | (int(bytes[offset + 2]) << 16) | (int(bytes[offset + 3]) << 24)
