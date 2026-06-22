extends Node

const SpikeRegionScene: PackedScene = preload("res://scenes/regions/spike_1km.tscn")
const TerrainVisualBuilderScript: GDScript = preload("res://systems/render/terrain_visual_builder.gd")
const EXPECTED_DETAIL_TILE_COUNT: int = 100
const EXPECTED_REGION_SIZE_M: float = 1000.0
const FLOAT_EPSILON: float = 0.001
const BOUNDS_EPSILON_M: float = 0.5
const TILE_INDEX_META: StringName = &"trailhead_tile_index"
const REGION_LOD_META: StringName = &"trailhead_region_lod"
const VISIBILITY_RADIUS_META: StringName = &"trailhead_visibility_radius"
const EXPECTED_FOLIAGE_LOD0_META: String = "foliage_lod0"
const EXPECTED_FOLIAGE_LOD1_META: String = "foliage_lod1"
const EXPECTED_FOLIAGE_LOD0_SHADOW_CASTING: int = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
const EXPECTED_FOLIAGE_LOD1_SHADOW_CASTING: int = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
const FOLIAGE_SPECIES_META: StringName = &"trailhead_foliage_species"

var _scene_root: Node = null
var _errors: PackedStringArray = PackedStringArray()


func _ready() -> void:
	_scene_root = SpikeRegionScene.instantiate()
	add_child(_scene_root)
	call_deferred("_inspect")


func _inspect() -> void:
	if _scene_root == null:
		_errors.append("failed to instantiate spike_1km scene")
		_finish()
		return

	var terrain_root: Node = _require_node(_scene_root, "TerrainVisuals")
	if terrain_root == null:
		_finish()
		return

	var warmup_root: Node = _require_node(terrain_root, TerrainVisualBuilderScript.REGION_PIPELINE_WARMUP_ROOT_NAME)
	if warmup_root != null:
		_inspect_pipeline_warmup(warmup_root)

	var hlod: MeshInstance3D = _require_node(terrain_root, "TerrainHLOD") as MeshInstance3D
	if hlod == null:
		_errors.append("TerrainHLOD should be a MeshInstance3D")
	else:
		_require_mesh_surfaces(hlod, "TerrainHLOD")
		_require_xz_bounds(hlod, "TerrainHLOD", EXPECTED_REGION_SIZE_M, EXPECTED_REGION_SIZE_M)
		if absf(hlod.visibility_range_begin - GameConfig.vis_range_terrain) > FLOAT_EPSILON:
			_errors.append("TerrainHLOD visibility_range_begin expected " + str(GameConfig.vis_range_terrain) + ", got " + str(hlod.visibility_range_begin))
		if absf(hlod.visibility_range_end) > FLOAT_EPSILON:
			_errors.append("TerrainHLOD visibility_range_end should be open-ended")
		if hlod.visibility_range_fade_mode != GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED:
			_errors.append("TerrainHLOD visibility_range_fade_mode expected DISABLED, got " + str(hlod.visibility_range_fade_mode))

	var detail_root: Node = _require_node(terrain_root, "TerrainDetailTiles")
	if detail_root != null:
		_require_direct_mesh_child_count(detail_root, EXPECTED_DETAIL_TILE_COUNT)
		_inspect_detail_tiles(detail_root)

	var foliage_root: Node = _require_node(terrain_root, "FoliageCells")
	if foliage_root != null:
		_inspect_foliage_cells(foliage_root)
		var foliage_instances: int = _count_multimesh_render_instances(foliage_root)
		if foliage_instances <= 0:
			_errors.append("FoliageCells should contain nonzero foliage instances")

	var collision_count: int = _count_collision_objects(terrain_root)
	if collision_count > 0:
		_errors.append("spike_1km render scene should not contain collision objects: " + str(collision_count))

	var mesh_count: int = _count_mesh_instances(terrain_root)
	if mesh_count <= 0:
		_errors.append("spike_1km render scene should contain mesh instances")

	_finish()


