class_name TerrainVisualBuilder
extends Node3D

const CedarTerrainDef: Resource = preload("res://data/terrain/cedar_hollow_terrain_def.tres")
const TerrainSurfacePaletteResource: Resource = preload("res://data/surface_palettes/cedar_hollow_terrain.tres")
const SurfaceVisualCatalogResource: Resource = preload("res://data/surface_visuals/cedar_hollow_surface_visuals.tres")
const TerrainTrackOverlayShader: Shader = preload("res://systems/render/terrain_track_overlay.gdshader")
const DETAIL_MASK_TEXTURE_PATH: String = "res://assets/textures/surface_visuals/generated/terrain_detail_mask.png"
const GENERATED_SURFACE_TEXTURE_DIR: String = "res://assets/textures/surface_visuals/generated/"
const TEXTURE_SOURCE_PATH_META: StringName = &"trailhead_source_path"

static var _terrain_material_cache: Dictionary[StringName, StandardMaterial3D] = {}

const REGION_ID_META: StringName = &"trailhead_region_id"
const REGION_LOD_META: StringName = &"trailhead_region_lod"
const VISIBILITY_RADIUS_META: StringName = &"trailhead_visibility_radius"
const TILE_INDEX_META: StringName = &"trailhead_tile_index"
const TILE_PATH_META: StringName = &"trailhead_visual_tile_path"
const TILE_SURFACE_ID_PATH_META: StringName = &"trailhead_surface_id_path"
const HEIGHTMESH_NAME: String = "cedar_hollow_heightmesh"
const TERRAIN_TILE_NAME_PREFIX: String = "terrain_visual_tile_"
const TERRAIN_MATERIAL_PREFIX: String = "terrain_mat_"
const SPIKE_1KM_REGION_ID: String = "spike_1km"
const SPIKE_1KM_SCENE_ROOT_NAME: String = "Spike1KmRegion"
const REGION_ROOT_NAME: String = "TerrainVisuals"
const REGION_DETAIL_ROOT_NAME: String = "TerrainDetailTiles"
const REGION_HLOD_NAME: String = "TerrainHLOD"
const REGION_FOLIAGE_ROOT_NAME: String = "FoliageCells"
const REGION_PIPELINE_WARMUP_ROOT_NAME: String = "PipelineWarmup"
const REGION_PIPELINE_WARMUP_TERRAIN_NAME: String = "TerrainMaterialWarmup"
const REGION_PIPELINE_WARMUP_FOLIAGE_LOD0_NAME: String = "FoliageLOD0Warmup"
const REGION_PIPELINE_WARMUP_FOLIAGE_LOD1_NAME: String = "FoliageLOD1Warmup"
const REGION_MANIFEST_FILE: String = "collision_tiles_manifest.json"
const REGION_TILE_SIDE_CAR_FILE: String = "tile.json"
const REGION_TILE_HEIGHTMAP_FILE: String = "heightmap.bin"
const REGION_TILE_SURFACE_ID_FILE: String = "surface_id.png"
const PIPELINE_WARMUP_TERRAIN_MATERIAL_COUNT_META: StringName = &"trailhead_pipeline_warmup_terrain_material_count"
const PIPELINE_WARMUP_FOLIAGE_LOD_COUNT_META: StringName = &"trailhead_pipeline_warmup_foliage_lod_count"
const HEIGHTMAP_FLOAT_BYTE_SIZE: int = 4
const REGION_DETAIL_SAMPLE_STEP: int = 1
const REGION_HLOD_SAMPLE_STEP: int = 5
const REGION_FOLIAGE_CELL_SIZE_M: float = 32.0
const REGION_FOLIAGE_LOD0_BASE_COUNT: int = 8
const REGION_FOLIAGE_LOD1_BASE_COUNT: int = 3
const REGION_FOLIAGE_PATTERN_MODULUS: int = 1009
const REGION_FOLIAGE_CELL_X_MULTIPLIER: int = 97
const REGION_FOLIAGE_CELL_Z_MULTIPLIER: int = 193
const REGION_FOLIAGE_INSTANCE_MULTIPLIER: int = 389
const REGION_FOLIAGE_LOD_MULTIPLIER: int = 521
const REGION_FOLIAGE_SALT_MULTIPLIER: int = 61
const REGION_FOLIAGE_Y_OFFSET: float = 0.035
const REGION_FOLIAGE_CULL_MARGIN: float = 0.08
const REGION_FOLIAGE_LOD0_SCALE: Vector3 = Vector3(0.16, 0.42, 0.16)
const REGION_FOLIAGE_LOD1_SCALE: Vector3 = Vector3(0.42, 0.58, 0.42)
const REGION_FOLIAGE_LOD0_COLOR: Color = Color(0.24, 0.38, 0.14, 0.92)
const REGION_FOLIAGE_LOD1_COLOR: Color = Color(0.28, 0.34, 0.16, 0.86)
const WET_DIFFUSE_MULTIPLIER: float = 0.2
const WET_ROUGHNESS: float = 0.12
const WET_CLEARCOAT: float = 0.58
const WET_CLEARCOAT_ROUGHNESS: float = 0.08
const TRACK_RT_UNIFORM: StringName = &"track_rt"
const TRACK_BOUNDS_MIN_UNIFORM: StringName = &"track_bounds_min"
const TRACK_BOUNDS_MAX_UNIFORM: StringName = &"track_bounds_max"
const TRACK_DARKENING_UNIFORM: StringName = &"track_darkening"
const RUT_DARKENING_UNIFORM: StringName = &"rut_darkening"
const RUT_DARKENING_SCALE: float = 0.75


class RegionTileData:
	var cell: Vector2i = Vector2i.ZERO
	var key: String = ""
	var tile_size_m: float = 0.0
	var width: int = 0
	var depth: int = 0
	var heightmap_path: String = ""
	var surface_id_path: String = ""
	var heights: PackedFloat32Array = PackedFloat32Array()
	var surface_image: Image = null


class MeshBucket:
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var indices: PackedInt32Array = PackedInt32Array()
	var vertex_indices: Dictionary[String, int] = {}


func _ready() -> void:
	if name != SPIKE_1KM_SCENE_ROOT_NAME:
		return
	if get_node_or_null(REGION_ROOT_NAME) != null:
		return
	build_spike_1km(self)


