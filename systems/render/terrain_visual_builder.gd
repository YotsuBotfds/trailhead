class_name TerrainVisualBuilder
extends RefCounted

const HeightmeshScene: PackedScene = preload("res://assets/models/terrain/cedar_hollow_heightmesh.glb")
const SurfaceVisualCatalogResource: Resource = preload("res://data/surface_visuals/cedar_hollow_surface_visuals.tres")
const HEIGHTMESH_NAME: String = "cedar_hollow_heightmesh"
const TERRAIN_MATERIAL_PREFIX: String = "terrain_mat_"


static func build_cedar_hollow(parent: Node3D) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = "TerrainVisuals"
	parent.add_child(root)

	var heightmesh: Node3D = HeightmeshScene.instantiate() as Node3D
	if heightmesh == null:
		return root
	heightmesh.name = HEIGHTMESH_NAME
	root.add_child(heightmesh)
	_apply_surface_visuals(heightmesh)
	return root


static func _apply_surface_visuals(parent: Node) -> void:
	var mesh_instance: MeshInstance3D = parent as MeshInstance3D
	if mesh_instance != null:
		_apply_surface_visuals_to_mesh(mesh_instance)
	for child in parent.get_children():
		_apply_surface_visuals(child)


static func _apply_surface_visuals_to_mesh(mesh_instance: MeshInstance3D) -> void:
	var mesh: Mesh = mesh_instance.mesh
	if mesh == null:
		return
	for surface_index in range(mesh.get_surface_count()):
		var material_token: StringName = _material_token_for_mesh_surface(mesh, surface_index)
		if material_token == &"":
			continue
		var visual_def: Resource = SurfaceVisualCatalogResource.call("visual_for_terrain_material_token", material_token)
		if visual_def == null:
			continue
		mesh_instance.set_surface_override_material(surface_index, _material_for_visual_def(visual_def))


static func _material_token_for_mesh_surface(mesh: Mesh, surface_index: int) -> StringName:
	var material: Material = mesh.surface_get_material(surface_index)
	if material == null:
		return &""
	var material_name: String = material.resource_name
	if not material_name.begins_with(TERRAIN_MATERIAL_PREFIX):
		return &""
	return StringName(material_name.substr(TERRAIN_MATERIAL_PREFIX.length()))


static func _material_for_visual_def(visual_def: Resource) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	var visual_id: StringName = visual_def.get("id")
	material.resource_name = "terrain_visual_" + String(visual_id)
	material.albedo_color = visual_def.get("albedo_color")
	material.roughness = float(visual_def.get("roughness"))
	material.metallic = 0.0
	var texture_uv_scale: Vector2 = visual_def.get("texture_uv_scale")
	material.uv1_scale = Vector3(texture_uv_scale.x, texture_uv_scale.y, 1.0)
	_apply_texture_paths(material, visual_def)
	return material


static func _apply_texture_paths(material: StandardMaterial3D, visual_def: Resource) -> void:
	var albedo_texture_path: String = visual_def.get("albedo_texture_path")
	if not albedo_texture_path.is_empty():
		var albedo_texture: Texture2D = load(albedo_texture_path) as Texture2D
		if albedo_texture != null:
			material.albedo_texture = albedo_texture
	var normal_texture_path: String = visual_def.get("normal_texture_path")
	if not normal_texture_path.is_empty():
		var normal_texture: Texture2D = load(normal_texture_path) as Texture2D
		if normal_texture != null:
			material.normal_enabled = true
			material.normal_texture = normal_texture
	var orm_texture_path: String = visual_def.get("orm_texture_path")
	if not orm_texture_path.is_empty():
		var orm_texture: Texture2D = load(orm_texture_path) as Texture2D
		if orm_texture != null:
			material.orm_texture = orm_texture
