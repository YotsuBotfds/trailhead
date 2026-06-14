class_name PropVisualBuilder
extends RefCounted

const TrailSignScene: PackedScene = preload("res://assets/models/props/trail_sign.glb")
const KioskScene: PackedScene = preload("res://assets/models/props/kiosk.glb")
const MileMarkerScene: PackedScene = preload("res://assets/models/props/mile_marker.glb")
const ParkBenchScene: PackedScene = preload("res://assets/models/props/park_bench.glb")
const CarabinerScene: PackedScene = preload("res://assets/models/props/carabiner.glb")
const BottleCapScene: PackedScene = preload("res://assets/models/props/bottle_cap.glb")
const PicnicTableScene: PackedScene = preload("res://assets/models/props/picnic_table.glb")
const OldCedarStumpScene: PackedScene = preload("res://assets/models/props/old_cedar_stump.glb")
const FireRingScene: PackedScene = preload("res://assets/models/props/fire_ring.glb")
const HikingBootScene: PackedScene = preload("res://assets/models/props/hiking_boot.glb")
const WaterBottleScene: PackedScene = preload("res://assets/models/props/water_bottle.glb")


static func build_cedar_hollow(parent: Node3D) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = "PropVisuals"
	parent.add_child(root)
	var trail_sign: Node3D = _instance_prop(root, TrailSignScene, "trail_sign", Vector3(0.72, 0.0, 0.25), Vector3(0.0, -24.0, 0.0), Vector3.ONE)
	_add_trail_sign_labels(trail_sign)
	var kiosk: Node3D = _instance_prop(root, KioskScene, "kiosk", Vector3(-1.18, 0.0, 1.18), Vector3(0.0, 12.0, 0.0), Vector3.ONE)
	_add_kiosk_labels(kiosk)
	var mile_marker: Node3D = _instance_prop(root, MileMarkerScene, "mile_marker", Vector3(1.12, 0.0, -2.35), Vector3(0.0, -8.0, 0.0), Vector3.ONE)
	_add_mile_marker_label(mile_marker)
	_add_wayfinder_sign(root, "wayfinder_culvert", Vector3(-2.35, 0.0, -1.72), Vector3(0.0, 80.0, 0.0), Vector3(0.62, 0.72, 0.62), "Culvert", "Spur")
	_add_wayfinder_sign(root, "wayfinder_overlook", Vector3(-0.7, 0.0, -5.95), Vector3(0.0, -58.0, 0.0), Vector3(0.62, 0.72, 0.62), "Overlook", "Ridge")
	_add_wayfinder_sign(root, "wayfinder_creek", Vector3(2.15, 0.0, -4.55), Vector3(0.0, 38.0, 0.0), Vector3(0.62, 0.72, 0.62), "Bog", "Crossing")
	_instance_prop(root, ParkBenchScene, "park_bench", Vector3(-2.0, 0.0, 0.9), Vector3(0.0, 24.0, 0.0), Vector3.ONE)
	_instance_prop(root, CarabinerScene, "carabiner", Vector3(1.25, 0.02, -1.15), Vector3(0.0, -18.0, 0.0), Vector3.ONE)
	_instance_prop(root, BottleCapScene, "bottle_cap", Vector3(-0.95, 0.0, -3.25), Vector3(0.0, 12.0, 0.0), Vector3.ONE)
	_instance_prop(root, PicnicTableScene, "picnic_table", Vector3(-1.45, 0.0, 0.35), Vector3(0.0, 18.0, 0.0), Vector3.ONE)
	_instance_prop(root, OldCedarStumpScene, "old_cedar_stump", Vector3(0.65, 0.0, -5.25), Vector3(0.0, 12.0, 0.0), Vector3(0.78, 0.78, 0.78))
	_instance_prop(root, FireRingScene, "fire_ring", Vector3(-0.78, 0.0, 1.05), Vector3(0.0, 12.0, 0.0), Vector3.ONE)
	_instance_prop(root, HikingBootScene, "hiking_boot", Vector3(0.75, 0.01, -4.65), Vector3(0.0, -32.0, 0.0), Vector3.ONE)
	_instance_prop(root, WaterBottleScene, "water_bottle", Vector3(2.45, 0.0, -4.15), Vector3(0.0, 17.0, 78.0), Vector3.ONE)
	return root


static func _instance_prop(parent: Node3D, scene: PackedScene, node_name: String, position: Vector3, rotation: Vector3, scale: Vector3) -> Node3D:
	var instance: Node3D = scene.instantiate() as Node3D
	if instance == null:
		push_error("PropVisualBuilder: failed to instantiate " + node_name)
		return null
	instance.name = node_name
	instance.position = position
	instance.rotation_degrees = rotation
	instance.scale = scale
	parent.add_child(instance)
	return instance


static func _add_trail_sign_labels(parent: Node3D) -> void:
	_add_sign_label(parent, "label_old_cedar", "Old Cedar", Vector3(0.0, 0.73, -0.052), Vector3(0.0, 180.0, 0.0), 28)
	_add_sign_label(parent, "label_creek", "Creek", Vector3(0.0, 0.43, -0.045), Vector3(0.0, 180.0, 0.0), 22)


static func _add_kiosk_labels(parent: Node3D) -> void:
	_add_sign_label(parent, "label_title", "Cedar Hollow", Vector3(0.0, 0.82, -0.055), Vector3(0.0, 180.0, 0.0), 22)
	_add_sign_label(parent, "label_loop", "Loop Trail", Vector3(0.0, 0.58, -0.052), Vector3(0.0, 180.0, 0.0), 18)


static func _add_mile_marker_label(parent: Node3D) -> void:
	_add_sign_label(parent, "label_distance", "0.4", Vector3(0.0, 0.53, -0.047), Vector3(0.0, 180.0, 0.0), 18)


static func _add_wayfinder_sign(parent: Node3D, node_name: String, position: Vector3, rotation: Vector3, scale: Vector3, primary_text: String, secondary_text: String) -> void:
	var sign: Node3D = _instance_prop(parent, TrailSignScene, node_name, position, rotation, scale)
	_add_sign_label(sign, "label_primary", primary_text, Vector3(0.0, 0.73, -0.052), Vector3(0.0, 180.0, 0.0), 22)
	_add_sign_label(sign, "label_secondary", secondary_text, Vector3(0.0, 0.43, -0.045), Vector3(0.0, 180.0, 0.0), 18)


static func _add_sign_label(parent: Node3D, label_name: String, text: String, position: Vector3, rotation: Vector3, font_size: int) -> void:
	if parent == null:
		return
	var label: Label3D = Label3D.new()
	label.name = label_name
	label.text = text
	label.position = position
	label.rotation_degrees = rotation
	label.font_size = font_size
	label.pixel_size = 0.003
	label.modulate = Color(0.92, 0.82, 0.62)
	label.outline_size = 4
	label.outline_modulate = Color(0.12, 0.08, 0.04)
	parent.add_child(label)
