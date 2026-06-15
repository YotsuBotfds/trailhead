class_name LogbookData
extends Resource

const ENTRY_LANDMARK_VISIT: StringName = &"landmark_visit"
const ENTRY_RECOVER: StringName = &"recover"
const ENTRY_PHOTOGRAPH: StringName = &"photograph"
const ENTRY_INCIDENT: StringName = &"incident"
const SECONDS_PER_MINUTE: int = 60

var session_seed: String = ""
var entries: Array[Variant]:
	get:
		return get_entries()

var _entries: Array[Variant] = []


func reset(new_session_seed: String) -> void:
	session_seed = new_session_seed
	_entries.clear()


func add_entry(entry_type: StringName, key: StringName, sim_tick: int) -> Dictionary[String, Variant]:
	var entry: Dictionary[String, Variant] = {
		"type": entry_type,
		"key": key,
		"sim_tick": sim_tick,
		"display_text": display_text_for_entry(entry_type, key, sim_tick),
	}
	_entries.append(entry)
	return _copy_entry(entry)


func get_entries() -> Array[Variant]:
	var copy: Array[Variant] = []
	for entry_value: Variant in _entries:
		var entry: Dictionary[String, Variant] = entry_value
		copy.append(_copy_entry(entry))
	return copy


func entry_count() -> int:
	return _entries.size()


static func display_text_for_entry(entry_type: StringName, key: StringName, sim_tick: int) -> String:
	var prefix: String = "[" + display_time_for_tick(sim_tick) + "] "
	if entry_type == ENTRY_LANDMARK_VISIT:
		return prefix + "Reached " + String(key) + "."
	if entry_type == ENTRY_RECOVER:
		return prefix + "Tagged: " + String(key) + "."
	if entry_type == ENTRY_PHOTOGRAPH:
		return prefix + "Photo near " + String(key) + "."
	if entry_type == ENTRY_INCIDENT:
		return prefix + String(key) + "."
	return prefix + String(entry_type) + ": " + String(key) + "."


static func display_time_for_tick(sim_tick: int) -> String:
	var ticks_per_second: int = maxi(GameConfig.pace_clock_display_ticks_per_second, 1)
	var total_seconds: int = sim_tick / ticks_per_second
	var minutes: int = total_seconds / SECONDS_PER_MINUTE
	var seconds: int = total_seconds % SECONDS_PER_MINUTE
	return "%d:%02d" % [minutes, seconds]


func _copy_entry(entry: Dictionary[String, Variant]) -> Dictionary[String, Variant]:
	var copy: Dictionary[String, Variant] = {
		"type": StringName(entry.get("type", &"")),
		"key": StringName(entry.get("key", &"")),
		"sim_tick": int(entry.get("sim_tick", 0)),
		"display_text": String(entry.get("display_text", "")),
	}
	return copy
