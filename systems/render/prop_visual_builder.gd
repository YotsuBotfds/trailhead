class_name PropVisualBuilder
extends RefCounted

const TrailSignScene: PackedScene = preload("res://assets/models/props/trail_sign.glb")
const PicnicTableScene: PackedScene = preload("res://assets/models/props/picnic_table.glb")
const OldCedarStumpScene: PackedScene = preload("res://assets/models/props/old_cedar_stump.glb")


static func build_cedar_hollow(parent: Node3D) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = "PropVisuals"
	parent.add_child(root)
	_instance_prop(root, TrailSignScene, "trail_sign", Vector3(0.72, 0.0, 0.25), Vector3(0.0, -24.0, 0.0), Vector3.ONE)
	_instance_prop(root, PicnicTableScene, "picnic_table", Vector3(-1.45, 0.0, 0.35), Vector3(0.0, 18.0, 0.0), Vector3.ONE)
	_instance_prop(root, OldCedarStumpScene, "old_cedar_stump", Vector3(0.0, 0.0, -5.25), Vector3.ZERO, Vector3.ONE)
	return root


static func _instance_prop(parent: Node3D, scene: PackedScene, node_name: String, position: Vector3, rotation: Vector3, scale: Vector3) -> Node3D:
	var instance: Node3D = scene.instantiate() as Node3D
	if instance == null:
		return parent
	instance.name = node_name
	instance.position = position
	instance.rotation_degrees = rotation
	instance.scale = scale
	parent.add_child(instance)
	return instance
