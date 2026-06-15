extends Node

const PhotographSystemScript: GDScript = preload("res://systems/render/photograph_system.gd")
const VehicleStateScript: GDScript = preload("res://systems/vehicle/vehicle_state.gd")
const CedarRoute: Resource = preload("res://data/routes/cedar_hollow.tres")
const NEXT_LANDMARK_GOLDEN_TICKS: int = 12

class StubVehicle:
	extends Node

	var state: RefCounted = null

	func _init(initial_state: RefCounted) -> void:
		state = initial_state

	func get_state() -> RefCounted:
		return state

var _errors: PackedStringArray = PackedStringArray()
var _events: Array[Variant] = []


func _ready() -> void:
	_ensure_photo_action()
	EventBus.world_photograph_taken.connect(_on_world_photograph_taken)
	call_deferred("_run")


func _run() -> void:
	_assert_photo_fires_at_threshold()
	_assert_photo_never_fires_above_threshold()
	if EventBus.world_photograph_taken.is_connected(_on_world_photograph_taken):
		EventBus.world_photograph_taken.disconnect(_on_world_photograph_taken)
	_finish()


func _assert_photo_fires_at_threshold() -> void:
	_events.clear()
	var state: RefCounted = VehicleStateScript.new()
	state.set("position", CedarRoute.call("landmark_position", &"old_cedar"))
	state.set("linear_velocity", Vector3(GameConfig.photo_max_speed_mps, 0.0, 0.0))
	var vehicle: StubVehicle = StubVehicle.new(state)
	var system: Node = PhotographSystemScript.new()
	add_child(vehicle)
	add_child(system)
	system.call("configure", CedarRoute, vehicle)
	Input.action_press(StringName("photograph"))
	for _i in range(GameConfig.photo_hold_ticks):
		system._physics_process(GameConfig.FIXED_DT)
	if _events.size() != 1:
		_errors.append("photo at threshold emitted " + str(_events.size()) + " events, expected 1")
	else:
		var event: Dictionary = _events[0] as Dictionary
		if StringName(event.get("nearest_landmark_id", &"")) != &"old_cedar":
			_errors.append("photo event nearest landmark was " + String(event.get("nearest_landmark_id", &"")) + ", expected old_cedar")
		if int(event.get("sim_tick", -1)) != GameConfig.photo_hold_ticks:
			_errors.append("photo event sim_tick was " + str(event.get("sim_tick", -1)) + ", expected " + str(GameConfig.photo_hold_ticks))
	if int(system.call("capture_count")) != 1:
		_errors.append("capture_count at threshold was " + str(system.call("capture_count")) + ", expected 1")
	if int(system.call("presentation_frames_remaining")) != GameConfig.photo_freeze_render_frames:
		_errors.append("presentation hold frames were " + str(system.call("presentation_frames_remaining")) + ", expected " + str(GameConfig.photo_freeze_render_frames))
	var tick_before_next_landmark: int = int(system.call("sim_tick"))
	for _i in range(NEXT_LANDMARK_GOLDEN_TICKS):
		system._physics_process(GameConfig.FIXED_DT)
		system._process(1.0 / 60.0)
	if int(system.call("sim_tick")) != tick_before_next_landmark + NEXT_LANDMARK_GOLDEN_TICKS:
		_errors.append("photo presentation hold stalled physics ticks before the next landmark")
	if int(system.call("presentation_frames_remaining")) != 0:
		_errors.append("presentation hold did not drain its render-frame counter")
	if _events.size() != 1:
		_errors.append("continued hold emitted duplicate photo events")
	Input.action_release(StringName("photograph"))
	system._physics_process(GameConfig.FIXED_DT)
	if int(system.call("held_ticks")) != 0:
		_errors.append("photo hold did not reset after input release")
	system.queue_free()
	vehicle.queue_free()


func _assert_photo_never_fires_above_threshold() -> void:
	_events.clear()
	var state: RefCounted = VehicleStateScript.new()
	state.set("position", CedarRoute.call("landmark_position", &"old_cedar"))
	state.set("linear_velocity", Vector3(GameConfig.photo_max_speed_mps + 0.01, 0.0, 0.0))
	var vehicle: StubVehicle = StubVehicle.new(state)
	var system: Node = PhotographSystemScript.new()
	add_child(vehicle)
	add_child(system)
	system.call("configure", CedarRoute, vehicle)
	Input.action_press(StringName("photograph"))
	for _i in range(GameConfig.photo_hold_ticks + 4):
		system._physics_process(GameConfig.FIXED_DT)
	if _events.size() != 0:
		_errors.append("photo above threshold emitted " + str(_events.size()) + " events, expected 0")
	if int(system.call("capture_count")) != 0:
		_errors.append("capture_count above threshold was " + str(system.call("capture_count")) + ", expected 0")
	if int(system.call("held_ticks")) != 0:
		_errors.append("photo hold accumulated while above speed threshold")
	Input.action_release(StringName("photograph"))
	system.queue_free()
	vehicle.queue_free()


func _ensure_photo_action() -> void:
	if not InputMap.has_action("photograph"):
		InputMap.add_action("photograph", 0.2)


func _on_world_photograph_taken(nearest_landmark_id: StringName, sim_tick: int) -> void:
	_events.append({
		"nearest_landmark_id": nearest_landmark_id,
		"sim_tick": sim_tick,
	})


func _finish() -> void:
	if _errors.is_empty():
		print("ok: photo stationary fixture")
		get_tree().quit(0)
		return
	for error in _errors:
		push_error(error)
	get_tree().quit(1)
