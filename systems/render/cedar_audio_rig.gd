class_name CedarAudioRig
extends Node

const SurfaceVisualCatalogResource: Resource = preload("res://data/surface_visuals/cedar_hollow_surface_visuals.tres")
const LAYER_MOTOR: StringName = &"motor"
const LAYER_TIRE: StringName = &"tire"
const LAYER_AMBIENT: StringName = &"ambient"
const LAYER_WATER: StringName = &"water"
const LAYER_PLANK: StringName = &"plank"
const FAR_EAR_ATTENUATION: float = 0.42
const WATER_PAN_WIDTH: float = 0.72
const AMBIENT_PAN_WIDTH: float = 0.16
const INSECT_PAN_WIDTH: float = 0.48
const REVERB_DRY_DUCK: float = 0.22
const REVERB_FEEDBACK: float = 0.74
const REVERB_INPUT_GAIN: float = 0.34
const REVERB_SEND_GAIN: float = 0.30
const OUTPUT_LIMIT: float = 0.18
const MOTOR_IDLE_RPM: float = 140.0
const MOTOR_RPM_BUZZ_SCALE: float = 0.34
const MOTOR_SPEED_BLEND: float = 0.18
const MOTOR_RPM_VOLUME_GAIN: float = 0.72
const TIRE_SPEED_GATE: float = 0.08
const DIAG_NO_AUDIO_RIG_ENV: String = "TRAILHEAD_DIAG_NOAUDIORIG"
const AUDIO_TARGET_BUFFER_SECONDS: float = 0.12
const AUDIO_FILL_BUDGET_SECONDS: float = 0.040
const AUDIO_SYNTH_STRIDE_FRAMES: int = 4
# Audio-thread fill cadence: how long the worker sleeps between fill cycles when the
# generator is already topped up. Host-only; read only by this rig.
const AUDIO_THREAD_IDLE_SLEEP_USEC: int = 3000

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
var _insect_phase: float = 0.0
var _water_phase: float = 0.0
var _plank_phase: float = 0.0
var _plank_envelope: float = 0.0
var _noise_state: int = 17
var _ambient_noise_state: int = 43
var _water_noise_state: int = 89
var _current_surface_id: StringName = &"packed_dirt"
var _motor_reverb_frame: Vector2 = Vector2.ZERO
var _tire_reverb_frame: Vector2 = Vector2.ZERO
var _ambient_reverb_frame: Vector2 = Vector2.ZERO
var _water_reverb_frame: Vector2 = Vector2.ZERO
var _plank_reverb_frame: Vector2 = Vector2.ZERO
var _preview_mix_override_active: bool = false
var _preview_master_volume_db: float = 0.0
var _preview_ambient_volume_db: float = 0.0
var _preview_reverb_wet: float = 0.0
var _ambient_duck_volume_db: float = 0.0
var _diag_no_audio_rig: bool = false
var _started: bool = false
var _audio_capacity_frames: int = 1
var _audio_target_free_frames: int = 0
var _audio_fill_budget_frames: int = 1
var _motor_fill_buffer: PackedVector2Array = PackedVector2Array()
var _tire_fill_buffer: PackedVector2Array = PackedVector2Array()
var _ambient_fill_buffer: PackedVector2Array = PackedVector2Array()
var _water_fill_buffer: PackedVector2Array = PackedVector2Array()
var _plank_fill_buffer: PackedVector2Array = PackedVector2Array()
var _audio_thread: Thread = null
var _audio_mutex: Mutex = Mutex.new()
var _audio_thread_should_stop: bool = false
var _audio_thread_running: bool = false
# Single-producer (main _process) / single-consumer (audio thread) input snapshot.
var _snapshot_speed: float = 0.0
var _snapshot_motor_rpm: float = 0.0
var _snapshot_position: Vector3 = Vector3.ZERO
var _snapshot_surface_id: StringName = &"packed_dirt"


func configure(vehicle: Node) -> void:
	_vehicle = vehicle


func start() -> void:
	_started = true
	# Reveal gate: spin the fill thread ONLY once the cold-start reveal fires (host calls
	# this at cedar_hollow_host.gd:623). The thread bypasses the _process `_started` check,
	# so starting it earlier (in _start_players) played audio during the title/loading hold.
	_start_audio_thread()


