extends Node

const CedarHollowPlayableScene: PackedScene = preload("res://scenes/cedar_hollow_playable.tscn")
const EXPECTED_BOARDWALK_SEGMENTS: int = 9
const EXPECTED_STEPPING_STONES: int = 5

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
	_require_node(_scene_root, "CedarHollow")
	_require_node(_scene_root, "Vehicle")
	_require_node(_scene_root, "ChaseCamera")
	_require_node(_scene_root, "SurfaceMap")
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
		print("ok: Cedar Hollow feature visuals instantiated")
		get_tree().quit(0)
		return
	for error in _errors:
		push_error(error)
	get_tree().quit(1)
