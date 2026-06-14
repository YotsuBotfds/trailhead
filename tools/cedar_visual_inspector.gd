extends Node

const CedarHollowPlayableScene: PackedScene = preload("res://scenes/cedar_hollow_playable.tscn")
const CedarRoute: Resource = preload("res://data/routes/cedar_hollow.tres")
const VehicleStateScript: GDScript = preload("res://systems/vehicle/vehicle_state.gd")
const SURFACE_DIR_PATH: String = "res://data/surfaces"
const EXPECTED_BOARDWALK_SEGMENTS: int = 9
const EXPECTED_STEPPING_STONES: int = 5
const EXPECTED_GRASS_TUFTS: int = 18
const EXPECTED_GRASS_OCCLUDERS: int = 10
const EXPECTED_BOULDERS: int = 5
const EXPECTED_BRANCHES: int = 5
const EXPECTED_PINECONES: int = 8
const EXPECTED_FERN_CLUMPS: int = 6
const EXPECTED_CATTAILS: int = 5
const EXPECTED_BOUNDARY_GRASS: int = 20
const EXPECTED_BOUNDARY_BOULDERS: int = 8
const EXPECTED_BOUNDARY_BRANCHES: int = 6
const EXPECTED_TRAIL_BLAZES: int = 4
const EXPECTED_WAYFINDER_SIGNS: int = 3
const FLOAT_EPSILON: float = 0.001
const CAMERA_COMPOSITION_TOLERANCE: float = 0.01
const CAMERA_LOOK_TOLERANCE: float = 0.01
const CAMERA_PITCH_TOLERANCE_DEG: float = 0.25
const FEATURE_TRANSFORM_TOLERANCE: float = 0.01
const FEATURE_COLLISION_ALIGNMENT_TOLERANCE: float = 0.05
const SCATTER_X_MIN: float = -2.8
const SCATTER_X_MAX: float = 5.05
const SCATTER_Z_MIN: float = -9.55
const SCATTER_Z_MAX: float = -0.3
const GRASS_OCCLUDER_X_MIN: float = -2.8
const GRASS_OCCLUDER_X_MAX: float = 4.7
const GRASS_OCCLUDER_Z_MIN: float = -7.4
const GRASS_OCCLUDER_Z_MAX: float = -0.9
const GRASS_OCCLUDER_MIN_HEIGHT: float = 0.58
const BOUNDARY_EDGE_X: float = 4.5
const BOUNDARY_BACK_Z: float = -9.8
const HEIGHTMESH_ROUTE_MARGIN: float = 0.35
const EXPECTED_BOUNDARY_LEFT_VISUALS: int = 15
const EXPECTED_BOUNDARY_RIGHT_VISUALS: int = 16
const EXPECTED_BOUNDARY_BACK_VISUALS: int = 7

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
	var terrain_root: Node = _require_node(_scene_root, "CedarHollow/TerrainVisuals")
	if terrain_root != null:
		_require_named_count(terrain_root, "terrain_patch_", 0)
		var heightmesh: Node = _require_node(terrain_root, "cedar_hollow_heightmesh")
		if heightmesh != null:
			_inspect_heightmesh_layout(heightmesh)
		var terrain_collision_count: int = _count_collision_objects(terrain_root)
		if terrain_collision_count > 0:
			_errors.append("TerrainVisuals contains collision objects: " + str(terrain_collision_count))
		var terrain_mesh_count: int = _count_mesh_instances(terrain_root)
		if terrain_mesh_count <= 0:
			_errors.append("TerrainVisuals contains no mesh instances")
	var feature_root: Node = _require_node(_scene_root, "CedarHollow/FeatureVisuals")
	if feature_root != null:
		_require_named_count(feature_root, "boardwalk_segment_", EXPECTED_BOARDWALK_SEGMENTS)
		_require_named_count(feature_root, "stepping_stone_", EXPECTED_STEPPING_STONES)
		_require_named_count(feature_root, "culvert_pipe", 1)
		_require_named_count(feature_root, "log_ramp", 1)
		_require_node_position(feature_root, "boardwalk_segment_1", Vector3(3.25, 0.035, -4.31), FEATURE_TRANSFORM_TOLERANCE)
		_require_node_position(feature_root, "boardwalk_segment_9", Vector3(3.25, 0.035, -2.39), FEATURE_TRANSFORM_TOLERANCE)
		_require_node_scale(feature_root, "boardwalk_segment_1", Vector3(1.35, 1.0, 1.0), FLOAT_EPSILON)
		_require_node_position(feature_root, "culvert_pipe", Vector3(-4.35, -0.02, -3.05), FEATURE_TRANSFORM_TOLERANCE)
		_require_node_position(feature_root, "log_ramp", Vector3(1.3, -0.005, 0.16), FEATURE_TRANSFORM_TOLERANCE)
		_require_node_rotation(feature_root, "log_ramp", Vector3(0.0, 115.0, 0.0), FLOAT_EPSILON)
		_require_node_position(feature_root, "stepping_stone_1", Vector3(3.45, 0.01, -7.05), FEATURE_TRANSFORM_TOLERANCE)
		_require_node_position(feature_root, "stepping_stone_5", Vector3(5.0, 0.01, -7.2), FEATURE_TRANSFORM_TOLERANCE)
		_inspect_feature_sequences(feature_root)
		var cedar_world: Node = _require_node(_scene_root, "CedarHollow")
		if cedar_world != null:
			_inspect_feature_collision_alignment(cedar_world, feature_root)
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
		_require_node_rotation(prop_root, "trail_sign", Vector3(0.0, -24.0, 0.0), FLOAT_EPSILON)
		_require_node_position(prop_root, "kiosk", Vector3(-0.18, 0.0, 1.18), FEATURE_TRANSFORM_TOLERANCE)
		_require_node_rotation(prop_root, "kiosk", Vector3(0.0, 6.0, 0.0), FLOAT_EPSILON)
		_require_node_position(prop_root, "mile_marker", Vector3(1.12, 0.0, -2.35), FEATURE_TRANSFORM_TOLERANCE)
		_require_node_rotation(prop_root, "mile_marker", Vector3(0.0, -8.0, 0.0), FLOAT_EPSILON)
		_require_node_position(prop_root, "park_bench", Vector3(-2.0, 0.0, 0.9), FEATURE_TRANSFORM_TOLERANCE)
		_require_node_rotation(prop_root, "park_bench", Vector3(0.0, 24.0, 0.0), FLOAT_EPSILON)
		_require_node_position(prop_root, "carabiner", Vector3(1.25, 0.02, -1.15), FEATURE_TRANSFORM_TOLERANCE)
		_require_node_rotation(prop_root, "carabiner", Vector3(0.0, -18.0, 0.0), FLOAT_EPSILON)
		_require_node_position(prop_root, "bottle_cap", Vector3(-0.95, 0.0, -3.25), FEATURE_TRANSFORM_TOLERANCE)
		_require_node_rotation(prop_root, "bottle_cap", Vector3(0.0, 12.0, 0.0), FLOAT_EPSILON)
		_require_node_position(prop_root, "wayfinder_culvert", Vector3(-2.35, 0.0, -1.72), FEATURE_TRANSFORM_TOLERANCE)
		_require_node_rotation(prop_root, "wayfinder_culvert", Vector3(0.0, 80.0, 0.0), FLOAT_EPSILON)
		_require_node_position(prop_root, "wayfinder_overlook", Vector3(-0.7, 0.0, -5.95), FEATURE_TRANSFORM_TOLERANCE)
		_require_node_rotation(prop_root, "wayfinder_overlook", Vector3(0.0, -58.0, 0.0), FLOAT_EPSILON)
		_require_node_position(prop_root, "wayfinder_creek", Vector3(2.15, 0.0, -4.55), FEATURE_TRANSFORM_TOLERANCE)
		_require_node_rotation(prop_root, "wayfinder_creek", Vector3(0.0, 38.0, 0.0), FLOAT_EPSILON)
		_require_node_position(prop_root, "picnic_table", Vector3(-1.45, 0.0, 0.35), FEATURE_TRANSFORM_TOLERANCE)
		_require_node_rotation(prop_root, "picnic_table", Vector3(0.0, 18.0, 0.0), FLOAT_EPSILON)
		_require_node_position(prop_root, "old_cedar_stump", Vector3(0.0, 0.0, -5.25), FEATURE_TRANSFORM_TOLERANCE)
		_require_node_position(prop_root, "fire_ring", Vector3(-0.78, 0.0, 1.05), FEATURE_TRANSFORM_TOLERANCE)
		_require_node_position(prop_root, "hiking_boot", Vector3(0.75, 0.01, -4.65), FEATURE_TRANSFORM_TOLERANCE)
		_require_node_rotation(prop_root, "hiking_boot", Vector3(0.0, -32.0, 0.0), FLOAT_EPSILON)
		_require_node_position(prop_root, "water_bottle", Vector3(2.45, 0.0, -4.15), FEATURE_TRANSFORM_TOLERANCE)
		_require_node_rotation(prop_root, "water_bottle", Vector3(0.0, 17.0, 78.0), FLOAT_EPSILON)
		_require_label(prop_root, "trail_sign/label_old_cedar", "Old Cedar", 28)
		_require_label(prop_root, "trail_sign/label_creek", "Creek", 22)
		_require_label(prop_root, "kiosk/label_title", "Cedar Hollow", 22)
		_require_label(prop_root, "kiosk/label_loop", "Loop Trail", 18)
		_require_label(prop_root, "mile_marker/label_distance", "0.4", 18)
		_require_label(prop_root, "wayfinder_culvert/label_primary", "Culvert", 22)
		_require_label(prop_root, "wayfinder_culvert/label_secondary", "Spur", 18)
		_require_label(prop_root, "wayfinder_overlook/label_primary", "Overlook", 22)
		_require_label(prop_root, "wayfinder_overlook/label_secondary", "Ridge", 18)
		_require_label(prop_root, "wayfinder_creek/label_primary", "Bog", 22)
		_require_label(prop_root, "wayfinder_creek/label_secondary", "Crossing", 18)
		var prop_collision_count: int = _count_collision_objects(prop_root)
		if prop_collision_count > 0:
			_errors.append("PropVisuals contains collision objects: " + str(prop_collision_count))
		var prop_mesh_count: int = _count_mesh_instances(prop_root)
		if prop_mesh_count <= 0:
			_errors.append("PropVisuals contains no mesh instances")
	var scatter_root: Node = _require_node(_scene_root, "CedarHollow/ScatterVisuals")
	if scatter_root != null:
		_require_named_count(scatter_root, "grass_tuft_", EXPECTED_GRASS_TUFTS)
		_require_named_count(scatter_root, "grass_occluder_", EXPECTED_GRASS_OCCLUDERS)
		_require_named_count(scatter_root, "boulder_", EXPECTED_BOULDERS)
		_require_named_count(scatter_root, "branch_", EXPECTED_BRANCHES)
		_require_named_count(scatter_root, "pinecone_", EXPECTED_PINECONES)
		_require_named_count(scatter_root, "fern_clump_", EXPECTED_FERN_CLUMPS)
		_require_named_count(scatter_root, "cattail_", EXPECTED_CATTAILS)
		_inspect_scatter_layout(scatter_root)
		var scatter_collision_count: int = _count_collision_objects(scatter_root)
		if scatter_collision_count > 0:
			_errors.append("ScatterVisuals contains collision objects: " + str(scatter_collision_count))
		var scatter_mesh_count: int = _count_mesh_instances(scatter_root)
		if scatter_mesh_count <= 0:
			_errors.append("ScatterVisuals contains no mesh instances")
	var boundary_root: Node = _require_node(_scene_root, "CedarHollow/BoundaryVisuals")
	if boundary_root != null:
		_require_named_count(boundary_root, "boundary_grass_", EXPECTED_BOUNDARY_GRASS)
		_require_named_count(boundary_root, "boundary_boulder_", EXPECTED_BOUNDARY_BOULDERS)
		_require_named_count(boundary_root, "boundary_branch_", EXPECTED_BOUNDARY_BRANCHES)
		_require_named_count(boundary_root, "trail_blaze_", EXPECTED_TRAIL_BLAZES)
		_inspect_boundary_layout(boundary_root)
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


