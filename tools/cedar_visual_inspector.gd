extends Node

const CedarHollowPlayableScene: PackedScene = preload("res://scenes/cedar_hollow_playable.tscn")
const CedarRoute: Resource = preload("res://data/routes/cedar_hollow.tres")
const CedarTerrainDef: Resource = preload("res://data/terrain/cedar_hollow_terrain_def.tres")
const CedarSurfaceVisualCatalog: Resource = preload("res://data/surface_visuals/cedar_hollow_surface_visuals.tres")
const VehicleStateScript: GDScript = preload("res://systems/vehicle/vehicle_state.gd")
const SurfaceMapScript: GDScript = preload("res://systems/world/surface_map.gd")
const TerrainVisualBuilderScript: GDScript = preload("res://systems/render/terrain_visual_builder.gd")
const FeatureVisualBuilderScript: GDScript = preload("res://systems/render/feature_visual_builder.gd")
const ScatterVisualBuilderScript: GDScript = preload("res://systems/render/scatter_visual_builder.gd")
const GroundDetailVisualBuilderScript: GDScript = preload("res://systems/render/ground_detail_visual_builder.gd")
const BoundaryVisualBuilderScript: GDScript = preload("res://systems/render/boundary_visual_builder.gd")
const DustTiltShiftVisualBuilderScript: GDScript = preload("res://systems/render/dust_tilt_shift_visual_builder.gd")
const SURFACE_DIR_PATH: String = "res://data/surfaces"
const EXPECTED_BOARDWALK_SEGMENTS: int = FeatureVisualBuilderScript.BOARDWALK_SEGMENT_COUNT
const EXPECTED_STEPPING_STONES: int = FeatureVisualBuilderScript.STEPPING_STONE_COUNT
const EXPECTED_CULVERT_PIPES: int = 1
const EXPECTED_LOG_RAMPS: int = 1
const EXPECTED_FEATURE_INSTANCED_CHILDREN: int = EXPECTED_BOARDWALK_SEGMENTS + EXPECTED_STEPPING_STONES + EXPECTED_CULVERT_PIPES + EXPECTED_LOG_RAMPS
const EXPECTED_GRASS_TUFTS: int = ScatterVisualBuilderScript.EXPECTED_GRASS_TUFTS
const EXPECTED_GRASS_OCCLUDERS: int = ScatterVisualBuilderScript.EXPECTED_GRASS_OCCLUDERS
const EXPECTED_BOULDERS: int = ScatterVisualBuilderScript.EXPECTED_BOULDERS
const EXPECTED_BRANCHES: int = ScatterVisualBuilderScript.EXPECTED_BRANCHES
const EXPECTED_PINECONES: int = ScatterVisualBuilderScript.EXPECTED_PINECONES
const EXPECTED_FERN_CLUMPS: int = ScatterVisualBuilderScript.EXPECTED_FERN_CLUMPS
const EXPECTED_CATTAILS: int = ScatterVisualBuilderScript.EXPECTED_CATTAILS
const EXPECTED_SCATTER_INSTANCED_CHILDREN: int = EXPECTED_GRASS_TUFTS + EXPECTED_GRASS_OCCLUDERS + EXPECTED_BOULDERS + EXPECTED_BRANCHES + EXPECTED_PINECONES + EXPECTED_FERN_CLUMPS + EXPECTED_CATTAILS
const EXPECTED_MUD_PATCHES: int = GroundDetailVisualBuilderScript.EXPECTED_MUD_PATCHES
const EXPECTED_TIRE_TRACK_PAIRS: int = GroundDetailVisualBuilderScript.EXPECTED_TIRE_TRACK_PAIRS
const EXPECTED_GRAVEL_SPECKLES: int = GroundDetailVisualBuilderScript.EXPECTED_GRAVEL_SPECKLES
const EXPECTED_LEAF_LITTER: int = GroundDetailVisualBuilderScript.EXPECTED_LEAF_LITTER
const EXPECTED_ROOT_RIDGES: int = GroundDetailVisualBuilderScript.EXPECTED_ROOT_RIDGES
const EXPECTED_PUDDLE_SHEENS: int = GroundDetailVisualBuilderScript.EXPECTED_PUDDLE_SHEENS
const EXPECTED_WET_GLINTS: int = GroundDetailVisualBuilderScript.EXPECTED_WET_GLINTS
const EXPECTED_BOUNDARY_GRASS: int = BoundaryVisualBuilderScript.EXPECTED_BOUNDARY_GRASS
const EXPECTED_BOUNDARY_BOULDERS: int = BoundaryVisualBuilderScript.EXPECTED_BOUNDARY_BOULDERS
const EXPECTED_BOUNDARY_BRANCHES: int = BoundaryVisualBuilderScript.EXPECTED_BOUNDARY_BRANCHES
const EXPECTED_TRAIL_BLAZES: int = BoundaryVisualBuilderScript.EXPECTED_TRAIL_BLAZES
const EXPECTED_BOUNDARY_INSTANCED_CHILDREN: int = EXPECTED_BOUNDARY_GRASS + EXPECTED_BOUNDARY_BOULDERS + EXPECTED_BOUNDARY_BRANCHES + EXPECTED_TRAIL_BLAZES
const EXPECTED_WAYFINDER_SIGNS: int = 3
const EXPECTED_SIGN_LABEL_BACKINGS: int = 11
const EXPECTED_SIGN_ARROW_LABELS: int = 5
const EXPECTED_SIGN_AXIS_ACCENTS: int = 6
const EXPECTED_PROP_MESH_NODES: Array[String] = [
	"trail_sign",
	"kiosk",
	"mile_marker",
	"park_bench",
	"carabiner",
	"bottle_cap",
	"wayfinder_culvert",
	"wayfinder_overlook",
	"wayfinder_creek",
	"picnic_table",
	"old_cedar_stump",
	"fire_ring",
	"hiking_boot",
	"water_bottle"
]
const FLOAT_EPSILON: float = 0.001
const LIGHTING_BAR_TOLERANCE: float = 0.01
const LIGHTING_BAR_COLOR_TOLERANCE: float = 0.02
const GROUND_DETAIL_MATERIAL_TOLERANCE: float = 0.05
const FOLIAGE_SHADER_TOLERANCE: float = 0.01
const MUD_PATCH_ALPHA_MIN: float = 0.45
const MUD_PATCH_ALPHA_MAX: float = 0.65
const MUD_PATCH_ROUGHNESS_MIN: float = 0.85
const MUD_PATCH_ROUGHNESS_MAX: float = 0.99
const PUDDLE_SHEEN_ROUGHNESS_MIN: float = 0.10
const PUDDLE_SHEEN_ROUGHNESS_MAX: float = 0.35
const WET_GLINT_RED_MIN: float = 0.5
const GRASS_BASE_RED_MAX: float = 0.15
const GRASS_BASE_GREEN_MIN: float = 0.12
const GRASS_BASE_BLUE_MAX: float = 0.10
const GRASS_TIP_RED_MIN: float = 0.35
const GRASS_TIP_GREEN_MIN: float = 0.50
const VISUAL_BAR_LIGHTING_SPEC_VERSION: int = 1
const DUSK_SUN_ENERGY_MIN: float = 2.0
const DUSK_SUN_ENERGY_MAX: float = 2.6
const GRADE_SATURATION_MIN: float = 1.20
const GRADE_SATURATION_MAX: float = 1.35
const GRADE_CONTRAST_MIN: float = 1.08
const GRADE_CONTRAST_MAX: float = 1.20
const DUSK_GLOW_INTENSITY: float = 0.18
const DUSK_GLOW_STRENGTH: float = 0.32
const DUSK_GLOW_BLOOM: float = 0.06
const DUSK_SUN_VOLUMETRIC_FOG_ENERGY: float = 0.82
const VOLUMETRIC_FOG_DENSITY_FLOOR: float = 0.006
const LABEL_MIN_CONTRAST_RATIO: float = 7.0
const ACCENT_MIN_CONTRAST_RATIO: float = 4.5
const CAMERA_COMPOSITION_TOLERANCE: float = 0.01
const CAMERA_LOOK_TOLERANCE: float = 0.01
const CAMERA_PITCH_TOLERANCE_DEG: float = 0.25
const CAMERA_REACTIVE_PITCH_TOLERANCE_DEG: float = 0.5
const TILT_SHIFT_SHADER_PATH: String = "res://systems/render/tilt_shift.gdshader"
const TILT_SHIFT_LAYER_NAME: String = "TiltShiftLayer"
const TILT_SHIFT_RECT_NAME: String = "TiltShiftOverlay"
const TILT_SHIFT_LAYER_INDEX: int = 2
const EXPECTED_FOV_MIN: float = 68.0
const EXPECTED_FOV_MAX: float = 80.0
const FEATURE_TRANSFORM_TOLERANCE: float = 0.01
const SCATTER_X_MIN: float = -2.8
const SCATTER_X_MAX: float = 5.05
const SCATTER_Z_MIN: float = -9.55
const SCATTER_Z_MAX: float = -0.3
const GROUND_DETAIL_X_MIN: float = -1.2
const GROUND_DETAIL_X_MAX: float = 5.05
const GROUND_DETAIL_Z_MIN: float = -7.8
const GROUND_DETAIL_Z_MAX: float = 1.4
const GROUND_DETAIL_MAX_HEIGHT: float = 0.08
const GRASS_OCCLUDER_X_MIN: float = -2.8
const GRASS_OCCLUDER_X_MAX: float = 4.7
const GRASS_OCCLUDER_Z_MIN: float = -7.4
const GRASS_OCCLUDER_Z_MAX: float = -0.9
const GRASS_OCCLUDER_MIN_HEIGHT: float = 0.58
const CROSSING_CHASE_QA_POSITION: Vector3 = Vector3(4.25, 0.0, -6.55)
const CROSSING_CHASE_QA_YAW_DEGREES: float = -70.0
const CHASE_CLEAR_CORRIDOR_LENGTH: float = 0.7
const CHASE_CLEAR_CORRIDOR_HALF_WIDTH: float = 0.18
const CAMERA_PROP_CLEARANCE_MARGIN: float = 0.025
const READABILITY_CENTER_CLEAR_RECT: Rect2 = Rect2(0.34, 0.18, 0.32, 0.62)
const READABILITY_MAX_DECOR_SCREEN_AREA: float = 0.34
const READABILITY_MAX_FOCAL_SCREEN_AREA: float = 0.42
const READABILITY_MAX_DECOR_CENTER_OVERLAP: float = 0.055
const BOUNDARY_EDGE_X: float = 4.5
const BOUNDARY_BACK_Z: float = -9.8
const HEIGHTMESH_ROUTE_MARGIN: float = 0.35
const EXPECTED_BOUNDARY_LEFT_VISUALS: int = 15
const EXPECTED_BOUNDARY_RIGHT_VISUALS: int = 16
const EXPECTED_BOUNDARY_BACK_VISUALS: int = 7
const EXPECTED_TERRAIN_ACTIVE_TILE_COUNT: int = 12
const EXPECTED_TERRAIN_TILE_GRID: Vector2i = Vector2i(1, 12)
const EXPECTED_TERRAIN_TILE_GRID_ORIGIN: Vector2i = Vector2i(0, -5)
const TERRAIN_TILE_BOUNDS_TOLERANCE: float = 0.01
const TERRAIN_HEIGHTMAP_COLLISION_NODE: String = "cedar_hollow_heightmap_collision"
const RESIDUE_SHADER_PATH: String = "res://systems/render/vehicle_contamination_visual.gdshader"
const RESIDUE_BODY_OVERLAY: String = "body/residue_body_contamination_overlay"
const RESIDUE_NOSE_OVERLAY: String = "nose/residue_body_contamination_overlay"
const RESIDUE_TIRE_OVERLAY: String = "residue_tire_contamination_overlay"
const RESIDUE_MUD_BODY_MASK: String = "res://assets/textures/vehicle/residue/mud_body_mask.png"
const RESIDUE_DUST_BODY_MASK: String = "res://assets/textures/vehicle/residue/dust_body_mask.png"
const RESIDUE_WETNESS_BODY_MASK: String = "res://assets/textures/vehicle/residue/wetness_body_mask.png"
const RESIDUE_MUD_TIRE_MASK: String = "res://assets/textures/vehicle/residue/mud_tire_mask.png"
const RESIDUE_DUST_TIRE_MASK: String = "res://assets/textures/vehicle/residue/dust_tire_mask.png"
const RESIDUE_WETNESS_TIRE_MASK: String = "res://assets/textures/vehicle/residue/wetness_tire_mask.png"
const TERRAIN_MATERIAL_PREFIX: String = "terrain_mat_"
const TERRAIN_DETAIL_MASK_TEXTURE: String = "res://assets/textures/surface_visuals/generated/terrain_detail_mask.png"
const TEXTURE_SOURCE_PATH_META: StringName = &"trailhead_source_path"
const VEHICLE_BODY_BASE_POSITION: Vector3 = Vector3(0.0, 0.010, 0.015)
const VEHICLE_NOSE_BASE_POSITION: Vector3 = Vector3(0.0, 0.018, -0.155)
const VEHICLE_FRONT_LEFT_WHEEL_SOCKET_POSITION: Vector3 = Vector3(-0.08, -0.015, -0.10)
const WET_DIFFUSE_MULTIPLIER: float = 0.2
const WET_ROUGHNESS: float = 0.12
const WET_CLEARCOAT: float = 0.58
const WET_CLEARCOAT_ROUGHNESS: float = 0.08
const WHEEL_SOCKET_NAMES: Array[String] = [
	"wheel_front_left",
	"wheel_front_right",
	"wheel_rear_left",
	"wheel_rear_right"
]

class BoundsAccumulator:
	var has_bounds: bool = false
	var bounds_min: Vector3 = Vector3.ZERO
	var bounds_max: Vector3 = Vector3.ZERO

var _scene_root: Node = null
var _errors: PackedStringArray = PackedStringArray()


func _ready() -> void:
	_scene_root = CedarHollowPlayableScene.instantiate()
	add_child(_scene_root)
	call_deferred("_inspect")


