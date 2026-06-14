class_name CedarAudioRig
extends Node

var _vehicle: Node = null
var _motor_player: AudioStreamPlayer = null
var _tire_player: AudioStreamPlayer = null
var _motor_playback: AudioStreamGeneratorPlayback = null
var _tire_playback: AudioStreamGeneratorPlayback = null
var _motor_phase: float = 0.0
var _tire_phase: float = 0.0
var _noise_state: int = 17
var _current_surface_id: StringName = &"packed_dirt"


func configure(vehicle: Node) -> void:
	_vehicle = vehicle


func _ready() -> void:
	_motor_player = _make_generator_player("MotorWhine")
	_tire_player = _make_generator_player("TireTexture")
	EventBus.vehicle_changed_surface.connect(_on_vehicle_changed_surface)
	if DisplayServer.get_name() != "headless":
		call_deferred("_start_players")


func _exit_tree() -> void:
	if EventBus.vehicle_changed_surface.is_connected(_on_vehicle_changed_surface):
		EventBus.vehicle_changed_surface.disconnect(_on_vehicle_changed_surface)
	_stop_player(_motor_player)
	_stop_player(_tire_player)
	_motor_playback = null
	_tire_playback = null


func _process(_delta: float) -> void:
	if _motor_playback == null or _tire_playback == null or _vehicle == null:
		return
	var state: RefCounted = _vehicle.call("get_state")
	var speed: float = float(state.call("speed"))
	_fill_motor(speed)
	_fill_tires(speed)


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


func _fill_motor(speed: float) -> void:
	if _motor_playback == null:
		return
	var frames_available: int = _motor_playback.get_frames_available()
	var frequency: float = GameConfig.audio_motor_base_hz + speed * GameConfig.audio_motor_speed_hz_gain
	var phase_step: float = TAU * frequency / maxf(GameConfig.audio_mix_rate, 1.0)
	for i in range(frames_available):
		_motor_phase += phase_step
		if _motor_phase > TAU:
			_motor_phase -= TAU
		var sample: float = sin(_motor_phase) * GameConfig.audio_motor_volume
		_motor_playback.push_frame(Vector2(sample, sample))


func _fill_tires(speed: float) -> void:
	if _tire_playback == null:
		return
	var frames_available: int = _tire_playback.get_frames_available()
	var frequency: float = GameConfig.audio_tire_base_hz * _surface_tire_pitch()
	var phase_step: float = TAU * frequency / maxf(GameConfig.audio_mix_rate, 1.0)
	var volume: float = (GameConfig.audio_tire_volume + speed * GameConfig.audio_tire_speed_volume_gain) * _surface_tire_gain()
	for i in range(frames_available):
		_tire_phase += phase_step
		if _tire_phase > TAU:
			_tire_phase -= TAU
		var wave: float = sin(_tire_phase) * 0.65 + _next_noise() * 0.35
		var sample: float = wave * volume
		_tire_playback.push_frame(Vector2(sample, sample))


func _next_noise() -> float:
	_noise_state = int((_noise_state * 1103515245 + 12345) & 0x7fffffff)
	return float(_noise_state % 2000) / 1000.0 - 1.0


func _surface_tire_gain() -> float:
	if _current_surface_id == &"packed_gravel":
		return GameConfig.audio_tire_gain_gravel
	if _current_surface_id == &"packed_dirt":
		return GameConfig.audio_tire_gain_dirt
	if _current_surface_id == &"tall_grass":
		return GameConfig.audio_tire_gain_grass
	if _current_surface_id == &"mud":
		return GameConfig.audio_tire_gain_mud
	if _current_surface_id == &"loose_rock":
		return GameConfig.audio_tire_gain_rock
	if _current_surface_id == &"wet_stone":
		return GameConfig.audio_tire_gain_stone
	if _current_surface_id == &"wood_plank":
		return GameConfig.audio_tire_gain_wood
	return GameConfig.audio_tire_gain_dirt


func _surface_tire_pitch() -> float:
	if _current_surface_id == &"packed_gravel":
		return GameConfig.audio_tire_pitch_gravel
	if _current_surface_id == &"packed_dirt":
		return GameConfig.audio_tire_pitch_dirt
	if _current_surface_id == &"tall_grass":
		return GameConfig.audio_tire_pitch_grass
	if _current_surface_id == &"mud":
		return GameConfig.audio_tire_pitch_mud
	if _current_surface_id == &"loose_rock":
		return GameConfig.audio_tire_pitch_rock
	if _current_surface_id == &"wet_stone":
		return GameConfig.audio_tire_pitch_stone
	if _current_surface_id == &"wood_plank":
		return GameConfig.audio_tire_pitch_wood
	return GameConfig.audio_tire_pitch_dirt


func _on_vehicle_changed_surface(surface_id: StringName) -> void:
	_current_surface_id = surface_id
