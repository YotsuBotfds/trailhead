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

const LABEL_TEXT_COLOR: Color = Color(1.0, 0.96, 0.78)
const LABEL_OUTLINE_COLOR: Color = Color(0.025, 0.018, 0.012)
const LABEL_BACKING_COLOR: Color = Color(0.045, 0.035, 0.022)
const WAYFINDER_ACCENT_COLOR: Color = Color(1.0, 0.36, 0.08)
const WAYFINDER_ACCENT_DARK_COLOR: Color = Color(0.08, 0.025, 0.012)
const LABEL_PIXEL_SIZE: float = 0.0027
const LABEL_BACKING_HEIGHT: float = 0.115
const LABEL_BACKING_DEPTH_OFFSET: float = -0.006


static func build_cedar_hollow(parent: Node3D) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = "PropVisuals"
	parent.add_child(root)
	var trail_sign: Node3D = _instance_prop(root, TrailSignScene, "trail_sign", Vector3(0.72, 0.0, 0.25), Vector3(0.0, -16.0, 0.0), Vector3.ONE)
	_add_trail_sign_labels(trail_sign)
	var kiosk: Node3D = _instance_prop(root, KioskScene, "kiosk", Vector3(-1.18, 0.0, 1.18), Vector3(0.0, 20.0, 0.0), Vector3.ONE)
	_add_kiosk_labels(kiosk)
	var mile_marker: Node3D = _instance_prop(root, MileMarkerScene, "mile_marker", Vector3(1.12, 0.0, -2.35), Vector3(0.0, -8.0, 0.0), Vector3.ONE)
	_add_mile_marker_label(mile_marker)
	_add_wayfinder_sign(root, "wayfinder_culvert", Vector3(-2.15, 0.0, -1.82), Vector3(0.0, 68.0, 0.0), Vector3(0.62, 0.72, 0.62), "Culvert", "Spur", "<")
	_add_wayfinder_sign(root, "wayfinder_overlook", Vector3(-0.55, 0.0, -5.78), Vector3(0.0, -44.0, 0.0), Vector3(0.62, 0.72, 0.62), "Overlook", "Ridge", "^")
	_add_wayfinder_sign(root, "wayfinder_creek", Vector3(1.95, 0.0, -4.72), Vector3(0.0, 28.0, 0.0), Vector3(0.62, 0.72, 0.62), "Bog", "Crossing", ">")
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
	_add_sign_label(parent, "label_old_cedar", "Old Cedar", Vector3(-0.045, 0.73, -0.052), Vector3(0.0, 180.0, 0.0), 30)
	_add_sign_arrow(parent, "arrow_old_cedar", ">", Vector3(0.37, 0.73, -0.054), Vector3(0.0, 180.0, 0.0), 24)
	_add_sign_label(parent, "label_creek", "Creek", Vector3(-0.04, 0.43, -0.045), Vector3(0.0, 180.0, 0.0), 24)
	_add_sign_arrow(parent, "arrow_creek", ">", Vector3(0.29, 0.43, -0.047), Vector3(0.0, 180.0, 0.0), 21)
	_add_sign_accent_bar(parent, "axis_accent", Vector3(0.0, 0.275, -0.048), Vector3(0.0, 180.0, 0.0), Vector2(0.58, 0.035))


static func _add_kiosk_labels(parent: Node3D) -> void:
	_add_sign_label(parent, "label_title", "Cedar Hollow", Vector3(0.0, 0.82, -0.055), Vector3(0.0, 180.0, 0.0), 24)
	_add_sign_label(parent, "label_loop", "Loop Trail", Vector3(0.0, 0.58, -0.052), Vector3(0.0, 180.0, 0.0), 20)
	_add_sign_accent_bar(parent, "axis_accent", Vector3(0.0, 0.43, -0.052), Vector3(0.0, 180.0, 0.0), Vector2(0.46, 0.03))


static func _add_mile_marker_label(parent: Node3D) -> void:
	_add_sign_label(parent, "label_distance", "0.4", Vector3(0.0, 0.53, -0.047), Vector3(0.0, 180.0, 0.0), 20)
	_add_sign_accent_bar(parent, "axis_accent", Vector3(0.0, 0.39, -0.046), Vector3(0.0, 180.0, 0.0), Vector2(0.20, 0.026))


