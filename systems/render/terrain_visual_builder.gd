class_name TerrainVisualBuilder
extends Node3D

class PipelineWarmupRoot:
	extends Node3D

	var release_after_frames: int = 2

	func _ready() -> void:
		call_deferred("_release_after_render_warmup")

	func _release_after_render_warmup() -> void:
		for _frame_index in range(maxi(release_after_frames, 0)):
			if not is_inside_tree():
				return
			await get_tree().process_frame
		queue_free()

const CedarTerrainDef: Resource = preload("res://data/terrain/cedar_hollow_terrain_def.tres")
const TerrainSurfacePaletteResource: Resource = preload("res://data/surface_palettes/cedar_hollow_zion_surface_palette.tres")
const SurfaceVisualCatalogResource: Resource = preload("res://data/surface_visuals/cedar_hollow_surface_visuals.tres")
const TerrainTrackOverlayShader: Shader = preload("res://systems/render/terrain_track_overlay.gdshader")
const TerrainSurfaceIndexShader: Shader = preload("res://systems/render/terrain_surface_index.gdshader")
const GrassShader: Shader = preload("res://systems/render/grass_billboard.gdshader")
const CottonwoodTreeScene: PackedScene = preload("res://assets/models/foliage/cottonwood.glb")
const WillowTreeScene: PackedScene = preload("res://assets/models/foliage/willow.glb")
const JuniperTreeScene: PackedScene = preload("res://assets/models/foliage/juniper.glb")
const YuccaTreeScene: PackedScene = preload("res://assets/models/foliage/yucca.glb")
const DETAIL_MASK_TEXTURE_PATH: String = "res://assets/textures/surface_visuals/generated/terrain_detail_mask.png"
const GENERATED_SURFACE_TEXTURE_DIR: String = "res://assets/textures/surface_visuals/generated/"
const TEXTURE_SOURCE_PATH_META: StringName = &"trailhead_source_path"
const SURFACE_INDEX_LAYER_COUNT: int = 8
const SURFACE_INDEX_ARRAY_CACHE_DIR: String = "user://trailhead/terrain_surface_index_arrays"
const SURFACE_INDEX_ARRAY_CACHE_VERSION: String = "surface-index-array-cache-v2"
const SURFACE_INDEX_ALBEDO_ARRAY_CACHE_KIND: String = "albedo"
const SURFACE_INDEX_NORMAL_ARRAY_CACHE_KIND: String = "normal"
const SURFACE_INDEX_ARRAY_IMAGE_FORMAT_NAME: String = "RGBA8"
const SURFACE_INDEX_ARRAY_RESIZE_FILTER_NAME: String = "LANCZOS"

static var _terrain_material_cache: Dictionary[StringName, StandardMaterial3D] = {}
static var _surface_index_material_cache: Dictionary[String, ShaderMaterial] = {}
static var _surface_index_tile_material_cache: Dictionary[String, ShaderMaterial] = {}
static var _surface_index_tile_material_cache_order: PackedStringArray = PackedStringArray()
static var _foliage_mesh_cache: Dictionary[String, Mesh] = {}
static var _foliage_material_cache: Dictionary[String, Material] = {}
static var _surface_index_albedo_array_cache: Texture2DArray = null
static var _surface_index_normal_array_cache: Texture2DArray = null
static var _surface_index_macro_albedo_cache: Texture2D = null
static var _surface_cache_mutex: Mutex = Mutex.new()
static var _region_tile_data_cache: Dictionary[String, Variant] = {}
static var _region_tile_cache_order: PackedStringArray = PackedStringArray()
static var _region_tile_cache_mutex: Mutex = Mutex.new()

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
const REGION_STREAM_MIDLOD_ROOT_NAME: String = "TerrainMidLODTiles"
const REGION_HLOD_NAME: String = "TerrainHLOD"
const REGION_HLOD_TILE_NAME_PREFIX: String = "TerrainHLODTile"
const REGION_MIDLOD_TILE_NAME_PREFIX: String = "TerrainMidLODTile"
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
const REGION_TILE_DATA_CACHE_CAPACITY: int = 24
const SURFACE_INDEX_TILE_MATERIAL_CACHE_CAPACITY: int = 48
const PIPELINE_WARMUP_TERRAIN_MATERIAL_COUNT_META: StringName = &"trailhead_pipeline_warmup_terrain_material_count"
const PIPELINE_WARMUP_FOLIAGE_LOD_COUNT_META: StringName = &"trailhead_pipeline_warmup_foliage_lod_count"
const PIPELINE_WARMUP_TRANSIENT_META: StringName = &"trailhead_pipeline_warmup_transient"
const PIPELINE_WARMUP_RELEASE_FRAMES_META: StringName = &"trailhead_pipeline_warmup_release_frames"
const PIPELINE_WARMUP_RELEASE_AFTER_FRAMES: int = 2
const HEIGHTMAP_FLOAT_BYTE_SIZE: int = 4
# Detail (near-vehicle) terrain visual sample step. The visual mesh is built by
# striding through the full-resolution collision heightmap; step=5 downsamples
# 5x along each axis (~25x fewer verts) which lets slope tiles wander several cm
# above/below the collision surface the wheels actually touch. Near the vehicle
# that visual/collision mismatch reads as the tires sinking or floating, so the
# active (vehicle-near) tiles use step=1 (full collision resolution) while
# distant/prefetched tiles keep the cheaper step=5. Render-only: the collision
# HeightMapShape3D and heightmap source are untouched (D30/D35).
const REGION_DETAIL_SAMPLE_STEP: int = 5
const REGION_DETAIL_FULLRES_SAMPLE_STEP: int = 1
const REGION_HLOD_SAMPLE_STEP: int = 5
const REGION_STREAM_MIDLOD_SAMPLE_STEP: int = 4
const REGION_STREAM_HLOD_SAMPLE_STEP: int = 20
const REGION_STREAM_MIDLOD_RANGE_END_M: float = 500.0
const REGION_VERTEX_KEY_CELL_OFFSET: int = 32768
const REGION_VERTEX_KEY_CELL_STRIDE: int = 65536
const REGION_FOLIAGE_CELL_SIZE_M: float = 32.0
const REGION_FOLIAGE_LOD0_BASE_COUNT: int = 56
const REGION_FOLIAGE_LOD1_BASE_COUNT: int = 4
const REGION_FOLIAGE_PATTERN_MODULUS: int = 1009
const REGION_FOLIAGE_CELL_X_MULTIPLIER: int = 97
const REGION_FOLIAGE_CELL_Z_MULTIPLIER: int = 193
const REGION_FOLIAGE_INSTANCE_MULTIPLIER: int = 389
const REGION_FOLIAGE_LOD_MULTIPLIER: int = 521
const REGION_FOLIAGE_SALT_MULTIPLIER: int = 61
const REGION_FOLIAGE_MIXED_CELL_X_MULTIPLIER: int = 1103515245
const REGION_FOLIAGE_MIXED_CELL_Z_MULTIPLIER: int = 12345
const REGION_FOLIAGE_MIXED_INSTANCE_MULTIPLIER: int = 2654435761
const REGION_FOLIAGE_MIXED_LOD_MULTIPLIER: int = 1013904223
const REGION_FOLIAGE_MIXED_SALT_MULTIPLIER: int = 374761393
const REGION_FOLIAGE_MIXED_MASK: int = 0x7fffffff
const REGION_FOLIAGE_MIXED_MODULUS: int = 10000
const REGION_FOLIAGE_Y_OFFSET: float = 0.035
const REGION_TERRAIN_SEAM_MAX_SLOPE: float = 7.5
const REGION_TERRAIN_SEAM_MIN_DELTA_M: float = 180.0
const FOLIAGE_MAX_SLOPE_NORMAL_Y: float = 0.819
const FOLIAGE_CELL_MAX_GROUND_DELTA_M: float = 18.0
const REGION_FOLIAGE_CULL_MARGIN: float = 0.08
# Godot 4.6 MultiMesh.buffer stride for TRANSFORM_3D + use_colors + use_custom_data:
# per instance = basis.x, basis.y, basis.z, origin (12) + color (4) + custom_data (4).
const FOLIAGE_MULTIMESH_FLOATS_PER_INSTANCE: int = 20
const REGION_FOLIAGE_LOD0_SCALE: Vector3 = Vector3(0.16, 0.42, 0.16)
const REGION_FOLIAGE_LOD1_SCALE: Vector3 = Vector3(0.42, 0.58, 0.42)
const REGION_FOLIAGE_HEIGHT_SCALE_MAX: float = 1.32
# Matches source-material tree placement: width_scale = 0.84 + unit * 0.34.
const REGION_FOLIAGE_TREE_WIDTH_SCALE_MAX: float = 1.18
const REGION_FOLIAGE_LOD0_COLOR: Color = Color(0.24, 0.38, 0.14, 0.92)
const REGION_FOLIAGE_LOD1_COLOR: Color = Color(0.28, 0.34, 0.16, 0.86)
const FOLIAGE_SPECIES_GRASS: StringName = &"grass"
const FOLIAGE_SPECIES_RIPARIAN_GRASS: StringName = &"riparian_grass"
const FOLIAGE_SPECIES_SHRUB: StringName = &"shrub"
const FOLIAGE_SPECIES_YUCCA: StringName = &"yucca"
const FOLIAGE_SPECIES_JUNIPER: StringName = &"juniper"
const FOLIAGE_SPECIES_WILLOW: StringName = &"willow"
const FOLIAGE_SPECIES_COTTONWOOD: StringName = &"cottonwood"
const FOLIAGE_SPECIES_BOULDER: StringName = &"boulder"
const FOLIAGE_SPECIES_LIST: Array[StringName] = [FOLIAGE_SPECIES_GRASS, FOLIAGE_SPECIES_RIPARIAN_GRASS, FOLIAGE_SPECIES_SHRUB, FOLIAGE_SPECIES_YUCCA, FOLIAGE_SPECIES_JUNIPER, FOLIAGE_SPECIES_WILLOW, FOLIAGE_SPECIES_COTTONWOOD, FOLIAGE_SPECIES_BOULDER]
# Zion foliage identity palette (art-direction bible §2): varied desert-riparian species
# colors, with dusk tints kept muted so the river corridor reads botanical instead of rainbow.
# Species palette calibrated to lower Zion canyon field references (2026-06-24):
#   cottonwood     — warm yellow-green shimmer (Fremont gallery forest, sunlit canopy)
#   willow         — lighter/brighter green than cottonwood (Goodding willow, wet margin)
#   juniper        — blue-grey-green, cool and desaturated (Utah juniper, dry benches)
#   sage           — silvery grey-green, cool (Great Basin sagebrush understory)
#   rabbitbrush    — olive-warm but muted (rubber rabbitbrush, talus + wash edges)
#   yucca          — steel blue-grey-green (sharp blade colour, dry exposed rock)
#   riparian_grass — lusher medium green (wet sedge + rush corridor, river margin)
const FOLIAGE_SPECIES_GRASS_COLOR: Color = Color(0.64, 0.53, 0.25, 0.92)
const FOLIAGE_SPECIES_RIPARIAN_GRASS_COLOR: Color = Color(0.16, 0.32, 0.09, 0.92)
const FOLIAGE_SPECIES_SHRUB_COLOR: Color = Color(0.46, 0.50, 0.39, 0.94)
const FOLIAGE_SHRUB_RABBITBRUSH_COLOR: Color = Color(0.58, 0.56, 0.22, 0.95)
const FOLIAGE_SHRUB_SAGE_COLOR: Color = Color(0.38, 0.44, 0.40, 0.95)
const FOLIAGE_SHRUB_MORMON_TEA_COLOR: Color = Color(0.31, 0.39, 0.27, 0.95)
const FOLIAGE_SPECIES_YUCCA_COLOR: Color = Color(0.28, 0.38, 0.32, 0.95)
const FOLIAGE_SPECIES_JUNIPER_COLOR: Color = Color(0.12, 0.20, 0.17, 0.97)
const FOLIAGE_SPECIES_WILLOW_COLOR: Color = Color(0.20, 0.32, 0.13, 0.95)
const FOLIAGE_SPECIES_COTTONWOOD_COLOR: Color = Color(0.30, 0.44, 0.085, 0.96)
const FOLIAGE_SPECIES_BOULDER_COLOR: Color = Color(0.69, 0.47, 0.31, 1.0)
const FOLIAGE_SPECIES_GRASS_DUSK_TINT: Color = Color(0.76, 0.55, 0.30, 0.92)
const FOLIAGE_SPECIES_RIPARIAN_GRASS_DUSK_TINT: Color = Color(0.22, 0.33, 0.12, 0.92)
const FOLIAGE_SPECIES_SHRUB_DUSK_TINT: Color = Color(0.52, 0.46, 0.34, 0.94)
const FOLIAGE_SPECIES_YUCCA_DUSK_TINT: Color = Color(0.35, 0.40, 0.33, 0.95)
const FOLIAGE_SPECIES_JUNIPER_DUSK_TINT: Color = Color(0.15, 0.20, 0.17, 0.97)
const FOLIAGE_SPECIES_WILLOW_DUSK_TINT: Color = Color(0.25, 0.32, 0.14, 0.95)
const FOLIAGE_SPECIES_COTTONWOOD_DUSK_TINT: Color = Color(0.38, 0.40, 0.11, 0.96)
const FOLIAGE_SPECIES_MATERIAL_DUSK_STRENGTH: float = 0.18
const FOLIAGE_SPECIES_INSTANCE_DUSK_JITTER: float = 0.18
# Lane-D demo triage: keep Zion foliage lush without the graded rim/tips reading neon.
const FOLIAGE_NEON_TAME_TIP_BOOST: Vector3 = Vector3(1.12, 1.08, 1.02)
const FOLIAGE_NEON_TAME_BACKLIGHT_ENERGY: float = 0.10
# Foliage visual-fidelity (fidelity/foliage-shading): travelling-wave wind + per-instance
# tint jitter live in grass_billboard.gdshader. These tune them for the Zion region
# foliage material so the lushness survives without re-reading neon. Wavelengths are in
# metres; 0 disables a band (falls back to the legacy instance-only sway). Jitter
# amplitudes are half-ranges around 1.0, so 0.14 spans [0.86, 1.14] saturation per clump.
const FOLIAGE_WIND_WORLD_WAVELENGTH_PRIMARY: float = 9.0
const FOLIAGE_WIND_WORLD_WAVELENGTH_GUST: float = 23.0
const FOLIAGE_INSTANCE_SATURATION_JITTER: float = 0.14
const FOLIAGE_INSTANCE_VALUE_JITTER: float = 0.10
const FOLIAGE_TREE_REAL_MESH_SCALE: Vector3 = Vector3.ONE
const FOLIAGE_SHRUB_LOD0_SCALE: Vector3 = Vector3(0.90, 1.22, 0.90)
const FOLIAGE_SHRUB_LOD1_SCALE: Vector3 = Vector3(0.86, 0.94, 0.86)
const FOLIAGE_BOULDER_LOD0_SCALE: Vector3 = Vector3(1.0, 1.0, 1.0)
const FOLIAGE_BOULDER_LOD1_SCALE: Vector3 = Vector3(0.82, 0.82, 0.82)
# Boulder/talus enrichment (Zion art-direction bible §1.1, §2.3): real lower Zion carpets
# cliff bases + steep slopes in rock (talus aprons, scattered Navajo boulders, rubble in
# washes) while the dry desert benches stay sparse class-4. Per-instance size runs from
# small rubble through large boulders; each settles at its own attitude and embeds into the
# ground so it sits IN the dirt, not on top. All deterministic (hash by cell+index+salt).
const FOLIAGE_BOULDER_WIDTH_MIN: float = 0.34
const FOLIAGE_BOULDER_WIDTH_MAX: float = 2.15
const FOLIAGE_BOULDER_HEIGHT_MIN: float = 0.28
const FOLIAGE_BOULDER_HEIGHT_MAX: float = 1.36
const FOLIAGE_BOULDER_TILT_MAX_DEG: float = 16.0
const FOLIAGE_BOULDER_GROUND_SINK_MIN_M: float = 0.05
const FOLIAGE_BOULDER_GROUND_SINK_MAX_M: float = 0.15
# Steep-slope talus density boost. Flat ground (normal.y >= FOLIAGE_MAX_SLOPE_NORMAL_Y)
# keeps baseline sparse scatter; steeper ground (cliff bases / talus aprons) ramps up to
# FOLIAGE_BOULDER_TALUS_DENSITY_BOOST so rock piles where the slopes are. Capped so a near-
# vertical wall never forces keep-probability above 1.0.
const FOLIAGE_BOULDER_TALUS_DENSITY_BOOST: float = 3.2
const FOLIAGE_BOULDER_FLAT_DENSITY_MUL: float = 0.35
const FOLIAGE_BOULDER_DENSITY_CAP: float = 0.55
# normal.y floor at which the talus density boost saturates (~70 degrees); below this a
# near-vertical wall holds at the boost ceiling instead of stacking further.
const FOLIAGE_BOULDER_TALUS_STEEP_NORMAL_Y: float = 0.34
# Salts 14-17 stay disjoint from candidate slots 1-13, the bench selector at 18/30,
# and grass-clump salts 20-28.
const FOLIAGE_BOULDER_TILT_AXIS_SALT: int = 14
const FOLIAGE_BOULDER_TILT_SALT: int = 15
const FOLIAGE_BOULDER_KEEP_SALT: int = 16
const FOLIAGE_SURFACE_CLASS_SELECTOR_SALT: int = 17
const FOLIAGE_DENSITY_PACKED_DIRT: float = 0.85
const FOLIAGE_DENSITY_TALL_GRASS: float = 0.78
const FOLIAGE_DENSITY_LOOSE_ROCK: float = 0.03
const FOLIAGE_DENSITY_MUD: float = 0.30
# Distance-LOD fade for foliage. Every foliage MultiMeshInstance3D used to ship with
# VISIBILITY_RANGE_FADE_DISABLED, so foliage popped hard at the streaming/visibility boundary.
# Each species/LOD now self-fades (VISIBILITY_RANGE_FADE_SELF): LOD0 fades out over its end
# margin at the LOD0->LOD1 handoff. Grass/scrub fades out near the ground-detail band; GLB tree
# LOD1 is capped well before cam_far so canyon HLOD carries the far silhouette instead of drawing
# thousands of full meshes into the haze. DEPENDENCIES was ruled out: it requires visibility_parent
# wiring (Node3D.visibility_parent, a fragile cross-node LOD hierarchy) and is Forward+ only.
# Per species: trees (tall, sparse) reach farther and cross-fade slowly; grass (small, dense)
# keeps the existing closer range with a quick fade so distant draw cost stays low; boulders
# sit between. Bases are the LOD0 range before adding the cell radius; margins are the fade width.
const FOLIAGE_VIS_RANGE_BASE_TREE: float = 70.0
const FOLIAGE_VIS_RANGE_BASE_BOULDER: float = 60.0
const FOLIAGE_VIS_RANGE_BASE_GRASS_LOD1_END: float = 60.0
const FOLIAGE_VIS_RANGE_TREE_LOD1_END: float = 650.0
const FOLIAGE_FADE_MARGIN_GRASS: float = 28.0
const FOLIAGE_FADE_MARGIN_TREE: float = 55.0
const FOLIAGE_FADE_MARGIN_BOULDER: float = 35.0
const FOLIAGE_BENCH_SHRUB_SHARE: float = 0.30
const FOLIAGE_BENCH_GRASS_SHARE: float = 0.56
const FOLIAGE_BENCH_JUNIPER_SHARE: float = 0.08
const FOLIAGE_WOODLAND_SHRUB_SHARE: float = 0.24
const FOLIAGE_WOODLAND_GRASS_SHARE: float = 0.46
const FOLIAGE_WOODLAND_JUNIPER_SHARE: float = 0.24
const FOLIAGE_TALUS_SHRUB_SHARE: float = 0.46
const FOLIAGE_TALUS_YUCCA_SHARE: float = 0.38
const FOLIAGE_BENCH_SELECTOR_SALT_A: int = 18
const FOLIAGE_BENCH_SELECTOR_SALT_B: int = 30
# Region-foliage grass/riparian_grass/shrub de-uniforming. The live band read as an even grid of
# identical single crosses ("fence"). These gather accepted grass candidates around deterministic
# clump centers (so instances form tussocks with bare ground between) and add non-uniform per-
# instance scale, a small lean, and hue/value COLOR jitter. Salts are >= 20 to stay disjoint from
# the 1-17 candidate/boulder slots plus the bench selector salts consumed in
# _build_region_foliage_cell_data_with_audit.
const GRASS_CLUMP_ATTEMPTS_PER_CLUMP: int = 4
const GRASS_CLUMP_RADIUS_M: float = 1.6
const GRASS_TILT_MAX_DEG: float = 9.0
const GRASS_HUE_JITTER: float = 0.10
const GRASS_VALUE_JITTER: float = 0.24
const GRASS_MIN_VALUE: float = 0.35
const GRASS_CLUMP_CENTER_SALT_X: int = 20
const GRASS_CLUMP_CENTER_SALT_Z: int = 21
const GRASS_CLUMP_OFFSET_SALT_X: int = 22
const GRASS_WIDTH_Z_SALT: int = 24
const GRASS_TILT_AXIS_SALT: int = 25
const GRASS_TILT_AMOUNT_SALT: int = 26
const GRASS_HUE_SALT: int = 27
const GRASS_VALUE_SALT: int = 28
const RIPARIAN_TREE_MIN_DISTANCE_M: float = 10.0
const RIPARIAN_WILLOW_OUTER_M: float = 28.0
const RIPARIAN_COTTONWOOD_OUTER_M: float = 62.0
const RIPARIAN_GRASS_OUTER_M: float = 130.0
# Fremont cottonwood gallery forest along ZION_RIVER_THALWEG_XZ (Zion art-direction bible §2.1-
# §2.3). The default per-cell accepted-instance cap (REGION_FOLIAGE_LOD0/1_BASE_COUNT) is the
# bottleneck for a gallery read, and the species keep-probabilities (GameConfig.riparian_*_density)
# leave the cottonwood/willow grove thin. Two levers push the green where the river is, both pure
# functions of candidate/cell world position (deterministic -- no Time/randi):
#  1. RIPARIAN_GALLERY_CORE_OUTER_M -- cells whose center is within this distance of the thalweg
#     get a raised accepted-instance cap (_riparian_gallery_base_count) so the cottonwood/willow
#     canopy + lush sedge understory can actually fill in along the river.
#  2. Per-species density multipliers (_riparian_gallery_density_multiplier) that ramp the keep-
#     probability up inside the core and taper back to 1.0 by the fringe, so the corridor reads as
#     a dense gallery with a thinning edge -- a green RIBBON, not a floor-wide blanket. Beyond
#     RIPARIAN_GRASS_OUTER_M the bench selector takes back over; cells outside the core keep the
#     default cap.
const RIPARIAN_GALLERY_CORE_OUTER_M: float = 70.0
const RIPARIAN_GALLERY_LOD0_CORE_BASE_COUNT: int = 44
const RIPARIAN_GALLERY_LOD1_CORE_BASE_COUNT: int = 20
const RIPARIAN_COTTONWOOD_CORE_DENSITY_MUL: float = 1.9
const RIPARIAN_WILLOW_CORE_DENSITY_MUL: float = 2.6
const RIPARIAN_GRASS_CORE_DENSITY_MUL: float = 1.55
const ZION_RIVER_THALWEG_XZ: Array[Vector2] = [
	Vector2(910.0, 500.0),
	Vector2(900.0, 700.0),
	Vector2(920.0, 900.0),
	Vector2(1000.0, 1000.0),
	Vector2(1070.0, 1200.0),
	Vector2(1130.0, 1300.0),
	Vector2(1180.0, 1350.0),
	Vector2(1330.0, 1400.0),
	Vector2(1410.0, 1450.0),
	Vector2(1500.0, 1550.0),
	Vector2(1530.0, 1600.0),
]
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
# C2: per-surface roughness uniform prefix (surface_roughness_0..7). Each surface-id layer
# carries its own catalog roughness so wet/mossy stone shades glossier and loose sand/scree
# matte, instead of the single catalog-averaged terrain_roughness scalar.
const SURFACE_ROUGHNESS_UNIFORM_PREFIX: String = "surface_roughness_"
const ALBEDO_ARRAY_UNIFORM: StringName = &"albedo_array"
const USE_ALBEDO_ARRAY_UNIFORM: StringName = &"use_albedo_array"
const NORMAL_ARRAY_UNIFORM: StringName = &"normal_array"
const USE_NORMAL_ARRAY_UNIFORM: StringName = &"use_normal_array"
const NORMAL_ARRAY_STRENGTH_UNIFORM: StringName = &"normal_array_strength"
const MACRO_ALBEDO_TEXTURE_PATH: String = "res://data/terrain/cedar_hollow_zion_macro_albedo.png"
const MACRO_ALBEDO_TEXTURE_UNIFORM: StringName = &"macro_albedo_texture"
const MACRO_ALBEDO_ORIGIN_XZ_UNIFORM: StringName = &"macro_albedo_origin_xz"
const MACRO_ALBEDO_SIZE_XZ_UNIFORM: StringName = &"macro_albedo_size_xz"
const USE_MACRO_ALBEDO_UNIFORM: StringName = &"use_macro_albedo"
const MACRO_ALBEDO_STRENGTH_UNIFORM: StringName = &"macro_albedo_strength"
const MACRO_ALBEDO_REGION_ORIGIN_XZ: Vector2 = Vector2.ZERO
const MACRO_ALBEDO_REGION_SIZE_XZ: Vector2 = Vector2(5500.0, 5700.0)
const MACRO_ALBEDO_STRENGTH: float = 0.35
const ZION_SANDSTONE_COLOR_UNIFORM: StringName = &"zion_sandstone_color"
const ZION_SAND_COLOR_UNIFORM: StringName = &"zion_sand_color"
const ZION_STRATA_DARK_COLOR_UNIFORM: StringName = &"zion_strata_dark_color"
const ZION_SANDSTONE_SLOPE_START_UNIFORM: StringName = &"zion_sandstone_slope_start"
const ZION_SANDSTONE_SLOPE_END_UNIFORM: StringName = &"zion_sandstone_slope_end"
const ZION_SAND_HEIGHT_START_UNIFORM: StringName = &"zion_sand_height_start"
const ZION_SAND_HEIGHT_END_UNIFORM: StringName = &"zion_sand_height_end"
const ZION_STRATA_SCALE_UNIFORM: StringName = &"zion_strata_scale"
const ZION_STRATA_STRENGTH_UNIFORM: StringName = &"zion_strata_strength"
const ZION_STRATA_LIGHT_COLOR_UNIFORM: StringName = &"zion_strata_light_color"
const ZION_STRATA_DIP_UNIFORM: StringName = &"zion_strata_dip"
const ZION_DETILE_STRENGTH_UNIFORM: StringName = &"zion_detile_strength"
const ZION_FLOOR_DARK_COLOR_UNIFORM: StringName = &"zion_floor_dark_color"
const ZION_FLOOR_SEDIMENT_COLOR_UNIFORM: StringName = &"zion_floor_sediment_color"
const ZION_FLOOR_SCATTER_STRENGTH_UNIFORM: StringName = &"zion_floor_scatter_strength"
const ZION_FLOOR_DETILE_STRENGTH_UNIFORM: StringName = &"zion_floor_detile_strength"
const ZION_RIPARIAN_TINT_COLOR_UNIFORM: StringName = &"zion_riparian_tint_color"
const ZION_RIPARIAN_TINT_STRENGTH_UNIFORM: StringName = &"zion_riparian_tint_strength"
const ZION_RIPARIAN_OUTER_M_UNIFORM: StringName = &"zion_riparian_outer_m"
const ZION_BANK_WET_WIDTH_UNIFORM: StringName = &"zion_bank_wet_width_m"
const ZION_BANK_WET_DARKNESS_UNIFORM: StringName = &"zion_bank_wet_darkness"
const ZION_BANK_WET_ROUGHNESS_UNIFORM: StringName = &"zion_bank_wet_roughness"
const ZION_VARNISH_COLOR_UNIFORM: StringName = &"zion_varnish_color"
const ZION_VARNISH_STRENGTH_UNIFORM: StringName = &"zion_varnish_strength"
const ZION_VARNISH_WALL_THRESHOLD_UNIFORM: StringName = &"zion_varnish_wall_threshold"
const ZION_VARNISH_HEIGHT_START_UNIFORM: StringName = &"zion_varnish_height_start"
const ZION_VARNISH_STREAK_SCALE_UNIFORM: StringName = &"zion_varnish_streak_scale"
const ZION_KAYENTA_COLOR_UNIFORM: StringName = &"zion_kayenta_color"
const ZION_KAYENTA_HEIGHT_START_UNIFORM: StringName = &"zion_kayenta_height_start"
const ZION_KAYENTA_HEIGHT_END_UNIFORM: StringName = &"zion_kayenta_height_end"
const ZION_KAYENTA_STRENGTH_UNIFORM: StringName = &"zion_kayenta_strength"
const ZION_BLEACH_COLOR_UNIFORM: StringName = &"zion_bleach_color"
const ZION_BLEACH_HEIGHT_START_UNIFORM: StringName = &"zion_bleach_height_start"
const ZION_BLEACH_STRENGTH_UNIFORM: StringName = &"zion_bleach_strength"
const ZION_WETROCK_ENABLED_UNIFORM: StringName = &"zion_wetrock_enabled"
const ZION_WETROCK_HEIGHT_START_UNIFORM: StringName = &"zion_wetrock_height_start"
const ZION_WETROCK_HEIGHT_END_UNIFORM: StringName = &"zion_wetrock_height_end"
const ZION_WETROCK_DARKNESS_UNIFORM: StringName = &"zion_wetrock_darkness"
const SURFACE_UV_SCALE_UNIFORM_PREFIX: String = "surface_uv_scale_"
# FLOOR-PBR: triplanar world-space sampling of the real CC0 ambientCG albedo+normal
# arrays onto the drivable floor (see terrain_surface_index.gdshader). Render-only
# tuning; bound explicitly in _apply_zion_surface_index_tuning so the values are
# inspectable and never drift from the shader defaults.
const USE_FLOOR_PBR_UNIFORM: StringName = &"use_floor_pbr"
const FLOOR_PBR_BLEND_UNIFORM: StringName = &"floor_pbr_blend"
const FLOOR_PBR_NORMAL_STRENGTH_UNIFORM: StringName = &"floor_pbr_normal_strength"
const FLOOR_PBR_ROUGHNESS_STRENGTH_UNIFORM: StringName = &"floor_pbr_roughness_strength"
const FLOOR_PBR_UV_SCALE_UNIFORM: StringName = &"floor_pbr_uv_scale"
const FLOOR_PBR_SLICKROCK_SCALE_MUL_UNIFORM: StringName = &"floor_pbr_slickrock_scale_mul"
const FLOOR_PBR_TRIPLANAR_BLEND_UNIFORM: StringName = &"floor_pbr_triplanar_blend"
const FLOOR_PBR_SLOPE_FLAT_NY_UNIFORM: StringName = &"floor_pbr_slope_flat_ny"
const FLOOR_PBR_SLOPE_STEEP_NY_UNIFORM: StringName = &"floor_pbr_slope_steep_ny"
const FLOOR_PBR_HEIGHT_START_OFFSET_UNIFORM: StringName = &"floor_pbr_height_start_offset"
const FLOOR_PBR_HEIGHT_END_OFFSET_UNIFORM: StringName = &"floor_pbr_height_end_offset"
const FLOOR_PBR_SINGLE_PLANE_THRESHOLD_UNIFORM: StringName = &"floor_pbr_single_plane_threshold"
const FLOOR_PBR_ENABLED: bool = true
const FLOOR_PBR_BLEND: float = 0.55
const FLOOR_PBR_NORMAL_STRENGTH: float = 0.50
const FLOOR_PBR_ROUGHNESS_STRENGTH: float = 0.10
const FLOOR_PBR_UV_SCALE: Vector2 = Vector2(0.45, 0.45)
const FLOOR_PBR_SLICKROCK_SCALE_MUL: float = 0.5
const FLOOR_PBR_TRIPLANAR_BLEND: float = 6.0
const FLOOR_PBR_SLOPE_FLAT_NY: float = 0.86
const FLOOR_PBR_SLOPE_STEEP_NY: float = 0.55
const FLOOR_PBR_HEIGHT_START_OFFSET: float = 6.0
const FLOOR_PBR_HEIGHT_END_OFFSET: float = 22.0
const FLOOR_PBR_SINGLE_PLANE_THRESHOLD: float = 0.90


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
	var surface_id_texture: Texture2D = null
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
	var mesh: ArrayMesh = null
	var visibility_range_end: float = 0.0
	var visibility_radius: float = 0.0
	var heightmap_path: String = ""
	var surface_id_path: String = ""
	var message: String = ""


