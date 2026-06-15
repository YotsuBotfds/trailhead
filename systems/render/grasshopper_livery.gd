class_name GrasshopperLivery
extends Node

const CORRECT_CODE: String = "2401"
const GRASSHOPPER_UNLOCK_META: StringName = &"grasshopper_unlocked"
const GRASSHOPPER_LIVERY_META: StringName = &"grasshopper_livery_applied"
const CHASSIS_MESH_PATHS: Array[String] = [
	"body",
	"nose",
	"top_deck",
	"side_panel_left",
	"side_panel_right",
	"canopy",
	"rear_wing/wing_panel",
	"body_stripe",
	"fender_flares",
	"fender_lips",
	"side_number_plates",
	"side_number_marks",
	"body_vents"
]
const GRASSHOPPER_ORANGE: Color = Color(1.0, 0.34, 0.06, 1.0)
const GRASSHOPPER_CREAM: Color = Color(0.98, 0.91, 0.72, 1.0)
const GRASSHOPPER_BLACK: Color = Color(0.035, 0.032, 0.028, 1.0)

var _visual_root: Node = null
var _grasshopper_unlocked: bool = false
var _applied_mesh_count: int = 0


func configure(visual_root: Node) -> void:
	_visual_root = visual_root
	if _grasshopper_unlocked:
		_apply_livery()


func try_unlock_with_code(code: String) -> bool:
	if code != CORRECT_CODE:
		return false
	_grasshopper_unlocked = true
	set_meta(GRASSHOPPER_UNLOCK_META, true)
	_apply_livery()
	return true


func grasshopper_unlocked() -> bool:
	return _grasshopper_unlocked


func applied_mesh_count() -> int:
	return _applied_mesh_count


func _apply_livery() -> void:
	_applied_mesh_count = 0
	if _visual_root == null:
		return
	for path_index: int in range(CHASSIS_MESH_PATHS.size()):
		var mesh_instance: MeshInstance3D = _visual_root.get_node_or_null(CHASSIS_MESH_PATHS[path_index]) as MeshInstance3D
		if mesh_instance == null:
			continue
		mesh_instance.material_override = _make_livery_material(String(mesh_instance.name), path_index)
		mesh_instance.set_meta(GRASSHOPPER_LIVERY_META, true)
		_applied_mesh_count += 1


func _make_livery_material(mesh_name: String, path_index: int) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.resource_name = "grasshopper_livery_" + mesh_name
	if mesh_name.contains("stripe") or mesh_name.contains("number"):
		material.albedo_color = GRASSHOPPER_CREAM
	elif path_index % 5 == 0:
		material.albedo_color = GRASSHOPPER_BLACK
	else:
		material.albedo_color = GRASSHOPPER_ORANGE
	material.roughness = 0.46
	material.metallic = 0.0
	material.clearcoat_enabled = true
	material.clearcoat = 0.35
	material.clearcoat_roughness = 0.42
	return material
