class_name FeatureVisualBuilder
extends RefCounted

const BoardwalkSegmentScene: PackedScene = preload("res://assets/models/features/boardwalk_segment.glb")
const CulvertPipeScene: PackedScene = preload("res://assets/models/features/culvert_pipe.glb")
const LogRampScene: PackedScene = preload("res://assets/models/features/log_ramp.glb")
const SteppingStoneScene: PackedScene = preload("res://assets/models/features/stepping_stone.glb")

const BOARDWALK_SEGMENT_COUNT: int = 9
const STEPPING_STONE_COUNT: int = 5


static func build_cedar_hollow(parent: Node3D) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = "FeatureVisuals"
	parent.add_child(root)
	_add_boardwalk(root)
	_add_culvert(root)
	_add_log_ramp(root)
	_add_stepping_stones(root)
	return root


static func _add_boardwalk(parent: Node3D) -> void:
	var start_z: float = -4.31
	var stride_z: float = 0.24
	for i in range(BOARDWALK_SEGMENT_COUNT):
		var position: Vector3 = Vector3(3.25, 0.035, start_z + float(i) * stride_z)
		_instance_feature(parent, BoardwalkSegmentScene, "boardwalk_segment_" + str(i + 1), position, Vector3.ZERO, Vector3(1.35, 1.0, 1.0))


static func _add_culvert(parent: Node3D) -> void:
	_instance_feature(parent, CulvertPipeScene, "culvert_pipe", Vector3(-4.35, -0.02, -3.05), Vector3(0.0, 0.0, 0.0), Vector3.ONE)


static func _add_log_ramp(parent: Node3D) -> void:
	_instance_feature(parent, LogRampScene, "log_ramp", Vector3(1.3, -0.005, 0.16), Vector3(0.0, 115.0, 0.0), Vector3(1.0, 1.0, 1.0))


static func _add_stepping_stones(parent: Node3D) -> void:
	var positions: Array[Vector3] = [
		Vector3(3.45, 0.01, -7.05),
		Vector3(3.85, 0.01, -7.35),
		Vector3(4.25, 0.01, -7.15),
		Vector3(4.65, 0.01, -7.5),
		Vector3(5.0, 0.01, -7.2)
	]
	for i in range(mini(STEPPING_STONE_COUNT, positions.size())):
		var rotation: Vector3 = Vector3(0.0, float(i) * 23.0, 0.0)
		_instance_feature(parent, SteppingStoneScene, "stepping_stone_" + str(i + 1), positions[i], rotation, Vector3.ONE)


static func _instance_feature(parent: Node3D, scene: PackedScene, node_name: String, position: Vector3, rotation: Vector3, scale: Vector3) -> Node3D:
	var instance: Node3D = scene.instantiate() as Node3D
	if instance == null:
		push_error("FeatureVisualBuilder: failed to instantiate " + node_name)
		return null
	instance.name = node_name
	instance.position = position
	instance.rotation_degrees = rotation
	instance.scale = scale
	parent.add_child(instance)
	_apply_feature_visibility_range(instance)
	return instance


static func _apply_feature_visibility_range(parent: Node) -> void:
	if parent == null:
		return
	var geometry_instance: GeometryInstance3D = parent as GeometryInstance3D
	if geometry_instance != null:
		geometry_instance.visibility_range_end = GameConfig.vis_range_props
	for child: Node in parent.get_children():
		_apply_feature_visibility_range(child)
