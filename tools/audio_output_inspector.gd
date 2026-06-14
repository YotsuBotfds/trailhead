extends Node

const CedarAudioRigScript: GDScript = preload("res://systems/render/cedar_audio_rig.gd")
const FRAME_COUNT: int = 4096
const MOVING_SPEED: float = 3.0
const MIN_MOTOR_MEAN_ABS: float = 0.015
const MIN_TIRE_MEAN_ABS: float = 0.006
const MIN_AMBIENT_MEAN_ABS: float = 0.004
const MIN_WATER_MEAN_ABS: float = 0.006
const MIN_PLANK_MEAN_ABS: float = 0.001
const MAX_SILENT_MEAN_ABS: float = 0.0001
const MIN_MUD_TO_GRASS_TIRE_RATIO: float = 1.8

var _audio_rig: Node = null
var _errors: PackedStringArray = PackedStringArray()


func _ready() -> void:
	_audio_rig = CedarAudioRigScript.new()
	add_child(_audio_rig)
	call_deferred("_run")


func _run() -> void:
	if _audio_rig == null:
		_errors.append("failed to instantiate CedarAudioRig")
		await _finish()
		return
	_inspect_output_stats()
	await _finish()


func _inspect_output_stats() -> void:
	var creek_center_stats: Dictionary = _preview(MOVING_SPEED, GameConfig.audio_water_center, &"packed_dirt")
	_require_layer_signal(creek_center_stats, "motor", MIN_MOTOR_MEAN_ABS)
	_require_layer_signal(creek_center_stats, "tire", MIN_TIRE_MEAN_ABS)
	_require_layer_signal(creek_center_stats, "ambient", MIN_AMBIENT_MEAN_ABS)
	_require_layer_signal(creek_center_stats, "water", MIN_WATER_MEAN_ABS)
	var far_position: Vector3 = GameConfig.audio_water_center + Vector3(GameConfig.audio_water_audible_radius * 2.0, 0.0, 0.0)
	var far_dirt_stats: Dictionary = _preview(MOVING_SPEED, far_position, &"packed_dirt")
	_require_layer_below(far_dirt_stats, "water", MAX_SILENT_MEAN_ABS)
	_require_layer_below(far_dirt_stats, "plank", MAX_SILENT_MEAN_ABS)
	var wood_stats: Dictionary = _preview(MOVING_SPEED, far_position, &"wood_plank")
	_require_layer_signal(wood_stats, "plank", MIN_PLANK_MEAN_ABS)
	var grass_stats: Dictionary = _preview(MOVING_SPEED, far_position, &"tall_grass")
	var mud_stats: Dictionary = _preview(MOVING_SPEED, far_position, &"mud")
	var grass_tire: float = _mean_abs(grass_stats, "tire")
	var mud_tire: float = _mean_abs(mud_stats, "tire")
	if grass_tire <= 0.0:
		_errors.append("grass tire audio should produce measurable output")
	elif mud_tire / grass_tire < MIN_MUD_TO_GRASS_TIRE_RATIO:
		_errors.append("mud tire audio should be louder than grass; ratio " + str(mud_tire / grass_tire))


func _preview(speed: float, vehicle_position: Vector3, surface_id: StringName) -> Dictionary:
	return _audio_rig.call("preview_audio_output_stats", speed, vehicle_position, surface_id, FRAME_COUNT)


func _require_layer_signal(stats: Dictionary, layer_name: String, min_mean_abs: float) -> void:
	var layer_stats: Dictionary = _layer_stats(stats, layer_name)
	if layer_stats.is_empty():
		return
	var sample_count: int = int(layer_stats["sample_count"])
	var mean_abs: float = float(layer_stats["mean_abs"])
	var max_abs: float = float(layer_stats["max_abs"])
	var rms: float = float(layer_stats["rms"])
	if sample_count != FRAME_COUNT:
		_errors.append(layer_name + " audio sample count expected " + str(FRAME_COUNT) + ", got " + str(sample_count))
	if mean_abs < min_mean_abs:
		_errors.append(layer_name + " audio mean_abs " + str(mean_abs) + " below " + str(min_mean_abs))
	if max_abs <= 0.0:
		_errors.append(layer_name + " audio max_abs should be nonzero")
	if rms <= 0.0:
		_errors.append(layer_name + " audio rms should be nonzero")


func _require_layer_below(stats: Dictionary, layer_name: String, max_mean_abs: float) -> void:
	var layer_stats: Dictionary = _layer_stats(stats, layer_name)
	if layer_stats.is_empty():
		return
	var mean_abs: float = float(layer_stats["mean_abs"])
	if mean_abs > max_mean_abs:
		_errors.append(layer_name + " audio mean_abs " + str(mean_abs) + " should be below " + str(max_mean_abs))


func _mean_abs(stats: Dictionary, layer_name: String) -> float:
	var layer_stats: Dictionary = _layer_stats(stats, layer_name)
	if layer_stats.is_empty():
		return 0.0
	return float(layer_stats["mean_abs"])


func _layer_stats(stats: Dictionary, layer_name: String) -> Dictionary:
	if not stats.has(layer_name):
		_errors.append("audio preview is missing layer: " + layer_name)
		return {}
	var layer_stats: Dictionary = stats[layer_name]
	for key in ["sample_count", "mean_abs", "max_abs", "rms"]:
		if not layer_stats.has(key):
			_errors.append(layer_name + " audio stats missing key: " + key)
	return layer_stats


func _finish() -> void:
	if _errors.size() > 0:
		for error in _errors:
			push_error(error)
		get_tree().quit(1)
		return
	print("ok: Cedar audio output preview produces nonzero and reactive layer stats")
	get_tree().quit(0)
