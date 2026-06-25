extends Node

const TerrainVisualBuilderScript: GDScript = preload("res://systems/render/terrain_visual_builder.gd")
const SurfaceMapScript: GDScript = preload("res://systems/world/surface_map.gd")
const WaterVisualBuilderScript: GDScript = preload("res://systems/render/water_visual_builder.gd")

const OUT_ARG: String = "--out="
const ZION_REGION_ID: String = "cedar_hollow_zion"
const ZION_TERRAIN_DEF_PATH: String = "res://data/terrain/cedar_hollow_zion_terrain_def.tres"
const WATER_SHADER_PATH: String = "res://systems/render/water_visual.gdshader"
const VEHICLE_GLB_PATH: String = "res://assets/models/vehicle/rc_buggy.glb"
const SAMPLE_CELLS: Array[Vector2i] = [
	Vector2i(11, 8),
	Vector2i(20, 17),
	Vector2i(22, 51),
]
const FOLIAGE_TILE_CELL: Vector2i = Vector2i(11, 8)
const FOLIAGE_SCENE_PATHS: Array[String] = [
	"res://assets/models/foliage/cottonwood.glb",
	"res://assets/models/foliage/willow.glb",
	"res://assets/models/foliage/juniper.glb",
	"res://assets/models/foliage/yucca.glb",
]
const FOLIAGE_TEXTURE_PATHS: Array[String] = [
	"res://assets/textures/foliage/bark_willow_albedo.jpg",
	"res://assets/textures/foliage/bark_willow_normal.jpg",
	"res://assets/textures/foliage/bark_willow_arm.jpg",
	"res://assets/textures/foliage/leafset004_atlas_rgba.png",
]
const FOLIAGE_SPECIES: Array[StringName] = [
	&"cottonwood",
	&"willow",
	&"juniper",
	&"yucca",
]
const VEHICLE_TEXTURE_PATHS: Array[String] = [
	"res://assets/textures/vehicle/residue/mud_body_mask.png",
	"res://assets/textures/vehicle/residue/dust_body_mask.png",
	"res://assets/textures/vehicle/residue/wetness_body_mask.png",
	"res://assets/textures/vehicle/residue/mud_tire_mask.png",
	"res://assets/textures/vehicle/residue/dust_tire_mask.png",
	"res://assets/textures/vehicle/residue/wetness_tire_mask.png",
]
const ZION_SAMPLE_SURFACE_IDS: Array[StringName] = [
	&"wet_stone",
	&"packed_gravel",
	&"packed_dirt",
	&"loose_rock",
	&"tall_grass",
	&"paved_road",
]
const ZION_SAMPLE_POINTS: Array[Vector3] = [
	Vector3(324141.825, 0.0, 4122932.509),
	Vector3(323978.825, 0.0, 4122217.509),
	Vector3(324860.825, 0.0, 4120711.509),
	Vector3(325231.825, 0.0, 4120501.509),
	Vector3(325411.825, 0.0, 4122132.509),
	Vector3(323846.325, 0.0, 4118527.009),
]

var _out_path: String = "user://export_parity_smoke.json"
var _result: Dictionary[String, Variant] = {
	"ok": false,
	"classes": {},
}


func _ready() -> void:
	_out_path = _read_out_arg()
	call_deferred("_run")


func _run() -> void:
	_record_class("terrain_tiles", _check_terrain_tiles())
	_record_class("heightmap_bin", _check_heightmap_bins())
	_record_class("surface_map_png", _check_surface_map_png())
	_record_class("foliage", _check_foliage_assets())
	_record_class("water_vehicle", _check_water_vehicle_assets())
	_result["ok"] = _all_classes_ok()
	_write_result()
	if bool(_result["ok"]):
		print("PASS export_parity_smoke: all packed asset classes resolved")
		get_tree().quit(0)
		return
	print("FAIL export_parity_smoke: one or more packed asset classes failed")
	get_tree().quit(1)


