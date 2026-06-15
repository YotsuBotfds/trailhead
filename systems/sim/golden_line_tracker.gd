class_name GoldenLineTracker
extends Node

const DEFAULT_SEGMENT_ID: StringName = &"bog_bottom"
const DEFAULT_REPLAY_PATH: String = "res://tests/golden/cedar_hollow_bog_bottom_replay.json"
const MATCH_WINDOW_DIVISOR: int = 2
const INVALID_POSITION: Vector3 = Vector3(INF, INF, INF)

var _segment_id: StringName = DEFAULT_SEGMENT_ID
var _replay_path: String = DEFAULT_REPLAY_PATH
var _match_window_ticks: int = maxi(GameConfig.PHYSICS_TICKS_PER_SECOND / MATCH_WINDOW_DIVISOR, 1)
var _sample_ticks: Array[int] = []
var _sample_positions: Array[Vector3] = []
var _consecutive_match_ticks: int = 0
var _matched: bool = false
var _match_tick: int = -1
var _last_error_m: float = INF
var _load_error: String = ""


func _ready() -> void:
	if _sample_ticks.is_empty():
		load_golden_path()


func configure(replay_path: String = DEFAULT_REPLAY_PATH, segment_id: StringName = DEFAULT_SEGMENT_ID, match_window_ticks: int = 0) -> void:
	_replay_path = replay_path
	_segment_id = segment_id
	if match_window_ticks > 0:
		_match_window_ticks = match_window_ticks
	else:
		_match_window_ticks = maxi(GameConfig.PHYSICS_TICKS_PER_SECOND / MATCH_WINDOW_DIVISOR, 1)
	reset_match_state()
	load_golden_path()


func load_golden_path() -> bool:
	_sample_ticks.clear()
	_sample_positions.clear()
	_load_error = ""
	var file_path: String = _resolve_project_path(_replay_path)
	var file: FileAccess = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		_load_error = "could not open golden replay: " + _replay_path
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		_load_error = "golden replay was not a dictionary: " + _replay_path
		return false
	var samples_value: Variant = parsed.get("samples", [])
	if not (samples_value is Array):
		_load_error = "golden replay samples were not an array: " + _replay_path
		return false
	var samples: Array[Variant] = []
	for value in samples_value:
		samples.append(value)
	for value in samples:
		if not (value is Dictionary):
			continue
		var tick_value: Variant = value.get("tick", -1)
		var position_value: Variant = value.get("position", [])
		if not _is_number(tick_value) or not _is_vec3_array(position_value):
			continue
		_sample_ticks.append(int(tick_value))
		_sample_positions.append(_vec3_from_array(position_value))
	if _sample_ticks.size() < 2:
		_load_error = "golden replay needs at least two position samples: " + _replay_path
		_sample_ticks.clear()
		_sample_positions.clear()
		return false
	return true


func reset_match_state() -> void:
	_consecutive_match_ticks = 0
	_matched = false
	_match_tick = -1
	_last_error_m = INF


func sample_vehicle_state(vehicle_state: RefCounted, sim_tick: int) -> bool:
	if vehicle_state == null:
		return false
	var position_value: Variant = vehicle_state.get("position")
	if not (position_value is Vector3):
		return false
	return sample_position(position_value, sim_tick)


func sample_position(position: Vector3, sim_tick: int) -> bool:
	if _matched:
		return false
	if _sample_ticks.is_empty() and not load_golden_path():
		return false
	var golden_position: Vector3 = _golden_position_for_tick(sim_tick)
	if golden_position == INVALID_POSITION:
		_consecutive_match_ticks = 0
		_last_error_m = INF
		return false
	_last_error_m = position.distance_to(golden_position)
	if _last_error_m <= GameConfig.golden_position_tolerance_m:
		_consecutive_match_ticks += 1
	else:
		_consecutive_match_ticks = 0
	if _consecutive_match_ticks >= _match_window_ticks:
		_matched = true
		_match_tick = sim_tick
		EventBus.world_golden_line_matched.emit(_segment_id, sim_tick)
		return true
	return false


func has_matched() -> bool:
	return _matched


func match_tick() -> int:
	return _match_tick


func consecutive_match_ticks() -> int:
	return _consecutive_match_ticks


func match_window_ticks() -> int:
	return _match_window_ticks


func sample_count() -> int:
	return _sample_ticks.size()


func last_error_m() -> float:
	return _last_error_m


func load_error() -> String:
	return _load_error


func _golden_position_for_tick(sim_tick: int) -> Vector3:
	if _sample_ticks.size() < 2:
		return INVALID_POSITION
	var first_tick: int = _sample_ticks[0]
	var last_tick: int = _sample_ticks[_sample_ticks.size() - 1]
	if sim_tick < first_tick or sim_tick > last_tick:
		return INVALID_POSITION
	var lower_index: int = 0
	for index in range(_sample_ticks.size() - 1):
		var tick_a: int = _sample_ticks[index]
		var tick_b: int = _sample_ticks[index + 1]
		if sim_tick >= tick_a and sim_tick <= tick_b:
			lower_index = index
			break
	var lower_tick: int = _sample_ticks[lower_index]
	var upper_tick: int = _sample_ticks[lower_index + 1]
	var lower_position: Vector3 = _sample_positions[lower_index]
	var upper_position: Vector3 = _sample_positions[lower_index + 1]
	if upper_tick <= lower_tick:
		return lower_position
	var span: float = float(upper_tick - lower_tick)
	var alpha: float = clampf(float(sim_tick - lower_tick) / span, 0.0, 1.0)
	return lower_position.lerp(upper_position, alpha)


func _resolve_project_path(path: String) -> String:
	if path.begins_with("res://"):
		return ProjectSettings.globalize_path(path)
	return path


func _is_vec3_array(value: Variant) -> bool:
	if not (value is Array):
		return false
	return value.size() >= 3 and _is_number(value[0]) and _is_number(value[1]) and _is_number(value[2])


func _vec3_from_array(value: Variant) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


func _is_number(value: Variant) -> bool:
	return value is int or value is float
