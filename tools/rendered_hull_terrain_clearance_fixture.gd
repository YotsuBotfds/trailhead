extends Node

const CedarPlayableScene: PackedScene = preload("res://scenes/cedar_hollow_playable.tscn")
const TerrainVisualBuilderScript: GDScript = preload("res://systems/render/terrain_visual_builder.gd")
const VEHICLE_GLB_PATH: String = "res://assets/models/vehicle/rc_buggy.glb"
const GLB_MAGIC: PackedByteArray = [0x67, 0x6C, 0x54, 0x46]
const JSON_CHUNK_TYPE: int = 0x4E4F534A
const BIN_CHUNK_TYPE: int = 0x004E4942
const FLOAT_COMPONENT_TYPE: int = 5126
const WAIT_FRAMES: int = 900
const SETTLE_FRAMES: int = 120
const CLEARANCE_MARGIN_M: float = 0.005
const SLOPE_PROBE_OFFSET_M: float = 0.30
const MIN_SLOPE_HEIGHT_DELTA_M: float = 0.01
const HEIGHT_NOT_FOUND: float = -1000000000.0
const HULL_MESH_NAMES: Array[String] = [
	"body",
	"side_panel",
	"skid_plate",
]

var _errors: PackedStringArray = PackedStringArray()
var _host: Node = null


func _ready() -> void:
	_host = CedarPlayableScene.instantiate()
	if _host == null:
		_errors.append("failed to instantiate Cedar playable scene")
		_finish()
		return
	add_child(_host)
	call_deferred("_inspect")


func _inspect() -> void:
	await _wait_for_rendered_spawn_tile()
	if not _errors.is_empty():
		_finish()
		return
	for _settle_index in range(SETTLE_FRAMES):
		await get_tree().physics_frame
		await get_tree().process_frame

	var vehicle: Node = _host.get_node_or_null("Vehicle")
	if vehicle == null:
		_errors.append("fixture missing Vehicle")
		_finish()
		return
	var body: Node3D = vehicle.get_node_or_null("PhysicsBody") as Node3D
	var visual_root: Node3D = vehicle.get_node_or_null("PhysicsBody/VisualRoot") as Node3D
	var streamer: Node = _host.get_node_or_null("CedarHollow/TerrainVisualStreamer")
	if body == null or visual_root == null or streamer == null:
		_errors.append("fixture missing body, visual root, or TerrainVisualStreamer")
		_finish()
		return

	var vehicle_position: Vector3 = body.global_position
	var cell: Vector2i = _cell_for_world_position(vehicle_position)
	var visual_tile: MeshInstance3D = streamer.call("visual_cell_node", cell) as MeshInstance3D
	if visual_tile == null or visual_tile.mesh == null:
		_errors.append("fixture missing committed visual tile under vehicle: " + str(cell))
		_finish()
		return
	var committed_step: int = int(streamer.call("committed_visual_cell_sample_step", cell))
	if committed_step != TerrainVisualBuilderScript.REGION_DETAIL_FULLRES_SAMPLE_STEP:
		_errors.append("visual tile under vehicle expected step=1, got step=" + str(committed_step))
		_finish()
		return

	var terrain_y: float = _mesh_height_at_world_xz(visual_tile, Vector2(vehicle_position.x, vehicle_position.z))
	if terrain_y <= HEIGHT_NOT_FOUND * 0.5:
		_errors.append("could not sample rendered terrain under vehicle at " + str(vehicle_position))
		_finish()
		return
	var slope_delta: float = _rendered_slope_delta(visual_tile, vehicle_position)
	if slope_delta < MIN_SLOPE_HEIGHT_DELTA_M:
		_errors.append("rendered terrain probe expected a sloped Zion tile; max delta " + str(slope_delta) + " across " + str(SLOPE_PROBE_OFFSET_M) + "m")

	var glb_data: Dictionary = _read_vehicle_glb_data()
	var hull_min_y: float = _hull_min_world_y(visual_root, glb_data)
	if hull_min_y <= HEIGHT_NOT_FOUND * 0.5:
		_errors.append("could not read transformed GLB hull vertices")
		_finish()
		return
	var clearance: float = hull_min_y - terrain_y
	if clearance < CLEARANCE_MARGIN_M:
		_errors.append("rendered hull clearance expected >= " + str(CLEARANCE_MARGIN_M) + "m, got " + str(clearance) + "m (hull_min_y=" + str(hull_min_y) + ", terrain_y=" + str(terrain_y) + ", cell=" + str(cell) + ")")

	_finish()