class RegionStreamLODTileData:
	var ok: bool = false
	var cell: Vector2i = Vector2i.ZERO
	var node_name: String = ""
	var position: Vector3 = Vector3.ZERO
	var mesh_data: RegionMeshData = null
	var mesh: ArrayMesh = null
	var visibility_range_begin: float = 0.0
	var visibility_range_end: float = 0.0
	var visibility_radius: float = 0.0
	var heightmap_path: String = ""
	var surface_id_path: String = ""
	var lod_meta: String = ""
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
	var species: Array[FoliageSpeciesCellData] = []


class FoliageSpeciesCellData:
	var species_id: StringName = &""
	var transforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	var custom_data: Array[Color] = []
	var packed_buffer: PackedFloat32Array = PackedFloat32Array()
	var multimesh: MultiMesh = null


class RegionFoliageTileData:
	var ok: bool = false
	var cell: Vector2i = Vector2i.ZERO
	var position: Vector3 = Vector3.ZERO
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
	add_region_stream_hlod_root(root, region_id)
	var midlod_root: Node3D = Node3D.new()
	midlod_root.name = REGION_STREAM_MIDLOD_ROOT_NAME
	midlod_root.set_meta(REGION_ID_META, region_id)
	root.add_child(midlod_root)
	var detail_root: Node3D = Node3D.new()
	detail_root.name = REGION_DETAIL_ROOT_NAME
	detail_root.set_meta(REGION_ID_META, region_id)
	root.add_child(detail_root)
	var foliage_root: Node3D = Node3D.new()
	foliage_root.name = REGION_STREAMED_FOLIAGE_ROOT_NAME
	foliage_root.set_meta(REGION_ID_META, region_id)
	root.add_child(foliage_root)
	return root


static func add_region_stream_hlod_root(parent: Node3D, region_id: String) -> MeshInstance3D:
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = REGION_HLOD_NAME
	instance.visible = false
	instance.visibility_range_begin = _stream_hlod_visibility_range_begin()
	instance.visibility_range_end = 0.0
	instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.set_meta(REGION_LOD_META, "stream_hlod_root")
	instance.set_meta(REGION_ID_META, region_id)
	parent.add_child(instance)
	return instance


static func add_region_visual_tile(parent: Node3D, region_id: String, cell: Vector2i) -> MeshInstance3D:
	var visual_tile_data: RegionVisualTileData = build_region_visual_tile_data(region_id, cell)
	return region_visual_tile_from_data(parent, visual_tile_data, null)


static func build_region_visual_tile_data(region_id: String, cell: Vector2i, sample_step: int = REGION_DETAIL_SAMPLE_STEP) -> RegionVisualTileData:
	var visual_tile_data: RegionVisualTileData = RegionVisualTileData.new()
	visual_tile_data.cell = cell

	var tile_data: RegionTileData = _load_region_tile(region_id, cell)
	if tile_data == null:
		visual_tile_data.message = "visual tile failed to load: " + region_id + " " + str(cell)
		return visual_tile_data

	var effective_step: int = maxi(sample_step, 1)
	var tile_origin_xz: Vector2 = _tile_origin_xz(tile_data)
	visual_tile_data.node_name = region_detail_tile_node_name(region_id, tile_data.cell)
	visual_tile_data.position = Vector3(tile_origin_xz.x, 0.0, tile_origin_xz.y)
	visual_tile_data.mesh_data = build_region_surface_index_mesh_data(tile_data, effective_step, tile_data.key + "_terrain_detail_mesh", tile_origin_xz)
	if visual_tile_data.mesh_data != null and visual_tile_data.mesh_data.surfaces.size() > 0:
		visual_tile_data.mesh = region_mesh_from_data(visual_tile_data.mesh_data, false)
	visual_tile_data.visibility_range_end = _detail_visibility_range_end(tile_data)
	visual_tile_data.visibility_radius = _tile_visibility_radius(tile_data)
	visual_tile_data.heightmap_path = tile_data.heightmap_path
	visual_tile_data.surface_id_path = tile_data.surface_id_path
	visual_tile_data.ok = visual_tile_data.mesh_data != null and visual_tile_data.mesh != null and visual_tile_data.mesh_data.surfaces.size() > 0
	if not visual_tile_data.ok:
		visual_tile_data.message = "visual tile mesh had no surfaces: " + region_id + " " + str(cell)
	return visual_tile_data


static func build_region_stream_midlod_tile_data(region_id: String, cell: Vector2i) -> RegionStreamLODTileData:
	var midlod_tile_data: RegionStreamLODTileData = RegionStreamLODTileData.new()
	midlod_tile_data.cell = cell
	midlod_tile_data.lod_meta = "stream_midlod"

	var tile_data: RegionTileData = _load_region_tile(region_id, cell)
	if tile_data == null:
		midlod_tile_data.message = "mid-LOD tile failed to load: " + region_id + " " + str(cell)
		return midlod_tile_data

	var tile_origin_xz: Vector2 = _tile_origin_xz(tile_data)
	midlod_tile_data.node_name = _region_stream_midlod_tile_node_name(region_id, tile_data.cell)
	midlod_tile_data.position = Vector3(tile_origin_xz.x, 0.0, tile_origin_xz.y)
	midlod_tile_data.mesh_data = build_region_surface_index_mesh_data(
		tile_data,
		REGION_STREAM_MIDLOD_SAMPLE_STEP,
		tile_data.key + "_stream_terrain_midlod_mesh",
		tile_origin_xz
	)
	if midlod_tile_data.mesh_data != null and midlod_tile_data.mesh_data.surfaces.size() > 0:
		midlod_tile_data.mesh = region_mesh_from_data(midlod_tile_data.mesh_data, false)
	midlod_tile_data.visibility_range_begin = _midlod_visibility_range_begin()
	midlod_tile_data.visibility_range_end = _midlod_visibility_range_end(tile_data)
	midlod_tile_data.visibility_radius = _tile_visibility_radius(tile_data)
	midlod_tile_data.heightmap_path = tile_data.heightmap_path
	midlod_tile_data.surface_id_path = tile_data.surface_id_path
	midlod_tile_data.ok = midlod_tile_data.mesh_data != null and midlod_tile_data.mesh != null and midlod_tile_data.mesh_data.surfaces.size() > 0
	if not midlod_tile_data.ok:
		midlod_tile_data.message = "mid-LOD tile mesh had no surfaces: " + region_id + " " + str(cell)
	return midlod_tile_data


static func region_stream_hlod_chunk_for_cell(region_id: String, cell: Vector2i) -> MeshInstance3D:
	var tile_data: RegionTileData = _load_region_tile(region_id, cell)
	if tile_data == null:
		return null
	var tile_origin_xz: Vector2 = _tile_origin_xz(tile_data)
	return _region_stream_hlod_chunk(region_id, tile_data, tile_origin_xz)


static func region_visual_tile_from_data(parent: Node3D, visual_tile_data: RegionVisualTileData, _hlod_instance: MeshInstance3D) -> MeshInstance3D:
	if visual_tile_data == null or not visual_tile_data.ok or visual_tile_data.mesh_data == null or visual_tile_data.mesh == null:
		return null
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = visual_tile_data.node_name
	instance.position = visual_tile_data.position
	apply_region_mesh_materials(visual_tile_data.mesh, visual_tile_data.mesh_data)
	instance.mesh = visual_tile_data.mesh
	apply_region_mesh_instance_parameters(instance, visual_tile_data.mesh_data)
	instance.visibility_range_end = visual_tile_data.visibility_range_end
	instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	instance.set_meta(REGION_LOD_META, "detail")
	instance.set_meta(VISIBILITY_RADIUS_META, visual_tile_data.visibility_radius)
	instance.set_meta(TILE_INDEX_META, visual_tile_data.cell)
	instance.set_meta(TILE_PATH_META, visual_tile_data.heightmap_path)
	instance.set_meta(TILE_SURFACE_ID_PATH_META, visual_tile_data.surface_id_path)
	parent.add_child(instance)
	return instance


static func region_stream_midlod_tile_from_data(parent: Node3D, midlod_tile_data: RegionStreamLODTileData) -> MeshInstance3D:
	if midlod_tile_data == null or not midlod_tile_data.ok or midlod_tile_data.mesh_data == null or midlod_tile_data.mesh == null:
		return null
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = midlod_tile_data.node_name
	instance.position = midlod_tile_data.position
	apply_region_mesh_materials(midlod_tile_data.mesh, midlod_tile_data.mesh_data)
	instance.mesh = midlod_tile_data.mesh
	apply_region_mesh_instance_parameters(instance, midlod_tile_data.mesh_data)
	instance.visibility_range_begin = midlod_tile_data.visibility_range_begin
	instance.visibility_range_end = midlod_tile_data.visibility_range_end
	instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.set_meta(REGION_LOD_META, midlod_tile_data.lod_meta)
	instance.set_meta(VISIBILITY_RADIUS_META, midlod_tile_data.visibility_radius)
	instance.set_meta(TILE_INDEX_META, midlod_tile_data.cell)
	instance.set_meta(TILE_PATH_META, midlod_tile_data.heightmap_path)
	instance.set_meta(TILE_SURFACE_ID_PATH_META, midlod_tile_data.surface_id_path)
	parent.add_child(instance)
	return instance


