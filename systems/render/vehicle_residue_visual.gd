class_name VehicleResidueVisual
extends RefCounted

const ContaminationShader: Shader = preload("res://systems/render/vehicle_contamination_visual.gdshader")
const MudBodyMask: Texture2D = preload("res://assets/textures/vehicle/residue/mud_body_mask.png")
const DustBodyMask: Texture2D = preload("res://assets/textures/vehicle/residue/dust_body_mask.png")
const WetnessBodyMask: Texture2D = preload("res://assets/textures/vehicle/residue/wetness_body_mask.png")
const MudTireMask: Texture2D = preload("res://assets/textures/vehicle/residue/mud_tire_mask.png")
const DustTireMask: Texture2D = preload("res://assets/textures/vehicle/residue/dust_tire_mask.png")
const WetnessTireMask: Texture2D = preload("res://assets/textures/vehicle/residue/wetness_tire_mask.png")
const BODY_OVERLAY_NAME: String = "residue_body_contamination_overlay"
const TIRE_OVERLAY_NAME: String = "residue_tire_contamination_overlay"
const TIRE_SOURCE_NAME: String = "wheel_mesh"
const OVERLAY_META: String = "vehicle_contamination_overlay"
const SURFACE_META: String = "residue_surface"
const BODY_SURFACE: String = "body"
const TIRE_SURFACE: String = "tire"
const NORMAL_OFFSET_METERS: float = 0.0015
const DRY_ROUGHNESS: float = 0.88
const WET_ROUGHNESS: float = 0.12
const WET_SPECULAR: float = 0.72
const BODY_SOURCE_PATHS: Array[String] = [
	"body",
	"nose",
	"top_deck",
	"side_panel_left",
	"side_panel_right",
	"canopy",
	"roll_cage/cage_left",
	"roll_cage/cage_right",
	"roll_cage/cage_top",
	"roll_cage/cage_front",
	"roll_cage/cage_rear",
	"rear_wing/wing_panel",
	"front_bumper/front_bumper_bar",
	"front_bumper/front_bumper_loop",
	"skid_plate",
	"shock_front_left",
	"shock_front_right",
	"shock_rear_left",
	"shock_rear_right",
	"front_left_arm",
	"front_right_arm",
	"rear_left_arm",
	"rear_right_arm",
	"body_pin_front",
	"body_pin_rear",
	"body_stripe",
	"fender_flares",
	"fender_lips",
	"front_grille",
	"side_number_plates",
	"side_number_marks",
	"body_vents"
]
const WHEEL_SOCKET_NAMES: Array[String] = [
	"wheel_front_left",
	"wheel_front_right",
	"wheel_rear_left",
	"wheel_rear_right"
]


func attach(visual_root: Node) -> void:
	if visual_root == null:
		return
	_ensure_chassis_overlays(visual_root)
	_ensure_tire_overlays(visual_root)


func apply_state(visual_root: Node, state: RefCounted) -> void:
	if visual_root == null or state == null:
		return
	var mud_amount: float = 0.0
	var dust_amount: float = 0.0
	var wetness_amount: float = 0.0
	var contamination: RefCounted = state.get("contamination") as RefCounted
	if contamination != null:
		mud_amount = clampf(float(contamination.get("mud")), 0.0, 1.0)
		dust_amount = clampf(float(contamination.get("dust")), 0.0, 1.0)
		wetness_amount = clampf(float(contamination.get("wetness")), 0.0, 1.0)
	_set_contamination_amounts(visual_root, mud_amount, dust_amount, wetness_amount)


func _ensure_chassis_overlays(visual_root: Node) -> void:
	for index: int in range(BODY_SOURCE_PATHS.size()):
		var source_path: String = BODY_SOURCE_PATHS[index]
		var source: MeshInstance3D = visual_root.get_node_or_null(source_path) as MeshInstance3D
		if source == null:
			continue
		_ensure_mesh_overlay(
			source,
			BODY_OVERLAY_NAME,
			BODY_SURFACE,
			MudBodyMask,
			DustBodyMask,
			WetnessBodyMask,
			GameConfig.vehicle_residue_mud_visual_alpha,
			GameConfig.vehicle_residue_dust_visual_alpha,
			GameConfig.vehicle_residue_wetness_visual_alpha
		)


func _ensure_tire_overlays(visual_root: Node) -> void:
	for index: int in range(WHEEL_SOCKET_NAMES.size()):
		var socket_name: String = WHEEL_SOCKET_NAMES[index]
		var socket: Node = visual_root.get_node_or_null(socket_name)
		if socket == null:
			continue
		var tire_source: MeshInstance3D = _find_tire_source(socket)
		if tire_source == null:
			continue
		_ensure_mesh_overlay(
			tire_source,
			TIRE_OVERLAY_NAME,
			TIRE_SURFACE,
			MudTireMask,
			DustTireMask,
			WetnessTireMask,
			GameConfig.vehicle_residue_mud_visual_alpha * 0.82,
			GameConfig.vehicle_residue_dust_visual_alpha * 0.9,
			GameConfig.vehicle_residue_wetness_visual_alpha * 0.7
		)


