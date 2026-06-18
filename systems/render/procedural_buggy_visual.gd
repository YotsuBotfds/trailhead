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
	&"antenna",
	&"roof_kayak"
]
const TAIL_LIGHT_NODE_NAME: StringName = &"tail_lights"
const TAIL_LIGHT_MATERIAL_META: StringName = &"trailhead_tail_light_material"
const TAIL_LIGHT_EMISSION_COLOR: Color = Color(1.0, 0.07, 0.05)
const HEADLIGHT_NODE_NAME: StringName = &"headlights"
const HEADLIGHT_MATERIAL_META: StringName = &"trailhead_headlight_material"
const HEADLIGHT_SPOT_LEFT_NAME: StringName = &"headlight_spot_left"
const HEADLIGHT_SPOT_RIGHT_NAME: StringName = &"headlight_spot_right"
const HEADLIGHT_LEFT_LOCAL: Vector3 = Vector3(-0.038, 0.030, -0.204)
const HEADLIGHT_RIGHT_LOCAL: Vector3 = Vector3(0.038, 0.030, -0.204)
const KAYAK_NODE_NAME: StringName = &"roof_kayak"
const KAYAK_MATERIAL_META: StringName = &"trailhead_kayak_material"
const KAYAK_BASE_POSITION: Vector3 = Vector3(0.0, 0.130, -0.020)
const KAYAK_LENGTH: float = 0.20
const KAYAK_HALF_HEIGHT: float = 0.013
const KAYAK_HULL_COLOR: Color = Color(0.90, 0.74, 0.16)
const KAYAK_SECTION_HALF_WIDTHS: Array[float] = [0.004, 0.014, 0.019, 0.020, 0.019, 0.014, 0.004]


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
	_attach_roof_kayak(visual_root)
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
	tuned_material.emission = GameConfig.headlight_emission_color
	tuned_material.emission_energy_multiplier = GameConfig.headlight_emission_energy
	mesh.surface_set_material(0, tuned_material)
	mesh_instance.set_meta(HEADLIGHT_MATERIAL_META, tuned_material)
	_attach_headlight_spot(mesh_instance, HEADLIGHT_SPOT_LEFT_NAME, HEADLIGHT_LEFT_LOCAL)
	_attach_headlight_spot(mesh_instance, HEADLIGHT_SPOT_RIGHT_NAME, HEADLIGHT_RIGHT_LOCAL)


static func _attach_headlight_spot(parent: Node3D, spot_name: StringName, local_position: Vector3) -> void:
	var spot: SpotLight3D = SpotLight3D.new()
	spot.name = spot_name
	spot.position = local_position
	spot.rotation = Vector3(deg_to_rad(-GameConfig.headlight_pitch_deg), 0.0, 0.0)
	spot.light_color = GameConfig.headlight_light_color
	spot.light_energy = GameConfig.headlight_light_energy
	spot.spot_range = GameConfig.headlight_spot_range
	spot.spot_angle = GameConfig.headlight_spot_angle_deg
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


static func _attach_roof_kayak(visual_root: Node3D) -> void:
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.name = KAYAK_NODE_NAME
	mesh_instance.position = KAYAK_BASE_POSITION
	mesh_instance.mesh = _build_kayak_mesh()
	_apply_kayak_material(mesh_instance)
	visual_root.add_child(mesh_instance)


static func _build_kayak_mesh() -> ArrayMesh:
	var section_count: int = KAYAK_SECTION_HALF_WIDTHS.size()
	var half_length: float = KAYAK_LENGTH * 0.5
	var z_step: float = KAYAK_LENGTH / float(maxi(section_count - 1, 1))
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for section_index in range(section_count - 1):
		var z0: float = -half_length + z_step * float(section_index)
		var z1: float = -half_length + z_step * float(section_index + 1)
		var hw0: float = KAYAK_SECTION_HALF_WIDTHS[section_index]
		var hw1: float = KAYAK_SECTION_HALF_WIDTHS[section_index + 1]
		_append_kayak_hull_segment(st, z0, hw0, z1, hw1)
	_append_kayak_cap(st, -half_length, KAYAK_SECTION_HALF_WIDTHS[0], true)
	_append_kayak_cap(st, half_length, KAYAK_SECTION_HALF_WIDTHS[section_count - 1], false)
	st.generate_normals()
	var mesh: ArrayMesh = st.commit()
	return mesh


static func _append_kayak_hull_segment(st: SurfaceTool, z0: float, hw0: float, z1: float, hw1: float) -> void:
	var tl0: Vector3 = Vector3(-hw0, KAYAK_HALF_HEIGHT, z0)
	var tr0: Vector3 = Vector3(hw0, KAYAK_HALF_HEIGHT, z0)
	var br0: Vector3 = Vector3(hw0, -KAYAK_HALF_HEIGHT, z0)
	var bl0: Vector3 = Vector3(-hw0, -KAYAK_HALF_HEIGHT, z0)
	var tl1: Vector3 = Vector3(-hw1, KAYAK_HALF_HEIGHT, z1)
	var tr1: Vector3 = Vector3(hw1, KAYAK_HALF_HEIGHT, z1)
	var br1: Vector3 = Vector3(hw1, -KAYAK_HALF_HEIGHT, z1)
	var bl1: Vector3 = Vector3(-hw1, -KAYAK_HALF_HEIGHT, z1)
	_append_kayak_quad(st, tl0, tl1, tr1, tr0)
	_append_kayak_quad(st, tr0, tr1, br1, br0)
	_append_kayak_quad(st, br0, br1, bl1, bl0)
	_append_kayak_quad(st, bl0, bl1, tl1, tl0)


static func _append_kayak_cap(st: SurfaceTool, z: float, half_width: float, is_stern: bool) -> void:
	var tl: Vector3 = Vector3(-half_width, KAYAK_HALF_HEIGHT, z)
	var tr: Vector3 = Vector3(half_width, KAYAK_HALF_HEIGHT, z)
	var br: Vector3 = Vector3(half_width, -KAYAK_HALF_HEIGHT, z)
	var bl: Vector3 = Vector3(-half_width, -KAYAK_HALF_HEIGHT, z)
	if is_stern:
		_append_kayak_quad(st, tl, tr, br, bl)
	else:
		_append_kayak_quad(st, tl, bl, br, tr)


static func _append_kayak_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(d)


static func _apply_kayak_material(mesh_instance: MeshInstance3D) -> void:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.resource_name = "kayak_hull_mat"
	material.albedo_color = KAYAK_HULL_COLOR
	material.roughness = 0.78
	material.metallic = 0.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_instance.material_override = material
	mesh_instance.set_meta(KAYAK_MATERIAL_META, material)


static func get_kayak_material(visual_root: Node) -> StandardMaterial3D:
	if visual_root == null:
		return null
	var node: Node = visual_root.get_node_or_null(String(KAYAK_NODE_NAME))
	if node == null or not node.has_meta(KAYAK_MATERIAL_META):
		return null
	return node.get_meta(KAYAK_MATERIAL_META) as StandardMaterial3D