static func build_cedar_hollow(parent: Node3D) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = "TerrainVisuals"
	parent.add_child(root)

	var terrain_errors: PackedStringArray = CedarTerrainDef.call("validate_render")
	if terrain_errors.size() > 0:
		for error in terrain_errors:
			push_error("TerrainVisualBuilder TerrainDef invalid: " + error)
		return root

	var active_tiles: Array[Vector2i] = CedarTerrainDef.call("active_tile_indices")
	for tile_array_index in range(active_tiles.size()):
		var tile_index: Vector2i = active_tiles[tile_array_index]
		var tile_path: String = CedarTerrainDef.call("visual_tile_path_for_tile", tile_index)
		_add_visual_tile(root, tile_index, tile_path, tile_array_index)
	return root


static func build_spike_1km(parent: Node3D) -> Node3D:
	return build_region(parent, SPIKE_1KM_REGION_ID)


static func build_region(parent: Node3D, region_id: String) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = REGION_ROOT_NAME
	root.set_meta(REGION_ID_META, region_id)
	parent.add_child(root)

	var manifest_path: String = _region_manifest_path(region_id)
	var manifest: Dictionary = _load_json_dictionary(manifest_path)
	if manifest.is_empty():
		push_error("TerrainVisualBuilder region manifest failed to load: " + manifest_path)
		return root

	var tile_cells: Array[Vector2i] = _tile_cells_from_manifest(manifest)
	if tile_cells.is_empty():
		push_error("TerrainVisualBuilder region has no manifest tiles: " + region_id)
		return root

	var tile_data_list: Array[RegionTileData] = _load_region_tiles(region_id, tile_cells)
	if tile_data_list.is_empty():
		push_error("TerrainVisualBuilder region has no loadable render tiles: " + region_id)
		return root

	_add_region_pipeline_warmup(root)
	var hlod_instance: MeshInstance3D = _add_region_hlod(root, tile_data_list)
	var detail_root: Node3D = Node3D.new()
	detail_root.name = REGION_DETAIL_ROOT_NAME
	root.add_child(detail_root)
	for tile_data in tile_data_list:
		_add_region_detail_tile(detail_root, region_id, tile_data, hlod_instance)
	_add_region_foliage(root, manifest, tile_data_list)
	return root


static func build_region_stream_root(parent: Node3D, region_id: String) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = REGION_ROOT_NAME
	root.set_meta(REGION_ID_META, region_id)
	parent.add_child(root)

	_add_region_pipeline_warmup(root)
	var detail_root: Node3D = Node3D.new()
	detail_root.name = REGION_DETAIL_ROOT_NAME
	detail_root.set_meta(REGION_ID_META, region_id)
	root.add_child(detail_root)
	return root


static func add_region_visual_tile(parent: Node3D, region_id: String, cell: Vector2i) -> MeshInstance3D:
	var tile_data: RegionTileData = _load_region_tile(region_id, cell)
	if tile_data == null:
		return null
	return _add_region_detail_tile(parent, region_id, tile_data, null)


static func visual_tile_node_name(tile_index: Vector2i, tile_path: String, tile_array_index: int) -> String:
	var base_name: String = tile_path.get_file().get_basename()
	if base_name.is_empty():
		base_name = HEIGHTMESH_NAME + "_" + str(tile_array_index)
	return TERRAIN_TILE_NAME_PREFIX + str(tile_index.x) + "_" + str(tile_index.y) + "_" + _safe_node_name(base_name)


static func region_detail_tile_node_name(region_id: String, tile_index: Vector2i) -> String:
	return "region_" + _safe_node_name(region_id) + "_detail_tile_" + str(tile_index.x) + "_" + str(tile_index.y)


static func _detail_visibility_range_end(tile_data: RegionTileData) -> float:
	return maxf(maxf(GameConfig.cam_far, GameConfig.vis_range_terrain) + _tile_visibility_radius(tile_data), 0.0)


static func _hlod_visibility_range_begin() -> float:
	return maxf(GameConfig.vis_range_terrain, 0.0)


static func _foliage_lod0_visibility_range_end(cell_radius: float) -> float:
	return maxf(GameConfig.vis_range_grass + cell_radius, 0.0)


static func _foliage_lod1_visibility_range_begin(cell_radius: float) -> float:
	return _foliage_lod0_visibility_range_end(cell_radius)


static func _foliage_lod1_visibility_range_end(cell_radius: float) -> float:
	return maxf(GameConfig.cam_far + cell_radius, _foliage_lod1_visibility_range_begin(cell_radius))


static func _add_region_pipeline_warmup(parent: Node3D) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = REGION_PIPELINE_WARMUP_ROOT_NAME
	root.visible = false
	root.process_mode = Node.PROCESS_MODE_DISABLED
	parent.add_child(root)

	var terrain_material_count: int = _add_terrain_pipeline_warmup(root)
	var foliage_lod_count: int = _add_foliage_pipeline_warmup(root)
	root.set_meta(PIPELINE_WARMUP_TERRAIN_MATERIAL_COUNT_META, terrain_material_count)
	root.set_meta(PIPELINE_WARMUP_FOLIAGE_LOD_COUNT_META, foliage_lod_count)
	return root


static func _add_terrain_pipeline_warmup(parent: Node3D) -> int:
	var visual_defs: Array[Resource] = _surface_visual_defs()
	if visual_defs.is_empty():
		return 0
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.resource_name = "region_terrain_pipeline_warmup_mesh"
	var material_count: int = 0
	for visual_def in visual_defs:
		var material: StandardMaterial3D = _material_for_visual_def(visual_def)
		_append_pipeline_warmup_surface(mesh, material, material_count)
		material_count += 1
	if material_count <= 0:
		return 0
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = REGION_PIPELINE_WARMUP_TERRAIN_NAME
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return material_count


