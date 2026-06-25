class_name RecoverableObjectRender
extends Node

const PLACEHOLDER_MESH_NAME: StringName = &"RecoverableObjectMesh"
const TAGGED_RIBBON_NAME: StringName = &"TaggedRibbon"
const TAGGED_META: StringName = &"tagged"
const TAGGED_SHADER_PARAM: StringName = &"tagged"
const TAG_CUE_NAME: String = "RecoverableTagCue"
const TAG_CUE_HZ: float = 392.0
const TAG_CUE_DECAY_PER_FRAME: float = 0.996
const TAG_CUE_AMBIENT_RATIO: float = 0.62
const PLACEHOLDER_BODY_SIZE: Vector3 = Vector3(0.22, 0.10, 0.12)
const PLACEHOLDER_BODY_OFFSET: Vector3 = Vector3(0.0, 0.08, 0.0)
const RIBBON_SIZE: Vector3 = Vector3(0.30, 0.035, 0.035)
const RIBBON_OFFSET: Vector3 = Vector3(0.0, 0.18, 0.0)
const UNTAGGED_COLOR: Color = Color(0.42, 0.33, 0.23, 1.0)
const TAGGED_COLOR: Color = Color(1.0, 0.47, 0.11, 1.0)
const TaggedShader: Shader = preload("res://systems/render/recoverable_tagged.gdshader")

var _world_root: Node = null
var _recoverable_ids: Array[StringName] = []
var _recoverable_nodes: Array[Node3D] = []
var _mesh_nodes: Array[MeshInstance3D] = []
var _ribbon_nodes: Array[MeshInstance3D] = []
var _tagged_ids: Array[StringName] = []
var _is_headless: bool = false
var _cue_player: AudioStreamPlayer = null
var _cue_playback: AudioStreamGeneratorPlayback = null
var _cue_phase: float = 0.0
var _cue_envelope: float = 0.0
var _process_usec_last_frame: int = 0


func configure(world_root: Node) -> void:
	_world_root = world_root
	if is_inside_tree():
		_register_recoverables()


func _ready() -> void:
	_is_headless = DisplayServer.get_name() == "headless"
	if not EventBus.world_recoverable_object_tagged.is_connected(_on_world_recoverable_object_tagged):
		EventBus.world_recoverable_object_tagged.connect(_on_world_recoverable_object_tagged)
	if not _is_headless and GameConfig.recover_tag_cue_enabled:
		_setup_tag_cue()
	_register_recoverables()


func _exit_tree() -> void:
	if EventBus.world_recoverable_object_tagged.is_connected(_on_world_recoverable_object_tagged):
		EventBus.world_recoverable_object_tagged.disconnect(_on_world_recoverable_object_tagged)
	if _cue_player != null:
		_cue_player.stop()
		_cue_player.stream = null
		_cue_player = null
	_cue_playback = null


func _process(_delta: float) -> void:
	var process_start_usec: int = Time.get_ticks_usec()
	_process_body()
	_process_usec_last_frame = maxi(Time.get_ticks_usec() - process_start_usec, 0)


func process_usec_last_frame() -> int:
	return _process_usec_last_frame


func _process_body() -> void:
	_fill_tag_cue()


func is_object_tagged(object_id: StringName) -> bool:
	return _tagged_ids.has(object_id)


func mesh_for_object(object_id: StringName) -> MeshInstance3D:
	var index: int = _index_for(object_id)
	if index < 0:
		return null
	return _mesh_nodes[index]


func ribbon_for_object(object_id: StringName) -> MeshInstance3D:
	var index: int = _index_for(object_id)
	if index < 0:
		return null
	return _ribbon_nodes[index]


func has_audio_cue_player() -> bool:
	return _cue_player != null


func _on_world_recoverable_object_tagged(object_id: StringName) -> void:
	if object_id == &"":
		return
	if not _tagged_ids.has(object_id):
		_tagged_ids.append(object_id)
	if _index_for(object_id) < 0:
		_register_recoverables()
	var index: int = _index_for(object_id)
	if index >= 0:
		_apply_tagged_state(index, true)
	_play_tag_cue()


func _register_recoverables() -> void:
	_recoverable_ids.clear()
	_recoverable_nodes.clear()
	_mesh_nodes.clear()
	_ribbon_nodes.clear()
	if _world_root == null:
		return
	_collect_recoverables(_world_root)
	for tagged_id in _tagged_ids:
		var index: int = _index_for(tagged_id)
		if index >= 0:
			_apply_tagged_state(index, true)


func _collect_recoverables(node: Node) -> void:
	var recoverable: Node3D = node as Node3D
	if recoverable != null and _recoverable_object_id(recoverable) != &"":
		_register_recoverable(recoverable)
	for child in node.get_children():
		var child_node: Node = child as Node
		if child_node != null:
			_collect_recoverables(child_node)


func _register_recoverable(recoverable: Node3D) -> void:
	var object_id: StringName = _recoverable_object_id(recoverable)
	if object_id == &"" or _index_for(object_id) >= 0:
		return
	var mesh: MeshInstance3D = _ensure_object_mesh(recoverable)
	var ribbon: MeshInstance3D = _ensure_ribbon_mesh(recoverable)
	_recoverable_ids.append(object_id)
	_recoverable_nodes.append(recoverable)
	_mesh_nodes.append(mesh)
	_ribbon_nodes.append(ribbon)
	_apply_tagged_state(_recoverable_ids.size() - 1, _tagged_ids.has(object_id))


