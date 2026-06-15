class_name GroundDetailVisualBuilder
extends RefCounted

const EXPECTED_MUD_PATCHES: int = 8
const EXPECTED_TIRE_TRACK_PAIRS: int = 3
const EXPECTED_GRAVEL_SPECKLES: int = 14
const EXPECTED_LEAF_LITTER: int = 12
const EXPECTED_ROOT_RIDGES: int = 5
const EXPECTED_PUDDLE_SHEENS: int = 4
const EXPECTED_WET_GLINTS: int = 6
const DECAL_Y: float = 0.012
const LOW_DETAIL_Y: float = 0.018


static func build_cedar_hollow(parent: Node3D) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = "GroundDetailVisuals"
	parent.add_child(root)
	_add_mud_patches(root)
	_add_tire_tracks(root)
	_add_gravel_speckles(root)
	_add_leaf_litter(root)
	_add_root_ridges(root)
	_add_puddle_sheens(root)
	_add_wet_glints(root)
	return root


static func _add_mud_patches(parent: Node3D) -> void:
	var positions: Array[Vector3] = [
		Vector3(2.16, DECAL_Y, -4.72),
		Vector3(2.76, DECAL_Y, -4.98),
		Vector3(3.26, DECAL_Y, -5.38),
		Vector3(2.42, DECAL_Y, -5.72),
		Vector3(3.58, DECAL_Y, -4.42),
		Vector3(4.08, DECAL_Y, -5.18),
		Vector3(3.42, DECAL_Y, -6.16),
		Vector3(4.34, DECAL_Y, -6.52)
	]
	var sizes: Array[Vector2] = [
		Vector2(0.52, 0.28),
		Vector2(0.42, 0.34),
		Vector2(0.58, 0.38),
		Vector2(0.46, 0.30),
		Vector2(0.50, 0.26),
		Vector2(0.36, 0.32),
		Vector2(0.44, 0.34),
		Vector2(0.38, 0.28)
	]
	for i in range(EXPECTED_MUD_PATCHES):
		var color: Color = Color(0.13 + float(i % 3) * 0.018, 0.085, 0.045, 0.56)
		_add_blob(parent, "mud_patch_" + str(i + 1), positions[i], sizes[i], float(i) * 31.0, color, 0.94)


static func _add_tire_tracks(parent: Node3D) -> void:
	var centers: Array[Vector3] = [
		Vector3(2.35, DECAL_Y + 0.002, -5.12),
		Vector3(3.05, DECAL_Y + 0.002, -5.68),
		Vector3(3.82, DECAL_Y + 0.002, -4.46)
	]
	var yaws: Array[float] = [-12.0, 18.0, 5.0]
	var lengths: Array[float] = [0.74, 0.66, 0.70]
	for i in range(EXPECTED_TIRE_TRACK_PAIRS):
		var basis: Basis = Basis(Vector3.UP, deg_to_rad(yaws[i]))
		var side_offset: Vector3 = basis.x.normalized() * 0.065
		var size: Vector2 = Vector2(0.036, lengths[i])
		var color: Color = Color(0.07, 0.045, 0.028, 0.62)
		_add_plane(parent, "tire_track_" + str(i + 1) + "_left", centers[i] - side_offset, size, yaws[i], color, 0.98)
		_add_plane(parent, "tire_track_" + str(i + 1) + "_right", centers[i] + side_offset, size, yaws[i], color, 0.98)