static func _add_foliage_pipeline_warmup(parent: Node3D) -> int:
	var lod0_mesh: Mesh = _region_foliage_mesh("region_foliage_lod0_pipeline_warmup_mesh")
	var lod0_material: Material = _region_foliage_material("region_foliage_lod0_pipeline_warmup_material", REGION_FOLIAGE_LOD0_COLOR)
	_add_foliage_pipeline_warmup_instance(parent, REGION_PIPELINE_WARMUP_FOLIAGE_LOD0_NAME, lod0_mesh, lod0_material)
	var lod1_mesh: Mesh = _region_foliage_mesh("region_foliage_lod1_pipeline_warmup_mesh")
	var lod1_material: Material = _region_foliage_material("region_foliage_lod1_pipeline_warmup_material", REGION_FOLIAGE_LOD1_COLOR)
	_add_foliage_pipeline_warmup_instance(parent, REGION_PIPELINE_WARMUP_FOLIAGE_LOD1_NAME, lod1_mesh, lod1_material)
	return 2


static func _add_foliage_pipeline_warmup_instance(parent: Node3D, instance_name: String, mesh: Mesh, material: Material) -> void:
	var multimesh: MultiMesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = mesh
	multimesh.instance_count = 1
	multimesh.set_instance_transform(0, Transform3D(Basis.IDENTITY, Vector3.ZERO))
	multimesh.set_instance_color(0, Color.WHITE)

	var instance: MultiMeshInstance3D = MultiMeshInstance3D.new()
	instance.name = instance_name
	instance.multimesh = multimesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)


static func _append_pipeline_warmup_surface(mesh: ArrayMesh, material: Material, surface_index: int) -> void:
	var x_offset: float = float(surface_index) * 0.02
	var vertices: PackedVector3Array = PackedVector3Array()
	vertices.append(Vector3(x_offset, 0.0, 0.0))
	vertices.append(Vector3(x_offset + 0.01, 0.0, 0.0))
	vertices.append(Vector3(x_offset, 0.01, 0.0))
	var normals: PackedVector3Array = PackedVector3Array()
	normals.append(Vector3.BACK)
	normals.append(Vector3.BACK)
	normals.append(Vector3.BACK)
	var uvs: PackedVector2Array = PackedVector2Array()
	uvs.append(Vector2.ZERO)
	uvs.append(Vector2.RIGHT)
	uvs.append(Vector2.UP)
	var indices: PackedInt32Array = PackedInt32Array()
	indices.append(0)
	indices.append(1)
	indices.append(2)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(mesh.get_surface_count() - 1, material)


static func _add_region_hlod(parent: Node3D, tile_data_list: Array[RegionTileData]) -> MeshInstance3D:
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = REGION_HLOD_NAME
	instance.mesh = _build_region_mesh(tile_data_list, REGION_HLOD_SAMPLE_STEP, "spike_1km_terrain_hlod_mesh", Vector2.ZERO)
	instance.visibility_range_begin = _hlod_visibility_range_begin()
	instance.visibility_range_end = 0.0
	instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	instance.set_meta(REGION_LOD_META, "hlod")
	parent.add_child(instance)
	return instance


static func _add_region_detail_tile(parent: Node3D, region_id: String, tile_data: RegionTileData, hlod_instance: MeshInstance3D) -> MeshInstance3D:
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = region_detail_tile_node_name(region_id, tile_data.cell)
	var tile_origin_xz: Vector2 = _tile_origin_xz(tile_data)
	instance.position = Vector3(tile_origin_xz.x, 0.0, tile_origin_xz.y)
	instance.mesh = _build_region_mesh([tile_data], REGION_DETAIL_SAMPLE_STEP, tile_data.key + "_terrain_detail_mesh", tile_origin_xz)
	instance.visibility_range_end = _detail_visibility_range_end(tile_data)
	instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	instance.set_meta(REGION_LOD_META, "detail")
	instance.set_meta(VISIBILITY_RADIUS_META, _tile_visibility_radius(tile_data))
	instance.set_meta(TILE_INDEX_META, tile_data.cell)
	instance.set_meta(TILE_PATH_META, tile_data.heightmap_path)
	instance.set_meta(TILE_SURFACE_ID_PATH_META, tile_data.surface_id_path)
	parent.add_child(instance)
	if hlod_instance != null:
		instance.visibility_parent = instance.get_path_to(hlod_instance)
	return instance


static func _build_region_mesh(tile_data_list: Array[RegionTileData], sample_step: int, mesh_name: String, local_origin_xz: Vector2) -> ArrayMesh:
	var buckets: Dictionary[int, MeshBucket] = {}
	for tile_data in tile_data_list:
		_append_tile_quads(tile_data, sample_step, buckets, local_origin_xz)

	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.resource_name = mesh_name
	var surface_values: Array[int] = _sorted_surface_values(buckets)
	for surface_id_value in surface_values:
		var bucket: MeshBucket = buckets[surface_id_value]
		if bucket.indices.size() <= 0:
			continue
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = bucket.vertices
		arrays[Mesh.ARRAY_NORMAL] = bucket.normals
		arrays[Mesh.ARRAY_TEX_UV] = bucket.uvs
		arrays[Mesh.ARRAY_INDEX] = bucket.indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _material_for_surface_value(surface_id_value))
	return mesh


static func _append_tile_quads(tile_data: RegionTileData, sample_step: int, buckets: Dictionary[int, MeshBucket], local_origin_xz: Vector2) -> void:
	if tile_data.width <= 1 or tile_data.depth <= 1:
		return
	var safe_step: int = maxi(sample_step, 1)
	var max_col: int = tile_data.width - 1
	var max_row: int = tile_data.depth - 1
	for row in range(0, max_row, safe_step):
		var next_row: int = mini(row + safe_step, max_row)
		for col in range(0, max_col, safe_step):
			var next_col: int = mini(col + safe_step, max_col)
			var surface_col: int = _surface_sample_coord(col, next_col, tile_data.surface_image.get_width())
			var surface_row: int = _surface_sample_coord(row, next_row, tile_data.surface_image.get_height())
			var surface_id_value: int = _surface_id_value_at(tile_data, surface_col, surface_row)
			var bucket: MeshBucket = _bucket_for_surface_value(buckets, surface_id_value)
			var corner_a: int = _bucket_vertex(bucket, tile_data, col, row, local_origin_xz)
			var corner_b: int = _bucket_vertex(bucket, tile_data, next_col, row, local_origin_xz)
			var corner_c: int = _bucket_vertex(bucket, tile_data, col, next_row, local_origin_xz)
			var corner_d: int = _bucket_vertex(bucket, tile_data, next_col, next_row, local_origin_xz)
			bucket.indices.append(corner_a)
			bucket.indices.append(corner_c)
			bucket.indices.append(corner_b)
			bucket.indices.append(corner_b)
			bucket.indices.append(corner_c)
			bucket.indices.append(corner_d)


