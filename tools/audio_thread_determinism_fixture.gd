extends Node

const CedarAudioRigScript: GDScript = preload("res://systems/render/cedar_audio_rig.gd")
const CYCLE_COUNT: int = 8
const FRAME_COUNT: int = 513
const LAYERS: Array[String] = ["motor", "tire", "ambient", "water", "plank"]
const CYCLE_SURFACES: Array[StringName] = [
	&"packed_dirt",
	&"tall_grass",
	&"mud",
	&"wood_plank",
	&"packed_gravel",
	&"paved_road",
	&"wet_stone",
	&"packed_dirt",
]

var _errors: PackedStringArray = PackedStringArray()


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var reference_rig: Node = _make_rig("ReferenceCedarAudioRig")
	var threaded_rig: Node = _make_rig("ThreadedCedarAudioRig")
	var reference_cycles: Array[Variant] = _run_reference_sequence(reference_rig)
	var threaded_cycles: Array[Variant] = _run_threaded_sequence(threaded_rig)
	_require_matching_sequences(reference_cycles, threaded_cycles)
	_finish()


func _make_rig(rig_name: String) -> Node:
	var rig: Node = CedarAudioRigScript.new() as Node
	rig.name = rig_name
	add_child(rig)
	return rig


func _run_reference_sequence(rig: Node) -> Array[Variant]:
	var cycles: Array[Variant] = []
	for cycle_index in range(CYCLE_COUNT):
		var input: Dictionary = _cycle_input(cycle_index)
		cycles.append(_fill_from_input(rig, input))
	return cycles


func _run_threaded_sequence(rig: Node) -> Array[Variant]:
	var cycles: Array[Variant] = []
	for cycle_index in range(CYCLE_COUNT):
		var input: Dictionary = _cycle_input(cycle_index)
		var context: Dictionary = {
			"rig": rig,
			"mutex": rig.get("_audio_mutex"),
			"result": {},
		}
		_publish_snapshot(rig, input)
		var thread: Thread = Thread.new()
		var start_error: Error = thread.start(Callable(self, "_threaded_cycle_worker").bind(context), Thread.PRIORITY_NORMAL)
		if start_error != OK:
			_errors.append("cycle " + str(cycle_index) + " thread start failed: " + error_string(start_error))
			cycles.append({})
			continue
		thread.wait_to_finish()
		var mutex: Mutex = context["mutex"] as Mutex
		mutex.lock()
		var result: Dictionary = context["result"] as Dictionary
		mutex.unlock()
		cycles.append(result)
	return cycles


func _threaded_cycle_worker(context: Dictionary) -> void:
	var rig: Node = context["rig"] as Node
	var mutex: Mutex = context["mutex"] as Mutex
	mutex.lock()
	var speed: float = float(rig.get("_snapshot_speed"))
	var motor_rpm: float = float(rig.get("_snapshot_motor_rpm"))
	var vehicle_position: Vector3 = rig.get("_snapshot_position")
	var surface_id: StringName = rig.get("_snapshot_surface_id")
	mutex.unlock()
	var result: Dictionary = rig.call("debug_fill_cycle_buffers", speed, motor_rpm, vehicle_position, surface_id, FRAME_COUNT) as Dictionary
	mutex.lock()
	context["result"] = result
	mutex.unlock()


func _publish_snapshot(rig: Node, input: Dictionary) -> void:
	var mutex: Mutex = rig.get("_audio_mutex") as Mutex
	mutex.lock()
	rig.set("_snapshot_speed", float(input["speed"]))
	rig.set("_snapshot_motor_rpm", float(input["motor_rpm"]))
	rig.set("_snapshot_position", input["position"])
	rig.set("_snapshot_surface_id", input["surface_id"])
	mutex.unlock()


func _fill_from_input(rig: Node, input: Dictionary) -> Dictionary:
	var result: Dictionary = rig.call(
		"debug_fill_cycle_buffers",
		float(input["speed"]),
		float(input["motor_rpm"]),
		input["position"],
		input["surface_id"],
		FRAME_COUNT
	) as Dictionary
	return result


func _cycle_input(cycle_index: int) -> Dictionary:
	var cycle_float: float = float(cycle_index)
	var position: Vector3 = GameConfig.audio_water_center + Vector3(
		(cycle_float - 3.0) * 8.5,
		0.0,
		sin(cycle_float * 0.7) * 11.0
	)
	return {
		"speed": 0.35 + cycle_float * 0.48,
		"motor_rpm": 160.0 + cycle_float * 91.0,
		"position": position,
		"surface_id": CYCLE_SURFACES[cycle_index % CYCLE_SURFACES.size()],
	}


func _require_matching_sequences(reference_cycles: Array[Variant], threaded_cycles: Array[Variant]) -> void:
	if reference_cycles.size() != threaded_cycles.size():
		_errors.append("cycle count mismatch: reference " + str(reference_cycles.size()) + ", threaded " + str(threaded_cycles.size()))
		return
	for cycle_index in range(reference_cycles.size()):
		var reference_cycle: Dictionary = reference_cycles[cycle_index] as Dictionary
		var threaded_cycle: Dictionary = threaded_cycles[cycle_index] as Dictionary
		_require_matching_cycle(reference_cycle, threaded_cycle, cycle_index)


func _require_matching_cycle(reference_cycle: Dictionary, threaded_cycle: Dictionary, cycle_index: int) -> void:
	for layer_name in LAYERS:
		if not reference_cycle.has(layer_name):
			_errors.append("reference cycle " + str(cycle_index) + " missing layer " + layer_name)
			continue
		if not threaded_cycle.has(layer_name):
			_errors.append("threaded cycle " + str(cycle_index) + " missing layer " + layer_name)
			continue
		var reference_buffer: PackedVector2Array = reference_cycle[layer_name]
		var threaded_buffer: PackedVector2Array = threaded_cycle[layer_name]
		if reference_buffer.size() != threaded_buffer.size():
			_errors.append(layer_name + " cycle " + str(cycle_index) + " size mismatch: reference " + str(reference_buffer.size()) + ", threaded " + str(threaded_buffer.size()))
			continue
		if reference_buffer != threaded_buffer:
			var first_index: int = _first_differing_index(reference_buffer, threaded_buffer)
			_errors.append(layer_name + " cycle " + str(cycle_index) + " differs at frame " + str(first_index) + ": reference " + str(reference_buffer[first_index]) + ", threaded " + str(threaded_buffer[first_index]))


func _first_differing_index(reference_buffer: PackedVector2Array, threaded_buffer: PackedVector2Array) -> int:
	var count: int = mini(reference_buffer.size(), threaded_buffer.size())
	for index in range(count):
		if reference_buffer[index] != threaded_buffer[index]:
			return index
	return count


func _finish() -> void:
	if _errors.size() > 0:
		for error in _errors:
			push_error(error)
		get_tree().quit(1)
		return
	print("ok: Cedar audio threaded fill matches direct fill buffers bitwise")
	get_tree().quit(0)
