class_name PropVisualBuilder
extends RefCounted

const TrailSignScene: PackedScene = preload("res://assets/models/props/trail_sign.glb")
const PicnicTableScene: PackedScene = preload("res://assets/models/props/picnic_table.glb")
const OldCedarStumpScene: PackedScene = preload("res://assets/models/props/old_cedar_stump.glb")
const FireRingScene: PackedScene = preload("res://assets/models/props/fire_ring.glb")
const HikingBootScene: PackedScene = preload("res://assets/models/props/hiking_boot.glb")
const WaterBottleScene: PackedScene = preload("res://assets/models/props/water_bottle.glb")


static func build_cedar_hollow(parent: Node3D) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = "PropVisuals"
	parent.add_child(root)
	_instance_prop(root, TrailSignScene, "trail_sign", Vector3(0.72, 0.0, 0.25), Vector3(0.0, -24.0, 0.0), Vector3.ONE)
	_instance_prop(root, PicnicTableScene, "picnic_table", Vector3(-1.45, 0.0, 0.35), Vector3(0.0, 18.0, 0.0), Vector3.ONE)
	_instance_prop(root, OldCedarStumpScene, "old_cedar_stump", Vector3(0.0, 0.0, -5.25), Vector3.ZERO, Vector3.ONE)
	_instance_prop(root, FireRingScene, "fire_ring", Vector3(-0.78, 0.0, 1.05), Vector3(0.0, 12.0, 0.0), Vector3.ONE)
	_instance_prop(root, HikingBootScene, "hiking_boot", Vector3(0.75, 0.01, -4.65), Vector3(0.0, -32.0, 0.0), Vector3.ONE)
	_instance_prop(root, WaterBottleScene, "water_bottle", Vector3(2.45, 0.0, -4.15), Vector3(0.0, 17.0, 78.0), Vector3.ONE)
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