func _ready() -> void:
	_diag_no_audio_rig = _env_enabled(DIAG_NO_AUDIO_RIG_ENV)
	_configure_audio_fill_budget()
	_ambient_duck_volume_db = GameConfig.audio_bus_ambient_volume_db
	_motor_player = _make_generator_player("MotorWhine")
	_tire_player = _make_generator_player("TireTexture")
	_ambient_player = _make_generator_player("AmbientBed")
	_water_player = _make_generator_player("CreekBed")
	_plank_player = _make_generator_player("PlankKnock")
	if not EventBus.vehicle_changed_surface.is_connected(_on_vehicle_changed_surface):
		EventBus.vehicle_changed_surface.connect(_on_vehicle_changed_surface)
	if not EventBus.world_duck_ambient_audio.is_connected(_on_world_duck_ambient_audio):
		EventBus.world_duck_ambient_audio.connect(_on_world_duck_ambient_audio)
	if DisplayServer.get_name() != "headless":
		call_deferred("_start_players")


func _exit_tree() -> void:
	_stop_audio_thread()
	if EventBus.vehicle_changed_surface.is_connected(_on_vehicle_changed_surface):
		EventBus.vehicle_changed_surface.disconnect(_on_vehicle_changed_surface)
	if EventBus.world_duck_ambient_audio.is_connected(_on_world_duck_ambient_audio):
		EventBus.world_duck_ambient_audio.disconnect(_on_world_duck_ambient_audio)
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
	if not _started:
		return
	if _diag_no_audio_rig:
		return
	if _vehicle == null:
		return
	var state: RefCounted = _vehicle.call("get_state")
	var speed: float = float(state.call("speed"))
	var motor_rpm: float = float(state.get("motor_rpm"))
	var vehicle_position: Vector3 = state.get("position")
	if _audio_thread_running:
		# Publish-only. The self-paced worker reads the latest snapshot on its own
		# cadence, so _process does not drive fills and does not need to wake it.
		_audio_mutex.lock()
		var threaded_surface_id: StringName = _dominant_surface_from_state(state, _snapshot_surface_id)
		_snapshot_speed = speed
		_snapshot_motor_rpm = motor_rpm
		_snapshot_position = vehicle_position
		_snapshot_surface_id = threaded_surface_id
		_audio_mutex.unlock()
		return
	# Headless / thread-not-started fallback: synthesize inline, exactly as before.
	_current_surface_id = _dominant_surface_from_state(state, _current_surface_id)
	_fill_motor(speed, motor_rpm)
	_fill_tires(speed)
	_fill_ambient(vehicle_position)
	_fill_water(vehicle_position)
	_fill_planks(speed)


func preview_audio_output_stats(speed: float, vehicle_position: Vector3, surface_id: StringName, frame_count: int) -> Dictionary:
	var fallback_motor_rpm: float = speed * GameConfig.motor_rpm_speed_scale
	return preview_audio_output_stats_with_motor_rpm(speed, fallback_motor_rpm, vehicle_position, surface_id, frame_count)


func preview_audio_output_stats_with_motor_rpm(speed: float, motor_rpm: float, vehicle_position: Vector3, surface_id: StringName, frame_count: int) -> Dictionary:
	var previous_surface_id: StringName = _current_surface_id
	var previous_motor_phase: float = _motor_phase
	var previous_tire_phase: float = _tire_phase
	var previous_ambient_phase: float = _ambient_phase
	var previous_bird_phase: float = _bird_phase
	var previous_insect_phase: float = _insect_phase
	var previous_water_phase: float = _water_phase
	var previous_plank_phase: float = _plank_phase
	var previous_plank_envelope: float = _plank_envelope
	var previous_noise_state: int = _noise_state
	var previous_ambient_noise_state: int = _ambient_noise_state
	var previous_water_noise_state: int = _water_noise_state
	var previous_motor_reverb_frame: Vector2 = _motor_reverb_frame
	var previous_tire_reverb_frame: Vector2 = _tire_reverb_frame
	var previous_ambient_reverb_frame: Vector2 = _ambient_reverb_frame
	var previous_water_reverb_frame: Vector2 = _water_reverb_frame
	var previous_plank_reverb_frame: Vector2 = _plank_reverb_frame
	_current_surface_id = surface_id
	var motor_stats: Dictionary = _new_audio_stats()
	var tire_stats: Dictionary = _new_audio_stats()
	var ambient_stats: Dictionary = _new_audio_stats()
	var water_stats: Dictionary = _new_audio_stats()
	var plank_stats: Dictionary = _new_audio_stats()
	for _i in range(maxi(frame_count, 0)):
		_record_audio_frame(motor_stats, _next_motor_frame(speed, motor_rpm))
		_record_audio_frame(tire_stats, _next_tire_frame(speed))
		_record_audio_frame(ambient_stats, _next_ambient_frame(vehicle_position))
		_record_audio_frame(water_stats, _next_water_frame(vehicle_position))
		_record_audio_frame(plank_stats, _next_plank_frame(speed))
	_current_surface_id = previous_surface_id
	_motor_phase = previous_motor_phase
	_tire_phase = previous_tire_phase
	_ambient_phase = previous_ambient_phase
	_bird_phase = previous_bird_phase
	_insect_phase = previous_insect_phase
	_water_phase = previous_water_phase
	_plank_phase = previous_plank_phase
	_plank_envelope = previous_plank_envelope
	_noise_state = previous_noise_state
	_ambient_noise_state = previous_ambient_noise_state
	_water_noise_state = previous_water_noise_state
	_motor_reverb_frame = previous_motor_reverb_frame
	_tire_reverb_frame = previous_tire_reverb_frame
	_ambient_reverb_frame = previous_ambient_reverb_frame
	_water_reverb_frame = previous_water_reverb_frame
	_plank_reverb_frame = previous_plank_reverb_frame
	return {
		"motor": _finalize_audio_stats(motor_stats),
		"tire": _finalize_audio_stats(tire_stats),
		"ambient": _finalize_audio_stats(ambient_stats),
		"water": _finalize_audio_stats(water_stats),
		"plank": _finalize_audio_stats(plank_stats),
	}