static func _surface_sample_coord(start_index: int, end_index: int, sample_count: int) -> int:
	var max_index: int = maxi(sample_count - 1, 0)
	var center_index: int = int(floor((float(start_index) + float(end_index)) * 0.5))
	return mini(maxi(center_index, 0), max_index)


static func _bucket_for_surface_value(buckets: Dictionary[int, MeshBucket], surface_id_value: int) -> MeshBucket:
	if buckets.has(surface_id_value):
		return buckets[surface_id_value]
	var bucket: MeshBucket = MeshBucket.new()
	buckets[surface_id_value] = bucket
	return bucket


static func _bucket_vertex(bucket: MeshBucket, tile_data: RegionTileData, col: int, row: int, local_origin_xz: Vector2) -> int:
	var key: String = _tile_key(tile_data.cell) + ":" + str(row) + ":" + str(col)
	if bucket.vertex_indices.has(key):
		return int(bucket.vertex_indices[key])
	var vertex_index: int = bucket.vertices.size()
	bucket.vertex_indices[key] = vertex_index
	var vertex: Vector3 = _tile_vertex(tile_data, col, row, local_origin_xz)
	bucket.vertices.append(vertex)
	bucket.normals.append(_tile_normal(tile_data, col, row))
	bucket.uvs.append(_tile_world_xz(tile_data, col, row))
	return vertex_index


static func _tile_vertex(tile_data: RegionTileData, col: int, row: int, local_origin_xz: Vector2) -> Vector3:
	var world_xz: Vector2 = _tile_world_xz(tile_data, col, row)
	return Vector3(
		world_xz.x - local_origin_xz.x,
		_height_value_at(tile_data, col, row),
		world_xz.y - local_origin_xz.y
	)


static func _tile_world_xz(tile_data: RegionTileData, col: int, row: int) -> Vector2:
	var x_spacing: float = tile_data.tile_size_m / float(maxi(tile_data.width - 1, 1))
	var z_spacing: float = tile_data.tile_size_m / float(maxi(tile_data.depth - 1, 1))
	return Vector2(
		float(tile_data.cell.x) * tile_data.tile_size_m + float(col) * x_spacing,
		float(tile_data.cell.y) * tile_data.tile_size_m + float(row) * z_spacing
	)


static func _tile_origin_xz(tile_data: RegionTileData) -> Vector2:
	return Vector2(
		(float(tile_data.cell.x) + 0.5) * tile_data.tile_size_m,
		(float(tile_data.cell.y) + 0.5) * tile_data.tile_size_m
	)


static func _tile_visibility_radius(tile_data: RegionTileData) -> float:
	return Vector2(tile_data.tile_size_m, tile_data.tile_size_m).length() * 0.5


static func _tile_normal(tile_data: RegionTileData, col: int, row: int) -> Vector3:
	var left_col: int = mini(maxi(col - 1, 0), tile_data.width - 1)
	var right_col: int = mini(maxi(col + 1, 0), tile_data.width - 1)
	var back_row: int = mini(maxi(row - 1, 0), tile_data.depth - 1)
	var forward_row: int = mini(maxi(row + 1, 0), tile_data.depth - 1)
	var x_spacing: float = tile_data.tile_size_m / float(maxi(tile_data.width - 1, 1))
	var z_spacing: float = tile_data.tile_size_m / float(maxi(tile_data.depth - 1, 1))
	var x_span: float = maxf(float(right_col - left_col) * x_spacing, x_spacing)
	var z_span: float = maxf(float(forward_row - back_row) * z_spacing, z_spacing)
	var x_slope: float = (_height_value_at(tile_data, right_col, row) - _height_value_at(tile_data, left_col, row)) / x_span
	var z_slope: float = (_height_value_at(tile_data, col, forward_row) - _height_value_at(tile_data, col, back_row)) / z_span
	return Vector3(-x_slope, 1.0, -z_slope).normalized()


static func _height_value_at(tile_data: RegionTileData, col: int, row: int) -> float:
	var safe_col: int = mini(maxi(col, 0), tile_data.width - 1)
	var safe_row: int = mini(maxi(row, 0), tile_data.depth - 1)
	var index: int = safe_row * tile_data.width + safe_col
	if index < 0 or index >= tile_data.heights.size():
		return 0.0
	return tile_data.heights[index]


static func _surface_id_value_at(tile_data: RegionTileData, col: int, row: int) -> int:
	if tile_data.surface_image == null or tile_data.surface_image.is_empty():
		return 0
	var safe_col: int = mini(maxi(col, 0), tile_data.surface_image.get_width() - 1)
	var safe_row: int = mini(maxi(row, 0), tile_data.surface_image.get_height() - 1)
	return int(floor(tile_data.surface_image.get_pixel(safe_col, safe_row).r * 255.0 + 0.5))


static func _sorted_surface_values(buckets: Dictionary[int, MeshBucket]) -> Array[int]:
	var values: Array[int] = []
	for key in buckets.keys():
		values.append(int(key))
	values.sort()
	return values


static func _material_for_surface_value(surface_id_value: int) -> StandardMaterial3D:
	var surface_id: StringName = _surface_id_for_value(surface_id_value)
	var visual_def: Resource = SurfaceVisualCatalogResource.call("default_visual_for_surface_id", surface_id)
	if visual_def != null:
		return _material_for_visual_def(visual_def)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.resource_name = "terrain_visual_surface_" + str(surface_id_value)
	material.albedo_color = Color(0.50, 0.47, 0.38, 1.0)
	material.roughness = 0.9
	return material


static func _surface_visual_defs() -> Array[Resource]:
	var visual_defs: Array[Resource] = []
	var visual_defs_value: Variant = SurfaceVisualCatalogResource.get("visual_defs")
	if not (visual_defs_value is Array):
		return visual_defs
	var visual_defs_array: Array = visual_defs_value as Array
	for item in visual_defs_array:
		var visual_def: Resource = item as Resource
		if visual_def != null:
			visual_defs.append(visual_def)
	return visual_defs


