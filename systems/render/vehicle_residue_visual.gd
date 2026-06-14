class_name VehicleResidueVisual
extends RefCounted

const MUD_OVERLAY_NAME: String = "residue_mud_overlay"
const DUST_OVERLAY_NAME: String = "residue_dust_overlay"
const WETNESS_OVERLAY_NAME: String = "residue_wetness_overlay"
const MUD_TIRE_OVERLAY_NAME: String = "residue_mud_tire"
const DUST_TIRE_OVERLAY_NAME: String = "residue_dust_tire"
const WETNESS_TIRE_OVERLAY_NAME: String = "residue_wetness_tire"
const MudBodyMask: Texture2D = preload("res://assets/textures/vehicle/residue/mud_body_mask.png")
const DustBodyMask: Texture2D = preload("res://assets/textures/vehicle/residue/dust_body_mask.png")
const WetnessBodyMask: Texture2D = preload("res://assets/textures/vehicle/residue/wetness_body_mask.png")
const MudTireMask: Texture2D = preload("res://assets/textures/vehicle/residue/mud_tire_mask.png")
const DustTireMask: Texture2D = preload("res://assets/textures/vehicle/residue/dust_tire_mask.png")
const WetnessTireMask: Texture2D = preload("res://assets/textures/vehicle/residue/wetness_tire_mask.png")
const MUD_KIND: String = "mud"
const DUST_KIND: String = "dust"
const WETNESS_KIND: String = "wetness"
const RESIDUE_KIND_META: String = "residue_kind"
const MAX_ALPHA_META: String = "max_alpha"
const WHEEL_SOCKET_NAMES: Array[String] = [
	"wheel_front_left",
	"wheel_front_right",
	"wheel_rear_left",
	"wheel_rear_right"
]


func attach(visual_root: Node) -> void:
	if visual_root == null:
		return
	_ensure_overlay(
		visual_root,
		MUD_OVERLAY_NAME,
		MUD_KIND,
		Vector3(0.0, 0.018, 0.01),
		Vector3(0.17, 0.006, 0.22),
		GameConfig.vehicle_residue_mud_color,
		GameConfig.vehicle_residue_mud_visual_alpha,
		0.92,
		MudBodyMask
	)
	_ensure_overlay(
		visual_root,
		DUST_OVERLAY_NAME,
		DUST_KIND,
		Vector3(0.0, 0.021, 0.0),
		Vector3(0.19, 0.004, 0.24),
		GameConfig.vehicle_residue_dust_color,
		GameConfig.vehicle_residue_dust_visual_alpha,
		0.96,
		DustBodyMask
	)
	_ensure_overlay(
		visual_root,
		WETNESS_OVERLAY_NAME,
		WETNESS_KIND,
		Vector3(0.0, 0.024, -0.01),
		Vector3(0.15, 0.003, 0.20),
		GameConfig.vehicle_residue_wetness_color,
		GameConfig.vehicle_residue_wetness_visual_alpha,
		0.18,
		WetnessBodyMask
	)
	_ensure_tire_overlays(visual_root)


func apply_state(visual_root: Node, state: RefCounted) -> void:
	if visual_root == null or state == null:
		return
	var contamination: RefCounted = state.get("contamination") as RefCounted
	if contamination == null:
		_set_residue_alpha(visual_root, MUD_KIND, 0.0)
		_set_residue_alpha(visual_root, DUST_KIND, 0.0)
		_set_residue_alpha(visual_root, WETNESS_KIND, 0.0)
		return
	_set_residue_alpha(visual_root, MUD_KIND, float(contamination.get("mud")) * GameConfig.vehicle_residue_mud_visual_alpha)
	_set_residue_alpha(visual_root, DUST_KIND, float(contamination.get("dust")) * GameConfig.vehicle_residue_dust_visual_alpha)
	_set_residue_alpha(visual_root, WETNESS_KIND, float(contamination.get("wetness")) * GameConfig.vehicle_residue_wetness_visual_alpha)


func _ensure_tire_overlays(visual_root: Node) -> void:
	for socket_name in WHEEL_SOCKET_NAMES:
		var socket: Node3D = visual_root.get_node_or_null(socket_name) as Node3D
		if socket == null:
			continue
		var side_sign: float = -1.0 if socket_name.ends_with("_left") else 1.0
		_ensure_overlay(
			socket,
			MUD_TIRE_OVERLAY_NAME,
			MUD_KIND,
			Vector3(0.021 * side_sign, 0.0, 0.0),
			Vector3(0.003, 0.067, 0.067),
			GameConfig.vehicle_residue_mud_color,
			GameConfig.vehicle_residue_mud_visual_alpha * 0.82,
			0.9,
			MudTireMask
		)
		_ensure_overlay(
			socket,
			DUST_TIRE_OVERLAY_NAME,
			DUST_KIND,
			Vector3(0.024 * side_sign, 0.0, 0.0),
			Vector3(0.003, 0.07, 0.07),
			GameConfig.vehicle_residue_dust_color,
			GameConfig.vehicle_residue_dust_visual_alpha * 0.9,
			0.96,
			DustTireMask
		)
		_ensure_overlay(
			socket,
			WETNESS_TIRE_OVERLAY_NAME,
			WETNESS_KIND,
			Vector3(0.027 * side_sign, 0.0, 0.0),
			Vector3(0.003, 0.064, 0.064),
			GameConfig.vehicle_residue_wetness_color,
			GameConfig.vehicle_residue_wetness_visual_alpha * 0.7,
			0.12,
			WetnessTireMask
		)


func _ensure_overlay(parent: Node, overlay_name: String, residue_kind: String, local_position: Vector3, size: Vector3, color: Color, max_alpha: float, roughness: float, albedo_texture: Texture2D) -> void:
	if parent.get_node_or_null(overlay_name) != null:
		return
	var overlay: MeshInstance3D = MeshInstance3D.new()
	overlay.name = overlay_name
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	overlay.mesh = mesh
	overlay.position = local_position
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.resource_name = overlay_name + "_material"
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(color.r, color.g, color.b, 0.0)
	material.albedo_texture = albedo_texture
	material.roughness = roughness
	material.metallic = 0.0
	overlay.material_override = material
	overlay.visible = false
	overlay.set_meta(MAX_ALPHA_META, max_alpha)
	overlay.set_meta(RESIDUE_KIND_META, residue_kind)
	parent.add_child(overlay)


func _set_residue_alpha(parent: Node, residue_kind: String, alpha: float) -> void:
	for child in parent.get_children():
		var overlay: MeshInstance3D = child as MeshInstance3D
		if overlay != null and String(overlay.get_meta(RESIDUE_KIND_META, "")) == residue_kind:
			_set_overlay_alpha(overlay, alpha)
		_set_residue_alpha(child, residue_kind, alpha)


func _set_overlay_alpha(overlay: MeshInstance3D, alpha: float) -> void:
	var material: StandardMaterial3D = overlay.material_override as StandardMaterial3D
	if material == null:
		return
	var color: Color = material.albedo_color
	color.a = clampf(alpha, 0.0, float(overlay.get_meta(MAX_ALPHA_META, 1.0)))
	material.albedo_color = color
	overlay.visible = color.a > GameConfig.vehicle_residue_visible_epsilon