func _inspect() -> void:
	if _scene_root == null:
		_errors.append("failed to instantiate Cedar Hollow playable scene")
		_finish()
		return
	var cedar_world: Node = _require_node(_scene_root, "CedarHollow")
	if cedar_world != null:
		_inspect_terrain_heightmap_collision(cedar_world)
	var terrain_root: Node = _require_node(_scene_root, "CedarHollow/TerrainVisuals")
	if terrain_root != null:
		_require_named_count(terrain_root, "terrain_patch_", 0)
		_inspect_terrain_visual_tiles(terrain_root)
		_inspect_terrain_visual_layout(terrain_root)
		var terrain_collision_count: int = _count_collision_objects(terrain_root)
		if terrain_collision_count > 0:
			_errors.append("TerrainVisuals contains collision objects: " + str(terrain_collision_count))
		var terrain_mesh_count: int = _count_mesh_instances(terrain_root)
		if terrain_mesh_count <= 0:
			_errors.append("TerrainVisuals contains no mesh instances")
	var feature_root: Node = _require_node(_scene_root, "CedarHollow/FeatureVisuals")
	if feature_root != null:
		_require_direct_child_count(feature_root, "FeatureVisuals", EXPECTED_FEATURE_INSTANCED_CHILDREN)
		_require_named_count(feature_root, "boardwalk_segment_", EXPECTED_BOARDWALK_SEGMENTS)
		_require_named_count(feature_root, "stepping_stone_", EXPECTED_STEPPING_STONES)
		_require_named_count(feature_root, "culvert_pipe", EXPECTED_CULVERT_PIPES)
		_require_named_count(feature_root, "log_ramp", EXPECTED_LOG_RAMPS)
		_require_node_position(feature_root, "boardwalk_segment_1", Vector3(3.25, 0.035, -4.31), FEATURE_TRANSFORM_TOLERANCE)
		_require_node_position(feature_root, "boardwalk_segment_9", Vector3(3.25, 0.035, -2.39), FEATURE_TRANSFORM_TOLERANCE)
		_require_node_scale(feature_root, "boardwalk_segment_1", Vector3(1.35, 1.0, 1.0), FLOAT_EPSILON)
		_require_node_position(feature_root, "culvert_pipe", Vector3(-4.35, -0.02, -3.05), FEATURE_TRANSFORM_TOLERANCE)
		_require_node_position(feature_root, "log_ramp", Vector3(1.3, -0.005, 0.16), FEATURE_TRANSFORM_TOLERANCE)
		_require_node_rotation(feature_root, "log_ramp", Vector3(0.0, 115.0, 0.0), FLOAT_EPSILON)
		_require_node_position(feature_root, "stepping_stone_1", Vector3(3.45, 0.01, -7.05), FEATURE_TRANSFORM_TOLERANCE)
		_require_node_position(feature_root, "stepping_stone_5", Vector3(5.0, 0.01, -7.2), FEATURE_TRANSFORM_TOLERANCE)
		_inspect_feature_sequences(feature_root)
		_require_geometry_visibility_range(feature_root, "FeatureVisuals", GameConfig.vis_range_props)
		var collision_count: int = _count_collision_objects(feature_root)
		if collision_count > 0:
			_errors.append("FeatureVisuals contains collision objects: " + str(collision_count))
		var mesh_count: int = _count_mesh_instances(feature_root)
		if mesh_count <= 0:
			_errors.append("FeatureVisuals contains no mesh instances")
	var prop_root: Node = _require_node(_scene_root, "CedarHollow/PropVisuals")
	if prop_root != null:
		_require_named_count(prop_root, "trail_sign", 1)
		_require_named_count(prop_root, "kiosk", 1)
		_require_named_count(prop_root, "mile_marker", 1)
		_require_named_count(prop_root, "park_bench", 1)
		_require_named_count(prop_root, "carabiner", 1)
		_require_named_count(prop_root, "bottle_cap", 1)
		_require_named_count(prop_root, "wayfinder_", EXPECTED_WAYFINDER_SIGNS)
		_require_named_count(prop_root, "picnic_table", 1)
		_require_named_count(prop_root, "old_cedar_stump", 1)
		_require_named_count(prop_root, "fire_ring", 1)
		_require_named_count(prop_root, "hiking_boot", 1)
		_require_named_count(prop_root, "water_bottle", 1)
		_require_node_position(prop_root, "trail_sign", Vector3(0.72, 0.0, 0.25), FEATURE_TRANSFORM_TOLERANCE)
		_require_node_rotation(prop_root, "trail_sign", Vector3(0.0, -16.0, 0.0), FLOAT_EPSILON)
		_require_node_position(prop_root, "kiosk", Vector3(-1.18, 0.0, 1.18), FEATURE_TRANSFORM_TOLERANCE)
		_require_node_rotation(prop_root, "kiosk", Vector3(0.0, 20.0, 0.0), FLOAT_EPSILON)
		_require_node_position(prop_root, "mile_marker", Vector3(1.12, 0.0, -2.35), FEATURE_TRANSFORM_TOLERANCE)
		_require_node_rotation(prop_root, "mile_marker", Vector3(0.0, -8.0, 0.0), FLOAT_EPSILON)
		_require_node_position(prop_root, "park_bench", Vector3(-2.0, 0.0, 0.9), FEATURE_TRANSFORM_TOLERANCE)
		_require_node_rotation(prop_root, "park_bench", Vector3(0.0, 24.0, 0.0), FLOAT_EPSILON)
		_require_node_position(prop_root, "carabiner", Vector3(1.25, 0.02, -1.15), FEATURE_TRANSFORM_TOLERANCE)
		_require_node_rotation(prop_root, "carabiner", Vector3(0.0, -18.0, 0.0), FLOAT_EPSILON)
		_require_node_position(prop_root, "bottle_cap", Vector3(-0.95, 0.0, -3.25), FEATURE_TRANSFORM_TOLERANCE)
		_require_node_rotation(prop_root, "bottle_cap", Vector3(0.0, 12.0, 0.0), FLOAT_EPSILON)
		_require_node_position(prop_root, "wayfinder_culvert", Vector3(-2.15, 0.0, -1.82), FEATURE_TRANSFORM_TOLERANCE)
		_require_node_rotation(prop_root, "wayfinder_culvert", Vector3(0.0, 68.0, 0.0), FLOAT_EPSILON)
		_require_node_position(prop_root, "wayfinder_overlook", Vector3(-0.55, 0.0, -5.78), FEATURE_TRANSFORM_TOLERANCE)
		_require_node_rotation(prop_root, "wayfinder_overlook", Vector3(0.0, -44.0, 0.0), FLOAT_EPSILON)
		_require_node_position(prop_root, "wayfinder_creek", Vector3(1.95, 0.0, -4.72), FEATURE_TRANSFORM_TOLERANCE)
		_require_node_rotation(prop_root, "wayfinder_creek", Vector3(0.0, 28.0, 0.0), FLOAT_EPSILON)
		_require_node_position(prop_root, "picnic_table", Vector3(-1.45, 0.0, 0.35), FEATURE_TRANSFORM_TOLERANCE)
		_require_node_rotation(prop_root, "picnic_table", Vector3(0.0, 18.0, 0.0), FLOAT_EPSILON)
		_require_node_position(prop_root, "old_cedar_stump", Vector3(0.65, 0.0, -5.25), FEATURE_TRANSFORM_TOLERANCE)
		_require_node_rotation(prop_root, "old_cedar_stump", Vector3(0.0, 12.0, 0.0), FLOAT_EPSILON)
		_require_node_scale(prop_root, "old_cedar_stump", Vector3(0.78, 0.78, 0.78), FLOAT_EPSILON)
		_require_node_position(prop_root, "fire_ring", Vector3(-0.78, 0.0, 1.05), FEATURE_TRANSFORM_TOLERANCE)
		_require_node_position(prop_root, "hiking_boot", Vector3(0.75, 0.01, -4.65), FEATURE_TRANSFORM_TOLERANCE)
		_require_node_rotation(prop_root, "hiking_boot", Vector3(0.0, -32.0, 0.0), FLOAT_EPSILON)
		_require_node_position(prop_root, "water_bottle", Vector3(2.45, 0.0, -4.15), FEATURE_TRANSFORM_TOLERANCE)
		_require_node_rotation(prop_root, "water_bottle", Vector3(0.0, 17.0, 78.0), FLOAT_EPSILON)
		_require_descendant_named_count(prop_root, "label_backing_", EXPECTED_SIGN_LABEL_BACKINGS)
		_require_descendant_named_count(prop_root, "arrow_", EXPECTED_SIGN_ARROW_LABELS)
		_require_descendant_named_count(prop_root, "axis_accent", EXPECTED_SIGN_AXIS_ACCENTS)
		_require_label(prop_root, "trail_sign/label_old_cedar", "Old Cedar", 30)
		_require_label(prop_root, "trail_sign/label_creek", "Creek", 24)
		_require_label(prop_root, "kiosk/label_title", "Cedar Hollow", 24)
		_require_label(prop_root, "kiosk/label_loop", "Loop Trail", 20)
		_require_label(prop_root, "mile_marker/label_distance", "0.4", 20)
		_require_label(prop_root, "wayfinder_culvert/label_primary", "Culvert", 24)
		_require_label(prop_root, "wayfinder_culvert/label_secondary", "Spur", 20)
		_require_label(prop_root, "wayfinder_overlook/label_primary", "Overlook", 24)
		_require_label(prop_root, "wayfinder_overlook/label_secondary", "Ridge", 20)
		_require_label(prop_root, "wayfinder_creek/label_primary", "Bog", 24)
		_require_label(prop_root, "wayfinder_creek/label_secondary", "Crossing", 20)
		_require_arrow_label(prop_root, "trail_sign/arrow_old_cedar", ">", 24)
		_require_arrow_label(prop_root, "trail_sign/arrow_creek", ">", 21)
		_require_arrow_label(prop_root, "wayfinder_culvert/arrow_primary", "<", 24)
		_require_arrow_label(prop_root, "wayfinder_overlook/arrow_primary", "^", 24)
		_require_arrow_label(prop_root, "wayfinder_creek/arrow_primary", ">", 24)
		_require_accent_mesh(prop_root, "trail_sign/axis_accent")
		_require_accent_mesh(prop_root, "kiosk/axis_accent")
		_require_accent_mesh(prop_root, "mile_marker/axis_accent")
		_require_accent_mesh(prop_root, "wayfinder_culvert/axis_accent")
		_require_accent_mesh(prop_root, "wayfinder_overlook/axis_accent")
		_require_accent_mesh(prop_root, "wayfinder_creek/axis_accent")
		_require_prop_meshes(prop_root)
		_require_geometry_visibility_range(prop_root, "PropVisuals", GameConfig.vis_range_props)
		var prop_collision_count: int = _count_collision_objects(prop_root)
		if prop_collision_count > 0:
			_errors.append("PropVisuals contains collision objects: " + str(prop_collision_count))
		var prop_mesh_count: int = _count_mesh_instances(prop_root)
		if prop_mesh_count <= 0:
			_errors.append("PropVisuals contains no mesh instances")
	var scatter_root: Node = _require_node(_scene_root, "CedarHollow/ScatterVisuals")
	if scatter_root != null:
		_require_direct_child_count(scatter_root, "ScatterVisuals", EXPECTED_SCATTER_INSTANCED_CHILDREN)
		_require_named_count(scatter_root, "grass_tuft_", EXPECTED_GRASS_TUFTS)
		_require_named_count(scatter_root, "grass_occluder_", EXPECTED_GRASS_OCCLUDERS)
		_require_named_count(scatter_root, "boulder_", EXPECTED_BOULDERS)
		_require_named_count(scatter_root, "branch_", EXPECTED_BRANCHES)
		_require_named_count(scatter_root, "pinecone_", EXPECTED_PINECONES)
		_require_named_count(scatter_root, "fern_clump_", EXPECTED_FERN_CLUMPS)
		_require_named_count(scatter_root, "cattail_", EXPECTED_CATTAILS)
		_inspect_foliage_bar(scatter_root, "Cedar")
		_inspect_scatter_layout(scatter_root)
		_inspect_scatter_visibility_ranges(scatter_root)
		_inspect_chase_capture_clearance(scatter_root)
		var scatter_collision_count: int = _count_collision_objects(scatter_root)
		if scatter_collision_count > 0:
			_errors.append("ScatterVisuals contains collision objects: " + str(scatter_collision_count))
		var scatter_mesh_count: int = _count_mesh_instances(scatter_root)
		if scatter_mesh_count <= 0:
			_errors.append("ScatterVisuals contains no mesh instances")
	var ground_detail_root: Node = _require_node(_scene_root, "CedarHollow/GroundDetailVisuals")
	if ground_detail_root != null:
		var ground_detail_chase_camera: Camera3D = _scene_root.get_node_or_null("ChaseCamera") as Camera3D
		_inspect_ground_detail_bar(ground_detail_root, ground_detail_chase_camera, "Cedar")
		_inspect_ground_detail_layout(ground_detail_root)
		var ground_detail_collision_count: int = _count_collision_objects(ground_detail_root)
		if ground_detail_collision_count > 0:
			_errors.append("GroundDetailVisuals contains collision objects: " + str(ground_detail_collision_count))
		var ground_detail_mesh_count: int = _count_mesh_instances(ground_detail_root)
		var expected_ground_detail_mesh_count: int = EXPECTED_MUD_PATCHES + EXPECTED_TIRE_TRACK_PAIRS * 2 + EXPECTED_GRAVEL_SPECKLES + EXPECTED_LEAF_LITTER + EXPECTED_ROOT_RIDGES + EXPECTED_PUDDLE_SHEENS + EXPECTED_WET_GLINTS
		if ground_detail_mesh_count < expected_ground_detail_mesh_count:
			_errors.append("GroundDetailVisuals mesh count expected at least " + str(expected_ground_detail_mesh_count) + ", got " + str(ground_detail_mesh_count))
	var boundary_root: Node = _require_node(_scene_root, "CedarHollow/BoundaryVisuals")
	if boundary_root != null:
		_require_direct_child_count(boundary_root, "BoundaryVisuals", EXPECTED_BOUNDARY_INSTANCED_CHILDREN)
		_require_named_count(boundary_root, "boundary_grass_", EXPECTED_BOUNDARY_GRASS)
		_require_named_count(boundary_root, "boundary_boulder_", EXPECTED_BOUNDARY_BOULDERS)
		_require_named_count(boundary_root, "boundary_branch_", EXPECTED_BOUNDARY_BRANCHES)
		_require_named_count(boundary_root, "trail_blaze_", EXPECTED_TRAIL_BLAZES)
		_inspect_boundary_layout(boundary_root)
		_require_geometry_visibility_range(boundary_root, "BoundaryVisuals", GameConfig.vis_range_scatter)
		var boundary_collision_count: int = _count_collision_objects(boundary_root)
		if boundary_collision_count > 0:
			_errors.append("BoundaryVisuals contains collision objects: " + str(boundary_collision_count))
		var boundary_mesh_count: int = _count_mesh_instances(boundary_root)
		if boundary_mesh_count <= 0:
			_errors.append("BoundaryVisuals contains no mesh instances")
	_require_node(_scene_root, "CedarHollow")
	var vehicle: Node = _require_node(_scene_root, "Vehicle")
	_inspect_vehicle_visuals(_scene_root, vehicle)
	var chase_camera: Camera3D = _require_node(_scene_root, "ChaseCamera") as Camera3D
	var orbit_camera: Camera3D = _require_node(_scene_root, "OrbitCamera") as Camera3D
	var fpv_camera: Camera3D = _require_node(_scene_root, "FpvCamera") as Camera3D
	_inspect_camera_defaults(vehicle, chase_camera, orbit_camera, fpv_camera)
	_inspect_render_camera_contract(_scene_root, chase_camera, orbit_camera, fpv_camera, "Cedar")
	var prop_visual_root: Node = _scene_root.get_node_or_null("CedarHollow/PropVisuals")
	if prop_visual_root != null:
		_inspect_chase_camera_prop_clearance(prop_visual_root, chase_camera)
	var scatter_visual_root: Node = _scene_root.get_node_or_null("CedarHollow/ScatterVisuals")
	if prop_visual_root != null and scatter_visual_root != null and chase_camera != null:
		_inspect_camera_space_readability(chase_camera, prop_visual_root, scatter_visual_root)
	_inspect_camera_reactivity(_scene_root, vehicle, chase_camera, orbit_camera, fpv_camera)
	_require_node(_scene_root, "SurfaceMap")
	var world_environment: WorldEnvironment = _require_node(_scene_root, "GoldenHourEnvironment") as WorldEnvironment
	if world_environment != null:
		_inspect_default_environment(world_environment)
	var sun: DirectionalLight3D = _require_node(_scene_root, "GoldenHourSun") as DirectionalLight3D
	if sun != null:
		_inspect_default_sun(sun)
	var audio_rig: Node = _require_node(_scene_root, "CedarAudioRig")
	if audio_rig != null:
		_inspect_audio_rig(audio_rig)
	var hud: Node = _require_node(_scene_root, "LandmarkHintHud")
	if hud != null:
		_inspect_hud_defaults(hud)
	_inspect_render_toggles(_scene_root, chase_camera, orbit_camera, fpv_camera, world_environment, sun, hud)
	_inspect_input_map()
	_inspect_reverse_input_output(_scene_root, "Cedar host")
	_finish()


func _require_node(parent: Node, path: String) -> Node:
	var node: Node = parent.get_node_or_null(path)
	if node == null:
		_errors.append("missing node: " + path)
	return node


func _require_named_count(parent: Node, prefix: String, expected: int) -> void:
	var count: int = 0
	for child in parent.get_children():
		var child_name: String = child.name
		if child_name.begins_with(prefix):
			count += 1
	if count != expected:
		_errors.append("expected " + str(expected) + " nodes named " + prefix + "*, got " + str(count))


func _require_direct_child_count(parent: Node, label: String, expected: int) -> void:
	var count: int = parent.get_child_count()
	if count != expected:
		_errors.append(label + " expected " + str(expected) + " direct instanced children, got " + str(count))


func _require_descendant_named_count(parent: Node, prefix: String, expected: int) -> void:
	var count: int = _count_descendants_named(parent, prefix)
	if count != expected:
		_errors.append("expected " + str(expected) + " descendant nodes named " + prefix + "*, got " + str(count))


func _count_descendants_named(parent: Node, prefix: String) -> int:
	var count: int = 0
	for child in parent.get_children():
		var child_name: String = child.name
		if child_name.begins_with(prefix):
			count += 1
		count += _count_descendants_named(child, prefix)
	return count


func _require_node_position(parent: Node, path: String, expected: Vector3, tolerance: float) -> void:
	var node: Node3D = _require_node(parent, path) as Node3D
	if node == null:
		return
	if node.position.distance_to(expected) > tolerance:
		_errors.append(path + " position expected " + str(expected) + ", got " + str(node.position))


func _require_node_rotation(parent: Node, path: String, expected: Vector3, tolerance: float) -> void:
	var node: Node3D = _require_node(parent, path) as Node3D
	if node == null:
		return
	if node.rotation_degrees.distance_to(expected) > tolerance:
		_errors.append(path + " rotation expected " + str(expected) + ", got " + str(node.rotation_degrees))


func _require_node_scale(parent: Node, path: String, expected: Vector3, tolerance: float) -> void:
	var node: Node3D = _require_node(parent, path) as Node3D
	if node == null:
		return
	if node.scale.distance_to(expected) > tolerance:
		_errors.append(path + " scale expected " + str(expected) + ", got " + str(node.scale))


func _require_label(parent: Node, path: String, expected_text: String, expected_font_size: int) -> void:
	var label: Label3D = _require_node(parent, path) as Label3D
	if label == null:
		return
	if label.text != expected_text:
		_errors.append(path + " text expected " + expected_text + ", got " + label.text)
	if label.font_size != expected_font_size:
		_errors.append(path + " font_size expected " + str(expected_font_size) + ", got " + str(label.font_size))
	if label.outline_size < 6:
		_errors.append(path + " outline_size should support high-contrast readability")
	var label_material: StandardMaterial3D = label.material_override as StandardMaterial3D
	if label_material == null:
		_errors.append(path + " should use a StandardMaterial3D text material")
	else:
		_require_unshaded_material(label_material, path + " material")
	var parent_node: Node = label.get_parent()
	if parent_node == null:
		_errors.append(path + " should have a parent for backing")
		return
	var backing_name: String = String(label.name).replace("label_", "label_backing_")
	var backing: MeshInstance3D = parent_node.get_node_or_null(backing_name) as MeshInstance3D
	if backing == null:
		_errors.append(path + " missing high-contrast backing " + backing_name)
		return
	var backing_material: StandardMaterial3D = _require_mesh_standard_material(backing, path + " backing")
	if backing_material == null:
		return
	_require_unshaded_material(backing_material, path + " backing")
	if _contrast_ratio(label.modulate, backing_material.albedo_color) < LABEL_MIN_CONTRAST_RATIO:
		_errors.append(path + " label/backing contrast should be at least " + str(LABEL_MIN_CONTRAST_RATIO))
	if _contrast_ratio(label.modulate, label.outline_modulate) < LABEL_MIN_CONTRAST_RATIO:
		_errors.append(path + " label/outline contrast should be at least " + str(LABEL_MIN_CONTRAST_RATIO))


func _require_arrow_label(parent: Node, path: String, expected_text: String, expected_font_size: int) -> void:
	var arrow: Label3D = _require_node(parent, path) as Label3D
	if arrow == null:
		return
	if arrow.text != expected_text:
		_errors.append(path + " arrow expected " + expected_text + ", got " + arrow.text)
	if arrow.font_size != expected_font_size:
		_errors.append(path + " font_size expected " + str(expected_font_size) + ", got " + str(arrow.font_size))
	if arrow.outline_size < 7:
		_errors.append(path + " outline_size should support high-contrast arrow readability")
	var material: StandardMaterial3D = arrow.material_override as StandardMaterial3D
	if material == null:
		_errors.append(path + " should use a StandardMaterial3D arrow material")
	else:
		_require_unshaded_material(material, path + " material")
	if _contrast_ratio(arrow.modulate, arrow.outline_modulate) < ACCENT_MIN_CONTRAST_RATIO:
		_errors.append(path + " arrow/outline contrast should be at least " + str(ACCENT_MIN_CONTRAST_RATIO))


func _require_accent_mesh(parent: Node, path: String) -> void:
	var accent: MeshInstance3D = _require_node(parent, path) as MeshInstance3D
	if accent == null:
		return
	var material: StandardMaterial3D = _require_mesh_standard_material(accent, path)
	if material == null:
		return
	_require_unshaded_material(material, path + " material")
	if _contrast_ratio(material.albedo_color, Color(0.045, 0.035, 0.022)) < ACCENT_MIN_CONTRAST_RATIO:
		_errors.append(path + " accent should contrast with dark sign backing")


func _require_mesh_standard_material(mesh_instance: MeshInstance3D, label: String) -> StandardMaterial3D:
	var material: StandardMaterial3D = mesh_instance.material_override as StandardMaterial3D
	if material == null:
		_errors.append(label + " should use StandardMaterial3D")
		return null
	if mesh_instance.mesh == null:
		_errors.append(label + " should include a mesh")
	return material


func _require_unshaded_material(material: StandardMaterial3D, label: String) -> void:
	if material.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED:
		_errors.append(label + " should be unshaded for stable sign readability")
	if material.cull_mode != BaseMaterial3D.CULL_DISABLED:
		_errors.append(label + " should render double-sided")
	if absf(material.metallic) > FLOAT_EPSILON:
		_errors.append(label + " should be nonmetallic")


func _contrast_ratio(a: Color, b: Color) -> float:
	var luminance_a: float = _relative_luminance(a)
	var luminance_b: float = _relative_luminance(b)
	var lighter: float = maxf(luminance_a, luminance_b)
	var darker: float = minf(luminance_a, luminance_b)
	return (lighter + 0.05) / (darker + 0.05)


func _relative_luminance(color: Color) -> float:
	return 0.2126 * _linear_color_channel(color.r) + 0.7152 * _linear_color_channel(color.g) + 0.0722 * _linear_color_channel(color.b)


func _linear_color_channel(value: float) -> float:
	if value <= 0.03928:
		return value / 12.92
	return float(pow((value + 0.055) / 1.055, 2.4))


func _require_prop_meshes(prop_root: Node) -> void:
	for prop_path in EXPECTED_PROP_MESH_NODES:
		var prop: Node = _require_node(prop_root, prop_path)
		if prop == null:
			continue
		if not _has_mesh_instance(prop):
			_errors.append("PropVisuals/" + prop_path + " contains no mesh instances")


func _has_mesh_instance(parent: Node) -> bool:
	if parent is MeshInstance3D:
		return true
	for child in parent.get_children():
		if _has_mesh_instance(child):
			return true
	return false