func preview_audio_output_stats_with_mix_overrides(
	speed: float,
	vehicle_position: Vector3,
	surface_id: StringName,
	frame_count: int,
	master_volume_db: float,
	ambient_volume_db: float,
	reverb_wet: float
) -> Dictionary:
	var previous_override_active: bool = _preview_mix_override_active
	var previous_master_volume_db: float = _preview_master_volume_db
	var previous_ambient_volume_db: float = _preview_ambient_volume_db
	var previous_reverb_wet: float = _preview_reverb_wet
	_preview_mix_override_active = true
	_preview_master_volume_db = master_volume_db
	_preview_ambient_volume_db = ambient_volume_db
	_preview_reverb_wet = reverb_wet
	var fallback_motor_rpm: float = speed * GameConfig.motor_rpm_speed_scale
	var stats: Dictionary = preview_audio_output_stats_with_motor_rpm(speed, fallback_motor_rpm, vehicle_position, surface_id, frame_count)
	_preview_mix_override_active = previous_override_active
	_preview_master_volume_db = previous_master_volume_db
	_preview_ambient_volume_db = previous_ambient_volume_db
	_preview_reverb_wet = previous_reverb_wet
	return stats


func debug_fill_cycle_buffers(speed: float, motor_rpm: float, vehicle_position: Vector3, surface_id: StringName, frame_count: int) -> Dictionary:
	var safe_frame_count: int = maxi(frame_count, 0)
	_current_surface_id = surface_id
	_motor_fill_buffer.resize(safe_frame_count)
	var write_index: int = 0
	var repeat_count: int = 0
	while write_index < safe_frame_count:
		repeat_count = mini(AUDIO_SYNTH_STRIDE_FRAMES, safe_frame_count - write_index)
		var motor_frame: Vector2 = _next_motor_frame(speed, motor_rpm, repeat_count)
		for motor_repeat_index in range(repeat_count):
			_motor_fill_buffer[write_index + motor_repeat_index] = motor_frame
		write_index += repeat_count
	_tire_fill_buffer.resize(safe_frame_count)
	write_index = 0
	while write_index < safe_frame_count:
		repeat_count = mini(AUDIO_SYNTH_STRIDE_FRAMES, safe_frame_count - write_index)
		var tire_frame: Vector2 = _next_tire_frame(speed, repeat_count)
		for tire_repeat_index in range(repeat_count):
			_tire_fill_buffer[write_index + tire_repeat_index] = tire_frame
		write_index += repeat_count
	_ambient_fill_buffer.resize(safe_frame_count)
	write_index = 0
	while write_index < safe_frame_count:
		repeat_count = mini(AUDIO_SYNTH_STRIDE_FRAMES, safe_frame_count - write_index)
		var ambient_frame: Vector2 = _next_ambient_frame(vehicle_position, repeat_count)
		for ambient_repeat_index in range(repeat_count):
			_ambient_fill_buffer[write_index + ambient_repeat_index] = ambient_frame
		write_index += repeat_count
	_water_fill_buffer.resize(safe_frame_count)
	write_index = 0
	while write_index < safe_frame_count:
		repeat_count = mini(AUDIO_SYNTH_STRIDE_FRAMES, safe_frame_count - write_index)
		var water_frame: Vector2 = _next_water_frame(vehicle_position, repeat_count)
		for water_repeat_index in range(repeat_count):
			_water_fill_buffer[write_index + water_repeat_index] = water_frame
		write_index += repeat_count
	_plank_fill_buffer.resize(safe_frame_count)
	write_index = 0
	while write_index < safe_frame_count:
		repeat_count = mini(AUDIO_SYNTH_STRIDE_FRAMES, safe_frame_count - write_index)
		var plank_frame: Vector2 = _next_plank_frame(speed, repeat_count)
		for plank_repeat_index in range(repeat_count):
			_plank_fill_buffer[write_index + plank_repeat_index] = plank_frame
		write_index += repeat_count
	return {
		"motor": _copy_audio_buffer(_motor_fill_buffer),
		"tire": _copy_audio_buffer(_tire_fill_buffer),
		"ambient": _copy_audio_buffer(_ambient_fill_buffer),
		"water": _copy_audio_buffer(_water_fill_buffer),
		"plank": _copy_audio_buffer(_plank_fill_buffer),
	}


