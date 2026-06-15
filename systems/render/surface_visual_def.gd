class_name SurfaceVisualDef
extends Resource

const MIN_TIRE_AUDIO_GAIN: float = 0.0
const MAX_TIRE_AUDIO_GAIN: float = 2.0
const MIN_TIRE_AUDIO_PITCH: float = 0.1
const MAX_TIRE_AUDIO_PITCH: float = 3.0
const MIN_TEXTURE_UV_SCALE: float = 0.1
const MAX_TEXTURE_UV_SCALE: float = 256.0
const MIN_NORMAL_SCALE: float = 0.0
const MAX_NORMAL_SCALE: float = 4.0
const MIN_HEIGHT_SCALE: float = 0.0
const MAX_HEIGHT_SCALE: float = 0.12
const MIN_HEIGHT_LAYERS: int = 1
const MAX_HEIGHT_LAYERS: int = 64

@export var id: StringName = &""
@export var surface_id: StringName = &""
@export var display_name: String = ""
@export var default_for_surface: bool = true
@export var albedo_color: Color = Color(1.0, 1.0, 1.0)
@export_range(0.0, 1.0) var roughness: float = 0.8
@export_range(0.0, 1.0) var wetness: float = 0.0
@export_range(0.0, 2.0) var tire_audio_gain: float = 1.0
@export_range(0.1, 3.0) var tire_audio_pitch: float = 1.0
@export var emits_plank_knock: bool = false
@export_file("*.png", "*.jpg", "*.jpeg") var albedo_texture_path: String = ""
@export_file("*.png", "*.jpg", "*.jpeg") var normal_texture_path: String = ""
@export_file("*.png", "*.jpg", "*.jpeg") var detail_albedo_texture_path: String = ""
@export_file("*.png", "*.jpg", "*.jpeg") var detail_normal_texture_path: String = ""
@export_file("*.png", "*.jpg", "*.jpeg") var height_texture_path: String = ""
@export var texture_uv_scale: Vector2 = Vector2(8.0, 8.0)
@export var detail_uv_scale: Vector2 = Vector2(32.0, 32.0)
@export var triplanar: bool = false
@export_range(0.0, 4.0) var normal_scale: float = 1.0
@export var heightmap_enabled: bool = false
@export_range(0.0, 0.12) var height_scale: float = 0.0
@export_range(1, 64, 1) var height_min_layers: int = 8
@export_range(1, 64, 1) var height_max_layers: int = 24


func validate(resource_label: String = "") -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	var label: String = resource_label
	if label.is_empty():
		label = String(id)
	if id == &"":
		errors.append(label + " id is empty")
	if surface_id == &"":
		errors.append(label + " surface_id is empty")
	if display_name.strip_edges().is_empty():
		errors.append(label + " display_name is empty")
	_require_float_range(roughness, 0.0, 1.0, label + " roughness", errors)
	_require_float_range(wetness, 0.0, 1.0, label + " wetness", errors)
	_require_float_range(tire_audio_gain, MIN_TIRE_AUDIO_GAIN, MAX_TIRE_AUDIO_GAIN, label + " tire_audio_gain", errors)
	_require_float_range(tire_audio_pitch, MIN_TIRE_AUDIO_PITCH, MAX_TIRE_AUDIO_PITCH, label + " tire_audio_pitch", errors)
	_require_texture_path(albedo_texture_path, label + " albedo_texture_path", errors)
	_require_texture_path(normal_texture_path, label + " normal_texture_path", errors)
	_require_texture_path(detail_albedo_texture_path, label + " detail_albedo_texture_path", errors)
	_require_texture_path(detail_normal_texture_path, label + " detail_normal_texture_path", errors)
	_require_texture_path(height_texture_path, label + " height_texture_path", errors)
	_require_float_range(texture_uv_scale.x, MIN_TEXTURE_UV_SCALE, MAX_TEXTURE_UV_SCALE, label + " texture_uv_scale.x", errors)
	_require_float_range(texture_uv_scale.y, MIN_TEXTURE_UV_SCALE, MAX_TEXTURE_UV_SCALE, label + " texture_uv_scale.y", errors)
	_require_float_range(detail_uv_scale.x, MIN_TEXTURE_UV_SCALE, MAX_TEXTURE_UV_SCALE, label + " detail_uv_scale.x", errors)
	_require_float_range(detail_uv_scale.y, MIN_TEXTURE_UV_SCALE, MAX_TEXTURE_UV_SCALE, label + " detail_uv_scale.y", errors)
	_require_float_range(normal_scale, MIN_NORMAL_SCALE, MAX_NORMAL_SCALE, label + " normal_scale", errors)
	_require_float_range(height_scale, MIN_HEIGHT_SCALE, MAX_HEIGHT_SCALE, label + " height_scale", errors)
	_require_int_range(height_min_layers, MIN_HEIGHT_LAYERS, MAX_HEIGHT_LAYERS, label + " height_min_layers", errors)
	_require_int_range(height_max_layers, MIN_HEIGHT_LAYERS, MAX_HEIGHT_LAYERS, label + " height_max_layers", errors)
	if height_min_layers > height_max_layers:
		errors.append(label + " height_min_layers should be <= height_max_layers")
	return errors


func _require_float_range(value: float, min_value: float, max_value: float, label: String, errors: PackedStringArray) -> void:
	if value < min_value or value > max_value:
		errors.append(label + " expected range " + str(min_value) + ".." + str(max_value) + ", got " + str(value))


func _require_int_range(value: int, min_value: int, max_value: int, label: String, errors: PackedStringArray) -> void:
	if value < min_value or value > max_value:
		errors.append(label + " expected range " + str(min_value) + ".." + str(max_value) + ", got " + str(value))


func _require_texture_path(path: String, label: String, errors: PackedStringArray) -> void:
	if path.is_empty():
		return
	if not path.begins_with("res://"):
		errors.append(label + " should be a res:// path, got " + path)
		return
	if not ResourceLoader.exists(path):
		errors.append(label + " does not exist: " + path)