static func build_region_foliage_tile_data(region_id: String, cell: Vector2i) -> RegionFoliageTileData:
	var audit: Dictionary[String, Variant] = {}
	return _build_region_foliage_tile_data(region_id, cell, audit)


static func build_region_foliage_tile_audit(region_id: String, cell: Vector2i) -> Dictionary[String, Variant]:
	var audit: Dictionary[String, Variant] = _new_region_foliage_tile_audit(cell)
	var foliage_tile_data: RegionFoliageTileData = _build_region_foliage_tile_data(region_id, cell, audit)
	audit["ok"] = foliage_tile_data != null and foliage_tile_data.ok
	if foliage_tile_data != null:
		audit["message"] = foliage_tile_data.message
	return audit


static func _build_region_foliage_tile_data(region_id: String, cell: Vector2i, audit: Dictionary[String, Variant]) -> RegionFoliageTileData:
	var foliage_tile_data: RegionFoliageTileData = RegionFoliageTileData.new()
	foliage_tile_data.cell = cell

	var tile_data: RegionTileData = _load_region_tile(region_id, cell)
	if tile_data == null:
		foliage_tile_data.message = "foliage tile failed to load: " + region_id + " " + str(cell)
		if not audit.is_empty():
			audit["message"] = foliage_tile_data.message
		return foliage_tile_data
	if not audit.is_empty():
		_add_region_foliage_surface_audit(audit, tile_data)

	var tile_data_by_cell: Dictionary[Vector2i, RegionTileData] = {cell: tile_data}
	var tile_min_x: float = float(cell.x) * tile_data.tile_size_m
	var tile_min_z: float = float(cell.y) * tile_data.tile_size_m
	var tile_origin_xz: Vector2 = _tile_origin_xz(tile_data)
	var lod0_cell_data_list: Array[FoliageCellData] = []
	var lod1_cell_data_list: Array[FoliageCellData] = []
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
			var lod0_base_count: int = _riparian_gallery_base_count(cell_rect, 0, REGION_FOLIAGE_LOD0_BASE_COUNT)
			var lod0_data: FoliageCellData = _build_region_foliage_cell_data_with_audit(tile_data_by_cell, cell_rect, foliage_cell, 0, lod0_base_count, audit)
			if lod0_data != null:
				_prepare_streamed_foliage_cell_data(lod0_data, tile_origin_xz)
				_build_foliage_cell_multimeshes(lod0_data)
				lod0_cell_data_list.append(lod0_data)
			var lod1_base_count: int = _riparian_gallery_base_count(cell_rect, 1, REGION_FOLIAGE_LOD1_BASE_COUNT)
			var lod1_data: FoliageCellData = _build_region_foliage_cell_data_with_audit(tile_data_by_cell, cell_rect, foliage_cell, 1, lod1_base_count, audit)
			if lod1_data != null:
				_prepare_streamed_foliage_cell_data(lod1_data, tile_origin_xz)
				_build_foliage_cell_multimeshes(lod1_data)
				lod1_cell_data_list.append(lod1_data)

	foliage_tile_data.position = Vector3(tile_origin_xz.x, 0.0, tile_origin_xz.y)
	for lod0_cell_data in lod0_cell_data_list:
		foliage_tile_data.cells.append(lod0_cell_data)
	for lod1_cell_data in lod1_cell_data_list:
		foliage_tile_data.cells.append(lod1_cell_data)
	foliage_tile_data.ok = true
	if not audit.is_empty():
		audit["ok"] = true
		audit["message"] = foliage_tile_data.message
	return foliage_tile_data


static func region_foliage_tile_from_data(parent: Node3D, foliage_tile_data: RegionFoliageTileData) -> Node3D:
	var tile_root: Node3D = region_foliage_tile_root_from_data(parent, foliage_tile_data)
	if tile_root == null:
		return null
	for cell_data in foliage_tile_data.cells:
		_add_foliage_cell_from_data(tile_root, cell_data)
	return tile_root


static func region_foliage_tile_root_from_data(parent: Node3D, foliage_tile_data: RegionFoliageTileData, attach_to_parent: bool = true) -> Node3D:
	if parent == null or foliage_tile_data == null or not foliage_tile_data.ok:
		return null
	var tile_root: Node3D = Node3D.new()
	tile_root.name = "foliage_tile_" + str(foliage_tile_data.cell.x) + "_" + str(foliage_tile_data.cell.y)
	tile_root.position = foliage_tile_data.position
	tile_root.set_meta(TILE_INDEX_META, foliage_tile_data.cell)
	if attach_to_parent:
		parent.add_child(tile_root)
	return tile_root


static func add_region_foliage_species_cell_from_data(parent: Node3D, cell_data: FoliageCellData, species_data: FoliageSpeciesCellData) -> bool:
	if parent == null or cell_data == null or species_data == null:
		return false
	if species_data.transforms.is_empty():
		return false
	var child_count: int = parent.get_child_count()
	_add_foliage_species_cell_from_data(parent, cell_data, species_data)
	return parent.get_child_count() > child_count


static func _build_region_foliage_tile_lod_data(tile_data: RegionTileData, tile_custom_aabb: AABB, lod_index: int) -> FoliageCellData:
	var tile_lod_data: FoliageCellData = FoliageCellData.new()
	var safe_lod_index: int = _region_foliage_lod_index(lod_index)
	var tile_radius: float = _tile_visibility_radius(tile_data)
	tile_lod_data.lod_index = safe_lod_index
	tile_lod_data.node_name = "foliage_tile_" + str(tile_data.cell.x) + "_" + str(tile_data.cell.y) + "_lod" + str(safe_lod_index)
	tile_lod_data.position = Vector3.ZERO
	tile_lod_data.custom_aabb = tile_custom_aabb
	tile_lod_data.visibility_radius = tile_radius
	tile_lod_data.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if safe_lod_index == 0:
		tile_lod_data.visibility_range_end = _foliage_lod0_visibility_range_end(tile_radius)
	else:
		tile_lod_data.visibility_range_begin = _foliage_lod1_visibility_range_begin(tile_radius)
		tile_lod_data.visibility_range_end = _foliage_lod1_visibility_range_end(tile_radius)
	return tile_lod_data


static func _append_foliage_cell_data_to_tile_lod(tile_lod_data: FoliageCellData, cell_data: FoliageCellData, tile_origin_xz: Vector2) -> void:
	var cell_offset_x: float = cell_data.position.x - tile_origin_xz.x
	var cell_offset_z: float = cell_data.position.z - tile_origin_xz.y
	for source_species_data in cell_data.species:
		var target_species_data: FoliageSpeciesCellData = _foliage_species_data(tile_lod_data, source_species_data.species_id)
		for i in range(source_species_data.transforms.size()):
			var transform: Transform3D = source_species_data.transforms[i]
			transform.origin.x += cell_offset_x
			transform.origin.z += cell_offset_z
			target_species_data.transforms.append(transform)
			target_species_data.colors.append(source_species_data.colors[i])
			target_species_data.custom_data.append(source_species_data.custom_data[i])


# Rebase a freshly-built foliage cell into its parent tile's local frame for streaming.
# Only the cell ORIGIN is moved (tile-local instead of world); the per-instance transforms,
# the tight per-cell custom_aabb (built by _foliage_cell_custom_aabb_from_instances), and the
# cell-sized visibility_radius (cell_rect diagonal half) are all expressed RELATIVE to that
# origin and therefore stay valid verbatim under the shift -- so each 32m cell keeps its own
# tight cull AABB and its own cell-sized visibility reach instead of inheriting the whole
# 100m tile's bounds. This is the culling fix: Godot's frustum cull + visibility_range tests
# read multimesh.custom_aabb / the per-species range (both fed from these fields), so a far
# canyon cell now culls as a cell, not as a full tile. Nothing here is read by the foliage
# audit -- it only touches custom_aabb / visibility radius / visibility range, all of which the
# audit ignores; cell identity, instance bucketing, per-class counts and boulder placement were
# all finalized earlier in _build_region_foliage_cell_data_with_audit and are untouched.
static func _prepare_streamed_foliage_cell_data(cell_data: FoliageCellData, tile_origin_xz: Vector2) -> void:
	var local_position: Vector3 = cell_data.position
	local_position.x -= tile_origin_xz.x
	local_position.z -= tile_origin_xz.y
	cell_data.position = local_position
	var cell_radius: float = cell_data.visibility_radius
	if cell_data.lod_index == 0:
		cell_data.visibility_range_begin = 0.0
		cell_data.visibility_range_end = _foliage_lod0_visibility_range_end(cell_radius)
	else:
		cell_data.visibility_range_begin = _foliage_lod1_visibility_range_begin(cell_radius)
		cell_data.visibility_range_end = _foliage_lod1_visibility_range_end(cell_radius)


static func visual_tile_node_name(tile_index: Vector2i, tile_path: String, tile_array_index: int) -> String:
	var base_name: String = tile_path.get_file().get_basename()
	if base_name.is_empty():
		base_name = HEIGHTMESH_NAME + "_" + str(tile_array_index)
	return TERRAIN_TILE_NAME_PREFIX + str(tile_index.x) + "_" + str(tile_index.y) + "_" + _safe_node_name(base_name)


static func region_detail_tile_node_name(region_id: String, tile_index: Vector2i) -> String:
	return "region_" + _safe_node_name(region_id) + "_detail_tile_" + str(tile_index.x) + "_" + str(tile_index.y)


static func _region_stream_hlod_tile_node_name(region_id: String, tile_index: Vector2i) -> String:
	return REGION_HLOD_TILE_NAME_PREFIX + "_" + _safe_node_name(region_id) + "_" + str(tile_index.x) + "_" + str(tile_index.y)


static func _region_stream_midlod_tile_node_name(region_id: String, tile_index: Vector2i) -> String:
	return REGION_MIDLOD_TILE_NAME_PREFIX + "_" + _safe_node_name(region_id) + "_" + str(tile_index.x) + "_" + str(tile_index.y)


static func _detail_visibility_range_end(tile_data: RegionTileData) -> float:
	return maxf(GameConfig.vis_range_terrain + _tile_visibility_radius(tile_data), 0.0)


static func _hlod_visibility_range_begin() -> float:
	return maxf(GameConfig.vis_range_terrain, 0.0)


static func _midlod_visibility_range_begin() -> float:
	return _hlod_visibility_range_begin()


static func _midlod_visibility_range_end(tile_data: RegionTileData) -> float:
	return maxf(REGION_STREAM_MIDLOD_RANGE_END_M + _tile_visibility_radius(tile_data), _midlod_visibility_range_begin())


static func _stream_hlod_visibility_range_begin() -> float:
	return maxf(REGION_STREAM_MIDLOD_RANGE_END_M, _hlod_visibility_range_begin())


static func _foliage_lod0_visibility_range_end(cell_radius: float) -> float:
	return maxf(GameConfig.vis_range_grass + cell_radius, 0.0)


static func _foliage_lod1_visibility_range_begin(cell_radius: float) -> float:
	return _foliage_lod0_visibility_range_end(cell_radius)


static func _foliage_lod1_visibility_range_end(cell_radius: float) -> float:
	return maxf(GameConfig.cam_far + cell_radius, _foliage_lod1_visibility_range_begin(cell_radius))


# --- Foliage distance-LOD fade (per species / per LOD) ---
# The cell-level helpers above (_foliage_lod0_visibility_range_end etc.) compute ONE shared range
# per cell (the grass/default value) and feed the cell-data defaults. The per-species helpers
# below override those at the MultiMeshInstance3D so each species gets its own fade reach: trees
# stay visible farther and fade slowly, grass culls closer with a quick fade, boulders sit between.
# They are public so tools/spike_1km_render_inspector.gd asserts the exact values the builder
# writes (builder + inspector stay in sync, no drift).
static func _foliage_vis_range_base_for_species(species_id: StringName) -> float:
	if _foliage_species_uses_source_material(species_id):
		return FOLIAGE_VIS_RANGE_BASE_TREE
	if species_id == FOLIAGE_SPECIES_BOULDER:
		return FOLIAGE_VIS_RANGE_BASE_BOULDER
	return GameConfig.vis_range_grass


static func foliage_lod0_visibility_range_end_for_species(cell_radius: float, species_id: StringName) -> float:
	return maxf(_foliage_vis_range_base_for_species(species_id) + cell_radius, 0.0)


static func foliage_lod1_visibility_range_begin_for_species(cell_radius: float, species_id: StringName) -> float:
	# LOD1 begins exactly where LOD0 ends. This preserves the codebase's existing LOD1.begin ==
	# LOD0.end invariant (the standard Godot manual-LOD recipe) so the SELF->SELF handoff reads as
	# a gentle fade, not a hard swap.
	return foliage_lod0_visibility_range_end_for_species(cell_radius, species_id)


static func foliage_lod1_visibility_range_end_for_species(cell_radius: float, species_id: StringName) -> float:
	if _foliage_species_uses_source_material(species_id):
		return maxf(FOLIAGE_VIS_RANGE_TREE_LOD1_END + cell_radius, foliage_lod1_visibility_range_begin_for_species(cell_radius, species_id))
	if species_id != FOLIAGE_SPECIES_BOULDER:
		return maxf(FOLIAGE_VIS_RANGE_BASE_GRASS_LOD1_END + cell_radius, foliage_lod1_visibility_range_begin_for_species(cell_radius, species_id))
	# Boulders still run out to the far clip: they are cheap procedural geometry and help steep
	# talus slopes read until the terrain/HLOD takes over in fog.
	return maxf(GameConfig.cam_far + cell_radius, foliage_lod1_visibility_range_begin_for_species(cell_radius, species_id))


static func foliage_visibility_range_fade_mode_for_lod(lod_index: int) -> int:
	# Both LODs self-fade. LOD0/LOD1 share the same mesh for grass and the GLB tree species, so the
	# SELF->SELF handoff dissolves one scatter pattern into the other instead of winking a shape.
	if lod_index <= 0:
		return GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	return GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


static func foliage_visibility_range_fade_margin_for_species(species_id: StringName) -> float:
	if _foliage_species_uses_source_material(species_id):
		return FOLIAGE_FADE_MARGIN_TREE
	if species_id == FOLIAGE_SPECIES_BOULDER:
		return FOLIAGE_FADE_MARGIN_BOULDER
	return FOLIAGE_FADE_MARGIN_GRASS


static func foliage_pipeline_warmup_node_names() -> PackedStringArray:
	var node_names: PackedStringArray = PackedStringArray()
	for species_id in FOLIAGE_SPECIES_LIST:
		node_names.append(REGION_PIPELINE_WARMUP_FOLIAGE_LOD0_NAME + "_" + String(species_id))
		node_names.append(REGION_PIPELINE_WARMUP_FOLIAGE_LOD1_NAME + "_" + String(species_id))
	return node_names


static func _add_region_pipeline_warmup(parent: Node3D) -> Node3D:
	var root: PipelineWarmupRoot = PipelineWarmupRoot.new()
	root.name = REGION_PIPELINE_WARMUP_ROOT_NAME
	root.visible = true
	root.release_after_frames = PIPELINE_WARMUP_RELEASE_AFTER_FRAMES
	parent.add_child(root)

	var terrain_material_count: int = _add_terrain_pipeline_warmup(root)
	var foliage_lod_count: int = _add_foliage_pipeline_warmup(root)
	root.set_meta(PIPELINE_WARMUP_TERRAIN_MATERIAL_COUNT_META, terrain_material_count)
	root.set_meta(PIPELINE_WARMUP_FOLIAGE_LOD_COUNT_META, foliage_lod_count)
	root.set_meta(PIPELINE_WARMUP_TRANSIENT_META, true)
	root.set_meta(PIPELINE_WARMUP_RELEASE_FRAMES_META, PIPELINE_WARMUP_RELEASE_AFTER_FRAMES)
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
	var warmup_count: int = 0
	for species_id in FOLIAGE_SPECIES_LIST:
		var lod0_mesh: Mesh = _region_foliage_mesh_for_lod_species(0, species_id)
		var lod0_material: Material = _region_foliage_warmup_material_for_lod_species(0, species_id)
		_add_foliage_pipeline_warmup_instance(parent, REGION_PIPELINE_WARMUP_FOLIAGE_LOD0_NAME + "_" + String(species_id), lod0_mesh, lod0_material)
		warmup_count += 1
		var lod1_mesh: Mesh = _region_foliage_mesh_for_lod_species(1, species_id)
		var lod1_material: Material = _region_foliage_warmup_material_for_lod_species(1, species_id)
		_add_foliage_pipeline_warmup_instance(parent, REGION_PIPELINE_WARMUP_FOLIAGE_LOD1_NAME + "_" + String(species_id), lod1_mesh, lod1_material)
		warmup_count += 1
	return warmup_count


# Pipeline-warmup material mirror. Runtime GLB foliage (cottonwood/willow/juniper/yucca)
# renders with NO material_override: the StandardMaterial3D baked into the GLB mesh's first
# surface is the material whose PSO actually compiles the first time a tree of that species
# streams in. _region_foliage_material_for_lod_species returns null for these species (so
# runtime leaves material_override empty), which would leave the warmup with nothing concrete
# to compile or verify. Here we lift that same surface material out and hand it to the warmup
# instance as material_override. It is the identical material instance (same RID) the runtime
# resolves, so the PSO cache entry is shared and the first streamed tree pays no compile hitch.
static func _region_foliage_warmup_material_for_lod_species(lod_index: int, species_id: StringName) -> Material:
	if _foliage_species_uses_source_material(species_id):
		var source_mesh: Mesh = _region_foliage_mesh_for_lod_species(lod_index, species_id)
		if source_mesh != null and source_mesh.get_surface_count() > 0:
			var source_material: Material = source_mesh.surface_get_material(0)
			if source_material != null:
				return source_material
		return null
	return _region_foliage_material_for_lod_species(lod_index, species_id)


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
	if material != null:
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
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
	var mesh_data: RegionMeshData = build_region_surface_index_mesh_data(tile_data, REGION_STREAM_HLOD_SAMPLE_STEP, tile_data.key + "_stream_terrain_hlod_mesh", tile_origin_xz)
	instance.mesh = region_mesh_from_data(mesh_data)
	instance.visibility_range_begin = _stream_hlod_visibility_range_begin()
	instance.visibility_range_end = 0.0
	instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.set_meta(REGION_LOD_META, "stream_hlod")
	instance.set_meta(VISIBILITY_RADIUS_META, _tile_visibility_radius(tile_data))
	instance.set_meta(TILE_INDEX_META, tile_data.cell)
	instance.set_meta(TILE_PATH_META, tile_data.heightmap_path)
	instance.set_meta(TILE_SURFACE_ID_PATH_META, tile_data.surface_id_path)
	apply_region_mesh_instance_parameters(instance, mesh_data)
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
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
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
	surface_data.surface_id_texture = load(tile_data.surface_id_path) as Texture2D
	if surface_data.surface_id_texture == null and tile_data.surface_image != null and not tile_data.surface_image.is_empty():
		surface_data.surface_id_texture = ImageTexture.create_from_image(tile_data.surface_image)
	surface_data.control_origin_xz = Vector2(float(tile_data.cell.x) * tile_data.tile_size_m, float(tile_data.cell.y) * tile_data.tile_size_m)
	surface_data.control_size_xz = Vector2(tile_data.tile_size_m, tile_data.tile_size_m)
	mesh_data.surfaces.append(surface_data)
	return mesh_data


static func region_mesh_from_data(mesh_data: RegionMeshData, assign_materials: bool = true) -> ArrayMesh:
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
	if assign_materials:
		apply_region_mesh_materials(mesh, mesh_data)
	return mesh


static func apply_region_mesh_materials(mesh: ArrayMesh, mesh_data: RegionMeshData) -> void:
	if mesh == null or mesh_data == null:
		return
	var surface_count: int = mini(mesh.get_surface_count(), mesh_data.surfaces.size())
	for surface_index in range(surface_count):
		var surface_data: MeshSurfaceData = mesh_data.surfaces[surface_index]
		if surface_data.use_surface_index_material:
			mesh.surface_set_material(surface_index, _surface_index_tile_material(surface_data))
		else:
			mesh.surface_set_material(surface_index, _material_for_surface_value(surface_data.surface_id_value))


