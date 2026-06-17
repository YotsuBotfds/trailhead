class_name TerrainVisualBuilder
extends Node3D

const CedarTerrainDef: Resource = preload("res://data/terrain/cedar_hollow_terrain_def.tres")
const TerrainSurfacePaletteResource: Resource = preload("res://data/surface_palettes/cedar_hollow_zion_surface_palette.tres")
const SurfaceVisualCatalogResource: Resource = preload("res://data/surface_visuals/cedar_hollow_surface_visuals.tres")
const TerrainTrackOverlayShader: Shader = preload("res://systems/render/terrain_track_overlay.gdshader")
const TerrainSurfaceIndexShader: Shader = preload("res://systems/render/terrain_surface_index.gdshader")
const GrassShader: Shader = preload("res://systems/render/grass_billboard.gdshader")
const DETAIL_MASK_TEXTURE_PATH: String = "res://assets/textures/surface_visuals/generated/terrain_detail_mask.png"
const GENERATED_SURFACE_TEXTURE_DIR: String = "res://assets/textures/surface_visuals/generated/"
const TEXTURE_SOURCE_PATH_META: StringName = &"trailhead_source_path"

static var _terrain_material_cache: Dictionary[StringName, StandardMaterial3D] = {}
static var _foliage_mesh_cache: Dictionary[int, Mesh] = {}
static var _foliage_material_cache: Dictionary[int, Material] = {}
static var _surface_index_albedo_array_cache: Texture2DArray = null

const REGION_ID_META: StringName = &"trailhead_region_id"
const REGION_LOD_META: StringName = &"trailhead_region_lod"
const VISIBILITY_RADIUS_META: StringName = &"trailhead_visibility_radius"
const TILE_INDEX_META: StringName = &"trailhead_tile_index"
const TILE_PATH_META: StringName = &"trailhead_visual_tile_path"
const TILE_SURFACE_ID_PATH_META: StringName = &"trailhead_surface_id_path"
const HEIGHTMESH_NAME: String = "cedar_hollow_heightmesh"
const TERRAIN_TILE_NAME_PREFIX: String = "terrain_visual_tile_"
const TERRAIN_MATERIAL_PREFIX: String = "terrain_mat_"
const TERRAIN_INDEX_MATERIAL_NAME: String = "terrain_surface_index_material"
const SPIKE_1KM_REGION_ID: String = "spike_1km"
const SPIKE_1KM_SCENE_ROOT_NAME: String = "Spike1KmRegion"
const REGION_ROOT_NAME: String = "TerrainVisuals"
const REGION_DETAIL_ROOT_NAME: String = "TerrainDetailTiles"
const REGION_HLOD_NAME: String = "TerrainHLOD"
const REGION_HLOD_TILE_NAME_PREFIX: String = "TerrainHLODTile"
const REGION_FOLIAGE_ROOT_NAME: String = "FoliageCells"
const REGION_STREAMED_FOLIAGE_ROOT_NAME: String = "StreamedFoliageCells"
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
const REGION_STREAM_HLOD_SAMPLE_STEP: int = 20
const REGION_VERTEX_KEY_CELL_OFFSET: int = 32768
const REGION_VERTEX_KEY_CELL_STRIDE: int = 65536
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
const SURFACE_ID_TEXTURE_UNIFORM: StringName = &"surface_id_texture"
const CONTROL_ORIGIN_XZ_UNIFORM: StringName = &"control_origin_xz"
const CONTROL_SIZE_XZ_UNIFORM: StringName = &"control_size_xz"
const TERRAIN_ROUGHNESS_UNIFORM: StringName = &"terrain_roughness"
const TERRAIN_SPECULAR_UNIFORM: StringName = &"terrain_specular"
const ALBEDO_ARRAY_UNIFORM: StringName = &"albedo_array"
const USE_ALBEDO_ARRAY_UNIFORM: StringName = &"use_albedo_array"
const ZION_SANDSTONE_COLOR_UNIFORM: StringName = &"zion_sandstone_color"
const ZION_SAND_COLOR_UNIFORM: StringName = &"zion_sand_color"
const ZION_STRATA_DARK_COLOR_UNIFORM: StringName = &"zion_strata_dark_color"
const ZION_SANDSTONE_SLOPE_START_UNIFORM: StringName = &"zion_sandstone_slope_start"
const ZION_SANDSTONE_SLOPE_END_UNIFORM: StringName = &"zion_sandstone_slope_end"
const ZION_SAND_HEIGHT_START_UNIFORM: StringName = &"zion_sand_height_start"
const ZION_SAND_HEIGHT_END_UNIFORM: StringName = &"zion_sand_height_end"
const ZION_STRATA_SCALE_UNIFORM: StringName = &"zion_strata_scale"
const ZION_STRATA_STRENGTH_UNIFORM: StringName = &"zion_strata_strength"
const ZION_DETILE_STRENGTH_UNIFORM: StringName = &"zion_detile_strength"
const SURFACE_UV_SCALE_UNIFORM_PREFIX: String = "surface_uv_scale_"


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
	var vertex_indices: Dictionary[int, int] = {}