func _copy_audio_buffer(buffer: PackedVector2Array) -> PackedVector2Array:
	var copy: PackedVector2Array = PackedVector2Array()
	copy.resize(buffer.size())
	for index in range(buffer.size()):
		copy[index] = buffer[index]
	return copy


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
	# NOTE: the fill thread is started by start() at the reveal gate, NOT here — otherwise
	# it fills the generators during the title/loading hold (the _started gate only guards _process).


func _start_audio_thread() -> void:
	if _audio_thread != null:
		return
	if DisplayServer.get_name() == "headless":
		return
	_audio_thread_should_stop = false
	_audio_thread = Thread.new()
	# Low priority parks audio fill on efficiency cores so main+render keep the perf
	# cores, matching the TerrainVisualStreamer windowed worker rationale.
	var start_error: Error = _audio_thread.start(Callable(self, "_audio_thread_loop"), Thread.PRIORITY_LOW)
	if start_error != OK:
		push_error("CedarAudioRig audio thread start failed: " + error_string(start_error))
		_audio_thread = null
		return
	_audio_thread_running = true


func _stop_audio_thread() -> void:
	if _audio_thread == null:
		return
	_audio_mutex.lock()
	_audio_thread_should_stop = true
	_audio_mutex.unlock()
	_audio_thread.wait_to_finish()
	_audio_thread = null
	_audio_thread_running = false
	_audio_thread_should_stop = false


func _audio_thread_loop() -> void:
	while true:
		_audio_mutex.lock()
		if _audio_thread_should_stop:
			_audio_mutex.unlock()
			return
		var speed: float = _snapshot_speed
		var motor_rpm: float = _snapshot_motor_rpm
		var vehicle_position: Vector3 = _snapshot_position
		var surface_id: StringName = _snapshot_surface_id
		_audio_mutex.unlock()
		_current_surface_id = surface_id
		_fill_motor(speed, motor_rpm)
		_fill_tires(speed)
		_fill_ambient(vehicle_position)
		_fill_water(vehicle_position)
		_fill_planks(speed)
		OS.delay_usec(AUDIO_THREAD_IDLE_SLEEP_USEC)


func _fill_motor(speed: float, motor_rpm: float) -> void:
	if _motor_playback == null:
		return
	var frame_count: int = _frames_to_fill(_motor_playback)
	if frame_count <= 0:
		return
	_motor_fill_buffer.resize(frame_count)
	var write_index: int = 0
	while write_index < frame_count:
		var repeat_count: int = mini(AUDIO_SYNTH_STRIDE_FRAMES, frame_count - write_index)
		var frame: Vector2 = _next_motor_frame(speed, motor_rpm, repeat_count)
		for repeat_index in range(repeat_count):
			_motor_fill_buffer[write_index + repeat_index] = frame
		write_index += repeat_count
	_motor_playback.push_buffer(_motor_fill_buffer)


func _fill_tires(speed: float) -> void:
	if _tire_playback == null:
		return
	var frame_count: int = _frames_to_fill(_tire_playback)
	if frame_count <= 0:
		return
	_tire_fill_buffer.resize(frame_count)
	var write_index: int = 0
	while write_index < frame_count:
		var repeat_count: int = mini(AUDIO_SYNTH_STRIDE_FRAMES, frame_count - write_index)
		var frame: Vector2 = _next_tire_frame(speed, repeat_count)
		for repeat_index in range(repeat_count):
			_tire_fill_buffer[write_index + repeat_index] = frame
		write_index += repeat_count
	_tire_playback.push_buffer(_tire_fill_buffer)


func _fill_ambient(vehicle_position: Vector3) -> void:
	if _ambient_playback == null:
		return
	var frame_count: int = _frames_to_fill(_ambient_playback)
	if frame_count <= 0:
		return
	_ambient_fill_buffer.resize(frame_count)
	var write_index: int = 0
	while write_index < frame_count:
		var repeat_count: int = mini(AUDIO_SYNTH_STRIDE_FRAMES, frame_count - write_index)
		var frame: Vector2 = _next_ambient_frame(vehicle_position, repeat_count)
		for repeat_index in range(repeat_count):
			_ambient_fill_buffer[write_index + repeat_index] = frame
		write_index += repeat_count
	_ambient_playback.push_buffer(_ambient_fill_buffer)


