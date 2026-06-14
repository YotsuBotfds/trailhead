class_name VehicleResidueVisual
extends RefCounted

const MUD_OVERLAY_NAME: String = "residue_mud_overlay"
const DUST_OVERLAY_NAME: String = "residue_dust_overlay"
const WETNESS_OVERLAY_NAME: String = "residue_wetness_overlay"


func attach(visual_root: Node) -> void:
	if visual_root == null:
		return
	_ensure_overlay(
		visual_root,
		MUD_OVERLAY_NAME,
		Vector3(0.0, 0.018, 0.01),
		Vector3(0.17, 0.006, 0.22),
		GameConfig.vehicle_residue_mud_color,
		GameConfig.vehicle_residue_mud_visual_alpha,
		0.92
	)
	_ensure_overlay(
		visual_root,
		DUST_OVERLAY_NAME,
		Vector3(0.0, 0.021, 0.0),
		Vector3(0.19, 0.004, 0.24),
		GameConfig.vehicle_residue_dust_color,
		GameConfig.vehicle_residue_dust_visual_alpha,
		0.96
	)
	_ensure_overlay(
		visual_root,
		WETNESS_OVERLAY_NAME,
		Vector3(0.0, 0.024, -0.01),
		Vector3(0.15, 0.003, 0.20),
		GameConfig.vehicle_residue_wetness_color,
		GameConfig.vehicle_residue_wetness_visual_alpha,
		0.18
	)


func apply_state(visual_root: Node, state: RefCounted) -> void:
	if visual_root == null or state == null:
		return
	var contamination: RefCounted = state.get("contamination") as RefCounted
	if contamination == null:
		_set_overlay_alpha(visual_root, MUD_OVERLAY_NAME, 0.0)
		_set_overlay_alpha(visual_root, DUST_OVERLAY_NAME, 0.0)
		_set_overlay_alpha(visual_root, WETNESS_OVERLAY_NAME, 0.0)
		return
	_set_overlay_alpha(visual_root, MUD_OVERLAY_NAME, float(contamination.get("mud")) * GameConfig.vehicle_residue_mud_visual_alpha)
	_set_overlay_alpha(visual_root, DUST_OVERLAY_NAME, float(contamination.get("dust")) * GameConfig.vehicle_residue_dust_visual_alpha)
	_set_overlay_alpha(visual_root, WETNESS_OVERLAY_NAME, float(contamination.get("wetness")) * GameConfig.vehicle_residue_wetness_visual_alpha)


func _ensure_overlay(visual_root: Node, overlay_name: String, local_position: Vector3, size: Vector3, color: Color, max_alpha: float, roughness: float) -> void:
	if visual_root.get_node_or_null(overlay_name) != null:
		return
	var overlay: MeshInstance3D = MeshInstance3D.new()
	overlay.name = overlay_name
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	overlay.mesh = mesh
	overlay.position = local_position
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(color.r, color.g, color.b, 0.0)
	material.roughness = roughness
	overlay.material_override = material
	overlay.visible = false
	overlay.set_meta("max_alpha", max_alpha)
	visual_root.add_child(overlay)


func _set_overlay_alpha(visual_root: Node, overlay_name: String, alpha: float) -> void:
	var overlay: MeshInstance3D = visual_root.get_node_or_null(overlay_name) as MeshInstance3D
	if overlay == null:
		return
	var material: StandardMaterial3D = overlay.material_override as StandardMaterial3D
	if material == null:
		return
	var color: Color = material.albedo_color
	color.a = clampf(alpha, 0.0, float(overlay.get_meta("max_alpha", 1.0)))
	material.albedo_color = color
	overlay.visible = color.a > GameConfig.vehicle_residue_visible_epsilon
