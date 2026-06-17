printf 'run: tile streamer seam hitch regression\n'

fixture_script="tests/out/tile_streamer_seam_hitch_fixture.gd"
fixture_scene="tests/out/tile_streamer_seam_hitch_fixture.tscn"
mkdir -p tests/out

cat > "$fixture_script" <<'GDSCRIPT'
extends Node

const REGION_ID: String = "spike_1km"
const START_POSITION: Vector3 = Vector3(499.995, -0.18, 450.0)
const CROSS_POSITION: Vector3 = Vector3(500.05, -0.18, 450.0)
const START_YAW_DEG: float = -90.0
const SEAM_X: float = 500.0
const DRIVE_TICKS: int = 180
const PRIME_TIMEOUT_TICKS: int = 120
const END_ACTIVE_TIMEOUT_TICKS: int = 160
const MAX_INTERFRAME_DELTA_M: float = 0.35
const CLAMP_EPSILON: float = 0.000001
const START_VELOCITY: Vector3 = Vector3(8.0, 0.0, 0.0)
const VehicleInputScript: GDScript = preload("res://systems/vehicle/vehicle_input.gd")
const VehicleContaminationStateScript: GDScript = preload("res://systems/vehicle/vehicle_contamination_state.gd")
const VehicleStateScript: GDScript = preload("res://systems/vehicle/vehicle_state.gd")
const VehicleControllerScript: GDScript = preload("res://systems/vehicle/vehicle_controller.gd")
const RaycastVehicleControllerScript: GDScript = preload("res://systems/vehicle/raycast_vehicle_controller.gd")
const VehicleScene: PackedScene = preload("res://scenes/vehicle.tscn")

var _errors: PackedStringArray = PackedStringArray()
var _vehicle: Node = null
var _body: RigidBody3D = null
var _tick: int = 0
var _max_fixture_delta: float = 0.0
var _previous_position: Vector3 = Vector3.ZERO
var _has_previous_position: bool = false
var _max_position_delta: float = 0.0
var _crossed: bool = false
var _cross_tick: int = -1
var _end_active_at_cross: bool = false
var _deferred_before_drive: int = 0
var _deferred_at_cross: int = 0
var _end_active_after_cross: bool = false


func _ready() -> void:
	set_physics_process(true)
	call_deferred("_run")


func _physics_process(delta: float) -> void:
	_max_fixture_delta = maxf(_max_fixture_delta, maxf(delta, 0.0))


func _run() -> void:
	var streamer: Node = get_node_or_null("/root/TileStreamer")
	if streamer == null:
		_errors.append("TileStreamer autoload was not registered")
		_finish(null, [], [])
		return

	streamer.call("set_worker_count_for_tests", 1)
	_vehicle = VehicleScene.instantiate()
	add_child(_vehicle)
	_body = _vehicle.get_node_or_null("PhysicsBody") as RigidBody3D
	if _body == null:
		_errors.append("vehicle PhysicsBody was not created")
		_finish(streamer, [], [])
		return

	var spawn: Transform3D = Transform3D(Basis(Vector3.UP, deg_to_rad(START_YAW_DEG)), START_POSITION)
	_vehicle.call("reset_to", spawn)
	_body.freeze = true
	_body.sleeping = false
	streamer.call("configure_region", REGION_ID, _body)

	var start_active_cells: Array[Vector2i] = _expected_active_cells(streamer, START_POSITION)
	if not await _wait_for_active_cells(streamer, start_active_cells, PRIME_TIMEOUT_TICKS):
		_errors.append(
			"start active set did not prime before timeout; got "
			+ _cells_to_string(_active_cells(streamer))
		)
		_finish(streamer, start_active_cells, [])
		return

	var end_position: Vector3 = Vector3(SEAM_X + 0.2, START_POSITION.y, START_POSITION.z)
	var end_active_cells: Array[Vector2i] = _expected_active_cells(streamer, end_position)
	var new_end_cells: Array[Vector2i] = _cell_difference(end_active_cells, start_active_cells)
	streamer.call("forget_ready_cells_for_tests", new_end_cells)
	var missing_ready_new_cells: Array[Vector2i] = _cell_difference(new_end_cells, _ready_cells(streamer))
	if missing_ready_new_cells.is_empty():
		_errors.append("fixture did not catch an unready seam prefetch cell before drive")

	_deferred_before_drive = int(streamer.call("deferred_activation_count"))
	var cross_spawn: Transform3D = Transform3D(Basis(Vector3.UP, deg_to_rad(START_YAW_DEG)), CROSS_POSITION)
	streamer.call("set_fixed_world_position", CROSS_POSITION)
	_set_body_state(cross_spawn, START_VELOCITY, Vector3.ZERO)
	_body.freeze = false
	_body.sleeping = false
	_record_position()

	var input: RefCounted = VehicleInputScript.new()
	input.set("throttle", 1.0)
	input.set("steer", 0.0)
	input.set("brake", 0.0)
	input.set("ebrake", false)
	input.set("self_right", false)

	for _i in range(DRIVE_TICKS):
		_vehicle.call("apply_input", input)
		await get_tree().physics_frame
		_tick += 1
		_record_position()
		_capture_crossing(streamer, end_active_cells)
		if _crossed:
			break

	if not _crossed:
		_errors.append("vehicle did not cross seam x=" + str(SEAM_X) + " within drive window")
	else:
		for _i in range(END_ACTIVE_TIMEOUT_TICKS):
			if _cell_arrays_equal(_active_cells(streamer), end_active_cells):
				_end_active_after_cross = true
				break
			_vehicle.call("apply_input", input)
			await get_tree().physics_frame
			_tick += 1
			_record_position()

	_assert_streamer_contract(streamer)
	_finish(streamer, start_active_cells, end_active_cells)