func _inspect_terrain_visual_tiles(terrain_root: Node) -> void:
	var active_tiles: Array[Vector2i] = CedarTerrainDef.call("active_tile_indices")
	var visual_tile_paths: Array[String] = CedarTerrainDef.get("visual_tile_paths")
	_inspect_terrain_def_visual_tile_contract(active_tiles)
	_inspect_landmark_tile_coverage(active_tiles)
	if active_tiles.is_empty():
		_errors.append("TerrainDef should expose at least one active visual tile")
	if visual_tile_paths.size() != active_tiles.size():
		_errors.append("TerrainDef visual_tile_paths should match active tile count")
	var observed_tile_count: int = 0
	for tile_array_index in range(active_tiles.size()):
		var tile_index: Vector2i = active_tiles[tile_array_index]
		var tile_path: String = CedarTerrainDef.call("visual_tile_path_for_tile", tile_index)
		if tile_path.is_empty():
			_errors.append("TerrainDef visual tile path is empty for tile " + str(tile_index))
			continue
		if not FileAccess.file_exists(tile_path):
			_errors.append("TerrainDef visual tile path does not exist: " + tile_path)
			continue
		var expected_name: String = TerrainVisualBuilderScript.visual_tile_node_name(tile_index, tile_path, tile_array_index)
		var tile_node: Node = terrain_root.get_node_or_null(expected_name)
		if tile_node == null:
			_errors.append("TerrainVisuals missing active visual tile " + expected_name + " from " + tile_path)
			continue
		observed_tile_count += 1
		if not tile_node.has_meta(TerrainVisualBuilderScript.TILE_INDEX_META):
			_errors.append(expected_name + " should expose its TerrainDef tile index metadata")
		elif tile_node.get_meta(TerrainVisualBuilderScript.TILE_INDEX_META) != tile_index:
			_errors.append(expected_name + " tile index metadata should match " + str(tile_index))
		if not tile_node.has_meta(TerrainVisualBuilderScript.TILE_PATH_META):
			_errors.append(expected_name + " should expose its TerrainDef visual tile path metadata")
		elif String(tile_node.get_meta(TerrainVisualBuilderScript.TILE_PATH_META)) != tile_path:
			_errors.append(expected_name + " visual tile path metadata should match " + tile_path)
		var tile_mesh_count: int = _count_mesh_instances(tile_node)
		if tile_mesh_count <= 0:
			_errors.append(expected_name + " should contain mesh instances")
		_require_geometry_visibility_range(tile_node, expected_name, GameConfig.vis_range_terrain)
		_require_visual_tile_bounds(tile_node, tile_index, expected_name)
	if observed_tile_count != active_tiles.size():
		_errors.append("TerrainVisuals should instantiate every active visual tile before tick 0")


func _inspect_terrain_def_visual_tile_contract(active_tiles: Array[Vector2i]) -> void:
	var tile_grid: Vector2i = CedarTerrainDef.get("tile_grid")
	var tile_grid_origin: Vector2i = CedarTerrainDef.get("tile_grid_origin")
	if tile_grid != EXPECTED_TERRAIN_TILE_GRID:
		_errors.append("TerrainDef tile_grid expected " + str(EXPECTED_TERRAIN_TILE_GRID) + ", got " + str(tile_grid))
	if tile_grid_origin != EXPECTED_TERRAIN_TILE_GRID_ORIGIN:
		_errors.append("TerrainDef tile_grid_origin expected " + str(EXPECTED_TERRAIN_TILE_GRID_ORIGIN) + ", got " + str(tile_grid_origin))
	if active_tiles.size() != EXPECTED_TERRAIN_ACTIVE_TILE_COUNT:
		_errors.append("TerrainDef active visual tile count expected " + str(EXPECTED_TERRAIN_ACTIVE_TILE_COUNT) + ", got " + str(active_tiles.size()))
	for i in range(EXPECTED_TERRAIN_ACTIVE_TILE_COUNT):
		var expected_tile: Vector2i = Vector2i(0, EXPECTED_TERRAIN_TILE_GRID_ORIGIN.y + i)
		if i >= active_tiles.size():
			continue
		if active_tiles[i] != expected_tile:
			_errors.append("TerrainDef active visual tile " + str(i) + " expected " + str(expected_tile) + ", got " + str(active_tiles[i]))


func _inspect_landmark_tile_coverage(active_tiles: Array[Vector2i]) -> void:
	var landmark_ids: Array[StringName] = CedarRoute.get("landmark_ids")
	for i in range(landmark_ids.size()):
		var landmark_id: StringName = landmark_ids[i]
		var position: Vector3 = CedarRoute.call("landmark_position", landmark_id)
		var world_xz: Vector2 = Vector2(position.x, position.z)
		if not bool(CedarTerrainDef.call("contains_world_xz", world_xz)):
			_errors.append("Cedar landmark " + String(landmark_id) + " should be inside TerrainDef bounds")
			continue
		var tile_index: Vector2i = CedarTerrainDef.call("tile_index_for_world_xz", world_xz)
		if not active_tiles.has(tile_index):
			_errors.append("Cedar landmark " + String(landmark_id) + " should resolve to an active visual tile, got " + str(tile_index))


func _require_visual_tile_bounds(tile_node: Node, tile_index: Vector2i, label: String) -> void:
	var accumulator: BoundsAccumulator = BoundsAccumulator.new()
	_collect_mesh_bounds(tile_node, accumulator)
	if not accumulator.has_bounds:
		_errors.append(label + " should expose mesh bounds for TerrainDef tile_bounds")
		return
	var expected_bounds: Rect2 = CedarTerrainDef.call("tile_bounds", tile_index)
	var expected_min: Vector2 = expected_bounds.position
	var expected_max: Vector2 = expected_bounds.position + expected_bounds.size
	if absf(accumulator.bounds_min.x - expected_min.x) > TERRAIN_TILE_BOUNDS_TOLERANCE:
		_errors.append(label + " bounds min X expected " + str(expected_min.x) + ", got " + str(accumulator.bounds_min.x))
	if absf(accumulator.bounds_max.x - expected_max.x) > TERRAIN_TILE_BOUNDS_TOLERANCE:
		_errors.append(label + " bounds max X expected " + str(expected_max.x) + ", got " + str(accumulator.bounds_max.x))
	if absf(accumulator.bounds_min.z - expected_min.y) > TERRAIN_TILE_BOUNDS_TOLERANCE:
		_errors.append(label + " bounds min Z expected " + str(expected_min.y) + ", got " + str(accumulator.bounds_min.z))
	if absf(accumulator.bounds_max.z - expected_max.y) > TERRAIN_TILE_BOUNDS_TOLERANCE:
		_errors.append(label + " bounds max Z expected " + str(expected_max.y) + ", got " + str(accumulator.bounds_max.z))


func _inspect_terrain_visual_layout(terrain_root: Node) -> void:
	var accumulator: BoundsAccumulator = BoundsAccumulator.new()
	_collect_mesh_bounds(terrain_root, accumulator)
	if not accumulator.has_bounds:
		_errors.append("TerrainVisuals should expose visual tile mesh bounds")
		return
	var route_bounds_min: Vector3 = CedarRoute.get("bounds_min")
	var route_bounds_max: Vector3 = CedarRoute.get("bounds_max")
	if accumulator.bounds_min.x > route_bounds_min.x + HEIGHTMESH_ROUTE_MARGIN:
		_errors.append("TerrainVisuals should cover route min X within margin, got " + str(accumulator.bounds_min.x))
	if accumulator.bounds_max.x < route_bounds_max.x - HEIGHTMESH_ROUTE_MARGIN:
		_errors.append("TerrainVisuals should cover route max X within margin, got " + str(accumulator.bounds_max.x))
	if accumulator.bounds_min.z > route_bounds_min.z + HEIGHTMESH_ROUTE_MARGIN:
		_errors.append("TerrainVisuals should cover route min Z within margin, got " + str(accumulator.bounds_min.z))
	if accumulator.bounds_max.z < route_bounds_max.z - HEIGHTMESH_ROUTE_MARGIN:
		_errors.append("TerrainVisuals should cover route max Z within margin, got " + str(accumulator.bounds_max.z))
	_require_heightmesh_surface_visuals(terrain_root)


func _require_heightmesh_surface_visuals(parent: Node) -> void:
	var observed_surface_ids: Array[StringName] = []
	_collect_heightmesh_surface_visuals(parent, observed_surface_ids)
	var expected_surface_ids: Array[StringName] = CedarSurfaceVisualCatalog.call("supported_surface_ids")
	for surface_id in expected_surface_ids:
		if not observed_surface_ids.has(surface_id):
			_errors.append("TerrainVisuals missing visual material override for " + String(surface_id))


func _collect_heightmesh_surface_visuals(parent: Node, observed_surface_ids: Array[StringName]) -> void:
	var mesh_instance: MeshInstance3D = parent as MeshInstance3D
	if mesh_instance != null:
		_inspect_heightmesh_mesh_materials(mesh_instance, observed_surface_ids)
	for child in parent.get_children():
		_collect_heightmesh_surface_visuals(child, observed_surface_ids)


func _inspect_heightmesh_mesh_materials(mesh_instance: MeshInstance3D, observed_surface_ids: Array[StringName]) -> void:
	var mesh: Mesh = mesh_instance.mesh
	if mesh == null:
		return
	for surface_index in range(mesh.get_surface_count()):
		var material_token: StringName = _material_token_for_terrain_surface(mesh, surface_index)
		if material_token == &"":
			continue
		var visual_def: Resource = CedarSurfaceVisualCatalog.call("visual_for_terrain_material_token", material_token)
		if visual_def == null:
			_errors.append("missing SurfaceVisualDef for terrain material token " + String(material_token))
			continue
		var surface_id: StringName = visual_def.get("surface_id")
		var visual_id: StringName = visual_def.get("id")
		if not observed_surface_ids.has(surface_id):
			observed_surface_ids.append(surface_id)
		var material: StandardMaterial3D = mesh_instance.get_surface_override_material(surface_index) as StandardMaterial3D
		if material == null:
			_errors.append("terrain surface " + String(surface_id) + " should have a StandardMaterial3D override")
			continue
		var wetness: float = clampf(float(visual_def.get("wetness")), 0.0, 1.0)
		var base_color: Color = visual_def.get("albedo_color")
		var expected_color: Color = _wet_albedo_color(base_color, wetness)
		var expected_roughness: float = _wet_roughness(float(visual_def.get("roughness")), wetness)
		var expected_uv_scale: Vector2 = visual_def.get("texture_uv_scale")
		var expected_detail_uv_scale: Vector2 = visual_def.get("detail_uv_scale")
		var expected_triplanar: bool = bool(visual_def.get("triplanar"))
		var expected_name: String = "terrain_visual_" + String(visual_id)
		if material.resource_name != expected_name:
			_errors.append("terrain surface " + String(surface_id) + " override name expected " + expected_name + ", got " + material.resource_name)
		if not _colors_match(material.albedo_color, expected_color):
			_errors.append("terrain surface " + String(surface_id) + " albedo should match SurfaceVisualCatalog")
		if absf(material.roughness - expected_roughness) > FLOAT_EPSILON:
			_errors.append("terrain surface " + String(surface_id) + " roughness expected " + str(expected_roughness) + ", got " + str(material.roughness))
		if absf(material.metallic) > FLOAT_EPSILON:
			_errors.append("terrain surface " + String(surface_id) + " metallic should be 0")
		if absf(material.uv1_scale.x - expected_uv_scale.x) > FLOAT_EPSILON or absf(material.uv1_scale.y - expected_uv_scale.y) > FLOAT_EPSILON:
			_errors.append("terrain surface " + String(surface_id) + " uv1_scale expected " + str(expected_uv_scale) + ", got " + str(material.uv1_scale))
		if absf(material.uv2_scale.x - expected_detail_uv_scale.x) > FLOAT_EPSILON or absf(material.uv2_scale.y - expected_detail_uv_scale.y) > FLOAT_EPSILON:
			_errors.append("terrain surface " + String(surface_id) + " uv2_scale expected " + str(expected_detail_uv_scale) + ", got " + str(material.uv2_scale))
		if material.uv1_triplanar != expected_triplanar:
			_errors.append("terrain surface " + String(surface_id) + " uv1_triplanar should match SurfaceVisualCatalog")
		if material.uv1_world_triplanar != expected_triplanar:
			_errors.append("terrain surface " + String(surface_id) + " uv1_world_triplanar should match SurfaceVisualCatalog")
		if material.uv2_triplanar != expected_triplanar:
			_errors.append("terrain surface " + String(surface_id) + " uv2_triplanar should match SurfaceVisualCatalog")
		if material.uv2_world_triplanar != expected_triplanar:
			_errors.append("terrain surface " + String(surface_id) + " uv2_world_triplanar should match SurfaceVisualCatalog")
		if material.texture_repeat != true:
			_errors.append("terrain surface " + String(surface_id) + " should repeat terrain textures")
		_require_material_texture(material.albedo_texture, String(visual_def.get("albedo_texture_path")), "terrain surface " + String(surface_id) + " albedo texture")
		var expected_normal_texture_path: String = visual_def.get("normal_texture_path")
		if not expected_normal_texture_path.is_empty() and not material.normal_enabled:
			_errors.append("terrain surface " + String(surface_id) + " should enable normal mapping")
		if absf(material.normal_scale - float(visual_def.get("normal_scale"))) > FLOAT_EPSILON:
			_errors.append("terrain surface " + String(surface_id) + " normal_scale should match SurfaceVisualCatalog")
		_require_material_texture(material.normal_texture, expected_normal_texture_path, "terrain surface " + String(surface_id) + " normal texture")
		var expected_detail_albedo_path: String = visual_def.get("detail_albedo_texture_path")
		var expected_detail_normal_path: String = visual_def.get("detail_normal_texture_path")
		if not expected_detail_albedo_path.is_empty() or not expected_detail_normal_path.is_empty():
			if not material.detail_enabled:
				_errors.append("terrain surface " + String(surface_id) + " should enable detail mapping")
			if material.detail_blend_mode != BaseMaterial3D.BLEND_MODE_MUL:
				_errors.append("terrain surface " + String(surface_id) + " detail_blend_mode should multiply")
			if material.detail_uv_layer != BaseMaterial3D.DETAIL_UV_2:
				_errors.append("terrain surface " + String(surface_id) + " detail_uv_layer should use UV2")
			_require_material_texture(material.detail_mask, TERRAIN_DETAIL_MASK_TEXTURE, "terrain surface " + String(surface_id) + " detail mask")
			_require_material_texture(material.detail_albedo, expected_detail_albedo_path, "terrain surface " + String(surface_id) + " detail albedo")
			_require_material_texture(material.detail_normal, expected_detail_normal_path, "terrain surface " + String(surface_id) + " detail normal")
		if wetness > 0.0:
			if not material.clearcoat_enabled:
				_errors.append("terrain surface " + String(surface_id) + " should enable clearcoat when wet")
			if absf(material.clearcoat - WET_CLEARCOAT * wetness) > FLOAT_EPSILON:
				_errors.append("terrain surface " + String(surface_id) + " clearcoat should scale with wetness")
			if absf(material.clearcoat_roughness - WET_CLEARCOAT_ROUGHNESS) > FLOAT_EPSILON:
				_errors.append("terrain surface " + String(surface_id) + " clearcoat_roughness should match wetness model")
		elif material.clearcoat_enabled:
			_errors.append("terrain surface " + String(surface_id) + " should not enable clearcoat when dry")


func _material_token_for_terrain_surface(mesh: Mesh, surface_index: int) -> StringName:
	var material: Material = mesh.surface_get_material(surface_index)
	if material == null:
		return &""
	var material_name: String = material.resource_name
	if not material_name.begins_with(TERRAIN_MATERIAL_PREFIX):
		return &""
	return StringName(material_name.substr(TERRAIN_MATERIAL_PREFIX.length()))


func _require_material_texture(texture: Texture2D, expected_path: String, label: String) -> void:
	if expected_path.is_empty():
		return
	if texture == null:
		_errors.append(label + " should load " + expected_path)
		return
	var actual_path: String = texture.resource_path
	if actual_path.is_empty() and texture.has_meta(TEXTURE_SOURCE_PATH_META):
		actual_path = String(texture.get_meta(TEXTURE_SOURCE_PATH_META))
	if actual_path != expected_path:
		_errors.append(label + " expected " + expected_path + ", got " + actual_path)


func _colors_match(actual: Color, expected: Color) -> bool:
	return absf(actual.r - expected.r) <= FLOAT_EPSILON and absf(actual.g - expected.g) <= FLOAT_EPSILON and absf(actual.b - expected.b) <= FLOAT_EPSILON and absf(actual.a - expected.a) <= FLOAT_EPSILON


func _wet_albedo_color(base_color: Color, wetness: float) -> Color:
	var multiplier: float = 1.0 + (WET_DIFFUSE_MULTIPLIER - 1.0) * wetness
	return Color(base_color.r * multiplier, base_color.g * multiplier, base_color.b * multiplier, base_color.a)


func _wet_roughness(base_roughness: float, wetness: float) -> float:
	return base_roughness + (WET_ROUGHNESS - base_roughness) * wetness


func _collect_mesh_bounds(parent: Node, accumulator: BoundsAccumulator) -> void:
	var mesh_instance: MeshInstance3D = parent as MeshInstance3D
	if mesh_instance != null:
		var local_bounds: AABB = mesh_instance.get_aabb()
		for x_index in range(2):
			for y_index in range(2):
				for z_index in range(2):
					var local_point: Vector3 = local_bounds.position + Vector3(
						local_bounds.size.x if x_index == 1 else 0.0,
						local_bounds.size.y if y_index == 1 else 0.0,
						local_bounds.size.z if z_index == 1 else 0.0
					)
					_include_bounds_point(accumulator, mesh_instance.global_transform * local_point)
	for child in parent.get_children():
		_collect_mesh_bounds(child, accumulator)


func _include_bounds_point(accumulator: BoundsAccumulator, point: Vector3) -> void:
	if not accumulator.has_bounds:
		accumulator.has_bounds = true
		accumulator.bounds_min = point
		accumulator.bounds_max = point
		return
	accumulator.bounds_min = Vector3(
		minf(accumulator.bounds_min.x, point.x),
		minf(accumulator.bounds_min.y, point.y),
		minf(accumulator.bounds_min.z, point.z)
	)
	accumulator.bounds_max = Vector3(
		maxf(accumulator.bounds_max.x, point.x),
		maxf(accumulator.bounds_max.y, point.y),
		maxf(accumulator.bounds_max.z, point.z)
	)