func _inspect_detail_tiles(detail_root: Node) -> void:
	for child in detail_root.get_children():
		var mesh_instance: MeshInstance3D = child as MeshInstance3D
		if mesh_instance == null:
			_errors.append("TerrainDetailTiles child should be MeshInstance3D: " + String(child.name))
			continue
		_require_mesh_surfaces(mesh_instance, "TerrainDetailTiles/" + String(child.name))
		if mesh_instance.mesh != null and mesh_instance.mesh.get_surface_count() != 1:
			_errors.append("TerrainDetailTiles/" + String(child.name) + " should collapse to one surface, got " + str(mesh_instance.mesh.get_surface_count()))
		if not mesh_instance.visibility_parent.is_empty():
			_errors.append("TerrainDetailTiles/" + String(child.name) + " should not use whole-region TerrainHLOD as visibility_parent")
		var visibility_radius: float = _visibility_radius(mesh_instance, "TerrainDetailTiles/" + String(child.name))
		var expected_range_end: float = _detail_visibility_range_end(visibility_radius)
		if absf(mesh_instance.visibility_range_end - expected_range_end) > FLOAT_EPSILON:
			_errors.append("TerrainDetailTiles/" + String(child.name) + " visibility_range_end expected " + str(expected_range_end) + ", got " + str(mesh_instance.visibility_range_end))
		if mesh_instance.visibility_range_fade_mode != GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED:
			_errors.append("TerrainDetailTiles/" + String(child.name) + " visibility_range_fade_mode expected DISABLED, got " + str(mesh_instance.visibility_range_fade_mode))
		if mesh_instance.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_ON:
			_errors.append("TerrainDetailTiles/" + String(child.name) + " should cast shadows")
		if not mesh_instance.has_meta(TILE_INDEX_META):
			_errors.append("TerrainDetailTiles/" + String(child.name) + " missing tile index metadata")
		else:
			var tile_index: Vector2i = Vector2i(mesh_instance.get_meta(TILE_INDEX_META))
			var expected_origin: Vector3 = Vector3(
				(float(tile_index.x) + 0.5) * GameConfig.STREAM_TILE_SIZE_M,
				0.0,
				(float(tile_index.y) + 0.5) * GameConfig.STREAM_TILE_SIZE_M
			)
			if mesh_instance.position.distance_to(expected_origin) > FLOAT_EPSILON:
				_errors.append("TerrainDetailTiles/" + String(child.name) + " origin expected " + str(expected_origin) + ", got " + str(mesh_instance.position))