class MeshSurfaceData:
	var surface_id_value: int = 0
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var indices: PackedInt32Array = PackedInt32Array()
	var use_surface_index_material: bool = false
	var surface_id_path: String = ""
	var control_origin_xz: Vector2 = Vector2.ZERO
	var control_size_xz: Vector2 = Vector2.ONE


class RegionMeshData:
	var resource_name: String = ""
	var surfaces: Array[MeshSurfaceData] = []


class RegionVisualTileData:
	var ok: bool = false
	var cell: Vector2i = Vector2i.ZERO
	var node_name: String = ""
	var position: Vector3 = Vector3.ZERO
	var mesh_data: RegionMeshData = null
	var visibility_range_end: float = 0.0
	var visibility_radius: float = 0.0
	var heightmap_path: String = ""
	var surface_id_path: String = ""
	var message: String = ""


class FoliageCellData:
	var lod_index: int = 0
	var node_name: String = ""
	var position: Vector3 = Vector3.ZERO
	var custom_aabb: AABB = AABB()
	var visibility_range_begin: float = 0.0
	var visibility_range_end: float = 0.0
	var visibility_radius: float = 0.0
	var cast_shadow: int = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var transforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	var custom_data: Array[Color] = []


class RegionFoliageTileData:
	var ok: bool = false
	var cell: Vector2i = Vector2i.ZERO
	var cells: Array[FoliageCellData] = []
	var message: String = ""


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
	_add_region_stream_hlod(root, region_id)
	var detail_root: Node3D = Node3D.new()
	detail_root.name = REGION_DETAIL_ROOT_NAME
	detail_root.set_meta(REGION_ID_META, region_id)
	root.add_child(detail_root)
	var foliage_root: Node3D = Node3D.new()
	foliage_root.name = REGION_STREAMED_FOLIAGE_ROOT_NAME
	foliage_root.set_meta(REGION_ID_META, region_id)
	root.add_child(foliage_root)
	return root


static func add_region_visual_tile(parent: Node3D, region_id: String, cell: Vector2i) -> MeshInstance3D:
	var visual_tile_data: RegionVisualTileData = build_region_visual_tile_data(region_id, cell)
	return region_visual_tile_from_data(parent, visual_tile_data, null)


static func build_region_visual_tile_data(region_id: String, cell: Vector2i) -> RegionVisualTileData:
	var visual_tile_data: RegionVisualTileData = RegionVisualTileData.new()
	visual_tile_data.cell = cell

	var tile_data: RegionTileData = _load_region_tile(region_id, cell)
	if tile_data == null:
		visual_tile_data.message = "visual tile failed to load: " + region_id + " " + str(cell)
		return visual_tile_data

	var tile_origin_xz: Vector2 = _tile_origin_xz(tile_data)
	visual_tile_data.node_name = region_detail_tile_node_name(region_id, tile_data.cell)
	visual_tile_data.position = Vector3(tile_origin_xz.x, 0.0, tile_origin_xz.y)
	visual_tile_data.mesh_data = build_region_surface_index_mesh_data(tile_data, REGION_DETAIL_SAMPLE_STEP, tile_data.key + "_terrain_detail_mesh", tile_origin_xz)
	visual_tile_data.visibility_range_end = _detail_visibility_range_end(tile_data)
	visual_tile_data.visibility_radius = _tile_visibility_radius(tile_data)
	visual_tile_data.heightmap_path = tile_data.heightmap_path
	visual_tile_data.surface_id_path = tile_data.surface_id_path
	visual_tile_data.ok = visual_tile_data.mesh_data != null and visual_tile_data.mesh_data.surfaces.size() > 0
	if not visual_tile_data.ok:
		visual_tile_data.message = "visual tile mesh had no surfaces: " + region_id + " " + str(cell)
	return visual_tile_data


static func region_visual_tile_from_data(parent: Node3D, visual_tile_data: RegionVisualTileData, _hlod_instance: MeshInstance3D) -> MeshInstance3D:
	if visual_tile_data == null or not visual_tile_data.ok or visual_tile_data.mesh_data == null:
		return null
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = visual_tile_data.node_name
	instance.position = visual_tile_data.position
	instance.mesh = region_mesh_from_data(visual_tile_data.mesh_data)
	instance.visibility_range_end = visual_tile_data.visibility_range_end
	instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	instance.set_meta(REGION_LOD_META, "detail")
	instance.set_meta(VISIBILITY_RADIUS_META, visual_tile_data.visibility_radius)
	instance.set_meta(TILE_INDEX_META, visual_tile_data.cell)
	instance.set_meta(TILE_PATH_META, visual_tile_data.heightmap_path)
	instance.set_meta(TILE_SURFACE_ID_PATH_META, visual_tile_data.surface_id_path)
	parent.add_child(instance)
	return instance


