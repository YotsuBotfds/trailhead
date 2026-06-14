class_name TerrainVisualBuilder
extends RefCounted

const SURFACE_TAG_MARKER: String = "__surf_"
const PATCH_PREFIX: String = "terrain_patch_"
const PATCH_LIFT: float = 0.004


static func build_cedar_hollow(parent: Node3D) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = "TerrainVisuals"
	parent.add_child(root)

	var patch_index: int = 0
	for child in parent.get_children():
		var body: StaticBody3D = child as StaticBody3D
		if body == null:
			continue
		var collision: CollisionShape3D = body.get_node_or_null("Collision") as CollisionShape3D
		if collision == null:
			continue
		var box_shape: BoxShape3D = collision.shape as BoxShape3D
		if box_shape == null:
			continue
		patch_index += 1
		_add_patch(root, body, box_shape.size, patch_index)
	return root


static func _add_patch(parent: Node3D, body: StaticBody3D, size: Vector3, patch_index: int) -> void:
	var surface_id: StringName = _surface_id_from_name(String(body.name))
	var patch: MeshInstance3D = MeshInstance3D.new()
	patch.name = PATCH_PREFIX + String.num_int64(patch_index).pad_zeros(2) + "__surf_" + String(surface_id)
	patch.transform = body.transform
	patch.mesh = _build_patch_mesh(size)
	patch.set_surface_override_material(0, _material_for_surface(surface_id))
	parent.add_child(patch)


static func _surface_id_from_name(body_name: String) -> StringName:
	var marker_index: int = body_name.find(SURFACE_TAG_MARKER)
	if marker_index < 0:
		return &"packed_dirt"
	return StringName(body_name.substr(marker_index + SURFACE_TAG_MARKER.length()))


static func _build_patch_mesh(size: Vector3) -> ArrayMesh:
	var half_x: float = size.x * 0.5
	var half_z: float = size.z * 0.5
	var top_y: float = size.y * 0.5 + PATCH_LIFT
	var vertices: PackedVector3Array = PackedVector3Array([
		Vector3(-half_x, top_y, -half_z),
		Vector3(half_x, top_y, -half_z),
		Vector3(half_x, top_y, half_z),
		Vector3(-half_x, top_y, half_z),
	])
	var normals: PackedVector3Array = PackedVector3Array([
		Vector3.UP,
		Vector3.UP,
		Vector3.UP,
		Vector3.UP,
	])
	var uvs: PackedVector2Array = PackedVector2Array([
		Vector2(0.0, 0.0),
		Vector2(size.x, 0.0),
		Vector2(size.x, size.z),
		Vector2(0.0, size.z),
	])
	var indices: PackedInt32Array = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _material_for_surface(surface_id: StringName) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = _color_for_surface(surface_id)
	material.roughness = 1.0
	material.metallic = 0.0
	return material


static func _color_for_surface(surface_id: StringName) -> Color:
	match surface_id:
		&"packed_gravel":
			return Color(0.43, 0.39, 0.32)
		&"packed_dirt":
			return Color(0.36, 0.25, 0.15)
		&"tall_grass":
			return Color(0.28, 0.39, 0.19)
		&"mud":
			return Color(0.22, 0.15, 0.10)
		&"loose_rock":
			return Color(0.33, 0.34, 0.31)
		&"wet_stone":
			return Color(0.25, 0.32, 0.34)
		&"wood_plank":
			return Color(0.42, 0.25, 0.13)
		_:
			return Color(0.34, 0.29, 0.21)
