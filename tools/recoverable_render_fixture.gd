extends Node

const RecoverableObjectRenderScript: GDScript = preload("res://systems/render/recoverable_object_render.gd")
const RecoverableObjectScript: GDScript = preload("res://systems/world/recoverable_object.gd")
const SUCCESS_LINE: String = "ok: RecoverableObjectRender tags placeholder visual state without sim writes"

var _errors: PackedStringArray = PackedStringArray()


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var world_root: Node3D = Node3D.new()
	world_root.name = "RecoverableRenderFixtureWorld"
	add_child(world_root)

	var recoverable: Node3D = RecoverableObjectScript.new() as Node3D
	if recoverable == null:
		_errors.append("failed to instantiate RecoverableObject")
		_finish()
		return
	recoverable.name = "RO_Fixture"
	recoverable.call("configure", &"ro_fixture", Vector3.ZERO)
	world_root.add_child(recoverable)

	var subscriber: Node = RecoverableObjectRenderScript.new() as Node
	if subscriber == null:
		_errors.append("failed to instantiate RecoverableObjectRender")
		_finish()
		return
	subscriber.name = "RecoverableObjectRender"
	add_child(subscriber)
	subscriber.call("configure", world_root)
	await get_tree().process_frame

	_assert_initial_state(subscriber, recoverable)
	EventBus.world_recoverable_object_tagged.emit(&"ro_fixture")
	await get_tree().process_frame
	_assert_tagged_state(subscriber, recoverable)

	subscriber.queue_free()
	world_root.queue_free()
	await get_tree().process_frame
	_finish()


func _assert_initial_state(subscriber: Node, recoverable: Node3D) -> void:
	if bool(subscriber.call("has_audio_cue_player")):
		_errors.append("headless RecoverableObjectRender should not create an audio cue player")
	if bool(subscriber.call("is_object_tagged", &"ro_fixture")):
		_errors.append("recoverable render state started tagged")
	var mesh: MeshInstance3D = subscriber.call("mesh_for_object", &"ro_fixture") as MeshInstance3D
	if mesh == null:
		_errors.append("recoverable render state did not create or find an object mesh")
	else:
		if bool(mesh.get_meta("tagged", false)):
			_errors.append("recoverable object mesh meta started tagged")
		var material: ShaderMaterial = mesh.material_override as ShaderMaterial
		if material == null:
			_errors.append("recoverable object mesh should use a ShaderMaterial placeholder")
	var ribbon: MeshInstance3D = subscriber.call("ribbon_for_object", &"ro_fixture") as MeshInstance3D
	if ribbon == null:
		_errors.append("recoverable render state did not create a tagged ribbon placeholder")
	elif ribbon.visible:
		_errors.append("tagged ribbon placeholder should start hidden")
	if bool(recoverable.call("was_tagged")):
		_errors.append("render subscriber should not pre-tag sim/world RecoverableObject")


func _assert_tagged_state(subscriber: Node, recoverable: Node3D) -> void:
	if not bool(subscriber.call("is_object_tagged", &"ro_fixture")):
		_errors.append("recoverable render subscriber did not record the tagged object id")
	var mesh: MeshInstance3D = subscriber.call("mesh_for_object", &"ro_fixture") as MeshInstance3D
	if mesh == null:
		_errors.append("tagged recoverable mesh was missing")
	else:
		if not bool(mesh.get_meta("tagged", false)):
			_errors.append("recoverable object mesh meta was not tagged after signal")
		if not bool(mesh.get_instance_shader_parameter(&"tagged")):
			_errors.append("recoverable object mesh shader parameter was not tagged after signal")
	var ribbon: MeshInstance3D = subscriber.call("ribbon_for_object", &"ro_fixture") as MeshInstance3D
	if ribbon == null:
		_errors.append("tagged ribbon placeholder was missing after signal")
	elif not ribbon.visible:
		_errors.append("tagged ribbon placeholder did not become visible")
	if bool(recoverable.call("was_tagged")):
		_errors.append("render subscriber wrote sim/world RecoverableObject tagged state")
	if int(recoverable.call("hold_ticks")) != 0:
		_errors.append("render subscriber changed RecoverableObject hold ticks")


func _finish() -> void:
	if _errors.is_empty():
		print(SUCCESS_LINE)
		get_tree().quit(0)
		return
	for error in _errors:
		push_error(error)
	get_tree().quit(1)
