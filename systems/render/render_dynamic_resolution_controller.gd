extends Node

const CURRENT_SCALE_META: StringName = &"trailhead_dynamic_resolution_scale"
const TARGET_FRAME_MS_META: StringName = &"trailhead_dynamic_resolution_target_frame_ms"

var _viewport: Viewport = null
var _scale: float = 1.0
var _ema_frame_ms: float = 0.0
var _sample_frames: int = 0
var _over_budget_frames: int = 0
var _under_budget_frames: int = 0
var _manual_test_mode: bool = false
var _measure_render_time_enabled: bool = false


func _ready() -> void:
	if _manual_test_mode:
		return
	_viewport = get_viewport()
	_scale = _initial_scale()
	_apply_scale(_scale)
	if GameConfig.render_dynamic_resolution_enabled:
		_enable_render_time_measurement()
	set_process(GameConfig.render_dynamic_resolution_enabled and _viewport != null)


func _exit_tree() -> void:
	_disable_render_time_measurement()


func _process(_delta: float) -> void:
	var gpu_frame_ms: float = _measured_gpu_frame_ms()
	if gpu_frame_ms <= 0.0:
		_publish_state()
		return
	sample_frame_ms(gpu_frame_ms)


func configure_for_tests(viewport: Viewport, initial_scale: float) -> void:
	_disable_render_time_measurement()
	_manual_test_mode = true
	_viewport = viewport
	_scale = clampf(initial_scale, _min_scale(), _max_scale())
	_ema_frame_ms = 0.0
	_sample_frames = 0
	_over_budget_frames = 0
	_under_budget_frames = 0
	_apply_scale(_scale)
	set_process(false)


func sample_frame_ms(frame_ms: float) -> float:
	var safe_frame_ms: float = maxf(frame_ms, 0.0)
	if _ema_frame_ms <= 0.0:
		_ema_frame_ms = safe_frame_ms
	else:
		_ema_frame_ms = lerpf(_ema_frame_ms, safe_frame_ms, _ema_alpha())
	_sample_frames += 1
	if _sample_frames <= maxi(GameConfig.render_dynamic_resolution_warmup_frames, 0):
		_publish_state()
		return _scale

	var target_frame_ms: float = _target_frame_ms()
	if _ema_frame_ms > target_frame_ms * maxf(GameConfig.render_dynamic_resolution_downscale_ratio, 1.0):
		_over_budget_frames += 1
		_under_budget_frames = 0
	elif _ema_frame_ms < target_frame_ms * clampf(GameConfig.render_dynamic_resolution_upscale_ratio, 0.1, 1.0):
		_under_budget_frames += 1
		_over_budget_frames = 0
	else:
		_over_budget_frames = 0
		_under_budget_frames = 0

	var adjust_frames: int = maxi(GameConfig.render_dynamic_resolution_adjust_frames, 1)
	if _over_budget_frames >= adjust_frames:
		_set_scale(_scale - maxf(GameConfig.render_dynamic_resolution_step_down, 0.0))
		_over_budget_frames = 0
	elif _under_budget_frames >= adjust_frames:
		_set_scale(_scale + maxf(GameConfig.render_dynamic_resolution_step_up, 0.0))
		_under_budget_frames = 0
	else:
		_publish_state()
	return _scale


func current_scale() -> float:
	return _scale


func ema_frame_ms() -> float:
	return _ema_frame_ms


func _set_scale(new_scale: float) -> void:
	_scale = clampf(new_scale, _min_scale(), _max_scale())
	_apply_scale(_scale)


func _apply_scale(new_scale: float) -> void:
	if _viewport != null:
		_viewport.scaling_3d_scale = new_scale
	_publish_state()


func _publish_state() -> void:
	set_meta(CURRENT_SCALE_META, _scale)
	set_meta(TARGET_FRAME_MS_META, _target_frame_ms())


func _initial_scale() -> float:
	var project_scale: float = float(ProjectSettings.get_setting("rendering/scaling_3d/scale", _max_scale()))
	return clampf(project_scale, _min_scale(), _max_scale())


func _target_frame_ms() -> float:
	var target_fps: int = maxi(GameConfig.render_max_fps, 1)
	return 1000.0 / float(target_fps)


func _min_scale() -> float:
	return clampf(GameConfig.render_dynamic_resolution_min_scale, 0.25, 1.0)


func _max_scale() -> float:
	return clampf(GameConfig.render_dynamic_resolution_max_scale, _min_scale(), 1.0)


func _ema_alpha() -> float:
	return clampf(GameConfig.render_dynamic_resolution_ema_alpha, 0.01, 1.0)


func _enable_render_time_measurement() -> void:
	if _viewport == null or _measure_render_time_enabled:
		return
	RenderingServer.viewport_set_measure_render_time(_viewport.get_viewport_rid(), true)
	_measure_render_time_enabled = true


func _disable_render_time_measurement() -> void:
	if _viewport == null or not _measure_render_time_enabled:
		return
	RenderingServer.viewport_set_measure_render_time(_viewport.get_viewport_rid(), false)
	_measure_render_time_enabled = false


func _measured_gpu_frame_ms() -> float:
	if _viewport == null or not _measure_render_time_enabled:
		return 0.0
	return maxf(RenderingServer.viewport_get_measured_render_time_gpu(_viewport.get_viewport_rid()), 0.0)