static func build_region_foliage_tile_data(region_id: String, cell: Vector2i) -> RegionFoliageTileData:
	var foliage_tile_data: RegionFoliageTileData = RegionFoliageTileData.new()
	foliage_tile_data.cell = cell

	var tile_data: RegionTileData = _load_region_tile(region_id, cell)
	if tile_data == null:
		foliage_tile_data.message = "foliage tile failed to load: " + region_id + " " + str(cell)
		return foliage_tile_data

	var tile_data_by_cell: Dictionary[Vector2i, RegionTileData] = {cell: tile_data}
	var tile_min_x: float = float(cell.x) * tile_data.tile_size_m
	var tile_min_z: float = float(cell.y) * tile_data.tile_size_m
	var cell_count_x: int = int(ceil(tile_data.tile_size_m / REGION_FOLIAGE_CELL_SIZE_M))
	var cell_count_z: int = int(ceil(tile_data.tile_size_m / REGION_FOLIAGE_CELL_SIZE_M))
	for cell_z in range(cell_count_z):
		for cell_x in range(cell_count_x):
			var cell_min_x: float = tile_min_x + float(cell_x) * REGION_FOLIAGE_CELL_SIZE_M
			var cell_min_z: float = tile_min_z + float(cell_z) * REGION_FOLIAGE_CELL_SIZE_M
			var cell_max_x: float = minf(cell_min_x + REGION_FOLIAGE_CELL_SIZE_M, tile_min_x + tile_data.tile_size_m)
			var cell_max_z: float = minf(cell_min_z + REGION_FOLIAGE_CELL_SIZE_M, tile_min_z + tile_data.tile_size_m)
			var cell_rect: Rect2 = Rect2(
				Vector2(cell_min_x, cell_min_z),
				Vector2(maxf(cell_max_x - cell_min_x, 0.0), maxf(cell_max_z - cell_min_z, 0.0))
			)
			var foliage_cell: Vector2i = Vector2i(cell.x * 1000 + cell_x, cell.y * 1000 + cell_z)
			var lod0_data: FoliageCellData = _build_region_foliage_cell_data(tile_data_by_cell, cell_rect, foliage_cell, 0, REGION_FOLIAGE_LOD0_BASE_COUNT)
			if lod0_data != null:
				foliage_tile_data.cells.append(lod0_data)
			var lod1_data: FoliageCellData = _build_region_foliage_cell_data(tile_data_by_cell, cell_rect, foliage_cell, 1, REGION_FOLIAGE_LOD1_BASE_COUNT)
			if lod1_data != null:
				foliage_tile_data.cells.append(lod1_data)

	foliage_tile_data.ok = true
	return foliage_tile_data


static func region_foliage_tile_from_data(parent: Node3D, foliage_tile_data: RegionFoliageTileData) -> Node3D:
	if foliage_tile_data == null or not foliage_tile_data.ok:
		return null
	var tile_root: Node3D = Node3D.new()
	tile_root.name = "foliage_tile_" + str(foliage_tile_data.cell.x) + "_" + str(foliage_tile_data.cell.y)
	tile_root.set_meta(TILE_INDEX_META, foliage_tile_data.cell)
	for cell_data in foliage_tile_data.cells:
		_add_foliage_cell_from_data(tile_root, cell_data)
	parent.add_child(tile_root)
	return tile_root


static func visual_tile_node_name(tile_index: Vector2i, tile_path: String, tile_array_index: int) -> String:
	var base_name: String = tile_path.get_file().get_basename()
	if base_name.is_empty():
		base_name = HEIGHTMESH_NAME + "_" + str(tile_array_index)
	return TERRAIN_TILE_NAME_PREFIX + str(tile_index.x) + "_" + str(tile_index.y) + "_" + _safe_node_name(base_name)


static func region_detail_tile_node_name(region_id: String, tile_index: Vector2i) -> String:
	return "region_" + _safe_node_name(region_id) + "_detail_tile_" + str(tile_index.x) + "_" + str(tile_index.y)


static func _region_stream_hlod_tile_node_name(region_id: String, tile_index: Vector2i) -> String:
	return REGION_HLOD_TILE_NAME_PREFIX + "_" + _safe_node_name(region_id) + "_" + str(tile_index.x) + "_" + str(tile_index.y)


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
	_append_pipeline_warmup_surface(mesh, _surface_index_warmup_material(), material_count)
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
	var lod0_mesh: Mesh = _region_foliage_mesh_for_lod(0)
	var lod0_material: Material = _region_foliage_material_for_lod(0)
	_add_foliage_pipeline_warmup_instance(parent, REGION_PIPELINE_WARMUP_FOLIAGE_LOD0_NAME, lod0_mesh, lod0_material)
	var lod1_mesh: Mesh = _region_foliage_mesh_for_lod(1)
	var lod1_material: Material = _region_foliage_material_for_lod(1)
	_add_foliage_pipeline_warmup_instance(parent, REGION_PIPELINE_WARMUP_FOLIAGE_LOD1_NAME, lod1_mesh, lod1_material)
	return 2


static func _add_foliage_pipeline_warmup_instance(parent: Node3D, instance_name: String, mesh: Mesh, material: Material) -> void:
	var multimesh: MultiMesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = mesh
	multimesh.instance_count = 1
	multimesh.set_instance_transform(0, Transform3D(Basis.IDENTITY, Vector3.ZERO))
	multimesh.set_instance_color(0, Color.WHITE)
	multimesh.set_instance_custom_data(0, Color(0.8, 0.25, 0.65, 0.4))

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