static func _surface_id_for_value(surface_id_value: int) -> StringName:
	var fallback_surface_id: StringName = SurfaceVisualCatalogResource.get("fallback_surface_id")
	return StringName(TerrainSurfacePaletteResource.call("surface_id_for", surface_id_value, fallback_surface_id))


static func _load_region_tiles(region_id: String, tile_cells: Array[Vector2i]) -> Array[RegionTileData]:
	var tile_data_list: Array[RegionTileData] = []
	for cell in tile_cells:
		var tile_data: RegionTileData = _load_region_tile(region_id, cell)
		if tile_data != null:
			tile_data_list.append(tile_data)
	return tile_data_list


static func _load_region_tile(region_id: String, cell: Vector2i) -> RegionTileData:
	var sidecar_path: String = _tile_sidecar_path(region_id, cell)
	var sidecar: Dictionary = _load_json_dictionary(sidecar_path)
	if sidecar.is_empty():
		push_error("TerrainVisualBuilder tile sidecar failed to load: " + sidecar_path)
		return null
	if not sidecar.has("heightmap") or not sidecar.has("surface_id"):
		push_error("TerrainVisualBuilder tile sidecar missing render data: " + sidecar_path)
		return null

	var heightmap_info: Dictionary = sidecar["heightmap"] as Dictionary
	var surface_info: Dictionary = sidecar["surface_id"] as Dictionary
	if heightmap_info == null or surface_info == null:
		push_error("TerrainVisualBuilder tile sidecar render data is invalid: " + sidecar_path)
		return null
	if not heightmap_info.has("shape") or not heightmap_info.has("path"):
		push_error("TerrainVisualBuilder tile sidecar heightmap shape/path missing: " + sidecar_path)
		return null
	if not surface_info.has("path"):
		push_error("TerrainVisualBuilder tile sidecar surface path missing: " + sidecar_path)
		return null

	var shape_value: Variant = heightmap_info["shape"]
	if not (shape_value is Array):
		push_error("TerrainVisualBuilder tile heightmap shape is not an array: " + sidecar_path)
		return null
	var shape_array: Array = shape_value as Array
	if shape_array.size() != 2:
		push_error("TerrainVisualBuilder tile heightmap shape must have two entries: " + sidecar_path)
		return null

	var tile_data: RegionTileData = RegionTileData.new()
	tile_data.cell = cell
	tile_data.key = _tile_key(cell)
	tile_data.tile_size_m = float(sidecar.get("tile_size_m", GameConfig.STREAM_TILE_SIZE_M))
	tile_data.depth = int(shape_array[0])
	tile_data.width = int(shape_array[1])
	tile_data.heightmap_path = _tile_directory_path(region_id, cell).path_join(String(heightmap_info["path"]))
	tile_data.surface_id_path = _tile_directory_path(region_id, cell).path_join(String(surface_info["path"]))
	if tile_data.width <= 1 or tile_data.depth <= 1:
		push_error("TerrainVisualBuilder tile heightmap shape too small: " + sidecar_path)
		return null

	var height_bytes: PackedByteArray = FileAccess.get_file_as_bytes(tile_data.heightmap_path)
	var expected_bytes: int = tile_data.width * tile_data.depth * HEIGHTMAP_FLOAT_BYTE_SIZE
	if height_bytes.size() != expected_bytes:
		push_error("TerrainVisualBuilder heightmap byte count mismatch: " + tile_data.heightmap_path)
		return null
	tile_data.heights = height_bytes.to_float32_array()
	if tile_data.heights.size() != tile_data.width * tile_data.depth:
		push_error("TerrainVisualBuilder heightmap float count mismatch: " + tile_data.heightmap_path)
		return null

	tile_data.surface_image = Image.load_from_file(ProjectSettings.globalize_path(tile_data.surface_id_path))
	if tile_data.surface_image == null or tile_data.surface_image.is_empty():
		push_error("TerrainVisualBuilder surface_id image failed to load: " + tile_data.surface_id_path)
		return null
	return tile_data


static func _load_json_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		return {}
	return parsed as Dictionary


static func _tile_cells_from_manifest(manifest: Dictionary) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if not manifest.has("tiles"):
		return cells
	var tiles_value: Variant = manifest["tiles"]
	if not (tiles_value is Array):
		return cells
	var tiles: Array = tiles_value as Array
	for tile_value in tiles:
		if not (tile_value is Array):
			continue
		var tile_array: Array = tile_value as Array
		if tile_array.size() != 2:
			continue
		cells.append(Vector2i(int(tile_array[0]), int(tile_array[1])))
	cells.sort_custom(Callable(TerrainVisualBuilder, "_cell_less"))
	return cells


static func _cell_less(left: Vector2i, right: Vector2i) -> bool:
	if left.x == right.x:
		return left.y < right.y
	return left.x < right.x


static func _region_manifest_path(region_id: String) -> String:
	return _region_path(region_id).path_join(REGION_MANIFEST_FILE)


static func _tile_sidecar_path(region_id: String, cell: Vector2i) -> String:
	return _tile_directory_path(region_id, cell).path_join(REGION_TILE_SIDE_CAR_FILE)


static func _tile_directory_path(region_id: String, cell: Vector2i) -> String:
	return _region_path(region_id).path_join("tiles").path_join(_tile_key(cell))


static func _region_path(region_id: String) -> String:
	return GameConfig.STREAM_TILE_DATA_BASE.path_join(region_id)


static func _tile_key(cell: Vector2i) -> String:
	return str(cell.x) + "_" + str(cell.y)


