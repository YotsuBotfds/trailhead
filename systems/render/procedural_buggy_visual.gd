class_name ProceduralBuggyVisual
extends RefCounted

const BuggyVisualScene: PackedScene = preload("res://assets/models/vehicle/rc_buggy.glb")
const VehicleResidueVisualScript: GDScript = preload("res://systems/render/vehicle_residue_visual.gd")
const CLEARCOAT_MATERIAL_TOKENS: Array[String] = [
	"body",
	"nose",
	"side_panel",
	"paint_stripe",
	"fender_flare",
	"side_number_plate"
]
const CHASSIS_DROP_NODE_NAMES: Array[StringName] = [
	&"body",
	&"nose",
	&"top_deck",
	&"side_panel_left",
	&"side_panel_right",
	&"canopy",
	&"roll_cage",
	&"rear_wing",
	&"front_bumper",
	&"skid_plate",
	&"body_pin_front",
	&"body_pin_rear",
	&"body_stripe",
	&"fender_flares",
	&"fender_lips",
	&"headlights",
	&"tail_lights",
	&"front_grille",
	&"side_number_plates",
	&"side_number_marks",
	&"body_vents",
	&"antenna"
]
const TAIL_LIGHT_NODE_NAME: StringName = &"tail_lights"
const TAIL_LIGHT_MATERIAL_META: StringName = &"trailhead_tail_light_material"
const TAIL_LIGHT_EMISSION_COLOR: Color = Color(1.0, 0.07, 0.05)
const HEADLIGHT_NODE_NAME: StringName = &"headlights"
const HEADLIGHT_MATERIAL_META: StringName = &"trailhead_headlight_material"
const HEADLIGHT_SPOT_LEFT_NAME: StringName = &"headlight_spot_left"
const HEADLIGHT_SPOT_RIGHT_NAME: StringName = &"headlight_spot_right"
const HEADLIGHT_EMISSION_COLOR: Color = Color(1.0, 0.949, 0.847)
const HEADLIGHT_EMISSION_ENERGY: float = 1.6
const HEADLIGHT_LIGHT_COLOR: Color = Color(1.0, 0.949, 0.847)
const HEADLIGHT_LIGHT_ENERGY: float = 3.0
const HEADLIGHT_SPOT_RANGE: float = 6.0
const HEADLIGHT_SPOT_ANGLE_DEG: float = 35.0
const HEADLIGHT_PITCH_DEG: float = 12.0
const HEADLIGHT_LEFT_LOCAL: Vector3 = Vector3(-0.038, 0.030, -0.204)
const HEADLIGHT_RIGHT_LOCAL: Vector3 = Vector3(0.038, 0.030, -0.204)


func attach(vehicle: Node) -> void:
	var body: Node3D = vehicle.get_node_or_null("PhysicsBody") as Node3D
	if body == null or body.has_node("VisualRoot"):
		return
	var imported_root: Node3D = BuggyVisualScene.instantiate() as Node3D
	if imported_root == null:
		return
	var visual_root: Node3D = imported_root
	var imported_buggy: Node3D = imported_root.get_node_or_null("rc_buggy") as Node3D
	if imported_buggy != null:
		imported_root.remove_child(imported_buggy)
		imported_root.free()
		visual_root = imported_buggy
	visual_root.name = "VisualRoot"
	body.add_child(visual_root)
	_apply_chassis_drop(visual_root)
	_apply_vehicle_render_tuning(visual_root)
	var residue_visual: RefCounted = VehicleResidueVisualScript.new()
	residue_visual.call("attach", visual_root)


static func _apply_chassis_drop(visual_root: Node) -> void:
	var drop: float = maxf(GameConfig.vehicle_visual_chassis_drop, 0.0)
	if drop <= 0.0:
		return
	for node_name in CHASSIS_DROP_NODE_NAMES:
		var node: Node3D = visual_root.get_node_or_null(NodePath(String(node_name))) as Node3D
		if node == null:
			continue
		var local_position: Vector3 = node.position
		local_position.y -= drop
		node.position = local_position


static func _apply_vehicle_render_tuning(node: Node) -> void:
	var geometry: GeometryInstance3D = node as GeometryInstance3D
	if geometry != null:
		geometry.visibility_range_end = maxf(GameConfig.vis_range_vehicle, 0.0)
	var mesh_instance: MeshInstance3D = node as MeshInstance3D
	if mesh_instance != null:
		_apply_clearcoat(mesh_instance)
		if mesh_instance.name == TAIL_LIGHT_NODE_NAME:
			_apply_tail_light_emission(mesh_instance)
		elif mesh_instance.name == HEADLIGHT_NODE_NAME:
			_apply_headlight_emission_and_lights(mesh_instance)
	for child in node.get_children():
		_apply_vehicle_render_tuning(child)


