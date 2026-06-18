class_name DesertPropBuilder
extends RefCounted

const PROP_TRAILHEAD_SIGN: StringName = &"trailhead_sign"
const PROP_ROCK_CAIRN: StringName = &"rock_cairn"
const PROP_BLEACHED_DEAD_LOG: StringName = &"bleached_dead_log"
const PROP_MARKER_POST: StringName = &"marker_post"
const PROP_DESERT_SHRUB: StringName = &"desert_shrub"
const PROP_IDS: Array[StringName] = [
	PROP_TRAILHEAD_SIGN,
	PROP_ROCK_CAIRN,
	PROP_BLEACHED_DEAD_LOG,
	PROP_MARKER_POST,
	PROP_DESERT_SHRUB
]

static func build_prop(prop_id: StringName, seed: int = 0) -> Node3D:
	if prop_id == PROP_TRAILHEAD_SIGN:
		return build_trailhead_sign(seed)
	if prop_id == PROP_ROCK_CAIRN:
		return build_rock_cairn(seed)
	if prop_id == PROP_BLEACHED_DEAD_LOG:
		return build_bleached_dead_log(seed)
	if prop_id == PROP_MARKER_POST:
		return build_marker_post(seed)
	if prop_id == PROP_DESERT_SHRUB:
		return build_desert_shrub(seed)
	push_error("DesertPropBuilder unknown prop id: " + String(prop_id))
	return Node3D.new()


static func build_trailhead_sign(seed: int = 0) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = "trailhead_sign"
	var wood_material: StandardMaterial3D = _wood_material()
	var dark_wood_material: StandardMaterial3D = _dark_wood_material()
	_add_box(root, "post", Vector3(0.055, 0.34 + _unit(seed, 1) * 0.04, 0.055), Vector3(0.0, 0.17, 0.0), wood_material)
	_add_box(root, "board", Vector3(0.38, 0.12, 0.045), Vector3(0.0, 0.30, -0.015), wood_material)
	_add_box(root, "glyph", Vector3(0.055, 0.065, 0.008), Vector3(-0.095, 0.304, -0.043), dark_wood_material)
	_add_box(root, "glyph_notch", Vector3(0.040, 0.010, 0.010), Vector3(0.060, 0.306, -0.044), dark_wood_material)
	_snap_base_to_ground(root)
	return root


static func build_rock_cairn(seed: int = 0) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = "rock_cairn"
	var sandstone_material: StandardMaterial3D = _sandstone_material()
	var stone_count: int = 3 + int(floor(_unit(seed, 2) * 3.0))
	var base_y: float = 0.0
	for stone_index in range(stone_count):
		var width: float = 0.25 - float(stone_index) * 0.035 + _unit(seed, 10 + stone_index) * 0.025
		var height: float = 0.070 - float(stone_index) * 0.006 + _unit(seed, 20 + stone_index) * 0.015
		var depth: float = 0.20 - float(stone_index) * 0.026 + _unit(seed, 30 + stone_index) * 0.020
		var center: Vector3 = Vector3((_unit(seed, 40 + stone_index) - 0.5) * 0.025, base_y + height * 0.5, (_unit(seed, 50 + stone_index) - 0.5) * 0.025)
		var stone: MeshInstance3D = _mesh_instance("stone_" + str(stone_index), _faceted_stone_mesh("desert_cairn_stone_" + str(seed) + "_" + str(stone_index), Vector3(width, height, depth), seed + stone_index * 19), sandstone_material)
		stone.position = center
		stone.rotation.y = (_unit(seed, 60 + stone_index) - 0.5) * 0.7
		root.add_child(stone)
		base_y += height * 0.86
	_snap_base_to_ground(root)
	return root