static func apply_region_mesh_instance_parameters(instance: MeshInstance3D, mesh_data: RegionMeshData) -> void:
	if instance == null or mesh_data == null:
		return
	for surface_data in mesh_data.surfaces:
		if not surface_data.use_surface_index_material:
			continue
		instance.set_instance_shader_parameter(CONTROL_ORIGIN_XZ_UNIFORM, surface_data.control_origin_xz)
		instance.set_instance_shader_parameter(CONTROL_SIZE_XZ_UNIFORM, surface_data.control_size_xz)
		return


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
			if _tile_quad_exceeds_relative_seam_delta(tile_data, col, row, next_col, next_row):
				continue
			var surface_col: int = _surface_sample_coord(col, next_col, tile_data.surface_image.get_width())
			var surface_row: int = _surface_sample_coord(row, next_row, tile_data.surface_image.get_height())
			var surface_id_value: int = _surface_id_value_at(tile_data, surface_col, surface_row)
			var bucket: MeshBucket = _bucket_for_surface_value(buckets, surface_id_value)
			var corner_a: int = _bucket_vertex(bucket, tile_data, col, row, local_origin_xz)
			var corner_b: int = _bucket_vertex(bucket, tile_data, next_col, row, local_origin_xz)
			var corner_c: int = _bucket_vertex(bucket, tile_data, col, next_row, local_origin_xz)
			var corner_d: int = _bucket_vertex(bucket, tile_data, next_col, next_row, local_origin_xz)
			# Godot culls the opposite winding from above; keep terrain front-facing.
			bucket.indices.append(corner_a)
			bucket.indices.append(corner_b)
			bucket.indices.append(corner_c)
			bucket.indices.append(corner_b)
			bucket.indices.append(corner_d)
			bucket.indices.append(corner_c)


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
			if _tile_quad_exceeds_relative_seam_delta(tile_data, col, row, next_col, next_row):
				continue
			var corner_a: int = _bucket_vertex(bucket, tile_data, col, row, local_origin_xz)
			var corner_b: int = _bucket_vertex(bucket, tile_data, next_col, row, local_origin_xz)
			var corner_c: int = _bucket_vertex(bucket, tile_data, col, next_row, local_origin_xz)
			var corner_d: int = _bucket_vertex(bucket, tile_data, next_col, next_row, local_origin_xz)
			# Godot culls the opposite winding from above; keep terrain front-facing.
			bucket.indices.append(corner_a)
			bucket.indices.append(corner_b)
			bucket.indices.append(corner_c)
			bucket.indices.append(corner_b)
			bucket.indices.append(corner_d)
			bucket.indices.append(corner_c)


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


static func _tile_quad_exceeds_relative_seam_delta(tile_data: RegionTileData, col: int, row: int, next_col: int, next_row: int) -> bool:
	var world_a: Vector2 = _tile_world_xz(tile_data, col, row)
	var world_b: Vector2 = _tile_world_xz(tile_data, next_col, row)
	var world_c: Vector2 = _tile_world_xz(tile_data, col, next_row)
	var world_d: Vector2 = _tile_world_xz(tile_data, next_col, next_row)
	var max_allowed_delta: float = maxf(
		maxf(world_a.distance_to(world_b), world_c.distance_to(world_d)),
		maxf(world_a.distance_to(world_c), world_b.distance_to(world_d))
	) * REGION_TERRAIN_SEAM_MAX_SLOPE
	max_allowed_delta = maxf(max_allowed_delta, REGION_TERRAIN_SEAM_MIN_DELTA_M)
	var height_a: float = _height_value_at(tile_data, col, row)
	var height_b: float = _height_value_at(tile_data, next_col, row)
	var height_c: float = _height_value_at(tile_data, col, next_row)
	var height_d: float = _height_value_at(tile_data, next_col, next_row)
	return (
		absf(height_a - height_b) > max_allowed_delta
		or absf(height_a - height_c) > max_allowed_delta
		or absf(height_b - height_d) > max_allowed_delta
		or absf(height_c - height_d) > max_allowed_delta
	)


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
	_surface_cache_mutex.lock()
	var material: ShaderMaterial = _surface_index_material_locked(surface_data)
	_surface_cache_mutex.unlock()
	return material


static func _surface_index_material_locked(surface_data: MeshSurfaceData) -> ShaderMaterial:
	var cache_key: String = _surface_index_material_cache_key(surface_data)
	if _surface_index_material_cache.has(cache_key):
		return _surface_index_material_cache[cache_key]
	var material: ShaderMaterial = ShaderMaterial.new()
	material.resource_name = TERRAIN_INDEX_MATERIAL_NAME
	material.shader = TerrainSurfaceIndexShader
	var albedo_array: Texture2DArray = _surface_index_albedo_array_locked()
	if albedo_array != null:
		material.set_shader_parameter(ALBEDO_ARRAY_UNIFORM, albedo_array)
		material.set_shader_parameter(USE_ALBEDO_ARRAY_UNIFORM, true)
	var normal_array: Texture2DArray = _surface_index_normal_array_locked()
	if normal_array != null:
		material.set_shader_parameter(NORMAL_ARRAY_UNIFORM, normal_array)
		material.set_shader_parameter(USE_NORMAL_ARRAY_UNIFORM, true)
	var macro_albedo_texture: Texture2D = _surface_index_macro_albedo_texture_locked()
	if macro_albedo_texture != null:
		material.set_shader_parameter(MACRO_ALBEDO_TEXTURE_UNIFORM, macro_albedo_texture)
		material.set_shader_parameter(USE_MACRO_ALBEDO_UNIFORM, true)
	material.set_shader_parameter(TERRAIN_ROUGHNESS_UNIFORM, _average_default_surface_roughness())
	material.set_shader_parameter(TERRAIN_SPECULAR_UNIFORM, 0.18)
	_apply_zion_surface_index_tuning(material)
	_apply_surface_index_palette(material)
	_surface_index_material_cache[cache_key] = material
	return material


static func _surface_index_tile_material(surface_data: MeshSurfaceData) -> ShaderMaterial:
	_surface_cache_mutex.lock()
	var tile_material: ShaderMaterial = _surface_index_tile_material_locked(surface_data)
	_surface_cache_mutex.unlock()
	return tile_material


static func _surface_index_tile_material_locked(surface_data: MeshSurfaceData) -> ShaderMaterial:
	var tile_cache_key: String = _surface_index_material_cache_key(surface_data) + "|" + surface_data.surface_id_path
	if _surface_index_tile_material_cache.has(tile_cache_key):
		_surface_index_tile_material_cache_touch_locked(tile_cache_key)
		return _surface_index_tile_material_cache[tile_cache_key]
	var shared_material: ShaderMaterial = _surface_index_material_locked(surface_data)
	var tile_material: ShaderMaterial = shared_material.duplicate(false) as ShaderMaterial
	tile_material.resource_name = TERRAIN_INDEX_MATERIAL_NAME
	var surface_texture: Texture2D = surface_data.surface_id_texture
	if surface_texture == null:
		surface_texture = _load_texture(surface_data.surface_id_path)
	if surface_texture != null:
		tile_material.set_shader_parameter(SURFACE_ID_TEXTURE_UNIFORM, surface_texture)
	_surface_index_tile_material_cache[tile_cache_key] = tile_material
	_surface_index_tile_material_cache_order.append(tile_cache_key)
	_surface_index_tile_material_cache_prune_locked()
	return tile_material


static func _surface_index_tile_material_cache_touch_locked(cache_key: String) -> void:
	var cache_index: int = _surface_index_tile_material_cache_order.find(cache_key)
	if cache_index >= 0:
		_surface_index_tile_material_cache_order.remove_at(cache_index)
	_surface_index_tile_material_cache_order.append(cache_key)


static func _surface_index_tile_material_cache_prune_locked() -> void:
	while _surface_index_tile_material_cache_order.size() > SURFACE_INDEX_TILE_MATERIAL_CACHE_CAPACITY:
		var evicted_key: String = String(_surface_index_tile_material_cache_order[0])
		_surface_index_tile_material_cache_order.remove_at(0)
		_surface_index_tile_material_cache.erase(evicted_key)


static func _surface_index_material_cache_key(surface_data: MeshSurfaceData) -> String:
	return TerrainSurfacePaletteResource.resource_path + "|" + SurfaceVisualCatalogResource.resource_path


static func _surface_index_warmup_material() -> ShaderMaterial:
	var surface_data: MeshSurfaceData = MeshSurfaceData.new()
	surface_data.control_origin_xz = Vector2.ZERO
	surface_data.control_size_xz = Vector2(GameConfig.STREAM_TILE_SIZE_M, GameConfig.STREAM_TILE_SIZE_M)
	return _surface_index_material(surface_data)


# Cold-start pre-realization. Force the heavy surface-index Texture2DArrays
# (~44 MB albedo + normal) and the shared terrain ShaderMaterial into their static
# caches NOW, during the host's _ready/setup, so the FIRST live terrain commit doesn't
# pay the image-decode + create_from_images cost on a drive frame (a multi-hundred-ms
# boot hitch). The pipeline-warmup mesh built by build_region_stream_root already binds
# the same shared material; calling this first means that path is a pure cache hit and
# nothing is duplicated. All cache accessors are static + mutex-guarded, so this is
# idempotent and safe to call once up front. Returns true if both arrays realized.
static func prewarm_surface_index_pipeline() -> bool:
	var albedo_array: Texture2DArray = _surface_index_albedo_array()
	var normal_array: Texture2DArray = _surface_index_normal_array()
	_surface_index_macro_albedo_texture()
	var _shared_material: ShaderMaterial = _surface_index_warmup_material()
	return albedo_array != null and normal_array != null


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
			# C2: per-surface base roughness (wet-adjusted, same model as the cedar material
			# path and the legacy average) so the surface-id map drives real material variation.
			var surface_roughness: float = _wet_roughness(float(visual_def.get("roughness")), wetness)
			material.set_shader_parameter(StringName(SURFACE_ROUGHNESS_UNIFORM_PREFIX + str(id_value)), surface_roughness)
		material.set_shader_parameter(StringName("surface_color_" + str(id_value)), color)


static func _apply_zion_surface_index_tuning(material: ShaderMaterial) -> void:
	material.set_shader_parameter(ZION_SANDSTONE_COLOR_UNIFORM, Color(0.49, 0.14, 0.05, 1.0))
	material.set_shader_parameter(ZION_SAND_COLOR_UNIFORM, Color(0.78, 0.68, 0.52, 1.0))
	material.set_shader_parameter(ZION_STRATA_DARK_COLOR_UNIFORM, Color(0.36, 0.14, 0.08, 1.0))
	material.set_shader_parameter(ZION_SANDSTONE_SLOPE_START_UNIFORM, 0.08)
	material.set_shader_parameter(ZION_SANDSTONE_SLOPE_END_UNIFORM, 0.38)
	material.set_shader_parameter(ZION_SAND_HEIGHT_START_UNIFORM, 1193.0)
	material.set_shader_parameter(ZION_SAND_HEIGHT_END_UNIFORM, 1202.0)
	material.set_shader_parameter(ZION_STRATA_SCALE_UNIFORM, 18.0)
	material.set_shader_parameter(ZION_STRATA_STRENGTH_UNIFORM, 0.28)
	material.set_shader_parameter(ZION_STRATA_LIGHT_COLOR_UNIFORM, Color(0.86, 0.62, 0.38, 1.0))
	material.set_shader_parameter(ZION_STRATA_DIP_UNIFORM, Vector2(0.15, 0.15))
	material.set_shader_parameter(ZION_DETILE_STRENGTH_UNIFORM, 0.18)
	material.set_shader_parameter(ZION_FLOOR_DARK_COLOR_UNIFORM, Color(0.20, 0.16, 0.13, 1.0))
	material.set_shader_parameter(ZION_FLOOR_SEDIMENT_COLOR_UNIFORM, Color(0.55, 0.34, 0.24, 1.0))
	material.set_shader_parameter(ZION_FLOOR_SCATTER_STRENGTH_UNIFORM, 0.80)
	material.set_shader_parameter(ZION_FLOOR_DETILE_STRENGTH_UNIFORM, 0.24)
	material.set_shader_parameter(ZION_RIPARIAN_TINT_COLOR_UNIFORM, Color(0.31, 0.44, 0.24, 1.0))
	material.set_shader_parameter(ZION_RIPARIAN_TINT_STRENGTH_UNIFORM, 0.24)
	material.set_shader_parameter(ZION_RIPARIAN_OUTER_M_UNIFORM, 130.0)
	material.set_shader_parameter(ZION_BANK_WET_WIDTH_UNIFORM, 14.0)
	material.set_shader_parameter(ZION_BANK_WET_DARKNESS_UNIFORM, 0.16)
	material.set_shader_parameter(ZION_BANK_WET_ROUGHNESS_UNIFORM, 0.36)
	material.set_shader_parameter(ZION_VARNISH_COLOR_UNIFORM, Color(0.13, 0.08, 0.06, 1.0))
	material.set_shader_parameter(ZION_VARNISH_STRENGTH_UNIFORM, 0.5)
	material.set_shader_parameter(ZION_VARNISH_WALL_THRESHOLD_UNIFORM, 0.30)
	material.set_shader_parameter(ZION_VARNISH_HEIGHT_START_UNIFORM, 1300.0)
	material.set_shader_parameter(ZION_VARNISH_STREAK_SCALE_UNIFORM, 0.12)
	material.set_shader_parameter(ZION_KAYENTA_COLOR_UNIFORM, Color(0.38, 0.10, 0.06, 1.0))
	material.set_shader_parameter(ZION_KAYENTA_HEIGHT_START_UNIFORM, 1200.0)
	material.set_shader_parameter(ZION_KAYENTA_HEIGHT_END_UNIFORM, 1250.0)
	material.set_shader_parameter(ZION_KAYENTA_STRENGTH_UNIFORM, 0.55)
	material.set_shader_parameter(ZION_BLEACH_COLOR_UNIFORM, Color(0.91, 0.84, 0.72, 1.0))
	material.set_shader_parameter(ZION_BLEACH_HEIGHT_START_UNIFORM, 1550.0)
	material.set_shader_parameter(ZION_BLEACH_STRENGTH_UNIFORM, 0.55)
	material.set_shader_parameter(ZION_WETROCK_ENABLED_UNIFORM, true)
	material.set_shader_parameter(ZION_WETROCK_HEIGHT_START_UNIFORM, 1230.0)
	material.set_shader_parameter(ZION_WETROCK_HEIGHT_END_UNIFORM, 1320.0)
	material.set_shader_parameter(ZION_WETROCK_DARKNESS_UNIFORM, 0.4)
	material.set_shader_parameter(MACRO_ALBEDO_ORIGIN_XZ_UNIFORM, MACRO_ALBEDO_REGION_ORIGIN_XZ)
	material.set_shader_parameter(MACRO_ALBEDO_SIZE_XZ_UNIFORM, MACRO_ALBEDO_REGION_SIZE_XZ)
	material.set_shader_parameter(MACRO_ALBEDO_STRENGTH_UNIFORM, MACRO_ALBEDO_STRENGTH)
	material.set_shader_parameter(NORMAL_ARRAY_STRENGTH_UNIFORM, 0.36)
	# FLOOR-PBR: real CC0 ambientCG albedo+normal triplanar detail on the drivable floor.
	# Defaults match the shader; bound explicitly so the values are inspectable. The floor
	# path reuses the already-bound per-surface-id albedo_array + normal_array, so no new
	# textures are wired here.
	material.set_shader_parameter(USE_FLOOR_PBR_UNIFORM, FLOOR_PBR_ENABLED)
	material.set_shader_parameter(FLOOR_PBR_BLEND_UNIFORM, FLOOR_PBR_BLEND)
	material.set_shader_parameter(FLOOR_PBR_NORMAL_STRENGTH_UNIFORM, FLOOR_PBR_NORMAL_STRENGTH)
	material.set_shader_parameter(FLOOR_PBR_ROUGHNESS_STRENGTH_UNIFORM, FLOOR_PBR_ROUGHNESS_STRENGTH)
	material.set_shader_parameter(FLOOR_PBR_UV_SCALE_UNIFORM, FLOOR_PBR_UV_SCALE)
	material.set_shader_parameter(FLOOR_PBR_SLICKROCK_SCALE_MUL_UNIFORM, FLOOR_PBR_SLICKROCK_SCALE_MUL)
	material.set_shader_parameter(FLOOR_PBR_TRIPLANAR_BLEND_UNIFORM, FLOOR_PBR_TRIPLANAR_BLEND)
	material.set_shader_parameter(FLOOR_PBR_SLOPE_FLAT_NY_UNIFORM, FLOOR_PBR_SLOPE_FLAT_NY)
	material.set_shader_parameter(FLOOR_PBR_SLOPE_STEEP_NY_UNIFORM, FLOOR_PBR_SLOPE_STEEP_NY)
	material.set_shader_parameter(FLOOR_PBR_HEIGHT_START_OFFSET_UNIFORM, FLOOR_PBR_HEIGHT_START_OFFSET)
	material.set_shader_parameter(FLOOR_PBR_HEIGHT_END_OFFSET_UNIFORM, FLOOR_PBR_HEIGHT_END_OFFSET)
	material.set_shader_parameter(FLOOR_PBR_SINGLE_PLANE_THRESHOLD_UNIFORM, FLOOR_PBR_SINGLE_PLANE_THRESHOLD)


static func _surface_index_macro_albedo_texture() -> Texture2D:
	_surface_cache_mutex.lock()
	var texture: Texture2D = _surface_index_macro_albedo_texture_locked()
	_surface_cache_mutex.unlock()
	return texture


static func _surface_index_macro_albedo_texture_locked() -> Texture2D:
	if _surface_index_macro_albedo_cache != null:
		return _surface_index_macro_albedo_cache
	_surface_index_macro_albedo_cache = _load_source_image_texture(MACRO_ALBEDO_TEXTURE_PATH)
	if _surface_index_macro_albedo_cache == null:
		push_error("Terrain surface-index macro albedo failed to load: " + MACRO_ALBEDO_TEXTURE_PATH)
	return _surface_index_macro_albedo_cache


static func _surface_index_albedo_array() -> Texture2DArray:
	_surface_cache_mutex.lock()
	var texture_array: Texture2DArray = _surface_index_albedo_array_locked()
	_surface_cache_mutex.unlock()
	return texture_array


static func _surface_index_albedo_array_locked() -> Texture2DArray:
	if _surface_index_albedo_array_cache != null:
		if _surface_index_array_has_expected_layers(_surface_index_albedo_array_cache):
			return _surface_index_albedo_array_cache
		_surface_index_albedo_array_cache = null
		_surface_index_material_cache.clear()
		_surface_index_tile_material_cache.clear()
		_surface_index_tile_material_cache_order.clear()
	var target_size: Vector2i = _surface_index_albedo_target_size()
	var cache_path: String = _surface_index_array_cache_path(SURFACE_INDEX_ALBEDO_ARRAY_CACHE_KIND, target_size)
	var cached_array: Texture2DArray = _load_surface_index_array_cache(cache_path)
	if cached_array != null:
		cached_array.resource_name = "terrain_surface_index_albedo_array"
		_surface_index_albedo_array_cache = cached_array
		return _surface_index_albedo_array_cache
	var images: Array[Image] = []
	for id_value in range(SURFACE_INDEX_LAYER_COUNT):
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
	for layer_index in range(images.size()):
		texture_array.update_layer(images[layer_index], layer_index)
	if not _surface_index_array_has_expected_layers(texture_array):
		push_error(
			"Terrain surface-index albedo array created with "
			+ str(texture_array.get_layers())
			+ " layers, expected "
			+ str(SURFACE_INDEX_LAYER_COUNT)
		)
		return null
	_save_surface_index_array_cache(texture_array, cache_path)
	_surface_index_albedo_array_cache = texture_array
	return _surface_index_albedo_array_cache


static func _surface_index_normal_array() -> Texture2DArray:
	_surface_cache_mutex.lock()
	var texture_array: Texture2DArray = _surface_index_normal_array_locked()
	_surface_cache_mutex.unlock()
	return texture_array


static func _surface_index_normal_array_locked() -> Texture2DArray:
	if _surface_index_normal_array_cache != null:
		if _surface_index_array_has_expected_layers(_surface_index_normal_array_cache):
			return _surface_index_normal_array_cache
		_surface_index_normal_array_cache = null
		_surface_index_material_cache.clear()
		_surface_index_tile_material_cache.clear()
		_surface_index_tile_material_cache_order.clear()
	var target_size: Vector2i = _surface_index_normal_target_size()
	var cache_path: String = _surface_index_array_cache_path(SURFACE_INDEX_NORMAL_ARRAY_CACHE_KIND, target_size)
	var cached_array: Texture2DArray = _load_surface_index_array_cache(cache_path)
	if cached_array != null:
		cached_array.resource_name = "terrain_surface_index_normal_array"
		_surface_index_normal_array_cache = cached_array
		return _surface_index_normal_array_cache
	var images: Array[Image] = []
	for id_value in range(SURFACE_INDEX_LAYER_COUNT):
		var image: Image = _surface_index_normal_image(id_value, target_size)
		if image == null:
			return null
		images.append(image)
	var texture_array: Texture2DArray = Texture2DArray.new()
	var create_error: Error = texture_array.create_from_images(images)
	if create_error != OK:
		push_error("Terrain surface-index normal array failed to create: " + error_string(create_error))
		return null
	texture_array.resource_name = "terrain_surface_index_normal_array"
	for layer_index in range(images.size()):
		texture_array.update_layer(images[layer_index], layer_index)
	if not _surface_index_array_has_expected_layers(texture_array):
		push_error(
			"Terrain surface-index normal array created with "
			+ str(texture_array.get_layers())
			+ " layers, expected "
			+ str(SURFACE_INDEX_LAYER_COUNT)
		)
		return null
	_save_surface_index_array_cache(texture_array, cache_path)
	_surface_index_normal_array_cache = texture_array
	return _surface_index_normal_array_cache