static func _add_wayfinder_sign(parent: Node3D, node_name: String, position: Vector3, rotation: Vector3, scale: Vector3, primary_text: String, secondary_text: String, arrow_text: String) -> void:
	var sign: Node3D = _instance_prop(parent, TrailSignScene, node_name, position, rotation, scale)
	_add_sign_label(sign, "label_primary", primary_text, Vector3(-0.045, 0.73, -0.052), Vector3(0.0, 180.0, 0.0), 24)
	_add_sign_arrow(sign, "arrow_primary", arrow_text, Vector3(0.35, 0.73, -0.054), Vector3(0.0, 180.0, 0.0), 24)
	_add_sign_label(sign, "label_secondary", secondary_text, Vector3(0.0, 0.43, -0.045), Vector3(0.0, 180.0, 0.0), 20)
	_add_sign_accent_bar(sign, "axis_accent", Vector3(0.0, 0.275, -0.048), Vector3(0.0, 180.0, 0.0), Vector2(0.52, 0.035))


static func _add_sign_label(parent: Node3D, label_name: String, text: String, position: Vector3, rotation: Vector3, font_size: int) -> void:
	if parent == null:
		return
	_add_label_backing(parent, label_name, text, position, rotation, font_size)
	var label: Label3D = Label3D.new()
	label.name = label_name
	label.text = text
	label.position = position
	label.rotation_degrees = rotation
	label.font_size = font_size
	label.pixel_size = LABEL_PIXEL_SIZE
	label.modulate = LABEL_TEXT_COLOR
	label.outline_size = 6
	label.outline_modulate = LABEL_OUTLINE_COLOR
	label.material_override = _make_unshaded_material("wayfinder_label_text", LABEL_TEXT_COLOR)
	parent.add_child(label)


static func _add_sign_arrow(parent: Node3D, arrow_name: String, text: String, position: Vector3, rotation: Vector3, font_size: int) -> void:
	if parent == null:
		return
	var arrow: Label3D = Label3D.new()
	arrow.name = arrow_name
	arrow.text = text
	arrow.position = position
	arrow.rotation_degrees = rotation
	arrow.font_size = font_size
	arrow.pixel_size = LABEL_PIXEL_SIZE
	arrow.modulate = WAYFINDER_ACCENT_COLOR
	arrow.outline_size = 7
	arrow.outline_modulate = WAYFINDER_ACCENT_DARK_COLOR
	arrow.material_override = _make_unshaded_material("wayfinder_arrow_text", WAYFINDER_ACCENT_COLOR)
	parent.add_child(arrow)


static func _add_label_backing(parent: Node3D, label_name: String, text: String, position: Vector3, rotation: Vector3, font_size: int) -> void:
	var backing: MeshInstance3D = MeshInstance3D.new()
	backing.name = label_name.replace("label_", "label_backing_")
	var mesh: QuadMesh = QuadMesh.new()
	var text_width: float = maxf(0.22, float(text.length()) * float(font_size) * 0.00095)
	mesh.size = Vector2(text_width + 0.08, LABEL_BACKING_HEIGHT)
	backing.mesh = mesh
	backing.position = position + Vector3(0.0, 0.0, LABEL_BACKING_DEPTH_OFFSET)
	backing.rotation_degrees = rotation
	backing.material_override = _make_unshaded_material("wayfinder_label_backing", LABEL_BACKING_COLOR)
	parent.add_child(backing)


static func _add_sign_accent_bar(parent: Node3D, node_name: String, position: Vector3, rotation: Vector3, size: Vector2) -> void:
	if parent == null:
		return
	var accent: MeshInstance3D = MeshInstance3D.new()
	accent.name = node_name
	var mesh: QuadMesh = QuadMesh.new()
	mesh.size = size
	accent.mesh = mesh
	accent.position = position
	accent.rotation_degrees = rotation
	accent.material_override = _make_unshaded_material("wayfinder_axis_accent", WAYFINDER_ACCENT_COLOR)
	parent.add_child(accent)


static func _make_unshaded_material(resource_name: String, albedo: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.resource_name = resource_name
	material.albedo_color = albedo
	material.roughness = 0.82
	material.metallic = 0.0
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material
