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
		var surface_id: StringName = _surface_id_for_mesh_surface(mesh, surface_index)
		if surface_id == &"":
			continue
		var visual_def: Resource = SurfaceVisualCatalogResource.call("default_visual_for_surface_id", surface_id)
		if visual_def == null:
			continue
		mesh_instance.set_surface_override_material(surface_index, _material_for_visual_def(visual_def))


static func _surface_id_for_mesh_surface(mesh: Mesh, surface_index: int) -> StringName:
	var material: Material = mesh.surface_get_material(surface_index)
	if material == null:
		return &""
	var material_name: String = material.resource_name
	if not material_name.begins_with(TERRAIN_MATERIAL_PREFIX):
		return &""
	return StringName(material_name.substr(TERRAIN_MATERIAL_PREFIX.length()))


static func _material_for_visual_def(visual_def: Resource) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	var surface_id: StringName = visual_def.get("surface_id")
	material.resource_name = "terrain_visual_" + String(surface_id)
	material.albedo_color = visual_def.get("albedo_color")
	material.roughness = float(visual_def.get("roughness"))
	material.metallic = 0.0
	return material