static func _add_region_stream_hlod(parent: Node3D, region_id: String) -> MeshInstance3D:
	var manifest_path: String = _region_manifest_path(region_id)
	var manifest: Dictionary = _load_json_dictionary(manifest_path)
	if manifest.is_empty():
		push_error("TerrainVisualBuilder region manifest failed to load for stream HLOD: " + manifest_path)
		return null
	var tile_cells: Array[Vector2i] = _tile_cells_from_manifest(manifest)
	if tile_cells.is_empty():
		push_error("TerrainVisualBuilder region stream HLOD has no manifest tiles: " + region_id)
		return null
	var tile_data_list: Array[RegionTileData] = _load_region_tiles(region_id, tile_cells)
	if tile_data_list.is_empty():
		push_error("TerrainVisualBuilder region stream HLOD has no loadable render tiles: " + region_id)
		return null

	var root_instance: MeshInstance3D = null
	var root_origin_xz: Vector2 = Vector2.ZERO
	for tile_data_index in range(tile_data_list.size()):
		var tile_data: RegionTileData = tile_data_list[tile_data_index]
		var tile_origin_xz: Vector2 = _tile_origin_xz(tile_data)
		var instance: MeshInstance3D = _region_stream_hlod_chunk(region_id, tile_data, tile_origin_xz)
		if tile_data_index == 0:
			instance.name = REGION_HLOD_NAME
			instance.position = Vector3(tile_origin_xz.x, 0.0, tile_origin_xz.y)
			root_instance = instance
			root_origin_xz = tile_origin_xz
			parent.add_child(instance)
		else:
			instance.position = Vector3(tile_origin_xz.x - root_origin_xz.x, 0.0, tile_origin_xz.y - root_origin_xz.y)
			root_instance.add_child(instance)
	if root_instance != null:
		root_instance.visible = false
	return root_instance


static func _region_stream_hlod_chunk(region_id: String, tile_data: RegionTileData, tile_origin_xz: Vector2) -> MeshInstance3D:
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = _region_stream_hlod_tile_node_name(region_id, tile_data.cell)
	instance.mesh = _build_region_stream_hlod_mesh(tile_data, tile_origin_xz)
	instance.visibility_range_begin = _hlod_visibility_range_begin()
	instance.visibility_range_end = 0.0
	instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	instance.set_meta(REGION_LOD_META, "stream_hlod")
	instance.set_meta(VISIBILITY_RADIUS_META, _tile_visibility_radius(tile_data))
	instance.set_meta(TILE_INDEX_META, tile_data.cell)
	instance.set_meta(TILE_PATH_META, tile_data.heightmap_path)
	instance.set_meta(TILE_SURFACE_ID_PATH_META, tile_data.surface_id_path)
	return instance


static func _build_region_stream_hlod_mesh(tile_data: RegionTileData, local_origin_xz: Vector2) -> ArrayMesh:
	var mesh_data: RegionMeshData = build_region_surface_index_mesh_data(
		tile_data,
		REGION_STREAM_HLOD_SAMPLE_STEP,
		tile_data.key + "_stream_terrain_hlod_mesh",
		local_origin_xz
	)
	return region_mesh_from_data(mesh_data)


static func _dominant_surface_id_value(tile_data_list: Array[RegionTileData]) -> int:
	var counts: Dictionary[int, int] = {}
	for tile_data in tile_data_list:
		if tile_data.surface_image == null or tile_data.surface_image.is_empty():
			continue
		var sample_step_x: int = maxi(tile_data.surface_image.get_width() / 8, 1)
		var sample_step_y: int = maxi(tile_data.surface_image.get_height() / 8, 1)
		for y in range(0, tile_data.surface_image.get_height(), sample_step_y):
			for x in range(0, tile_data.surface_image.get_width(), sample_step_x):
				var surface_id_value: int = _surface_id_value_at(tile_data, x, y)
				counts[surface_id_value] = int(counts.get(surface_id_value, 0)) + 1
	var best_surface_id_value: int = 0
	var best_count: int = -1
	var surface_values: Array[int] = []
	for key in counts.keys():
		surface_values.append(int(key))
	surface_values.sort()
	for surface_id_value in surface_values:
		var count: int = int(counts[surface_id_value])
		if count > best_count:
			best_surface_id_value = surface_id_value
			best_count = count
	return best_surface_id_value