func _inspect_terrain_heightmap_collision(cedar_world: Node) -> void:
	var static_body_count: int = _count_static_bodies(cedar_world)
	if static_body_count != 1:
		_errors.append("Cedar Hollow should expose exactly one terrain StaticBody3D, got " + str(static_body_count))
	var box_collision_count: int = _count_box_collision_shapes(cedar_world)
	if box_collision_count > 0:
		_errors.append("Cedar Hollow terrain collision should not retain BoxShape3D collision shapes: " + str(box_collision_count))
	var body: StaticBody3D = _require_node(cedar_world, TERRAIN_HEIGHTMAP_COLLISION_NODE) as StaticBody3D
	if body == null:
		return
	if not body.is_in_group(SurfaceMapScript.TERRAIN_SURFACE_MAP_GROUP):
		_errors.append(TERRAIN_HEIGHTMAP_COLLISION_NODE + " should be in the terrain surface-id map group")
	if not body.has_meta(SurfaceMapScript.TERRAIN_SURFACE_OVERRIDE_RECTS_META):
		_errors.append(TERRAIN_HEIGHTMAP_COLLISION_NODE + " should expose terrain surface override rects")
	var active_tiles: Array[Vector2i] = CedarTerrainDef.call("active_tile_indices")
	var collision_tile_paths: Array[String] = CedarTerrainDef.get("collision_tile_paths")
	if collision_tile_paths.size() != active_tiles.size():
		_errors.append(TERRAIN_HEIGHTMAP_COLLISION_NODE + " collision tile paths should match active tile count")
	var observed_collision_shapes: int = 0
	for i in range(active_tiles.size()):
		var tile_index: Vector2i = active_tiles[i]
		var collision_name: String = "Collision" if tile_index == Vector2i.ZERO else "Collision_" + str(tile_index.x) + "_" + str(tile_index.y)
		var collision: CollisionShape3D = _require_node(body, collision_name) as CollisionShape3D
		if collision == null:
			continue
		observed_collision_shapes += 1
		if collision.disabled:
			_errors.append(TERRAIN_HEIGHTMAP_COLLISION_NODE + " " + collision_name + " should be enabled")
		var heightmap: HeightMapShape3D = collision.shape as HeightMapShape3D
		if heightmap == null:
			_errors.append(TERRAIN_HEIGHTMAP_COLLISION_NODE + " " + collision_name + " should use HeightMapShape3D")
			continue
		if i < collision_tile_paths.size() and heightmap.resource_path != collision_tile_paths[i]:
			_errors.append(TERRAIN_HEIGHTMAP_COLLISION_NODE + " " + collision_name + " should use committed heightmap collision resource")
		if heightmap.map_width <= 1 or heightmap.map_depth <= 1:
			_errors.append(TERRAIN_HEIGHTMAP_COLLISION_NODE + " " + collision_name + " heightmap dimensions should be populated")
		if heightmap.map_data.size() != heightmap.map_width * heightmap.map_depth:
			_errors.append(TERRAIN_HEIGHTMAP_COLLISION_NODE + " " + collision_name + " map_data size should match heightmap dimensions")
	if observed_collision_shapes != active_tiles.size():
		_errors.append(TERRAIN_HEIGHTMAP_COLLISION_NODE + " should preload every active collision tile before tick 0")


func _inspect_feature_sequences(feature_root: Node) -> void:
	_require_sequential_named_nodes(feature_root, "boardwalk_segment_", EXPECTED_BOARDWALK_SEGMENTS)
	var boardwalk_start_z: float = -4.31
	var boardwalk_stride_z: float = 0.24
	for i in range(EXPECTED_BOARDWALK_SEGMENTS):
		var node_path: String = "boardwalk_segment_" + str(i + 1)
		var expected_position: Vector3 = Vector3(3.25, 0.035, boardwalk_start_z + float(i) * boardwalk_stride_z)
		_require_node_position(feature_root, node_path, expected_position, FEATURE_TRANSFORM_TOLERANCE)
		_require_node_scale(feature_root, node_path, Vector3(1.35, 1.0, 1.0), FLOAT_EPSILON)
		if i > 0:
			var previous: Node3D = feature_root.get_node_or_null("boardwalk_segment_" + str(i)) as Node3D
			var current: Node3D = feature_root.get_node_or_null(node_path) as Node3D
			if previous != null and current != null and current.position.z <= previous.position.z:
				_errors.append(node_path + " should advance along +Z from the previous boardwalk segment")
	_require_sequential_named_nodes(feature_root, "stepping_stone_", EXPECTED_STEPPING_STONES)
	var stepping_positions: Array[Vector3] = [
		Vector3(3.45, 0.01, -7.05),
		Vector3(3.85, 0.01, -7.35),
		Vector3(4.25, 0.01, -7.15),
		Vector3(4.65, 0.01, -7.5),
		Vector3(5.0, 0.01, -7.2)
	]
	for i in range(mini(EXPECTED_STEPPING_STONES, stepping_positions.size())):
		var stone_path: String = "stepping_stone_" + str(i + 1)
		_require_node_position(feature_root, stone_path, stepping_positions[i], FEATURE_TRANSFORM_TOLERANCE)
		_require_node_rotation(feature_root, stone_path, Vector3(0.0, float(i) * 23.0, 0.0), FLOAT_EPSILON)
	_require_minimum_xz_spacing(feature_root, "stepping_stone_", EXPECTED_STEPPING_STONES, 0.35)


func _inspect_scatter_layout(scatter_root: Node) -> void:
	_require_node_position(scatter_root, "grass_tuft_1", Vector3(-2.3, 0.0, -0.9), FEATURE_TRANSFORM_TOLERANCE)
	_require_node_position(scatter_root, "grass_tuft_18", Vector3(2.9, 0.0, -6.9), FEATURE_TRANSFORM_TOLERANCE)
	_require_node_position(scatter_root, "grass_occluder_1", Vector3(-2.65, 0.0, -1.25), FEATURE_TRANSFORM_TOLERANCE)
	_require_node_position(scatter_root, "grass_occluder_10", Vector3(2.65, 0.0, -7.25), FEATURE_TRANSFORM_TOLERANCE)
	_require_node_position(scatter_root, "boulder_1", Vector3(-2.65, 0.3, -8.5), FEATURE_TRANSFORM_TOLERANCE)
	_require_node_position(scatter_root, "boulder_5", Vector3(3.15, 0.0, -7.25), FEATURE_TRANSFORM_TOLERANCE)
	_require_node_position(scatter_root, "branch_5", Vector3(-0.9, 0.02, -9.45), FEATURE_TRANSFORM_TOLERANCE)
	_require_node_position(scatter_root, "pinecone_8", Vector3(-1.9, 0.24, -8.9), FEATURE_TRANSFORM_TOLERANCE)
	_require_node_position(scatter_root, "fern_clump_1", Vector3(2.2, 0.0, -4.65), FEATURE_TRANSFORM_TOLERANCE)
	_require_node_position(scatter_root, "fern_clump_6", Vector3(3.05, 0.0, -7.65), FEATURE_TRANSFORM_TOLERANCE)
	_require_node_position(scatter_root, "cattail_1", Vector3(3.95, 0.0, -6.25), FEATURE_TRANSFORM_TOLERANCE)
	_require_node_position(scatter_root, "cattail_5", Vector3(4.45, 0.0, -7.55), FEATURE_TRANSFORM_TOLERANCE)
	_inspect_scatter_sequences(scatter_root)
	_inspect_grass_occluders(scatter_root)
	_require_direct_children_inside_xz(scatter_root, "ScatterVisuals", SCATTER_X_MIN, SCATTER_X_MAX, SCATTER_Z_MIN, SCATTER_Z_MAX)


func _inspect_scatter_sequences(scatter_root: Node) -> void:
	_require_sequential_named_nodes(scatter_root, "grass_tuft_", EXPECTED_GRASS_TUFTS)
	_require_sequential_named_nodes(scatter_root, "grass_occluder_", EXPECTED_GRASS_OCCLUDERS)
	_require_sequential_named_nodes(scatter_root, "boulder_", EXPECTED_BOULDERS)
	_require_sequential_named_nodes(scatter_root, "branch_", EXPECTED_BRANCHES)
	_require_sequential_named_nodes(scatter_root, "pinecone_", EXPECTED_PINECONES)
	_require_sequential_named_nodes(scatter_root, "fern_clump_", EXPECTED_FERN_CLUMPS)
	_require_sequential_named_nodes(scatter_root, "cattail_", EXPECTED_CATTAILS)
	_require_minimum_xz_spacing(scatter_root, "grass_tuft_", EXPECTED_GRASS_TUFTS, 0.45)
	_require_minimum_xz_spacing(scatter_root, "grass_occluder_", EXPECTED_GRASS_OCCLUDERS, 0.75)
	_require_minimum_xz_spacing(scatter_root, "boulder_", EXPECTED_BOULDERS, 0.70)
	_require_minimum_xz_spacing(scatter_root, "branch_", EXPECTED_BRANCHES, 1.10)
	_require_minimum_xz_spacing(scatter_root, "pinecone_", EXPECTED_PINECONES, 0.55)
	_require_minimum_xz_spacing(scatter_root, "fern_clump_", EXPECTED_FERN_CLUMPS, 0.70)
	_require_minimum_xz_spacing(scatter_root, "cattail_", EXPECTED_CATTAILS, 0.35)


func _inspect_grass_occluders(scatter_root: Node) -> void:
	for i in range(EXPECTED_GRASS_OCCLUDERS):
		var node_path: String = "grass_occluder_" + str(i + 1)
		var occluder: Node3D = _require_node(scatter_root, node_path) as Node3D
		if occluder == null:
			continue
		var position: Vector3 = occluder.position
		if position.x < GRASS_OCCLUDER_X_MIN or position.x > GRASS_OCCLUDER_X_MAX or position.z < GRASS_OCCLUDER_Z_MIN or position.z > GRASS_OCCLUDER_Z_MAX:
			_errors.append(node_path + " should remain in the meadow/creek occluder band, got " + str(position))
		var accumulator: BoundsAccumulator = BoundsAccumulator.new()
		_collect_mesh_bounds(occluder, accumulator)
		if not accumulator.has_bounds:
			_errors.append(node_path + " should expose mesh bounds")
			continue
		var height: float = accumulator.bounds_max.y - accumulator.bounds_min.y
		if height < GRASS_OCCLUDER_MIN_HEIGHT:
			_errors.append(node_path + " height expected at least " + str(GRASS_OCCLUDER_MIN_HEIGHT) + ", got " + str(height))
		var camera_scale_height: float = GameConfig.cam_height * 3.0
		if accumulator.bounds_max.y < occluder.global_position.y + camera_scale_height:
			_errors.append(node_path + " should rise above the low chase-camera scale read")


func _inspect_chase_capture_clearance(scatter_root: Node) -> void:
	var prefixes: Array[String] = ["grass_occluder_", "cattail_"]
	var basis: Basis = Basis(Vector3.UP, deg_to_rad(CROSSING_CHASE_QA_YAW_DEGREES))
	var forward: Vector3 = -basis.z.normalized()
	var forward_xz: Vector2 = Vector2(forward.x, forward.z).normalized()
	for child in scatter_root.get_children():
		var node: Node3D = child as Node3D
		if node == null or not _name_begins_with_any(String(child.name), prefixes):
			continue
		var delta: Vector2 = Vector2(
			node.position.x - CROSSING_CHASE_QA_POSITION.x,
			node.position.z - CROSSING_CHASE_QA_POSITION.z
		)
		var along: float = delta.dot(forward_xz)
		if along <= 0.0 or along > CHASE_CLEAR_CORRIDOR_LENGTH:
			continue
		var lateral: float = absf(delta.x * forward_xz.y - delta.y * forward_xz.x)
		if lateral < CHASE_CLEAR_CORRIDOR_HALF_WIDTH:
			_errors.append("ScatterVisuals/" + String(child.name) + " blocks the crossing chase QA corridor")


func _inspect_foliage_bar(scatter_root: Node, context: String) -> void:
	if GameConfig.visual_bar_lighting_spec_version != VISUAL_BAR_LIGHTING_SPEC_VERSION:
		_errors.append(context + " visual_bar_lighting_spec_version expected " + str(VISUAL_BAR_LIGHTING_SPEC_VERSION) + ", got " + str(GameConfig.visual_bar_lighting_spec_version))
	var grass_tuft_count: int = 0
	var grass_clump_count: int = 0
	for child: Node in scatter_root.get_children():
		var child_name: String = String(child.name)
		if child_name.begins_with("grass_tuft_"):
			grass_tuft_count += 1
		if _is_scatter_grass_child(child_name):
			grass_clump_count += 1
			_require_grass_clump_visual_bar(child, context + " ScatterVisuals/" + child_name)
	if grass_tuft_count < GameConfig.grass_clump_count:
		_errors.append(context + " ScatterVisuals grass_tuft_* count expected at least " + str(GameConfig.grass_clump_count) + ", got " + str(grass_tuft_count))
	if grass_clump_count <= 0:
		_errors.append(context + " ScatterVisuals should contain grass clump MultiMeshInstance3D nodes")
	_require_scatter_spot_visibility(scatter_root, "boulder_1", context)
	_require_scatter_spot_visibility(scatter_root, "fern_clump_1", context)


func _require_grass_clump_visual_bar(child: Node, label: String) -> void:
	var clump: MultiMeshInstance3D = child as MultiMeshInstance3D
	if clump == null:
		_errors.append(label + " should be a MultiMeshInstance3D")
		return
	_require_float_close(label + " visibility range", clump.visibility_range_end, GameConfig.vis_range_grass, FLOAT_EPSILON)
	var material: ShaderMaterial = clump.material_override as ShaderMaterial
	if material == null:
		_errors.append(label + " should use ShaderMaterial material_override")
		return
	if material.shader == null:
		_errors.append(label + " should have a grass shader")
		return
	var base_color: Color = _require_shader_color_parameter(material, "blade_base_color", label)
	if base_color.r >= GRASS_BASE_RED_MAX + FOLIAGE_SHADER_TOLERANCE:
		_errors.append(label + " blade_base_color.r expected below " + str(GRASS_BASE_RED_MAX) + ", got " + str(base_color.r))
	if base_color.g <= GRASS_BASE_GREEN_MIN - FOLIAGE_SHADER_TOLERANCE:
		_errors.append(label + " blade_base_color.g expected above " + str(GRASS_BASE_GREEN_MIN) + ", got " + str(base_color.g))
	if base_color.b >= GRASS_BASE_BLUE_MAX + FOLIAGE_SHADER_TOLERANCE:
		_errors.append(label + " blade_base_color.b expected below " + str(GRASS_BASE_BLUE_MAX) + ", got " + str(base_color.b))
	var tip_color: Color = _require_shader_color_parameter(material, "blade_tip_color", label)
	if tip_color.r <= GRASS_TIP_RED_MIN - FOLIAGE_SHADER_TOLERANCE:
		_errors.append(label + " blade_tip_color.r expected above " + str(GRASS_TIP_RED_MIN) + ", got " + str(tip_color.r))
	if tip_color.g <= GRASS_TIP_GREEN_MIN - FOLIAGE_SHADER_TOLERANCE:
		_errors.append(label + " blade_tip_color.g expected above " + str(GRASS_TIP_GREEN_MIN) + ", got " + str(tip_color.g))
	var backlight_color: Color = _require_shader_color_parameter(material, "backlight_color", label)
	_require_color_close(label + " backlight_color", backlight_color, GameConfig.grass_backlight_color, FOLIAGE_SHADER_TOLERANCE)
	var backlight_energy: float = _require_shader_float_parameter(material, "backlight_energy", label)
	if GameConfig.grass_backlight_enabled:
		if backlight_energy <= 0.0:
			_errors.append(label + " backlight_energy should be positive when grass backlight is enabled")
		_require_float_close(label + " backlight_energy", backlight_energy, maxf(GameConfig.grass_backlight_energy, 0.0), FOLIAGE_SHADER_TOLERANCE)
	else:
		_require_float_close(label + " backlight_energy", backlight_energy, 0.0, FOLIAGE_SHADER_TOLERANCE)
	var wind_strength: float = _require_shader_float_parameter(material, "wind_strength", label)
	if GameConfig.grass_wind_enabled:
		if wind_strength <= 0.0:
			_errors.append(label + " wind_strength should be positive when grass wind is enabled")
		_require_float_close(label + " wind_strength", wind_strength, maxf(GameConfig.grass_wind_strength, 0.0), FOLIAGE_SHADER_TOLERANCE)
	else:
		_require_float_close(label + " wind_strength", wind_strength, 0.0, FOLIAGE_SHADER_TOLERANCE)
	var wind_speed: float = _require_shader_float_parameter(material, "wind_speed", label)
	_require_float_close(label + " wind_speed", wind_speed, maxf(GameConfig.grass_wind_speed, 0.0), FOLIAGE_SHADER_TOLERANCE)


func _require_shader_color_parameter(material: ShaderMaterial, parameter_name: String, label: String) -> Color:
	var value: Variant = material.get_shader_parameter(parameter_name)
	if not (value is Color):
		_errors.append(label + " shader parameter " + parameter_name + " should be Color")
		return Color.TRANSPARENT
	var color_value: Color = value
	return color_value


func _require_shader_float_parameter(material: ShaderMaterial, parameter_name: String, label: String) -> float:
	var value: Variant = material.get_shader_parameter(parameter_name)
	if not (value is float) and not (value is int):
		_errors.append(label + " shader parameter " + parameter_name + " should be float")
		return 0.0
	return float(value)


func _require_scatter_spot_visibility(scatter_root: Node, node_name: String, context: String) -> void:
	var node: Node = _require_node(scatter_root, node_name)
	if node == null:
		return
	_require_geometry_visibility_range(node, context + " ScatterVisuals/" + node_name, GameConfig.vis_range_scatter)


func _inspect_ground_detail_layout(ground_detail_root: Node) -> void:
	_require_node_position(ground_detail_root, "mud_patch_1", Vector3(2.16, 0.012, -4.72), FEATURE_TRANSFORM_TOLERANCE)
	_require_node_position(ground_detail_root, "tire_track_1_left", Vector3(2.28642, 0.014, -5.133514), FEATURE_TRANSFORM_TOLERANCE)
	_require_node_position(ground_detail_root, "gravel_speckle_1", Vector3(-0.82, 0.018, 1.16), FEATURE_TRANSFORM_TOLERANCE)
	_require_node_position(ground_detail_root, "leaf_litter_1", Vector3(-0.82, 0.015, -1.72), FEATURE_TRANSFORM_TOLERANCE)
	_require_node_position(ground_detail_root, "root_ridge_1", Vector3(-0.55, 0.016, -3.42), FEATURE_TRANSFORM_TOLERANCE)
	_require_node_position(ground_detail_root, "puddle_sheen_1", Vector3(2.85, 0.016, -5.10), FEATURE_TRANSFORM_TOLERANCE)
	_require_node_position(ground_detail_root, "wet_glint_1", Vector3(3.58, 0.016, -7.08), FEATURE_TRANSFORM_TOLERANCE)
	_require_direct_children_inside_xz(ground_detail_root, "GroundDetailVisuals", GROUND_DETAIL_X_MIN, GROUND_DETAIL_X_MAX, GROUND_DETAIL_Z_MIN, GROUND_DETAIL_Z_MAX)
	for child in ground_detail_root.get_children():
		var mesh_instance: MeshInstance3D = child as MeshInstance3D
		if mesh_instance == null:
			_errors.append("GroundDetailVisuals/" + String(child.name) + " should be a MeshInstance3D")
			continue
		var material: StandardMaterial3D = mesh_instance.material_override as StandardMaterial3D
		if material == null:
			_errors.append("GroundDetailVisuals/" + String(child.name) + " should use StandardMaterial3D")
		else:
			if absf(material.metallic) > FLOAT_EPSILON:
				_errors.append("GroundDetailVisuals/" + String(child.name) + " should be nonmetallic")
			if material.albedo_color.a < 1.0 and material.transparency != BaseMaterial3D.TRANSPARENCY_ALPHA:
				_errors.append("GroundDetailVisuals/" + String(child.name) + " translucent detail should use alpha transparency")
		var accumulator: BoundsAccumulator = BoundsAccumulator.new()
		_collect_mesh_bounds(mesh_instance, accumulator)
		if accumulator.has_bounds:
			var height: float = accumulator.bounds_max.y - accumulator.bounds_min.y
			if height > GROUND_DETAIL_MAX_HEIGHT:
				_errors.append("GroundDetailVisuals/" + String(child.name) + " should stay low to the ground, height was " + str(height))