func _find_tire_source(socket: Node) -> MeshInstance3D:
	var named_source: MeshInstance3D = socket.get_node_or_null(TIRE_SOURCE_NAME) as MeshInstance3D
	if named_source != null:
		return named_source
	for index: int in range(socket.get_child_count()):
		var child: MeshInstance3D = socket.get_child(index) as MeshInstance3D
		if child != null and child.mesh != null:
			return child
	return null


func _ensure_mesh_overlay(source: MeshInstance3D, overlay_name: String, surface_kind: String, mud_mask: Texture2D, dust_mask: Texture2D, wetness_mask: Texture2D, mud_alpha_scale: float, dust_alpha_scale: float, wetness_alpha_scale: float) -> void:
	if source.mesh == null or source.get_node_or_null(overlay_name) != null:
		return
	var overlay: MeshInstance3D = MeshInstance3D.new()
	overlay.name = overlay_name
	overlay.mesh = source.mesh
	overlay.visible = false
	overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	overlay.material_override = _contamination_material(
		overlay_name + "_" + surface_kind,
		mud_mask,
		dust_mask,
		wetness_mask,
		mud_alpha_scale,
		dust_alpha_scale,
		wetness_alpha_scale
	)
	overlay.set_meta(OVERLAY_META, true)
	overlay.set_meta(SURFACE_META, surface_kind)
	source.add_child(overlay)


func _contamination_material(resource_name: String, mud_mask: Texture2D, dust_mask: Texture2D, wetness_mask: Texture2D, mud_alpha_scale: float, dust_alpha_scale: float, wetness_alpha_scale: float) -> ShaderMaterial:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.resource_name = resource_name + "_material"
	material.shader = ContaminationShader
	material.set_shader_parameter("mud_mask", mud_mask)
	material.set_shader_parameter("dust_mask", dust_mask)
	material.set_shader_parameter("wetness_mask", wetness_mask)
	material.set_shader_parameter("mud_color", GameConfig.vehicle_residue_mud_color)
	material.set_shader_parameter("dust_color", GameConfig.vehicle_residue_dust_color)
	material.set_shader_parameter("wetness_color", GameConfig.vehicle_residue_wetness_color)
	material.set_shader_parameter("mud_alpha_scale", mud_alpha_scale)
	material.set_shader_parameter("dust_alpha_scale", dust_alpha_scale)
	material.set_shader_parameter("wetness_alpha_scale", wetness_alpha_scale)
	material.set_shader_parameter("normal_offset_meters", NORMAL_OFFSET_METERS)
	material.set_shader_parameter("dry_roughness", DRY_ROUGHNESS)
	material.set_shader_parameter("wet_roughness", WET_ROUGHNESS)
	material.set_shader_parameter("wet_specular", WET_SPECULAR)
	_apply_material_amounts(material, 0.0, 0.0, 0.0)
	return material


func _set_contamination_amounts(parent: Node, mud_amount: float, dust_amount: float, wetness_amount: float) -> void:
	for index: int in range(parent.get_child_count()):
		var child: Node = parent.get_child(index)
		var overlay: MeshInstance3D = child as MeshInstance3D
		if overlay != null and bool(overlay.get_meta(OVERLAY_META, false)):
			_set_overlay_amounts(overlay, mud_amount, dust_amount, wetness_amount)
		_set_contamination_amounts(child, mud_amount, dust_amount, wetness_amount)


func _set_overlay_amounts(overlay: MeshInstance3D, mud_amount: float, dust_amount: float, wetness_amount: float) -> void:
	var material: ShaderMaterial = overlay.material_override as ShaderMaterial
	if material == null:
		return
	_apply_material_amounts(material, mud_amount, dust_amount, wetness_amount)
	var mud_alpha_scale: float = float(material.get_shader_parameter("mud_alpha_scale"))
	var dust_alpha_scale: float = float(material.get_shader_parameter("dust_alpha_scale"))
	var wetness_alpha_scale: float = float(material.get_shader_parameter("wetness_alpha_scale"))
	var strongest_alpha: float = maxf(maxf(mud_amount * mud_alpha_scale, dust_amount * dust_alpha_scale), wetness_amount * wetness_alpha_scale)
	overlay.visible = strongest_alpha > GameConfig.vehicle_residue_visible_epsilon


func _apply_material_amounts(material: ShaderMaterial, mud_amount: float, dust_amount: float, wetness_amount: float) -> void:
	material.set_shader_parameter("mud_amount", mud_amount)
	material.set_shader_parameter("dust_amount", dust_amount)
	material.set_shader_parameter("wetness_amount", wetness_amount)
