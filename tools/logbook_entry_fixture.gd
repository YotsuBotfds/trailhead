extends Node

const LogbookSystemScript: GDScript = preload("res://systems/sim/logbook_system.gd")
const PaceClockSystemScript: GDScript = preload("res://systems/sim/pace_clock_system.gd")
const OLD_CEDAR_TICK: int = 12
const DUPLICATE_LANDMARK_TICK: int = 18
const RECOVER_TICK: int = 24
const DUPLICATE_RECOVER_TICK: int = 30
const PHOTO_SIGNAL_TICK: int = 142
const INCIDENT_TICK: int = 48
const SECOND_LANDMARK_TICK: int = 60

var _clock: Node = null
var _logbook: Node = null
var _written_events: Array[Variant] = []
var _errors: PackedStringArray = PackedStringArray()


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_clock = PaceClockSystemScript.new() as Node
	_logbook = LogbookSystemScript.new() as Node
	if _clock == null:
		_errors.append("PaceClockSystem could not be instantiated")
		_finish()
		return
	if _logbook == null:
		_errors.append("LogbookSystem could not be instantiated")
		_finish()
		return
	add_child(_clock)
	_logbook.call("configure", _clock)
	add_child(_logbook)

	if not EventBus.sim_logbook_entry_written.is_connected(_on_sim_logbook_entry_written):
		EventBus.sim_logbook_entry_written.connect(_on_sim_logbook_entry_written)

	_require_string("session seed", String(_logbook.get("session_seed")), "000000")
	_require_string("seed one digit", String(_logbook.call("encode_session_seed_for_tick", 35)), "00000Z")
	_require_string("seed base carry", String(_logbook.call("encode_session_seed_for_tick", 36)), "000010")
	_require_string("seed modulo", String(_logbook.call("encode_session_seed_for_tick", 2176782336)), "000000")

	await _advance_to_tick(OLD_CEDAR_TICK)
	EventBus.world_reached_landmark.emit(&"old_cedar")
	_require_entry_count(1, "first landmark")

	await _advance_to_tick(DUPLICATE_LANDMARK_TICK)
	EventBus.world_reached_landmark.emit(&"old_cedar")
	_require_entry_count(1, "duplicate landmark")

	await _advance_to_tick(RECOVER_TICK)
	EventBus.world_recoverable_object_tagged.emit(&"ro_01_water_bottle")
	_require_entry_count(2, "first recover")

	await _advance_to_tick(DUPLICATE_RECOVER_TICK)
	EventBus.world_recoverable_object_tagged.emit(&"ro_01_water_bottle")
	_require_entry_count(2, "duplicate recover")

	EventBus.world_photograph_taken.emit(&"old_cedar", PHOTO_SIGNAL_TICK)
	_require_entry_count(3, "photograph")

	await _advance_to_tick(INCIDENT_TICK)
	EventBus.vehicle_flipped_over.emit()
	_require_entry_count(4, "incident")

	await _advance_to_tick(SECOND_LANDMARK_TICK)
	EventBus.world_reached_landmark.emit(&"overlook_ridge")
	_require_entry_count(5, "second landmark")

	_require_entry(0, LogbookData.ENTRY_LANDMARK_VISIT, &"old_cedar", OLD_CEDAR_TICK, "[0:00] Reached old_cedar.")
	_require_entry(1, LogbookData.ENTRY_RECOVER, &"ro_01_water_bottle", RECOVER_TICK, "[0:00] Tagged: ro_01_water_bottle.")
	_require_entry(2, LogbookData.ENTRY_PHOTOGRAPH, &"old_cedar", PHOTO_SIGNAL_TICK, "[0:01] Photo near old_cedar.")
	_require_entry(3, LogbookData.ENTRY_INCIDENT, &"vehicle_flipped_over", INCIDENT_TICK, "[0:00] vehicle_flipped_over.")
	_require_entry(4, LogbookData.ENTRY_LANDMARK_VISIT, &"overlook_ridge", SECOND_LANDMARK_TICK, "[0:00] Reached overlook_ridge.")
	_require_written_events_match_entries()
	_finish()


func _advance_to_tick(target_tick: int) -> void:
	while int(_clock.get("elapsed_ticks")) < target_tick:
		await get_tree().physics_frame


func _on_sim_logbook_entry_written(entry_type: StringName, key: StringName, sim_tick: int) -> void:
	var event: Dictionary[String, Variant] = {
		"type": entry_type,
		"key": key,
		"sim_tick": sim_tick,
	}
	_written_events.append(event)


func _entries() -> Array[Variant]:
	var entries: Array[Variant] = _logbook.call("get_entries")
	return entries


func _require_entry_count(expected_count: int, label: String) -> void:
	var observed_count: int = int(_logbook.call("entry_count"))
	if observed_count != expected_count:
		_errors.append(label + " expected " + str(expected_count) + " entries, got " + str(observed_count))


func _require_entry(index: int, expected_type: StringName, expected_key: StringName, expected_tick: int, expected_text: String) -> void:
	var entries: Array[Variant] = _entries()
	if index < 0 or index >= entries.size():
		_errors.append("missing logbook entry at index " + str(index))
		return
	var entry: Dictionary[String, Variant] = entries[index]
	var observed_type: StringName = StringName(entry.get("type", &""))
	var observed_key: StringName = StringName(entry.get("key", &""))
	var observed_tick: int = int(entry.get("sim_tick", -1))
	var observed_text: String = String(entry.get("display_text", ""))
	if observed_type != expected_type:
		_errors.append("entry " + str(index) + " expected type " + String(expected_type) + ", got " + String(observed_type))
	if observed_key != expected_key:
		_errors.append("entry " + str(index) + " expected key " + String(expected_key) + ", got " + String(observed_key))
	if observed_tick != expected_tick:
		_errors.append("entry " + str(index) + " expected tick " + str(expected_tick) + ", got " + str(observed_tick))
	if observed_text != expected_text:
		_errors.append("entry " + str(index) + " expected text " + expected_text + ", got " + observed_text)


func _require_written_events_match_entries() -> void:
	var entries: Array[Variant] = _entries()
	if _written_events.size() != entries.size():
		_errors.append("sim_logbook_entry_written emitted " + str(_written_events.size()) + " events for " + str(entries.size()) + " entries")
		return
	for index in range(entries.size()):
		var entry: Dictionary[String, Variant] = entries[index]
		var event: Dictionary[String, Variant] = _written_events[index]
		var entry_type: StringName = StringName(entry.get("type", &""))
		var event_type: StringName = StringName(event.get("type", &""))
		var entry_key: StringName = StringName(entry.get("key", &""))
		var event_key: StringName = StringName(event.get("key", &""))
		var entry_tick: int = int(entry.get("sim_tick", -1))
		var event_tick: int = int(event.get("sim_tick", -2))
		if event_type != entry_type or event_key != entry_key or event_tick != entry_tick:
			_errors.append("written event " + str(index) + " did not match its logbook entry")


func _require_string(label: String, actual: String, expected: String) -> void:
	if actual != expected:
		_errors.append(label + " expected " + expected + ", got " + actual)


func _finish() -> void:
	if EventBus.sim_logbook_entry_written.is_connected(_on_sim_logbook_entry_written):
		EventBus.sim_logbook_entry_written.disconnect(_on_sim_logbook_entry_written)
	if _logbook != null:
		_logbook.queue_free()
	if _clock != null:
		_clock.queue_free()

	if _errors.is_empty():
		print("ok: logbook entry fixture")
		get_tree().quit(0)
		return
	for error in _errors:
		push_error(error)
	get_tree().quit(1)
