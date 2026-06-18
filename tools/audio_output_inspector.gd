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
const MAX_QUIET_LAYER_PEAK_ABS: float = 0.09
const MIN_WATER_PAN_BALANCE: float = 0.08
const MIN_WATER_REVERB_PAN_RETENTION: float = 0.6
const AMBIENT_BUS_TEST_DB: float = -12.0
const MAX_AMBIENT_BUS_DUCK_RATIO: float = 0.35
const REVERB_TEST_WET: float = 0.8
const MIN_REVERB_RMS_RATIO: float = 1.02
const IDLE_SPEED: float = 0.0
const LOW_MOTOR_RPM: float = 120.0
const HIGH_MOTOR_RPM: float = 760.0
const MIN_RPM_MOTOR_RATIO: float = 1.35
const MAX_IDLE_TIRE_MEAN_ABS: float = 0.0005
const MIN_GRAVEL_TO_PAVED_TIRE_RATIO: float = 1.25

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
	_require_quiet_peak_targets(creek_center_stats)
	var far_position: Vector3 = GameConfig.audio_water_center + Vector3(GameConfig.audio_water_audible_radius * 2.0, 0.0, 0.0)
	var far_dirt_stats: Dictionary = _preview(MOVING_SPEED, far_position, &"packed_dirt")
	_require_layer_below(far_dirt_stats, "water", MAX_SILENT_MEAN_ABS)
	_require_layer_below(far_dirt_stats, "plank", MAX_SILENT_MEAN_ABS)
	_require_mix_controls(far_dirt_stats, far_position)
	_require_engine_and_surface_controls(far_position)
	_require_water_spatial_pan()
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


func _preview_with_motor_rpm(speed: float, motor_rpm: float, vehicle_position: Vector3, surface_id: StringName) -> Dictionary:
	return _audio_rig.call("preview_audio_output_stats_with_motor_rpm", speed, motor_rpm, vehicle_position, surface_id, FRAME_COUNT)


func _preview_with_mix_overrides(speed: float, vehicle_position: Vector3, surface_id: StringName, master_volume_db: float, ambient_volume_db: float, reverb_wet: float) -> Dictionary:
	return _audio_rig.call("preview_audio_output_stats_with_mix_overrides", speed, vehicle_position, surface_id, FRAME_COUNT, master_volume_db, ambient_volume_db, reverb_wet)


func _preview_reverb_off(speed: float, vehicle_position: Vector3, surface_id: StringName) -> Dictionary:
	# Shipped mix bus gains, reverb forced off — isolates the dry/direct spatial pan.
	return _preview_with_mix_overrides(speed, vehicle_position, surface_id, GameConfig.audio_bus_master_volume_db, GameConfig.audio_bus_ambient_volume_db, 0.0)


func _require_quiet_peak_targets(stats: Dictionary) -> void:
	for layer_name in ["motor", "tire", "ambient", "water", "plank"]:
		var max_abs: float = _max_abs(stats, layer_name)
		if max_abs > MAX_QUIET_LAYER_PEAK_ABS:
			_errors.append(layer_name + " audio peak " + str(max_abs) + " exceeds quiet target " + str(MAX_QUIET_LAYER_PEAK_ABS))


func _require_mix_controls(base_stats: Dictionary, vehicle_position: Vector3) -> void:
	var bus_duck_stats: Dictionary = _preview_with_mix_overrides(MOVING_SPEED, vehicle_position, &"packed_dirt", 0.0, AMBIENT_BUS_TEST_DB, 0.0)
	var base_ambient: float = _mean_abs(base_stats, "ambient")
	var ducked_ambient: float = _mean_abs(bus_duck_stats, "ambient")
	if base_ambient <= 0.0:
		_errors.append("ambient audio should produce measurable output before bus duck test")
	elif ducked_ambient / base_ambient > MAX_AMBIENT_BUS_DUCK_RATIO:
		_errors.append("ambient bus duck ratio " + str(ducked_ambient / base_ambient) + " should be below " + str(MAX_AMBIENT_BUS_DUCK_RATIO))
	var dry_stats: Dictionary = _preview_with_mix_overrides(MOVING_SPEED, vehicle_position, &"packed_dirt", 0.0, 0.0, 0.0)
	var wet_stats: Dictionary = _preview_with_mix_overrides(MOVING_SPEED, vehicle_position, &"packed_dirt", 0.0, 0.0, REVERB_TEST_WET)
	var dry_rms: float = _rms(dry_stats, "ambient")
	var wet_rms: float = _rms(wet_stats, "ambient")
	if dry_rms <= 0.0:
		_errors.append("ambient audio should produce measurable output before reverb test")
	elif wet_rms / dry_rms < MIN_REVERB_RMS_RATIO:
		_errors.append("ambient reverb rms ratio " + str(wet_rms / dry_rms) + " should be at least " + str(MIN_REVERB_RMS_RATIO))