func _check_terrain_tiles() -> Dictionary[String, Variant]:
	var errors: Array[String] = []
	var details: Array[String] = []
	var cells: Array[Vector2i] = TerrainVisualBuilderScript.region_tile_cells(ZION_REGION_ID)
	if cells.is_empty():
		errors.append("region manifest returned no cells for " + ZION_REGION_ID)
	if not TerrainVisualBuilderScript.prewarm_surface_index_pipeline():
		errors.append("surface-index texture arrays failed to prewarm from packed resources")
	for cell in SAMPLE_CELLS:
		if not cells.has(cell):
			errors.append("sample cell missing from manifest: " + str(cell))
			continue
		var tile_data: Variant = TerrainVisualBuilderScript._load_region_tile(ZION_REGION_ID, cell)
		if tile_data == null:
			errors.append("tile data failed to load: " + str(cell))
			continue
		var surface_image: Image = TerrainVisualBuilderScript._load_source_image(String(tile_data.surface_id_path), true)
		if surface_image == null or surface_image.is_empty():
			errors.append("surface_id failed through _load_source_image(..., true): " + String(tile_data.surface_id_path))
		var visual_data: Variant = TerrainVisualBuilderScript.build_region_visual_tile_data(
			ZION_REGION_ID,
			cell,
			TerrainVisualBuilderScript.REGION_DETAIL_SAMPLE_STEP
		)
		if visual_data == null or not bool(visual_data.ok):
			var message: String = "<null>"
			if visual_data != null:
				message = String(visual_data.message)
			errors.append("visual tile build failed for " + str(cell) + ": " + message)
			continue
		if visual_data.mesh == null:
			errors.append("visual tile mesh is null for " + str(cell))
			continue
		if visual_data.mesh.get_surface_count() <= 0:
			errors.append("visual tile mesh has no surfaces for " + str(cell))
		TerrainVisualBuilderScript.apply_region_mesh_materials(visual_data.mesh, visual_data.mesh_data)
		if not _mesh_has_surface_id_texture(visual_data.mesh):
			errors.append("visual tile material missing packed surface_id texture for " + str(cell))
		details.append("tile " + str(cell) + " surface_id=" + String(tile_data.surface_id_path))
	return _class_result(errors, details)


func _check_heightmap_bins() -> Dictionary[String, Variant]:
	var errors: Array[String] = []
	var details: Array[String] = []
	for cell in SAMPLE_CELLS:
		var tile_data: Variant = TerrainVisualBuilderScript._load_region_tile(ZION_REGION_ID, cell)
		if tile_data == null:
			errors.append("tile data failed to load before heightmap assertion: " + str(cell))
			continue
		var heightmap_path: String = String(tile_data.heightmap_path)
		var height_bytes: PackedByteArray = FileAccess.get_file_as_bytes(heightmap_path)
		var expected_bytes: int = int(tile_data.width) * int(tile_data.depth) * TerrainVisualBuilderScript.HEIGHTMAP_FLOAT_BYTE_SIZE
		if height_bytes.size() != expected_bytes:
			errors.append(heightmap_path + " byte count " + str(height_bytes.size()) + " != " + str(expected_bytes))
			continue
		details.append(heightmap_path + " bytes=" + str(height_bytes.size()))
	return _class_result(errors, details)


func _check_surface_map_png() -> Dictionary[String, Variant]:
	var errors: Array[String] = []
	var details: Array[String] = []
	var surface_map: Node = SurfaceMapScript.new()
	surface_map.name = "ExportParitySurfaceMap"
	add_child(surface_map)
	if not bool(surface_map.call("configure_terrain_def", ZION_TERRAIN_DEF_PATH)):
		errors.append("SurfaceMap failed to configure " + ZION_TERRAIN_DEF_PATH)
	elif not bool(surface_map.call("is_terrain_sampler_ready")):
		errors.append("SurfaceMap terrain sampler is not ready after configure")
	else:
		for i in range(ZION_SAMPLE_POINTS.size()):
			var expected_surface_id: StringName = ZION_SAMPLE_SURFACE_IDS[i]
			var point: Vector3 = ZION_SAMPLE_POINTS[i]
			var observed_surface_id: StringName = surface_map.call("surface_id_at_world_position", point, &"")
			if observed_surface_id != expected_surface_id:
				errors.append("surface sample " + str(i + 1) + " expected " + String(expected_surface_id) + ", got " + String(observed_surface_id))
			else:
				details.append(String(expected_surface_id) + " @ " + str(point))
	remove_child(surface_map)
	surface_map.free()
	return _class_result(errors, details)