func _inspect_heightmesh_layout(heightmesh: Node) -> void:
	var accumulator: BoundsAccumulator = BoundsAccumulator.new()
	_collect_mesh_bounds(heightmesh, accumulator)
	if not accumulator.has_bounds:
		_errors.append("cedar_hollow_heightmesh should expose mesh bounds")
		return
	var route_bounds_min: Vector3 = CedarRoute.get("bounds_min")
	var route_bounds_max: Vector3 = CedarRoute.get("bounds_max")
	if accumulator.bounds_min.x > route_bounds_min.x + HEIGHTMESH_ROUTE_MARGIN:
		_errors.append("heightmesh should cover route min X within margin, got " + str(accumulator.bounds_min.x))
	if accumulator.bounds_max.x < route_bounds_max.x - HEIGHTMESH_ROUTE_MARGIN:
		_errors.append("heightmesh should cover route max X within margin, got " + str(accumulator.bounds_max.x))
	if accumulator.bounds_min.z > route_bounds_min.z + HEIGHTMESH_ROUTE_MARGIN:
		_errors.append("heightmesh should cover route min Z within margin, got " + str(accumulator.bounds_min.z))
	if accumulator.bounds_max.z < route_bounds_max.z - HEIGHTMESH_ROUTE_MARGIN:
		_errors.append("heightmesh should cover route max Z within margin, got " + str(accumulator.bounds_max.z))


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