static func _add_gravel_speckles(parent: Node3D) -> void:
	var positions: Array[Vector3] = [
		Vector3(-0.82, LOW_DETAIL_Y, 1.16),
		Vector3(-0.42, LOW_DETAIL_Y, 0.94),
		Vector3(0.08, LOW_DETAIL_Y, 1.25),
		Vector3(0.55, LOW_DETAIL_Y, 0.78),
		Vector3(0.82, LOW_DETAIL_Y, 1.08),
		Vector3(-0.68, LOW_DETAIL_Y, 0.36),
		Vector3(-0.18, LOW_DETAIL_Y, 0.22),
		Vector3(0.36, LOW_DETAIL_Y, 0.38),
		Vector3(0.78, LOW_DETAIL_Y, 0.04),
		Vector3(-0.95, LOW_DETAIL_Y, 0.74),
		Vector3(-0.22, LOW_DETAIL_Y, 0.66),
		Vector3(0.24, LOW_DETAIL_Y, 1.02),
		Vector3(0.96, LOW_DETAIL_Y, 0.46),
		Vector3(-0.52, LOW_DETAIL_Y, 1.32)
	]
	for i in range(EXPECTED_GRAVEL_SPECKLES):
		var width: float = 0.035 + float(i % 3) * 0.010
		var depth: float = 0.024 + float((i + 1) % 3) * 0.008
		var height: float = 0.006 + float(i % 2) * 0.003
		var color_step: float = float(i % 4) * 0.025
		var color: Color = Color(0.36 + color_step, 0.32 + color_step, 0.25 + color_step, 1.0)
		_add_box(parent, "gravel_speckle_" + str(i + 1), positions[i], Vector3(width, height, depth), float(i) * 27.0, color, 0.86)


static func _add_leaf_litter(parent: Node3D) -> void:
	var positions: Array[Vector3] = [
		Vector3(-0.82, DECAL_Y + 0.003, -1.72),
		Vector3(-0.42, DECAL_Y + 0.003, -2.38),
		Vector3(0.38, DECAL_Y + 0.003, -2.88),
		Vector3(-0.26, DECAL_Y + 0.003, -3.55),
		Vector3(0.72, DECAL_Y + 0.003, -4.24),
		Vector3(-0.62, DECAL_Y + 0.003, -4.86),
		Vector3(-0.42, DECAL_Y + 0.003, -5.32),
		Vector3(0.28, DECAL_Y + 0.003, -5.82),
		Vector3(0.82, DECAL_Y + 0.003, -5.06),
		Vector3(-1.08, DECAL_Y + 0.003, -3.08),
		Vector3(1.12, DECAL_Y + 0.003, -5.42),
		Vector3(-0.12, DECAL_Y + 0.003, -6.12)
	]
	for i in range(EXPECTED_LEAF_LITTER):
		var size: Vector2 = Vector2(0.10 + float(i % 2) * 0.025, 0.035 + float(i % 3) * 0.008)
		var color: Color = Color(0.42 + float(i % 3) * 0.05, 0.25 + float(i % 2) * 0.035, 0.10, 0.72)
		_add_plane(parent, "leaf_litter_" + str(i + 1), positions[i], size, float(i) * 38.0, color, 0.9)


static func _add_root_ridges(parent: Node3D) -> void:
	var positions: Array[Vector3] = [
		Vector3(-0.55, DECAL_Y + 0.004, -3.42),
		Vector3(0.62, DECAL_Y + 0.004, -4.92),
		Vector3(-0.22, DECAL_Y + 0.004, -5.08),
		Vector3(1.00, DECAL_Y + 0.004, -5.72),
		Vector3(-0.92, DECAL_Y + 0.004, -6.02)
	]
	var yaws: Array[float] = [22.0, -18.0, 36.0, -42.0, 12.0]
	for i in range(EXPECTED_ROOT_RIDGES):
		var size: Vector2 = Vector2(0.28 + float(i % 2) * 0.08, 0.028 + float(i % 3) * 0.006)
		var color: Color = Color(0.19 + float(i % 3) * 0.020, 0.105, 0.050, 0.68)
		_add_plane(parent, "root_ridge_" + str(i + 1), positions[i], size, yaws[i], color, 0.88)