func _capture_crossing(streamer: Node, end_active_cells: Array[Vector2i]) -> void:
	if _crossed or _body == null:
		return
	if _body.global_position.x < SEAM_X:
		return
	_crossed = true
	_cross_tick = _tick
	_deferred_at_cross = int(streamer.call("deferred_activation_count"))
	_end_active_at_cross = _cell_arrays_equal(_active_cells(streamer), end_active_cells)


func _assert_streamer_contract(streamer: Node) -> void:
	if _crossed and _deferred_at_cross <= _deferred_before_drive:
		_errors.append(
			"streamer did not record deferred activation at seam; before="
			+ str(_deferred_before_drive)
			+ " cross="
			+ str(_deferred_at_cross)
		)
	if _crossed and _end_active_at_cross:
		_errors.append("end active cells were synchronously active on the seam-crossing tick")
	if _crossed and not _end_active_after_cross:
		_errors.append("end active cells did not activate after deferred seam crossing")

	var max_observed_delta: float = float(streamer.call("max_observed_physics_delta"))
	var max_effective_delta: float = float(streamer.call("max_effective_physics_delta"))
	var delta_limit: float = GameConfig.STREAM_PHYSICS_DELTA_CLAMP + CLAMP_EPSILON
	if _max_fixture_delta > delta_limit:
		_errors.append("fixture physics delta " + str(_max_fixture_delta) + " exceeded clamp " + str(delta_limit))
	if max_observed_delta > delta_limit:
		_errors.append("streamer observed physics delta " + str(max_observed_delta) + " exceeded clamp " + str(delta_limit))
	if max_effective_delta > delta_limit:
		_errors.append("streamer effective physics delta " + str(max_effective_delta) + " exceeded clamp " + str(delta_limit))
	if _max_position_delta > MAX_INTERFRAME_DELTA_M:
		_errors.append(
			"vehicle inter-frame position delta "
			+ str(_max_position_delta)
			+ " exceeded "
			+ str(MAX_INTERFRAME_DELTA_M)
		)

	var failures: Dictionary = streamer.call("load_failures")
	if not failures.is_empty():
		_errors.append("TileStreamer load failures: " + str(failures))


func _wait_for_active_cells(streamer: Node, expected_cells: Array[Vector2i], timeout_ticks: int) -> bool:
	for _i in range(timeout_ticks):
		await get_tree().physics_frame
		_tick += 1
		_record_position()
		if _cell_arrays_equal(_active_cells(streamer), expected_cells):
			return true
	return false