static func _add_region_detail_tile(parent: Node3D, region_id: String, tile_data: RegionTileData, _hlod_instance: MeshInstance3D) -> MeshInstance3D:
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = region_detail_tile_node_name(region_id, tile_data.cell)
	var tile_origin_xz: Vector2 = _tile_origin_xz(tile_data)
	instance.position = Vector3(tile_origin_xz.x, 0.0, tile_origin_xz.y)
	var mesh_data: RegionMeshData = build_region_surface_index_mesh_data(tile_data, REGION_DETAIL_SAMPLE_STEP, tile_data.key + "_terrain_detail_mesh", tile_origin_xz)
	instance.mesh = region_mesh_from_data(mesh_data)
	instance.visibility_range_end = _detail_visibility_range_end(tile_data)
	instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	instance.set_meta(REGION_LOD_META, "detail")
	instance.set_meta(VISIBILITY_RADIUS_META, _tile_visibility_radius(tile_data))
	instance.set_meta(TILE_INDEX_META, tile_data.cell)
	instance.set_meta(TILE_PATH_META, tile_data.heightmap_path)
	instance.set_meta(TILE_SURFACE_ID_PATH_META, tile_data.surface_id_path)
	parent.add_child(instance)
	return instance


static func _build_region_mesh(tile_data_list: Array[RegionTileData], sample_step: int, mesh_name: String, local_origin_xz: Vector2) -> ArrayMesh:
	var mesh_data: RegionMeshData = build_region_mesh_data(tile_data_list, sample_step, mesh_name, local_origin_xz)
	return region_mesh_from_data(mesh_data)


static func build_region_mesh_data(tile_data_list: Array[RegionTileData], sample_step: int, mesh_name: String, local_origin_xz: Vector2) -> RegionMeshData:
	var buckets: Dictionary[int, MeshBucket] = {}
	for tile_data in tile_data_list:
		_append_tile_quads(tile_data, sample_step, buckets, local_origin_xz)

	var mesh_data: RegionMeshData = RegionMeshData.new()
	mesh_data.resource_name = mesh_name
	var surface_values: Array[int] = _sorted_surface_values(buckets)
	for surface_id_value in surface_values:
		var bucket: MeshBucket = buckets[surface_id_value]
		if bucket.indices.size() <= 0:
			continue
		var surface_data: MeshSurfaceData = MeshSurfaceData.new()
		surface_data.surface_id_value = surface_id_value
		surface_data.vertices = bucket.vertices
		surface_data.normals = bucket.normals
		surface_data.uvs = bucket.uvs
		surface_data.indices = bucket.indices
		mesh_data.surfaces.append(surface_data)
	return mesh_data


static func build_region_surface_index_mesh_data(tile_data: RegionTileData, sample_step: int, mesh_name: String, local_origin_xz: Vector2) -> RegionMeshData:
	var bucket: MeshBucket = MeshBucket.new()
	_append_tile_quads_to_bucket(tile_data, sample_step, bucket, local_origin_xz)

	var mesh_data: RegionMeshData = RegionMeshData.new()
	mesh_data.resource_name = mesh_name
	if bucket.indices.size() <= 0:
		return mesh_data
	var surface_data: MeshSurfaceData = MeshSurfaceData.new()
	surface_data.surface_id_value = 0
	surface_data.vertices = bucket.vertices
	surface_data.normals = bucket.normals
	surface_data.uvs = bucket.uvs
	surface_data.indices = bucket.indices
	surface_data.use_surface_index_material = true
	surface_data.surface_id_path = tile_data.surface_id_path
	surface_data.control_origin_xz = Vector2(float(tile_data.cell.x) * tile_data.tile_size_m, float(tile_data.cell.y) * tile_data.tile_size_m)
	surface_data.control_size_xz = Vector2(tile_data.tile_size_m, tile_data.tile_size_m)
	mesh_data.surfaces.append(surface_data)
	return mesh_data


static func region_mesh_from_data(mesh_data: RegionMeshData) -> ArrayMesh:
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.resource_name = mesh_data.resource_name
	for surface_data in mesh_data.surfaces:
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = surface_data.vertices
		arrays[Mesh.ARRAY_NORMAL] = surface_data.normals
		arrays[Mesh.ARRAY_TEX_UV] = surface_data.uvs
		arrays[Mesh.ARRAY_INDEX] = surface_data.indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		if surface_data.use_surface_index_material:
			mesh.surface_set_material(mesh.get_surface_count() - 1, _surface_index_material(surface_data))
		else:
			mesh.surface_set_material(mesh.get_surface_count() - 1, _material_for_surface_value(surface_data.surface_id_value))
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


static func _append_tile_quads_to_bucket(tile_data: RegionTileData, sample_step: int, bucket: MeshBucket, local_origin_xz: Vector2) -> void:
	if tile_data.width <= 1 or tile_data.depth <= 1:
		return
	var safe_step: int = maxi(sample_step, 1)
	var max_col: int = tile_data.width - 1
	var max_row: int = tile_data.depth - 1
	for row in range(0, max_row, safe_step):
		var next_row: int = mini(row + safe_step, max_row)
		for col in range(0, max_col, safe_step):
			var next_col: int = mini(col + safe_step, max_col)
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
	var key: int = _tile_vertex_key(tile_data, col, row)
	if bucket.vertex_indices.has(key):
		return int(bucket.vertex_indices[key])
	var vertex_index: int = bucket.vertices.size()
	bucket.vertex_indices[key] = vertex_index
	var vertex: Vector3 = _tile_vertex(tile_data, col, row, local_origin_xz)
	bucket.vertices.append(vertex)
	bucket.normals.append(_tile_normal(tile_data, col, row))
	bucket.uvs.append(_tile_world_xz(tile_data, col, row))
	return vertex_index