static func _apply_clearcoat(mesh_instance: MeshInstance3D) -> void:
	var mesh: Mesh = mesh_instance.mesh
	if mesh == null:
		return
	for surface_index in range(mesh.get_surface_count()):
		var material: StandardMaterial3D = mesh.surface_get_material(surface_index) as StandardMaterial3D
		if material == null:
			continue
		if not _is_clearcoat_body_material(material.resource_name):
			continue
		var tuned_material: StandardMaterial3D = material.duplicate() as StandardMaterial3D
		if tuned_material == null:
			continue
		tuned_material.clearcoat_enabled = GameConfig.buggy_clearcoat_enabled
		tuned_material.clearcoat = clampf(GameConfig.buggy_clearcoat, 0.0, 1.0)
		tuned_material.clearcoat_roughness = clampf(GameConfig.buggy_clearcoat_roughness, 0.0, 1.0)
		mesh.surface_set_material(surface_index, tuned_material)


static func _is_clearcoat_body_material(material_name: String) -> bool:
	for token in CLEARCOAT_MATERIAL_TOKENS:
		if material_name.contains(token):
			return true
	return false


static func _apply_tail_light_emission(mesh_instance: MeshInstance3D) -> void:
	var mesh: Mesh = mesh_instance.mesh
	if mesh == null or mesh.get_surface_count() == 0:
		return
	var base_material: StandardMaterial3D = mesh.surface_get_material(0) as StandardMaterial3D
	if base_material == null:
		return
	var tuned_material: StandardMaterial3D = base_material.duplicate() as StandardMaterial3D
	if tuned_material == null:
		return
	tuned_material.emission_enabled = true
	tuned_material.emission = TAIL_LIGHT_EMISSION_COLOR
	tuned_material.emission_energy_multiplier = 0.0
	mesh.surface_set_material(0, tuned_material)
	mesh_instance.set_meta(TAIL_LIGHT_MATERIAL_META, tuned_material)


static func get_tail_light_material(visual_root: Node) -> StandardMaterial3D:
	if visual_root == null:
		return null
	var node: Node = visual_root.get_node_or_null(String(TAIL_LIGHT_NODE_NAME))
	if node == null or not node.has_meta(TAIL_LIGHT_MATERIAL_META):
		return null
	return node.get_meta(TAIL_LIGHT_MATERIAL_META) as StandardMaterial3D


static func _apply_headlight_emission_and_lights(mesh_instance: MeshInstance3D) -> void:
	var mesh: Mesh = mesh_instance.mesh
	if mesh == null or mesh.get_surface_count() == 0:
		return
	var base_material: StandardMaterial3D = mesh.surface_get_material(0) as StandardMaterial3D
	if base_material == null:
		return
	var tuned_material: StandardMaterial3D = base_material.duplicate() as StandardMaterial3D
	if tuned_material == null:
		return
	tuned_material.emission_enabled = true
	tuned_material.emission = HEADLIGHT_EMISSION_COLOR
	tuned_material.emission_energy_multiplier = HEADLIGHT_EMISSION_ENERGY
	mesh.surface_set_material(0, tuned_material)
	mesh_instance.set_meta(HEADLIGHT_MATERIAL_META, tuned_material)
	_attach_headlight_spot(mesh_instance, HEADLIGHT_SPOT_LEFT_NAME, HEADLIGHT_LEFT_LOCAL)
	_attach_headlight_spot(mesh_instance, HEADLIGHT_SPOT_RIGHT_NAME, HEADLIGHT_RIGHT_LOCAL)


static func _attach_headlight_spot(parent: Node3D, spot_name: StringName, local_position: Vector3) -> void:
	var spot: SpotLight3D = SpotLight3D.new()
	spot.name = spot_name
	spot.position = local_position
	spot.rotation = Vector3(deg_to_rad(-HEADLIGHT_PITCH_DEG), 0.0, 0.0)
	spot.light_color = HEADLIGHT_LIGHT_COLOR
	spot.light_energy = HEADLIGHT_LIGHT_ENERGY
	spot.spot_range = HEADLIGHT_SPOT_RANGE
	spot.spot_angle = HEADLIGHT_SPOT_ANGLE_DEG
	spot.shadow_enabled = false
	parent.add_child(spot)


static func get_headlight_material(visual_root: Node) -> StandardMaterial3D:
	if visual_root == null:
		return null
	var node: Node = visual_root.get_node_or_null(String(HEADLIGHT_NODE_NAME))
	if node == null or not node.has_meta(HEADLIGHT_MATERIAL_META):
		return null
	return node.get_meta(HEADLIGHT_MATERIAL_META) as StandardMaterial3D


static func get_headlight_lights(visual_root: Node) -> Array[SpotLight3D]:
	var lights: Array[SpotLight3D] = []
	if visual_root == null:
		return lights
	var node: Node = visual_root.get_node_or_null(String(HEADLIGHT_NODE_NAME))
	if node == null:
		return lights
	var spot_names: Array[StringName] = [HEADLIGHT_SPOT_LEFT_NAME, HEADLIGHT_SPOT_RIGHT_NAME]
	for spot_name in spot_names:
		var spot: SpotLight3D = node.get_node_or_null(String(spot_name)) as SpotLight3D
		if spot != null:
			lights.append(spot)
	return lights
