extends Node

const RenderRuntimeConfigScript: GDScript = preload("res://systems/render/render_runtime_config.gd")

var _errors: PackedStringArray = PackedStringArray()


func _ready() -> void:
	var host: Node = Node.new()
	host.name = "RenderRuntimeConfigFixtureHost"
	add_child(host)
	RenderRuntimeConfigScript.apply_to(host)
	_inspect(host)
	_finish()


func _inspect(host: Node) -> void:
	if DisplayServer.get_name() == "headless":
		_errors.append("render runtime config fixture must run windowed")
	if RenderRuntimeConfigScript.frame_cap_skip_requested():
		_errors.append("render runtime config fixture should not request the frame-cap skip")
	if not GameConfig.render_frame_cap_enabled:
		_errors.append("render frame cap should be enabled")
	if GameConfig.render_max_fps != 60:
		_errors.append("render_max_fps expected 60, got " + str(GameConfig.render_max_fps))
	var applied_max_fps: int = int(host.get_meta(RenderRuntimeConfigScript.RENDER_MAX_FPS_META, -1))
	if applied_max_fps != GameConfig.render_max_fps:
		_errors.append("applied render max fps expected " + str(GameConfig.render_max_fps) + ", got " + str(applied_max_fps))
	if Engine.max_fps != GameConfig.render_max_fps:
		_errors.append("Engine.max_fps expected " + str(GameConfig.render_max_fps) + ", got " + str(Engine.max_fps))
	if not bool(host.get_meta(RenderRuntimeConfigScript.DYNAMIC_RESOLUTION_INSTALLED_META, false)):
		_errors.append("dynamic resolution controller should be installed for ordinary windowed hosts")
	if host.get_node_or_null("RenderDynamicResolutionController") == null:
		_errors.append("host missing RenderDynamicResolutionController child")
	_inspect_dynamic_resolution_without_frame_cap()
	if not bool(ProjectSettings.get_setting("physics/common/physics_interpolation", false)):
		_errors.append("physics interpolation should be enabled for render smoothing")


func _inspect_dynamic_resolution_without_frame_cap() -> void:
	var previous_frame_cap_enabled: bool = GameConfig.render_frame_cap_enabled
	GameConfig.render_frame_cap_enabled = false
	var host: Node = Node.new()
	host.name = "RenderRuntimeNoFrameCapHost"
	add_child(host)
	RenderRuntimeConfigScript.apply_to(host)
	var applied_max_fps: int = int(host.get_meta(RenderRuntimeConfigScript.RENDER_MAX_FPS_META, -1))
	if applied_max_fps != 0:
		_errors.append("disabled frame cap should apply render max fps 0, got " + str(applied_max_fps))
	if not bool(host.get_meta(RenderRuntimeConfigScript.DYNAMIC_RESOLUTION_INSTALLED_META, false)):
		_errors.append("dynamic resolution should install even when frame cap is disabled")
	GameConfig.render_frame_cap_enabled = previous_frame_cap_enabled


func _finish() -> void:
	if _errors.size() > 0:
		for error in _errors:
			push_error(error)
		get_tree().quit(1)
		return
	print("ok: render runtime frame cap and interpolation config")
	get_tree().quit(0)