func _inspect_feature_collision_alignment(cedar_world: Node, feature_root: Node) -> void:
	_require_node_xz_matches_body(feature_root, "boardwalk_segment_5", cedar_world, "boardwalk__surf_wood_plank", FEATURE_COLLISION_ALIGNMENT_TOLERANCE)
	_require_node_xz_matches_body(feature_root, "culvert_pipe", cedar_world, "culvert_mouth_floor__surf_packed_dirt", FEATURE_COLLISION_ALIGNMENT_TOLERANCE)
	_require_node_xz_matches_body(feature_root, "log_ramp", cedar_world, "log_ramp__surf_wood_plank", FEATURE_COLLISION_ALIGNMENT_TOLERANCE)
	_require_node_inside_body_xz(feature_root, "boardwalk_segment_1", cedar_world, "boardwalk__surf_wood_plank", FEATURE_COLLISION_ALIGNMENT_TOLERANCE)
	_require_node_inside_body_xz(feature_root, "boardwalk_segment_9", cedar_world, "boardwalk__surf_wood_plank", FEATURE_COLLISION_ALIGNMENT_TOLERANCE)
	_require_node_inside_body_xz(feature_root, "stepping_stone_1", cedar_world, "wet_stone_crossing__surf_wet_stone", FEATURE_COLLISION_ALIGNMENT_TOLERANCE)
	_require_node_inside_body_xz(feature_root, "stepping_stone_5", cedar_world, "wet_stone_crossing__surf_wet_stone", FEATURE_COLLISION_ALIGNMENT_TOLERANCE)


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
	_require_node_position(scatter_root, "boulder_5", Vector3(3.55, 0.0, -6.55), FEATURE_TRANSFORM_TOLERANCE)
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