func _inspect_ground_detail_bar(ground_detail_root: Node, chase_camera: Camera3D, context: String) -> void:
	_require_named_count(ground_detail_root, "mud_patch_", EXPECTED_MUD_PATCHES)
	_require_named_count(ground_detail_root, "tire_track_", EXPECTED_TIRE_TRACK_PAIRS * 2)
	_require_named_count(ground_detail_root, "gravel_speckle_", EXPECTED_GRAVEL_SPECKLES)
	_require_named_count(ground_detail_root, "leaf_litter_", EXPECTED_LEAF_LITTER)
	_require_named_count(ground_detail_root, "root_ridge_", EXPECTED_ROOT_RIDGES)
	_require_named_count(ground_detail_root, "puddle_sheen_", EXPECTED_PUDDLE_SHEENS)
	_require_named_count(ground_detail_root, "wet_glint_", EXPECTED_WET_GLINTS)
	for child: Node in ground_detail_root.get_children():
		var mesh_instance: MeshInstance3D = child as MeshInstance3D
		if mesh_instance == null:
			continue
		_require_float_close(context + " GroundDetailVisuals/" + String(child.name) + " visibility range", mesh_instance.visibility_range_end, GameConfig.vis_range_ground_detail, FLOAT_EPSILON)
	_require_ground_detail_material_ranges(ground_detail_root, context)
	_require_dust_mote_field(chase_camera, context)


func _require_ground_detail_material_ranges(ground_detail_root: Node, context: String) -> void:
	var mud_material: StandardMaterial3D = _require_ground_detail_material(ground_detail_root, "mud_patch_1", context)
	if mud_material != null:
		_require_float_in_range_with_tolerance(context + " mud_patch_1 alpha", mud_material.albedo_color.a, MUD_PATCH_ALPHA_MIN, MUD_PATCH_ALPHA_MAX, GROUND_DETAIL_MATERIAL_TOLERANCE)
		_require_float_in_range_with_tolerance(context + " mud_patch_1 roughness", mud_material.roughness, MUD_PATCH_ROUGHNESS_MIN, MUD_PATCH_ROUGHNESS_MAX, GROUND_DETAIL_MATERIAL_TOLERANCE)
	var puddle_material: StandardMaterial3D = _require_ground_detail_material(ground_detail_root, "puddle_sheen_1", context)
	if puddle_material != null:
		_require_float_in_range_with_tolerance(context + " puddle_sheen_1 roughness", puddle_material.roughness, PUDDLE_SHEEN_ROUGHNESS_MIN, PUDDLE_SHEEN_ROUGHNESS_MAX, GROUND_DETAIL_MATERIAL_TOLERANCE)
	var glint_material: StandardMaterial3D = _require_ground_detail_material(ground_detail_root, "wet_glint_1", context)
	if glint_material != null and glint_material.albedo_color.r <= WET_GLINT_RED_MIN - GROUND_DETAIL_MATERIAL_TOLERANCE:
		_errors.append(context + " wet_glint_1 albedo red expected greater than " + str(WET_GLINT_RED_MIN) + ", got " + str(glint_material.albedo_color.r))


func _require_ground_detail_material(ground_detail_root: Node, node_name: String, context: String) -> StandardMaterial3D:
	var child: Node = _require_node(ground_detail_root, node_name)
	if child == null:
		return null
	var mesh_instance: MeshInstance3D = child as MeshInstance3D
	if mesh_instance == null:
		_errors.append(context + " GroundDetailVisuals/" + node_name + " should be a MeshInstance3D")
		return null
	var material: StandardMaterial3D = mesh_instance.material_override as StandardMaterial3D
	if material == null:
		_errors.append(context + " GroundDetailVisuals/" + node_name + " should use StandardMaterial3D material_override")
		return null
	return material


func _require_dust_mote_field(chase_camera: Camera3D, context: String) -> void:
	if chase_camera == null:
		_errors.append(context + " ChaseCamera missing for DustMoteField inspection")
		return
	var field_node: Node = _require_node(chase_camera, DustTiltShiftVisualBuilderScript.DUST_FIELD_NAME)
	if field_node == null:
		return
	var particles: GPUParticles3D = field_node as GPUParticles3D
	if particles == null:
		_errors.append(context + " ChaseCamera/" + DustTiltShiftVisualBuilderScript.DUST_FIELD_NAME + " should be GPUParticles3D")
		return
	if particles.amount != GameConfig.dust_mote_count:
		_errors.append(context + " DustMoteField amount expected " + str(GameConfig.dust_mote_count) + ", got " + str(particles.amount))
	if not particles.use_fixed_seed:
		_errors.append(context + " DustMoteField should use a fixed seed")
	if particles.seed != DustTiltShiftVisualBuilderScript.DUST_FIXED_SEED:
		_errors.append(context + " DustMoteField seed expected " + str(DustTiltShiftVisualBuilderScript.DUST_FIXED_SEED) + ", got " + str(particles.seed))
	if particles.randomness != 0.0:
		_errors.append(context + " DustMoteField randomness expected 0.0, got " + str(particles.randomness))
	if not particles.emitting:
		_errors.append(context + " DustMoteField should emit by default")
	_require_float_close(context + " DustMoteField visibility range", particles.visibility_range_end, GameConfig.vis_range_dust, FLOAT_EPSILON)


func _require_float_in_range_with_tolerance(label: String, actual: float, minimum_value: float, maximum_value: float, tolerance: float) -> void:
	if actual < minimum_value - tolerance or actual > maximum_value + tolerance:
		_errors.append(label + " expected in [" + str(minimum_value) + ", " + str(maximum_value) + "] +/- " + str(tolerance) + ", got " + str(actual))


func _name_begins_with_any(child_name: String, prefixes: Array[String]) -> bool:
	for prefix in prefixes:
		if child_name.begins_with(prefix):
			return true
	return false


func _inspect_scatter_visibility_ranges(scatter_root: Node) -> void:
	for child: Node in scatter_root.get_children():
		var child_label: String = "ScatterVisuals/" + String(child.name)
		if _is_scatter_grass_child(String(child.name)):
			_require_geometry_visibility_range(child, child_label, GameConfig.vis_range_grass)
		else:
			_require_geometry_visibility_range(child, child_label, GameConfig.vis_range_scatter)


func _is_scatter_grass_child(child_name: String) -> bool:
	return child_name.begins_with("grass_tuft_") or child_name.begins_with("grass_occluder_")


func _require_geometry_visibility_range(parent: Node, label: String, expected_range_end: float) -> void:
	var geometry_instance: GeometryInstance3D = parent as GeometryInstance3D
	if geometry_instance != null and absf(geometry_instance.visibility_range_end - expected_range_end) > FLOAT_EPSILON:
		_errors.append(label + " visibility_range_end expected " + str(expected_range_end) + ", got " + str(geometry_instance.visibility_range_end))
	for child: Node in parent.get_children():
		_require_geometry_visibility_range(child, label + "/" + String(child.name), expected_range_end)


func _inspect_boundary_layout(boundary_root: Node) -> void:
	_require_node_position(boundary_root, "boundary_grass_1", Vector3(-5.05, 0.0, 0.8), FEATURE_TRANSFORM_TOLERANCE)
	_require_node_position(boundary_root, "boundary_grass_16", Vector3(4.95, 0.0, -8.5), FEATURE_TRANSFORM_TOLERANCE)
	_require_node_position(boundary_root, "boundary_grass_20", Vector3(1.0, 0.12, -9.95), FEATURE_TRANSFORM_TOLERANCE)
	_require_node_position(boundary_root, "boundary_boulder_1", Vector3(-5.15, 0.0, -0.9), FEATURE_TRANSFORM_TOLERANCE)
	_require_node_position(boundary_root, "boundary_boulder_8", Vector3(0.15, 0.18, -10.05), FEATURE_TRANSFORM_TOLERANCE)
	_require_node_position(boundary_root, "boundary_branch_1", Vector3(-4.9, 0.02, -2.2), FEATURE_TRANSFORM_TOLERANCE)
	_require_node_position(boundary_root, "boundary_branch_6", Vector3(-1.55, 0.31, -10.05), FEATURE_TRANSFORM_TOLERANCE)
	_require_node_position(boundary_root, "trail_blaze_1", Vector3(-4.68, 0.0, -2.55), FEATURE_TRANSFORM_TOLERANCE)
	_require_node_position(boundary_root, "trail_blaze_2", Vector3(-4.62, 0.0, -6.62), FEATURE_TRANSFORM_TOLERANCE)
	_require_node_position(boundary_root, "trail_blaze_3", Vector3(4.68, 0.0, -3.42), FEATURE_TRANSFORM_TOLERANCE)
	_require_node_position(boundary_root, "trail_blaze_4", Vector3(4.62, 0.0, -7.0), FEATURE_TRANSFORM_TOLERANCE)
	_require_node_rotation(boundary_root, "trail_blaze_1", Vector3(0.0, 80.0, 0.0), FLOAT_EPSILON)
	_require_node_rotation(boundary_root, "trail_blaze_2", Vector3(0.0, 72.0, 0.0), FLOAT_EPSILON)
	_require_node_rotation(boundary_root, "trail_blaze_3", Vector3(0.0, -82.0, 0.0), FLOAT_EPSILON)
	_require_node_rotation(boundary_root, "trail_blaze_4", Vector3(0.0, -72.0, 0.0), FLOAT_EPSILON)
	_inspect_trail_blaze_readability(boundary_root)
	_require_boundary_bands(boundary_root)


func _inspect_trail_blaze_readability(boundary_root: Node) -> void:
	for i in range(EXPECTED_TRAIL_BLAZES):
		var blaze_path: String = "trail_blaze_" + str(i + 1)
		var blaze: Node = _require_node(boundary_root, blaze_path)
		if blaze == null:
			continue
		_require_blaze_marker(blaze, blaze_path + "/contrast_backing", "contrast_backing", Color(1.0, 0.92, 0.42), LABEL_MIN_CONTRAST_RATIO)
		_require_blaze_marker(blaze, blaze_path + "/center_stripe", "center_stripe", Color(0.035, 0.028, 0.018), LABEL_MIN_CONTRAST_RATIO)
		_require_blaze_marker(blaze, blaze_path + "/arrow_left_arm", "arrow_left_arm", Color(0.035, 0.028, 0.018), ACCENT_MIN_CONTRAST_RATIO)
		_require_blaze_marker(blaze, blaze_path + "/arrow_right_arm", "arrow_right_arm", Color(0.035, 0.028, 0.018), ACCENT_MIN_CONTRAST_RATIO)


func _require_blaze_marker(parent: Node, label: String, child_name: String, contrast_against: Color, minimum_contrast: float) -> void:
	var marker: MeshInstance3D = _require_node(parent, child_name) as MeshInstance3D
	if marker == null:
		return
	var material: StandardMaterial3D = _require_mesh_standard_material(marker, label)
	if material == null:
		return
	_require_unshaded_material(material, label + " material")
	if _contrast_ratio(material.albedo_color, contrast_against) < minimum_contrast:
		_errors.append(label + " contrast should be at least " + str(minimum_contrast))


func _require_direct_children_inside_xz(parent: Node, label: String, min_x: float, max_x: float, min_z: float, max_z: float) -> void:
	for child in parent.get_children():
		var node: Node3D = child as Node3D
		if node == null:
			continue
		var local_position: Vector3 = node.position
		if local_position.x < min_x or local_position.x > max_x or local_position.z < min_z or local_position.z > max_z:
			_errors.append(label + "/" + String(child.name) + " should remain inside XZ range, got " + str(local_position))


func _require_sequential_named_nodes(parent: Node, prefix: String, expected_count: int) -> void:
	for i in range(expected_count):
		var node_path: String = prefix + str(i + 1)
		if parent.get_node_or_null(node_path) == null:
			_errors.append(String(parent.name) + " missing sequential node: " + node_path)


func _require_minimum_xz_spacing(parent: Node, prefix: String, expected_count: int, min_spacing: float) -> void:
	for i in range(expected_count):
		var path_a: String = prefix + str(i + 1)
		var node_a: Node3D = parent.get_node_or_null(path_a) as Node3D
		if node_a == null:
			continue
		for j in range(i + 1, expected_count):
			var path_b: String = prefix + str(j + 1)
			var node_b: Node3D = parent.get_node_or_null(path_b) as Node3D
			if node_b == null:
				continue
			var delta: Vector2 = Vector2(node_a.position.x - node_b.position.x, node_a.position.z - node_b.position.z)
			if delta.length() < min_spacing:
				_errors.append(path_a + " and " + path_b + " should stay at least " + str(min_spacing) + " m apart in XZ")


func _require_boundary_bands(boundary_root: Node) -> void:
	var left_count: int = 0
	var right_count: int = 0
	var back_count: int = 0
	for child in boundary_root.get_children():
		var node: Node3D = child as Node3D
		if node == null:
			continue
		var local_position: Vector3 = node.position
		var is_left_band: bool = local_position.x <= -BOUNDARY_EDGE_X
		var is_right_band: bool = local_position.x >= BOUNDARY_EDGE_X
		var is_back_band: bool = local_position.z <= BOUNDARY_BACK_Z
		if is_left_band:
			left_count += 1
		if is_right_band:
			right_count += 1
		if is_back_band:
			back_count += 1
		if not is_left_band and not is_right_band and not is_back_band:
			_errors.append("BoundaryVisuals/" + String(child.name) + " should sit on a left, right, or back boundary band, got " + str(local_position))
	if left_count != EXPECTED_BOUNDARY_LEFT_VISUALS:
		_errors.append("expected " + str(EXPECTED_BOUNDARY_LEFT_VISUALS) + " left boundary visuals, got " + str(left_count))
	if right_count != EXPECTED_BOUNDARY_RIGHT_VISUALS:
		_errors.append("expected " + str(EXPECTED_BOUNDARY_RIGHT_VISUALS) + " right boundary visuals, got " + str(right_count))
	if back_count != EXPECTED_BOUNDARY_BACK_VISUALS:
		_errors.append("expected " + str(EXPECTED_BOUNDARY_BACK_VISUALS) + " back boundary visuals, got " + str(back_count))


func _inspect_default_environment(world_environment: WorldEnvironment) -> void:
	var environment: Environment = world_environment.environment
	if environment == null:
		_errors.append("GoldenHourEnvironment has no Environment resource")
		return
	_require_environment_mood(
		environment,
		"dusk",
		GameConfig.dusk_background_color,
		GameConfig.dusk_ambient_color,
		GameConfig.dusk_ambient_energy,
		GameConfig.dusk_fog_density,
		GameConfig.dusk_fog_light_color
	)


func _inspect_default_sun(sun: DirectionalLight3D) -> void:
	if sun.light_color != GameConfig.dusk_sun_color:
		_errors.append("GoldenHourSun should start in dusk color")
	if absf(sun.light_energy - GameConfig.dusk_sun_energy) > FLOAT_EPSILON:
		_errors.append("GoldenHourSun should start in dusk energy")


func _inspect_camera_defaults(vehicle: Node, chase_camera: Camera3D, orbit_camera: Camera3D, fpv_camera: Camera3D) -> void:
	if vehicle == null or chase_camera == null or orbit_camera == null or fpv_camera == null:
		return
	var state: RefCounted = vehicle.call("get_state")
	var vehicle_position: Vector3 = state.get("position")
	if not chase_camera.current:
		_errors.append("ChaseCamera should be current by default")
	if orbit_camera.current:
		_errors.append("OrbitCamera should not be current by default")
	if fpv_camera.current:
		_errors.append("FpvCamera should not be current by default")
	if absf(chase_camera.fov - GameConfig.cam_fov_base) > FLOAT_EPSILON:
		_errors.append("ChaseCamera should start at base FOV")
	if absf(orbit_camera.fov - GameConfig.orbit_cam_fov) > FLOAT_EPSILON:
		_errors.append("OrbitCamera should start at orbit FOV")
	if absf(fpv_camera.fov - GameConfig.fpv_cam_fov) > FLOAT_EPSILON:
		_errors.append("FpvCamera should start at FPV FOV")
	if chase_camera.global_position.y <= vehicle_position.y:
		_errors.append("ChaseCamera should start above the vehicle")
	if chase_camera.global_position.z <= vehicle_position.z:
		_errors.append("ChaseCamera should start behind the trailhead spawn")
	_require_chase_camera_composition(state, chase_camera, "ChaseCamera")
	_require_orbit_camera_composition(state, orbit_camera, GameConfig.orbit_cam_start_yaw_deg, "OrbitCamera")
	_require_fpv_camera_composition(state, fpv_camera, "FpvCamera")


func _inspect_vehicle_visuals(host: Node, vehicle: Node) -> void:
	if host == null or vehicle == null:
		return
	var visual_root: Node = _require_node(vehicle, "PhysicsBody/VisualRoot")
	if visual_root == null:
		return
	_require_node(visual_root, "body")
	_require_node(visual_root, "nose")
	_require_node(visual_root, "roll_cage")
	_require_vehicle_chassis_drop(visual_root)
	_require_node_position(visual_root, "wheel_front_left", VEHICLE_FRONT_LEFT_WHEEL_SOCKET_POSITION, FLOAT_EPSILON)
	_require_node_position(visual_root, "wheel_front_right", Vector3(0.08, -0.015, -0.10), FLOAT_EPSILON)
	_require_node_position(visual_root, "wheel_rear_left", Vector3(-0.08, -0.015, 0.10), FLOAT_EPSILON)
	_require_node_position(visual_root, "wheel_rear_right", Vector3(0.08, -0.015, 0.10), FLOAT_EPSILON)
	_require_wheel_socket_mesh(visual_root, "wheel_front_left")
	_require_wheel_socket_mesh(visual_root, "wheel_front_right")
	_require_wheel_socket_mesh(visual_root, "wheel_rear_left")
	_require_wheel_socket_mesh(visual_root, "wheel_rear_right")
	var visual_collision_count: int = _count_collision_objects(visual_root)
	if visual_collision_count > 0:
		_errors.append("vehicle VisualRoot contains collision objects: " + str(visual_collision_count))
	var visual_mesh_count: int = _count_mesh_instances(visual_root)
	if visual_mesh_count < 9:
		_errors.append("vehicle VisualRoot should include chassis, roll cage, and wheel meshes")
	_require_vehicle_body_clearcoat(visual_root)
	_require_vehicle_steering_visuals(host, visual_root)
	_require_vehicle_residue_visuals(host, vehicle, visual_root)


func _require_vehicle_chassis_drop(visual_root: Node) -> void:
	var drop_offset: Vector3 = Vector3(0.0, GameConfig.vehicle_visual_chassis_drop, 0.0)
	_require_node_position(visual_root, "body", VEHICLE_BODY_BASE_POSITION - drop_offset, FLOAT_EPSILON)
	_require_node_position(visual_root, "nose", VEHICLE_NOSE_BASE_POSITION - drop_offset, FLOAT_EPSILON)
	var body: Node3D = _require_node(visual_root, "body") as Node3D
	var wheel_socket: Node3D = _require_node(visual_root, "wheel_front_left") as Node3D
	if body == null or wheel_socket == null:
		return
	var visual_gap: float = body.position.y - wheel_socket.position.y
	if visual_gap > GameConfig.vehicle_visual_chassis_wheel_socket_max_gap:
		_errors.append("vehicle visual chassis-to-wheel socket gap expected <= " + str(GameConfig.vehicle_visual_chassis_wheel_socket_max_gap) + ", got " + str(visual_gap))


func _require_vehicle_body_clearcoat(visual_root: Node) -> void:
	var clearcoat_material_count: int = _count_vehicle_body_clearcoat_materials(visual_root)
	if clearcoat_material_count == 0:
		_errors.append("vehicle body paint should include at least one clearcoat StandardMaterial3D")


func _count_vehicle_body_clearcoat_materials(parent: Node) -> int:
	var count: int = 0
	var mesh_instance: MeshInstance3D = parent as MeshInstance3D
	if mesh_instance != null and _is_vehicle_body_paint_node(String(mesh_instance.name)):
		count += _count_mesh_clearcoat_materials(mesh_instance)
	for child in parent.get_children():
		count += _count_vehicle_body_clearcoat_materials(child)
	return count