func _inspect_foliage_cells(foliage_root: Node) -> void:
	var lod0_count: int = 0
	var lod1_count: int = 0
	for child in foliage_root.get_children():
		var multimesh_instance: MultiMeshInstance3D = child as MultiMeshInstance3D
		if multimesh_instance == null:
			continue
		var label: String = "FoliageCells/" + String(child.name)
		if not multimesh_instance.has_meta(REGION_LOD_META):
			_errors.append(label + " missing region LOD metadata")
			continue
		var region_lod: String = String(multimesh_instance.get_meta(REGION_LOD_META))
		var lod_index: int = 1
		if region_lod == EXPECTED_FOLIAGE_LOD0_META:
			lod_index = 0
		# Species drives the per-species fade reach/margin; grass is the fallback if the meta is
		# somehow missing (the builder always sets it), so the range checks below still resolve.
		var species_id: StringName = &""
		if multimesh_instance.has_meta(FOLIAGE_SPECIES_META):
			species_id = StringName(multimesh_instance.get_meta(FOLIAGE_SPECIES_META))
		else:
			_errors.append(label + " missing foliage species metadata")
		var expected_fade_mode: int = TerrainVisualBuilderScript.foliage_visibility_range_fade_mode_for_lod(lod_index)
		if multimesh_instance.visibility_range_fade_mode != expected_fade_mode:
			_errors.append(label + " visibility_range_fade_mode expected " + str(expected_fade_mode) + ", got " + str(multimesh_instance.visibility_range_fade_mode))
		var visibility_radius: float = _visibility_radius(multimesh_instance, label)
		var expected_margin: float = TerrainVisualBuilderScript.foliage_visibility_range_fade_margin_for_species(species_id)
		if absf(multimesh_instance.visibility_range_end_margin - expected_margin) > FLOAT_EPSILON:
			_errors.append(label + " visibility_range_end_margin expected " + str(expected_margin) + ", got " + str(multimesh_instance.visibility_range_end_margin))
		if lod_index == 0:
			lod0_count += 1
			if multimesh_instance.cast_shadow != EXPECTED_FOLIAGE_LOD0_SHADOW_CASTING:
				_errors.append(label + " LOD0 cast_shadow expected OFF, got " + str(multimesh_instance.cast_shadow))
			if absf(multimesh_instance.visibility_range_begin) > FLOAT_EPSILON:
				_errors.append(label + " LOD0 visibility_range_begin expected 0, got " + str(multimesh_instance.visibility_range_begin))
			var expected_lod0_end: float = TerrainVisualBuilderScript.foliage_lod0_visibility_range_end_for_species(visibility_radius, species_id)
			if absf(multimesh_instance.visibility_range_end - expected_lod0_end) > FLOAT_EPSILON:
				_errors.append(label + " LOD0 visibility_range_end expected " + str(expected_lod0_end) + ", got " + str(multimesh_instance.visibility_range_end))
			if absf(multimesh_instance.visibility_range_begin_margin) > FLOAT_EPSILON:
				_errors.append(label + " LOD0 visibility_range_begin_margin expected 0, got " + str(multimesh_instance.visibility_range_begin_margin))
		else:
			lod1_count += 1
			if multimesh_instance.cast_shadow != EXPECTED_FOLIAGE_LOD1_SHADOW_CASTING:
				_errors.append(label + " LOD1 cast_shadow expected OFF, got " + str(multimesh_instance.cast_shadow))
			var expected_lod1_begin: float = TerrainVisualBuilderScript.foliage_lod1_visibility_range_begin_for_species(visibility_radius, species_id)
			var expected_lod1_end: float = TerrainVisualBuilderScript.foliage_lod1_visibility_range_end_for_species(visibility_radius, species_id)
			if absf(multimesh_instance.visibility_range_begin - expected_lod1_begin) > FLOAT_EPSILON:
				_errors.append(label + " LOD1 visibility_range_begin expected " + str(expected_lod1_begin) + ", got " + str(multimesh_instance.visibility_range_begin))
			if absf(multimesh_instance.visibility_range_end - expected_lod1_end) > FLOAT_EPSILON:
				_errors.append(label + " LOD1 visibility_range_end expected " + str(expected_lod1_end) + ", got " + str(multimesh_instance.visibility_range_end))
			if absf(multimesh_instance.visibility_range_begin_margin - expected_margin) > FLOAT_EPSILON:
				_errors.append(label + " LOD1 visibility_range_begin_margin expected " + str(expected_margin) + ", got " + str(multimesh_instance.visibility_range_begin_margin))
	if lod0_count <= 0:
		_errors.append("FoliageCells should contain foliage_lod0 cells")
	if lod1_count <= 0:
		_errors.append("FoliageCells should contain foliage_lod1 cells")