func _inspect_boundary_layout(boundary_root: Node) -> void:
	_require_node_position(boundary_root, "boundary_grass_1", Vector3(-5.05, 0.0, 0.8), FEATURE_TRANSFORM_TOLERANCE)
	_require_node_position(boundary_root, "boundary_grass_16", Vector3(4.95, 0.0, -8.5), FEATURE_TRANSFORM_TOLERANCE)
	_require_node_position(boundary_root, "boundary_grass_20", Vector3(1.0, 0.12, -9.95), FEATURE_TRANSFORM_TOLERANCE)
	_require_node_position(boundary_root, "boundary_boulder_1", Vector3(-5.15, 0.0, -0.9), FEATURE_TRANSFORM_TOLERANCE)
	_require_node_position(boundary_root, "boundary_boulder_8", Vector3(0.15, 0.18, -10.05), FEATURE_TRANSFORM_TOLERANCE)
	_require_node_position(boundary_root, "boundary_branch_1", Vector3(-4.9, 0.02, -2.2), FEATURE_TRANSFORM_TOLERANCE)
	_require_node_position(boundary_root, "boundary_branch_6", Vector3(-1.55, 0.31, -10.05), FEATURE_TRANSFORM_TOLERANCE)
	_require_node_position(boundary_root, "trail_blaze_1", Vector3(-5.18, 0.0, -2.85), FEATURE_TRANSFORM_TOLERANCE)
	_require_node_position(boundary_root, "trail_blaze_4", Vector3(5.08, 0.0, -7.25), FEATURE_TRANSFORM_TOLERANCE)
	_require_boundary_bands(boundary_root)


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