static func _tile_vertex_key(tile_data: RegionTileData, col: int, row: int) -> int:
	var local_key: int = row * tile_data.width + col
	var cell_x_key: int = tile_data.cell.x + REGION_VERTEX_KEY_CELL_OFFSET
	var cell_y_key: int = tile_data.cell.y + REGION_VERTEX_KEY_CELL_OFFSET
	return ((cell_x_key * REGION_VERTEX_KEY_CELL_STRIDE + cell_y_key) * tile_data.width * tile_data.depth) + local_key


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


static func _surface_index_material(surface_data: MeshSurfaceData) -> ShaderMaterial:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.resource_name = TERRAIN_INDEX_MATERIAL_NAME
	material.shader = TerrainSurfaceIndexShader
	var surface_texture: Texture2D = _load_texture(surface_data.surface_id_path)
	if surface_texture != null:
		material.set_shader_parameter(SURFACE_ID_TEXTURE_UNIFORM, surface_texture)
	var albedo_array: Texture2DArray = _surface_index_albedo_array()
	if albedo_array != null:
		material.set_shader_parameter(ALBEDO_ARRAY_UNIFORM, albedo_array)
		material.set_shader_parameter(USE_ALBEDO_ARRAY_UNIFORM, true)
	material.set_shader_parameter(CONTROL_ORIGIN_XZ_UNIFORM, surface_data.control_origin_xz)
	material.set_shader_parameter(CONTROL_SIZE_XZ_UNIFORM, surface_data.control_size_xz)
	material.set_shader_parameter(TERRAIN_ROUGHNESS_UNIFORM, _average_default_surface_roughness())
	material.set_shader_parameter(TERRAIN_SPECULAR_UNIFORM, 0.18)
	_apply_zion_surface_index_tuning(material)
	_apply_surface_index_palette(material)
	return material


static func _surface_index_warmup_material() -> ShaderMaterial:
	var surface_data: MeshSurfaceData = MeshSurfaceData.new()
	surface_data.control_origin_xz = Vector2.ZERO
	surface_data.control_size_xz = Vector2(GameConfig.STREAM_TILE_SIZE_M, GameConfig.STREAM_TILE_SIZE_M)
	return _surface_index_material(surface_data)


static func _apply_surface_index_palette(material: ShaderMaterial) -> void:
	for id_value in range(8):
		var surface_id: StringName = _surface_id_for_value(id_value)
		var visual_def: Resource = SurfaceVisualCatalogResource.call("default_visual_for_surface_id", surface_id)
		var color: Color = Color(0.50, 0.47, 0.38, 1.0)
		if visual_def != null:
			var wetness: float = clampf(float(visual_def.get("wetness")), 0.0, 1.0)
			color = _wet_albedo_color(visual_def.get("albedo_color"), wetness)
			var texture_uv_scale: Vector2 = visual_def.get("texture_uv_scale")
			material.set_shader_parameter(StringName(SURFACE_UV_SCALE_UNIFORM_PREFIX + str(id_value)), texture_uv_scale)
		material.set_shader_parameter(StringName("surface_color_" + str(id_value)), color)


static func _apply_zion_surface_index_tuning(material: ShaderMaterial) -> void:
	material.set_shader_parameter(ZION_SANDSTONE_COLOR_UNIFORM, Color(0.82, 0.42, 0.20, 1.0))
	material.set_shader_parameter(ZION_SAND_COLOR_UNIFORM, Color(0.86, 0.74, 0.54, 1.0))
	material.set_shader_parameter(ZION_STRATA_DARK_COLOR_UNIFORM, Color(0.36, 0.14, 0.08, 1.0))
	material.set_shader_parameter(ZION_SANDSTONE_SLOPE_START_UNIFORM, 0.08)
	material.set_shader_parameter(ZION_SANDSTONE_SLOPE_END_UNIFORM, 0.38)
	material.set_shader_parameter(ZION_SAND_HEIGHT_START_UNIFORM, 1193.0)
	material.set_shader_parameter(ZION_SAND_HEIGHT_END_UNIFORM, 1202.0)
	material.set_shader_parameter(ZION_STRATA_SCALE_UNIFORM, 0.58)
	material.set_shader_parameter(ZION_STRATA_STRENGTH_UNIFORM, 0.48)
	material.set_shader_parameter(ZION_DETILE_STRENGTH_UNIFORM, 0.18)


static func _surface_index_albedo_array() -> Texture2DArray:
	if _surface_index_albedo_array_cache != null:
		return _surface_index_albedo_array_cache
	var target_size: Vector2i = _surface_index_albedo_target_size()
	var images: Array[Image] = []
	for id_value in range(8):
		var image: Image = _surface_index_albedo_image(id_value, target_size)
		if image == null:
			return null
		images.append(image)
	var texture_array: Texture2DArray = Texture2DArray.new()
	var create_error: Error = texture_array.create_from_images(images)
	if create_error != OK:
		push_error("Terrain surface-index albedo array failed to create: " + error_string(create_error))
		return null
	texture_array.resource_name = "terrain_surface_index_albedo_array"
	_surface_index_albedo_array_cache = texture_array
	return _surface_index_albedo_array_cache