func _wait_for_rendered_spawn_tile() -> void:
	for _frame_index in range(WAIT_FRAMES):
		var vehicle: Node = _host.get_node_or_null("Vehicle")
		var streamer: Node = _host.get_node_or_null("CedarHollow/TerrainVisualStreamer")
		if vehicle != null and streamer != null:
			var body: Node3D = vehicle.get_node_or_null("PhysicsBody") as Node3D
			if body != null:
				var cell: Vector2i = _cell_for_world_position(body.global_position)
				var committed_step: int = int(streamer.call("committed_visual_cell_sample_step", cell))
				var frozen: bool = bool(vehicle.call("is_streaming_collision_frozen")) if vehicle.has_method("is_streaming_collision_frozen") else false
				var state: RefCounted = vehicle.call("get_state") as RefCounted
				var speed: float = 0.0
				var on_ground: bool = false
				if state != null:
					speed = Vector3(state.get("linear_velocity")).length()
					on_ground = bool(state.get("on_ground"))
				if committed_step == TerrainVisualBuilderScript.REGION_DETAIL_FULLRES_SAMPLE_STEP and not frozen and on_ground and speed < 0.20:
					return
		await get_tree().physics_frame
		await get_tree().process_frame
	_errors.append("timed out waiting for full-res rendered spawn tile and settled vehicle")


func _rendered_slope_delta(visual_tile: MeshInstance3D, position: Vector3) -> float:
	var center: float = _mesh_height_at_world_xz(visual_tile, Vector2(position.x, position.z))
	if center <= HEIGHT_NOT_FOUND * 0.5:
		return 0.0
	var max_delta: float = 0.0
	var probes: Array[Vector2] = [
		Vector2(position.x + SLOPE_PROBE_OFFSET_M, position.z),
		Vector2(position.x - SLOPE_PROBE_OFFSET_M, position.z),
		Vector2(position.x, position.z + SLOPE_PROBE_OFFSET_M),
		Vector2(position.x, position.z - SLOPE_PROBE_OFFSET_M),
	]
	for probe in probes:
		var height: float = _mesh_height_at_world_xz(visual_tile, probe)
		if height > HEIGHT_NOT_FOUND * 0.5:
			max_delta = maxf(max_delta, absf(height - center))
	return max_delta


func _mesh_height_at_world_xz(tile: MeshInstance3D, world_xz: Vector2) -> float:
	if tile == null or tile.mesh == null:
		return HEIGHT_NOT_FOUND
	var local_probe: Vector3 = tile.to_local(Vector3(world_xz.x, 0.0, world_xz.y))
	var best_height: float = HEIGHT_NOT_FOUND
	for surface_index in range(tile.mesh.get_surface_count()):
		var arrays: Array = tile.mesh.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
		for index in range(0, indices.size(), 3):
			var a: Vector3 = vertices[indices[index]]
			var b: Vector3 = vertices[indices[index + 1]]
			var c: Vector3 = vertices[indices[index + 2]]
			var local_y: float = _triangle_height_at_xz(a, b, c, Vector2(local_probe.x, local_probe.z))
			if local_y <= HEIGHT_NOT_FOUND * 0.5:
				continue
			var world_y: float = tile.to_global(Vector3(local_probe.x, local_y, local_probe.z)).y
			best_height = world_y
			return best_height
	return best_height