func _check_foliage_assets() -> Dictionary[String, Variant]:
	var errors: Array[String] = []
	var details: Array[String] = []
	for path in FOLIAGE_TEXTURE_PATHS:
		_require_texture(path, "foliage texture", errors, details)
	for path in FOLIAGE_SCENE_PATHS:
		_require_scene_with_mesh(path, "foliage GLB", errors, details)
	for species_id in FOLIAGE_SPECIES:
		for lod_index in range(2):
			var mesh: Mesh = TerrainVisualBuilderScript._region_foliage_mesh_for_lod_species(lod_index, species_id)
			if mesh == null:
				errors.append("foliage builder returned null mesh for " + String(species_id) + " lod" + str(lod_index))
				continue
			if mesh.get_surface_count() <= 0:
				errors.append("foliage builder mesh has no surfaces for " + String(species_id) + " lod" + str(lod_index))
			if (species_id == &"cottonwood" or species_id == &"willow") and not _mesh_has_albedo_texture(mesh):
				errors.append("riparian foliage mesh missing applied leaf/bark texture for " + String(species_id) + " lod" + str(lod_index))
			details.append("builder mesh " + String(species_id) + " lod" + str(lod_index) + " surfaces=" + str(mesh.get_surface_count()))
	var foliage_tile_data: Variant = TerrainVisualBuilderScript.build_region_foliage_tile_data(ZION_REGION_ID, FOLIAGE_TILE_CELL)
	if foliage_tile_data == null or not bool(foliage_tile_data.ok):
		var message: String = "<null>"
		if foliage_tile_data != null:
			message = String(foliage_tile_data.message)
		errors.append("foliage tile build failed for " + str(FOLIAGE_TILE_CELL) + ": " + message)
	else:
		var instance_count: int = _foliage_instance_count(foliage_tile_data)
		if instance_count <= 0:
			errors.append("foliage tile has no accepted instances: " + str(FOLIAGE_TILE_CELL))
		var tile_root: Node3D = TerrainVisualBuilderScript.region_foliage_tile_root_from_data(self, foliage_tile_data, false) as Node3D
		if tile_root == null:
			errors.append("foliage tile root failed to materialize: " + str(FOLIAGE_TILE_CELL))
		else:
			var multimesh_count: int = _count_multimesh_instances(tile_root)
			if multimesh_count <= 0:
				errors.append("foliage tile root has no MultiMeshInstance3D nodes: " + str(FOLIAGE_TILE_CELL))
			details.append("foliage tile " + str(FOLIAGE_TILE_CELL) + " instances=" + str(instance_count) + " multimeshes=" + str(multimesh_count))
			tile_root.free()
	return _class_result(errors, details)


func _check_water_vehicle_assets() -> Dictionary[String, Variant]:
	var errors: Array[String] = []
	var details: Array[String] = []
	var water_shader: Shader = load(WATER_SHADER_PATH) as Shader
	if water_shader == null:
		errors.append("water shader failed to load: " + WATER_SHADER_PATH)
	else:
		details.append("water shader " + WATER_SHADER_PATH)
	var water_root: Node3D = Node3D.new()
	water_root.name = "ExportParityWaterRoot"
	add_child(water_root)
	WaterVisualBuilderScript.build_zion_virgin_river(water_root)
	var water_meshes: int = _count_mesh_instances(water_root)
	if water_meshes <= 0:
		errors.append("WaterVisualBuilder built no MeshInstance3D nodes")
	else:
		details.append("water meshes=" + str(water_meshes))
	remove_child(water_root)
	water_root.free()
	_require_scene_with_mesh(VEHICLE_GLB_PATH, "vehicle GLB", errors, details)
	for path in VEHICLE_TEXTURE_PATHS:
		_require_texture(path, "vehicle residue texture", errors, details)
	return _class_result(errors, details)


func _require_texture(path: String, label: String, errors: Array[String], details: Array[String]) -> void:
	var texture: Texture2D = load(path) as Texture2D
	if texture == null:
		errors.append(label + " failed to load through resource system: " + path)
		return
	var image: Image = texture.get_image()
	if image == null or image.is_empty():
		errors.append(label + " loaded but returned an empty image: " + path)
		return
	details.append(label + " " + path + " " + str(texture.get_width()) + "x" + str(texture.get_height()))


