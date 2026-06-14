extends Node

const CedarHollowPlayableScene: PackedScene = preload("res://scenes/cedar_hollow_playable.tscn")
const EXPECTED_BOARDWALK_SEGMENTS: int = 9
const EXPECTED_STEPPING_STONES: int = 5
const EXPECTED_TERRAIN_PATCHES: int = 18
const EXPECTED_GRASS_TUFTS: int = 18
const EXPECTED_BOULDERS: int = 5
const EXPECTED_BRANCHES: int = 5
const EXPECTED_PINECONES: int = 8

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
		_require_named_count(terrain_root, "terrain_patch_", EXPECTED_TERRAIN_PATCHES)
		var terrain_collision_count: int = _count_collision_objects(terrain_root)
		if terrain_collision_count > 0:
			_errors.append("TerrainVisuals contains collision objects: " + str(terrain_collision_count))
		var terrain_mesh_count: int = _count_mesh_instances(terrain_root)
		if terrain_mesh_count != EXPECTED_TERRAIN_PATCHES:
			_errors.append("expected " + str(EXPECTED_TERRAIN_PATCHES) + " terrain patch meshes, got " + str(terrain_mesh_count))
	var feature_root: Node = _require_node(_scene_root, "CedarHollow/FeatureVisuals")
	if feature_root != null:
		_require_named_count(feature_root, "boardwalk_segment_", EXPECTED_BOARDWALK_SEGMENTS)
		_require_named_count(feature_root, "stepping_stone_", EXPECTED_STEPPING_STONES)
		_require_named_count(feature_root, "culvert_pipe", 1)
		_require_named_count(feature_root, "log_ramp", 0)
		var collision_count: int = _count_collision_objects(feature_root)
		if collision_count > 0:
			_errors.append("FeatureVisuals contains collision objects: " + str(collision_count))
		var mesh_count: int = _count_mesh_instances(feature_root)
		if mesh_count <= 0:
			_errors.append("FeatureVisuals contains no mesh instances")
	var prop_root: Node = _require_node(_scene_root, "CedarHollow/PropVisuals")
	if prop_root != null:
		_require_named_count(prop_root, "trail_sign", 1)
		_require_named_count(prop_root, "picnic_table", 1)
		_require_named_count(prop_root, "old_cedar_stump", 1)
		var prop_collision_count: int = _count_collision_objects(prop_root)
		if prop_collision_count > 0:
			_errors.append("PropVisuals contains collision objects: " + str(prop_collision_count))
		var prop_mesh_count: int = _count_mesh_instances(prop_root)
		if prop_mesh_count <= 0:
			_errors.append("PropVisuals contains no mesh instances")
	var scatter_root: Node = _require_node(_scene_root, "CedarHollow/ScatterVisuals")
	if scatter_root != null:
		_require_named_count(scatter_root, "grass_tuft_", EXPECTED_GRASS_TUFTS)
		_require_named_count(scatter_root, "boulder_", EXPECTED_BOULDERS)
		_require_named_count(scatter_root, "branch_", EXPECTED_BRANCHES)
		_require_named_count(scatter_root, "pinecone_", EXPECTED_PINECONES)
		var scatter_collision_count: int = _count_collision_objects(scatter_root)
		if scatter_collision_count > 0:
			_errors.append("ScatterVisuals contains collision objects: " + str(scatter_collision_count))
		var scatter_mesh_count: int = _count_mesh_instances(scatter_root)
		if scatter_mesh_count <= 0:
			_errors.append("ScatterVisuals contains no mesh instances")
	_require_node(_scene_root, "CedarHollow")
	_require_node(_scene_root, "Vehicle")
	_require_node(_scene_root, "ChaseCamera")
	_require_node(_scene_root, "OrbitCamera")
	_require_node(_scene_root, "SurfaceMap")
	_require_node(_scene_root, "GoldenHourEnvironment")
	_require_node(_scene_root, "GoldenHourSun")
	_require_node(_scene_root, "CedarAudioRig")
	_require_node(_scene_root, "CedarAudioRig/MotorWhine")
	_require_node(_scene_root, "CedarAudioRig/TireTexture")
	_require_node(_scene_root, "LandmarkHintHud")
	_require_node(_scene_root, "LandmarkHintHud/MinimapView")
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
