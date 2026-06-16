extends Node

const CampfireSilenceZoneScene: PackedScene = preload("res://scenes/world/easter_eggs/campfire_silence_zone.tscn")
const CedarAudioRigScript: GDScript = preload("res://systems/render/cedar_audio_rig.gd")
const FIXED_DT: float = 1.0 / 120.0
const FADE_FRAME_COUNT: int = 60
const FLOAT_TOLERANCE: float = 0.001

class TestVehicle:
	extends Node

	func get_state() -> RefCounted:
		return RefCounted.new()

var _errors: PackedStringArray = PackedStringArray()
var _duck_events: Array[float] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var original_volume_db: float = GameConfig.audio_bus_ambient_volume_db
	GameConfig.audio_bus_ambient_volume_db = -3.0
	if not EventBus.world_duck_ambient_audio.is_connected(_on_world_duck_ambient_audio):
		EventBus.world_duck_ambient_audio.connect(_on_world_duck_ambient_audio)
	var audio_rig: Node = CedarAudioRigScript.new() as Node
	if audio_rig == null:
		_errors.append("failed to instantiate CedarAudioRig")
		_finish(original_volume_db)
		return
	add_child(audio_rig)

	var zone: Area3D = CampfireSilenceZoneScene.instantiate() as Area3D
	if zone == null:
		_errors.append("failed to instantiate CampfireSilenceZone")
		_finish(original_volume_db)
		return
	add_child(zone)
	await get_tree().process_frame

	_require_zone_contract(zone)

	var vehicle: TestVehicle = TestVehicle.new()
	vehicle.name = "Vehicle"
	var physics_body: RigidBody3D = RigidBody3D.new()
	physics_body.name = "PhysicsBody"
	vehicle.add_child(physics_body)
	add_child(vehicle)

	zone.call("_on_body_entered", physics_body)
	_step_zone(zone, FADE_FRAME_COUNT)
	if _last_duck_volume_db() > -59.0:
		_errors.append("ambient duck should fade near silence on vehicle entry, got " + str(_last_duck_volume_db()))
	if absf(GameConfig.audio_bus_ambient_volume_db - -3.0) > FLOAT_TOLERANCE:
		_errors.append("campfire zone should not mutate GameConfig ambient volume on entry")
	_require_ambient_gain_matches_duck(audio_rig, "entry")

	zone.call("_on_body_exited", physics_body)
	_step_zone(zone, FADE_FRAME_COUNT)
	if absf(_last_duck_volume_db() - -3.0) > FLOAT_TOLERANCE:
		_errors.append("ambient duck should restore saved value on vehicle exit, got " + str(_last_duck_volume_db()))
	if absf(GameConfig.audio_bus_ambient_volume_db - -3.0) > FLOAT_TOLERANCE:
		_errors.append("campfire zone should not mutate GameConfig ambient volume on exit")
	_require_ambient_gain_matches_duck(audio_rig, "exit")

	_finish(original_volume_db)


func _step_zone(zone: Area3D, frame_count: int) -> void:
	for _i in range(frame_count):
		zone.call("_physics_process", FIXED_DT)


func _last_duck_volume_db() -> float:
	if _duck_events.is_empty():
		return INF
	return _duck_events[_duck_events.size() - 1]


func _on_world_duck_ambient_audio(target_volume_db: float) -> void:
	_duck_events.append(target_volume_db)


func _require_ambient_gain_matches_duck(audio_rig: Node, label: String) -> void:
	if audio_rig == null:
		return
	var expected_gain: float = db_to_linear(GameConfig.audio_bus_master_volume_db + _last_duck_volume_db())
	var actual_gain: float = float(audio_rig.call("bus_gain_for_layer", &"ambient"))
	if absf(actual_gain - expected_gain) > FLOAT_TOLERANCE:
		_errors.append("ambient rig gain did not match " + label + " duck signal")


func _require_zone_contract(zone: Area3D) -> void:
	if absf(zone.position.distance_to(Vector3(-1.4, 0.08, -34.2))) > FLOAT_TOLERANCE:
		_errors.append("CampfireSilenceZone is not authored at the Pine Floor placeholder anchor")
	var shape: CollisionShape3D = zone.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape == null:
		_errors.append("CampfireSilenceZone missing CollisionShape3D")
	else:
		var sphere: SphereShape3D = shape.shape as SphereShape3D
		if sphere == null:
			_errors.append("CampfireSilenceZone shape should be SphereShape3D")
		elif absf(sphere.radius - 5.0) > FLOAT_TOLERANCE:
			_errors.append("CampfireSilenceZone radius expected 5.0, got " + str(sphere.radius))
	var prop_root: Node = zone.get_node_or_null("PropRoot")
	if prop_root == null:
		_errors.append("CampfireSilenceZone missing placeholder prop root")
	elif prop_root.get_child_count() <= 0:
		_errors.append("CampfireSilenceZone placeholder prop root should contain visual payoff meshes")
	var smoke: GPUParticles3D = zone.get_node_or_null("ColdSmoke") as GPUParticles3D
	if smoke == null:
		_errors.append("CampfireSilenceZone missing cold-smoke particle placeholder")


func _finish(original_volume_db: float) -> void:
	if EventBus.world_duck_ambient_audio.is_connected(_on_world_duck_ambient_audio):
		EventBus.world_duck_ambient_audio.disconnect(_on_world_duck_ambient_audio)
	GameConfig.audio_bus_ambient_volume_db = original_volume_db
	for error in _errors:
		push_error(error)
	if _errors.is_empty():
		print("campfire_silence_zone_fixture: ok")
		get_tree().quit(0)
	else:
		get_tree().quit(1)