func _require_engine_and_surface_controls(vehicle_position: Vector3) -> void:
	var idle_stats: Dictionary = _preview_with_motor_rpm(IDLE_SPEED, LOW_MOTOR_RPM, vehicle_position, &"packed_dirt")
	_require_layer_signal(idle_stats, "ambient", MIN_AMBIENT_MEAN_ABS)
	_require_layer_below(idle_stats, "tire", MAX_IDLE_TIRE_MEAN_ABS)
	var low_rpm_stats: Dictionary = _preview_with_motor_rpm(MOVING_SPEED, LOW_MOTOR_RPM, vehicle_position, &"packed_dirt")
	var high_rpm_stats: Dictionary = _preview_with_motor_rpm(MOVING_SPEED, HIGH_MOTOR_RPM, vehicle_position, &"packed_dirt")
	var low_motor: float = _mean_abs(low_rpm_stats, "motor")
	var high_motor: float = _mean_abs(high_rpm_stats, "motor")
	if low_motor <= 0.0:
		_errors.append("low-rpm motor audio should produce measurable output")
	elif high_motor / low_motor < MIN_RPM_MOTOR_RATIO:
		_errors.append("high-rpm motor audio ratio " + str(high_motor / low_motor) + " should be at least " + str(MIN_RPM_MOTOR_RATIO))
	var paved_stats: Dictionary = _preview(MOVING_SPEED, vehicle_position, &"paved_road")
	var gravel_stats: Dictionary = _preview(MOVING_SPEED, vehicle_position, &"packed_gravel")
	var paved_tire: float = _mean_abs(paved_stats, "tire")
	var gravel_tire: float = _mean_abs(gravel_stats, "tire")
	if paved_tire <= 0.0:
		_errors.append("paved tire audio should produce measurable output")
	elif gravel_tire / paved_tire < MIN_GRAVEL_TO_PAVED_TIRE_RATIO:
		_errors.append("gravel tire audio should be louder than paved; ratio " + str(gravel_tire / paved_tire))


func _require_water_spatial_pan() -> void:
	# Spatial panning is a property of the dry/direct signal path. Canyon reverb is a
	# deliberately diffuse field that cross-feeds L/R, so it lowers the aggregate balance
	# of the full mix without moving where the creek localizes. Assert the pan logic on the
	# dry signal (reverb forced off), then separately guard that the shipped reverb level
	# still preserves most of that directional balance.
	var right_source_position: Vector3 = GameConfig.audio_water_center + Vector3(-GameConfig.audio_water_audible_radius * 0.5, 0.0, 0.0)
	var left_source_position: Vector3 = GameConfig.audio_water_center + Vector3(GameConfig.audio_water_audible_radius * 0.5, 0.0, 0.0)
	var right_dry: float = _pan_balance(_preview_reverb_off(MOVING_SPEED, right_source_position, &"packed_dirt"), "water")
	var left_dry: float = _pan_balance(_preview_reverb_off(MOVING_SPEED, left_source_position, &"packed_dirt"), "water")
	if right_dry < MIN_WATER_PAN_BALANCE:
		_errors.append("water audio should pan right when creek source is right of vehicle; dry balance " + str(right_dry))
	if left_dry > -MIN_WATER_PAN_BALANCE:
		_errors.append("water audio should pan left when creek source is left of vehicle; dry balance " + str(left_dry))
	var right_mix: float = _pan_balance(_preview(MOVING_SPEED, right_source_position, &"packed_dirt"), "water")
	var left_mix: float = _pan_balance(_preview(MOVING_SPEED, left_source_position, &"packed_dirt"), "water")
	_require_reverb_preserves_pan(right_dry, right_mix, "right")
	_require_reverb_preserves_pan(left_dry, left_mix, "left")


func _require_reverb_preserves_pan(dry_balance: float, mix_balance: float, side: String) -> void:
	if absf(dry_balance) <= 0.0:
		_errors.append("water dry pan balance should be nonzero before reverb retention check (" + side + ")")
		return
	if signf(mix_balance) != signf(dry_balance):
		_errors.append("canyon reverb should keep water " + side + " pan direction; dry " + str(dry_balance) + " shipped-mix " + str(mix_balance))
		return
	var retention: float = mix_balance / dry_balance
	if retention < MIN_WATER_REVERB_PAN_RETENTION:
		_errors.append("canyon reverb collapses water " + side + " pan; retention " + str(retention) + " below " + str(MIN_WATER_REVERB_PAN_RETENTION))


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


func _max_abs(stats: Dictionary, layer_name: String) -> float:
	var layer_stats: Dictionary = _layer_stats(stats, layer_name)
	if layer_stats.is_empty():
		return 0.0
	return float(layer_stats["max_abs"])


func _rms(stats: Dictionary, layer_name: String) -> float:
	var layer_stats: Dictionary = _layer_stats(stats, layer_name)
	if layer_stats.is_empty():
		return 0.0
	return float(layer_stats["rms"])


func _pan_balance(stats: Dictionary, layer_name: String) -> float:
	var layer_stats: Dictionary = _layer_stats(stats, layer_name)
	if layer_stats.is_empty():
		return 0.0
	if not layer_stats.has("pan_balance"):
		_errors.append(layer_name + " audio stats missing key: pan_balance")
		return 0.0
	return float(layer_stats["pan_balance"])


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
