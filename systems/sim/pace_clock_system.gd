extends Node

const SECONDS_PER_MINUTE: int = 60
const INCIDENT_FLIPPED_OVER: StringName = &"vehicle_flipped_over"
const INCIDENT_RECOVERED_TO_TRAIL: StringName = &"vehicle_recovered_to_trail"

var start_tick: int:
	get:
		return _start_tick

var elapsed_ticks: int:
	get:
		return _elapsed_ticks

var landmark_records: Array[Variant]:
	get:
		return _landmark_records.duplicate(true)

var incident_records: Array[Variant]:
	get:
		return _incident_records.duplicate(true)

var _start_tick: int = 0
var _elapsed_ticks: int = 0
var _landmark_records: Array[Variant] = []
var _incident_records: Array[Variant] = []


func _ready() -> void:
	reset()
	_connect_event_bus()


func _exit_tree() -> void:
	_disconnect_event_bus()


func _physics_process(_delta: float) -> void:
	_elapsed_ticks += 1


func reset() -> void:
	_start_tick = 0
	_elapsed_ticks = 0
	_landmark_records.clear()
	_incident_records.clear()


func get_elapsed_display_text() -> String:
	return display_text_for_ticks(_elapsed_ticks)


func display_text_for_ticks(ticks: int) -> String:
	var ticks_per_second: int = maxi(GameConfig.pace_clock_display_ticks_per_second, 1)
	var total_seconds: int = ticks / ticks_per_second
	var minutes: int = total_seconds / SECONDS_PER_MINUTE
	var seconds: int = total_seconds % SECONDS_PER_MINUTE
	return "%d:%02d" % [minutes, seconds]


func get_landmark_records() -> Array[Variant]:
	return _landmark_records.duplicate(true)


func get_incident_records() -> Array[Variant]:
	return _incident_records.duplicate(true)


func _connect_event_bus() -> void:
	if not EventBus.vehicle_flipped_over.is_connected(_on_vehicle_flipped_over):
		EventBus.vehicle_flipped_over.connect(_on_vehicle_flipped_over)
	if not EventBus.vehicle_recovered_to_trail.is_connected(_on_vehicle_recovered_to_trail):
		EventBus.vehicle_recovered_to_trail.connect(_on_vehicle_recovered_to_trail)
	if not EventBus.world_reached_landmark.is_connected(_on_world_reached_landmark):
		EventBus.world_reached_landmark.connect(_on_world_reached_landmark)


func _disconnect_event_bus() -> void:
	if EventBus.vehicle_flipped_over.is_connected(_on_vehicle_flipped_over):
		EventBus.vehicle_flipped_over.disconnect(_on_vehicle_flipped_over)
	if EventBus.vehicle_recovered_to_trail.is_connected(_on_vehicle_recovered_to_trail):
		EventBus.vehicle_recovered_to_trail.disconnect(_on_vehicle_recovered_to_trail)
	if EventBus.world_reached_landmark.is_connected(_on_world_reached_landmark):
		EventBus.world_reached_landmark.disconnect(_on_world_reached_landmark)


func _on_vehicle_flipped_over() -> void:
	_record_incident(INCIDENT_FLIPPED_OVER)


func _on_vehicle_recovered_to_trail(_from_position: Vector3, _to_position: Vector3) -> void:
	_record_incident(INCIDENT_RECOVERED_TO_TRAIL)


func _on_world_reached_landmark(landmark_id: StringName) -> void:
	var record: Dictionary[String, Variant] = {
		"landmark_id": landmark_id,
		"elapsed_ticks": _elapsed_ticks
	}
	_landmark_records.append(record)


func _record_incident(incident_type: StringName) -> void:
	var record: Dictionary[String, Variant] = {
		"incident_type": incident_type,
		"elapsed_ticks": _elapsed_ticks
	}
	_incident_records.append(record)
	EventBus.sim_pace_clock_incident.emit(incident_type, _elapsed_ticks)