func _inspect_pipeline_warmup(warmup_root: Node) -> void:
	var warmup_node: Node3D = warmup_root as Node3D
	if warmup_node == null:
		_errors.append("PipelineWarmup should be Node3D")
	elif not warmup_node.visible:
		_errors.append("PipelineWarmup should be visible for PSO warmup")
	if warmup_root.process_mode != Node.PROCESS_MODE_INHERIT:
		_errors.append("PipelineWarmup process_mode should be INHERIT")
	var terrain_material_count: int = _require_int_meta(
		warmup_root,
		TerrainVisualBuilderScript.PIPELINE_WARMUP_TERRAIN_MATERIAL_COUNT_META,
		"PipelineWarmup"
	)
	if terrain_material_count <= 0:
		_errors.append("PipelineWarmup terrain material count should be positive")
	var foliage_lod_count: int = _require_int_meta(
		warmup_root,
		TerrainVisualBuilderScript.PIPELINE_WARMUP_FOLIAGE_LOD_COUNT_META,
		"PipelineWarmup"
	)
	var expected_foliage_warmup_nodes: PackedStringArray = TerrainVisualBuilderScript.foliage_pipeline_warmup_node_names()
	if foliage_lod_count != expected_foliage_warmup_nodes.size():
		_errors.append("PipelineWarmup foliage warmup count expected " + str(expected_foliage_warmup_nodes.size()) + ", got " + str(foliage_lod_count))
	var terrain_warmup: MeshInstance3D = _require_node(warmup_root, TerrainVisualBuilderScript.REGION_PIPELINE_WARMUP_TERRAIN_NAME) as MeshInstance3D
	if terrain_warmup == null:
		_errors.append("PipelineWarmup terrain child should be MeshInstance3D")
	else:
		if terrain_warmup.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			_errors.append("PipelineWarmup terrain should not cast shadows")
		if terrain_warmup.mesh == null:
			_errors.append("PipelineWarmup terrain missing mesh")
		else:
			if terrain_warmup.mesh.get_surface_count() != terrain_material_count:
				_errors.append("PipelineWarmup terrain surface count expected " + str(terrain_material_count) + ", got " + str(terrain_warmup.mesh.get_surface_count()))
			_require_surface_materials(terrain_warmup, "PipelineWarmup terrain")
	for node_name in expected_foliage_warmup_nodes:
		var foliage_warmup: MultiMeshInstance3D = _require_node(warmup_root, node_name) as MultiMeshInstance3D
		_require_warmup_multimesh(foliage_warmup, "PipelineWarmup " + node_name)
	var collision_count: int = _count_collision_objects(warmup_root)
	if collision_count > 0:
		_errors.append("PipelineWarmup should not contain collision objects: " + str(collision_count))


func _require_int_meta(node: Node, meta_name: StringName, label: String) -> int:
	if not node.has_meta(meta_name):
		_errors.append(label + " missing metadata: " + String(meta_name))
		return 0
	return int(node.get_meta(meta_name))


func _require_surface_materials(mesh_instance: MeshInstance3D, label: String) -> void:
	if mesh_instance.mesh == null:
		return
	for surface_index in range(mesh_instance.mesh.get_surface_count()):
		var material: Material = mesh_instance.mesh.surface_get_material(surface_index)
		if material == null:
			_errors.append(label + " surface " + str(surface_index) + " missing material")
			continue
		var shader_material: ShaderMaterial = material as ShaderMaterial
		if shader_material != null and shader_material.resource_name == TerrainVisualBuilderScript.TERRAIN_INDEX_MATERIAL_NAME:
			_require_shader_color(shader_material, TerrainVisualBuilderScript.ZION_SANDSTONE_COLOR_UNIFORM, label)
			_require_shader_color(shader_material, TerrainVisualBuilderScript.ZION_SAND_COLOR_UNIFORM, label)
			_require_shader_float(shader_material, TerrainVisualBuilderScript.ZION_STRATA_STRENGTH_UNIFORM, label)


func _require_warmup_multimesh(multimesh_instance: MultiMeshInstance3D, label: String) -> void:
	if multimesh_instance == null:
		_errors.append(label + " should be MultiMeshInstance3D")
		return
	if multimesh_instance.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
		_errors.append(label + " should not cast shadows")
	if multimesh_instance.material_override == null:
		_errors.append(label + " missing material_override")
	elif _is_standard_material_warmup_label(label):
		if not (multimesh_instance.material_override is StandardMaterial3D):
			_errors.append(label + " should use StandardMaterial3D")
	elif not _is_grass_shader_material(multimesh_instance.material_override):
		_errors.append(label + " should use grass_billboard ShaderMaterial")
	if multimesh_instance.multimesh == null:
		_errors.append(label + " missing MultiMesh")
		return
	if not multimesh_instance.multimesh.use_custom_data:
		_errors.append(label + " should enable MultiMesh custom data for wind")
	if multimesh_instance.multimesh.instance_count != 1:
		_errors.append(label + " instance_count expected 1, got " + str(multimesh_instance.multimesh.instance_count))
	if multimesh_instance.multimesh.mesh == null:
		_errors.append(label + " missing warmup mesh")