func _require_node_xz_matches_body(visual_parent: Node, visual_path: String, body_parent: Node, body_path: String, tolerance: float) -> void:
	var visual: Node3D = _require_node(visual_parent, visual_path) as Node3D
	var body: Node3D = _require_node(body_parent, body_path) as Node3D
	if visual == null or body == null:
		return
	var delta: Vector2 = Vector2(visual.global_position.x - body.global_position.x, visual.global_position.z - body.global_position.z)
	if delta.length() > tolerance:
		_errors.append(visual_path + " should align with " + body_path + " in XZ, delta was " + str(delta.length()))


func _require_node_inside_body_xz(visual_parent: Node, visual_path: String, body_parent: Node, body_path: String, margin: float) -> void:
	var visual: Node3D = _require_node(visual_parent, visual_path) as Node3D
	var body: Node3D = _require_node(body_parent, body_path) as Node3D
	if visual == null or body == null:
		return
	var collision: CollisionShape3D = body.get_node_or_null("Collision") as CollisionShape3D
	if collision == null:
		_errors.append(body_path + " is missing Collision")
		return
	var box: BoxShape3D = collision.shape as BoxShape3D
	if box == null:
		_errors.append(body_path + " Collision should use BoxShape3D")
		return
	var local_position: Vector3 = body.global_transform.affine_inverse() * visual.global_position
	var half_x: float = box.size.x * 0.5 + margin
	var half_z: float = box.size.z * 0.5 + margin
	if absf(local_position.x) > half_x or absf(local_position.z) > half_z:
		_errors.append(visual_path + " should sit inside " + body_path + " XZ bounds, local position was " + str(local_position))


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
	_require_node_position(visual_root, "wheel_front_left", Vector3(-0.08, -0.015, -0.10), FLOAT_EPSILON)
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
	_require_vehicle_steering_visuals(host, visual_root)


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
	_require_camera_pitch(chase_camera, "ChaseCamera reactive update")

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
	var offset: Vector3 = chase_camera.global_position - vehicle_position
	var expected_offset_xz: Vector2 = Vector2(back.x, back.z) * GameConfig.cam_distance
	var actual_offset_xz: Vector2 = Vector2(offset.x, offset.z)
	if actual_offset_xz.distance_to(expected_offset_xz) > CAMERA_COMPOSITION_TOLERANCE:
		_errors.append(context + " rear offset expected " + str(expected_offset_xz) + ", got " + str(actual_offset_xz))
	if absf(offset.y - GameConfig.cam_height) > CAMERA_COMPOSITION_TOLERANCE:
		_errors.append(context + " height offset expected " + str(GameConfig.cam_height) + ", got " + str(offset.y))
	_require_camera_pitch(chase_camera, context)