static func _add_region_foliage(parent: Node3D, manifest: Dictionary, tile_data_list: Array[RegionTileData]) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = REGION_FOLIAGE_ROOT_NAME
	root.set_meta(REGION_ID_META, String(manifest.get("region_id", SPIKE_1KM_REGION_ID)))
	parent.add_child(root)

	var bounds: Rect2 = _region_bounds_xz(tile_data_list)
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return root

	var tile_data_by_cell: Dictionary[Vector2i, RegionTileData] = _tile_data_by_cell(tile_data_list)
	var lod0_mesh: Mesh = _region_foliage_mesh("region_foliage_lod0_mesh")
	var lod1_mesh: Mesh = _region_foliage_mesh("region_foliage_lod1_mesh")
	var lod0_material: Material = _region_foliage_material("region_foliage_lod0_material", REGION_FOLIAGE_LOD0_COLOR)
	var lod1_material: Material = _region_foliage_material("region_foliage_lod1_material", REGION_FOLIAGE_LOD1_COLOR)
	var cell_count_x: int = int(ceil(bounds.size.x / REGION_FOLIAGE_CELL_SIZE_M))
	var cell_count_z: int = int(ceil(bounds.size.y / REGION_FOLIAGE_CELL_SIZE_M))
	for cell_z in range(cell_count_z):
		for cell_x in range(cell_count_x):
			var cell_min_x: float = bounds.position.x + float(cell_x) * REGION_FOLIAGE_CELL_SIZE_M
			var cell_min_z: float = bounds.position.y + float(cell_z) * REGION_FOLIAGE_CELL_SIZE_M
			var cell_max_x: float = minf(cell_min_x + REGION_FOLIAGE_CELL_SIZE_M, bounds.position.x + bounds.size.x)
			var cell_max_z: float = minf(cell_min_z + REGION_FOLIAGE_CELL_SIZE_M, bounds.position.y + bounds.size.y)
			var cell_rect: Rect2 = Rect2(
				Vector2(cell_min_x, cell_min_z),
				Vector2(maxf(cell_max_x - cell_min_x, 0.0), maxf(cell_max_z - cell_min_z, 0.0))
			)
			var foliage_cell: Vector2i = Vector2i(cell_x, cell_z)
			_add_region_foliage_cell(root, tile_data_by_cell, cell_rect, foliage_cell, 0, lod0_mesh, lod0_material, REGION_FOLIAGE_LOD0_BASE_COUNT)
			_add_region_foliage_cell(root, tile_data_by_cell, cell_rect, foliage_cell, 1, lod1_mesh, lod1_material, REGION_FOLIAGE_LOD1_BASE_COUNT)
	return root


static func _add_region_foliage_cell(parent: Node3D, tile_data_by_cell: Dictionary[Vector2i, RegionTileData], cell_rect: Rect2, foliage_cell: Vector2i, lod_index: int, mesh: Mesh, material: Material, base_count: int) -> void:
	if cell_rect.size.x <= 0.0 or cell_rect.size.y <= 0.0:
		return
	var transforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	var max_attempts: int = maxi(base_count * 3, base_count)
	for attempt in range(max_attempts):
		if transforms.size() >= base_count:
			break
		var unit_x: float = _region_foliage_unit(foliage_cell, lod_index, attempt, 1)
		var unit_z: float = _region_foliage_unit(foliage_cell, lod_index, attempt, 2)
		var world_x: float = cell_rect.position.x + unit_x * cell_rect.size.x
		var world_z: float = cell_rect.position.y + unit_z * cell_rect.size.y
		var surface_id_value: int = _surface_id_value_at_region_xz(tile_data_by_cell, world_x, world_z)
		var density: float = _foliage_density_for_surface_value(surface_id_value)
		if density <= 0.0:
			continue
		var keep_value: float = _region_foliage_unit(foliage_cell, lod_index, attempt, 3)
		if keep_value > density:
			continue
		var height: float = _height_at_region_xz(tile_data_by_cell, world_x, world_z)
		var yaw: float = deg_to_rad(_region_foliage_unit(foliage_cell, lod_index, attempt, 4) * 360.0)
		var width_scale: float = 0.82 + _region_foliage_unit(foliage_cell, lod_index, attempt, 5) * 0.42
		var height_scale: float = 0.78 + _region_foliage_unit(foliage_cell, lod_index, attempt, 6) * 0.54
		var base_scale: Vector3 = REGION_FOLIAGE_LOD0_SCALE
		if lod_index > 0:
			base_scale = REGION_FOLIAGE_LOD1_SCALE
		var basis: Basis = Basis(Vector3.UP, yaw).scaled(Vector3(base_scale.x * width_scale, base_scale.y * height_scale, base_scale.z * width_scale))
		transforms.append(Transform3D(basis, Vector3(world_x, height + REGION_FOLIAGE_Y_OFFSET, world_z)))
		var color_warmth: float = _region_foliage_unit(foliage_cell, lod_index, attempt, 7)
		colors.append(Color(0.84 + color_warmth * 0.22, 0.92 + color_warmth * 0.14, 0.72 + color_warmth * 0.12, 1.0))

	if transforms.is_empty():
		return

	var instance: MultiMeshInstance3D = MultiMeshInstance3D.new()
	instance.name = "foliage_cell_" + str(foliage_cell.x) + "_" + str(foliage_cell.y) + "_lod" + str(lod_index)
	var foliage_origin_xz: Vector2 = cell_rect.position + cell_rect.size * 0.5
	var foliage_cell_radius: float = cell_rect.size.length() * 0.5
	instance.position = Vector3(foliage_origin_xz.x, 0.0, foliage_origin_xz.y)
	instance.material_override = material
	instance.extra_cull_margin = REGION_FOLIAGE_CULL_MARGIN
	if lod_index == 0:
		instance.visibility_range_end = _foliage_lod0_visibility_range_end(foliage_cell_radius)
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	else:
		instance.visibility_range_begin = _foliage_lod1_visibility_range_begin(foliage_cell_radius)
		instance.visibility_range_end = _foliage_lod1_visibility_range_end(foliage_cell_radius)
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	instance.set_meta(REGION_LOD_META, "foliage_lod" + str(lod_index))
	instance.set_meta(VISIBILITY_RADIUS_META, foliage_cell_radius)
	var multimesh: MultiMesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for i in range(transforms.size()):
		var transform: Transform3D = transforms[i]
		transform.origin.x -= foliage_origin_xz.x
		transform.origin.z -= foliage_origin_xz.y
		multimesh.set_instance_transform(i, transform)
		multimesh.set_instance_color(i, colors[i])
	instance.multimesh = multimesh
	parent.add_child(instance)