func _count_mesh_clearcoat_materials(mesh_instance: MeshInstance3D) -> int:
	var mesh: Mesh = mesh_instance.mesh
	if mesh == null:
		return 0
	var count: int = 0
	for surface_index in range(mesh.get_surface_count()):
		var material: StandardMaterial3D = mesh.surface_get_material(surface_index) as StandardMaterial3D
		if material == null:
			continue
		if not material.clearcoat_enabled:
			continue
		if absf(material.clearcoat - GameConfig.buggy_clearcoat) > FLOAT_EPSILON:
			continue
		if absf(material.clearcoat_roughness - GameConfig.buggy_clearcoat_roughness) > FLOAT_EPSILON:
			continue
		count += 1
	return count


func _is_vehicle_body_paint_node(node_name: String) -> bool:
	var lower_name: String = node_name.to_lower()
	return lower_name.contains("body") \
		or lower_name.contains("nose") \
		or lower_name.contains("side_panel") \
		or lower_name.contains("paint_stripe") \
		or lower_name.contains("fender_flare") \
		or lower_name.contains("side_number_plate")


func _require_vehicle_steering_visuals(host: Node, visual_root: Node) -> void:
	var vehicle_input: RefCounted = host.get("_vehicle_input") as RefCounted
	if vehicle_input == null:
		_errors.append("CedarHollowHost should expose vehicle input for visual wheel updates")
		return
	vehicle_input.set("steer", 1.0)
	host.call("_update_visual_wheels", GameConfig.FIXED_DT)
	var expected_steer: float = deg_to_rad(GameConfig.steer_limit_deg)
	_require_node_rotation_y(visual_root, "wheel_front_left", expected_steer, FLOAT_EPSILON)
	_require_node_rotation_y(visual_root, "wheel_front_right", expected_steer, FLOAT_EPSILON)
	_require_node_rotation_y(visual_root, "wheel_rear_left", 0.0, FLOAT_EPSILON)
	_require_node_rotation_y(visual_root, "wheel_rear_right", 0.0, FLOAT_EPSILON)
	vehicle_input.set("steer", 0.0)
	host.call("_update_visual_wheels", GameConfig.FIXED_DT)


func _require_vehicle_residue_visuals(host: Node, vehicle: Node, visual_root: Node) -> void:
	var state: RefCounted = vehicle.call("get_state")
	var contamination: RefCounted = state.get("contamination") as RefCounted
	if contamination == null:
		_errors.append("vehicle state should expose contamination")
		return
	contamination.call("set_values", 0.5, 0.25, 0.75)
	host.call("_update_vehicle_residue_visual", state)
	_require_residue_overlay_alpha(
		visual_root,
		RESIDUE_BODY_OVERLAY,
		0.5,
		0.25,
		0.75,
		GameConfig.vehicle_residue_mud_visual_alpha,
		GameConfig.vehicle_residue_dust_visual_alpha,
		GameConfig.vehicle_residue_wetness_visual_alpha,
		RESIDUE_MUD_BODY_MASK,
		RESIDUE_DUST_BODY_MASK,
		RESIDUE_WETNESS_BODY_MASK
	)
	_require_residue_overlay_visible(
		visual_root,
		RESIDUE_NOSE_OVERLAY,
		0.5,
		0.25,
		0.75,
		GameConfig.vehicle_residue_mud_visual_alpha,
		GameConfig.vehicle_residue_dust_visual_alpha,
		GameConfig.vehicle_residue_wetness_visual_alpha,
		RESIDUE_MUD_BODY_MASK,
		RESIDUE_DUST_BODY_MASK,
		RESIDUE_WETNESS_BODY_MASK
	)
	_require_tire_residue_overlays(visual_root)
	contamination.call("reset")
	host.call("_update_vehicle_residue_visual", state)
	_require_residue_overlay_hidden(visual_root, RESIDUE_BODY_OVERLAY)
	_require_residue_overlay_hidden(visual_root, RESIDUE_NOSE_OVERLAY)
	_require_tire_residue_overlays_hidden(visual_root)


func _require_tire_residue_overlays(visual_root: Node) -> void:
	for wheel_socket_name in WHEEL_SOCKET_NAMES:
		_require_tire_residue_overlay_visible(
			visual_root,
			wheel_socket_name,
			0.5,
			0.25,
			0.75,
			GameConfig.vehicle_residue_mud_visual_alpha * 0.82,
			GameConfig.vehicle_residue_dust_visual_alpha * 0.9,
			GameConfig.vehicle_residue_wetness_visual_alpha * 0.7,
			RESIDUE_MUD_TIRE_MASK,
			RESIDUE_DUST_TIRE_MASK,
			RESIDUE_WETNESS_TIRE_MASK
		)


func _require_tire_residue_overlays_hidden(visual_root: Node) -> void:
	for wheel_socket_name in WHEEL_SOCKET_NAMES:
		_require_tire_residue_overlay_hidden(visual_root, wheel_socket_name)


func _require_tire_residue_overlay_visible(visual_root: Node, wheel_socket_name: String, expected_mud_amount: float, expected_dust_amount: float, expected_wetness_amount: float, expected_mud_alpha_scale: float, expected_dust_alpha_scale: float, expected_wetness_alpha_scale: float, expected_mud_texture_path: String, expected_dust_texture_path: String, expected_wetness_texture_path: String) -> void:
	var socket: Node = _require_node(visual_root, wheel_socket_name)
	if socket == null:
		return
	var overlay: MeshInstance3D = _find_named_residue_overlay(socket, RESIDUE_TIRE_OVERLAY)
	if overlay == null:
		_errors.append(wheel_socket_name + " should contain " + RESIDUE_TIRE_OVERLAY)
		return
	_require_residue_overlay_instance_visible(overlay, wheel_socket_name.path_join(String(overlay.name)), expected_mud_amount, expected_dust_amount, expected_wetness_amount, expected_mud_alpha_scale, expected_dust_alpha_scale, expected_wetness_alpha_scale, expected_mud_texture_path, expected_dust_texture_path, expected_wetness_texture_path)


func _require_tire_residue_overlay_hidden(visual_root: Node, wheel_socket_name: String) -> void:
	var socket: Node = _require_node(visual_root, wheel_socket_name)
	if socket == null:
		return
	var overlay: MeshInstance3D = _find_named_residue_overlay(socket, RESIDUE_TIRE_OVERLAY)
	if overlay == null:
		_errors.append(wheel_socket_name + " should contain " + RESIDUE_TIRE_OVERLAY)
		return
	_require_residue_overlay_instance_hidden(overlay, wheel_socket_name.path_join(String(overlay.name)))


func _find_named_residue_overlay(parent: Node, overlay_name: String) -> MeshInstance3D:
	for index: int in range(parent.get_child_count()):
		var child: Node = parent.get_child(index)
		var overlay: MeshInstance3D = child as MeshInstance3D
		if overlay != null and String(overlay.name) == overlay_name:
			return overlay
		var nested: MeshInstance3D = _find_named_residue_overlay(child, overlay_name)
		if nested != null:
			return nested
	return null


func _require_residue_overlay_visible(parent: Node, path: String, expected_mud_amount: float, expected_dust_amount: float, expected_wetness_amount: float, expected_mud_alpha_scale: float, expected_dust_alpha_scale: float, expected_wetness_alpha_scale: float, expected_mud_texture_path: String, expected_dust_texture_path: String, expected_wetness_texture_path: String) -> void:
	var overlay: MeshInstance3D = _require_node(parent, path) as MeshInstance3D
	if overlay == null:
		return
	_require_residue_overlay_instance_visible(overlay, path, expected_mud_amount, expected_dust_amount, expected_wetness_amount, expected_mud_alpha_scale, expected_dust_alpha_scale, expected_wetness_alpha_scale, expected_mud_texture_path, expected_dust_texture_path, expected_wetness_texture_path)


func _require_residue_overlay_instance_visible(overlay: MeshInstance3D, path: String, expected_mud_amount: float, expected_dust_amount: float, expected_wetness_amount: float, expected_mud_alpha_scale: float, expected_dust_alpha_scale: float, expected_wetness_alpha_scale: float, expected_mud_texture_path: String, expected_dust_texture_path: String, expected_wetness_texture_path: String) -> void:
	if not overlay.visible:
		_errors.append(path + " should be visible when contamination is nonzero")
	var material: ShaderMaterial = _require_residue_material(overlay, path)
	if material == null:
		return
	_require_shader_float(material, "mud_amount", expected_mud_amount, path)
	_require_shader_float(material, "dust_amount", expected_dust_amount, path)
	_require_shader_float(material, "wetness_amount", expected_wetness_amount, path)
	_require_shader_float(material, "mud_alpha_scale", expected_mud_alpha_scale, path)
	_require_shader_float(material, "dust_alpha_scale", expected_dust_alpha_scale, path)
	_require_shader_float(material, "wetness_alpha_scale", expected_wetness_alpha_scale, path)
	_require_residue_texture(material, path, "mud_mask", expected_mud_texture_path)
	_require_residue_texture(material, path, "dust_mask", expected_dust_texture_path)
	_require_residue_texture(material, path, "wetness_mask", expected_wetness_texture_path)


func _require_residue_overlay_alpha(parent: Node, path: String, expected_mud_amount: float, expected_dust_amount: float, expected_wetness_amount: float, expected_mud_alpha_scale: float, expected_dust_alpha_scale: float, expected_wetness_alpha_scale: float, expected_mud_texture_path: String, expected_dust_texture_path: String, expected_wetness_texture_path: String) -> void:
	_require_residue_overlay_visible(parent, path, expected_mud_amount, expected_dust_amount, expected_wetness_amount, expected_mud_alpha_scale, expected_dust_alpha_scale, expected_wetness_alpha_scale, expected_mud_texture_path, expected_dust_texture_path, expected_wetness_texture_path)


func _require_residue_overlay_hidden(parent: Node, path: String) -> void:
	var overlay: MeshInstance3D = _require_node(parent, path) as MeshInstance3D
	if overlay == null:
		return
	_require_residue_overlay_instance_hidden(overlay, path)


func _require_residue_overlay_instance_hidden(overlay: MeshInstance3D, path: String) -> void:
	var material: ShaderMaterial = _require_residue_material(overlay, path)
	if material == null:
		return
	if overlay.visible:
		_errors.append(path + " should hide after contamination reset")
	_require_shader_float(material, "mud_amount", 0.0, path)
	_require_shader_float(material, "dust_amount", 0.0, path)
	_require_shader_float(material, "wetness_amount", 0.0, path)


func _require_residue_material(overlay: MeshInstance3D, path: String) -> ShaderMaterial:
	if overlay.mesh is BoxMesh:
		_errors.append(path + " should use a conformed duplicate source mesh, not BoxMesh")
	var material: ShaderMaterial = overlay.material_override as ShaderMaterial
	if material == null:
		_errors.append(path + " should use ShaderMaterial")
		return null
	if material.shader == null:
		_errors.append(path + " should have a residue shader")
	elif material.shader.resource_path != RESIDUE_SHADER_PATH:
		_errors.append(path + " shader expected " + RESIDUE_SHADER_PATH + ", got " + material.shader.resource_path)
	return material


func _require_residue_texture(material: ShaderMaterial, path: String, parameter_name: String, expected_texture_path: String) -> void:
	var texture: Texture2D = material.get_shader_parameter(parameter_name) as Texture2D
	if texture == null:
		_errors.append(path + " should set shader texture " + parameter_name)
		return
	if texture.resource_path != expected_texture_path:
		_errors.append(path + " " + parameter_name + " expected " + expected_texture_path + ", got " + texture.resource_path)


func _require_shader_float(material: ShaderMaterial, parameter_name: String, expected: float, label: String) -> void:
	var value: float = float(material.get_shader_parameter(parameter_name))
	if absf(value - expected) > FLOAT_EPSILON:
		_errors.append(label + " shader parameter " + parameter_name + " expected " + str(expected) + ", got " + str(value))


func _require_float_close(label: String, actual: float, expected: float, tolerance: float) -> void:
	if absf(actual - expected) > tolerance:
		_errors.append(label + " expected " + str(expected) + ", got " + str(actual))


func _require_float_in_range(label: String, actual: float, minimum_value: float, maximum_value: float) -> void:
	if actual < minimum_value or actual > maximum_value:
		_errors.append(label + " expected in [" + str(minimum_value) + ", " + str(maximum_value) + "], got " + str(actual))


func _require_color_close(label: String, actual: Color, expected: Color, tolerance: float) -> void:
	if absf(actual.r - expected.r) > tolerance or absf(actual.g - expected.g) > tolerance or absf(actual.b - expected.b) > tolerance or absf(actual.a - expected.a) > tolerance:
		_errors.append(label + " expected " + str(expected) + ", got " + str(actual))


func _inspect_render_camera_contract(host: Node, chase_camera: Camera3D, orbit_camera: Camera3D, fpv_camera: Camera3D, context: String) -> void:
	_inspect_tilt_shift_layer(host, context)
	_inspect_lighting_bar(host, context)
	_inspect_viewport_antialiasing(host, context)
	_inspect_project_scaling_settings(context)
	_inspect_fov_range(context)
	_require_camera_dof_disabled(chase_camera, context + " ChaseCamera")
	_require_camera_dof_disabled(orbit_camera, context + " OrbitCamera")
	_require_camera_dof_disabled(fpv_camera, context + " FpvCamera")


func _inspect_tilt_shift_layer(host: Node, context: String) -> void:
	if host == null:
		return
	var layer: CanvasLayer = _require_node(host, TILT_SHIFT_LAYER_NAME) as CanvasLayer
	if layer == null:
		return
	if layer.layer != TILT_SHIFT_LAYER_INDEX:
		_errors.append(context + " TiltShiftLayer layer expected " + str(TILT_SHIFT_LAYER_INDEX) + ", got " + str(layer.layer))
	if layer.visible != GameConfig.tilt_shift_enabled:
		_errors.append(context + " TiltShiftLayer visible state should follow GameConfig")
	var overlay: ColorRect = _require_node(layer, TILT_SHIFT_RECT_NAME) as ColorRect
	if overlay == null:
		return
	if absf(overlay.anchor_left) > FLOAT_EPSILON or absf(overlay.anchor_top) > FLOAT_EPSILON or absf(overlay.anchor_right - 1.0) > FLOAT_EPSILON or absf(overlay.anchor_bottom - 1.0) > FLOAT_EPSILON:
		_errors.append(context + " TiltShiftOverlay should be full-rect anchored")
	var material: ShaderMaterial = overlay.material as ShaderMaterial
	if material == null:
		_errors.append(context + " TiltShiftOverlay should use ShaderMaterial")
		return
	if material.shader == null:
		_errors.append(context + " TiltShiftOverlay should have a shader")
	elif material.shader.resource_path != TILT_SHIFT_SHADER_PATH:
		_errors.append(context + " TiltShiftOverlay shader expected " + TILT_SHIFT_SHADER_PATH + ", got " + material.shader.resource_path)
	_require_shader_float(material, "center", GameConfig.tilt_shift_band_center, context + " TiltShiftOverlay")
	_require_shader_float(material, "band", GameConfig.tilt_shift_focus_band, context + " TiltShiftOverlay")
	_require_shader_float(material, "blur", GameConfig.tilt_shift_blur_amount, context + " TiltShiftOverlay")


func _inspect_lighting_bar(host: Node, context: String) -> void:
	if host == null:
		return
	var sun: DirectionalLight3D = _require_node(host, "GoldenHourSun") as DirectionalLight3D
	if sun != null:
		_require_lighting_bar_sun(sun, context)
	var world_environment: WorldEnvironment = _require_node(host, "GoldenHourEnvironment") as WorldEnvironment
	if world_environment != null:
		_require_lighting_bar_environment(world_environment, context)
	_require_lighting_bar_contact_fill(host, context)


func _require_lighting_bar_sun(sun: DirectionalLight3D, context: String) -> void:
	if not sun.shadow_enabled:
		_errors.append(context + " GoldenHourSun should enable shadows")
	_require_float_in_range(context + " GoldenHourSun dusk energy", sun.light_energy, DUSK_SUN_ENERGY_MIN, DUSK_SUN_ENERGY_MAX)
	_require_float_close(context + " GoldenHourSun dusk energy", sun.light_energy, GameConfig.dusk_sun_energy, LIGHTING_BAR_TOLERANCE)
	if sun.light_color != GameConfig.dusk_sun_color:
		_errors.append(context + " GoldenHourSun dusk color should follow GameConfig")
	if sun.rotation_degrees.distance_to(GameConfig.dusk_sun_rotation_degrees) > LIGHTING_BAR_TOLERANCE:
		_errors.append(context + " GoldenHourSun dusk rotation expected " + str(GameConfig.dusk_sun_rotation_degrees) + ", got " + str(sun.rotation_degrees))
	_require_float_close(context + " GoldenHourSun angular distance", sun.light_angular_distance, GameConfig.atmosphere_pcss_sun_angular_distance, LIGHTING_BAR_TOLERANCE)
	_require_float_close(context + " GoldenHourSun shadow blur", sun.shadow_blur, GameConfig.atmosphere_pcss_shadow_blur, LIGHTING_BAR_TOLERANCE)
	_require_float_close(context + " GoldenHourSun shadow opacity", sun.shadow_opacity, GameConfig.atmosphere_pcss_shadow_opacity, LIGHTING_BAR_TOLERANCE)
	_require_float_close(context + " GoldenHourSun shadow max distance", sun.directional_shadow_max_distance, GameConfig.atmosphere_pcss_shadow_max_distance, LIGHTING_BAR_TOLERANCE)
	_require_float_close(context + " GoldenHourSun volumetric fog energy", sun.light_volumetric_fog_energy, DUSK_SUN_VOLUMETRIC_FOG_ENERGY, LIGHTING_BAR_TOLERANCE)


