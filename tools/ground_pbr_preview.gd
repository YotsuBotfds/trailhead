extends Node3D

const BASE_PATH: String = "res://assets/textures/surface_visuals/ground_pbr"
const REQUIRED_SIZE: int = 1024

var _asset_ids: PackedStringArray = PackedStringArray([
	"Ground080",
	"Gravel028",
	"Ground031",
	"Ground079L"
])
var _errors: PackedStringArray = PackedStringArray()


func _ready() -> void:
	call_deferred("_inspect")


func _inspect() -> void:
	for i in range(_asset_ids.size()):
		_inspect_asset(_asset_ids[i], i)
	if _errors.is_empty():
		print("ok: ground_pbr_preview loaded " + str(_asset_ids.size()) + " PBR texture sets")
		get_tree().quit(0)
		return
	for error in _errors:
		push_error(error)
	get_tree().quit(1)


func _inspect_asset(asset_id: String, index: int) -> void:
	var color_texture: Texture2D = _load_texture(asset_id, "Color")
	var normal_texture: Texture2D = _load_texture(asset_id, "NormalGL")
	var roughness_texture: Texture2D = _load_texture(asset_id, "Roughness")
	var ao_texture: Texture2D = _load_texture(asset_id, "AmbientOcclusion")
	if color_texture == null or normal_texture == null or roughness_texture == null or ao_texture == null:
		return
	_require_texture_size(asset_id, "Color", color_texture)
	_require_texture_size(asset_id, "NormalGL", normal_texture)
	_require_texture_size(asset_id, "Roughness", roughness_texture)
	_require_texture_size(asset_id, "AmbientOcclusion", ao_texture)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_texture = color_texture
	material.normal_enabled = true
	material.normal_texture = normal_texture
	material.roughness_texture = roughness_texture
	material.ao_enabled = true
	material.ao_texture = ao_texture
	var mesh: PlaneMesh = PlaneMesh.new()
	mesh.size = Vector2(2.0, 2.0)
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = asset_id + "Preview"
	instance.mesh = mesh
	instance.material_override = material
	instance.position = Vector3(float(index) * 2.4, 0.0, 0.0)
	add_child(instance)


func _load_texture(asset_id: String, map_type: String) -> Texture2D:
	var texture_path: String = BASE_PATH.path_join(asset_id).path_join(asset_id + "_1K-JPG_" + map_type + ".jpg")
	var texture: Texture2D = load(texture_path)
	if texture == null:
		_errors.append("failed to load texture: " + texture_path)
	return texture


func _require_texture_size(asset_id: String, map_type: String, texture: Texture2D) -> void:
	var width: int = texture.get_width()
	var height: int = texture.get_height()
	if width != REQUIRED_SIZE or height != REQUIRED_SIZE:
		_errors.append(asset_id + " " + map_type + " expected 1024x1024, got " + str(width) + "x" + str(height))
