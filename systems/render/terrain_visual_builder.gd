class_name TerrainVisualBuilder
extends RefCounted

const HeightmeshScene: PackedScene = preload("res://assets/models/terrain/cedar_hollow_heightmesh.glb")
const SurfaceVisualCatalogResource: Resource = preload("res://data/surface_visuals/cedar_hollow_surface_visuals.tres")
const DETAIL_MASK_TEXTURE_PATH: String = "res://assets/textures/surface_visuals/generated/terrain_detail_mask.png"
const GENERATED_SURFACE_TEXTURE_DIR: String = "res://assets/textures/surface_visuals/generated/"
const TEXTURE_SOURCE_PATH_META: StringName = &"trailhead_source_path"
const HEIGHTMESH_NAME: String = "cedar_hollow_heightmesh"
const TERRAIN_MATERIAL_PREFIX: String = "terrain_mat_"
const WET_DIFFUSE_MULTIPLIER: float = 0.2
const WET_ROUGHNESS: float = 0.12
const WET_CLEARCOAT: float = 0.58
const WET_CLEARCOAT_ROUGHNESS: float = 0.08


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
	var wetness: float = clampf(float(visual_def.get("wetness")), 0.0, 1.0)
	var base_albedo_color: Color = visual_def.get("albedo_color")
	material.resource_name = "terrain_visual_" + String(visual_id)
	material.albedo_color = _wet_albedo_color(base_albedo_color, wetness)
	material.roughness = _wet_roughness(float(visual_def.get("roughness")), wetness)
	material.metallic = 0.0
	material.texture_repeat = true
	material.normal_scale = float(visual_def.get("normal_scale"))
	_apply_uv_mapping(material, visual_def)
	_apply_wetness(material, wetness)
	_apply_texture_paths(material, visual_def)
	return material


static func _apply_uv_mapping(material: StandardMaterial3D, visual_def: Resource) -> void:
	var texture_uv_scale: Vector2 = visual_def.get("texture_uv_scale")
	material.uv1_scale = Vector3(texture_uv_scale.x, texture_uv_scale.y, 1.0)
	var detail_uv_scale: Vector2 = visual_def.get("detail_uv_scale")
	material.uv2_scale = Vector3(detail_uv_scale.x, detail_uv_scale.y, 1.0)
	var triplanar: bool = bool(visual_def.get("triplanar"))
	material.uv1_triplanar = triplanar
	material.uv1_world_triplanar = triplanar
	material.uv2_triplanar = triplanar
	material.uv2_world_triplanar = triplanar


static func _apply_texture_paths(material: StandardMaterial3D, visual_def: Resource) -> void:
	var albedo_texture_path: String = visual_def.get("albedo_texture_path")
	if not albedo_texture_path.is_empty():
		var albedo_texture: Texture2D = _load_texture(albedo_texture_path)
		if albedo_texture != null:
			material.albedo_texture = albedo_texture
	var normal_texture_path: String = visual_def.get("normal_texture_path")
	if not normal_texture_path.is_empty():
		var normal_texture: Texture2D = _load_texture(normal_texture_path)
		if normal_texture != null:
			material.normal_enabled = true
			material.normal_texture = normal_texture
	var detail_albedo_texture_path: String = visual_def.get("detail_albedo_texture_path")
	var detail_albedo_texture: Texture2D = _load_texture(detail_albedo_texture_path)
	var detail_normal_texture_path: String = visual_def.get("detail_normal_texture_path")
	var detail_normal_texture: Texture2D = _load_texture(detail_normal_texture_path)
	if detail_albedo_texture != null or detail_normal_texture != null:
		var detail_mask_texture: Texture2D = _load_texture(DETAIL_MASK_TEXTURE_PATH)
		if detail_mask_texture == null:
			push_error("Terrain detail mapping skipped because the detail mask could not load: " + DETAIL_MASK_TEXTURE_PATH)
			return
		material.detail_enabled = true
		material.detail_mask = detail_mask_texture
		material.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MUL
		material.detail_uv_layer = BaseMaterial3D.DETAIL_UV_2
		if detail_albedo_texture != null:
			material.detail_albedo = detail_albedo_texture
		if detail_normal_texture != null:
			material.detail_normal = detail_normal_texture


static func _load_texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if path.begins_with(GENERATED_SURFACE_TEXTURE_DIR):
		return _load_source_image_texture(path)
	var texture: Texture2D = load(path) as Texture2D
	if texture != null:
		return texture
	return _load_source_image_texture(path)


static func _load_source_image_texture(path: String) -> Texture2D:
	var image: Image = Image.load_from_file(ProjectSettings.globalize_path(path))
	if image == null or image.is_empty():
		return null
	var image_texture: ImageTexture = ImageTexture.create_from_image(image)
	image_texture.take_over_path(path)
	image_texture.set_meta(TEXTURE_SOURCE_PATH_META, path)
	return image_texture


static func _wet_albedo_color(base_color: Color, wetness: float) -> Color:
	var multiplier: float = 1.0 + (WET_DIFFUSE_MULTIPLIER - 1.0) * wetness
	return Color(base_color.r * multiplier, base_color.g * multiplier, base_color.b * multiplier, base_color.a)


static func _wet_roughness(base_roughness: float, wetness: float) -> float:
	return base_roughness + (WET_ROUGHNESS - base_roughness) * wetness


static func _apply_wetness(material: StandardMaterial3D, wetness: float) -> void:
	if wetness <= 0.0:
		material.clearcoat_enabled = false
		return
	material.clearcoat_enabled = true
	material.clearcoat = WET_CLEARCOAT * wetness
	material.clearcoat_roughness = WET_CLEARCOAT_ROUGHNESS
