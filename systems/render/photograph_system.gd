class_name PhotographSystem
extends Node

const INPUT_ACTION: StringName = &"photograph"
const PRESENTATION_LAYER_INDEX: int = 5
const SHUTTER_HZ: float = 1800.0
const SHUTTER_VOLUME: float = 0.045
const SHUTTER_DECAY_PER_FRAME: float = 0.92

var _vehicle: Node = null
var _route: Resource = null
var _hold_ticks: int = 0
var _sim_tick: int = 0
var _capture_latched: bool = false
var _capture_count: int = 0
var _presentation_frames_remaining: int = 0
var _presentation_layer: CanvasLayer = null
var _presentation_rect: ColorRect = null
var _shutter_player: AudioStreamPlayer = null
var _shutter_playback: AudioStreamGeneratorPlayback = null
var _shutter_phase: float = 0.0
var _shutter_envelope: float = 0.0
var _process_usec_last_frame: int = 0


func configure(route: Resource, vehicle: Node) -> void:
	_route = route
	_vehicle = vehicle


func _ready() -> void:
	_setup_presentation_layer()
	_setup_shutter_audio()


func _exit_tree() -> void:
	if _shutter_player != null:
		_shutter_player.stop()
		_shutter_player.stream = null
		_shutter_player = null
	_shutter_playback = null


func _physics_process(_delta: float) -> void:
	if _vehicle == null:
		return
	_sim_tick += 1
	var state: RefCounted = _vehicle.call("get_state")
	var speed: float = float(state.call("speed"))
	if not Input.is_action_pressed(String(INPUT_ACTION)) or speed > GameConfig.photo_max_speed_mps:
		_hold_ticks = 0
		_capture_latched = false
		return
	_hold_ticks += 1
	if _capture_latched or _hold_ticks < maxi(GameConfig.photo_hold_ticks, 1):
		return
	var position: Vector3 = state.get("position")
	var nearest_landmark_id: StringName = _nearest_landmark_id(position)
	if nearest_landmark_id == &"":
		return
	_capture_latched = true
	_capture_count += 1
	EventBus.world_photograph_taken.emit(nearest_landmark_id, _sim_tick)
	_begin_presentation_hold()
	_play_shutter_cue()


func _process(_delta: float) -> void:
	var process_start_usec: int = Time.get_ticks_usec()
	_process_body()
	_process_usec_last_frame = maxi(Time.get_ticks_usec() - process_start_usec, 0)


func process_usec_last_frame() -> int:
	return _process_usec_last_frame


func _process_body() -> void:
	_update_presentation_hold()
	_fill_shutter_audio()


func held_ticks() -> int:
	return _hold_ticks


func sim_tick() -> int:
	return _sim_tick


func capture_count() -> int:
	return _capture_count


func presentation_frames_remaining() -> int:
	return _presentation_frames_remaining


func _nearest_landmark_id(position: Vector3) -> StringName:
	if _route == null:
		return &""
	var landmark_ids: Array[StringName] = _route.get("landmark_ids")
	var max_distance_sq: float = GameConfig.vis_range_props * GameConfig.vis_range_props
	var best_distance_sq: float = max_distance_sq
	var best_id: StringName = &""
	for value in landmark_ids:
		var landmark_id: StringName = StringName(value)
		var landmark_position: Vector3 = _route.call("landmark_position", landmark_id)
		var delta: Vector3 = landmark_position - position
		delta.y = 0.0
		var distance_sq: float = delta.length_squared()
		if distance_sq <= best_distance_sq:
			best_distance_sq = distance_sq
			best_id = landmark_id
	return best_id


func _begin_presentation_hold() -> void:
	_presentation_frames_remaining = maxi(GameConfig.photo_freeze_render_frames, 0)
	if _presentation_rect != null:
		_presentation_rect.visible = _presentation_frames_remaining > 0


func _update_presentation_hold() -> void:
	if _presentation_frames_remaining <= 0:
		if _presentation_rect != null:
			_presentation_rect.visible = false
		return
	_presentation_frames_remaining -= 1
	if _presentation_frames_remaining <= 0 and _presentation_rect != null:
		_presentation_rect.visible = false


func _setup_presentation_layer() -> void:
	_presentation_layer = CanvasLayer.new()
	_presentation_layer.name = "PhotoPresentationHold"
	_presentation_layer.layer = PRESENTATION_LAYER_INDEX
	add_child(_presentation_layer)
	_presentation_rect = ColorRect.new()
	_presentation_rect.name = "PhotoPresentationFlash"
	_presentation_rect.anchor_right = 1.0
	_presentation_rect.anchor_bottom = 1.0
	_presentation_rect.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_presentation_rect.grow_vertical = Control.GROW_DIRECTION_BOTH
	_presentation_rect.color = Color(1.0, 0.94, 0.82, 0.18)
	_presentation_rect.visible = false
	_presentation_layer.add_child(_presentation_rect)


func _setup_shutter_audio() -> void:
	_shutter_player = AudioStreamPlayer.new()
	_shutter_player.name = "PhotoShutterCue"
	var stream: AudioStreamGenerator = AudioStreamGenerator.new()
	stream.mix_rate = GameConfig.audio_mix_rate
	stream.buffer_length = GameConfig.audio_buffer_length
	_shutter_player.stream = stream
	add_child(_shutter_player)
	if DisplayServer.get_name() != "headless":
		call_deferred("_start_shutter_audio")


func _start_shutter_audio() -> void:
	if _shutter_player == null:
		return
	_shutter_player.play()
	_shutter_playback = _shutter_player.get_stream_playback() as AudioStreamGeneratorPlayback


func _play_shutter_cue() -> void:
	_shutter_envelope = 1.0


func _fill_shutter_audio() -> void:
	if _shutter_playback == null:
		return
	var frames_available: int = _shutter_playback.get_frames_available()
	for _i in range(frames_available):
		_shutter_playback.push_frame(_next_shutter_frame())


func _next_shutter_frame() -> Vector2:
	if _shutter_envelope <= 0.001:
		_shutter_envelope = 0.0
		return Vector2.ZERO
	var phase_step: float = TAU * SHUTTER_HZ / maxf(GameConfig.audio_mix_rate, 1.0)
	_shutter_phase += phase_step
	if _shutter_phase > TAU:
		_shutter_phase -= TAU
	var sample: float = sin(_shutter_phase) * SHUTTER_VOLUME * _shutter_envelope
	_shutter_envelope *= SHUTTER_DECAY_PER_FRAME
	return Vector2(sample, sample)
