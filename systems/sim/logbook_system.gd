class_name LogbookSystem
extends Node

const ROUTE_SEED_LENGTH: int = 6
const BASE36_DIGITS: String = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"

@export var pace_clock_path: NodePath = NodePath("")

var data: LogbookData:
	get:
		return _data

var session_seed: String:
	get:
		return _data.session_seed

var _pace_clock: Node = null
var _data: LogbookData = LogbookData.new()
var _visited_landmarks: Dictionary[StringName, bool] = {}
var _recovered_objects: Dictionary[StringName, bool] = {}


func configure(pace_clock: Node) -> void:
	_pace_clock = pace_clock
	if is_inside_tree():
		reset_session()


func _ready() -> void:
	_resolve_pace_clock()
	reset_session()
	_connect_event_bus()


func _exit_tree() -> void:
	_disconnect_event_bus()


func reset_session() -> void:
	_visited_landmarks.clear()
	_recovered_objects.clear()
	_data.reset(encode_session_seed_for_tick(_session_start_tick()))


func get_entries() -> Array[Variant]:
	return _data.get_entries()


func entry_count() -> int:
	return _data.entry_count()


func encode_session_seed_for_tick(start_tick: int) -> String:
	var base: int = mini(maxi(GameConfig.logbook_route_seed_base, 2), BASE36_DIGITS.length())
	var modulus: int = 1
	for _i in range(ROUTE_SEED_LENGTH):
		modulus *= base
	var value: int = start_tick % modulus
	if value < 0:
		value += modulus
	var reversed_digits: PackedStringArray = PackedStringArray()
	for _i in range(ROUTE_SEED_LENGTH):
		var digit: int = value % base
		reversed_digits.append(BASE36_DIGITS.substr(digit, 1))
		value = int(value / base)
	var seed: String = ""
	for index in range(ROUTE_SEED_LENGTH - 1, -1, -1):
		seed += reversed_digits[index]
	return seed


func _connect_event_bus() -> void:
	if not EventBus.world_recoverable_object_tagged.is_connected(_on_world_recoverable_object_tagged):
		EventBus.world_recoverable_object_tagged.connect(_on_world_recoverable_object_tagged)
	if not EventBus.world_photograph_taken.is_connected(_on_world_photograph_taken):
		EventBus.world_photograph_taken.connect(_on_world_photograph_taken)
	if not EventBus.world_reached_landmark.is_connected(_on_world_reached_landmark):
		EventBus.world_reached_landmark.connect(_on_world_reached_landmark)
	if not EventBus.sim_pace_clock_incident.is_connected(_on_sim_pace_clock_incident):
		EventBus.sim_pace_clock_incident.connect(_on_sim_pace_clock_incident)


func _disconnect_event_bus() -> void:
	if EventBus.world_recoverable_object_tagged.is_connected(_on_world_recoverable_object_tagged):
		EventBus.world_recoverable_object_tagged.disconnect(_on_world_recoverable_object_tagged)
	if EventBus.world_photograph_taken.is_connected(_on_world_photograph_taken):
		EventBus.world_photograph_taken.disconnect(_on_world_photograph_taken)
	if EventBus.world_reached_landmark.is_connected(_on_world_reached_landmark):
		EventBus.world_reached_landmark.disconnect(_on_world_reached_landmark)
	if EventBus.sim_pace_clock_incident.is_connected(_on_sim_pace_clock_incident):
		EventBus.sim_pace_clock_incident.disconnect(_on_sim_pace_clock_incident)


func _on_world_recoverable_object_tagged(object_id: StringName) -> void:
	if object_id == &"" or _recovered_objects.has(object_id):
		return
	_recovered_objects[object_id] = true
	_write_entry(LogbookData.ENTRY_RECOVER, object_id, _elapsed_ticks())


func _on_world_photograph_taken(nearest_landmark_id: StringName, sim_tick: int) -> void:
	if nearest_landmark_id == &"":
		return
	_write_entry(LogbookData.ENTRY_PHOTOGRAPH, nearest_landmark_id, sim_tick)


func _on_world_reached_landmark(landmark_id: StringName) -> void:
	if landmark_id == &"" or _visited_landmarks.has(landmark_id):
		return
	_visited_landmarks[landmark_id] = true
	_write_entry(LogbookData.ENTRY_LANDMARK_VISIT, landmark_id, _elapsed_ticks())


func _on_sim_pace_clock_incident(incident_type: StringName, elapsed_ticks: int) -> void:
	if incident_type == &"":
		return
	_write_entry(LogbookData.ENTRY_INCIDENT, incident_type, elapsed_ticks)


func _write_entry(entry_type: StringName, key: StringName, sim_tick: int) -> void:
	_data.add_entry(entry_type, key, sim_tick)
	EventBus.sim_logbook_entry_written.emit(entry_type, key, sim_tick)


func _resolve_pace_clock() -> void:
	if _pace_clock != null and is_instance_valid(_pace_clock):
		return
	if not pace_clock_path.is_empty():
		_pace_clock = get_node_or_null(pace_clock_path)


func _session_start_tick() -> int:
	if _pace_clock == null or not is_instance_valid(_pace_clock):
		return 0
	return int(_pace_clock.get("start_tick"))


func _elapsed_ticks() -> int:
	if _pace_clock == null or not is_instance_valid(_pace_clock):
		return 0
	return int(_pace_clock.get("elapsed_ticks"))