func _recoverable_object_id(node: Node) -> StringName:
	if not node.has_method("sample_vehicle_position") or not node.has_method("was_tagged"):
		return &""
	var object_id_value: Variant = node.get("object_id")
	if object_id_value is StringName:
		return object_id_value
	if object_id_value is String:
		return StringName(object_id_value)
	return &""


func _ensure_object_mesh(recoverable: Node3D) -> MeshInstance3D:
	var mesh: MeshInstance3D = _find_object_mesh(recoverable)
	if mesh == null:
		mesh = MeshInstance3D.new()
		mesh.name = PLACEHOLDER_MESH_NAME
		var box_mesh: BoxMesh = BoxMesh.new()
		box_mesh.size = PLACEHOLDER_BODY_SIZE
		mesh.mesh = box_mesh
		mesh.position = PLACEHOLDER_BODY_OFFSET
		recoverable.add_child(mesh)
	if mesh.material_override == null:
		mesh.material_override = _make_recoverable_material(String(mesh.name))
	_set_mesh_tagged(mesh, false)
	return mesh


func _find_object_mesh(recoverable: Node3D) -> MeshInstance3D:
	var named_mesh: MeshInstance3D = recoverable.get_node_or_null(NodePath(String(PLACEHOLDER_MESH_NAME))) as MeshInstance3D
	if named_mesh != null:
		return named_mesh
	for child in recoverable.get_children():
		var mesh_child: MeshInstance3D = child as MeshInstance3D
		if mesh_child != null and mesh_child.name != TAGGED_RIBBON_NAME:
			return mesh_child
	return null


func _ensure_ribbon_mesh(recoverable: Node3D) -> MeshInstance3D:
	var ribbon: MeshInstance3D = recoverable.get_node_or_null(NodePath(String(TAGGED_RIBBON_NAME))) as MeshInstance3D
	if ribbon == null:
		ribbon = MeshInstance3D.new()
		ribbon.name = TAGGED_RIBBON_NAME
		var box_mesh: BoxMesh = BoxMesh.new()
		box_mesh.size = RIBBON_SIZE
		ribbon.mesh = box_mesh
		ribbon.position = RIBBON_OFFSET
		ribbon.rotation_degrees = Vector3(0.0, 0.0, -12.0)
		ribbon.material_override = _make_ribbon_material()
		recoverable.add_child(ribbon)
	ribbon.visible = false
	return ribbon


func _make_recoverable_material(resource_name: String) -> ShaderMaterial:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.resource_name = resource_name + "_tagged_material"
	material.shader = TaggedShader
	material.set_shader_parameter("untagged_color", UNTAGGED_COLOR)
	material.set_shader_parameter("tagged_color", TAGGED_COLOR)
	return material


func _make_ribbon_material() -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.resource_name = "recoverable_tagged_ribbon_material"
	material.albedo_color = TAGGED_COLOR
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material


func _apply_tagged_state(index: int, tagged: bool) -> void:
	if index < 0 or index >= _mesh_nodes.size() or index >= _ribbon_nodes.size():
		return
	_set_mesh_tagged(_mesh_nodes[index], tagged)
	_ribbon_nodes[index].visible = tagged


func _set_mesh_tagged(mesh: MeshInstance3D, tagged: bool) -> void:
	if mesh == null:
		return
	mesh.set_meta(String(TAGGED_META), tagged)
	mesh.set_instance_shader_parameter(TAGGED_SHADER_PARAM, tagged)


func _index_for(object_id: StringName) -> int:
	for index in range(_recoverable_ids.size()):
		if _recoverable_ids[index] == object_id:
			return index
	return -1


func _setup_tag_cue() -> void:
	_cue_player = AudioStreamPlayer.new()
	_cue_player.name = TAG_CUE_NAME
	var stream: AudioStreamGenerator = AudioStreamGenerator.new()
	stream.mix_rate = GameConfig.audio_mix_rate
	stream.buffer_length = GameConfig.audio_buffer_length
	_cue_player.stream = stream
	add_child(_cue_player)
	call_deferred("_start_tag_cue_player")


func _start_tag_cue_player() -> void:
	if _cue_player == null:
		return
	_cue_player.play()
	_cue_playback = _cue_player.get_stream_playback() as AudioStreamGeneratorPlayback


func _play_tag_cue() -> void:
	if _is_headless:
		return
	if not GameConfig.recover_tag_cue_enabled:
		return
	_cue_envelope = 1.0


func _fill_tag_cue() -> void:
	if _cue_playback == null:
		return
	var frames_available: int = _cue_playback.get_frames_available()
	for _i in range(frames_available):
		_cue_playback.push_frame(_next_tag_cue_frame())


func _next_tag_cue_frame() -> Vector2:
	if _cue_envelope <= 0.001:
		_cue_envelope = 0.0
		return Vector2.ZERO
	var phase_step: float = TAU * TAG_CUE_HZ / maxf(GameConfig.audio_mix_rate, 1.0)
	_cue_phase += phase_step
	if _cue_phase > TAU:
		_cue_phase -= TAU
	var volume: float = GameConfig.audio_ambient_wind_volume * TAG_CUE_AMBIENT_RATIO
	var sample: float = sin(_cue_phase) * volume * _cue_envelope
	_cue_envelope *= TAG_CUE_DECAY_PER_FRAME
	return Vector2(sample, sample)