static func _surface_index_albedo_target_size() -> Vector2i:
	for id_value in range(SURFACE_INDEX_LAYER_COUNT):
		var image: Image = _load_surface_index_source_albedo_image(id_value)
		if image == null:
			continue
		return Vector2i(image.get_width(), image.get_height())
	return Vector2i(4, 4)


static func _surface_index_normal_target_size() -> Vector2i:
	for id_value in range(SURFACE_INDEX_LAYER_COUNT):
		var image: Image = _load_surface_index_source_normal_image(id_value)
		if image == null:
			continue
		return Vector2i(image.get_width(), image.get_height())
	return Vector2i(4, 4)


static func _surface_index_array_cache_path(kind: String, target_size: Vector2i) -> String:
	var cache_key: String = _surface_index_array_cache_key(kind, target_size)
	if cache_key.is_empty():
		return ""
	var file_name: String = "terrain_surface_index_" + kind + "_array_" + cache_key + ".res"
	return SURFACE_INDEX_ARRAY_CACHE_DIR.path_join(file_name)


static func _surface_index_array_cache_key(kind: String, target_size: Vector2i) -> String:
	var parts: PackedStringArray = PackedStringArray()
	parts.append(SURFACE_INDEX_ARRAY_CACHE_VERSION)
	parts.append("kind=" + kind)
	parts.append("layers=" + str(SURFACE_INDEX_LAYER_COUNT))
	parts.append("target_size=" + str(target_size.x) + "x" + str(target_size.y))
	parts.append("format=" + SURFACE_INDEX_ARRAY_IMAGE_FORMAT_NAME)
	parts.append("mipmaps=generated")
	parts.append("resize_filter=" + SURFACE_INDEX_ARRAY_RESIZE_FILTER_NAME)
	parts.append("palette_path=" + TerrainSurfacePaletteResource.resource_path)
	parts.append("palette_md5=" + _file_md5_or_missing(TerrainSurfacePaletteResource.resource_path))
	parts.append("catalog_path=" + SurfaceVisualCatalogResource.resource_path)
	parts.append("catalog_md5=" + _file_md5_or_missing(SurfaceVisualCatalogResource.resource_path))
	for id_value in range(SURFACE_INDEX_LAYER_COUNT):
		parts.append(_surface_index_array_cache_layer_signature(kind, id_value))
	return "\n".join(parts).sha256_text()


static func _surface_index_array_cache_layer_signature(kind: String, id_value: int) -> String:
	var parts: PackedStringArray = PackedStringArray()
	var surface_id: StringName = _surface_id_for_value(id_value)
	parts.append("id=" + str(id_value))
	parts.append("surface_id=" + String(surface_id))
	var visual_def: Resource = SurfaceVisualCatalogResource.call("default_visual_for_surface_id", surface_id)
	if visual_def == null:
		parts.append("visual=<null>")
		parts.append("fallback=" + _surface_index_array_fallback_signature(kind, id_value))
		return "|".join(parts)
	var visual_id: StringName = visual_def.get("id")
	var texture_path: String = _surface_index_array_texture_path(kind, visual_def)
	parts.append("visual_id=" + String(visual_id))
	parts.append("texture_path=" + texture_path)
	if texture_path.is_empty():
		parts.append("fallback=" + _surface_index_array_fallback_signature(kind, id_value))
	else:
		parts.append("source_md5=" + _file_md5_or_missing(texture_path))
		parts.append("import_md5=" + _file_md5_or_missing(texture_path + ".import"))
	return "|".join(parts)


static func _surface_index_array_texture_path(kind: String, visual_def: Resource) -> String:
	if kind == SURFACE_INDEX_ALBEDO_ARRAY_CACHE_KIND:
		return String(visual_def.get("albedo_texture_path"))
	if kind == SURFACE_INDEX_NORMAL_ARRAY_CACHE_KIND:
		return String(visual_def.get("normal_texture_path"))
	return ""


static func _surface_index_array_fallback_signature(kind: String, id_value: int) -> String:
	if kind == SURFACE_INDEX_ALBEDO_ARRAY_CACHE_KIND:
		return str(_surface_index_fallback_color(id_value))
	if kind == SURFACE_INDEX_NORMAL_ARRAY_CACHE_KIND:
		return str(Color(0.5, 0.5, 1.0, 1.0))
	return "<unknown>"


static func _load_surface_index_array_cache(cache_path: String) -> Texture2DArray:
	if cache_path.is_empty():
		return null
	var absolute_path: String = _globalize_resource_path(cache_path)
	if not FileAccess.file_exists(absolute_path):
		return null
	var resource: Resource = ResourceLoader.load(cache_path) as Resource
	var texture_array: Texture2DArray = resource as Texture2DArray
	if texture_array == null:
		push_warning("Terrain surface-index texture-array cache ignored because it is not a Texture2DArray: " + cache_path)
		return null
	if not _surface_index_array_has_expected_layers(texture_array):
		push_warning(
			"Terrain surface-index texture-array cache ignored because it has "
			+ str(texture_array.get_layers())
			+ " layers, expected "
			+ str(SURFACE_INDEX_LAYER_COUNT)
			+ ": "
			+ cache_path
		)
		return null
	return texture_array


static func _surface_index_array_has_expected_layers(texture_array: Texture2DArray) -> bool:
	return texture_array != null and texture_array.get_layers() == SURFACE_INDEX_LAYER_COUNT


static func _save_surface_index_array_cache(texture_array: Texture2DArray, cache_path: String) -> void:
	if texture_array == null or cache_path.is_empty():
		return
	var absolute_dir: String = _globalize_resource_path(SURFACE_INDEX_ARRAY_CACHE_DIR)
	var dir_error: Error = DirAccess.make_dir_recursive_absolute(absolute_dir)
	if dir_error != OK:
		push_warning("Terrain surface-index texture-array cache directory failed: " + error_string(dir_error))
		return
	var absolute_path: String = _globalize_resource_path(cache_path)
	var save_error: Error = ResourceSaver.save(texture_array, absolute_path)
	if save_error != OK:
		push_warning("Terrain surface-index texture-array cache save failed: " + error_string(save_error))


static func _file_md5_or_missing(path: String) -> String:
	if path.is_empty():
		return "<empty>"
	var absolute_path: String = _globalize_resource_path(path)
	if not FileAccess.file_exists(absolute_path):
		return "<missing>"
	var md5: String = FileAccess.get_md5(absolute_path)
	if md5.is_empty():
		return "<hash-error>"
	return md5


