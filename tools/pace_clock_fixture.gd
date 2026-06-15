extends Node

const PaceClockSystemScript: GDScript = preload("res://systems/sim/pace_clock_system.gd")
const FIRST_INCIDENT_TICK: int = 48
const RECOVERY_INCIDENT_TICK: int = 72
const FIRST_LANDMARK_TICK: int = 96
const DISPLAY_SAMPLE_TICK: int = 120
const SECOND_LANDMARK_TICK: int = 144

var _clock: Node = null
var _incident_events: Array[Variant] = []
var _errors: PackedStringArray = PackedStringArray()


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_clock = PaceClockSystemScript.new() as Node
	if _clock == null:
		_errors.append("PaceClockSystem could not be instantiated")
		_finish()
		return
	add_child(_clock)

	if not EventBus.sim_pace_clock_incident.is_connected(_on_sim_pace_clock_incident):
		EventBus.sim_pace_clock_incident.connect(_on_sim_pace_clock_incident)

	await _advance_to_tick(1)
	_require_int("start_tick", int(_clock.get("start_tick")), 0)
	_require_int("elapsed after first physics tick", int(_clock.get("elapsed_ticks")), 1)

	await _advance_to_tick(FIRST_INCIDENT_TICK)
	EventBus.vehicle_flipped_over.emit()
	_require_incident_event(0, &"vehicle_flipped_over", FIRST_INCIDENT_TICK)

	await _advance_to_tick(RECOVERY_INCIDENT_TICK)
	EventBus.vehicle_recovered_to_trail.emit(Vector3.ZERO, Vector3(1.0, 0.0, 0.0))
	_require_incident_event(1, &"vehicle_recovered_to_trail", RECOVERY_INCIDENT_TICK)

	await _advance_to_tick(FIRST_LANDMARK_TICK)
	EventBus.world_reached_landmark.emit(&"old_cedar")

	await _advance_to_tick(DISPLAY_SAMPLE_TICK)
	_require_string("display text at one second", String(_clock.call("get_elapsed_display_text")), "0:01")

	await _advance_to_tick(SECOND_LANDMARK_TICK)
	EventBus.world_reached_landmark.emit(&"overlook_ridge")

	_require_int("elapsed at final sample", int(_clock.get("elapsed_ticks")), SECOND_LANDMARK_TICK)
	_require_landmark_record(0, &"old_cedar", FIRST_LANDMARK_TICK)
	_require_landmark_record(1, &"overlook_ridge", SECOND_LANDMARK_TICK)
	_require_clock_incident_record(0, &"vehicle_flipped_over", FIRST_INCIDENT_TICK)
	_require_clock_incident_record(1, &"vehicle_recovered_to_trail", RECOVERY_INCIDENT_TICK)
	_finish()


func _advance_to_tick(target_tick: int) -> void:
	while int(_clock.get("elapsed_ticks")) < target_tick:
		await get_tree().physics_frame


func _on_sim_pace_clock_incident(incident_type: StringName, elapsed_ticks: int) -> void:
	var record: Dictionary[String, Variant] = {
		"incident_type": incident_type,
		"elapsed_ticks": elapsed_ticks
	}
	_incident_events.append(record)


func _require_int(label: String, actual: int, expected: int) -> void:
	if actual != expected:
		_errors.append(label + " expected " + str(expected) + ", got " + str(actual))


func _require_string(label: String, actual: String, expected: String) -> void:
	if actual != expected:
		_errors.append(label + " expected " + expected + ", got " + actual)


func _require_incident_event(index: int, expected_type: StringName, expected_tick: int) -> void:
	if index < 0 or index >= _incident_events.size():
		_errors.append("missing sim_pace_clock_incident at index " + str(index))
		return
	var record: Dictionary[String, Variant] = _incident_events[index]
	_require_record(record, "incident event " + str(index), expected_type, expected_tick, "incident_type")


func _require_clock_incident_record(index: int, expected_type: StringName, expected_tick: int) -> void:
	var records: Array[Variant] = _clock.call("get_incident_records")
	if index < 0 or index >= records.size():
		_errors.append("missing clock incident record at index " + str(index))
		return
	var record: Dictionary[String, Variant] = records[index]
	_require_record(record, "clock incident record " + str(index), expected_type, expected_tick, "incident_type")


func _require_landmark_record(index: int, expected_landmark_id: StringName, expected_tick: int) -> void:
	var records: Array[Variant] = _clock.call("get_landmark_records")
	if index < 0 or index >= records.size():
		_errors.append("missing landmark record at index " + str(index))
		return
	var record: Dictionary[String, Variant] = records[index]
	_require_record(record, "landmark record " + str(index), expected_landmark_id, expected_tick, "landmark_id")


func _require_record(record: Dictionary[String, Variant], label: String, expected_key: StringName, expected_tick: int, key_field: String) -> void:
	if not record.has(key_field):
		_errors.append(label + " missing " + key_field)
		return
	if not record.has("elapsed_ticks"):
		_errors.append(label + " missing elapsed_ticks")
		return
	var observed_key: StringName = StringName(record[key_field])
	var observed_tick: int = int(record["elapsed_ticks"])
	if observed_key != expected_key:
		_errors.append(label + " expected " + String(expected_key) + ", got " + String(observed_key))
	if observed_tick != expected_tick:
		_errors.append(label + " expected tick " + str(expected_tick) + ", got " + str(observed_tick))


func _finish() -> void:
	if EventBus.sim_pace_clock_incident.is_connected(_on_sim_pace_clock_incident):
		EventBus.sim_pace_clock_incident.disconnect(_on_sim_pace_clock_incident)
	if _clock != null:
		_clock.queue_free()

	if _errors.is_empty():
		print("ok: PaceClockSystem ticks, incidents, and landmark records are deterministic")
		get_tree().quit(0)
		return
	for error in _errors:
		push_error(error)
	get_tree().quit(1)