static func _surface_index_albedo_target_size() -> Vector2i:
	for id_value in range(8):
		var image: Image = _load_surface_index_source_albedo_image(id_value)
		if image == null:
			continue
		return Vector2i(image.get_width(), image.get_height())
	return Vector2i(4, 4)


static func _surface_index_albedo_image(id_value: int, target_size: Vector2i) -> Image:
	var image: Image = _load_surface_index_source_albedo_image(id_value)
	if image == null:
		image = Image.create(target_size.x, target_size.y, false, Image.FORMAT_RGBA8)
		image.fill(_surface_index_fallback_color(id_value))
	else:
		if image.get_width() != target_size.x or image.get_height() != target_size.y:
			image.resize(target_size.x, target_size.y, Image.INTERPOLATE_LANCZOS)
		image.convert(Image.FORMAT_RGBA8)
	var mip_error: Error = image.generate_mipmaps()
	if mip_error != OK:
		push_error("Terrain surface-index albedo mipmaps failed for layer " + str(id_value) + ": " + error_string(mip_error))
	return image


static func _load_surface_index_source_albedo_image(id_value: int) -> Image:
	var surface_id: StringName = _surface_id_for_value(id_value)
	var visual_def: Resource = SurfaceVisualCatalogResource.call("default_visual_for_surface_id", surface_id)
	if visual_def == null:
		return null
	var albedo_texture_path: String = visual_def.get("albedo_texture_path")
	if albedo_texture_path.is_empty():
		return null
	var image: Image = Image.load_from_file(ProjectSettings.globalize_path(albedo_texture_path))
	if image == null or image.is_empty():
		return null
	return image


static func _surface_index_fallback_color(id_value: int) -> Color:
	var surface_id: StringName = _surface_id_for_value(id_value)
	var visual_def: Resource = SurfaceVisualCatalogResource.call("default_visual_for_surface_id", surface_id)
	if visual_def == null:
		return Color(0.50, 0.47, 0.38, 1.0)
	var wetness: float = clampf(float(visual_def.get("wetness")), 0.0, 1.0)
	return _wet_albedo_color(visual_def.get("albedo_color"), wetness)


static func _average_default_surface_roughness() -> float:
	var roughness_sum: float = 0.0
	var roughness_count: int = 0
	for id_value in range(1, 8):
		var surface_id: StringName = _surface_id_for_value(id_value)
		var visual_def: Resource = SurfaceVisualCatalogResource.call("default_visual_for_surface_id", surface_id)
		if visual_def == null:
			continue
		roughness_sum += _wet_roughness(float(visual_def.get("roughness")), clampf(float(visual_def.get("wetness")), 0.0, 1.0))
		roughness_count += 1
	if roughness_count <= 0:
		return 0.88
	return roughness_sum / float(roughness_count)


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
	var lod0_mesh: Mesh = _region_foliage_mesh_for_lod(0)
	var lod1_mesh: Mesh = _region_foliage_mesh_for_lod(1)
	var lod0_material: Material = _region_foliage_material_for_lod(0)
	var lod1_material: Material = _region_foliage_material_for_lod(1)
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
	var cell_data: FoliageCellData = _build_region_foliage_cell_data(tile_data_by_cell, cell_rect, foliage_cell, lod_index, base_count)
	if cell_data == null:
		return
	_add_foliage_cell_from_data(parent, cell_data, mesh, material)


static func _build_region_foliage_cell_data(tile_data_by_cell: Dictionary[Vector2i, RegionTileData], cell_rect: Rect2, foliage_cell: Vector2i, lod_index: int, base_count: int) -> FoliageCellData:
	if cell_rect.size.x <= 0.0 or cell_rect.size.y <= 0.0:
		return null
	var transforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	var custom_data: Array[Color] = []
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
		var wind_weight: float = 0.45 + _region_foliage_unit(foliage_cell, lod_index, attempt, 8) * 0.55
		var wind_phase: float = _region_foliage_unit(foliage_cell, lod_index, attempt, 9)
		var wind_flutter: float = _region_foliage_unit(foliage_cell, lod_index, attempt, 10)
		var tip_shift: float = _region_foliage_unit(foliage_cell, lod_index, attempt, 11)
		custom_data.append(Color(wind_weight, wind_phase, wind_flutter, tip_shift))

	if transforms.is_empty():
		return null

	var foliage_origin_xz: Vector2 = cell_rect.position + cell_rect.size * 0.5
	var foliage_cell_radius: float = cell_rect.size.length() * 0.5
	var cell_data: FoliageCellData = FoliageCellData.new()
	cell_data.lod_index = lod_index
	cell_data.node_name = "foliage_cell_" + str(foliage_cell.x) + "_" + str(foliage_cell.y) + "_lod" + str(lod_index)
	cell_data.position = Vector3(foliage_origin_xz.x, 0.0, foliage_origin_xz.y)
	cell_data.custom_aabb = AABB(
		Vector3(cell_rect.size.x * -0.5, 0.0, cell_rect.size.y * -0.5),
		Vector3(cell_rect.size.x, REGION_FOLIAGE_LOD1_SCALE.y + REGION_FOLIAGE_Y_OFFSET + 0.1, cell_rect.size.y)
	)
	cell_data.visibility_radius = foliage_cell_radius
	cell_data.transforms = transforms
	cell_data.colors = colors
	cell_data.custom_data = custom_data
	if lod_index == 0:
		cell_data.visibility_range_end = _foliage_lod0_visibility_range_end(foliage_cell_radius)
		cell_data.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	else:
		cell_data.visibility_range_begin = _foliage_lod1_visibility_range_begin(foliage_cell_radius)
		cell_data.visibility_range_end = _foliage_lod1_visibility_range_end(foliage_cell_radius)
		cell_data.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for i in range(cell_data.transforms.size()):
		var transform: Transform3D = cell_data.transforms[i]
		transform.origin.x -= foliage_origin_xz.x
		transform.origin.z -= foliage_origin_xz.y
		cell_data.transforms[i] = transform
	return cell_data