func _require_lighting_bar_environment(world_environment: WorldEnvironment, context: String) -> void:
	var environment: Environment = world_environment.environment
	if environment == null:
		_errors.append(context + " GoldenHourEnvironment has no Environment resource for lighting bar")
		return
	if not environment.fog_enabled:
		_errors.append(context + " GoldenHourEnvironment should enable fog")
	if environment.volumetric_fog_enabled != GameConfig.atmosphere_volumetric_fog_enabled:
		_errors.append(context + " GoldenHourEnvironment volumetric fog should follow GameConfig")
	_require_float_close(context + " GoldenHourEnvironment volumetric fog density", environment.volumetric_fog_density, maxf(GameConfig.atmosphere_volumetric_fog_density, VOLUMETRIC_FOG_DENSITY_FLOOR), LIGHTING_BAR_TOLERANCE)
	if not environment.glow_enabled:
		_errors.append(context + " GoldenHourEnvironment should enable glow")
	if not environment.glow_normalized:
		_errors.append(context + " GoldenHourEnvironment glow should be normalized")
	_require_float_close(context + " GoldenHourEnvironment dusk glow intensity", environment.glow_intensity, DUSK_GLOW_INTENSITY, LIGHTING_BAR_TOLERANCE)
	_require_float_close(context + " GoldenHourEnvironment dusk glow strength", environment.glow_strength, DUSK_GLOW_STRENGTH, LIGHTING_BAR_TOLERANCE)
	_require_float_close(context + " GoldenHourEnvironment glow bloom", environment.glow_bloom, DUSK_GLOW_BLOOM, LIGHTING_BAR_TOLERANCE)
	if environment.tonemap_mode != Environment.TONE_MAPPER_AGX:
		_errors.append(context + " GoldenHourEnvironment tonemap_mode expected AGX, got " + str(environment.tonemap_mode))
	if environment.adjustment_enabled != GameConfig.atmosphere_grade_enabled:
		_errors.append(context + " GoldenHourEnvironment color grade enabled should follow GameConfig")
	_require_float_in_range(context + " GoldenHourEnvironment grade saturation", environment.adjustment_saturation, GRADE_SATURATION_MIN, GRADE_SATURATION_MAX)
	_require_float_close(context + " GoldenHourEnvironment grade saturation", environment.adjustment_saturation, GameConfig.atmosphere_grade_saturation, LIGHTING_BAR_TOLERANCE)
	_require_float_in_range(context + " GoldenHourEnvironment grade contrast", environment.adjustment_contrast, GRADE_CONTRAST_MIN, GRADE_CONTRAST_MAX)
	_require_float_close(context + " GoldenHourEnvironment grade contrast", environment.adjustment_contrast, GameConfig.atmosphere_grade_contrast, LIGHTING_BAR_TOLERANCE)
	_require_float_close(context + " GoldenHourEnvironment grade brightness", environment.adjustment_brightness, GameConfig.atmosphere_grade_brightness, LIGHTING_BAR_TOLERANCE)
	if environment.ssao_enabled != GameConfig.atmosphere_ssao_enabled:
		_errors.append(context + " GoldenHourEnvironment SSAO enabled should follow GameConfig")
	_require_float_close(context + " GoldenHourEnvironment SSAO radius", environment.ssao_radius, GameConfig.atmosphere_ssao_radius, LIGHTING_BAR_TOLERANCE)
	_require_float_close(context + " GoldenHourEnvironment SSAO intensity", environment.ssao_intensity, GameConfig.atmosphere_ssao_intensity, LIGHTING_BAR_TOLERANCE)
	_require_float_close(context + " GoldenHourEnvironment SSAO light affect", environment.ssao_light_affect, GameConfig.atmosphere_ssao_light_affect, LIGHTING_BAR_TOLERANCE)
	if environment.ssil_enabled != GameConfig.atmosphere_ssil_enabled:
		_errors.append(context + " GoldenHourEnvironment SSIL enabled should follow GameConfig")
	_require_float_close(context + " GoldenHourEnvironment SSIL radius", environment.ssil_radius, GameConfig.atmosphere_ssil_radius, LIGHTING_BAR_TOLERANCE)
	_require_float_close(context + " GoldenHourEnvironment SSIL intensity", environment.ssil_intensity, GameConfig.atmosphere_ssil_intensity, LIGHTING_BAR_TOLERANCE)
	_require_float_close(context + " GoldenHourEnvironment SSIL sharpness", environment.ssil_sharpness, GameConfig.atmosphere_ssil_sharpness, LIGHTING_BAR_TOLERANCE)
	if environment.sdfgi_enabled:
		_errors.append(context + " GoldenHourEnvironment should keep SDFGI disabled")


func _require_lighting_bar_contact_fill(host: Node, context: String) -> void:
	var body_node: Node = _require_node(host, "Vehicle/PhysicsBody")
	var body: PhysicsBody3D = body_node as PhysicsBody3D
	if body_node != null and body == null:
		_errors.append(context + " Vehicle/PhysicsBody should be a PhysicsBody3D")
		return
	if body == null:
		return
	var light: OmniLight3D = _require_node(body, "VehicleContactFillLight") as OmniLight3D
	if light == null:
		return
	if light.shadow_enabled:
		_errors.append(context + " VehicleContactFillLight should not cast shadows")
	_require_float_close(context + " VehicleContactFillLight energy", light.light_energy, GameConfig.contact_fill_light_energy, LIGHTING_BAR_TOLERANCE)
	_require_float_close(context + " VehicleContactFillLight range", light.omni_range, GameConfig.contact_fill_light_range, LIGHTING_BAR_TOLERANCE)
	_require_color_close(context + " VehicleContactFillLight color", light.light_color, GameConfig.contact_fill_light_color, LIGHTING_BAR_COLOR_TOLERANCE)
	var expected_position: Vector3 = Vector3(0.0, -maxf(GameConfig.contact_fill_light_height, 0.0), 0.0)
	if light.position.distance_to(expected_position) > LIGHTING_BAR_TOLERANCE:
		_errors.append(context + " VehicleContactFillLight position expected " + str(expected_position) + ", got " + str(light.position))


func _inspect_viewport_antialiasing(host: Node, context: String) -> void:
	if host == null:
		return
	var viewport: Viewport = host.get_viewport()
	if viewport == null:
		_errors.append(context + " host should have a viewport")
		return
	if viewport.msaa_3d != Viewport.MSAA_2X:
		_errors.append(context + " viewport msaa_3d expected MSAA_2X, got " + str(viewport.msaa_3d))
	if not viewport.use_taa:
		_errors.append(context + " viewport should keep TAA enabled")


func _inspect_project_scaling_settings(context: String) -> void:
	var mode_value: int = int(ProjectSettings.get_setting("rendering/scaling_3d/mode", -1))
	var scale_value: float = float(ProjectSettings.get_setting("rendering/scaling_3d/scale", 0.0))
	var sharpness_value: float = float(ProjectSettings.get_setting("rendering/scaling_3d/fsr_sharpness", -1.0))
	if mode_value != 2:
		_errors.append(context + " project scaling_3d/mode expected 2, got " + str(mode_value))
	if absf(scale_value - 0.99) > FLOAT_EPSILON:
		_errors.append(context + " project scaling_3d/scale expected 0.99, got " + str(scale_value))
	if absf(sharpness_value - 0.1) > FLOAT_EPSILON:
		_errors.append(context + " project scaling_3d/fsr_sharpness expected 0.1, got " + str(sharpness_value))


func _inspect_fov_range(context: String) -> void:
	var rest_fov: float = GameConfig.get_fov_for_speed(0.0)
	var max_fov: float = GameConfig.get_fov_for_speed(GameConfig.max_speed)
	if absf(rest_fov - EXPECTED_FOV_MIN) > FLOAT_EPSILON:
		_errors.append(context + " FOV at rest expected " + str(EXPECTED_FOV_MIN) + ", got " + str(rest_fov))
	if absf(max_fov - EXPECTED_FOV_MAX) > FLOAT_EPSILON:
		_errors.append(context + " FOV at max speed expected " + str(EXPECTED_FOV_MAX) + ", got " + str(max_fov))


func _require_camera_dof_disabled(camera: Camera3D, label: String) -> void:
	if camera == null:
		return
	var existing_attributes: CameraAttributes = camera.attributes
	if existing_attributes != null and not (existing_attributes is CameraAttributesPractical):
		_errors.append(label + " should use CameraAttributesPractical when attributes are present")
		return
	var attributes: CameraAttributesPractical = existing_attributes as CameraAttributesPractical
	if attributes == null:
		_errors.append(label + " should have atmosphere-owned practical attributes")
		return
	if attributes.dof_blur_near_enabled:
		_errors.append(label + " should not enable near DOF blur")
	if attributes.dof_blur_far_enabled:
		_errors.append(label + " should not enable far DOF blur")
	if attributes.auto_exposure_enabled != GameConfig.atmosphere_auto_exposure_enabled:
		_errors.append(label + " auto exposure should follow GameConfig")


func _require_wheel_socket_mesh(parent: Node, path: String) -> void:
	var socket: Node = _require_node(parent, path)
	if socket == null:
		return
	for child in socket.get_children():
		if child is MeshInstance3D:
			return
	_errors.append(path + " should contain a wheel mesh")


func _require_node_rotation_y(parent: Node, path: String, expected: float, tolerance: float) -> void:
	var node: Node3D = _require_node(parent, path) as Node3D
	if node == null:
		return
	if absf(node.rotation.y - expected) > tolerance:
		_errors.append(path + " rotation.y expected " + str(expected) + ", got " + str(node.rotation.y))


func _inspect_camera_reactivity(host: Node, vehicle: Node, chase_camera: Camera3D, orbit_camera: Camera3D, fpv_camera: Camera3D) -> void:
	if host == null or vehicle == null or chase_camera == null or orbit_camera == null or fpv_camera == null:
		return
	var live_state: RefCounted = vehicle.call("get_state")
	var live_position: Vector3 = live_state.get("position")
	var test_position: Vector3 = live_position + Vector3(0.0, 0.0, -1.0)
	var test_state: RefCounted = VehicleStateScript.new()
	test_state.set("position", test_position)
	test_state.set("basis", Basis.IDENTITY)
	test_state.set("linear_velocity", Vector3(0.0, 0.0, -GameConfig.max_speed))

	var chase_position_before: Vector3 = chase_camera.global_position
	host.call("_update_chase_camera", GameConfig.FIXED_DT, test_state)
	var expected_chase_fov: float = GameConfig.get_fov_for_speed(GameConfig.max_speed)
	if absf(chase_camera.fov - expected_chase_fov) > FLOAT_EPSILON:
		_errors.append("ChaseCamera FOV should widen at max speed")
	if chase_camera.global_position.distance_to(chase_position_before) <= FLOAT_EPSILON:
		_errors.append("ChaseCamera should move toward a changed vehicle state")
	_require_camera_pitch(chase_camera, "ChaseCamera reactive update", CAMERA_REACTIVE_PITCH_TOLERANCE_DEG)

	host.call("cycle_camera_mode")
	var orbit_position_before: Vector3 = orbit_camera.global_position
	host.set("_orbit_camera_initialized", false)
	host.set("_orbit_yaw_degrees", GameConfig.orbit_cam_start_yaw_deg)
	host.call("_update_orbit_camera", GameConfig.FIXED_DT, test_state)
	var expected_orbit_yaw: float = float(host.get("_orbit_yaw_degrees"))
	if orbit_camera.global_position.distance_to(orbit_position_before) <= FLOAT_EPSILON:
		_errors.append("OrbitCamera should move while orbit mode is active")
	if absf(orbit_camera.fov - GameConfig.orbit_cam_fov) > FLOAT_EPSILON:
		_errors.append("OrbitCamera should keep orbit FOV during reactive update")
	_require_orbit_camera_composition(test_state, orbit_camera, expected_orbit_yaw, "OrbitCamera reactive update")

	host.call("_update_fpv_camera", test_state)
	if absf(fpv_camera.fov - GameConfig.fpv_cam_fov) > FLOAT_EPSILON:
		_errors.append("FpvCamera should keep FPV FOV during reactive update")
	_require_fpv_camera_composition(test_state, fpv_camera, "FpvCamera reactive update")

	host.call("cycle_camera_mode")
	host.call("cycle_camera_mode")


func _require_chase_camera_composition(state: RefCounted, chase_camera: Camera3D, context: String) -> void:
	var vehicle_position: Vector3 = state.get("position")
	var vehicle_basis: Basis = state.get("basis")
	var back: Vector3 = vehicle_basis.z.normalized()
	var expected_position: Vector3 = vehicle_position + back * GameConfig.cam_distance + Vector3.UP * GameConfig.cam_height
	if chase_camera.global_position.distance_to(expected_position) > CAMERA_COMPOSITION_TOLERANCE:
		_errors.append(context + " initial position expected " + str(expected_position) + ", got " + str(chase_camera.global_position))
	var offset: Vector3 = chase_camera.global_position - vehicle_position
	var expected_offset_xz: Vector2 = Vector2(back.x, back.z) * GameConfig.cam_distance
	var actual_offset_xz: Vector2 = Vector2(offset.x, offset.z)
	if actual_offset_xz.distance_to(expected_offset_xz) > CAMERA_COMPOSITION_TOLERANCE:
		_errors.append(context + " rear offset expected " + str(expected_offset_xz) + ", got " + str(actual_offset_xz))
	if absf(offset.y - GameConfig.cam_height) > CAMERA_COMPOSITION_TOLERANCE:
		_errors.append(context + " height offset expected " + str(GameConfig.cam_height) + ", got " + str(offset.y))
	_require_camera_pitch(chase_camera, context)


func _require_camera_pitch(camera: Camera3D, context: String, tolerance_degrees: float = CAMERA_PITCH_TOLERANCE_DEG) -> void:
	var forward: Vector3 = -camera.global_transform.basis.z.normalized()
	var pitch_degrees: float = rad_to_deg(asin(clampf(forward.y, -1.0, 1.0)))
	if absf(pitch_degrees - GameConfig.cam_pitch_deg) > tolerance_degrees:
		_errors.append(context + " pitch expected " + str(GameConfig.cam_pitch_deg) + ", got " + str(pitch_degrees))


func _require_orbit_camera_composition(state: RefCounted, orbit_camera: Camera3D, yaw_degrees: float, context: String) -> void:
	var vehicle_position: Vector3 = state.get("position")
	var offset: Vector3 = orbit_camera.global_position - vehicle_position
	var actual_offset_xz: Vector2 = Vector2(offset.x, offset.z)
	var yaw_radians: float = deg_to_rad(yaw_degrees)
	var expected_offset_xz: Vector2 = Vector2(sin(yaw_radians), cos(yaw_radians)) * GameConfig.orbit_cam_distance
	if actual_offset_xz.distance_to(expected_offset_xz) > CAMERA_COMPOSITION_TOLERANCE:
		_errors.append(context + " horizontal orbit offset expected " + str(expected_offset_xz) + ", got " + str(actual_offset_xz))
	if absf(offset.y - GameConfig.orbit_cam_height) > CAMERA_COMPOSITION_TOLERANCE:
		_errors.append(context + " height offset expected " + str(GameConfig.orbit_cam_height) + ", got " + str(offset.y))
	var look_target: Vector3 = vehicle_position + Vector3.UP * GameConfig.orbit_cam_look_height
	_require_camera_look_target(orbit_camera, look_target, context)


func _require_fpv_camera_composition(state: RefCounted, fpv_camera: Camera3D, context: String) -> void:
	var vehicle_position: Vector3 = state.get("position")
	var vehicle_basis: Basis = state.get("basis")
	var forward: Vector3 = -vehicle_basis.z.normalized()
	var up: Vector3 = vehicle_basis.y.normalized()
	var expected_position: Vector3 = vehicle_position + forward * GameConfig.fpv_cam_forward + up * GameConfig.fpv_cam_height
	if fpv_camera.global_position.distance_to(expected_position) > FEATURE_TRANSFORM_TOLERANCE:
		_errors.append(context + " position expected " + str(expected_position) + ", got " + str(fpv_camera.global_position))
	var look_target: Vector3 = vehicle_position + forward * GameConfig.fpv_cam_look_ahead + up * GameConfig.fpv_cam_look_height
	_require_camera_look_target(fpv_camera, look_target, context)


func _require_camera_look_target(camera: Camera3D, target: Vector3, context: String) -> void:
	var expected_forward: Vector3 = (target - camera.global_position).normalized()
	var actual_forward: Vector3 = -camera.global_transform.basis.z.normalized()
	if actual_forward.distance_to(expected_forward) > CAMERA_LOOK_TOLERANCE:
		_errors.append(context + " forward vector should look at " + str(target))


func _inspect_chase_camera_prop_clearance(prop_root: Node, chase_camera: Camera3D) -> void:
	if chase_camera == null:
		return
	for child in prop_root.get_children():
		var node: Node3D = child as Node3D
		if node == null:
			continue
		var accumulator: BoundsAccumulator = BoundsAccumulator.new()
		_collect_mesh_bounds(node, accumulator)
		if not accumulator.has_bounds:
			continue
		if _point_inside_bounds(chase_camera.global_position, accumulator, CAMERA_PROP_CLEARANCE_MARGIN):
			_errors.append("ChaseCamera starts inside PropVisuals/" + String(child.name) + " bounds")


func _inspect_camera_space_readability(chase_camera: Camera3D, prop_root: Node, scatter_root: Node) -> void:
	var original_transform: Transform3D = chase_camera.global_transform
	var original_fov: float = chase_camera.fov
	_inspect_chase_readability_shot(chase_camera, prop_root, scatter_root, "trailhead", Vector3(0.0, 0.12, 0.75), 0.0, PackedStringArray())
	_inspect_chase_readability_shot(chase_camera, prop_root, scatter_root, "meadow", Vector3(1.45, 0.12, -2.8), 205.0, PackedStringArray())
	_inspect_chase_readability_shot(chase_camera, prop_root, scatter_root, "bog_bottom", Vector3(2.85, 0.12, -5.3), 30.0, PackedStringArray())
	_inspect_chase_readability_shot(chase_camera, prop_root, scatter_root, "crossing", Vector3(4.25, 0.12, -6.55), -70.0, PackedStringArray())
	_inspect_chase_readability_shot(chase_camera, prop_root, scatter_root, "boardwalk", Vector3(3.25, 0.12, -4.15), 180.0, PackedStringArray())
	_inspect_chase_readability_shot(chase_camera, prop_root, scatter_root, "old_cedar", Vector3(0.0, 0.12, -3.55), 0.0, PackedStringArray(["old_cedar_stump"]))
	chase_camera.global_transform = original_transform
	chase_camera.fov = original_fov


func _inspect_chase_readability_shot(chase_camera: Camera3D, prop_root: Node, scatter_root: Node, shot_name: String, vehicle_position: Vector3, yaw_degrees: float, focal_prop_names: PackedStringArray) -> void:
	_position_chase_camera_for_readability(chase_camera, vehicle_position, yaw_degrees)
	_require_readability_root(chase_camera, prop_root, shot_name, "PropVisuals", focal_prop_names)
	_require_readability_root(chase_camera, scatter_root, shot_name, "ScatterVisuals", PackedStringArray())


func _position_chase_camera_for_readability(chase_camera: Camera3D, vehicle_position: Vector3, yaw_degrees: float) -> void:
	var vehicle_basis: Basis = Basis(Vector3.UP, deg_to_rad(yaw_degrees))
	var back: Vector3 = vehicle_basis.z.normalized()
	var forward: Vector3 = -vehicle_basis.z.normalized()
	chase_camera.global_position = vehicle_position + back * GameConfig.cam_distance + Vector3.UP * GameConfig.cam_height
	var target: Vector3 = vehicle_position + forward * GameConfig.cam_look_ahead
	var flat_delta: Vector3 = Vector3(target.x - chase_camera.global_position.x, 0.0, target.z - chase_camera.global_position.z)
	var horizontal_distance: float = maxf(flat_delta.length(), 0.001)
	target.y = chase_camera.global_position.y + tan(deg_to_rad(GameConfig.cam_pitch_deg)) * horizontal_distance
	chase_camera.look_at(target, Vector3.UP)
	chase_camera.fov = GameConfig.cam_fov_base


func _require_readability_root(chase_camera: Camera3D, root: Node, shot_name: String, root_label: String, focal_names: PackedStringArray) -> void:
	for child in root.get_children():
		var node: Node3D = child as Node3D
		if node == null:
			continue
		var accumulator: BoundsAccumulator = BoundsAccumulator.new()
		_collect_mesh_bounds(node, accumulator)
		if not accumulator.has_bounds:
			continue
		var screen_rect: Rect2 = _project_bounds_to_screen_rect(chase_camera, accumulator)
		if screen_rect.size.x <= 0.0 or screen_rect.size.y <= 0.0:
			continue
		var child_name: String = String(child.name)
		var screen_area: float = _rect_area(screen_rect)
		if focal_names.has(child_name):
			if screen_area > READABILITY_MAX_FOCAL_SCREEN_AREA:
				_errors.append(shot_name + " " + root_label + "/" + child_name + " dominates screen area: " + str(screen_area))
			continue
		if screen_area > READABILITY_MAX_DECOR_SCREEN_AREA:
			_errors.append(shot_name + " " + root_label + "/" + child_name + " dominates screen area: " + str(screen_area))
		if screen_rect.intersects(READABILITY_CENTER_CLEAR_RECT):
			var overlap: Rect2 = screen_rect.intersection(READABILITY_CENTER_CLEAR_RECT)
			var overlap_area: float = _rect_area(overlap)
			if overlap_area > READABILITY_MAX_DECOR_CENTER_OVERLAP:
				_errors.append(shot_name + " " + root_label + "/" + child_name + " blocks central chase readability area: " + str(overlap_area))