func _fill_water(vehicle_position: Vector3) -> void:
	if _water_playback == null:
		return
	var frame_count: int = _frames_to_fill(_water_playback)
	if frame_count <= 0:
		return
	_water_fill_buffer.resize(frame_count)
	var write_index: int = 0
	while write_index < frame_count:
		var repeat_count: int = mini(AUDIO_SYNTH_STRIDE_FRAMES, frame_count - write_index)
		var frame: Vector2 = _next_water_frame(vehicle_position, repeat_count)
		for repeat_index in range(repeat_count):
			_water_fill_buffer[write_index + repeat_index] = frame
		write_index += repeat_count
	_water_playback.push_buffer(_water_fill_buffer)


func _fill_planks(speed: float) -> void:
	if _plank_playback == null:
		return
	var frame_count: int = _frames_to_fill(_plank_playback)
	if frame_count <= 0:
		return
	_plank_fill_buffer.resize(frame_count)
	var write_index: int = 0
	while write_index < frame_count:
		var repeat_count: int = mini(AUDIO_SYNTH_STRIDE_FRAMES, frame_count - write_index)
		var frame: Vector2 = _next_plank_frame(speed, repeat_count)
		for repeat_index in range(repeat_count):
			_plank_fill_buffer[write_index + repeat_index] = frame
		write_index += repeat_count
	_plank_playback.push_buffer(_plank_fill_buffer)


func _configure_audio_fill_budget() -> void:
	var mix_rate: float = maxf(GameConfig.audio_mix_rate, 1.0)
	_audio_capacity_frames = maxi(int(mix_rate * maxf(GameConfig.audio_buffer_length, 0.001)), 1)
	var target_buffer_frames: int = clampi(int(mix_rate * AUDIO_TARGET_BUFFER_SECONDS), 1, _audio_capacity_frames)
	_audio_target_free_frames = clampi(_audio_capacity_frames - target_buffer_frames, 0, _audio_capacity_frames - 1)
	_audio_fill_budget_frames = clampi(int(mix_rate * AUDIO_FILL_BUDGET_SECONDS), 1, _audio_capacity_frames)


func _frames_to_fill(playback: AudioStreamGeneratorPlayback) -> int:
	var frames_available: int = playback.get_frames_available()
	if frames_available <= _audio_target_free_frames:
		return 0
	return mini(frames_available - _audio_target_free_frames, _audio_fill_budget_frames)


func _next_motor_frame(speed: float, motor_rpm: float, sample_stride: int = 1) -> Vector2:
	var speed_ratio: float = clampf(speed / maxf(GameConfig.max_speed, 0.001), 0.0, 1.25)
	var expected_max_rpm: float = maxf(GameConfig.max_speed * GameConfig.motor_rpm_speed_scale, 1.0)
	var rpm_ratio: float = clampf(maxf(motor_rpm, 0.0) / expected_max_rpm, 0.0, 1.35)
	var rpm_frequency: float = MOTOR_IDLE_RPM + rpm_ratio * GameConfig.audio_motor_speed_hz_gain * maxf(GameConfig.max_speed, 1.0)
	var speed_frequency: float = GameConfig.audio_motor_base_hz + speed_ratio * GameConfig.audio_motor_speed_hz_gain * maxf(GameConfig.max_speed, 1.0)
	var frequency: float = lerpf(rpm_frequency, speed_frequency, MOTOR_SPEED_BLEND)
	var phase_step: float = TAU * frequency * float(maxi(sample_stride, 1)) / maxf(GameConfig.audio_mix_rate, 1.0)
	_motor_phase += phase_step
	if _motor_phase > TAU:
		_motor_phase -= TAU
	var wave: float = sin(_motor_phase) * 0.48 \
		+ sin(_motor_phase * 2.0) * 0.24 \
		+ sin(_motor_phase * 3.0) * 0.14 \
		+ _next_noise() * MOTOR_RPM_BUZZ_SCALE * (0.35 + rpm_ratio * 0.65)
	var volume: float = GameConfig.audio_motor_volume * (0.62 + rpm_ratio * MOTOR_RPM_VOLUME_GAIN + speed_ratio * 0.25)
	return _apply_layer_mix(Vector2(wave, wave) * volume, LAYER_MOTOR)


