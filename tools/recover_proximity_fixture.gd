extends Node

const RecoverableObjectScript: GDScript = preload("res://systems/world/recoverable_object.gd")
const VehicleStateScript: GDScript = preload("res://systems/vehicle/vehicle_state.gd")

var _errors: PackedStringArray = PackedStringArray()
var _events_by_id: Dictionary[StringName, int] = {}
var _event_sequence: Array[StringName] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	if not EventBus.world_recoverable_object_tagged.is_connected(_on_world_recoverable_object_tagged):
		EventBus.world_recoverable_object_tagged.connect(_on_world_recoverable_object_tagged)
	_run_fixture()
	if EventBus.world_recoverable_object_tagged.is_connected(_on_world_recoverable_object_tagged):
		EventBus.world_recoverable_object_tagged.disconnect(_on_world_recoverable_object_tagged)
	if _errors.is_empty():
		print("ok: recover proximity fixture")
		get_tree().quit(0)
		return
	for error in _errors:
		push_error(error)
	get_tree().quit(1)


func _run_fixture() -> void:
	_assert_exact_hold_fires_once()
	_assert_far_distance_never_fires()
	_assert_exit_resets_hold_ticks()
	_assert_second_approach_is_idempotent()


func _assert_exact_hold_fires_once() -> void:
	var object_id: StringName = &"fixture_exact_hold"
	var recoverable: Node3D = _make_recoverable(object_id, Vector3.ZERO)
	var state: RefCounted = _make_state(Vector3(GameConfig.recover_radius - 0.01, 0.0, 0.0))
	for tick in range(GameConfig.recover_hold_ticks - 1):
		var fired: bool = bool(recoverable.call("sample_vehicle_state", state))
		if fired:
			_errors.append(String(object_id) + " fired early at tick " + str(tick))
	var early_count: int = _event_count(object_id)
	if early_count != 0:
		_errors.append(String(object_id) + " emitted before required hold ticks")
	var final_fired: bool = bool(recoverable.call("sample_vehicle_state", state))
	if not final_fired:
		_errors.append(String(object_id) + " did not return true on the tagging tick")
	_require_event_count(object_id, 1)


func _assert_far_distance_never_fires() -> void:
	var object_id: StringName = &"fixture_far_distance"
	var recoverable: Node3D = _make_recoverable(object_id, Vector3.ZERO)
	var state: RefCounted = _make_state(Vector3(GameConfig.recover_radius + 0.02, 0.0, 0.0))
	for tick in range(GameConfig.recover_hold_ticks + 8):
		var fired: bool = bool(recoverable.call("sample_vehicle_state", state))
		if fired:
			_errors.append(String(object_id) + " fired outside radius at tick " + str(tick))
	_require_event_count(object_id, 0)


func _assert_exit_resets_hold_ticks() -> void:
	var object_id: StringName = &"fixture_exit_resets"
	var recoverable: Node3D = _make_recoverable(object_id, Vector3.ZERO)
	var inside_state: RefCounted = _make_state(Vector3(GameConfig.recover_radius - 0.01, 0.0, 0.0))
	var outside_state: RefCounted = _make_state(Vector3(GameConfig.recover_radius + 0.02, 0.0, 0.0))
	for tick in range(GameConfig.recover_hold_ticks - 1):
		var fired_inside: bool = bool(recoverable.call("sample_vehicle_state", inside_state))
		if fired_inside:
			_errors.append(String(object_id) + " fired before reset setup at tick " + str(tick))
	var fired_outside: bool = bool(recoverable.call("sample_vehicle_state", outside_state))
	if fired_outside:
		_errors.append(String(object_id) + " fired while exiting radius")
	var held_ticks_after_exit: int = int(recoverable.call("hold_ticks"))
	if held_ticks_after_exit != 0:
		_errors.append(String(object_id) + " hold ticks did not reset after exit")
	for tick in range(GameConfig.recover_hold_ticks - 1):
		var fired_after_reset: bool = bool(recoverable.call("sample_vehicle_state", inside_state))
		if fired_after_reset:
			_errors.append(String(object_id) + " fired without a fresh full hold at tick " + str(tick))
	_require_event_count(object_id, 0)
	var final_fired: bool = bool(recoverable.call("sample_vehicle_state", inside_state))
	if not final_fired:
		_errors.append(String(object_id) + " did not fire after a fresh full hold")
	_require_event_count(object_id, 1)


func _assert_second_approach_is_idempotent() -> void:
	var object_id: StringName = &"fixture_idempotent"
	var recoverable: Node3D = _make_recoverable(object_id, Vector3.ZERO)
	var inside_state: RefCounted = _make_state(Vector3(GameConfig.recover_radius - 0.01, 0.0, 0.0))
	var outside_state: RefCounted = _make_state(Vector3(GameConfig.recover_radius + 0.02, 0.0, 0.0))
	for tick in range(GameConfig.recover_hold_ticks):
		recoverable.call("sample_vehicle_state", inside_state)
	_require_event_count(object_id, 1)
	for tick in range(GameConfig.recover_hold_ticks):
		recoverable.call("sample_vehicle_state", outside_state)
	for tick in range(GameConfig.recover_hold_ticks * 2):
		var fired_again: bool = bool(recoverable.call("sample_vehicle_state", inside_state))
		if fired_again:
			_errors.append(String(object_id) + " returned true after it was already tagged at tick " + str(tick))
	_require_event_count(object_id, 1)
	if not bool(recoverable.call("was_tagged")):
		_errors.append(String(object_id) + " did not retain tagged state")


func _make_recoverable(object_id: StringName, position: Vector3) -> Node3D:
	var recoverable: Node3D = RecoverableObjectScript.new() as Node3D
	recoverable.name = String(object_id)
	recoverable.call("configure", object_id, position)
	add_child(recoverable)
	return recoverable


func _make_state(position: Vector3) -> RefCounted:
	var state: RefCounted = VehicleStateScript.new()
	state.set("position", position)
	state.set("linear_velocity", Vector3.ZERO)
	return state


func _require_event_count(object_id: StringName, expected_count: int) -> void:
	var observed_count: int = _event_count(object_id)
	if observed_count != expected_count:
		_errors.append(String(object_id) + " expected " + str(expected_count) + " events, got " + str(observed_count))


func _event_count(object_id: StringName) -> int:
	if not _events_by_id.has(object_id):
		return 0
	return _events_by_id[object_id]


func _on_world_recoverable_object_tagged(object_id: StringName) -> void:
	_event_sequence.append(object_id)
	var count: int = _event_count(object_id)
	_events_by_id[object_id] = count + 1