func _triangle_height_at_xz(a: Vector3, b: Vector3, c: Vector3, point: Vector2) -> float:
	var v0: Vector2 = Vector2(b.x - a.x, b.z - a.z)
	var v1: Vector2 = Vector2(c.x - a.x, c.z - a.z)
	var v2: Vector2 = Vector2(point.x - a.x, point.y - a.z)
	var dot00: float = v0.dot(v0)
	var dot01: float = v0.dot(v1)
	var dot02: float = v0.dot(v2)
	var dot11: float = v1.dot(v1)
	var dot12: float = v1.dot(v2)
	var denominator: float = dot00 * dot11 - dot01 * dot01
	if absf(denominator) <= 0.0000001:
		return HEIGHT_NOT_FOUND
	var inv_denominator: float = 1.0 / denominator
	var u: float = (dot11 * dot02 - dot01 * dot12) * inv_denominator
	var v: float = (dot00 * dot12 - dot01 * dot02) * inv_denominator
	if u < -0.0001 or v < -0.0001 or u + v > 1.0001:
		return HEIGHT_NOT_FOUND
	return a.y + (b.y - a.y) * u + (c.y - a.y) * v


func _hull_min_world_y(visual_root: Node3D, glb_data: Dictionary) -> float:
	var node_mesh_by_name: Dictionary[String, String] = glb_data.get("node_mesh_by_name", {})
	var vertices_by_mesh_name: Dictionary[String, PackedVector3Array] = glb_data.get("vertices_by_mesh_name", {})
	var hull_min_y: float = HEIGHT_NOT_FOUND
	for node_name in node_mesh_by_name.keys():
		var mesh_name: String = node_mesh_by_name[node_name]
		if not HULL_MESH_NAMES.has(mesh_name):
			continue
		if not vertices_by_mesh_name.has(mesh_name):
			continue
		var scene_node: Node3D = visual_root.find_child(node_name, true, false) as Node3D
		if scene_node == null:
			continue
		var vertices: PackedVector3Array = vertices_by_mesh_name[mesh_name]
		for vertex in vertices:
			var world_vertex: Vector3 = scene_node.global_transform * vertex
			hull_min_y = world_vertex.y if hull_min_y <= HEIGHT_NOT_FOUND * 0.5 else minf(hull_min_y, world_vertex.y)
	return hull_min_y


func _read_vehicle_glb_data() -> Dictionary:
	var path: String = VEHICLE_GLB_PATH
	if path.begins_with("res://"):
		path = path.substr(6)
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		_errors.append("could not open vehicle GLB: " + VEHICLE_GLB_PATH)
		return {}
	var bytes: PackedByteArray = file.get_buffer(file.get_length())
	file.close()
	if bytes.size() < 20:
		_errors.append("vehicle GLB too small")
		return {}
	for i in range(4):
		if bytes[i] != GLB_MAGIC[i]:
			_errors.append("vehicle GLB magic mismatch")
			return {}
	var total_length: int = _read_u32(bytes, 8)
	var offset: int = 12
	var gltf: Dictionary = {}
	var bin: PackedByteArray = PackedByteArray()
	while offset + 8 <= total_length:
		var chunk_length: int = _read_u32(bytes, offset)
		var chunk_type: int = _read_u32(bytes, offset + 4)
		offset += 8
		if offset + chunk_length > total_length:
			_errors.append("vehicle GLB chunk exceeds file length")
			return {}
		var chunk: PackedByteArray = bytes.slice(offset, offset + chunk_length)
		if chunk_type == JSON_CHUNK_TYPE:
			var parsed: Variant = JSON.parse_string(chunk.get_string_from_utf8())
			if typeof(parsed) == TYPE_DICTIONARY:
				gltf = parsed
		elif chunk_type == BIN_CHUNK_TYPE:
			bin = chunk
		offset += chunk_length
	if gltf.is_empty() or bin.is_empty():
		_errors.append("vehicle GLB missing JSON or BIN chunk")
		return {}
	return _extract_glb_geometry(gltf, bin)


