extends Node

const REQUIRED_ACTIONS: Dictionary[StringName, Variant] = {
	&"throttle": [KEY_W, KEY_UP],
	&"brake": [KEY_S, KEY_DOWN],
	&"reverse": [KEY_S, KEY_DOWN],
	&"steer_left": [KEY_A, KEY_LEFT],
	&"steer_right": [KEY_D, KEY_RIGHT],
	&"ebrake": [KEY_SPACE],
	&"self_right": [KEY_R],
	&"cam_toggle": [KEY_C],
	&"map_toggle": [KEY_M],
	&"mood_toggle": [KEY_N],
	&"logbook_open": [KEY_TAB],
	&"photograph": [KEY_F]
}

var _errors: PackedStringArray = PackedStringArray()


func _ready() -> void:
	call_deferred("_inspect")


func _inspect() -> void:
	for action_key in REQUIRED_ACTIONS.keys():
		var action_name: StringName = action_key
		var expected_keycodes: Array[int] = _keycodes_from_variant(REQUIRED_ACTIONS[action_name])
		_require_input_action_keys(action_name, expected_keycodes)
	_finish()


func _require_input_action_keys(action_name: StringName, expected_keycodes: Array[int]) -> void:
	var action_string: String = String(action_name)
	if not InputMap.has_action(action_string):
		_errors.append("InputMap missing project action: " + action_string)
		return
	var observed_keycodes: Array[int] = []
	var event_count: int = 0
	for event in InputMap.action_get_events(action_string):
		var key_event: InputEventKey = event as InputEventKey
		if key_event == null:
			continue
		event_count += 1
		if key_event.physical_keycode != 0:
			observed_keycodes.append(key_event.physical_keycode)
		if key_event.keycode != 0:
			observed_keycodes.append(key_event.keycode)
	if event_count <= 0:
		_errors.append("InputMap action " + action_string + " has no default key events in project.godot")
	for keycode_value in expected_keycodes:
		var keycode: int = int(keycode_value)
		if not observed_keycodes.has(keycode):
			_errors.append("InputMap action " + action_string + " missing default keycode " + str(keycode))


func _keycodes_from_variant(value: Variant) -> Array[int]:
	var keycodes: Array[int] = []
	if not (value is Array):
		return keycodes
	for keycode_value: Variant in value:
		keycodes.append(int(keycode_value))
	return keycodes


func _finish() -> void:
	if _errors.is_empty():
		print("ok: project input map defaults are canonical")
		get_tree().quit(0)
		return
	for error in _errors:
		push_error(error)
	get_tree().quit(1)
