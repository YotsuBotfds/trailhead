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
# FIDELITY PBR-response classification. Keyed on the exact GLB material
# resource_name (see tools/generate_vehicle_glbs.py). Painted body, the roll
# cage, and the emissive lenses (headlight_lens_mat / tail_light_lens_mat) are
# handled by their own dedicated paths (_apply_clearcoat, _apply_roll_cage_polish,
# _apply_*_emission) and are intentionally EXCLUDED here so this pass never
# fights them. Everything else gets a conservative per-class light response;
# anything unlisted falls through to the safe satin-plastic neutral.
const TIRE_MATERIAL_NAMES: Array[String] = ["wheel_tire_mat"]
const POLISHED_METAL_MATERIAL_NAMES: Array[String] = [
	"wheel_rim_mat",
	"wheel_hub_mat",
	"shock_hardware_mat"
]
const CAST_METAL_MATERIAL_NAMES: Array[String] = [
	"skid_plate_mat",
	"exhaust_mat"
]
const GLASS_MATERIAL_NAMES: Array[String] = ["canopy_mat"]
# Materials owned by other paths -- skipped by the generic response pass.
const PBR_RESPONSE_EXCLUDED_NAMES: Array[String] = [
	"headlight_lens_mat",
	"tail_light_lens_mat",
	"cage_side_mat",
	"cage_top_mat",
	"cage_crossbar_mat",
	"wing_panel_mat",
	"wing_stanchion_mat",
	"bumper_bar_mat",
	"bumper_upright_mat",
	"roll_cage_detail_mat"
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
	&"whip_antenna",
	&"driver",
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
const WHIP_ANTENNA_NODE_NAME: StringName = &"whip_antenna"
const WHIP_ANTENNA_BASE_POSITION: Vector3 = Vector3(0.052, 0.108, 0.063)
const WHIP_ANTENNA_HEIGHT: float = 0.140
const WHIP_ANTENNA_RADIUS: float = 0.0016
const WHIP_ANTENNA_COLOR: Color = Color(0.05, 0.05, 0.06)
const WHIP_ANTENNA_ROUGHNESS: float = 0.45
const WHIP_FLAG_VERTICAL_OFFSET: float = 0.124
const WHIP_FLAG_WIDTH: float = 0.024
const WHIP_FLAG_HEIGHT: float = 0.014
const WHIP_FLAG_DEPTH: float = 0.0014
const WHIP_FLAG_COLOR: Color = Color(0.97, 0.84, 0.22)
const SHOCK_SPRING_NODE_SUFFIX: String = "_spring"
const SHOCK_NODE_NAMES: Array[StringName] = [
	&"shock_front_left",
	&"shock_front_right",
	&"shock_rear_left",
	&"shock_rear_right"
]
const SHOCK_SPRING_RADIUS: float = 0.0075
const SHOCK_SPRING_HEIGHT: float = 0.030
const SHOCK_SPRING_COILS: int = 4
const SHOCK_SPRING_WIRE_THICKNESS: float = 0.0018
const SHOCK_SPRING_COLOR: Color = Color(0.78, 0.52, 0.18)
const DRIVER_NODE_NAME: StringName = &"driver"
const DRIVER_BASE_POSITION: Vector3 = Vector3(0.0, 0.046, -0.028)
const DRIVER_TORSO_HALF_EXTENTS: Vector3 = Vector3(0.014, 0.014, 0.012)
const DRIVER_TORSO_COLOR: Color = Color(0.16, 0.18, 0.22)
const DRIVER_HEAD_RADIUS: float = 0.011
const DRIVER_HEAD_VERTICAL_OFFSET: float = 0.024
const DRIVER_HEAD_COLOR: Color = Color(0.93, 0.93, 0.93)
const DRIVER_VISOR_HALF_EXTENTS: Vector3 = Vector3(0.009, 0.004, 0.0025)
const DRIVER_VISOR_LOCAL_OFFSET: Vector3 = Vector3(0.0, 0.0015, -0.0095)
const DRIVER_VISOR_COLOR: Color = Color(0.06, 0.08, 0.12)
const CAGE_NAME_PREFIX: String = "cage_"
const RC_DETAIL_MATERIAL_META: StringName = &"trailhead_rc_detail_material"
# Ungrounding cap (kept defensive): the StandardMaterial3D fresnel rim is unlit
# edge energy, so a strong rim on a saturated body can read as a self-lit
# underglow once bloom picks it up. Cap it below the author value so the body
# stays lit-only-by-sun. The FIDELITY hero now wears a deep petrol-teal (far
# lower bloom risk than the prior bright orange), but the cap is retained so a
# future palette swap can't silently re-introduce the glow.
const BUGGY_BODY_RIM_GROUNDED_CAP: float = 0.15


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
	_attach_whip_antenna(visual_root)
	_attach_coil_springs(visual_root)
	_attach_driver_figure(visual_root)
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


static func sync_wheel_socket_heights(visual_root: Node, wheel_sockets: Array[Node3D], state: RefCounted) -> void:
	var physics_body: Node3D = null
	if visual_root != null:
		physics_body = visual_root.get_parent() as Node3D
	var hit_points: Array[Vector3] = []
	var wheel_contacts: Array[bool] = []
	if state != null:
		hit_points = state.get("wheel_hit_point")
		wheel_contacts = state.get("wheel_contact")
	var droop_y: float = -(GameConfig.susp_rest_length + GameConfig.susp_travel)
	var compressed_y: float = -GameConfig.susp_rest_length
	for i in range(wheel_sockets.size()):
		var socket: Node3D = wheel_sockets[i]
		if socket == null:
			continue
		var local_position: Vector3 = socket.position
		if physics_body != null and i < hit_points.size() and i < wheel_contacts.size() and wheel_contacts[i]:
			var hit_local: Vector3 = physics_body.to_local(hit_points[i])
			local_position.y = clampf(hit_local.y + GameConfig.wheel_radius, droop_y, compressed_y)
		else:
			local_position.y = droop_y
		socket.position = local_position


static func _apply_vehicle_render_tuning(node: Node) -> void:
	var geometry: GeometryInstance3D = node as GeometryInstance3D
	if geometry != null:
		geometry.visibility_range_end = maxf(GameConfig.vis_range_vehicle, 0.0)
	var mesh_instance: MeshInstance3D = node as MeshInstance3D
	if mesh_instance != null:
		_apply_pbr_response(mesh_instance)
		_apply_clearcoat(mesh_instance)
		_apply_roll_cage_polish(mesh_instance)
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
		# W6-VEHICLE / FIDELITY: subtle paint polish layered on the same duplicate so
		# the painted shells don't read flat under golden-hour light. Metallic adds a
		# faint flake (metallic-paint read); rim adds a soft edge highlight. Albedo
		# (the FIDELITY hero teal/amber palette baked in the GLB) is left untouched so
		# the authored two-tone survives. The GLB already carries a low metallic for
		# these panels; this re-asserts it from GameConfig so the flake is tunable.
		tuned_material.metallic = clampf(GameConfig.buggy_body_metallic, 0.0, 1.0)
		# FIDELITY: a subtle metallic_specular bump so a sharper highlight forms on
		# the painted shells under golden-hour sun (the GLB bake gives the body real
		# roughness but no specular lift). Roughness/albedo are left exactly as the
		# clearcoat/GLB authored them.
		if GameConfig.buggy_pbr_response_enabled:
			tuned_material.metallic_specular = clampf(GameConfig.buggy_body_specular, 0.0, 1.0)
		tuned_material.rim_enabled = GameConfig.buggy_body_rim_enabled
		# Cap the fresnel rim so it doesn't read as a self-lit underglow on saturated
		# paint (see BUGGY_BODY_RIM_GROUNDED_CAP).
		tuned_material.rim = minf(clampf(GameConfig.buggy_body_rim_energy, 0.0, 1.0), BUGGY_BODY_RIM_GROUNDED_CAP)
		# Guarantee the body paint is never self-lit. The source GLB materials carry
		# no emission, but pin it off here so a future import/path cannot silently
		# make the paint glow. Intended emissives (headlights, tail lights) are wired
		# on their own mesh names in dedicated paths and are NOT body clearcoat
		# panels, so they are unaffected.
		tuned_material.emission_enabled = false
		tuned_material.emission_energy_multiplier = 0.0
		mesh.surface_set_material(surface_index, tuned_material)


static func _apply_roll_cage_polish(mesh_instance: MeshInstance3D) -> void:
	if not String(mesh_instance.name).begins_with(CAGE_NAME_PREFIX):
		return
	var mesh: Mesh = mesh_instance.mesh
	if mesh == null:
		return
	for surface_index in range(mesh.get_surface_count()):
		var material: StandardMaterial3D = mesh.surface_get_material(surface_index) as StandardMaterial3D
		if material == null:
			continue
		var tuned_material: StandardMaterial3D = material.duplicate() as StandardMaterial3D
		if tuned_material == null:
			continue
		# W6-VEHICLE: read the cage as dark tubular metal instead of flat matte.
		# Albedo is preserved (only metallic + roughness are tuned).
		tuned_material.metallic = clampf(GameConfig.buggy_cage_metallic, 0.0, 1.0)
		tuned_material.metallic_specular = 0.5
		tuned_material.roughness = clampf(GameConfig.buggy_cage_roughness, 0.0, 1.0)
		mesh.surface_set_material(surface_index, tuned_material)


static func _is_clearcoat_body_material(material_name: String) -> bool:
	for token in CLEARCOAT_MATERIAL_TOKENS:
		if material_name.contains(token):
			return true
	return false


# FIDELITY: conservative per-surface-class PBR light response. Walks the mesh
# surfaces and re-asserts metallic / roughness / specular per material class so
# the hero buggy reads as painted bodywork, rubber, metal and glass rather than
# flat plastic. Albedo/colors are never touched. Painted body, the cage family
# and the emissive lenses are owned by dedicated paths and skipped here. Anything
# not confidently classified falls back to a safe satin-plastic neutral instead
# of a guessed metallic.
static func _apply_pbr_response(mesh_instance: MeshInstance3D) -> void:
	if not GameConfig.buggy_pbr_response_enabled:
		return
	var mesh: Mesh = mesh_instance.mesh
	if mesh == null:
		return
	for surface_index in range(mesh.get_surface_count()):
		var material: StandardMaterial3D = mesh.surface_get_material(surface_index) as StandardMaterial3D
		if material == null:
			continue
		var material_name: String = material.resource_name
		# Painted body shells + cage family + emissive lenses are tuned elsewhere.
		if _is_clearcoat_body_material(material_name):
			continue
		if PBR_RESPONSE_EXCLUDED_NAMES.has(material_name):
			continue
		var target_roughness: float = clampf(GameConfig.buggy_neutral_roughness, 0.0, 1.0)
		var target_metallic: float = clampf(GameConfig.buggy_neutral_metallic, 0.0, 1.0)
		if TIRE_MATERIAL_NAMES.has(material_name):
			target_roughness = clampf(GameConfig.buggy_tire_roughness, 0.0, 1.0)
			target_metallic = clampf(GameConfig.buggy_tire_metallic, 0.0, 1.0)
		elif POLISHED_METAL_MATERIAL_NAMES.has(material_name):
			target_roughness = clampf(GameConfig.buggy_metal_roughness, 0.0, 1.0)
			target_metallic = clampf(GameConfig.buggy_metal_metallic, 0.0, 1.0)
		elif CAST_METAL_MATERIAL_NAMES.has(material_name):
			target_roughness = clampf(GameConfig.buggy_cast_metal_roughness, 0.0, 1.0)
			target_metallic = clampf(GameConfig.buggy_cast_metal_metallic, 0.0, 1.0)
		elif GLASS_MATERIAL_NAMES.has(material_name):
			target_roughness = clampf(GameConfig.buggy_glass_roughness, 0.0, 1.0)
			target_metallic = clampf(GameConfig.buggy_glass_metallic, 0.0, 1.0)
		var tuned_material: StandardMaterial3D = material.duplicate() as StandardMaterial3D
		if tuned_material == null:
			continue
		tuned_material.roughness = target_roughness
		tuned_material.metallic = target_metallic
		mesh.surface_set_material(surface_index, tuned_material)


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


static func get_whip_antenna(visual_root: Node) -> Node3D:
	if visual_root == null:
		return null
	return visual_root.get_node_or_null(String(WHIP_ANTENNA_NODE_NAME)) as Node3D


# --- W6-VEHICLE: RC-toy detail polish ----------------------------------------
# All procedural + cheap, deterministic (no RNG, no wall-clock, no new assets).
# - whip antenna + bright flag topper (classic RC silhouette)
# - visible coil spring at each existing shock_* node (real-chassis read)
# - tiny stylized driver figure in the cockpit (low-poly torso + helmet + visor)
# Material polish (body metallic/rim + cage metalness) lives above in
# _apply_clearcoat / _apply_roll_cage_polish.

static func _attach_whip_antenna(visual_root: Node3D) -> void:
	var antenna_root: Node3D = Node3D.new()
	antenna_root.name = WHIP_ANTENNA_NODE_NAME
	antenna_root.position = WHIP_ANTENNA_BASE_POSITION
	visual_root.add_child(antenna_root)
	var whip_rod: MeshInstance3D = MeshInstance3D.new()
	whip_rod.name = &"whip_rod"
	whip_rod.position = Vector3(0.0, WHIP_ANTENNA_HEIGHT * 0.5, 0.0)
	var whip_mesh: CylinderMesh = CylinderMesh.new()
	whip_mesh.top_radius = WHIP_ANTENNA_RADIUS
	whip_mesh.bottom_radius = WHIP_ANTENNA_RADIUS
	whip_mesh.height = WHIP_ANTENNA_HEIGHT
	whip_rod.mesh = whip_mesh
	whip_rod.material_override = _build_rc_detail_material(WHIP_ANTENNA_COLOR, WHIP_ANTENNA_ROUGHNESS, 0.0)
	antenna_root.add_child(whip_rod)
	var flag: MeshInstance3D = MeshInstance3D.new()
	flag.name = &"whip_flag"
	flag.position = Vector3(WHIP_FLAG_WIDTH * 0.5, WHIP_FLAG_VERTICAL_OFFSET, 0.0)
	var flag_mesh: BoxMesh = BoxMesh.new()
	flag_mesh.size = Vector3(WHIP_FLAG_WIDTH, WHIP_FLAG_HEIGHT, WHIP_FLAG_DEPTH)
	flag.mesh = flag_mesh
	flag.material_override = _build_rc_detail_material(WHIP_FLAG_COLOR, 0.55, 0.0)
	antenna_root.add_child(flag)


static func _attach_coil_springs(visual_root: Node3D) -> void:
	for shock_name in SHOCK_NODE_NAMES:
		var shock_node: Node3D = visual_root.get_node_or_null(String(shock_name)) as Node3D
		if shock_node == null:
			continue
		var spring: MeshInstance3D = MeshInstance3D.new()
		spring.name = String(shock_name) + SHOCK_SPRING_NODE_SUFFIX
		spring.mesh = _build_coil_spring_mesh(SHOCK_SPRING_RADIUS, SHOCK_SPRING_HEIGHT, SHOCK_SPRING_COILS, SHOCK_SPRING_WIRE_THICKNESS)
		spring.material_override = _build_rc_detail_material(SHOCK_SPRING_COLOR, 0.40, 0.20)
		shock_node.add_child(spring)


static func _build_coil_spring_mesh(spring_radius: float, spring_height: float, coils: int, wire_thickness: float) -> ArrayMesh:
	var segments: int = maxi(coils * 10, 12)
	var ring_size: int = 5
	var vertices: PackedVector3Array = PackedVector3Array()
	var indices: PackedInt32Array = PackedInt32Array()
	var prev_offset: int = -1
	for i in range(segments + 1):
		var t: float = float(i) / float(segments)
		var angle: float = t * float(coils) * TAU
		var center: Vector3 = Vector3(cos(angle) * spring_radius, t * spring_height - spring_height * 0.5, sin(angle) * spring_radius)
		var tangent: Vector3 = Vector3(-sin(angle) * spring_radius * float(coils) * TAU, spring_height, cos(angle) * spring_radius * float(coils) * TAU).normalized()
		var up_axis: Vector3 = Vector3.UP if absf(tangent.y) < 0.95 else Vector3.RIGHT
		var binormal: Vector3 = tangent.cross(up_axis).normalized()
		var ring_normal: Vector3 = binormal.cross(tangent).normalized()
		var curr_offset: int = vertices.size()
		for j in range(ring_size):
			var a: float = (float(j) / float(ring_size)) * TAU
			var offset: Vector3 = (ring_normal * cos(a) + binormal * sin(a)) * wire_thickness
			vertices.append(center + offset)
		if prev_offset >= 0:
			for j in range(ring_size):
				var jn: int = (j + 1) % ring_size
				indices.append(prev_offset + j)
				indices.append(prev_offset + jn)
				indices.append(curr_offset + j)
				indices.append(prev_offset + jn)
				indices.append(curr_offset + jn)
				indices.append(curr_offset + j)
		prev_offset = curr_offset
	var arrays: Array = Array()
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _attach_driver_figure(visual_root: Node3D) -> void:
	var driver_root: Node3D = Node3D.new()
	driver_root.name = DRIVER_NODE_NAME
	driver_root.position = DRIVER_BASE_POSITION
	visual_root.add_child(driver_root)
	var torso: MeshInstance3D = MeshInstance3D.new()
	torso.name = &"driver_torso"
	var torso_mesh: BoxMesh = BoxMesh.new()
	torso_mesh.size = DRIVER_TORSO_HALF_EXTENTS * 2.0
	torso.mesh = torso_mesh
	torso.material_override = _build_rc_detail_material(DRIVER_TORSO_COLOR, 0.70, 0.0)
	driver_root.add_child(torso)
	var head: MeshInstance3D = MeshInstance3D.new()
	head.name = &"driver_head"
	head.position = Vector3(0.0, DRIVER_HEAD_VERTICAL_OFFSET, 0.0)
	var head_mesh: SphereMesh = SphereMesh.new()
	head_mesh.radius = DRIVER_HEAD_RADIUS
	head_mesh.height = DRIVER_HEAD_RADIUS * 2.0
	head.mesh = head_mesh
	head.material_override = _build_rc_detail_material(DRIVER_HEAD_COLOR, 0.45, 0.0)
	driver_root.add_child(head)
	var visor: MeshInstance3D = MeshInstance3D.new()
	visor.name = &"driver_visor"
	visor.position = DRIVER_VISOR_LOCAL_OFFSET
	var visor_mesh: BoxMesh = BoxMesh.new()
	visor_mesh.size = DRIVER_VISOR_HALF_EXTENTS * 2.0
	visor.mesh = visor_mesh
	visor.material_override = _build_rc_detail_material(DRIVER_VISOR_COLOR, 0.30, 0.0)
	head.add_child(visor)


static func _build_rc_detail_material(albedo: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = albedo
	material.roughness = clampf(roughness, 0.0, 1.0)
	material.metallic = clampf(metallic, 0.0, 1.0)
	material.set_meta(RC_DETAIL_MATERIAL_META, true)
	return material