func _next_tire_frame(speed: float, sample_stride: int = 1) -> Vector2:
	var frequency: float = GameConfig.audio_tire_base_hz * surface_tire_pitch_for(_current_surface_id)
	var phase_step: float = TAU * frequency * float(maxi(sample_stride, 1)) / maxf(GameConfig.audio_mix_rate, 1.0)
	var speed_ratio: float = clampf(speed / maxf(GameConfig.max_speed, 0.001), 0.0, 1.25)
	var surface_gain: float = surface_tire_gain_for(_current_surface_id)
	var speed_gate: float = clampf(speed / TIRE_SPEED_GATE, 0.0, 1.0)
	var volume: float = (GameConfig.audio_tire_volume + speed * GameConfig.audio_tire_speed_volume_gain) * surface_gain * speed_gate
	_tire_phase += phase_step
	if _tire_phase > TAU:
		_tire_phase -= TAU
	var roughness: float = clampf((surface_gain - 0.65) * 0.55 + speed_ratio * 0.35, 0.18, 0.82)
	var wave: float = sin(_tire_phase) * (1.0 - roughness) + _next_noise() * roughness
	return _apply_layer_mix(Vector2(wave, wave) * volume, LAYER_TIRE)


func _next_ambient_frame(vehicle_position: Vector3, sample_stride: int = 1) -> Vector2:
	var stride: float = float(maxi(sample_stride, 1))
	var wind_step: float = TAU * GameConfig.audio_ambient_wind_base_hz * stride / maxf(GameConfig.audio_mix_rate, 1.0)
	var bird_step: float = TAU * GameConfig.audio_ambient_bird_hz * stride / maxf(GameConfig.audio_mix_rate, 1.0)
	var insect_step: float = TAU * GameConfig.audio_ambient_insect_hz * stride / maxf(GameConfig.audio_mix_rate, 1.0)
	_ambient_phase += wind_step
	_bird_phase += bird_step
	_insect_phase += insect_step
	if _ambient_phase > TAU:
		_ambient_phase -= TAU
	if _bird_phase > TAU:
		_bird_phase -= TAU
	if _insect_phase > TAU:
		_insect_phase -= TAU
	var wind: float = (sin(_ambient_phase) * 0.35 + _next_ambient_noise() * 0.65) * GameConfig.audio_ambient_wind_volume
	var bird_gate: float = 1.0 if _ambient_noise_state % 991 > 982 else 0.0
	var bird: float = sin(_bird_phase) * bird_gate * GameConfig.audio_ambient_bird_volume
	var insect_gate: float = 1.0 if _ambient_noise_state % 719 > 356 else 0.35
	var insect: float = sin(_insect_phase) * insect_gate * GameConfig.audio_ambient_insect_volume
	var wind_frame: Vector2 = _pan_frame(wind, sin(_ambient_phase * 0.25) * AMBIENT_PAN_WIDTH)
	var bird_frame: Vector2 = _pan_frame(bird, -AMBIENT_PAN_WIDTH)
	var insect_frame: Vector2 = _pan_frame(insect, insect_pan_for_position(vehicle_position))
	return _apply_layer_mix(wind_frame + bird_frame + insect_frame, LAYER_AMBIENT)


func _next_water_frame(vehicle_position: Vector3, sample_stride: int = 1) -> Vector2:
	var volume: float = water_volume_for_position(vehicle_position)
	var phase_step: float = TAU * GameConfig.audio_water_base_hz * float(maxi(sample_stride, 1)) / maxf(GameConfig.audio_mix_rate, 1.0)
	_water_phase += phase_step
	if _water_phase > TAU:
		_water_phase -= TAU
	var stream_noise: float = _next_water_noise() * 0.75 + sin(_water_phase) * 0.25
	return _apply_layer_mix(_pan_frame(stream_noise * volume, water_pan_for_position(vehicle_position)), LAYER_WATER)


func _next_plank_frame(speed: float, sample_stride: int = 1) -> Vector2:
	var is_on_plank: bool = bool(SurfaceVisualCatalogResource.call("emits_plank_knock_for", _current_surface_id))
	var frequency: float = GameConfig.audio_plank_base_hz + speed * GameConfig.audio_plank_speed_hz_gain
	var phase_step: float = TAU * frequency * float(maxi(sample_stride, 1)) / maxf(GameConfig.audio_mix_rate, 1.0)
	if is_on_plank:
		_plank_phase += phase_step
		if _plank_phase > TAU:
			_plank_phase -= TAU
			_plank_envelope = 1.0
	_plank_envelope *= pow(GameConfig.audio_plank_decay, float(maxi(sample_stride, 1)))
	var sample: float = sin(_plank_phase * 5.0) * _plank_envelope * GameConfig.audio_plank_volume
	return _apply_layer_mix(Vector2(sample, sample), LAYER_PLANK)


func _new_audio_stats() -> Dictionary:
	return {
		"sample_count": 0,
		"max_abs": 0.0,
		"abs_sum": 0.0,
		"square_sum": 0.0,
		"mean_abs": 0.0,
		"rms": 0.0,
		"left_abs_sum": 0.0,
		"right_abs_sum": 0.0,
		"left_mean_abs": 0.0,
		"right_mean_abs": 0.0,
		"pan_balance": 0.0,
	}