func _require_scene_with_mesh(path: String, label: String, errors: Array[String], details: Array[String]) -> void:
	var scene: PackedScene = load(path) as PackedScene
	if scene == null:
		errors.append(label + " failed to load through resource system: " + path)
		return
	var root: Node = scene.instantiate()
	if root == null:
		errors.append(label + " failed to instantiate: " + path)
		return
	var mesh_count: int = _count_mesh_instances(root)
	if mesh_count <= 0:
		errors.append(label + " instantiated with no MeshInstance3D nodes: " + path)
	else:
		details.append(label + " " + path + " meshes=" + str(mesh_count))
	root.free()


func _mesh_has_surface_id_texture(mesh: Mesh) -> bool:
	if mesh == null:
		return false
	for surface_index in range(mesh.get_surface_count()):
		var material: ShaderMaterial = mesh.surface_get_material(surface_index) as ShaderMaterial
		if material == null:
			continue
		var surface_texture: Texture2D = material.get_shader_parameter(TerrainVisualBuilderScript.SURFACE_ID_TEXTURE_UNIFORM) as Texture2D
		if surface_texture != null:
			return true
	return false


func _mesh_has_albedo_texture(mesh: Mesh) -> bool:
	if mesh == null:
		return false
	for surface_index in range(mesh.get_surface_count()):
		var material: StandardMaterial3D = mesh.surface_get_material(surface_index) as StandardMaterial3D
		if material != null and material.albedo_texture != null:
			return true
	return false


func _foliage_instance_count(foliage_tile_data: Variant) -> int:
	var count: int = 0
	for cell_data: Variant in foliage_tile_data.cells:
		for species_data: Variant in cell_data.species:
			count += species_data.transforms.size()
	return count


func _count_mesh_instances(parent: Node) -> int:
	var count: int = 0
	var mesh_instance: MeshInstance3D = parent as MeshInstance3D
	if mesh_instance != null and mesh_instance.mesh != null:
		count += 1
	for child in parent.get_children():
		count += _count_mesh_instances(child)
	return count


func _count_multimesh_instances(parent: Node) -> int:
	var count: int = 0
	var multimesh_instance: MultiMeshInstance3D = parent as MultiMeshInstance3D
	if multimesh_instance != null and multimesh_instance.multimesh != null and multimesh_instance.multimesh.mesh != null:
		count += 1
	for child in parent.get_children():
		count += _count_multimesh_instances(child)
	return count


func _class_result(errors: Array[String], details: Array[String]) -> Dictionary[String, Variant]:
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"details": details,
	}


func _record_class(asset_class: String, class_result: Dictionary[String, Variant]) -> void:
	var classes: Dictionary[String, Variant] = _result["classes"] as Dictionary[String, Variant]
	classes[asset_class] = class_result
	_result["classes"] = classes
	if bool(class_result["ok"]):
		var details: Array[String] = class_result["details"] as Array[String]
		print("export_parity_smoke: PASS " + asset_class + " checks=" + str(details.size()))
		return
	var errors: Array[String] = class_result["errors"] as Array[String]
	print("export_parity_smoke: FAIL " + asset_class + " errors=" + str(errors.size()))
	for error in errors:
		push_error(asset_class + ": " + error)


func _all_classes_ok() -> bool:
	var classes: Dictionary[String, Variant] = _result["classes"] as Dictionary[String, Variant]
	for asset_class in classes.keys():
		var class_result: Dictionary[String, Variant] = classes[asset_class] as Dictionary[String, Variant]
		if not bool(class_result["ok"]):
			return false
	return true


func _write_result() -> void:
	var out_dir: String = _out_path.get_base_dir()
	if not out_dir.is_empty():
		var absolute_dir: String = out_dir
		if out_dir.begins_with("res://") or out_dir.begins_with("user://"):
			absolute_dir = ProjectSettings.globalize_path(out_dir)
		var dir_error: Error = DirAccess.make_dir_recursive_absolute(absolute_dir)
		if dir_error != OK:
			push_error("export_parity_smoke: failed to create output dir " + absolute_dir + " error=" + error_string(dir_error))
	var file: FileAccess = FileAccess.open(_out_path, FileAccess.WRITE)
	if file == null:
		push_error("export_parity_smoke: failed to open output file " + _out_path + " error=" + str(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify(_result, "\t") + "\n")
	file.close()


func _read_out_arg() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(OUT_ARG):
			var out_path: String = arg.substr(OUT_ARG.length())
			if not out_path.is_empty():
				return out_path
	return _out_path
