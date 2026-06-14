class_name SurfaceVisualDef
extends Resource

const MIN_TIRE_AUDIO_GAIN: float = 0.0
const MAX_TIRE_AUDIO_GAIN: float = 2.0
const MIN_TIRE_AUDIO_PITCH: float = 0.1
const MAX_TIRE_AUDIO_PITCH: float = 3.0

@export var id: StringName = &""
@export var surface_id: StringName = &""
@export var display_name: String = ""
@export var default_for_surface: bool = true
@export var albedo_color: Color = Color(1.0, 1.0, 1.0)
@export_range(0.0, 1.0) var roughness: float = 0.8
@export_range(0.0, 2.0) var tire_audio_gain: float = 1.0
@export_range(0.1, 3.0) var tire_audio_pitch: float = 1.0
@export var emits_plank_knock: bool = false
@export_file("*.png") var albedo_texture_path: String = ""
@export_file("*.png") var normal_texture_path: String = ""
@export_file("*.png") var orm_texture_path: String = ""


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
	_require_float_range(tire_audio_gain, MIN_TIRE_AUDIO_GAIN, MAX_TIRE_AUDIO_GAIN, label + " tire_audio_gain", errors)
	_require_float_range(tire_audio_pitch, MIN_TIRE_AUDIO_PITCH, MAX_TIRE_AUDIO_PITCH, label + " tire_audio_pitch", errors)
	_require_texture_path(albedo_texture_path, label + " albedo_texture_path", errors)
	_require_texture_path(normal_texture_path, label + " normal_texture_path", errors)
	_require_texture_path(orm_texture_path, label + " orm_texture_path", errors)
	return errors


func _require_float_range(value: float, min_value: float, max_value: float, label: String, errors: PackedStringArray) -> void:
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