func _project_bounds_to_screen_rect(chase_camera: Camera3D, accumulator: BoundsAccumulator) -> Rect2:
	var viewport_size_i: Vector2i = get_viewport().get_visible_rect().size
	if viewport_size_i.x <= 0 or viewport_size_i.y <= 0:
		_errors.append("cannot inspect camera-space readability with empty viewport")
		return Rect2()
	var viewport_size: Vector2 = Vector2(float(viewport_size_i.x), float(viewport_size_i.y))
	var has_point: bool = false
	var min_point: Vector2 = Vector2.ZERO
	var max_point: Vector2 = Vector2.ZERO
	for x_index in range(2):
		for y_index in range(2):
			for z_index in range(2):
				var world_point: Vector3 = Vector3(
					accumulator.bounds_min.x if x_index == 0 else accumulator.bounds_max.x,
					accumulator.bounds_min.y if y_index == 0 else accumulator.bounds_max.y,
					accumulator.bounds_min.z if z_index == 0 else accumulator.bounds_max.z
				)
				if chase_camera.is_position_behind(world_point):
					continue
				var screen_point: Vector2 = chase_camera.unproject_position(world_point)
				var normalized_point: Vector2 = Vector2(screen_point.x / viewport_size.x, screen_point.y / viewport_size.y)
				if not has_point:
					has_point = true
					min_point = normalized_point
					max_point = normalized_point
				else:
					min_point = Vector2(minf(min_point.x, normalized_point.x), minf(min_point.y, normalized_point.y))
					max_point = Vector2(maxf(max_point.x, normalized_point.x), maxf(max_point.y, normalized_point.y))
	if not has_point:
		return Rect2()
	return _clamp_screen_rect(Rect2(min_point, max_point - min_point))


func _clamp_screen_rect(rect: Rect2) -> Rect2:
	var min_point: Vector2 = Vector2(clampf(rect.position.x, 0.0, 1.0), clampf(rect.position.y, 0.0, 1.0))
	var rect_end: Vector2 = rect.position + rect.size
	var max_point: Vector2 = Vector2(clampf(rect_end.x, 0.0, 1.0), clampf(rect_end.y, 0.0, 1.0))
	var size: Vector2 = Vector2(maxf(max_point.x - min_point.x, 0.0), maxf(max_point.y - min_point.y, 0.0))
	return Rect2(min_point, size)


func _rect_area(rect: Rect2) -> float:
	return maxf(rect.size.x, 0.0) * maxf(rect.size.y, 0.0)


func _point_inside_bounds(point: Vector3, accumulator: BoundsAccumulator, margin: float) -> bool:
	return (
		point.x >= accumulator.bounds_min.x - margin
		and point.x <= accumulator.bounds_max.x + margin
		and point.y >= accumulator.bounds_min.y - margin
		and point.y <= accumulator.bounds_max.y + margin
		and point.z >= accumulator.bounds_min.z - margin
		and point.z <= accumulator.bounds_max.z + margin
	)


func _inspect_input_map() -> void:
	_require_input_action_keys(&"throttle", [KEY_W, KEY_UP])
	_require_input_action_keys(&"brake", [KEY_S, KEY_DOWN])
	_require_input_action_keys(&"reverse", [KEY_S, KEY_DOWN])
	_require_input_action_keys(&"steer_left", [KEY_A, KEY_LEFT])
	_require_input_action_keys(&"steer_right", [KEY_D, KEY_RIGHT])
	_require_input_action_keys(&"ebrake", [KEY_SPACE])
	_require_input_action_keys(&"self_right", [KEY_R])
	_require_input_action_keys(&"cam_toggle", [KEY_C])
	_require_input_action_keys(&"map_toggle", [KEY_M])
	_require_input_action_keys(&"mood_toggle", [KEY_N])
	_require_input_action_keys(&"logbook_open", [KEY_TAB])
	_require_input_action_keys(&"photograph", [KEY_F])


func _require_input_action_keys(action_name: StringName, expected_keycodes: Array[int]) -> void:
	var action_string: String = String(action_name)
	if not InputMap.has_action(action_string):
		_errors.append("InputMap missing action: " + action_string)
		return
	var observed_keycodes: Array[int] = []
	for event in InputMap.action_get_events(action_string):
		var key_event: InputEventKey = event as InputEventKey
		if key_event != null:
			if key_event.physical_keycode != 0:
				observed_keycodes.append(key_event.physical_keycode)
			if key_event.keycode != 0:
				observed_keycodes.append(key_event.keycode)
	for keycode in expected_keycodes:
		if not observed_keycodes.has(keycode):
			_errors.append("InputMap action " + action_string + " missing keycode " + str(keycode))


func _inspect_reverse_input_output(host: Node, context: String) -> void:
	if host == null:
		return
	var vehicle_input: RefCounted = host.get("_vehicle_input") as RefCounted
	if vehicle_input == null:
		_errors.append(context + " should expose vehicle input for reverse inspection")
		return
	Input.action_press(&"brake", 1.0)
	Input.action_press(&"reverse", 1.0)
	host.call("_update_vehicle_input")
	var reverse_throttle: float = float(vehicle_input.get("throttle"))
	var reverse_brake: float = float(vehicle_input.get("brake"))
	Input.action_release(&"reverse")
	Input.action_release(&"brake")
	if reverse_throttle >= -0.99:
		_errors.append(context + " reverse action should produce negative throttle, got " + str(reverse_throttle))
	if reverse_brake > FLOAT_EPSILON:
		_errors.append(context + " should not apply brake damping during pure reverse, got " + str(reverse_brake))
	Input.action_press(&"throttle", 1.0)
	Input.action_press(&"brake", 1.0)
	Input.action_press(&"reverse", 1.0)
	host.call("_update_vehicle_input")
	var opposed_throttle: float = float(vehicle_input.get("throttle"))
	var opposed_brake: float = float(vehicle_input.get("brake"))
	Input.action_release(&"reverse")
	Input.action_release(&"brake")
	Input.action_release(&"throttle")
	if absf(opposed_throttle) > FLOAT_EPSILON:
		_errors.append(context + " opposed forward/reverse should neutralize throttle, got " + str(opposed_throttle))
	if opposed_brake < 0.99:
		_errors.append(context + " opposed forward/reverse should apply brake, got " + str(opposed_brake))


func _inspect_hud_defaults(hud: Node) -> void:
	if hud.visible:
		_errors.append("LandmarkHintHud should be hidden by default")
	var minimap: Control = _require_node(hud, "MinimapView") as Control
	if minimap == null:
		return
	var expected_position: Vector2 = Vector2(GameConfig.minimap_margin, GameConfig.minimap_margin)
	var expected_size: Vector2 = Vector2(GameConfig.minimap_size, GameConfig.minimap_size)
	if minimap.position.distance_to(expected_position) > FLOAT_EPSILON:
		_errors.append("MinimapView position expected " + str(expected_position) + ", got " + str(minimap.position))
	if minimap.size.distance_to(expected_size) > FLOAT_EPSILON:
		_errors.append("MinimapView size expected " + str(expected_size) + ", got " + str(minimap.size))
	_inspect_minimap_route_content(minimap)


func _inspect_minimap_route_content(minimap: Control) -> void:
	var bounds_min: Vector3 = CedarRoute.get("bounds_min")
	var bounds_max: Vector3 = CedarRoute.get("bounds_max")
	var map_min: float = GameConfig.minimap_inner_padding
	var map_max: float = GameConfig.minimap_size - GameConfig.minimap_inner_padding
	var mapped_min: Vector2 = minimap.call("_world_to_map", bounds_min)
	var mapped_max: Vector2 = minimap.call("_world_to_map", bounds_max)
	if mapped_min.distance_to(Vector2(map_min, map_max)) > FLOAT_EPSILON:
		_errors.append("MinimapView should map route bounds_min to lower-left padded corner")
	if mapped_max.distance_to(Vector2(map_max, map_min)) > FLOAT_EPSILON:
		_errors.append("MinimapView should map route bounds_max to upper-right padded corner")
	var nearest_index: int = int(minimap.call("_nearest_landmark_index"))
	if nearest_index != 0:
		_errors.append("MinimapView should start nearest to trailhead landmark, got index " + str(nearest_index))
	_require_minimap_segment_points(minimap, &"trailhead_to_culvert_mouth", 3)
	_require_minimap_segment_points(minimap, &"overlook_to_old_cedar", 2)


func _require_minimap_segment_points(minimap: Control, segment_id: StringName, expected_count: int) -> void:
	var points: Array[Vector2] = minimap.call("_map_points_for_segment", segment_id)
	if points.size() != expected_count:
		_errors.append("MinimapView segment " + String(segment_id) + " expected " + str(expected_count) + " map points, got " + str(points.size()))
	for point_value in points:
		var point: Vector2 = point_value
		if point.x < 0.0 or point.y < 0.0 or point.x > minimap.size.x or point.y > minimap.size.y:
			_errors.append("MinimapView segment " + String(segment_id) + " point outside minimap bounds: " + str(point))


func _inspect_render_toggles(host: Node, chase_camera: Camera3D, orbit_camera: Camera3D, fpv_camera: Camera3D, world_environment: WorldEnvironment, sun: DirectionalLight3D, hud: Node) -> void:
	if host == null:
		return
	if chase_camera != null and orbit_camera != null and fpv_camera != null:
		host.call("cycle_camera_mode")
		_require_current_camera("orbit toggle", chase_camera, orbit_camera, fpv_camera, orbit_camera)
		host.call("cycle_camera_mode")
		_require_current_camera("fpv toggle", chase_camera, orbit_camera, fpv_camera, fpv_camera)
		host.call("cycle_camera_mode")
		_require_current_camera("chase toggle", chase_camera, orbit_camera, fpv_camera, chase_camera)
	if hud != null:
		host.call("toggle_landmark_hint_hud")
		if not hud.visible:
			_errors.append("LandmarkHintHud should become visible after toggle")
		host.call("toggle_landmark_hint_hud")
		if hud.visible:
			_errors.append("LandmarkHintHud should hide after second toggle")
	if world_environment != null and sun != null:
		host.call("toggle_mood")
		_require_dawn_mood(world_environment, sun)
		host.call("toggle_mood")
		_inspect_default_environment(world_environment)
		_inspect_default_sun(sun)


func _require_current_camera(context: String, chase_camera: Camera3D, orbit_camera: Camera3D, fpv_camera: Camera3D, expected: Camera3D) -> void:
	if chase_camera.current != (chase_camera == expected):
		_errors.append(context + " ChaseCamera current state was wrong")
	if orbit_camera.current != (orbit_camera == expected):
		_errors.append(context + " OrbitCamera current state was wrong")
	if fpv_camera.current != (fpv_camera == expected):
		_errors.append(context + " FpvCamera current state was wrong")


func _require_dawn_mood(world_environment: WorldEnvironment, sun: DirectionalLight3D) -> void:
	if world_environment.environment == null:
		_errors.append("GoldenHourEnvironment has no Environment resource for dawn toggle")
		return
	var environment: Environment = world_environment.environment
	_require_environment_mood(
		environment,
		"dawn",
		GameConfig.dawn_background_color,
		GameConfig.dawn_ambient_color,
		GameConfig.dawn_ambient_energy,
		GameConfig.dawn_fog_density,
		GameConfig.dawn_fog_light_color
	)
	if sun.light_color != GameConfig.dawn_sun_color:
		_errors.append("GoldenHourSun should switch to dawn color")
	if absf(sun.light_energy - GameConfig.dawn_sun_energy) > FLOAT_EPSILON:
		_errors.append("GoldenHourSun should switch to dawn energy")


func _require_environment_mood(environment: Environment, mood_name: String, background_color: Color, ambient_color: Color, ambient_energy: float, fog_density: float, fog_light_color: Color) -> void:
	if environment.background_mode != Environment.BG_COLOR:
		_errors.append("GoldenHourEnvironment " + mood_name + " should use color background mode")
	if environment.ambient_light_source != Environment.AMBIENT_SOURCE_COLOR:
		_errors.append("GoldenHourEnvironment " + mood_name + " should use color ambient source")
	if not environment.fog_enabled:
		_errors.append("GoldenHourEnvironment " + mood_name + " should enable fog")
	if environment.background_color != background_color:
		_errors.append("GoldenHourEnvironment " + mood_name + " background color mismatch")
	if environment.ambient_light_color != ambient_color:
		_errors.append("GoldenHourEnvironment " + mood_name + " ambient color mismatch")
	if absf(environment.ambient_light_energy - ambient_energy) > FLOAT_EPSILON:
		_errors.append("GoldenHourEnvironment " + mood_name + " ambient energy expected " + str(ambient_energy) + ", got " + str(environment.ambient_light_energy))
	if absf(environment.fog_density - fog_density) > FLOAT_EPSILON:
		_errors.append("GoldenHourEnvironment " + mood_name + " fog density expected " + str(fog_density) + ", got " + str(environment.fog_density))
	if environment.fog_light_color != fog_light_color:
		_errors.append("GoldenHourEnvironment " + mood_name + " fog light color mismatch")


func _inspect_audio_rig(audio_rig: Node) -> void:
	var surface_callable: Callable = Callable(audio_rig, "_on_vehicle_changed_surface")
	if not EventBus.vehicle_changed_surface.is_connected(surface_callable):
		_errors.append("CedarAudioRig should listen for vehicle_changed_surface")
	_require_audio_reactivity(audio_rig)
	_require_audio_generator(audio_rig, "MotorWhine")
	_require_audio_generator(audio_rig, "TireTexture")
	_require_audio_generator(audio_rig, "AmbientBed")
	_require_audio_generator(audio_rig, "CreekBed")
	_require_audio_generator(audio_rig, "PlankKnock")


func _require_audio_generator(parent: Node, path: String) -> void:
	var player: AudioStreamPlayer = _require_node(parent, path) as AudioStreamPlayer
	if player == null:
		return
	var stream: AudioStreamGenerator = player.stream as AudioStreamGenerator
	if stream == null:
		_errors.append(path + " should use an AudioStreamGenerator")
		return
	if absf(stream.mix_rate - GameConfig.audio_mix_rate) > FLOAT_EPSILON:
		_errors.append(path + " mix_rate expected " + str(GameConfig.audio_mix_rate) + ", got " + str(stream.mix_rate))
	if absf(stream.buffer_length - GameConfig.audio_buffer_length) > FLOAT_EPSILON:
		_errors.append(path + " buffer_length expected " + str(GameConfig.audio_buffer_length) + ", got " + str(stream.buffer_length))
	if player.playing:
		_errors.append(path + " should not auto-play in headless inspection")


func _require_audio_reactivity(audio_rig: Node) -> void:
	_require_audio_surface_catalog(audio_rig)
	var center_volume: float = float(audio_rig.call("water_volume_for_position", GameConfig.audio_water_center))
	if absf(center_volume - GameConfig.audio_water_volume) > FLOAT_EPSILON:
		_errors.append("CedarAudioRig water volume should be max at creek center")
	var far_position: Vector3 = GameConfig.audio_water_center + Vector3(GameConfig.audio_water_audible_radius * 2.0, 0.0, 0.0)
	var far_volume: float = float(audio_rig.call("water_volume_for_position", far_position))
	if absf(far_volume) > FLOAT_EPSILON:
		_errors.append("CedarAudioRig water volume should be silent outside audible radius")


func _require_audio_surface_catalog(audio_rig: Node) -> void:
	var supported_ids: Array[StringName] = audio_rig.call("supported_audio_surface_ids")
	var data_ids: Array[StringName] = _load_surface_resource_ids()
	for surface_id in data_ids:
		if not supported_ids.has(surface_id):
			_errors.append("CedarAudioRig missing tire audio mapping for SurfaceDef: " + String(surface_id))
			continue
		_require_audio_surface_response(audio_rig, surface_id, _expected_audio_gain(surface_id), _expected_audio_pitch(surface_id))
	for supported_id in supported_ids:
		if not data_ids.has(supported_id):
			_errors.append("CedarAudioRig supports non-existent SurfaceDef: " + String(supported_id))


func _load_surface_resource_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	var dir: DirAccess = DirAccess.open(SURFACE_DIR_PATH)
	if dir == null:
		_errors.append("failed to open surface data directory: " + SURFACE_DIR_PATH)
		return ids
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var resource_path: String = SURFACE_DIR_PATH.path_join(file_name)
			var surface: Resource = load(resource_path)
			if surface == null:
				_errors.append("failed to load surface resource for audio inspection: " + resource_path)
			else:
				var surface_id: StringName = surface.get("id")
				if surface_id == &"":
					_errors.append(resource_path + " has an empty surface id")
				else:
					ids.append(surface_id)
		file_name = dir.get_next()
	dir.list_dir_end()
	if ids.is_empty():
		_errors.append("surface data directory has no .tres resources: " + SURFACE_DIR_PATH)
	return ids


func _expected_audio_gain(surface_id: StringName) -> float:
	return float(CedarSurfaceVisualCatalog.call("tire_audio_gain_for", surface_id))


func _expected_audio_pitch(surface_id: StringName) -> float:
	return float(CedarSurfaceVisualCatalog.call("tire_audio_pitch_for", surface_id))


func _require_audio_surface_response(audio_rig: Node, surface_id: StringName, expected_gain: float, expected_pitch: float) -> void:
	var gain: float = float(audio_rig.call("surface_tire_gain_for", surface_id))
	var pitch: float = float(audio_rig.call("surface_tire_pitch_for", surface_id))
	if absf(gain - expected_gain) > FLOAT_EPSILON:
		_errors.append("CedarAudioRig tire gain for " + String(surface_id) + " expected " + str(expected_gain) + ", got " + str(gain))
	if absf(pitch - expected_pitch) > FLOAT_EPSILON:
		_errors.append("CedarAudioRig tire pitch for " + String(surface_id) + " expected " + str(expected_pitch) + ", got " + str(pitch))


func _count_collision_objects(parent: Node) -> int:
	var count: int = 0
	for child in parent.get_children():
		if child is CollisionObject3D:
			count += 1
		count += _count_collision_objects(child)
	return count


func _count_static_bodies(parent: Node) -> int:
	var count: int = 0
	for child in parent.get_children():
		if child is StaticBody3D:
			count += 1
		count += _count_static_bodies(child)
	return count


func _count_box_collision_shapes(parent: Node) -> int:
	var count: int = 0
	for child in parent.get_children():
		var collision: CollisionShape3D = child as CollisionShape3D
		if collision != null and collision.shape is BoxShape3D:
			count += 1
		count += _count_box_collision_shapes(child)
	return count


func _count_mesh_instances(parent: Node) -> int:
	var count: int = 0
	for child in parent.get_children():
		if child is MeshInstance3D:
			count += 1
		count += _count_mesh_instances(child)
	return count


func _finish() -> void:
	if _errors.is_empty():
		print("ok: Cedar Hollow terrain, visuals, cameras, mood, audio, and landmark HUD nodes instantiated")
		if _scene_root != null:
			_scene_root.queue_free()
		await get_tree().process_frame
		get_tree().quit(0)
		return
	for error in _errors:
		push_error(error)
	if _scene_root != null:
		_scene_root.queue_free()
	await get_tree().process_frame
	get_tree().quit(1)
