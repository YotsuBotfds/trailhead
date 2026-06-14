class_name CedarAudioRig
extends Node

const AUDIO_SURFACE_IDS: Array[StringName] = [
	&"packed_gravel",
	&"packed_dirt",
	&"tall_grass",
	&"mud",
	&"loose_rock",
	&"wet_stone",
	&"wood_plank"
]

var _vehicle: Node = null
var _motor_player: AudioStreamPlayer = null
var _tire_player: AudioStreamPlayer = null
var _ambient_player: AudioStreamPlayer = null
var _water_player: AudioStreamPlayer = null
var _plank_player: AudioStreamPlayer = null
var _motor_playback: AudioStreamGeneratorPlayback = null
var _tire_playback: AudioStreamGeneratorPlayback = null
var _ambient_playback: AudioStreamGeneratorPlayback = null
var _water_playback: AudioStreamGeneratorPlayback = null
var _plank_playback: AudioStreamGeneratorPlayback = null
var _motor_phase: float = 0.0
var _tire_phase: float = 0.0
var _ambient_phase: float = 0.0
var _bird_phase: float = 0.0
var _water_phase: float = 0.0
var _plank_phase: float = 0.0
var _plank_envelope: float = 0.0
var _noise_state: int = 17
var _ambient_noise_state: int = 43
var _water_noise_state: int = 89
var _current_surface_id: StringName = &"packed_dirt"


func configure(vehicle: Node) -> void:
	_vehicle = vehicle


func _ready() -> void:
	_motor_player = _make_generator_player("MotorWhine")
	_tire_player = _make_generator_player("TireTexture")
	_ambient_player = _make_generator_player("AmbientBed")
	_water_player = _make_generator_player("CreekBed")
	_plank_player = _make_generator_player("PlankKnock")
	EventBus.vehicle_changed_surface.connect(_on_vehicle_changed_surface)
	if DisplayServer.get_name() != "headless":
		call_deferred("_start_players")


func _exit_tree() -> void:
	if EventBus.vehicle_changed_surface.is_connected(_on_vehicle_changed_surface):
		EventBus.vehicle_changed_surface.disconnect(_on_vehicle_changed_surface)
	_stop_player(_motor_player)
	_stop_player(_tire_player)
	_stop_player(_ambient_player)
	_stop_player(_water_player)
	_stop_player(_plank_player)
	_motor_playback = null
	_tire_playback = null
	_ambient_playback = null
	_water_playback = null
	_plank_playback = null


func _process(_delta: float) -> void:
	if _vehicle == null:
		return
	var state: RefCounted = _vehicle.call("get_state")
	var speed: float = float(state.call("speed"))
	var vehicle_position: Vector3 = state.get("position")
	_fill_motor(speed)
	_fill_tires(speed)
	_fill_ambient()
	_fill_water(vehicle_position)
	_fill_planks(speed)


func preview_audio_output_stats(speed: float, vehicle_position: Vector3, surface_id: StringName, frame_count: int) -> Dictionary:
	var previous_surface_id: StringName = _current_surface_id
	var previous_motor_phase: float = _motor_phase
	var previous_tire_phase: float = _tire_phase
	var previous_ambient_phase: float = _ambient_phase
	var previous_bird_phase: float = _bird_phase
	var previous_water_phase: float = _water_phase
	var previous_plank_phase: float = _plank_phase
	var previous_plank_envelope: float = _plank_envelope
	var previous_noise_state: int = _noise_state
	var previous_ambient_noise_state: int = _ambient_noise_state
	var previous_water_noise_state: int = _water_noise_state
	_current_surface_id = surface_id
	var motor_stats: Dictionary = _new_audio_stats()
	var tire_stats: Dictionary = _new_audio_stats()
	var ambient_stats: Dictionary = _new_audio_stats()
	var water_stats: Dictionary = _new_audio_stats()
	var plank_stats: Dictionary = _new_audio_stats()
	for _i in range(maxi(frame_count, 0)):
		_record_audio_sample(motor_stats, _next_motor_sample(speed))
		_record_audio_sample(tire_stats, _next_tire_sample(speed))
		_record_audio_sample(ambient_stats, _next_ambient_sample())
		_record_audio_sample(water_stats, _next_water_sample(vehicle_position))
		_record_audio_sample(plank_stats, _next_plank_sample(speed))
	_current_surface_id = previous_surface_id
	_motor_phase = previous_motor_phase
	_tire_phase = previous_tire_phase
	_ambient_phase = previous_ambient_phase
	_bird_phase = previous_bird_phase
	_water_phase = previous_water_phase
	_plank_phase = previous_plank_phase
	_plank_envelope = previous_plank_envelope
	_noise_state = previous_noise_state
	_ambient_noise_state = previous_ambient_noise_state
	_water_noise_state = previous_water_noise_state
	return {
		"motor": _finalize_audio_stats(motor_stats),
		"tire": _finalize_audio_stats(tire_stats),
		"ambient": _finalize_audio_stats(ambient_stats),
		"water": _finalize_audio_stats(water_stats),
		"plank": _finalize_audio_stats(plank_stats),
	}