static func build_bleached_dead_log(seed: int = 0) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = "bleached_dead_log"
	var bleached_wood_material: StandardMaterial3D = _bleached_wood_material()
	var segment_count: int = 4
	var radius: float = 0.040 + _unit(seed, 3) * 0.014
	var segment_length: float = 0.15
	for segment_index in range(segment_count):
		var x: float = -0.225 + float(segment_index) * segment_length
		var y: float = radius + absf(sin(float(segment_index) * 1.7 + _unit(seed, 4))) * 0.020
		var z: float = sin(float(segment_index) * 0.9 + _unit(seed, 5) * TAU) * 0.035
		var log_segment: MeshInstance3D = _mesh_instance("log_segment_" + str(segment_index), _prism_x_mesh("desert_log_segment_" + str(seed) + "_" + str(segment_index), segment_length * 1.08, radius * (1.0 - float(segment_index) * 0.035), 7), bleached_wood_material)
		log_segment.position = Vector3(x, y, z)
		log_segment.rotation.y = (_unit(seed, 10 + segment_index) - 0.5) * 0.25
		log_segment.rotation.z = (_unit(seed, 20 + segment_index) - 0.5) * 0.18
		root.add_child(log_segment)
	_add_prong(root, "branch_left", Vector3(-0.08, radius * 1.8, 0.020), Vector3(0.12, 0.12, -0.10), 0.018, bleached_wood_material)
	_add_prong(root, "branch_right", Vector3(0.12, radius * 1.6, -0.010), Vector3(0.20, 0.11, 0.12), 0.014, bleached_wood_material)
	_snap_base_to_ground(root)
	return root


static func build_marker_post(seed: int = 0) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = "marker_post"
	var wood_material: StandardMaterial3D = _wood_material()
	var height: float = 0.33 + _unit(seed, 6) * 0.06
	_add_box(root, "post", Vector3(0.060, height, 0.060), Vector3(0.0, height * 0.5, 0.0), wood_material)
	_add_box(root, "cap_slant", Vector3(0.070, 0.024, 0.070), Vector3(0.0, height + 0.010, 0.0), wood_material)
	var wire: MeshInstance3D = _mesh_instance("wire_stub", _prism_x_mesh("desert_marker_wire_" + str(seed), 0.20, 0.006, 5), _dark_wood_material())
	wire.position = Vector3(0.095, height * 0.72, 0.0)
	wire.rotation.z = (_unit(seed, 7) - 0.5) * 0.16
	root.add_child(wire)
	_snap_base_to_ground(root)
	return root


static func build_desert_shrub(seed: int = 0) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = "desert_shrub"
	var yucca_material: StandardMaterial3D = _yucca_material()
	var blade_count: int = 12
	for blade_index in range(blade_count):
		var yaw: float = TAU * float(blade_index) / float(blade_count) + _unit(seed, blade_index) * 0.12
		var direction: Vector3 = Vector3(cos(yaw), 0.0, sin(yaw))
		var side: Vector3 = Vector3(-direction.z, 0.0, direction.x)
		var length: float = 0.14 + _unit(seed, 30 + blade_index) * 0.08
		var lift: float = 0.06 + _unit(seed, 50 + blade_index) * 0.08
		var base_center: Vector3 = direction * 0.012
		var tip: Vector3 = direction * length + Vector3(0.0, lift, 0.0)
		var blade: MeshInstance3D = _mesh_instance("blade_" + str(blade_index), _triangle_mesh("desert_shrub_blade_" + str(seed) + "_" + str(blade_index), base_center - side * 0.012, base_center + side * 0.012, tip), yucca_material)
		root.add_child(blade)
	_add_box(root, "bloom_stalk", Vector3(0.012, 0.20, 0.012), Vector3(0.0, 0.10, 0.0), yucca_material)
	_add_box(root, "bloom", Vector3(0.040, 0.050, 0.040), Vector3(0.0, 0.215, 0.0), _bloom_material())
	_snap_base_to_ground(root)
	return root