static func _region_foliage_mesh(mesh_name: String) -> ArrayMesh:
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.resource_name = mesh_name
	var vertices: PackedVector3Array = PackedVector3Array()
	vertices.append(Vector3(-0.5, 0.0, 0.0))
	vertices.append(Vector3(0.5, 0.0, 0.0))
	vertices.append(Vector3(-0.5, 1.0, 0.0))
	vertices.append(Vector3(0.5, 1.0, 0.0))
	vertices.append(Vector3(0.0, 0.0, -0.5))
	vertices.append(Vector3(0.0, 0.0, 0.5))
	vertices.append(Vector3(0.0, 1.0, -0.5))
	vertices.append(Vector3(0.0, 1.0, 0.5))
	var normals: PackedVector3Array = PackedVector3Array()
	for i in range(4):
		normals.append(Vector3.FORWARD)
	for i in range(4):
		normals.append(Vector3.RIGHT)
	var uvs: PackedVector2Array = PackedVector2Array()
	uvs.append(Vector2(0.0, 1.0))
	uvs.append(Vector2(1.0, 1.0))
	uvs.append(Vector2(0.0, 0.0))
	uvs.append(Vector2(1.0, 0.0))
	uvs.append(Vector2(0.0, 1.0))
	uvs.append(Vector2(1.0, 1.0))
	uvs.append(Vector2(0.0, 0.0))
	uvs.append(Vector2(1.0, 0.0))
	var indices: PackedInt32Array = PackedInt32Array()
	indices.append(0)
	indices.append(2)
	indices.append(1)
	indices.append(1)
	indices.append(2)
	indices.append(3)
	indices.append(4)
	indices.append(6)
	indices.append(5)
	indices.append(5)
	indices.append(6)
	indices.append(7)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _region_foliage_material(material_name: String, color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.resource_name = material_name
	material.albedo_color = color
	material.roughness = 0.88
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_HASH
	return material


static func _region_bounds_xz(tile_data_list: Array[RegionTileData]) -> Rect2:
	var has_bounds: bool = false
	var min_x: float = 0.0
	var min_z: float = 0.0
	var max_x: float = 0.0
	var max_z: float = 0.0
	for tile_data in tile_data_list:
		var tile_min_x: float = float(tile_data.cell.x) * tile_data.tile_size_m
		var tile_min_z: float = float(tile_data.cell.y) * tile_data.tile_size_m
		var tile_max_x: float = tile_min_x + tile_data.tile_size_m
		var tile_max_z: float = tile_min_z + tile_data.tile_size_m
		if not has_bounds:
			min_x = tile_min_x
			min_z = tile_min_z
			max_x = tile_max_x
			max_z = tile_max_z
			has_bounds = true
		else:
			min_x = minf(min_x, tile_min_x)
			min_z = minf(min_z, tile_min_z)
			max_x = maxf(max_x, tile_max_x)
			max_z = maxf(max_z, tile_max_z)
	if not has_bounds:
		return Rect2()
	return Rect2(Vector2(min_x, min_z), Vector2(maxf(max_x - min_x, 0.0), maxf(max_z - min_z, 0.0)))


static func _tile_data_by_cell(tile_data_list: Array[RegionTileData]) -> Dictionary[Vector2i, RegionTileData]:
	var tile_data_by_cell: Dictionary[Vector2i, RegionTileData] = {}
	for tile_data in tile_data_list:
		tile_data_by_cell[tile_data.cell] = tile_data
	return tile_data_by_cell


static func _height_at_region_xz(tile_data_by_cell: Dictionary[Vector2i, RegionTileData], world_x: float, world_z: float) -> float:
	var tile_data: RegionTileData = _tile_data_for_region_xz(tile_data_by_cell, world_x, world_z)
	if tile_data == null:
		return 0.0
	var local_x: float = clampf(world_x - float(tile_data.cell.x) * tile_data.tile_size_m, 0.0, tile_data.tile_size_m)
	var local_z: float = clampf(world_z - float(tile_data.cell.y) * tile_data.tile_size_m, 0.0, tile_data.tile_size_m)
	var col: int = int(floor(local_x / tile_data.tile_size_m * float(tile_data.width - 1) + 0.5))
	var row: int = int(floor(local_z / tile_data.tile_size_m * float(tile_data.depth - 1) + 0.5))
	return _height_value_at(tile_data, col, row)


static func _surface_id_value_at_region_xz(tile_data_by_cell: Dictionary[Vector2i, RegionTileData], world_x: float, world_z: float) -> int:
	var tile_data: RegionTileData = _tile_data_for_region_xz(tile_data_by_cell, world_x, world_z)
	if tile_data == null or tile_data.surface_image == null:
		return 0
	var local_x: float = clampf(world_x - float(tile_data.cell.x) * tile_data.tile_size_m, 0.0, tile_data.tile_size_m)
	var local_z: float = clampf(world_z - float(tile_data.cell.y) * tile_data.tile_size_m, 0.0, tile_data.tile_size_m)
	var col: int = int(floor(local_x / tile_data.tile_size_m * float(tile_data.surface_image.get_width() - 1) + 0.5))
	var row: int = int(floor(local_z / tile_data.tile_size_m * float(tile_data.surface_image.get_height() - 1) + 0.5))
	return _surface_id_value_at(tile_data, col, row)


static func _tile_data_for_region_xz(tile_data_by_cell: Dictionary[Vector2i, RegionTileData], world_x: float, world_z: float) -> RegionTileData:
	var tile_size_m: float = GameConfig.STREAM_TILE_SIZE_M
	var cell: Vector2i = Vector2i(int(floor(world_x / tile_size_m)), int(floor(world_z / tile_size_m)))
	if tile_data_by_cell.has(cell):
		return tile_data_by_cell[cell]
	return null


static func _foliage_density_for_surface_value(surface_id_value: int) -> float:
	var surface_id: StringName = _surface_id_for_value(surface_id_value)
	if surface_id == &"packed_dirt" or surface_id == &"tall_grass":
		return 1.0
	if surface_id == &"loose_rock":
		return 0.55
	if surface_id == &"mud":
		return 0.36
	return 0.0


static func _region_foliage_unit(cell: Vector2i, lod_index: int, instance_index: int, salt: int) -> float:
	var value: int = (
		cell.x * REGION_FOLIAGE_CELL_X_MULTIPLIER
		+ cell.y * REGION_FOLIAGE_CELL_Z_MULTIPLIER
		+ instance_index * REGION_FOLIAGE_INSTANCE_MULTIPLIER
		+ lod_index * REGION_FOLIAGE_LOD_MULTIPLIER
		+ salt * REGION_FOLIAGE_SALT_MULTIPLIER
	) % REGION_FOLIAGE_PATTERN_MODULUS
	if value < 0:
		value += REGION_FOLIAGE_PATTERN_MODULUS
	return float(value) / float(REGION_FOLIAGE_PATTERN_MODULUS - 1)


static func _add_visual_tile(parent: Node3D, tile_index: Vector2i, tile_path: String, tile_array_index: int) -> void:
	if tile_path.is_empty():
		push_error("Terrain visual tile path is empty for tile " + str(tile_index))
		return
	var tile_scene: PackedScene = load(tile_path) as PackedScene
	if tile_scene == null:
		push_error("Terrain visual tile failed to load: " + tile_path)
		return
	var tile: Node3D = tile_scene.instantiate() as Node3D
	if tile == null:
		push_error("Terrain visual tile did not instantiate as Node3D: " + tile_path)
		return
	tile.name = visual_tile_node_name(tile_index, tile_path, tile_array_index)
	tile.set_meta(TILE_INDEX_META, tile_index)
	tile.set_meta(TILE_PATH_META, tile_path)
	parent.add_child(tile)
	_apply_surface_visuals(tile)


static func _safe_node_name(value: String) -> String:
	var safe_name: String = value.replace("/", "_")
	safe_name = safe_name.replace("\\", "_")
	safe_name = safe_name.replace(":", "_")
	safe_name = safe_name.replace(" ", "_")
	safe_name = safe_name.replace(".", "_")
	if safe_name.is_empty():
		return "tile"
	return safe_name


static func _apply_surface_visuals(parent: Node) -> void:
	var mesh_instance: MeshInstance3D = parent as MeshInstance3D
	if mesh_instance != null:
		_apply_surface_visuals_to_mesh(mesh_instance)
	for child in parent.get_children():
		_apply_surface_visuals(child)


static func apply_track_texture(parent: Node, track_texture: Texture2D, bounds_min: Vector2, bounds_max: Vector2) -> void:
	if track_texture == null:
		return
	var mesh_instance: MeshInstance3D = parent as MeshInstance3D
	if mesh_instance != null:
		_apply_track_texture_to_mesh(mesh_instance, track_texture, bounds_min, bounds_max)
	for child in parent.get_children():
		apply_track_texture(child, track_texture, bounds_min, bounds_max)


static func _apply_surface_visuals_to_mesh(mesh_instance: MeshInstance3D) -> void:
	var mesh: Mesh = mesh_instance.mesh
	if mesh == null:
		return
	mesh_instance.visibility_range_end = GameConfig.vis_range_terrain
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
	var visual_id: StringName = visual_def.get("id")
	if _terrain_material_cache.has(visual_id):
		return _terrain_material_cache[visual_id]
	var material: StandardMaterial3D = StandardMaterial3D.new()
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
	_apply_height_mapping(material, visual_def)
	_terrain_material_cache[visual_id] = material
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


static func _apply_height_mapping(material: StandardMaterial3D, visual_def: Resource) -> void:
	material.heightmap_enabled = false
	if not GameConfig.terrain_pom_enabled:
		return
	var height_texture_path: String = visual_def.get("height_texture_path")
	if height_texture_path.is_empty():
		height_texture_path = DETAIL_MASK_TEXTURE_PATH
	var height_texture: Texture2D = _load_texture(height_texture_path)
	if height_texture == null:
		return
	var use_visual_height_values: bool = bool(visual_def.get("heightmap_enabled"))
	var height_scale: float = GameConfig.terrain_pom_depth_scale
	var min_layers: int = GameConfig.terrain_pom_min_layers
	var max_layers: int = GameConfig.terrain_pom_max_layers
	if use_visual_height_values:
		var visual_height_scale: float = float(visual_def.get("height_scale"))
		if visual_height_scale > 0.0:
			height_scale = visual_height_scale
		min_layers = int(visual_def.get("height_min_layers"))
		max_layers = int(visual_def.get("height_max_layers"))
	if max_layers < min_layers:
		max_layers = min_layers
	material.heightmap_enabled = height_scale > 0.0
	material.heightmap_texture = height_texture
	material.heightmap_scale = maxf(height_scale, 0.0)
	material.heightmap_deep_parallax = true
	material.heightmap_min_layers = maxi(min_layers, 1)
	material.heightmap_max_layers = maxi(max_layers, material.heightmap_min_layers)


static func _apply_track_texture_to_mesh(mesh_instance: MeshInstance3D, track_texture: Texture2D, bounds_min: Vector2, bounds_max: Vector2) -> void:
	var mesh: Mesh = mesh_instance.mesh
	if mesh == null:
		return
	for surface_index in range(mesh.get_surface_count()):
		var material: StandardMaterial3D = mesh_instance.get_surface_override_material(surface_index) as StandardMaterial3D
		if material == null:
			continue
		material = material.duplicate() as StandardMaterial3D
		if material == null:
			continue
		material.next_pass = _track_overlay_material(material.resource_name, track_texture, bounds_min, bounds_max)
		mesh_instance.set_surface_override_material(surface_index, material)


static func _track_overlay_material(material_name: String, track_texture: Texture2D, bounds_min: Vector2, bounds_max: Vector2) -> ShaderMaterial:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.resource_name = material_name + "_track_overlay"
	material.shader = TerrainTrackOverlayShader
	material.set_shader_parameter(TRACK_RT_UNIFORM, track_texture)
	material.set_shader_parameter(TRACK_BOUNDS_MIN_UNIFORM, bounds_min)
	material.set_shader_parameter(TRACK_BOUNDS_MAX_UNIFORM, bounds_max)
	material.set_shader_parameter(TRACK_DARKENING_UNIFORM, clampf(GameConfig.terrain_track_stamp_strength, 0.0, 1.0))
	material.set_shader_parameter(RUT_DARKENING_UNIFORM, clampf(GameConfig.terrain_track_stamp_strength * RUT_DARKENING_SCALE, 0.0, 1.0))
	return material


static func _load_texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
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