func _make_generator_player(player_name: String) -> AudioStreamPlayer:
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.name = player_name
	var stream: AudioStreamGenerator = AudioStreamGenerator.new()
	stream.mix_rate = GameConfig.audio_mix_rate
	stream.buffer_length = GameConfig.audio_buffer_length
	player.stream = stream
	add_child(player)
	return player


func _stop_player(player: AudioStreamPlayer) -> void:
	if player == null:
		return
	player.stop()
	player.stream = null


func _start_players() -> void:
	if _motor_player != null:
		_motor_player.play()
		_motor_playback = _motor_player.get_stream_playback() as AudioStreamGeneratorPlayback
	if _tire_player != null:
		_tire_player.play()
		_tire_playback = _tire_player.get_stream_playback() as AudioStreamGeneratorPlayback
	if _ambient_player != null:
		_ambient_player.play()
		_ambient_playback = _ambient_player.get_stream_playback() as AudioStreamGeneratorPlayback
	if _water_player != null:
		_water_player.play()
		_water_playback = _water_player.get_stream_playback() as AudioStreamGeneratorPlayback
	if _plank_player != null:
		_plank_player.play()
		_plank_playback = _plank_player.get_stream_playback() as AudioStreamGeneratorPlayback


func _fill_motor(speed: float) -> void:
	if _motor_playback == null:
		return
	var frames_available: int = _motor_playback.get_frames_available()
	for i in range(frames_available):
		var sample: float = _next_motor_sample(speed)
		_motor_playback.push_frame(Vector2(sample, sample))


func _fill_tires(speed: float) -> void:
	if _tire_playback == null:
		return
	var frames_available: int = _tire_playback.get_frames_available()
	for i in range(frames_available):
		var sample: float = _next_tire_sample(speed)
		_tire_playback.push_frame(Vector2(sample, sample))


func _fill_ambient() -> void:
	if _ambient_playback == null:
		return
	var frames_available: int = _ambient_playback.get_frames_available()
	for i in range(frames_available):
		var sample: float = _next_ambient_sample()
		_ambient_playback.push_frame(Vector2(sample, sample))


func _fill_water(vehicle_position: Vector3) -> void:
	if _water_playback == null:
		return
	var frames_available: int = _water_playback.get_frames_available()
	for i in range(frames_available):
		var sample: float = _next_water_sample(vehicle_position)
		_water_playback.push_frame(Vector2(sample, sample))


func _fill_planks(speed: float) -> void:
	if _plank_playback == null:
		return
	var frames_available: int = _plank_playback.get_frames_available()
	for i in range(frames_available):
		var sample: float = _next_plank_sample(speed)
		_plank_playback.push_frame(Vector2(sample, sample))


func _next_motor_sample(speed: float) -> float:
	var frequency: float = GameConfig.audio_motor_base_hz + speed * GameConfig.audio_motor_speed_hz_gain
	var phase_step: float = TAU * frequency / maxf(GameConfig.audio_mix_rate, 1.0)
	_motor_phase += phase_step
	if _motor_phase > TAU:
		_motor_phase -= TAU
	return sin(_motor_phase) * GameConfig.audio_motor_volume


func _next_tire_sample(speed: float) -> float:
	var frequency: float = GameConfig.audio_tire_base_hz * surface_tire_pitch_for(_current_surface_id)
	var phase_step: float = TAU * frequency / maxf(GameConfig.audio_mix_rate, 1.0)
	var volume: float = (GameConfig.audio_tire_volume + speed * GameConfig.audio_tire_speed_volume_gain) * surface_tire_gain_for(_current_surface_id)
	_tire_phase += phase_step
	if _tire_phase > TAU:
		_tire_phase -= TAU
	var wave: float = sin(_tire_phase) * 0.65 + _next_noise() * 0.35
	return wave * volume


func _next_ambient_sample() -> float:
	var wind_step: float = TAU * GameConfig.audio_ambient_wind_base_hz / maxf(GameConfig.audio_mix_rate, 1.0)
	var bird_step: float = TAU * GameConfig.audio_ambient_bird_hz / maxf(GameConfig.audio_mix_rate, 1.0)
	_ambient_phase += wind_step
	_bird_phase += bird_step
	if _ambient_phase > TAU:
		_ambient_phase -= TAU
	if _bird_phase > TAU:
		_bird_phase -= TAU
	var wind: float = (sin(_ambient_phase) * 0.35 + _next_ambient_noise() * 0.65) * GameConfig.audio_ambient_wind_volume
	var bird_gate: float = 1.0 if _ambient_noise_state % 991 > 982 else 0.0
	var bird: float = sin(_bird_phase) * bird_gate * GameConfig.audio_ambient_bird_volume
	return wind + bird