static func _add_box(parent: Node3D, node_name: String, size: Vector3, position: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.resource_name = "desert_prop_" + node_name + "_mesh"
	mesh.size = size
	mesh.material = material
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.position = position
	parent.add_child(instance)
	return instance


static func _add_prong(parent: Node3D, node_name: String, from_position: Vector3, to_position: Vector3, radius: float, material: StandardMaterial3D) -> void:
	var delta: Vector3 = to_position - from_position
	var instance: MeshInstance3D = _mesh_instance(node_name, _prism_x_mesh("desert_prop_" + node_name + "_mesh", delta.length(), radius, 6), material)
	parent.add_child(instance)
	var center: Vector3 = (from_position + to_position) * 0.5
	instance.look_at_from_position(center, center + delta.normalized(), Vector3.UP)
	instance.rotate_y(PI * 0.5)


static func _mesh_instance(node_name: String, mesh: ArrayMesh, material: StandardMaterial3D) -> MeshInstance3D:
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	if mesh.get_surface_count() > 0:
		mesh.surface_set_material(0, material)
	return instance


static func _prism_x_mesh(mesh_name: String, length: float, radius: float, side_count: int) -> ArrayMesh:
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var indices: PackedInt32Array = PackedInt32Array()
	for side_index in range(side_count):
		var a0: float = TAU * float(side_index) / float(side_count)
		var a1: float = TAU * float(side_index + 1) / float(side_count)
		var y0: float = cos(a0) * radius
		var z0: float = sin(a0) * radius
		var y1: float = cos(a1) * radius
		var z1: float = sin(a1) * radius
		_append_quad(vertices, normals, uvs, indices, Vector3(-length * 0.5, y0, z0), Vector3(length * 0.5, y0, z0), Vector3(length * 0.5, y1, z1), Vector3(-length * 0.5, y1, z1))
	_append_cap(vertices, normals, uvs, indices, -length * 0.5, radius, side_count, -1.0)
	_append_cap(vertices, normals, uvs, indices, length * 0.5, radius, side_count, 1.0)
	return _arrays_to_mesh(mesh_name, vertices, normals, uvs, indices)


static func _faceted_stone_mesh(mesh_name: String, size: Vector3, seed: int) -> ArrayMesh:
	var sx: float = size.x * 0.5
	var sy: float = size.y * 0.5
	var sz: float = size.z * 0.5
	var points: Array[Vector3] = [
		Vector3(0.0, sy, 0.0),
		Vector3(0.0, -sy, 0.0),
		Vector3(-sx * (0.92 + _unit(seed, 1) * 0.18), 0.0, 0.0),
		Vector3(sx * (0.92 + _unit(seed, 2) * 0.18), 0.0, 0.0),
		Vector3(0.0, 0.0, -sz * (0.92 + _unit(seed, 3) * 0.18)),
		Vector3(0.0, 0.0, sz * (0.92 + _unit(seed, 4) * 0.18)),
		Vector3(-sx * 0.55, sy * 0.20, -sz * 0.62),
		Vector3(sx * 0.58, sy * 0.18, -sz * 0.55),
		Vector3(sx * 0.52, sy * 0.22, sz * 0.65),
		Vector3(-sx * 0.60, sy * 0.15, sz * 0.58),
	]
	var faces: Array[PackedInt32Array] = [
		PackedInt32Array([0, 6, 7]), PackedInt32Array([0, 7, 8]), PackedInt32Array([0, 8, 9]), PackedInt32Array([0, 9, 6]),
		PackedInt32Array([6, 4, 7]), PackedInt32Array([7, 4, 3]), PackedInt32Array([7, 3, 8]), PackedInt32Array([8, 3, 5]),
		PackedInt32Array([8, 5, 9]), PackedInt32Array([9, 5, 2]), PackedInt32Array([9, 2, 6]), PackedInt32Array([6, 2, 4]),
		PackedInt32Array([1, 7, 4]), PackedInt32Array([1, 3, 7]), PackedInt32Array([1, 8, 3]), PackedInt32Array([1, 5, 8]),
		PackedInt32Array([1, 9, 5]), PackedInt32Array([1, 2, 9]), PackedInt32Array([1, 6, 2]), PackedInt32Array([1, 4, 6])
	]
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var indices: PackedInt32Array = PackedInt32Array()
	for face in faces:
		_append_triangle(vertices, normals, uvs, indices, points[face[0]], points[face[1]], points[face[2]])
	return _arrays_to_mesh(mesh_name, vertices, normals, uvs, indices)


static func _triangle_mesh(mesh_name: String, a: Vector3, b: Vector3, c: Vector3) -> ArrayMesh:
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var indices: PackedInt32Array = PackedInt32Array()
	_append_triangle(vertices, normals, uvs, indices, a, c, b)
	return _arrays_to_mesh(mesh_name, vertices, normals, uvs, indices)


static func _append_quad(vertices: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, indices: PackedInt32Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_append_triangle(vertices, normals, uvs, indices, a, b, c)
	_append_triangle(vertices, normals, uvs, indices, a, c, d)


static func _append_triangle(vertices: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, indices: PackedInt32Array, a: Vector3, b: Vector3, c: Vector3) -> void:
	var normal: Vector3 = (b - a).cross(c - a).normalized()
	if normal.length() <= 0.0:
		normal = Vector3.UP
	var vertex_start: int = vertices.size()
	vertices.append(a)
	vertices.append(b)
	vertices.append(c)
	normals.append(normal)
	normals.append(normal)
	normals.append(normal)
	uvs.append(Vector2.ZERO)
	uvs.append(Vector2.RIGHT)
	uvs.append(Vector2.UP)
	indices.append(vertex_start)
	indices.append(vertex_start + 1)
	indices.append(vertex_start + 2)


static func _append_cap(vertices: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, indices: PackedInt32Array, x: float, radius: float, side_count: int, normal_x: float) -> void:
	for side_index in range(side_count):
		var a0: float = TAU * float(side_index) / float(side_count)
		var a1: float = TAU * float(side_index + 1) / float(side_count)
		var center: Vector3 = Vector3(x, 0.0, 0.0)
		var b: Vector3 = Vector3(x, cos(a0) * radius, sin(a0) * radius)
		var c: Vector3 = Vector3(x, cos(a1) * radius, sin(a1) * radius)
		if normal_x < 0.0:
			_append_triangle(vertices, normals, uvs, indices, center, c, b)
		else:
			_append_triangle(vertices, normals, uvs, indices, center, b, c)


static func _arrays_to_mesh(mesh_name: String, vertices: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, indices: PackedInt32Array) -> ArrayMesh:
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.resource_name = mesh_name
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _make_material(material_name: String, color: Color, roughness: float) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.resource_name = material_name
	material.albedo_color = color
	material.roughness = roughness
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return material


static func _snap_base_to_ground(root: Node3D) -> void:
	var min_y: float = 0.0
	var has_bounds: bool = false
	for child in root.get_children():
		var mesh_instance: MeshInstance3D = child as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var transformed_aabb: AABB = mesh_instance.transform * mesh_instance.mesh.get_aabb()
		if not has_bounds:
			min_y = transformed_aabb.position.y
			has_bounds = true
		else:
			min_y = minf(min_y, transformed_aabb.position.y)
	if not has_bounds or absf(min_y) <= 0.0001:
		return
	for child in root.get_children():
		var child_3d: Node3D = child as Node3D
		if child_3d == null:
			continue
		child_3d.position.y -= min_y


static func _wood_material() -> StandardMaterial3D:
	return _make_material("desert_prop_weathered_wood", Color(0.55, 0.36, 0.18), 0.94)


static func _dark_wood_material() -> StandardMaterial3D:
	return _make_material("desert_prop_dark_wood_cut", Color(0.28, 0.18, 0.10), 0.96)


static func _sandstone_material() -> StandardMaterial3D:
	return _make_material("desert_prop_sandstone", Color(0.68, 0.45, 0.29), 0.92)


static func _bleached_wood_material() -> StandardMaterial3D:
	return _make_material("desert_prop_bleached_wood", Color(0.70, 0.67, 0.59), 0.98)


static func _yucca_material() -> StandardMaterial3D:
	return _make_material("desert_prop_muted_yucca", Color(0.36, 0.43, 0.28), 0.88)


static func _bloom_material() -> StandardMaterial3D:
	return _make_material("desert_prop_yucca_bloom", Color(0.86, 0.78, 0.55), 0.82)


static func _unit(seed: int, salt: int) -> float:
	var n: int = seed * 1103515245 + salt * 12345 + 67890
	n = ((n >> 16) ^ n) & 0x7fffffff
	return float(n % 10000) / 9999.0
