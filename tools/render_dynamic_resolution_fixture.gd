extends Node

const RenderDynamicResolutionControllerScript: GDScript = preload("res://systems/render/render_dynamic_resolution_controller.gd")
const FLOAT_EPSILON: float = 0.001
const INITIAL_SCALE: float = 0.93
const OVER_BUDGET_FRAME_MS: float = 24.0
const UNDER_BUDGET_FRAME_MS: float = 8.0

var _errors: PackedStringArray = PackedStringArray()


func _ready() -> void:
	var controller: Node = RenderDynamicResolutionControllerScript.new() as Node
	controller.name = "RenderDynamicResolutionControllerFixture"
	add_child(controller)
	controller.call("configure_for_tests", get_viewport(), INITIAL_SCALE)
	_inspect_downscale(controller)
	_inspect_upscale(controller)
	_finish()


func _inspect_downscale(controller: Node) -> void:
	var warmup_frames: int = maxi(GameConfig.render_dynamic_resolution_warmup_frames, 0)
	var adjust_frames: int = maxi(GameConfig.render_dynamic_resolution_adjust_frames, 1)
	for _i in range(warmup_frames + adjust_frames):
		controller.call("sample_frame_ms", OVER_BUDGET_FRAME_MS)
	var scale: float = float(controller.call("current_scale"))
	if scale >= INITIAL_SCALE:
		_errors.append("dynamic resolution should lower scale after sustained over-budget frames")
	if scale < GameConfig.render_dynamic_resolution_min_scale - FLOAT_EPSILON:
		_errors.append("dynamic resolution scale dropped below min")
	if absf(get_viewport().scaling_3d_scale - scale) > FLOAT_EPSILON:
		_errors.append("viewport scaling_3d_scale should match controller scale after downscale")


func _inspect_upscale(controller: Node) -> void:
	var adjust_frames: int = maxi(GameConfig.render_dynamic_resolution_adjust_frames, 1)
	for _i in range(adjust_frames * 16):
		controller.call("sample_frame_ms", UNDER_BUDGET_FRAME_MS)
	var scale: float = float(controller.call("current_scale"))
	if absf(scale - GameConfig.render_dynamic_resolution_max_scale) > FLOAT_EPSILON:
		_errors.append("dynamic resolution should restore max scale after sustained under-budget frames")
	if absf(get_viewport().scaling_3d_scale - scale) > FLOAT_EPSILON:
		_errors.append("viewport scaling_3d_scale should match controller scale after upscale")
	if not controller.has_meta(RenderDynamicResolutionControllerScript.CURRENT_SCALE_META):
		_errors.append("dynamic resolution controller missing current-scale metadata")
	if not controller.has_meta(RenderDynamicResolutionControllerScript.TARGET_FRAME_MS_META):
		_errors.append("dynamic resolution controller missing target-frame metadata")


func _finish() -> void:
	if _errors.is_empty():
		print("ok: render dynamic resolution controller response")
		get_tree().quit(0)
		return
	for error in _errors:
		push_error(error)
	get_tree().quit(1)