static func _add_foliage_cell_from_data(parent: Node3D, cell_data: FoliageCellData, mesh: Mesh = null, material: Material = null) -> void:
	var instance: MultiMeshInstance3D = MultiMeshInstance3D.new()
	instance.name = cell_data.node_name
	instance.position = cell_data.position
	if mesh == null:
		mesh = _region_foliage_mesh_for_lod(cell_data.lod_index)
	if material == null:
		material = _region_foliage_material_for_lod(cell_data.lod_index)
	instance.material_override = material
	instance.extra_cull_margin = REGION_FOLIAGE_CULL_MARGIN
	instance.visibility_range_begin = cell_data.visibility_range_begin
	instance.visibility_range_end = cell_data.visibility_range_end
	instance.cast_shadow = cell_data.cast_shadow
	instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	instance.set_meta(REGION_LOD_META, "foliage_lod" + str(cell_data.lod_index))
	instance.set_meta(VISIBILITY_RADIUS_META, cell_data.visibility_radius)
	var multimesh: MultiMesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = mesh
	multimesh.custom_aabb = cell_data.custom_aabb
	multimesh.instance_count = cell_data.transforms.size()
	for i in range(cell_data.transforms.size()):
		multimesh.set_instance_transform(i, cell_data.transforms[i])
		multimesh.set_instance_color(i, cell_data.colors[i])
		multimesh.set_instance_custom_data(i, cell_data.custom_data[i])
	instance.multimesh = multimesh
	parent.add_child(instance)


static func _region_foliage_mesh_for_lod(lod_index: int) -> Mesh:
	var safe_lod_index: int = _region_foliage_lod_index(lod_index)
	if _foliage_mesh_cache.has(safe_lod_index):
		return _foliage_mesh_cache[safe_lod_index]
	var mesh: Mesh = _region_foliage_mesh("region_foliage_lod" + str(safe_lod_index) + "_mesh")
	_foliage_mesh_cache[safe_lod_index] = mesh
	return mesh


static func _region_foliage_material_for_lod(lod_index: int) -> Material:
	var safe_lod_index: int = _region_foliage_lod_index(lod_index)
	if _foliage_material_cache.has(safe_lod_index):
		return _foliage_material_cache[safe_lod_index]
	var material_color: Color = REGION_FOLIAGE_LOD0_COLOR
	if safe_lod_index > 0:
		material_color = REGION_FOLIAGE_LOD1_COLOR
	var blade_height_reference: float = REGION_FOLIAGE_LOD0_SCALE.y
	if safe_lod_index > 0:
		blade_height_reference = REGION_FOLIAGE_LOD1_SCALE.y
	var material: Material = _region_foliage_material("region_foliage_lod" + str(safe_lod_index) + "_material", material_color, blade_height_reference)
	_foliage_material_cache[safe_lod_index] = material
	return material


static func _region_foliage_lod_index(lod_index: int) -> int:
	if lod_index <= 0:
		return 0
	return 1


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


static func _region_foliage_material(material_name: String, color: Color, blade_height_reference: float) -> ShaderMaterial:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.resource_name = material_name
	material.shader = GrassShader
	material.set_shader_parameter("blade_base_color", Color(color.r * 0.72, color.g * 0.72, color.b * 0.70, color.a))
	material.set_shader_parameter("blade_tip_color", Color(minf(color.r * 1.28, 1.0), minf(color.g * 1.22, 1.0), minf(color.b * 1.16, 1.0), color.a))
	material.set_shader_parameter("blade_height_reference", blade_height_reference)
	material.set_shader_parameter("wind_strength", 0.035)
	material.set_shader_parameter("wind_speed", 0.75)
	material.set_shader_parameter("wind_time_factor", 0.018)
	material.set_shader_parameter("backlight_color", Color(0.95, 0.74, 0.42, 1.0))
	material.set_shader_parameter("backlight_energy", 0.20)
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