func _require_camera_pitch(camera: Camera3D, context: String) -> void:
	var forward: Vector3 = -camera.global_transform.basis.z.normalized()
	var pitch_degrees: float = rad_to_deg(asin(clampf(forward.y, -1.0, 1.0)))
	if absf(pitch_degrees - GameConfig.cam_pitch_deg) > CAMERA_PITCH_TOLERANCE_DEG:
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


func _inspect_input_map() -> void:
	_require_input_action_keys(&"throttle", [KEY_W, KEY_UP])
	_require_input_action_keys(&"brake", [KEY_S, KEY_DOWN])
	_require_input_action_keys(&"steer_left", [KEY_A, KEY_LEFT])
	_require_input_action_keys(&"steer_right", [KEY_D, KEY_RIGHT])
	_require_input_action_keys(&"ebrake", [KEY_SPACE])
	_require_input_action_keys(&"self_right", [KEY_R])
	_require_input_action_keys(&"cam_toggle", [KEY_C])
	_require_input_action_keys(&"map_toggle", [KEY_M])
	_require_input_action_keys(&"mood_toggle", [KEY_N])


func _require_input_action_keys(action_name: StringName, expected_keycodes: Array[int]) -> void:
	var action_string: String = String(action_name)
	if not InputMap.has_action(action_string):
		_errors.append("InputMap missing action: " + action_string)
		return
	var observed_keycodes: Array[int] = []
	for event in InputMap.action_get_events(action_string):
		var key_event: InputEventKey = event as InputEventKey
		if key_event != null:
			observed_keycodes.append(key_event.physical_keycode)
	for keycode in expected_keycodes:
		if not observed_keycodes.has(keycode):
			_errors.append("InputMap action " + action_string + " missing keycode " + str(keycode))


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
	_require_minimap_segment_points(minimap, &"overlook_to_old_cedar", 6)


func _require_minimap_segment_points(minimap: Control, segment_id: StringName, expected_count: int) -> void:
	var points: Array = minimap.call("_map_points_for_segment", segment_id)
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
	if surface_id == &"packed_gravel":
		return GameConfig.audio_tire_gain_gravel
	if surface_id == &"packed_dirt":
		return GameConfig.audio_tire_gain_dirt
	if surface_id == &"tall_grass":
		return GameConfig.audio_tire_gain_grass
	if surface_id == &"mud":
		return GameConfig.audio_tire_gain_mud
	if surface_id == &"loose_rock":
		return GameConfig.audio_tire_gain_rock
	if surface_id == &"wet_stone":
		return GameConfig.audio_tire_gain_stone
	if surface_id == &"wood_plank":
		return GameConfig.audio_tire_gain_wood
	_errors.append("missing inspector tire gain expectation for SurfaceDef: " + String(surface_id))
	return GameConfig.audio_tire_gain_dirt


func _expected_audio_pitch(surface_id: StringName) -> float:
	if surface_id == &"packed_gravel":
		return GameConfig.audio_tire_pitch_gravel
	if surface_id == &"packed_dirt":
		return GameConfig.audio_tire_pitch_dirt
	if surface_id == &"tall_grass":
		return GameConfig.audio_tire_pitch_grass
	if surface_id == &"mud":
		return GameConfig.audio_tire_pitch_mud
	if surface_id == &"loose_rock":
		return GameConfig.audio_tire_pitch_rock
	if surface_id == &"wet_stone":
		return GameConfig.audio_tire_pitch_stone
	if surface_id == &"wood_plank":
		return GameConfig.audio_tire_pitch_wood
	_errors.append("missing inspector tire pitch expectation for SurfaceDef: " + String(surface_id))
	return GameConfig.audio_tire_pitch_dirt


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
