extends Node

const FrequencyInputPanelScene: PackedScene = preload("res://ui/frequency_input_panel.tscn")
const FrequencyStickersScene: PackedScene = preload("res://scenes/world/easter_eggs/frequency_stickers.tscn")
const GrasshopperLiveryScript: GDScript = preload("res://systems/render/grasshopper_livery.gd")
const SUCCESS_LINE: String = "ok: frequency panel unlocks render-only Grasshopper livery"
const EXPECTED_CODE: String = "2401"

var _errors: PackedStringArray = PackedStringArray()
var _submitted_codes: PackedStringArray = PackedStringArray()
var _livery: Node = null


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_inspect_sticker_scene()
	var visual_root: Node3D = _make_visual_root()
	add_child(visual_root)
	_livery = GrasshopperLiveryScript.new() as Node
	if _livery == null:
		_errors.append("failed to instantiate GrasshopperLivery")
		_finish()
		return
	add_child(_livery)
	_livery.call("configure", visual_root)

	var panel: CanvasLayer = FrequencyInputPanelScene.instantiate() as CanvasLayer
	if panel == null:
		_errors.append("failed to instantiate FrequencyInputPanel")
		_finish()
		return
	add_child(panel)
	panel.connect("ui_submitted_frequency_code", Callable(self, "_on_panel_submitted_code"))
	await get_tree().process_frame

	if panel.visible:
		_errors.append("FrequencyInputPanel should start hidden")
	panel.call("debug_submit_code", "1111")
	await get_tree().process_frame
	_assert_wrong_code_state(visual_root)
	panel.call("debug_submit_code", EXPECTED_CODE)
	await get_tree().process_frame
	_assert_correct_code_state(visual_root)
	_finish()


func _inspect_sticker_scene() -> void:
	var stickers: Node3D = FrequencyStickersScene.instantiate() as Node3D
	if stickers == null:
		_errors.append("failed to instantiate FrequencyStickers")
		return
	add_child(stickers)
	var names: Array[String] = [
		"frequency_sticker_culvert",
		"frequency_sticker_picnic",
		"frequency_sticker_bog_log",
		"frequency_sticker_cedar"
	]
	if stickers.get_child_count() != int(GameConfig.egg_frequency_spot_count):
		_errors.append("FrequencyStickers expected " + str(GameConfig.egg_frequency_spot_count) + " children, got " + str(stickers.get_child_count()))
	for sticker_name in names:
		var sticker: Node3D = stickers.get_node_or_null(sticker_name) as Node3D
		if sticker == null:
			_errors.append("missing sticker node " + sticker_name)
			continue
		var digit: Label3D = sticker.get_node_or_null("digit") as Label3D
		if digit == null or digit.text.length() != 1:
			_errors.append("sticker " + sticker_name + " should expose one Label3D digit")


func _make_visual_root() -> Node3D:
	var visual_root: Node3D = Node3D.new()
	visual_root.name = "VisualRoot"
	_add_mesh(visual_root, "body")
	_add_mesh(visual_root, "nose")
	_add_mesh(visual_root, "body_stripe")
	return visual_root


func _add_mesh(parent: Node3D, node_name: String) -> void:
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.name = node_name
	var box_mesh: BoxMesh = BoxMesh.new()
	box_mesh.size = Vector3(0.1, 0.04, 0.1)
	mesh_instance.mesh = box_mesh
	parent.add_child(mesh_instance)


func _assert_wrong_code_state(visual_root: Node3D) -> void:
	if _submitted_codes.size() != 1 or _submitted_codes[0] != "1111":
		_errors.append("panel did not emit wrong 4-digit code for host-side no-op handling")
	if bool(_livery.call("grasshopper_unlocked")):
		_errors.append("wrong code unlocked Grasshopper livery")
	if int(_livery.call("applied_mesh_count")) != 0:
		_errors.append("wrong code applied livery materials")
	var body: MeshInstance3D = visual_root.get_node_or_null("body") as MeshInstance3D
	if body == null or body.material_override != null:
		_errors.append("wrong code changed body material override")


func _assert_correct_code_state(visual_root: Node3D) -> void:
	if _submitted_codes.size() != 2 or _submitted_codes[1] != EXPECTED_CODE:
		_errors.append("panel did not emit correct 4-digit code")
	if not bool(_livery.call("try_unlock_with_code", EXPECTED_CODE)):
		_errors.append("correct code did not report livery unlock")
	if not bool(_livery.call("grasshopper_unlocked")):
		_errors.append("correct code did not flip in-memory session flag")
	if int(_livery.call("applied_mesh_count")) < 3:
		_errors.append("correct code did not apply placeholder livery materials to chassis meshes")
	var body: MeshInstance3D = visual_root.get_node_or_null("body") as MeshInstance3D
	if body == null:
		_errors.append("fixture body mesh missing")
	elif body.material_override == null:
		_errors.append("correct code left body material_override empty")
	elif not bool(body.get_meta(&"grasshopper_livery_applied", false)):
		_errors.append("correct code did not mark body mesh as livery-applied")


func _on_panel_submitted_code(code: String) -> void:
	_submitted_codes.append(code)
	if _livery != null:
		_livery.call("try_unlock_with_code", code)


func _finish() -> void:
	if _errors.is_empty():
		print(SUCCESS_LINE)
		get_tree().quit(0)
		return
	for error in _errors:
		push_error(error)
	get_tree().quit(1)