static func _add_puddle_sheens(parent: Node3D) -> void:
	var positions: Array[Vector3] = [
		Vector3(2.85, DECAL_Y + 0.004, -5.10),
		Vector3(3.72, DECAL_Y + 0.004, -4.82),
		Vector3(3.16, DECAL_Y + 0.004, -6.02),
		Vector3(4.42, DECAL_Y + 0.004, -6.88)
	]
	var yaws: Array[float] = [-8.0, 18.0, -26.0, 11.0]
	for i in range(EXPECTED_PUDDLE_SHEENS):
		var size: Vector2 = Vector2(0.34 + float(i % 2) * 0.10, 0.16 + float(i % 3) * 0.035)
		var color: Color = Color(0.15, 0.12, 0.085, 0.34)
		_add_blob(parent, "puddle_sheen_" + str(i + 1), positions[i], size, yaws[i], color, 0.22)


static func _add_wet_glints(parent: Node3D) -> void:
	var positions: Array[Vector3] = [
		Vector3(3.58, DECAL_Y + 0.004, -7.08),
		Vector3(3.94, DECAL_Y + 0.004, -7.42),
		Vector3(4.24, DECAL_Y + 0.004, -7.18),
		Vector3(4.54, DECAL_Y + 0.004, -7.54),
		Vector3(4.88, DECAL_Y + 0.004, -7.28),
		Vector3(4.28, DECAL_Y + 0.004, -6.82)
	]
	for i in range(EXPECTED_WET_GLINTS):
		var size: Vector2 = Vector2(0.20 + float(i % 2) * 0.05, 0.030 + float(i % 3) * 0.012)
		var color: Color = Color(0.68, 0.82, 0.86, 0.38)
		_add_plane(parent, "wet_glint_" + str(i + 1), positions[i], size, 18.0 + float(i) * 29.0, color, 0.18)


static func _add_plane(parent: Node3D, node_name: String, position: Vector3, size: Vector2, yaw_degrees: float, color: Color, roughness: float) -> MeshInstance3D:
	var mesh: PlaneMesh = PlaneMesh.new()
	mesh.size = size
	return _add_mesh_instance(parent, node_name, mesh, position, yaw_degrees, color, roughness)


static func _add_blob(parent: Node3D, node_name: String, position: Vector3, size: Vector2, yaw_degrees: float, color: Color, roughness: float) -> MeshInstance3D:
	var outline: Array[Vector2] = [
		Vector2(0.55, 0.02),
		Vector2(0.44, 0.34),
		Vector2(0.13, 0.50),
		Vector2(-0.23, 0.43),
		Vector2(-0.51, 0.20),
		Vector2(-0.43, -0.16),
		Vector2(-0.17, -0.48),
		Vector2(0.22, -0.42),
		Vector2(0.52, -0.20)
	]
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var indices: PackedInt32Array = PackedInt32Array()
	vertices.append(Vector3.ZERO)
	normals.append(Vector3.UP)
	uvs.append(Vector2(0.5, 0.5))
	for point in outline:
		vertices.append(Vector3(point.x * size.x, 0.0, point.y * size.y))
		normals.append(Vector3.UP)
		uvs.append(Vector2(0.5 + point.x, 0.5 + point.y))
	for i in range(outline.size()):
		indices.append(0)
		indices.append(i + 1)
		indices.append((i + 1) % outline.size() + 1)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return _add_mesh_instance(parent, node_name, mesh, position, yaw_degrees, color, roughness)


static func _add_box(parent: Node3D, node_name: String, position: Vector3, size: Vector3, yaw_degrees: float, color: Color, roughness: float) -> MeshInstance3D:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	return _add_mesh_instance(parent, node_name, mesh, position, yaw_degrees, color, roughness)


static func _add_mesh_instance(parent: Node3D, node_name: String, mesh: Mesh, position: Vector3, yaw_degrees: float, color: Color, roughness: float) -> MeshInstance3D:
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.position = position
	instance.rotation_degrees = Vector3(0.0, yaw_degrees, 0.0)
	instance.material_override = _material(node_name, color, roughness)
	instance.visibility_range_end = GameConfig.vis_range_ground_detail
	parent.add_child(instance)
	return instance


static func _material(node_name: String, color: Color, roughness: float) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.resource_name = node_name + "_mat"
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = 0.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if color.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material
