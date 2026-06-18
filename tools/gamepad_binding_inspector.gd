extends Node

const CedarHollowHostScript: GDScript = preload("res://systems/render/cedar_hollow_host.gd")

# Verifies the gamepad binding slice end-to-end without a physical device. The
# bindings are injected at runtime by CedarHollowHost (project.godot is left
# untouched), so every check exercises the host input setup path:
#   1. after the CedarHollowHost input setup, every driving action has >= 1 JOYPAD
#      event (the acceptance gate);
#   2. host setup is idempotent (no duplicate joypad events on repeat);
#   3. analog steering structure -- steer_left/steer_right sit on opposite halves
#      of LEFT_X so the host's strength(L) - strength(R) read spans -1..+1;
#   4. analog trigger structure -- throttle=RT, brake=LT, reverse=LT;
#   5. keyboard bindings still intact alongside the new gamepad bindings.
#
# Gamepad hardware cannot be exercised headlessly; smooth analog FEEL is a
# feel-test the owner runs separately. This inspector proves the bindings exist
# and are wired to the right axes/buttons, which is all that is verifiable here.
# Note: the host script transitively depends on many class_names, so the global
# class cache must be warm (any project-open warms it; the standing suite runs
# 00_project_open first). If the host cannot instantiate (cold cache) the host
# checks fail loudly rather than false-green.

const DRIVING_ACTIONS: Array[StringName] = [
	&"throttle",
	&"brake",
	&"steer_left",
	&"steer_right",
	&"ebrake",
]
var _errors: PackedStringArray = PackedStringArray()
var _host_unavailable: bool = false
var _host: Node = null


func _ready() -> void:
	call_deferred("_inspect")


func _inspect() -> void:
	_check_host_setup_bindings()
	_check_idempotent()
	_check_analog_steer_structure()
	_check_analog_trigger_structure()
	_check_keyboard_intact()
	_finish()


func _check_host_setup_bindings() -> void:
	# Non-tautological host proof: strip every joypad event from every driving
	# action, run the host input setup ONCE, then require each driving action to
	# have >= 1 joypad event restored. This proves the host injects the bindings
	# rather than inheriting them from project.godot.
	var host: Node = _new_host()
	if host == null:
		return
	for action_name in DRIVING_ACTIONS:
		_strip_joypad_events(action_name)
	host.call("_ensure_default_input_map")
	for action_name in DRIVING_ACTIONS:
		if _joypad_event_count(action_name) == 0:
			_errors.append("host: action " + String(action_name) + " has no joypad event after host setup")


func _check_idempotent() -> void:
	var host: Node = _new_host()
	if host == null:
		return
	var action: StringName = &"throttle"
	host.call("_ensure_default_input_map")
	var before: int = _joypad_event_count(action)
	host.call("_ensure_default_input_map")
	var after: int = _joypad_event_count(action)
	if before == 0:
		_errors.append("idempotent: throttle had no joypad event after first host setup")
		return
	if after != before:
		_errors.append("idempotent: throttle joypad event count changed " + str(before) + " -> " + str(after) + " on second host setup")


func _check_analog_steer_structure() -> void:
	# steer_left = LEFT_X (-half), steer_right = LEFT_X (+half): opposite halves of
	# the SAME axis. strength(steer_left) is the magnitude of the negative
	# deflection and strength(steer_right) the magnitude of the positive deflection,
	# so the host's strength(steer_left) - strength(steer_right) read spans the full
	# analog -1..+1 range. Structural proof of analog steering.
	if not _has_motion(&"steer_left", JOY_AXIS_LEFT_X, -1.0):
		_errors.append("steer: steer_left missing LEFT_X axis_value -1.0")
	if not _has_motion(&"steer_right", JOY_AXIS_LEFT_X, 1.0):
		_errors.append("steer: steer_right missing LEFT_X axis_value 1.0")


func _check_analog_trigger_structure() -> void:
	if not _has_motion(&"throttle", JOY_AXIS_TRIGGER_RIGHT, 1.0):
		_errors.append("trigger: throttle missing TRIGGER_RIGHT axis_value 1.0")
	if not _has_motion(&"brake", JOY_AXIS_TRIGGER_LEFT, 1.0):
		_errors.append("trigger: brake missing TRIGGER_LEFT axis_value 1.0")
	if not _has_motion(&"reverse", JOY_AXIS_TRIGGER_LEFT, 1.0):
		_errors.append("trigger: reverse missing TRIGGER_LEFT axis_value 1.0")


func _check_keyboard_intact() -> void:
	var host: Node = _new_host()
	if host == null:
		return
	# Additive-only proof: every driving action still has its keyboard binding
	# alongside the new gamepad binding after host setup.
	host.call("_ensure_default_input_map")
	for action_name in DRIVING_ACTIONS:
		if _keyboard_event_count(action_name) == 0:
			_errors.append("keyboard: action " + String(action_name) + " lost its keyboard binding")


func _new_host() -> Node:
	# Instantiates CedarHollowHost ONCE (cached) WITHOUT adding it to the scene
	# tree, so _ready (which builds the world/vehicle/tile-streamer) never runs and
	# only the InputMap-touching input setup is exercised. Guards against a cold
	# class cache (first-ever project run) where the host script chain fails to
	# compile: .new() returns a non-null "zombie" object in that case, so
	# has_method() is the reliable signal. Record one clear error instead of
	# false-greening.
	if _host_unavailable:
		return null
	if _host != null:
		return _host
	var host: Node = CedarHollowHostScript.new() as Node
	if host == null or not host.has_method("_ensure_default_input_map"):
		if not _host_unavailable:
			_host_unavailable = true
			_errors.append("host: CedarHollowHost script failed to instantiate (cold class cache?); run after a project-open")
		return null
	_host = host
	return _host


func _joypad_event_count(action_name: StringName) -> int:
	var action_string: String = String(action_name)
	if not InputMap.has_action(action_string):
		return 0
	var count: int = 0
	for event in InputMap.action_get_events(action_string):
		if (event is InputEventJoypadMotion) or (event is InputEventJoypadButton):
			count += 1
	return count


func _keyboard_event_count(action_name: StringName) -> int:
	var action_string: String = String(action_name)
	if not InputMap.has_action(action_string):
		return 0
	var count: int = 0
	for event in InputMap.action_get_events(action_string):
		if event is InputEventKey:
			count += 1
	return count


func _has_motion(action_name: StringName, axis: int, axis_value: float) -> bool:
	var action_string: String = String(action_name)
	if not InputMap.has_action(action_string):
		return false
	for event in InputMap.action_get_events(action_string):
		var motion: InputEventJoypadMotion = event as InputEventJoypadMotion
		if motion != null and motion.axis == axis and is_equal_approx(motion.axis_value, axis_value):
			return true
	return false


func _strip_joypad_events(action_name: StringName) -> void:
	var action_string: String = String(action_name)
	if not InputMap.has_action(action_string):
		return
	var to_erase: Array[InputEvent] = []
	for event in InputMap.action_get_events(action_string):
		if (event is InputEventJoypadMotion) or (event is InputEventJoypadButton):
			to_erase.append(event as InputEvent)
	for event in to_erase:
		InputMap.action_erase_event(action_string, event)


func _finish() -> void:
	if _host != null:
		_host.free()
		_host = null
	if _errors.is_empty():
		print("ok: gamepad bindings injected by host setup, analog steer/trigger structure verified, keyboard intact")
		get_tree().quit(0)
		return
	for error in _errors:
		push_error(error)
	get_tree().quit(1)