func _record_audio_frame(stats: Dictionary, frame: Vector2) -> void:
	var abs_left: float = absf(frame.x)
	var abs_right: float = absf(frame.y)
	var abs_sample: float = (abs_left + abs_right) * 0.5
	stats["sample_count"] = int(stats["sample_count"]) + 1
	stats["max_abs"] = maxf(float(stats["max_abs"]), abs_sample)
	stats["abs_sum"] = float(stats["abs_sum"]) + abs_sample
	stats["square_sum"] = float(stats["square_sum"]) + (frame.x * frame.x + frame.y * frame.y) * 0.5
	stats["left_abs_sum"] = float(stats["left_abs_sum"]) + abs_left
	stats["right_abs_sum"] = float(stats["right_abs_sum"]) + abs_right


func _finalize_audio_stats(stats: Dictionary) -> Dictionary:
	var sample_count: int = int(stats["sample_count"])
	if sample_count > 0:
		var count_float: float = float(sample_count)
		stats["mean_abs"] = float(stats["abs_sum"]) / count_float
		stats["rms"] = sqrt(float(stats["square_sum"]) / count_float)
		stats["left_mean_abs"] = float(stats["left_abs_sum"]) / count_float
		stats["right_mean_abs"] = float(stats["right_abs_sum"]) / count_float
		var stereo_abs_sum: float = float(stats["left_abs_sum"]) + float(stats["right_abs_sum"])
		if stereo_abs_sum > 0.0:
			stats["pan_balance"] = (float(stats["right_abs_sum"]) - float(stats["left_abs_sum"])) / stereo_abs_sum
	return stats


func _pan_frame(sample: float, pan: float) -> Vector2:
	var clamped_pan: float = clampf(pan, -1.0, 1.0)
	var left_gain: float = 1.0 - maxf(clamped_pan, 0.0) * FAR_EAR_ATTENUATION
	var right_gain: float = 1.0 - maxf(-clamped_pan, 0.0) * FAR_EAR_ATTENUATION
	return Vector2(sample * left_gain, sample * right_gain)


func _apply_layer_mix(frame: Vector2, layer_name: StringName) -> Vector2:
	var gained_frame: Vector2 = frame * bus_gain_for_layer(layer_name)
	var reverb_wet: float = _active_reverb_wet()
	if reverb_wet <= 0.0:
		return _limit_frame(gained_frame)
	var reverb_frame: Vector2 = _next_reverb_frame(layer_name, gained_frame)
	var dry_frame: Vector2 = gained_frame * (1.0 - reverb_wet * REVERB_DRY_DUCK)
	return _limit_frame(dry_frame + reverb_frame * reverb_wet * REVERB_SEND_GAIN)


func _next_reverb_frame(layer_name: StringName, frame: Vector2) -> Vector2:
	var previous_frame: Vector2 = _reverb_frame_for_layer(layer_name)
	var cross_frame: Vector2 = Vector2(previous_frame.y, previous_frame.x)
	var next_frame: Vector2 = previous_frame * REVERB_FEEDBACK + cross_frame * (1.0 - REVERB_FEEDBACK) + frame * REVERB_INPUT_GAIN
	_set_reverb_frame_for_layer(layer_name, next_frame)
	return next_frame


func _limit_frame(frame: Vector2) -> Vector2:
	return Vector2(clampf(frame.x, -OUTPUT_LIMIT, OUTPUT_LIMIT), clampf(frame.y, -OUTPUT_LIMIT, OUTPUT_LIMIT))


func _reverb_frame_for_layer(layer_name: StringName) -> Vector2:
	if layer_name == LAYER_MOTOR:
		return _motor_reverb_frame
	if layer_name == LAYER_TIRE:
		return _tire_reverb_frame
	if layer_name == LAYER_AMBIENT:
		return _ambient_reverb_frame
	if layer_name == LAYER_WATER:
		return _water_reverb_frame
	return _plank_reverb_frame


func _set_reverb_frame_for_layer(layer_name: StringName, frame: Vector2) -> void:
	if layer_name == LAYER_MOTOR:
		_motor_reverb_frame = frame
	elif layer_name == LAYER_TIRE:
		_tire_reverb_frame = frame
	elif layer_name == LAYER_AMBIENT:
		_ambient_reverb_frame = frame
	elif layer_name == LAYER_WATER:
		_water_reverb_frame = frame
	else:
		_plank_reverb_frame = frame


func _next_noise() -> float:
	_noise_state = int((_noise_state * 1103515245 + 12345) & 0x7fffffff)
	return float(_noise_state % 2000) / 1000.0 - 1.0