func _record_position() -> void:
	if _body == null:
		return
	var position: Vector3 = _body.global_position
	if _has_previous_position:
		_max_position_delta = maxf(_max_position_delta, position.distance_to(_previous_position))
	_previous_position = position
	_has_previous_position = true


func _set_body_state(transform: Transform3D, linear_velocity: Vector3, angular_velocity: Vector3) -> void:
	if _body == null:
		return
	_body.global_transform = transform
	_body.linear_velocity = linear_velocity
	_body.angular_velocity = angular_velocity
	_body.force_update_transform()
	PhysicsServer3D.body_set_state(_body.get_rid(), PhysicsServer3D.BODY_STATE_SLEEPING, false)
	PhysicsServer3D.body_set_state(_body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, transform)
	PhysicsServer3D.body_set_state(_body.get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, linear_velocity)
	PhysicsServer3D.body_set_state(_body.get_rid(), PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, angular_velocity)


func _expected_active_cells(streamer: Node, world_position: Vector3) -> Array[Vector2i]:
	return _cell_array(streamer.call("expected_active_cells_for_position", world_position))


func _active_cells(streamer: Node) -> Array[Vector2i]:
	return _cell_array(streamer.call("active_cells"))


func _ready_cells(streamer: Node) -> Array[Vector2i]:
	return _cell_array(streamer.call("ready_cells"))


func _cell_array(value: Variant) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if value is Array:
		var raw_cells: Array = value
		for item in raw_cells:
			if item is Vector2i:
				cells.append(item)
	_sort_cells(cells)
	return cells


func _cell_difference(left_cells: Array[Vector2i], right_cells: Array[Vector2i]) -> Array[Vector2i]:
	var difference: Array[Vector2i] = []
	for cell in left_cells:
		if not right_cells.has(cell):
			difference.append(cell)
	_sort_cells(difference)
	return difference


func _cell_arrays_equal(left: Array[Vector2i], right: Array[Vector2i]) -> bool:
	if left.size() != right.size():
		return false
	for i in range(left.size()):
		if left[i] != right[i]:
			return false
	return true


func _sort_cells(cells: Array[Vector2i]) -> void:
	cells.sort_custom(Callable(self, "_cell_less"))


func _cell_less(left: Vector2i, right: Vector2i) -> bool:
	if left.x == right.x:
		return left.y < right.y
	return left.x < right.x


func _cells_to_string(cells: Array[Vector2i]) -> String:
	var parts: Array[String] = []
	for cell in cells:
		parts.append("(" + str(cell.x) + "," + str(cell.y) + ")")
	var text: String = ""
	for i in range(parts.size()):
		if i > 0:
			text += ", "
		text += parts[i]
	return "[" + text + "]"


func _finish(streamer: Node, start_active_cells: Array[Vector2i], end_active_cells: Array[Vector2i]) -> void:
	if streamer != null:
		print(
			"tile_streamer_seam_hitch_result="
			+ JSON.stringify({
				"cross_tick": _cross_tick,
				"deferred_before_drive": _deferred_before_drive,
				"deferred_at_cross": _deferred_at_cross,
				"start_active_count": start_active_cells.size(),
				"end_active_count": end_active_cells.size(),
				"max_fixture_delta": _max_fixture_delta,
				"max_streamer_delta": float(streamer.call("max_observed_physics_delta")),
				"max_effective_delta": float(streamer.call("max_effective_physics_delta")),
				"max_position_delta": _max_position_delta
			})
		)
		streamer.call("reset")
	if _errors.is_empty():
		print("ok: TileStreamer defers seam activation without dt spike or vehicle launch")
		get_tree().quit(0)
		return
	for error in _errors:
		push_error(error)
	get_tree().quit(1)
GDSCRIPT

cat > "$fixture_scene" <<'TSCN'
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://tests/out/tile_streamer_seam_hitch_fixture.gd" id="1_fixture"]

[node name="TileStreamerSeamHitchFixture" type="Node"]
script = ExtResource("1_fixture")
TSCN

"$godot_bin" --headless --fixed-fps 120 --path . "res://$fixture_scene"