func _extract_glb_geometry(gltf: Dictionary, bin: PackedByteArray) -> Dictionary:
	var meshes: Array = gltf.get("meshes", [])
	var nodes: Array = gltf.get("nodes", [])
	var accessors: Array = gltf.get("accessors", [])
	var vertices_by_mesh_name: Dictionary[String, PackedVector3Array] = {}
	var node_mesh_by_name: Dictionary[String, String] = {}
	for mesh_index in range(meshes.size()):
		var mesh: Dictionary = meshes[mesh_index]
		var mesh_name: String = String(mesh.get("name", ""))
		if mesh_name.is_empty() or not HULL_MESH_NAMES.has(mesh_name):
			continue
		var primitives: Array = mesh.get("primitives", [])
		if primitives.is_empty():
			continue
		var primitive: Dictionary = primitives[0]
		var attributes: Dictionary = primitive.get("attributes", {})
		var position_index: int = int(attributes.get("POSITION", -1))
		if position_index < 0 or position_index >= accessors.size():
			continue
		vertices_by_mesh_name[mesh_name] = _read_accessor_vec3(gltf, bin, position_index)
	for node in nodes:
		if typeof(node) != TYPE_DICTIONARY:
			continue
		var mesh_index: int = int(node.get("mesh", -1))
		if mesh_index < 0 or mesh_index >= meshes.size():
			continue
		var mesh: Dictionary = meshes[mesh_index]
		var mesh_name: String = String(mesh.get("name", ""))
		if not vertices_by_mesh_name.has(mesh_name):
			continue
		var node_name: String = String(node.get("name", ""))
		if not node_name.is_empty():
			node_mesh_by_name[node_name] = mesh_name
	return {
		"node_mesh_by_name": node_mesh_by_name,
		"vertices_by_mesh_name": vertices_by_mesh_name,
	}


func _read_accessor_vec3(gltf: Dictionary, bin: PackedByteArray, accessor_index: int) -> PackedVector3Array:
	var accessors: Array = gltf.get("accessors", [])
	var buffer_views: Array = gltf.get("bufferViews", [])
	var accessor: Dictionary = accessors[accessor_index]
	if int(accessor.get("componentType", -1)) != FLOAT_COMPONENT_TYPE or String(accessor.get("type", "")) != "VEC3":
		return PackedVector3Array()
	var buffer_view_index: int = int(accessor.get("bufferView", -1))
	if buffer_view_index < 0 or buffer_view_index >= buffer_views.size():
		return PackedVector3Array()
	var buffer_view: Dictionary = buffer_views[buffer_view_index]
	var base_offset: int = int(buffer_view.get("byteOffset", 0)) + int(accessor.get("byteOffset", 0))
	var stride: int = int(buffer_view.get("byteStride", 12))
	var count: int = int(accessor.get("count", 0))
	var vertices: PackedVector3Array = PackedVector3Array()
	for index in range(count):
		var offset: int = base_offset + index * stride
		if offset + 12 > bin.size():
			break
		vertices.append(Vector3(bin.decode_float(offset), bin.decode_float(offset + 4), bin.decode_float(offset + 8)))
	return vertices


func _cell_for_world_position(world_position: Vector3) -> Vector2i:
	var tile_size: float = GameConfig.STREAM_TILE_SIZE_M
	return Vector2i(int(floorf(world_position.x / tile_size)), int(floorf(world_position.z / tile_size)))


func _read_u32(bytes: PackedByteArray, offset: int) -> int:
	return int(bytes[offset]) | (int(bytes[offset + 1]) << 8) | (int(bytes[offset + 2]) << 16) | (int(bytes[offset + 3]) << 24)


func _finish() -> void:
	if _errors.is_empty():
		print("rendered_hull_terrain_clearance_fixture: OK")
		get_tree().quit(0)
		return
	for error in _errors:
		push_error(error)
	get_tree().quit(1)