static func _globalize_resource_path(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	return path


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


static func _surface_index_normal_image(id_value: int, target_size: Vector2i) -> Image:
	var image: Image = _load_surface_index_source_normal_image(id_value)
	if image == null:
		image = Image.create(target_size.x, target_size.y, false, Image.FORMAT_RGBA8)
		image.fill(Color(0.5, 0.5, 1.0, 1.0))
	else:
		if image.get_width() != target_size.x or image.get_height() != target_size.y:
			image.resize(target_size.x, target_size.y, Image.INTERPOLATE_LANCZOS)
		image.convert(Image.FORMAT_RGBA8)
	var mip_error: Error = image.generate_mipmaps()
	if mip_error != OK:
		push_error("Terrain surface-index normal mipmaps failed for layer " + str(id_value) + ": " + error_string(mip_error))
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


static func _load_surface_index_source_normal_image(id_value: int) -> Image:
	var surface_id: StringName = _surface_id_for_value(id_value)
	var visual_def: Resource = SurfaceVisualCatalogResource.call("default_visual_for_surface_id", surface_id)
	if visual_def == null:
		return null
	var normal_texture_path: String = visual_def.get("normal_texture_path")
	if normal_texture_path.is_empty():
		return null
	var image: Image = Image.load_from_file(ProjectSettings.globalize_path(normal_texture_path))
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


static func region_tile_cells(region_id: String) -> Array[Vector2i]:
	var manifest_path: String = _region_manifest_path(region_id)
	var manifest: Dictionary = _load_json_dictionary(manifest_path)
	if manifest.is_empty():
		var empty_cells: Array[Vector2i] = []
		return empty_cells
	return _tile_cells_from_manifest(manifest)


static func _load_region_tile(region_id: String, cell: Vector2i) -> RegionTileData:
	var cache_key: String = _region_tile_cache_key(region_id, cell)
	var cached_tile_data: RegionTileData = _region_tile_cache_get(cache_key)
	if cached_tile_data != null:
		return _clone_region_tile_data(cached_tile_data)

	var loaded_tile_data: RegionTileData = _load_region_tile_uncached(region_id, cell)
	if loaded_tile_data == null:
		return null
	var stored_tile_data: RegionTileData = _region_tile_cache_store_or_get(cache_key, loaded_tile_data)
	return _clone_region_tile_data(stored_tile_data)


static func _load_region_tile_uncached(region_id: String, cell: Vector2i) -> RegionTileData:
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


static func _region_tile_cache_key(region_id: String, cell: Vector2i) -> String:
	return region_id + ":" + _tile_key(cell)


static func _region_tile_cache_get(cache_key: String) -> RegionTileData:
	_region_tile_cache_mutex.lock()
	var cached_variant: Variant = _region_tile_data_cache.get(cache_key, null)
	var cached_tile_data: RegionTileData = cached_variant as RegionTileData
	if cached_tile_data != null:
		_region_tile_cache_touch_locked(cache_key)
	_region_tile_cache_mutex.unlock()
	return cached_tile_data


static func _region_tile_cache_store_or_get(cache_key: String, tile_data: RegionTileData) -> RegionTileData:
	_region_tile_cache_mutex.lock()
	var cached_variant: Variant = _region_tile_data_cache.get(cache_key, null)
	var cached_tile_data: RegionTileData = cached_variant as RegionTileData
	if cached_tile_data != null:
		_region_tile_cache_touch_locked(cache_key)
		_region_tile_cache_mutex.unlock()
		return cached_tile_data

	_region_tile_data_cache[cache_key] = tile_data
	_region_tile_cache_order.append(cache_key)
	while _region_tile_cache_order.size() > REGION_TILE_DATA_CACHE_CAPACITY:
		var evicted_key: String = String(_region_tile_cache_order[0])
		_region_tile_cache_order.remove_at(0)
		_region_tile_data_cache.erase(evicted_key)
	_region_tile_cache_mutex.unlock()
	return tile_data


static func _region_tile_cache_touch_locked(cache_key: String) -> void:
	var cache_index: int = _region_tile_cache_order.find(cache_key)
	if cache_index >= 0:
		_region_tile_cache_order.remove_at(cache_index)
	_region_tile_cache_order.append(cache_key)


static func _clone_region_tile_data(source_tile_data: RegionTileData) -> RegionTileData:
	var tile_data: RegionTileData = RegionTileData.new()
	tile_data.cell = source_tile_data.cell
	tile_data.key = source_tile_data.key
	tile_data.tile_size_m = source_tile_data.tile_size_m
	tile_data.width = source_tile_data.width
	tile_data.depth = source_tile_data.depth
	tile_data.heightmap_path = source_tile_data.heightmap_path
	tile_data.surface_id_path = source_tile_data.surface_id_path
	tile_data.heights = source_tile_data.heights
	if source_tile_data.surface_image != null:
		tile_data.surface_image = source_tile_data.surface_image.duplicate() as Image
	return tile_data


static func clear_surface_index_tile_material_cache_for_tests() -> void:
	_surface_cache_mutex.lock()
	_surface_index_tile_material_cache.clear()
	_surface_index_tile_material_cache_order.clear()
	_surface_cache_mutex.unlock()


static func surface_index_tile_material_cache_size_for_tests() -> int:
	_surface_cache_mutex.lock()
	var cache_size: int = _surface_index_tile_material_cache.size()
	_surface_cache_mutex.unlock()
	return cache_size


static func clear_region_tile_data_cache_for_tests() -> void:
	_region_tile_cache_mutex.lock()
	_region_tile_data_cache.clear()
	_region_tile_cache_order.clear()
	_region_tile_cache_mutex.unlock()


static func region_tile_data_cache_size_for_tests() -> int:
	_region_tile_cache_mutex.lock()
	var cache_size: int = _region_tile_data_cache.size()
	_region_tile_cache_mutex.unlock()
	return cache_size


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
			_add_region_foliage_cell(root, tile_data_by_cell, cell_rect, foliage_cell, 0, REGION_FOLIAGE_LOD0_BASE_COUNT)
			_add_region_foliage_cell(root, tile_data_by_cell, cell_rect, foliage_cell, 1, REGION_FOLIAGE_LOD1_BASE_COUNT)
	return root


static func _add_region_foliage_cell(parent: Node3D, tile_data_by_cell: Dictionary[Vector2i, RegionTileData], cell_rect: Rect2, foliage_cell: Vector2i, lod_index: int, base_count: int) -> void:
	var cell_data: FoliageCellData = _build_region_foliage_cell_data(tile_data_by_cell, cell_rect, foliage_cell, lod_index, base_count)
	if cell_data == null:
		return
	_add_foliage_cell_from_data(parent, cell_data)


static func _build_region_foliage_cell_data(tile_data_by_cell: Dictionary[Vector2i, RegionTileData], cell_rect: Rect2, foliage_cell: Vector2i, lod_index: int, base_count: int) -> FoliageCellData:
	var audit: Dictionary[String, Variant] = {}
	return _build_region_foliage_cell_data_with_audit(tile_data_by_cell, cell_rect, foliage_cell, lod_index, base_count, audit)


static func _build_region_foliage_cell_data_with_audit(tile_data_by_cell: Dictionary[Vector2i, RegionTileData], cell_rect: Rect2, foliage_cell: Vector2i, lod_index: int, base_count: int, audit: Dictionary[String, Variant]) -> FoliageCellData:
	if cell_rect.size.x <= 0.0 or cell_rect.size.y <= 0.0:
		return null
	var species_data_list: Array[FoliageSpeciesCellData] = []
	var foliage_origin_xz: Vector2 = cell_rect.position + cell_rect.size * 0.5
	var cell_ground_y: float = _height_at_region_xz(tile_data_by_cell, foliage_origin_xz.x, foliage_origin_xz.y)
	var max_attempts: int = maxi(base_count * 3, base_count)
	for attempt in range(max_attempts):
		if _foliage_species_total_count(species_data_list) >= base_count:
			break
		var unit_x: float = _region_foliage_unit(foliage_cell, lod_index, attempt, 1)
		var unit_z: float = _region_foliage_unit(foliage_cell, lod_index, attempt, 2)
		var world_x: float = cell_rect.position.x + unit_x * cell_rect.size.x
		var world_z: float = cell_rect.position.y + unit_z * cell_rect.size.y
		var surface_id_value: int = _surface_id_value_at_region_xz(tile_data_by_cell, world_x, world_z)
		var species_id: StringName = _foliage_species_for_candidate(surface_id_value, foliage_cell, lod_index, attempt, world_x, world_z)
		if species_id == &"":
			continue
		var density: float = _foliage_density_for_surface_species(surface_id_value, species_id, world_x, world_z)
		if density <= 0.0:
			continue
		# Talus enrichment: boost boulder keep-probability on steep ground (cliff bases /
		# aprons) so rock clusters where real Zion piles it; flat benches stay sparse.
		# Deterministic — driven only by the candidate terrain normal, never Time/randi.
		# For boulders place == world (no grass-clump relocate), so this normal matches the
		# post-keep slope sample below.
		if species_id == FOLIAGE_SPECIES_BOULDER:
			var boulder_candidate_normal_y: float = _normal_at_region_xz(tile_data_by_cell, world_x, world_z).y
			density = minf(density * _boulder_slope_density_multiplier(boulder_candidate_normal_y), FOLIAGE_BOULDER_DENSITY_CAP)
		# Riparian gallery density band (Zion art-direction bible §2.3): ramp the cottonwood/willow/
		# riparian_grass keep-probability up inside the gallery core along the river so the corridor
		# reads as a continuous grove with a lush sedge understory; the multiplier tapers back to 1.0
		# by the fringe (RIPARIAN_GRASS_OUTER_M) so the green stays a ribbon and never blankets the
		# benches. Non-riparian species return 1.0 (untouched). Deterministic -- pure function of
		# species + candidate world position, no Time/randi.
		density = minf(density * _riparian_gallery_density_multiplier(species_id, world_x, world_z), 1.0)
		var keep_value: float = _foliage_keep_value_for_species(species_id, foliage_cell, lod_index, attempt)
		if keep_value > density:
			continue
		# Grass/riparian_grass/shrub gather into deterministic clumps (cluster centers + jittered
		# offsets) instead of an even per-cell fill, so the live band reads as tussocks with
		# bare gaps rather than a uniform fence. Species/density stay anchored to the candidate
		# sample (so non-clumped species and accepted counts are unchanged); only the render
		# transform is relocated and re-grounded on the clumped position.
		var is_grass_clump: bool = species_id == FOLIAGE_SPECIES_GRASS or species_id == FOLIAGE_SPECIES_RIPARIAN_GRASS or species_id == FOLIAGE_SPECIES_SHRUB
		var place_x: float = world_x
		var place_z: float = world_z
		if is_grass_clump:
			var clump_group: int = attempt / GRASS_CLUMP_ATTEMPTS_PER_CLUMP
			var clump_center_x: float = cell_rect.position.x + _region_foliage_unit(foliage_cell, lod_index, clump_group, GRASS_CLUMP_CENTER_SALT_X) * cell_rect.size.x
			var clump_center_z: float = cell_rect.position.y + _region_foliage_unit(foliage_cell, lod_index, clump_group, GRASS_CLUMP_CENTER_SALT_Z) * cell_rect.size.y
			place_x = clampf(clump_center_x + _grass_clump_offset_m(foliage_cell, lod_index, attempt, 0), cell_rect.position.x, cell_rect.position.x + cell_rect.size.x)
			place_z = clampf(clump_center_z + _grass_clump_offset_m(foliage_cell, lod_index, attempt, 1), cell_rect.position.y, cell_rect.position.y + cell_rect.size.y)
		var terrain_normal: Vector3 = _normal_at_region_xz(tile_data_by_cell, place_x, place_z)
		_record_foliage_slope_candidate(audit)
		if terrain_normal.y < FOLIAGE_MAX_SLOPE_NORMAL_Y and not _foliage_species_allows_steep_slope(species_id):
			_record_foliage_slope_rejection(audit)
			continue
		var height: float = _height_at_region_xz(tile_data_by_cell, place_x, place_z)
		if absf(height - cell_ground_y) > FOLIAGE_CELL_MAX_GROUND_DELTA_M:
			continue
		var yaw: float = deg_to_rad(_region_foliage_unit(foliage_cell, lod_index, attempt, 4) * 360.0)
		var width_scale: float = 0.82 + _region_foliage_unit(foliage_cell, lod_index, attempt, 5) * 0.42
		var height_scale: float = 0.78 + _region_foliage_unit(foliage_cell, lod_index, attempt, 6) * 0.54
		if _foliage_species_uses_source_material(species_id):
			width_scale = 0.84 + _region_foliage_unit(foliage_cell, lod_index, attempt, 5) * 0.34
			height_scale = 0.82 + _region_foliage_unit(foliage_cell, lod_index, attempt, 6) * 0.42
		elif species_id == FOLIAGE_SPECIES_BOULDER:
			width_scale = lerpf(FOLIAGE_BOULDER_WIDTH_MIN, FOLIAGE_BOULDER_WIDTH_MAX, _region_foliage_unit(foliage_cell, lod_index, attempt, 5))
			height_scale = lerpf(FOLIAGE_BOULDER_HEIGHT_MIN, FOLIAGE_BOULDER_HEIGHT_MAX, _region_foliage_unit(foliage_cell, lod_index, attempt, 6))
		var base_scale: Vector3 = _foliage_base_scale_for_lod_species(lod_index, species_id)
		var basis: Basis
		if is_grass_clump:
			basis = _grass_clump_basis(base_scale, width_scale, height_scale, foliage_cell, lod_index, attempt, yaw)
		elif species_id == FOLIAGE_SPECIES_BOULDER:
			basis = _boulder_instance_basis(base_scale, width_scale, height_scale, foliage_cell, lod_index, attempt, yaw)
		else:
			basis = Basis(Vector3.UP, yaw).scaled(Vector3(base_scale.x * width_scale, base_scale.y * height_scale, base_scale.z * width_scale))
		var species_data: FoliageSpeciesCellData = _foliage_species_data_from_list(species_data_list, species_id)
		var y_offset: float = REGION_FOLIAGE_Y_OFFSET
		if species_id == FOLIAGE_SPECIES_BOULDER:
			y_offset = -lerpf(FOLIAGE_BOULDER_GROUND_SINK_MIN_M, FOLIAGE_BOULDER_GROUND_SINK_MAX_M, _region_foliage_unit(foliage_cell, lod_index, attempt, 5))
		species_data.transforms.append(Transform3D(basis, Vector3(place_x, height + y_offset, place_z)))
		_record_foliage_acceptance(audit, terrain_normal.y, species_id)
		_record_foliage_species_acceptance(audit, species_id)
		var color_warmth: float = _region_foliage_unit(foliage_cell, lod_index, attempt, 7)
		if is_grass_clump:
			species_data.colors.append(_grass_clump_instance_color(species_id, color_warmth, foliage_cell, lod_index, attempt))
		else:
			species_data.colors.append(_foliage_instance_color(species_id, color_warmth))
		var wind_weight: float = 0.45 + _region_foliage_unit(foliage_cell, lod_index, attempt, 8) * 0.55
		var wind_phase: float = _region_foliage_unit(foliage_cell, lod_index, attempt, 9)
		var wind_flutter: float = _region_foliage_unit(foliage_cell, lod_index, attempt, 10)
		var tip_shift: float = _region_foliage_unit(foliage_cell, lod_index, attempt, 11)
		species_data.custom_data.append(Color(wind_weight, wind_phase, wind_flutter, tip_shift))

	if _foliage_species_total_count(species_data_list) <= 0:
		return null

	var foliage_cell_radius: float = cell_rect.size.length() * 0.5
	var cell_data: FoliageCellData = FoliageCellData.new()
	cell_data.lod_index = lod_index
	cell_data.node_name = "foliage_cell_" + str(foliage_cell.x) + "_" + str(foliage_cell.y) + "_lod" + str(lod_index)
	cell_data.position = Vector3(foliage_origin_xz.x, cell_ground_y, foliage_origin_xz.y)
	cell_data.visibility_radius = foliage_cell_radius
	cell_data.species = species_data_list
	if lod_index == 0:
		cell_data.visibility_range_end = _foliage_lod0_visibility_range_end(foliage_cell_radius)
		cell_data.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	else:
		cell_data.visibility_range_begin = _foliage_lod1_visibility_range_begin(foliage_cell_radius)
		cell_data.visibility_range_end = _foliage_lod1_visibility_range_end(foliage_cell_radius)
		cell_data.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for species_data in cell_data.species:
		for i in range(species_data.transforms.size()):
			var transform: Transform3D = species_data.transforms[i]
			transform.origin.x -= foliage_origin_xz.x
			transform.origin.y -= cell_ground_y
			transform.origin.z -= foliage_origin_xz.y
			species_data.transforms[i] = transform
	cell_data.custom_aabb = _foliage_cell_custom_aabb_from_instances(cell_data)
	_pack_foliage_cell_buffer(cell_data)
	return cell_data


static func _foliage_cell_custom_aabb_from_instances(cell_data: FoliageCellData) -> AABB:
	var has_bounds: bool = false
	var min_x: float = 0.0
	var min_y: float = 0.0
	var min_z: float = 0.0
	var max_x: float = 0.0
	var max_y: float = 0.0
	var max_z: float = 0.0
	var h_radius: float = _foliage_max_lod0_horizontal_radius()
	var horizontal_margin: float = h_radius + REGION_FOLIAGE_CULL_MARGIN
	var foliage_height: float = _foliage_max_lod0_height() + REGION_FOLIAGE_CULL_MARGIN
	for species_data in cell_data.species:
		for transform in species_data.transforms:
			var origin: Vector3 = transform.origin
			if not has_bounds:
				min_x = origin.x
				min_y = origin.y
				min_z = origin.z
				max_x = origin.x
				max_y = origin.y + foliage_height
				max_z = origin.z
				has_bounds = true
			else:
				min_x = minf(min_x, origin.x)
				min_y = minf(min_y, origin.y)
				min_z = minf(min_z, origin.z)
				max_x = maxf(max_x, origin.x)
				max_y = maxf(max_y, origin.y + foliage_height)
				max_z = maxf(max_z, origin.z)
	if not has_bounds:
		return AABB()
	return AABB(
		Vector3(min_x - horizontal_margin, min_y - REGION_FOLIAGE_CULL_MARGIN, min_z - horizontal_margin),
		Vector3(
			maxf(max_x - min_x, 0.0) + horizontal_margin * 2.0,
			maxf(max_y - min_y, 0.0) + REGION_FOLIAGE_CULL_MARGIN * 2.0,
			maxf(max_z - min_z, 0.0) + horizontal_margin * 2.0
		)
	)


static func _pack_foliage_cell_buffer(cell_data: FoliageCellData) -> void:
	for species_data in cell_data.species:
		_pack_foliage_species_buffer(species_data)


static func _build_foliage_cell_multimeshes(cell_data: FoliageCellData) -> void:
	for species_data in cell_data.species:
		species_data.multimesh = _build_foliage_species_multimesh(cell_data, species_data)


static func _build_foliage_species_multimesh(cell_data: FoliageCellData, species_data: FoliageSpeciesCellData) -> MultiMesh:
	if species_data.transforms.is_empty():
		return null
	var multimesh: MultiMesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.custom_aabb = cell_data.custom_aabb
	# Set mesh BEFORE instance_count (matches the pipeline-warmup order). Assigning MultiMesh.mesh
	# AFTER instance_count re-initializes (zeros) the buffer in Godot 4.x; doing it first means the
	# worker-built buffer survives and the main-thread commit doesn't need to re-assign mesh/buffer.
	# The foliage mesh cache is pre-warmed before workers start, so this lookup is a pure cache read.
	multimesh.mesh = _region_foliage_mesh_for_lod_species(cell_data.lod_index, species_data.species_id)
	multimesh.instance_count = species_data.transforms.size()
	multimesh.buffer = species_data.packed_buffer
	return multimesh


static func _pack_foliage_species_buffer(species_data: FoliageSpeciesCellData) -> void:
	var instance_count: int = species_data.transforms.size()
	var buffer: PackedFloat32Array = PackedFloat32Array()
	buffer.resize(instance_count * FOLIAGE_MULTIMESH_FLOATS_PER_INSTANCE)
	var write_index: int = 0
	for i in range(instance_count):
		var transform: Transform3D = species_data.transforms[i]
		# Godot 4.6 MultiMesh.buffer is ROW-MAJOR: row r = [basis.x[r], basis.y[r], basis.z[r], origin[r]].
		# (Was column-major, which collapsed every instance's origin to ~0 → foliage rendered 1197m
		# underground = invisible. Verified against MultiMesh.set_instance_transform's packing.)
		buffer[write_index] = transform.basis.x.x
		buffer[write_index + 1] = transform.basis.y.x
		buffer[write_index + 2] = transform.basis.z.x
		buffer[write_index + 3] = transform.origin.x
		buffer[write_index + 4] = transform.basis.x.y
		buffer[write_index + 5] = transform.basis.y.y
		buffer[write_index + 6] = transform.basis.z.y
		buffer[write_index + 7] = transform.origin.y
		buffer[write_index + 8] = transform.basis.x.z
		buffer[write_index + 9] = transform.basis.y.z
		buffer[write_index + 10] = transform.basis.z.z
		buffer[write_index + 11] = transform.origin.z
		var color: Color = species_data.colors[i]
		buffer[write_index + 12] = color.r
		buffer[write_index + 13] = color.g
		buffer[write_index + 14] = color.b
		buffer[write_index + 15] = color.a
		var custom: Color = species_data.custom_data[i]
		buffer[write_index + 16] = custom.r
		buffer[write_index + 17] = custom.g
		buffer[write_index + 18] = custom.b
		buffer[write_index + 19] = custom.a
		write_index += FOLIAGE_MULTIMESH_FLOATS_PER_INSTANCE
	species_data.packed_buffer = buffer


static func _add_foliage_cell_from_data(parent: Node3D, cell_data: FoliageCellData) -> void:
	for species_data in cell_data.species:
		_add_foliage_species_cell_from_data(parent, cell_data, species_data)


static func _add_foliage_species_cell_from_data(parent: Node3D, cell_data: FoliageCellData, species_data: FoliageSpeciesCellData) -> void:
	if species_data.transforms.is_empty():
		return
	var instance: MultiMeshInstance3D = MultiMeshInstance3D.new()
	instance.name = cell_data.node_name + "_" + String(species_data.species_id)
	instance.position = cell_data.position
	var material: Material = _region_foliage_material_for_lod_species(cell_data.lod_index, species_data.species_id)
	if material != null:
		instance.material_override = material
	instance.extra_cull_margin = _foliage_max_lod0_horizontal_radius() + REGION_FOLIAGE_CULL_MARGIN
	var species_id: StringName = species_data.species_id
	var cell_radius: float = cell_data.visibility_radius
	var fade_margin: float = foliage_visibility_range_fade_margin_for_species(species_id)
	instance.visibility_range_fade_mode = foliage_visibility_range_fade_mode_for_lod(cell_data.lod_index)
	if cell_data.lod_index <= 0:
		# LOD0: visible up close, fades out over the end margin at the handoff into LOD1.
		instance.visibility_range_begin = 0.0
		instance.visibility_range_end = foliage_lod0_visibility_range_end_for_species(cell_radius, species_id)
		instance.visibility_range_begin_margin = 0.0
		instance.visibility_range_end_margin = fade_margin
	else:
		# LOD1: fades in over the begin margin. Grass/scrub fade out after the near-field band;
		# trees and boulders run to cam_far. LOD1.begin == LOD0.end preserves the manual-LOD
		# handoff invariant (see helper doc).
		instance.visibility_range_begin = foliage_lod1_visibility_range_begin_for_species(cell_radius, species_id)
		instance.visibility_range_end = foliage_lod1_visibility_range_end_for_species(cell_radius, species_id)
		instance.visibility_range_begin_margin = fade_margin
		instance.visibility_range_end_margin = fade_margin
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cell_data.lod_index == 0 and _foliage_species_uses_source_material(species_id) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.set_meta(REGION_LOD_META, "foliage_lod" + str(cell_data.lod_index))
	instance.set_meta(&"trailhead_foliage_species", species_data.species_id)
	instance.set_meta(VISIBILITY_RADIUS_META, cell_data.visibility_radius)
	var multimesh: MultiMesh = species_data.multimesh
	if multimesh == null:
		multimesh = _build_foliage_species_multimesh(cell_data, species_data)
	if multimesh == null:
		return
	# mesh + buffer are already set by _build_foliage_species_multimesh (mesh BEFORE instance_count,
	# so the buffer is not re-zeroed). No main-thread mesh/buffer re-assignment needed.
	instance.multimesh = multimesh
	parent.add_child(instance)


static func _region_foliage_mesh_for_lod(lod_index: int) -> Mesh:
	return _region_foliage_mesh_for_lod_species(lod_index, FOLIAGE_SPECIES_GRASS)


static func _region_foliage_mesh_for_lod_species(lod_index: int, species_id: StringName) -> Mesh:
	_surface_cache_mutex.lock()
	var mesh: Mesh = _region_foliage_mesh_for_lod_species_locked(lod_index, species_id)
	_surface_cache_mutex.unlock()
	return mesh


static func _region_foliage_mesh_for_lod_species_locked(lod_index: int, species_id: StringName) -> Mesh:
	var safe_lod_index: int = _region_foliage_lod_index(lod_index)
	var cache_key: String = String(species_id) + "_lod" + str(safe_lod_index)
	if _foliage_mesh_cache.has(cache_key):
		return _foliage_mesh_cache[cache_key]
	var mesh: Mesh = null
	if species_id == FOLIAGE_SPECIES_YUCCA:
		mesh = _region_yucca_mesh("region_foliage_yucca_lod" + str(safe_lod_index) + "_mesh", safe_lod_index)
	elif species_id == FOLIAGE_SPECIES_JUNIPER:
		mesh = _region_juniper_mesh("region_foliage_juniper_lod" + str(safe_lod_index) + "_mesh", safe_lod_index)
	elif species_id == FOLIAGE_SPECIES_WILLOW:
		mesh = _region_willow_mesh("region_foliage_willow_lod" + str(safe_lod_index) + "_mesh", safe_lod_index)
	elif species_id == FOLIAGE_SPECIES_COTTONWOOD:
		mesh = _region_cottonwood_mesh("region_foliage_cottonwood_lod" + str(safe_lod_index) + "_mesh", safe_lod_index)
	elif species_id == FOLIAGE_SPECIES_BOULDER:
		mesh = _region_boulder_mesh("region_foliage_boulder_lod" + str(safe_lod_index) + "_mesh", safe_lod_index)
	else:
		mesh = _region_foliage_mesh("region_foliage_" + String(species_id) + "_lod" + str(safe_lod_index) + "_mesh")
	_foliage_mesh_cache[cache_key] = mesh
	return mesh


static func _region_foliage_material_for_lod(lod_index: int) -> Material:
	return _region_foliage_material_for_lod_species(lod_index, FOLIAGE_SPECIES_GRASS)


static func _region_foliage_material_for_lod_species(lod_index: int, species_id: StringName) -> Material:
	var safe_lod_index: int = _region_foliage_lod_index(lod_index)
	if _foliage_species_uses_source_material(species_id):
		return null
	var cache_key: String = String(species_id) + "_lod" + str(safe_lod_index)
	if _foliage_material_cache.has(cache_key):
		return _foliage_material_cache[cache_key]
	if species_id == FOLIAGE_SPECIES_BOULDER:
		var boulder_material: Material = _region_boulder_material("region_foliage_boulder_lod" + str(safe_lod_index) + "_material")
		_foliage_material_cache[cache_key] = boulder_material
		return boulder_material
	var material_color: Color = _foliage_material_color_for_species(species_id)
	if safe_lod_index > 0:
		material_color = material_color.lerp(Color(0.30, 0.32, 0.24, material_color.a), 0.22)
	var blade_height_reference: float = _foliage_base_scale_for_lod_species(safe_lod_index, species_id).y
	var material: Material = _region_foliage_material("region_foliage_" + String(species_id) + "_lod" + str(safe_lod_index) + "_material", material_color, blade_height_reference, species_id)
	_foliage_material_cache[cache_key] = material
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
	var original_vertex_count: int = vertices.size()
	var original_index_count: int = indices.size()
	for vertex_index in range(original_vertex_count):
		vertices.append(vertices[vertex_index])
		normals.append(-normals[vertex_index])
		uvs.append(uvs[vertex_index])
	for index in range(0, original_index_count, 3):
		indices.append(indices[index] + original_vertex_count)
		indices.append(indices[index + 2] + original_vertex_count)
		indices.append(indices[index + 1] + original_vertex_count)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _region_yucca_mesh(mesh_name: String, _lod_index: int) -> Mesh:
	return _extract_first_mesh(YuccaTreeScene, mesh_name, FOLIAGE_SPECIES_YUCCA)


static func _region_juniper_mesh(mesh_name: String, _lod_index: int) -> Mesh:
	return _extract_first_mesh(JuniperTreeScene, mesh_name, FOLIAGE_SPECIES_JUNIPER)


static func _region_willow_mesh(mesh_name: String, lod_index: int) -> Mesh:
	var lod_node_names: Array[String] = [
		"willow_lod" + str(lod_index),
	]
	return _extract_named_or_first_mesh(WillowTreeScene, mesh_name, lod_node_names, FOLIAGE_SPECIES_WILLOW)


static func _region_cottonwood_mesh(mesh_name: String, lod_index: int) -> Mesh:
	var lod_node_names: Array[String] = [
		"cottonwood_lod" + str(lod_index),
	]
	return _extract_named_or_first_mesh(CottonwoodTreeScene, mesh_name, lod_node_names, FOLIAGE_SPECIES_COTTONWOOD)


static func _extract_named_or_first_mesh(scene: PackedScene, node_name: String, lod_node_names: Array[String], species_id: StringName = &"") -> Mesh:
	var root: Node = scene.instantiate()
	if root == null:
		push_error("TerrainVisualBuilder: failed to instantiate " + node_name)
		return null
	var mesh: Mesh = null
	for name_index in range(lod_node_names.size()):
		var lod_node_name: String = lod_node_names[name_index]
		mesh = _find_mesh_by_node_name(root, lod_node_name)
		if mesh != null:
			break
	if mesh == null:
		mesh = _find_first_mesh(root)
	root.free()
	if mesh == null:
		push_error("TerrainVisualBuilder: failed to extract mesh from " + node_name)
		return null
	if species_id != &"":
		return _source_foliage_mesh_with_species_materials(mesh, node_name, species_id)
	return mesh


static func _extract_first_mesh(scene: PackedScene, node_name: String, species_id: StringName = &"") -> Mesh:
	var root: Node = scene.instantiate()
	if root == null:
		push_error("TerrainVisualBuilder: failed to instantiate " + node_name)
		return null
	var mesh: Mesh = _find_first_mesh(root)
	root.free()
	if mesh == null:
		push_error("TerrainVisualBuilder: failed to extract mesh from " + node_name)
		return null
	if species_id != &"":
		return _source_foliage_mesh_with_species_materials(mesh, node_name, species_id)
	return mesh


static func _find_first_mesh(parent: Node) -> Mesh:
	var mesh_instance: MeshInstance3D = parent as MeshInstance3D
	if mesh_instance != null and mesh_instance.mesh != null:
		return mesh_instance.mesh
	for child in parent.get_children():
		var child_mesh: Mesh = _find_first_mesh(child)
		if child_mesh != null:
			return child_mesh
	return null


static func _find_mesh_by_node_name(parent: Node, target_name: String) -> Mesh:
	if String(parent.name) == target_name:
		var mesh_instance: MeshInstance3D = parent as MeshInstance3D
		if mesh_instance != null and mesh_instance.mesh != null:
			return mesh_instance.mesh
	for child in parent.get_children():
		var child_mesh: Mesh = _find_mesh_by_node_name(child, target_name)
		if child_mesh != null:
			return child_mesh
	return null


static func _source_foliage_mesh_with_species_materials(source_mesh: Mesh, mesh_name: String, species_id: StringName) -> Mesh:
	var mesh: ArrayMesh = source_mesh.duplicate(true) as ArrayMesh
	if mesh == null:
		return source_mesh
	mesh.resource_name = mesh_name
	for surface_index in range(mesh.get_surface_count()):
		var source_material: StandardMaterial3D = mesh.surface_get_material(surface_index) as StandardMaterial3D
		if source_material == null:
			continue
		var material: StandardMaterial3D = source_material.duplicate(true) as StandardMaterial3D
		if material == null:
			continue
		if _foliage_source_material_is_leaf(species_id, material, surface_index):
			# GLB species intentionally keep no material_override; tint cloned leaf surfaces here
			# so bark/source-material rendering and the streamer warmup contract stay intact.
			var leaf_color: Color = _foliage_material_color_for_species(species_id)
			material.albedo_color = Color(leaf_color.r, leaf_color.g, leaf_color.b, material.albedo_color.a)
			# Willow/cottonwood leaf cards import from glTF alphaMode=MASK as a hard
			# alpha-scissor cutout; under TAA+FSR1 the sub-pixel leaf edges flip binary
			# coverage every jittered frame and shimmer. These trees are static MultiMesh
			# (no wind), so alpha-to-coverage lets the existing MSAA resolve the cutout edge
			# with sub-pixel coverage that survives the jitter — the correct stabiliser for a
			# non-animated cutout (opposite of the animated-grass A2C removal). Gate strictly
			# on the alpha-scissor transparency mode so opaque juniper/yucca leaves and all
			# bark surfaces are never touched; keep the imported scissor threshold intact.
			if material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
				material.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE_AND_TO_ONE
				# Tame leaf-highlight sparkle that FSR1 amplifies on the cutout edge: push
				# roughness toward matte and disable the specular lobe. Colour is unchanged.
				material.roughness = maxf(material.roughness, 0.9)
				material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		mesh.surface_set_material(surface_index, material)
	return mesh


static func _foliage_source_material_is_leaf(species_id: StringName, material: StandardMaterial3D, surface_index: int) -> bool:
	var material_name: String = material.resource_name.to_lower()
	if material_name.find("leaf") >= 0 or material_name.find("leaves") >= 0:
		return true
	if species_id == FOLIAGE_SPECIES_YUCCA:
		return surface_index == 0
	return surface_index == 1


static func _region_boulder_mesh(mesh_name: String, lod_index: int) -> ArrayMesh:
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.resource_name = mesh_name
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var indices: PackedInt32Array = PackedInt32Array()
	var points: Array[Vector3] = [
		Vector3(0.0, 0.62, 0.0),
		Vector3(0.0, -0.20, 0.0),
		Vector3(-0.58, 0.06, 0.0),
		Vector3(0.64, 0.02, 0.0),
		Vector3(0.0, 0.10, -0.48),
		Vector3(0.0, 0.04, 0.56),
		Vector3(-0.32, 0.28, -0.34),
		Vector3(0.36, 0.24, -0.28),
		Vector3(0.30, 0.22, 0.38),
		Vector3(-0.36, 0.25, 0.32),
	]
	var faces: Array[PackedInt32Array] = [
		PackedInt32Array([0, 6, 7]),
		PackedInt32Array([0, 7, 8]),
		PackedInt32Array([0, 8, 9]),
		PackedInt32Array([0, 9, 6]),
		PackedInt32Array([6, 4, 7]),
		PackedInt32Array([7, 4, 3]),
		PackedInt32Array([7, 3, 8]),
		PackedInt32Array([8, 3, 5]),
		PackedInt32Array([8, 5, 9]),
		PackedInt32Array([9, 5, 2]),
		PackedInt32Array([9, 2, 6]),
		PackedInt32Array([6, 2, 4]),
		PackedInt32Array([1, 7, 4]),
		PackedInt32Array([1, 3, 7]),
		PackedInt32Array([1, 8, 3]),
		PackedInt32Array([1, 5, 8]),
		PackedInt32Array([1, 9, 5]),
		PackedInt32Array([1, 2, 9]),
		PackedInt32Array([1, 6, 2]),
		PackedInt32Array([1, 4, 6]),
	]
	var face_limit: int = faces.size()
	if lod_index > 0:
		face_limit = 12
	for face_index in range(face_limit):
		var face: PackedInt32Array = faces[face_index]
		_append_boulder_triangle(vertices, normals, uvs, indices, points[face[0]], points[face[1]], points[face[2]])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _append_boulder_triangle(vertices: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, indices: PackedInt32Array, a: Vector3, b: Vector3, c: Vector3) -> void:
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


static func _region_foliage_material(material_name: String, color: Color, blade_height_reference: float, species_id: StringName) -> ShaderMaterial:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.resource_name = material_name
	material.shader = GrassShader
	material.set_shader_parameter("blade_base_color", Color(color.r * 0.72, color.g * 0.72, color.b * 0.70, color.a))
	material.set_shader_parameter(
		"blade_tip_color",
		Color(
			minf(color.r * FOLIAGE_NEON_TAME_TIP_BOOST.x, 1.0),
			minf(color.g * FOLIAGE_NEON_TAME_TIP_BOOST.y, 1.0),
			minf(color.b * FOLIAGE_NEON_TAME_TIP_BOOST.z, 1.0),
			color.a
		)
	)
	material.set_shader_parameter("blade_height_reference", blade_height_reference)
	material.set_shader_parameter("wind_strength", 0.035)
	material.set_shader_parameter("wind_speed", 0.75)
	material.set_shader_parameter("wind_time_factor", 0.018)
	# Travelling-wave wind desyncs neighbouring clumps (ripple) and brings wind in moving
	# gusts; per-instance tint jitter breaks the single-color plastic read. See the shader.
	material.set_shader_parameter("wind_world_wavelength_primary", FOLIAGE_WIND_WORLD_WAVELENGTH_PRIMARY)
	material.set_shader_parameter("wind_world_wavelength_gust", FOLIAGE_WIND_WORLD_WAVELENGTH_GUST)
	material.set_shader_parameter("per_instance_saturation_jitter", FOLIAGE_INSTANCE_SATURATION_JITTER)
	material.set_shader_parameter("per_instance_value_jitter", FOLIAGE_INSTANCE_VALUE_JITTER)
	material.set_shader_parameter("backlight_color", Color(0.95, 0.74, 0.42, 1.0))
	material.set_shader_parameter("backlight_energy", FOLIAGE_NEON_TAME_BACKLIGHT_ENERGY)
	var is_tree: bool = (species_id == FOLIAGE_SPECIES_WILLOW or species_id == FOLIAGE_SPECIES_COTTONWOOD)
	material.set_shader_parameter("canopy_cutout", 1.0 if is_tree else 0.0)
	return material


static func _region_boulder_material(material_name: String) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.resource_name = material_name
	material.albedo_color = FOLIAGE_SPECIES_BOULDER_COLOR
	material.roughness = 0.92
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
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


static func _normal_at_region_xz(tile_data_by_cell: Dictionary[Vector2i, RegionTileData], world_x: float, world_z: float) -> Vector3:
	var tile_data: RegionTileData = _tile_data_for_region_xz(tile_data_by_cell, world_x, world_z)
	if tile_data == null:
		return Vector3.UP
	var local_x: float = clampf(world_x - float(tile_data.cell.x) * tile_data.tile_size_m, 0.0, tile_data.tile_size_m)
	var local_z: float = clampf(world_z - float(tile_data.cell.y) * tile_data.tile_size_m, 0.0, tile_data.tile_size_m)
	var col: int = int(floor(local_x / tile_data.tile_size_m * float(tile_data.width - 1) + 0.5))
	var row: int = int(floor(local_z / tile_data.tile_size_m * float(tile_data.depth - 1) + 0.5))
	return _tile_normal(tile_data, col, row)


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


static func _new_region_foliage_tile_audit(cell: Vector2i) -> Dictionary[String, Variant]:
	return {
		"ok": false,
		"cell": cell,
		"message": "",
		"surface_pixel_count": 0,
		"dominant_surface_id_value": 0,
		"dominant_surface_share": 0.0,
		"surface_id_1_share": 0.0,
		"surface_id_2_share": 0.0,
		"surface_id_3_share": 0.0,
		"surface_id_4_share": 0.0,
		"surface_id_5_share": 0.0,
		"surface_id_6_share": 0.0,
		"slope_checked_count": 0,
		"slope_rejected_count": 0,
		"slope_violation_count": 0,
		"instance_count": 0,
		"grass_instance_count": 0,
		"riparian_grass_instance_count": 0,
		"shrub_instance_count": 0,
		"yucca_instance_count": 0,
		"juniper_instance_count": 0,
		"willow_instance_count": 0,
		"cottonwood_instance_count": 0,
		"boulder_instance_count": 0,
		"min_accepted_normal_y": 1.0,
	}


static func _add_region_foliage_surface_audit(audit: Dictionary[String, Variant], tile_data: RegionTileData) -> void:
	var surface_counts: Dictionary[int, int] = _surface_counts_for_tile(tile_data)
	var total_pixel_count: int = 0
	var dominant_surface_id_value: int = 0
	var dominant_surface_count: int = 0
	for surface_id_value in surface_counts.keys():
		var surface_count: int = surface_counts[surface_id_value]
		total_pixel_count += surface_count
		if surface_count > dominant_surface_count:
			dominant_surface_id_value = surface_id_value
			dominant_surface_count = surface_count
	audit["surface_pixel_count"] = total_pixel_count
	if total_pixel_count <= 0:
		return
	audit["dominant_surface_id_value"] = dominant_surface_id_value
	audit["dominant_surface_share"] = float(dominant_surface_count) / float(total_pixel_count)
	audit["surface_id_1_share"] = _surface_count_share(surface_counts, total_pixel_count, 1)
	audit["surface_id_2_share"] = _surface_count_share(surface_counts, total_pixel_count, 2)
	audit["surface_id_3_share"] = _surface_count_share(surface_counts, total_pixel_count, 3)
	audit["surface_id_4_share"] = _surface_count_share(surface_counts, total_pixel_count, 4)
	audit["surface_id_5_share"] = _surface_count_share(surface_counts, total_pixel_count, 5)
	audit["surface_id_6_share"] = _surface_count_share(surface_counts, total_pixel_count, 6)


static func _surface_counts_for_tile(tile_data: RegionTileData) -> Dictionary[int, int]:
	var surface_counts: Dictionary[int, int] = {}
	if tile_data.surface_image == null or tile_data.surface_image.is_empty():
		return surface_counts
	for row in range(tile_data.surface_image.get_height()):
		for col in range(tile_data.surface_image.get_width()):
			var surface_id_value: int = _surface_id_value_at(tile_data, col, row)
			surface_counts[surface_id_value] = int(surface_counts.get(surface_id_value, 0)) + 1
	return surface_counts


static func _surface_count_share(surface_counts: Dictionary[int, int], total_pixel_count: int, surface_id_value: int) -> float:
	if total_pixel_count <= 0:
		return 0.0
	return float(int(surface_counts.get(surface_id_value, 0))) / float(total_pixel_count)


static func _record_foliage_slope_candidate(audit: Dictionary[String, Variant]) -> void:
	if audit.is_empty():
		return
	audit["slope_checked_count"] = int(audit.get("slope_checked_count", 0)) + 1


static func _record_foliage_slope_rejection(audit: Dictionary[String, Variant]) -> void:
	if audit.is_empty():
		return
	audit["slope_rejected_count"] = int(audit.get("slope_rejected_count", 0)) + 1


static func _record_foliage_acceptance(audit: Dictionary[String, Variant], normal_y: float, species_id: StringName) -> void:
	if audit.is_empty():
		return
	audit["instance_count"] = int(audit.get("instance_count", 0)) + 1
	# Steep-slope-allowed species (boulders rest on talus) bypass the foliage slope gate by
	# design, so they must not register as slope violations nor drag down min_accepted_normal_y.
	if _foliage_species_allows_steep_slope(species_id):
		return
	var min_accepted_normal_y: float = float(audit.get("min_accepted_normal_y", 1.0))
	if normal_y < min_accepted_normal_y:
		audit["min_accepted_normal_y"] = normal_y
	if normal_y < FOLIAGE_MAX_SLOPE_NORMAL_Y:
		audit["slope_violation_count"] = int(audit.get("slope_violation_count", 0)) + 1


static func _record_foliage_species_acceptance(audit: Dictionary[String, Variant], species_id: StringName) -> void:
	if audit.is_empty():
		return
	var key: String = String(species_id) + "_instance_count"
	audit[key] = int(audit.get(key, 0)) + 1


static func _boulder_slope_density_multiplier(normal_y: float) -> float:
	# Flat ground should read as vegetation, not a boulder carpet; steeper ground (lower
	# normal.y -- cliff bases / talus aprons) ramps boulders up to the talus boost, saturating
	# below FOLIAGE_BOULDER_TALUS_STEEP_NORMAL_Y. Pure function of the terrain normal.
	var flat_y: float = FOLIAGE_MAX_SLOPE_NORMAL_Y
	if normal_y >= flat_y:
		return FOLIAGE_BOULDER_FLAT_DENSITY_MUL
	var steep_t: float = clampf((flat_y - normal_y) / maxf(flat_y - FOLIAGE_BOULDER_TALUS_STEEP_NORMAL_Y, 0.0001), 0.0, 1.0)
	return lerpf(FOLIAGE_BOULDER_FLAT_DENSITY_MUL, FOLIAGE_BOULDER_TALUS_DENSITY_BOOST, steep_t)


static func _boulder_instance_basis(base_scale: Vector3, width_scale: float, height_scale: float, foliage_cell: Vector2i, lod_index: int, attempt: int, yaw: float) -> Basis:
	# Full-yaw boulder plus a deterministic per-instance lean (axis azimuth from
	# FOLIAGE_BOULDER_TILT_AXIS_SALT, magnitude bounded by FOLIAGE_BOULDER_TILT_MAX_DEG via
	# FOLIAGE_BOULDER_TILT_SALT) so each rock settles at its own attitude instead of sitting
	# perfectly plumb -- real talus tumbles. Then non-uniform width/height scale.
	var tilt_axis_yaw: float = _region_foliage_unit(foliage_cell, lod_index, attempt, FOLIAGE_BOULDER_TILT_AXIS_SALT) * TAU
	var tilt_amount: float = deg_to_rad(lerpf(-FOLIAGE_BOULDER_TILT_MAX_DEG, FOLIAGE_BOULDER_TILT_MAX_DEG, _region_foliage_unit(foliage_cell, lod_index, attempt, FOLIAGE_BOULDER_TILT_SALT)))
	var tilt_axis: Vector3 = Vector3(cos(tilt_axis_yaw), 0.0, sin(tilt_axis_yaw))
	var basis: Basis = Basis(Vector3.UP, yaw) * Basis(tilt_axis, tilt_amount)
	return basis.scaled(Vector3(base_scale.x * width_scale, base_scale.y * height_scale, base_scale.z * width_scale))


static func _foliage_density_for_surface_value(surface_id_value: int) -> float:
	return _foliage_density_for_surface_species(surface_id_value, _foliage_species_for_surface_value(surface_id_value))


static func _foliage_density_for_surface_species(surface_id_value: int, species_id: StringName, world_x: float = -1.0, world_z: float = -1.0) -> float:
	if not bool(TerrainSurfacePaletteResource.call("has_surface_id_value", surface_id_value)):
		return 0.0
	var surface_id: StringName = _surface_id_for_value(surface_id_value)
	if species_id == FOLIAGE_SPECIES_RIPARIAN_GRASS:
		return GameConfig.riparian_grass_density
	if species_id == FOLIAGE_SPECIES_WILLOW:
		if surface_id == &"wet_stone":
			return GameConfig.riparian_willow_density * 0.65
		return GameConfig.riparian_willow_density
	if species_id == FOLIAGE_SPECIES_COTTONWOOD:
		if surface_id == &"wet_stone":
			return 0.0
		return GameConfig.riparian_cottonwood_density
	if species_id == FOLIAGE_SPECIES_GRASS and surface_id == &"packed_gravel":
		return GameConfig.scrub_density_packed_gravel
	if species_id == FOLIAGE_SPECIES_GRASS and surface_id == &"paved_road":
		return GameConfig.scrub_density_paved_road
	if species_id == FOLIAGE_SPECIES_GRASS and surface_id == &"wet_stone":
		return GameConfig.scrub_density_wet_stone
	if species_id == FOLIAGE_SPECIES_GRASS and surface_id == &"mud":
		return GameConfig.scrub_density_mud
	if species_id == FOLIAGE_SPECIES_GRASS and surface_id == &"loose_rock" and _foliage_is_corridor_scrub_position(world_x, world_z):
		return GameConfig.scrub_density_loose_rock_corridor
	if species_id == FOLIAGE_SPECIES_BOULDER and surface_id == &"packed_gravel":
		return GameConfig.boulder_density_packed_gravel
	if species_id == FOLIAGE_SPECIES_BOULDER and surface_id == &"loose_rock":
		return GameConfig.boulder_density_loose_rock
	if surface_id == &"loose_rock":
		return FOLIAGE_DENSITY_LOOSE_ROCK
	if species_id == FOLIAGE_SPECIES_SHRUB and _foliage_is_bench_surface(surface_id):
		return GameConfig.scrub_density_bench_shrub
	if surface_id == &"packed_dirt":
		return FOLIAGE_DENSITY_PACKED_DIRT
	if surface_id == &"tall_grass":
		return FOLIAGE_DENSITY_TALL_GRASS
	if surface_id == &"mud":
		return FOLIAGE_DENSITY_MUD
	return 0.0


static func _foliage_is_bench_surface(surface_id: StringName) -> bool:
	return surface_id == &"packed_dirt" or surface_id == &"loose_rock" or surface_id == &"packed_gravel"


static func _foliage_species_for_surface_value(surface_id_value: int) -> StringName:
	if not bool(TerrainSurfacePaletteResource.call("has_surface_id_value", surface_id_value)):
		return &""
	var surface_id: StringName = _surface_id_for_value(surface_id_value)
	if _foliage_is_bench_surface(surface_id):
		return FOLIAGE_SPECIES_SHRUB
	if surface_id == &"paved_road" or surface_id == &"wet_stone" or surface_id == &"mud":
		return FOLIAGE_SPECIES_GRASS
	if surface_id == &"tall_grass":
		return FOLIAGE_SPECIES_GRASS
	return &""


static func _bench_foliage_species_for_selector(selector: float) -> StringName:
	if selector <= FOLIAGE_BENCH_SHRUB_SHARE:
		return FOLIAGE_SPECIES_SHRUB
	if selector <= FOLIAGE_BENCH_SHRUB_SHARE + FOLIAGE_BENCH_GRASS_SHARE:
		return FOLIAGE_SPECIES_GRASS
	if selector <= FOLIAGE_BENCH_SHRUB_SHARE + FOLIAGE_BENCH_GRASS_SHARE + FOLIAGE_BENCH_JUNIPER_SHARE:
		return FOLIAGE_SPECIES_JUNIPER
	return FOLIAGE_SPECIES_YUCCA


static func _woodland_foliage_species_for_selector(selector: float) -> StringName:
	if selector <= FOLIAGE_WOODLAND_SHRUB_SHARE:
		return FOLIAGE_SPECIES_SHRUB
	if selector <= FOLIAGE_WOODLAND_SHRUB_SHARE + FOLIAGE_WOODLAND_GRASS_SHARE:
		return FOLIAGE_SPECIES_GRASS
	if selector <= FOLIAGE_WOODLAND_SHRUB_SHARE + FOLIAGE_WOODLAND_GRASS_SHARE + FOLIAGE_WOODLAND_JUNIPER_SHARE:
		return FOLIAGE_SPECIES_JUNIPER
	return FOLIAGE_SPECIES_YUCCA


static func _talus_foliage_species_for_selector(selector: float) -> StringName:
	if selector <= FOLIAGE_TALUS_SHRUB_SHARE:
		return FOLIAGE_SPECIES_SHRUB
	if selector <= FOLIAGE_TALUS_SHRUB_SHARE + FOLIAGE_TALUS_YUCCA_SHARE:
		return FOLIAGE_SPECIES_YUCCA
	return FOLIAGE_SPECIES_GRASS


static func _corridor_loose_rock_species_for_selector(selector: float) -> StringName:
	if selector <= GameConfig.scrub_loose_rock_corridor_grass_share:
		return FOLIAGE_SPECIES_GRASS
	if selector <= GameConfig.scrub_loose_rock_corridor_grass_share + GameConfig.scrub_loose_rock_corridor_shrub_share:
		return FOLIAGE_SPECIES_SHRUB
	return FOLIAGE_SPECIES_YUCCA


static func _bench_foliage_selector(foliage_cell: Vector2i, lod_index: int, attempt: int) -> float:
	var selector_a: float = _region_foliage_unit(foliage_cell, lod_index, attempt, FOLIAGE_BENCH_SELECTOR_SALT_A)
	var selector_b: float = _region_foliage_unit(foliage_cell, lod_index, attempt, FOLIAGE_BENCH_SELECTOR_SALT_B)
	return fmod(selector_a + selector_b, 1.0)


static func _surface_class_foliage_selector(foliage_cell: Vector2i, lod_index: int, attempt: int) -> float:
	return _region_foliage_mixed_unit(foliage_cell, lod_index, attempt, FOLIAGE_SURFACE_CLASS_SELECTOR_SALT)


static func _foliage_keep_value_for_species(species_id: StringName, foliage_cell: Vector2i, lod_index: int, attempt: int) -> float:
	if species_id == FOLIAGE_SPECIES_BOULDER:
		return _region_foliage_mixed_unit(foliage_cell, lod_index, attempt, FOLIAGE_BOULDER_KEEP_SALT)
	return _region_foliage_unit(foliage_cell, lod_index, attempt, 3)


static func _foliage_species_for_candidate(surface_id_value: int, foliage_cell: Vector2i, lod_index: int, attempt: int, world_x: float, world_z: float) -> StringName:
	if not bool(TerrainSurfacePaletteResource.call("has_surface_id_value", surface_id_value)):
		return &""
	var surface_id: StringName = _surface_id_for_value(surface_id_value)
	var riparian_species: StringName = _riparian_species_for_candidate(foliage_cell, lod_index, attempt, world_x, world_z)
	if riparian_species != &"":
		return riparian_species
	var boulder_selector: float = _region_foliage_unit(foliage_cell, lod_index, attempt, 12)
	if surface_id == &"packed_gravel":
		if boulder_selector <= GameConfig.boulder_packed_gravel_candidate_share:
			return FOLIAGE_SPECIES_BOULDER
		var bench_selector: float = _bench_foliage_selector(foliage_cell, lod_index, attempt)
		return _bench_foliage_species_for_selector(bench_selector)
	if surface_id == &"loose_rock":
		if boulder_selector <= GameConfig.boulder_loose_rock_candidate_share:
			return FOLIAGE_SPECIES_BOULDER
		if _foliage_is_corridor_scrub_position(world_x, world_z):
			return _corridor_loose_rock_species_for_selector(_surface_class_foliage_selector(foliage_cell, lod_index, attempt))
		return _talus_foliage_species_for_selector(_surface_class_foliage_selector(foliage_cell, lod_index, attempt))
	if surface_id == &"packed_dirt":
		return _woodland_foliage_species_for_selector(_surface_class_foliage_selector(foliage_cell, lod_index, attempt))
	return _foliage_species_for_surface_value(surface_id_value)


static func _foliage_species_allows_steep_slope(species_id: StringName) -> bool:
	return species_id == FOLIAGE_SPECIES_BOULDER


static func _foliage_species_uses_source_material(species_id: StringName) -> bool:
	return species_id == FOLIAGE_SPECIES_YUCCA or species_id == FOLIAGE_SPECIES_JUNIPER or species_id == FOLIAGE_SPECIES_WILLOW or species_id == FOLIAGE_SPECIES_COTTONWOOD


static func _riparian_species_for_candidate(foliage_cell: Vector2i, lod_index: int, attempt: int, world_x: float, world_z: float) -> StringName:
	var river_distance_m: float = _distance_to_zion_river_xz(Vector2(world_x, world_z))
	if river_distance_m > RIPARIAN_GRASS_OUTER_M:
		return &""
	var selector: float = _region_foliage_unit(foliage_cell, lod_index, attempt, 13)
	if river_distance_m <= RIPARIAN_TREE_MIN_DISTANCE_M:
		if selector <= 0.72:
			return FOLIAGE_SPECIES_RIPARIAN_GRASS
		return &""
	if river_distance_m <= RIPARIAN_WILLOW_OUTER_M:
		if selector <= 0.46:
			return FOLIAGE_SPECIES_WILLOW
		return FOLIAGE_SPECIES_RIPARIAN_GRASS
	if river_distance_m <= RIPARIAN_COTTONWOOD_OUTER_M:
		if selector <= 0.26:
			return FOLIAGE_SPECIES_COTTONWOOD
		if selector <= 0.58:
			return FOLIAGE_SPECIES_WILLOW
		return FOLIAGE_SPECIES_RIPARIAN_GRASS
	if selector <= 0.12:
		return FOLIAGE_SPECIES_COTTONWOOD
	if selector <= 0.62:
		return FOLIAGE_SPECIES_RIPARIAN_GRASS
	return &""


static func _foliage_is_corridor_scrub_position(world_x: float, world_z: float) -> bool:
	if world_x < 0.0 or world_z < 0.0:
		return false
	return _distance_to_zion_river_xz(Vector2(world_x, world_z)) <= GameConfig.scrub_loose_rock_corridor_river_distance_m


static func _riparian_gallery_density_multiplier(species_id: StringName, world_x: float, world_z: float) -> float:
	# Keep-probability multiplier for the Fremont cottonwood gallery band. Returns >1.0 inside the
	# dense core along the river (push the green where the water is), tapering linearly back to 1.0
	# by RIPARIAN_GRASS_OUTER_M so the fringe stays thin. Non-riparian species and any candidate
	# outside the riparian fringe return 1.0 -- desert/bench foliage is byte-identical to before.
	# Pure function of species + world position (deterministic, no Time/randi).
	if species_id != FOLIAGE_SPECIES_COTTONWOOD and species_id != FOLIAGE_SPECIES_WILLOW and species_id != FOLIAGE_SPECIES_RIPARIAN_GRASS:
		return 1.0
	var river_distance_m: float = _distance_to_zion_river_xz(Vector2(world_x, world_z))
	if river_distance_m >= RIPARIAN_GRASS_OUTER_M:
		return 1.0
	var core_boost: float = RIPARIAN_GRASS_CORE_DENSITY_MUL
	if species_id == FOLIAGE_SPECIES_COTTONWOOD:
		core_boost = RIPARIAN_COTTONWOOD_CORE_DENSITY_MUL
	elif species_id == FOLIAGE_SPECIES_WILLOW:
		core_boost = RIPARIAN_WILLOW_CORE_DENSITY_MUL
	if river_distance_m <= RIPARIAN_GALLERY_CORE_OUTER_M:
		return core_boost
	# Fringe: taper core_boost -> 1.0 across [core_outer, grass_outer] so the corridor edge
	# desaturates into sparse desert rather than carpeting the bench in green.
	var taper_t: float = clampf((river_distance_m - RIPARIAN_GALLERY_CORE_OUTER_M) / maxf(RIPARIAN_GRASS_OUTER_M - RIPARIAN_GALLERY_CORE_OUTER_M, 0.0001), 0.0, 1.0)
	return lerpf(core_boost, 1.0, taper_t)


static func _riparian_gallery_base_count(cell_rect: Rect2, lod_index: int, base_count: int) -> int:
	# Per-cell accepted-instance cap for the gallery core. A foliage cell whose center sits within
	# RIPARIAN_GALLERY_CORE_OUTER_M of the thalweg gets a raised cap so the cottonwood/willow canopy
	# + lush sedge understory can actually fill in along the river (the default cap is the gallery
	# bottleneck). Cells outside the core return base_count unchanged, so the ribbon stays dense at
	# the river and sparse everywhere else. Pure function of cell rect + LOD (deterministic).
	var cell_center: Vector2 = cell_rect.position + cell_rect.size * 0.5
	if _distance_to_zion_river_xz(cell_center) > RIPARIAN_GALLERY_CORE_OUTER_M:
		return base_count
	if lod_index <= 0:
		return RIPARIAN_GALLERY_LOD0_CORE_BASE_COUNT
	return RIPARIAN_GALLERY_LOD1_CORE_BASE_COUNT


static func _distance_to_zion_river_xz(point: Vector2) -> float:
	if ZION_RIVER_THALWEG_XZ.size() < 2:
		return INF
	var best_distance: float = INF
	for point_index in range(ZION_RIVER_THALWEG_XZ.size() - 1):
		var segment_distance: float = _distance_to_segment_xz(point, ZION_RIVER_THALWEG_XZ[point_index], ZION_RIVER_THALWEG_XZ[point_index + 1])
		best_distance = minf(best_distance, segment_distance)
	return best_distance


static func _distance_to_segment_xz(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var ab_len2: float = maxf(ab.length_squared(), 0.0001)
	var t: float = clampf((point - a).dot(ab) / ab_len2, 0.0, 1.0)
	return point.distance_to(a + ab * t)


static func _foliage_species_data(cell_data: FoliageCellData, species_id: StringName) -> FoliageSpeciesCellData:
	for species_data in cell_data.species:
		if species_data.species_id == species_id:
			return species_data
	var new_species_data: FoliageSpeciesCellData = FoliageSpeciesCellData.new()
	new_species_data.species_id = species_id
	cell_data.species.append(new_species_data)
	return new_species_data


static func _foliage_species_data_from_list(species_data_list: Array[FoliageSpeciesCellData], species_id: StringName) -> FoliageSpeciesCellData:
	for species_data in species_data_list:
		if species_data.species_id == species_id:
			return species_data
	var new_species_data: FoliageSpeciesCellData = FoliageSpeciesCellData.new()
	new_species_data.species_id = species_id
	species_data_list.append(new_species_data)
	return new_species_data


static func _foliage_species_total_count(species_data_list: Array[FoliageSpeciesCellData]) -> int:
	var total_count: int = 0
	for species_data in species_data_list:
		total_count += species_data.transforms.size()
	return total_count


static func _foliage_color_for_species(species_id: StringName) -> Color:
	if species_id == FOLIAGE_SPECIES_RIPARIAN_GRASS:
		return FOLIAGE_SPECIES_RIPARIAN_GRASS_COLOR
	if species_id == FOLIAGE_SPECIES_SHRUB:
		return FOLIAGE_SPECIES_SHRUB_COLOR
	if species_id == FOLIAGE_SPECIES_YUCCA:
		return FOLIAGE_SPECIES_YUCCA_COLOR
	if species_id == FOLIAGE_SPECIES_JUNIPER:
		return FOLIAGE_SPECIES_JUNIPER_COLOR
	if species_id == FOLIAGE_SPECIES_WILLOW:
		return FOLIAGE_SPECIES_WILLOW_COLOR
	if species_id == FOLIAGE_SPECIES_COTTONWOOD:
		return FOLIAGE_SPECIES_COTTONWOOD_COLOR
	if species_id == FOLIAGE_SPECIES_BOULDER:
		return FOLIAGE_SPECIES_BOULDER_COLOR
	return FOLIAGE_SPECIES_GRASS_COLOR


static func _foliage_dusk_tint_for_species(species_id: StringName) -> Color:
	if species_id == FOLIAGE_SPECIES_RIPARIAN_GRASS:
		return FOLIAGE_SPECIES_RIPARIAN_GRASS_DUSK_TINT
	if species_id == FOLIAGE_SPECIES_SHRUB:
		return FOLIAGE_SPECIES_SHRUB_DUSK_TINT
	if species_id == FOLIAGE_SPECIES_YUCCA:
		return FOLIAGE_SPECIES_YUCCA_DUSK_TINT
	if species_id == FOLIAGE_SPECIES_JUNIPER:
		return FOLIAGE_SPECIES_JUNIPER_DUSK_TINT
	if species_id == FOLIAGE_SPECIES_WILLOW:
		return FOLIAGE_SPECIES_WILLOW_DUSK_TINT
	if species_id == FOLIAGE_SPECIES_COTTONWOOD:
		return FOLIAGE_SPECIES_COTTONWOOD_DUSK_TINT
	if species_id == FOLIAGE_SPECIES_BOULDER:
		return FOLIAGE_SPECIES_BOULDER_COLOR
	return FOLIAGE_SPECIES_GRASS_DUSK_TINT


static func _foliage_material_color_for_species(species_id: StringName) -> Color:
	var base_color: Color = _foliage_color_for_species(species_id)
	if species_id == FOLIAGE_SPECIES_BOULDER:
		return base_color
	return base_color.lerp(_foliage_dusk_tint_for_species(species_id), FOLIAGE_SPECIES_MATERIAL_DUSK_STRENGTH)


static func _foliage_shrub_variant_color(selector: float) -> Color:
	if selector < 0.34:
		return FOLIAGE_SHRUB_RABBITBRUSH_COLOR
	if selector < 0.67:
		return FOLIAGE_SHRUB_SAGE_COLOR
	return FOLIAGE_SHRUB_MORMON_TEA_COLOR


static func _foliage_instance_color(species_id: StringName, color_warmth: float) -> Color:
	var base_color: Color = _foliage_color_for_species(species_id)
	if species_id == FOLIAGE_SPECIES_BOULDER:
		return base_color
	if species_id == FOLIAGE_SPECIES_SHRUB:
		base_color = _foliage_shrub_variant_color(color_warmth)
	var dusk_color: Color = _foliage_dusk_tint_for_species(species_id)
	var dusk_amount: float = clampf(FOLIAGE_SPECIES_MATERIAL_DUSK_STRENGTH + color_warmth * FOLIAGE_SPECIES_INSTANCE_DUSK_JITTER, 0.0, 1.0)
	return base_color.lerp(dusk_color, dusk_amount)


static func _grass_clump_offset_m(foliage_cell: Vector2i, lod_index: int, attempt: int, axis: int) -> float:
	var unit_value: float = _region_foliage_unit(foliage_cell, lod_index, attempt, GRASS_CLUMP_OFFSET_SALT_X + axis)
	return (unit_value * 2.0 - 1.0) * GRASS_CLUMP_RADIUS_M


static func _grass_clump_basis(base_scale: Vector3, width_scale_x: float, height_scale: float, foliage_cell: Vector2i, lod_index: int, attempt: int, yaw: float) -> Basis:
	# Non-uniform X/Z width so blades in a tussock do not share one outline, plus a small
	# deterministic lean (tilt about a horizontal axis) so clumps read as weighted scrub rather
	# than a regimented picket fence pivoting in lockstep.
	var width_scale_z: float = 0.82 + _region_foliage_unit(foliage_cell, lod_index, attempt, GRASS_WIDTH_Z_SALT) * 0.42
	var scaled: Basis = Basis(Vector3.UP, yaw).scaled(Vector3(base_scale.x * width_scale_x, base_scale.y * height_scale, base_scale.z * width_scale_z))
	var tilt_yaw: float = deg_to_rad(_region_foliage_unit(foliage_cell, lod_index, attempt, GRASS_TILT_AXIS_SALT) * 360.0)
	var tilt_angle: float = deg_to_rad((_region_foliage_unit(foliage_cell, lod_index, attempt, GRASS_TILT_AMOUNT_SALT) * 2.0 - 1.0) * GRASS_TILT_MAX_DEG)
	var tilt_axis: Vector3 = Vector3(cos(tilt_yaw), 0.0, sin(tilt_yaw))
	return scaled.rotated(tilt_axis, tilt_angle)


static func _grass_clump_instance_color(species_id: StringName, color_warmth: float, foliage_cell: Vector2i, lod_index: int, attempt: int) -> Color:
	# grass_billboard.gdshader multiplies ALBEDO by the MultiMesh instance COLOR, so per-instance
	# hue/value jitter reads directly as varied tussock color instead of a single repeating tint.
	# HSV is derived by hand: this Godot 4.6 build exposes no Color HSV getters, only from_hsv.
	var base: Color = _foliage_instance_color(species_id, color_warmth)
	var max_channel: float = maxf(maxf(base.r, base.g), base.b)
	var min_channel: float = minf(minf(base.r, base.g), base.b)
	var delta: float = max_channel - min_channel
	var hue: float = 0.0
	var saturation: float = 0.0
	if max_channel > 0.0:
		saturation = delta / max_channel
	if delta > 0.0:
		if max_channel == base.r:
			hue = fmod((base.g - base.b) / delta, 6.0)
		elif max_channel == base.g:
			hue = (base.b - base.r) / delta + 2.0
		else:
			hue = (base.r - base.g) / delta + 4.0
		hue = hue / 6.0
		if hue < 0.0:
			hue += 1.0
	var hue_shift: float = (_region_foliage_unit(foliage_cell, lod_index, attempt, GRASS_HUE_SALT) * 2.0 - 1.0) * GRASS_HUE_JITTER
	var value_shift: float = (_region_foliage_unit(foliage_cell, lod_index, attempt, GRASS_VALUE_SALT) * 2.0 - 1.0) * GRASS_VALUE_JITTER
	hue = fmod(hue + hue_shift + 1.0, 1.0)
	var value: float = clampf(max_channel + value_shift, GRASS_MIN_VALUE, 1.0)
	return Color.from_hsv(hue, saturation, value, base.a)


static func _foliage_base_scale_for_lod_species(lod_index: int, species_id: StringName) -> Vector3:
	if species_id == FOLIAGE_SPECIES_BOULDER:
		if lod_index > 0:
			return FOLIAGE_BOULDER_LOD1_SCALE
		return FOLIAGE_BOULDER_LOD0_SCALE
	if species_id == FOLIAGE_SPECIES_SHRUB:
		if lod_index > 0:
			return FOLIAGE_SHRUB_LOD1_SCALE
		return FOLIAGE_SHRUB_LOD0_SCALE
	if _foliage_species_uses_source_material(species_id):
		return FOLIAGE_TREE_REAL_MESH_SCALE
	if lod_index > 0:
		return GameConfig.foliage_grass_scrub_lod1_scale
	return GameConfig.foliage_grass_scrub_lod0_scale


static func _foliage_max_lod0_height() -> float:
	var max_height: float = 0.0
	for species_id in FOLIAGE_SPECIES_LIST:
		max_height = maxf(max_height, _foliage_lod0_height_for_species(species_id))
	return max_height * REGION_FOLIAGE_HEIGHT_SCALE_MAX


static func _foliage_max_lod0_horizontal_radius() -> float:
	var max_radius: float = 0.0
	for species_id in FOLIAGE_SPECIES_LIST:
		var mesh: Mesh = _region_foliage_mesh_for_lod_species(0, species_id)
		if mesh == null:
			continue
		var aabb: AABB = mesh.get_aabb()
		var scale: Vector3 = _foliage_base_scale_for_lod_species(0, species_id)
		var rx: float = maxf(absf(aabb.position.x), absf(aabb.position.x + aabb.size.x)) * scale.x
		var rz: float = maxf(absf(aabb.position.z), absf(aabb.position.z + aabb.size.z)) * scale.z
		max_radius = maxf(max_radius, maxf(rx, rz))
	return max_radius * REGION_FOLIAGE_TREE_WIDTH_SCALE_MAX


static func _foliage_lod0_height_for_species(species_id: StringName) -> float:
	var mesh: Mesh = _region_foliage_mesh_for_lod_species(0, species_id)
	var mesh_height: float = 1.0
	if mesh != null:
		mesh_height = maxf(mesh.get_aabb().size.y, 0.0)
	return mesh_height * _foliage_base_scale_for_lod_species(0, species_id).y


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


static func _region_foliage_mixed_unit(cell: Vector2i, lod_index: int, instance_index: int, salt: int) -> float:
	var value: int = (
		cell.x * REGION_FOLIAGE_MIXED_CELL_X_MULTIPLIER
		+ cell.y * REGION_FOLIAGE_MIXED_CELL_Z_MULTIPLIER
		+ instance_index * REGION_FOLIAGE_MIXED_INSTANCE_MULTIPLIER
		+ lod_index * REGION_FOLIAGE_MIXED_LOD_MULTIPLIER
		+ salt * REGION_FOLIAGE_MIXED_SALT_MULTIPLIER
	)
	value = ((value >> 16) ^ value) & REGION_FOLIAGE_MIXED_MASK
	return float(value % REGION_FOLIAGE_MIXED_MODULUS) / float(REGION_FOLIAGE_MIXED_MODULUS - 1)


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


static func clear_track_texture(parent: Node, track_texture: Texture2D) -> void:
	if track_texture == null:
		return
	var mesh_instance: MeshInstance3D = parent as MeshInstance3D
	if mesh_instance != null:
		_clear_track_texture_from_mesh(mesh_instance, track_texture)
	for child in parent.get_children():
		clear_track_texture(child, track_texture)


static func has_track_texture(parent: Node, track_texture: Texture2D) -> bool:
	if track_texture == null:
		return false
	var mesh_instance: MeshInstance3D = parent as MeshInstance3D
	if mesh_instance != null:
		var mesh: Mesh = mesh_instance.mesh
		if mesh != null:
			for surface_index in range(mesh.get_surface_count()):
				var material: Material = mesh_instance.get_surface_override_material(surface_index)
				if material == null:
					material = mesh.surface_get_material(surface_index)
				if material == null:
					continue
				if _material_has_track_texture(material, track_texture):
					return true
	for child in parent.get_children():
		if has_track_texture(child, track_texture):
			return true
	return false


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
	# Godot ignores POM/height mapping on triplanar materials ("Height mapping is
	# not supported on triplanar materials"). For those surfaces the authored
	# relief is baked into the normal map instead (see gen_zion_surface_textures
	# height_relief), so skip enabling the heightmap here to keep that warning out
	# of the log and avoid an inert texture binding.
	if bool(visual_def.get("triplanar")):
		return
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
		var material: Material = mesh_instance.get_surface_override_material(surface_index)
		if material == null:
			material = mesh.surface_get_material(surface_index)
		if material == null:
			continue
		if _material_has_track_texture(material, track_texture):
			_update_track_overlay_bounds(material, bounds_min, bounds_max)
			continue
		material = material.duplicate() as Material
		if material == null:
			continue
		material.next_pass = _track_overlay_material(material.resource_name, track_texture, bounds_min, bounds_max)
		mesh_instance.set_surface_override_material(surface_index, material)


static func _clear_track_texture_from_mesh(mesh_instance: MeshInstance3D, track_texture: Texture2D) -> void:
	var mesh: Mesh = mesh_instance.mesh
	if mesh == null:
		return
	for surface_index in range(mesh.get_surface_count()):
		var material: Material = mesh_instance.get_surface_override_material(surface_index)
		if material == null:
			material = mesh.surface_get_material(surface_index)
		if material == null:
			continue
		if not _material_has_track_texture(material, track_texture):
			continue
		material = material.duplicate() as Material
		if material == null:
			continue
		material.next_pass = null
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


static func _material_has_track_texture(material: Material, track_texture: Texture2D) -> bool:
	var overlay: ShaderMaterial = material.next_pass as ShaderMaterial
	if overlay == null:
		return false
	var overlay_texture: Texture2D = overlay.get_shader_parameter(TRACK_RT_UNIFORM) as Texture2D
	return overlay_texture == track_texture


static func _update_track_overlay_bounds(material: Material, bounds_min: Vector2, bounds_max: Vector2) -> void:
	var overlay: ShaderMaterial = material.next_pass as ShaderMaterial
	if overlay == null:
		return
	overlay.set_shader_parameter(TRACK_BOUNDS_MIN_UNIFORM, bounds_min)
	overlay.set_shader_parameter(TRACK_BOUNDS_MAX_UNIFORM, bounds_max)


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