func _next_ambient_noise() -> float:
	_ambient_noise_state = int((_ambient_noise_state * 1103515245 + 12345) & 0x7fffffff)
	return float(_ambient_noise_state % 2000) / 1000.0 - 1.0


func _next_water_noise() -> float:
	_water_noise_state = int((_water_noise_state * 1103515245 + 12345) & 0x7fffffff)
	return float(_water_noise_state % 2000) / 1000.0 - 1.0


func bus_gain_for_layer(layer_name: StringName) -> float:
	return db_to_linear(_active_master_volume_db() + _bus_volume_db_for_layer(layer_name))


func _active_master_volume_db() -> float:
	if _preview_mix_override_active:
		return _preview_master_volume_db
	return GameConfig.audio_bus_master_volume_db


func _active_reverb_wet() -> float:
	if _preview_mix_override_active:
		return clampf(_preview_reverb_wet, 0.0, 1.0)
	return clampf(GameConfig.audio_bus_reverb_wet, 0.0, 1.0)


func _bus_volume_db_for_layer(layer_name: StringName) -> float:
	if layer_name == LAYER_MOTOR:
		return GameConfig.audio_bus_motor_volume_db
	if layer_name == LAYER_TIRE:
		return GameConfig.audio_bus_tire_volume_db
	if layer_name == LAYER_AMBIENT:
		if _preview_mix_override_active:
			return _preview_ambient_volume_db
		return _ambient_duck_volume_db
	if layer_name == LAYER_WATER:
		return GameConfig.audio_bus_water_volume_db
	if layer_name == LAYER_PLANK:
		return GameConfig.audio_bus_tire_volume_db
	return 0.0


func surface_tire_gain_for(surface_id: StringName) -> float:
	return float(SurfaceVisualCatalogResource.call("tire_audio_gain_for", surface_id))


func _on_world_duck_ambient_audio(target_volume_db: float) -> void:
	_ambient_duck_volume_db = target_volume_db


func supported_audio_surface_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	var supported_ids: Array[StringName] = SurfaceVisualCatalogResource.call("supported_surface_ids")
	for surface_id in supported_ids:
		ids.append(surface_id)
	return ids


func surface_tire_pitch_for(surface_id: StringName) -> float:
	return float(SurfaceVisualCatalogResource.call("tire_audio_pitch_for", surface_id))


func water_volume_for_position(vehicle_position: Vector3) -> float:
	var flat_position: Vector3 = Vector3(vehicle_position.x, 0.0, vehicle_position.z)
	var flat_center: Vector3 = Vector3(GameConfig.audio_water_center.x, 0.0, GameConfig.audio_water_center.z)
	var distance: float = flat_position.distance_to(flat_center)
	var radius: float = maxf(GameConfig.audio_water_audible_radius, 0.001)
	return clampf(1.0 - distance / radius, 0.0, 1.0) * GameConfig.audio_water_volume


func water_pan_for_position(vehicle_position: Vector3) -> float:
	var radius: float = maxf(GameConfig.audio_water_audible_radius, 0.001)
	return clampf((GameConfig.audio_water_center.x - vehicle_position.x) / radius, -1.0, 1.0) * WATER_PAN_WIDTH


func insect_pan_for_position(vehicle_position: Vector3) -> float:
	var radius: float = maxf(GameConfig.audio_water_audible_radius, 0.001)
	var insect_source_x: float = GameConfig.audio_water_center.x - radius * 0.35
	return clampf((insect_source_x - vehicle_position.x) / radius, -1.0, 1.0) * INSECT_PAN_WIDTH


func _dominant_surface_from_state(state: RefCounted, fallback_surface_id: StringName) -> StringName:
	var surface_variant: Variant = state.get("wheel_surface")
	if not surface_variant is Array:
		return fallback_surface_id
	var wheel_surface: Array = surface_variant
	var counts: Dictionary[StringName, int] = {}
	var best_surface_id: StringName = fallback_surface_id
	var best_count: int = 0
	for surface_id_variant in wheel_surface:
		var surface_id: StringName = StringName(surface_id_variant)
		if surface_id == &"":
			continue
		var current_count: int = int(counts.get(surface_id, 0)) + 1
		counts[surface_id] = current_count
		if current_count > best_count:
			best_count = current_count
			best_surface_id = surface_id
	return best_surface_id


func _on_vehicle_changed_surface(surface_id: StringName) -> void:
	if _audio_thread_running:
		_audio_mutex.lock()
		_snapshot_surface_id = surface_id
		_audio_mutex.unlock()
		return
	_current_surface_id = surface_id


func _env_enabled(env_name: String) -> bool:
	var value: String = OS.get_environment(env_name).to_lower()
	return value == "1" or value == "true" or value == "yes"