func _next_water_sample(vehicle_position: Vector3) -> float:
	var volume: float = water_volume_for_position(vehicle_position)
	var phase_step: float = TAU * GameConfig.audio_water_base_hz / maxf(GameConfig.audio_mix_rate, 1.0)
	_water_phase += phase_step
	if _water_phase > TAU:
		_water_phase -= TAU
	var stream_noise: float = _next_water_noise() * 0.75 + sin(_water_phase) * 0.25
	return stream_noise * volume


func _next_plank_sample(speed: float) -> float:
	var is_on_plank: bool = _current_surface_id == &"wood_plank"
	var frequency: float = GameConfig.audio_plank_base_hz + speed * GameConfig.audio_plank_speed_hz_gain
	var phase_step: float = TAU * frequency / maxf(GameConfig.audio_mix_rate, 1.0)
	if is_on_plank:
		_plank_phase += phase_step
		if _plank_phase > TAU:
			_plank_phase -= TAU
			_plank_envelope = 1.0
	_plank_envelope *= GameConfig.audio_plank_decay
	return sin(_plank_phase * 5.0) * _plank_envelope * GameConfig.audio_plank_volume


func _new_audio_stats() -> Dictionary:
	return {
		"sample_count": 0,
		"max_abs": 0.0,
		"abs_sum": 0.0,
		"square_sum": 0.0,
		"mean_abs": 0.0,
		"rms": 0.0,
	}


func _record_audio_sample(stats: Dictionary, sample: float) -> void:
	var abs_sample: float = absf(sample)
	stats["sample_count"] = int(stats["sample_count"]) + 1
	stats["max_abs"] = maxf(float(stats["max_abs"]), abs_sample)
	stats["abs_sum"] = float(stats["abs_sum"]) + abs_sample
	stats["square_sum"] = float(stats["square_sum"]) + sample * sample


func _finalize_audio_stats(stats: Dictionary) -> Dictionary:
	var sample_count: int = int(stats["sample_count"])
	if sample_count > 0:
		var count_float: float = float(sample_count)
		stats["mean_abs"] = float(stats["abs_sum"]) / count_float
		stats["rms"] = sqrt(float(stats["square_sum"]) / count_float)
	return stats


func _next_noise() -> float:
	_noise_state = int((_noise_state * 1103515245 + 12345) & 0x7fffffff)
	return float(_noise_state % 2000) / 1000.0 - 1.0


func _next_ambient_noise() -> float:
	_ambient_noise_state = int((_ambient_noise_state * 1103515245 + 12345) & 0x7fffffff)
	return float(_ambient_noise_state % 2000) / 1000.0 - 1.0


func _next_water_noise() -> float:
	_water_noise_state = int((_water_noise_state * 1103515245 + 12345) & 0x7fffffff)
	return float(_water_noise_state % 2000) / 1000.0 - 1.0


func surface_tire_gain_for(surface_id: StringName) -> float:
	if surface_id == &"packed_gravel":
		return GameConfig.audio_tire_gain_gravel
	if surface_id == &"packed_dirt":
		return GameConfig.audio_tire_gain_dirt
	if surface_id == &"tall_grass":
		return GameConfig.audio_tire_gain_grass
	if surface_id == &"mud":
		return GameConfig.audio_tire_gain_mud
	if surface_id == &"loose_rock":
		return GameConfig.audio_tire_gain_rock
	if surface_id == &"wet_stone":
		return GameConfig.audio_tire_gain_stone
	if surface_id == &"wood_plank":
		return GameConfig.audio_tire_gain_wood
	return GameConfig.audio_tire_gain_dirt


func supported_audio_surface_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for surface_id in AUDIO_SURFACE_IDS:
		ids.append(surface_id)
	return ids


func surface_tire_pitch_for(surface_id: StringName) -> float:
	if surface_id == &"packed_gravel":
		return GameConfig.audio_tire_pitch_gravel
	if surface_id == &"packed_dirt":
		return GameConfig.audio_tire_pitch_dirt
	if surface_id == &"tall_grass":
		return GameConfig.audio_tire_pitch_grass
	if surface_id == &"mud":
		return GameConfig.audio_tire_pitch_mud
	if surface_id == &"loose_rock":
		return GameConfig.audio_tire_pitch_rock
	if surface_id == &"wet_stone":
		return GameConfig.audio_tire_pitch_stone
	if surface_id == &"wood_plank":
		return GameConfig.audio_tire_pitch_wood
	return GameConfig.audio_tire_pitch_dirt


func water_volume_for_position(vehicle_position: Vector3) -> float:
	var flat_position: Vector3 = Vector3(vehicle_position.x, 0.0, vehicle_position.z)
	var flat_center: Vector3 = Vector3(GameConfig.audio_water_center.x, 0.0, GameConfig.audio_water_center.z)
	var distance: float = flat_position.distance_to(flat_center)
	var radius: float = maxf(GameConfig.audio_water_audible_radius, 0.001)
	return clampf(1.0 - distance / radius, 0.0, 1.0) * GameConfig.audio_water_volume


func _on_vehicle_changed_surface(surface_id: StringName) -> void:
	_current_surface_id = surface_id