func _is_grass_shader_material(material: Material) -> bool:
	var shader_material: ShaderMaterial = material as ShaderMaterial
	if shader_material == null or shader_material.shader == null:
		return false
	return shader_material.shader.resource_path == "res://systems/render/grass_billboard.gdshader"


func _is_standard_material_warmup_label(label: String) -> bool:
	# Boulder (procedural StandardMaterial3D) and the four GLB foliage species
	# (cottonwood/willow/juniper/yucca) both warm a StandardMaterial3D. Grass and
	# riparian_grass warm the grass_billboard ShaderMaterial, so they fall through.
	return label.find("_boulder") >= 0 or label.find("_cottonwood") >= 0 or label.find("_willow") >= 0 or label.find("_juniper") >= 0 or label.find("_yucca") >= 0


func _require_shader_color(material: ShaderMaterial, parameter_name: StringName, label: String) -> void:
	var value: Variant = material.get_shader_parameter(parameter_name)
	if not (value is Color):
		_errors.append(label + " missing Color shader parameter " + String(parameter_name))


func _require_shader_float(material: ShaderMaterial, parameter_name: StringName, label: String) -> void:
	var value: Variant = material.get_shader_parameter(parameter_name)
	if not (value is float):
		_errors.append(label + " missing float shader parameter " + String(parameter_name))


func _visibility_radius(node: Node, label: String) -> float:
	if not node.has_meta(VISIBILITY_RADIUS_META):
		_errors.append(label + " missing visibility radius metadata")
		return 0.0
	return float(node.get_meta(VISIBILITY_RADIUS_META))


func _detail_visibility_range_end(visibility_radius: float) -> float:
	return maxf(GameConfig.vis_range_terrain + visibility_radius, 0.0)


func _require_mesh_surfaces(mesh_instance: MeshInstance3D, label: String) -> void:
	if mesh_instance.mesh == null:
		_errors.append(label + " missing mesh")
		return
	if mesh_instance.mesh.get_surface_count() <= 0:
		_errors.append(label + " mesh has no surfaces")


func _require_xz_bounds(mesh_instance: MeshInstance3D, label: String, expected_x: float, expected_z: float) -> void:
	if mesh_instance.mesh == null:
		return
	var bounds: AABB = mesh_instance.mesh.get_aabb()
	if absf(bounds.size.x - expected_x) > BOUNDS_EPSILON_M:
		_errors.append(label + " bounds X expected " + str(expected_x) + ", got " + str(bounds.size.x))
	if absf(bounds.size.z - expected_z) > BOUNDS_EPSILON_M:
		_errors.append(label + " bounds Z expected " + str(expected_z) + ", got " + str(bounds.size.z))


func _require_direct_mesh_child_count(parent: Node, expected_count: int) -> void:
	var count: int = 0
	for child in parent.get_children():
		if child is MeshInstance3D:
			count += 1
	if count != expected_count:
		_errors.append(String(parent.name) + " direct MeshInstance3D count expected " + str(expected_count) + ", got " + str(count))


func _require_node(parent: Node, path: String) -> Node:
	var node: Node = parent.get_node_or_null(path)
	if node == null:
		_errors.append("missing node: " + path)
	return node


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
	if multimesh_instance != null and multimesh_instance.multimesh != null:
		count += 1
	for child in parent.get_children():
		count += _count_multimesh_instances(child)
	return count


func _count_multimesh_render_instances(parent: Node) -> int:
	var count: int = 0
	var multimesh_instance: MultiMeshInstance3D = parent as MultiMeshInstance3D
	if multimesh_instance != null and multimesh_instance.multimesh != null:
		count += multimesh_instance.multimesh.instance_count
	for child in parent.get_children():
		count += _count_multimesh_render_instances(child)
	return count


func _count_collision_objects(parent: Node) -> int:
	var count: int = 0
	if parent is CollisionObject3D:
		count += 1
	for child in parent.get_children():
		count += _count_collision_objects(child)
	return count


func _finish() -> void:
	if _errors.is_empty():
		print("PASS spike_1km render inspector")
		get_tree().quit(0)
		return
	for error in _errors:
		push_error(error)
	get_tree().quit(1)
