extends Node

const CedarHollowPlayableScene: PackedScene = preload("res://scenes/cedar_hollow_playable.tscn")
const DEFAULT_DURATION_SECONDS: float = 40.0
const DEFAULT_HITCH_THRESHOLD_MS: float = 20.0
const DEFAULT_OUT_ROOT: String = "tests/out/perf"
const WINDOW_SIZE: Vector2i = Vector2i(2880, 1620)
const STREAM_WAIT_FRAMES: int = 1800
const SETTLE_FRAMES: int = 30
const CROSSING_WINDOW_FRAMES: int = 5
const MEDIAN_WINDOW_SIZE: int = 121
const HITCH_MEDIAN_MULTIPLIER: float = 2.0
const STEER_PERIOD_SECONDS: float = 9.5
const STEER_STRENGTH: float = 0.18
const FAIL_EXIT_CODE: int = 1
const SCENARIO_DEFAULT: String = "default"
const SCENARIO_STRESS: String = "stress"
const SCENARIO_GENTLE_ALIAS: String = "gentle"
const STRESS_PHASE_ACCEL: int = 0
const STRESS_PHASE_SLALOM: int = 1
const STRESS_PHASE_BRAKE: int = 2
const STRESS_ACCEL_MIN_SECONDS: float = 2.0
const STRESS_ACCEL_MAX_SECONDS: float = 12.0
const STRESS_TOP_SPEED_RATIO: float = 0.92
const STRESS_SLALOM_HOLD_SECONDS: float = 5.0
const STRESS_BRAKE_MAX_SECONDS: float = 5.0
const STRESS_NEAR_STOP_SPEED_MPS: float = 1.25
const STRESS_STEER_SWITCH_SECONDS: float = 0.55
const STRESS_STEER_DEADZONE: float = 0.01
const STRESS_OUTWARD_BIAS_PERIOD_SECONDS: float = 7.0
const STRESS_OUTWARD_BIAS_DURATION_SECONDS: float = 2.5
const STRESS_OUTWARD_MIN_STEER: float = 0.2
const STRESS_OUTWARD_STEER_GAIN: float = 1.5
const DYNAMIC_RESOLUTION_CONTROLLER_NAME: String = "RenderDynamicResolutionController"
const DYNAMIC_RESOLUTION_TARGET_FRAME_MS_META: StringName = &"trailhead_dynamic_resolution_target_frame_ms"
const SCALE_CHANGE_EPSILON: float = 0.0001

var _host: Node = null
var _duration_seconds: float = DEFAULT_DURATION_SECONDS
var _hitch_threshold_ms: float = DEFAULT_HITCH_THRESHOLD_MS
var _steer_strength: float = STEER_STRENGTH
var _out_root: String = DEFAULT_OUT_ROOT
var _scenario: String = SCENARIO_DEFAULT
var _run_dir: String = ""
var _errors: PackedStringArray = PackedStringArray()
var _frame_rows: PackedStringArray = PackedStringArray()
var _dt_samples_ms: Array[float] = []
var _fps_samples: Array[float] = []
var _draw_call_samples: Array[float] = []
var _video_mem_samples_mb: Array[float] = []
var _focus_samples: Array[float] = []
var _viewport_cpu_samples_ms: Array[float] = []
var _viewport_gpu_samples_ms: Array[float] = []
var _scaling_3d_scale_samples: Array[float] = []
var _positive_gpu_sample_count: int = 0
var _hitch_count: int = 0
var _crossing_hitch_count: int = 0
var _crossing_count: int = 0
var _scaling_change_count: int = 0
var _scaling_change_hitch_count: int = 0
var _frame_index: int = 0
var _last_cell: Vector2i = Vector2i.ZERO
var _has_last_cell: bool = false
var _last_scaling_3d_scale: float = 1.0
var _has_last_scaling_3d_scale: bool = false
var _last_crossing_frame: int = -1000000
var _stress_phase: int = STRESS_PHASE_ACCEL
var _stress_phase_elapsed: float = 0.0
var _stress_started: bool = false
var _stress_launch_count: int = 0
var _stress_cycle_count: int = 0
var _stress_brake_count: int = 0
var _stress_throttle_held: bool = false
var _stress_outward_bias_held: bool = false
var _stress_longest_throttle_stall_ms: float = 0.0
var _stress_throttle_hitch_count: int = 0
var _stress_outward_bias_samples: int = 0
var _stress_outward_bias_hitches: int = 0
var _stress_fresh_cell_crossings: int = 0
var _stress_streamed_cells: Dictionary[Vector2i, bool] = {}
var _stress_visited_drive_cells: Dictionary[Vector2i, bool] = {}


func _ready() -> void:
	_parse_args()
	DisplayServer.window_set_size(WINDOW_SIZE)
	_force_foreground()
	_prepare_output_dir()
	_host = CedarHollowPlayableScene.instantiate()
	add_child(_host)
	call_deferred("_run")


func _force_foreground() -> void:
	# Permanent harness fix: macOS throttles CAMetalLayer present (nextDrawable) for
	# occluded / App-Napped windows up to ~1s, which corrupts wall-clock dt measurement.
	# Pull the window to the front, keep it on top, and grab focus so the present path
	# is not throttle-gated. App Nap itself is disabled at the process level by the
	# launcher (caffeinate + NSAppSleepDisabled) — see tools/run_perf_drive.sh.
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	DisplayServer.window_move_to_foreground()
	DisplayServer.window_request_attention()


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		var text: String = String(arg)
		if text.begins_with("--duration="):
			_duration_seconds = maxf(text.trim_prefix("--duration=").to_float(), 1.0)
		elif text.begins_with("--hitch-threshold-ms="):
			_hitch_threshold_ms = maxf(text.trim_prefix("--hitch-threshold-ms=").to_float(), 1.0)
		elif text.begins_with("--steer-strength="):
			_steer_strength = clampf(text.trim_prefix("--steer-strength=").to_float(), 0.0, 1.0)
		elif text.begins_with("--out-root="):
			_out_root = text.trim_prefix("--out-root=")
		elif text.begins_with("--scenario="):
			_parse_scenario(text.trim_prefix("--scenario="))


func _parse_scenario(value: String) -> void:
	if value == SCENARIO_STRESS:
		_scenario = SCENARIO_STRESS
	elif value == SCENARIO_DEFAULT or value == SCENARIO_GENTLE_ALIAS:
		_scenario = SCENARIO_DEFAULT
	else:
		_errors.append("unknown perf autodrive scenario: " + value)


func _prepare_output_dir() -> void:
	var stamp: String = Time.get_datetime_string_from_system(false, true).replace(":", "").replace("-", "").replace("T", "_")
	_run_dir = _absolute_path(_out_root.path_join(stamp))
	var err: Error = DirAccess.make_dir_recursive_absolute(_run_dir)
	if err != OK:
		_errors.append("failed to create perf output dir: " + _run_dir + " error=" + str(err))


func _run() -> void:
	if _host == null:
		_errors.append("failed to instantiate Cedar Hollow playable scene")
		await _finish()
		return
	await _wait_for_streaming()
	await _wait_frames(SETTLE_FRAMES)
	if not _errors.is_empty():
		await _finish()
		return
	_enable_viewport_render_time_measurement()
	_frame_rows.append("frame,dt_ms,fps,process_ms,physics_process_ms,viewport_cpu_ms,viewport_gpu_ms,scaling_3d_scale,scaling_3d_scale_changed,dynamic_res_target_ms,draw_calls,primitives,objects,video_mem_mb,static_mem_mb,current_cell,active_cells,ready_cells,stream_tick,crossing_flag,hitch_flag,hitch_at_crossing,window_is_focused")
	await _drive_and_sample()
	_release_input()
	await _write_reports()
	await _finish()


func _wait_for_streaming() -> void:
	for _i in range(STREAM_WAIT_FRAMES):
		var streamer: Node = _tile_streamer()
		var vehicle: Node = _vehicle()
		if streamer != null and vehicle != null:
			var active_count: int = _active_cell_count(streamer)
			var ready_count: int = _ready_cell_count(streamer)
			if active_count > 0 and ready_count >= active_count and not _vehicle_streaming_frozen(vehicle):
				return
		await get_tree().physics_frame
		await get_tree().process_frame
	_errors.append("timed out waiting for vehicle and streamed collision cells")


func _drive_and_sample() -> void:
	var elapsed_seconds: float = 0.0
	# Use REAL wall-clock frame time, not get_process_delta_time() — Godot clamps/
	# smooths the process delta (spiral-of-death protection), so a 500 ms freeze is
	# reported as ~the clamp ceiling. Time.get_ticks_usec() captures the true stall.
	var last_usec: int = Time.get_ticks_usec()
	while elapsed_seconds < _duration_seconds:
		await get_tree().process_frame
		var now_usec: int = Time.get_ticks_usec()
		var dt: float = maxf(float(now_usec - last_usec) / 1000000.0, 0.0)
		last_usec = now_usec
		elapsed_seconds += dt
		if _scenario == SCENARIO_STRESS:
			_apply_stress_drive_input(elapsed_seconds, dt)
		else:
			_apply_drive_input(elapsed_seconds)
		_sample_frame(dt)


func _apply_drive_input(elapsed_seconds: float) -> void:
	Input.action_press(&"throttle", 1.0)
	var steer_value: float = sin(elapsed_seconds / STEER_PERIOD_SECONDS * TAU) * _steer_strength
	if steer_value > 0.01:
		Input.action_press(&"steer_left", steer_value)
		Input.action_release(&"steer_right")
	elif steer_value < -0.01:
		Input.action_press(&"steer_right", -steer_value)
		Input.action_release(&"steer_left")
	else:
		Input.action_release(&"steer_left")
		Input.action_release(&"steer_right")


func _apply_stress_drive_input(elapsed_seconds: float, dt: float) -> void:
	if not _stress_started:
		_stress_started = true
		_stress_launch_count += 1
	_stress_record_streamed_cells(_tile_streamer())
	_stress_update_phase(dt)
	var throttle: float = 1.0
	var brake: float = 0.0
	var steer_value: float = 0.0
	_stress_outward_bias_held = false
	if _stress_phase == STRESS_PHASE_BRAKE:
		throttle = 0.0
		brake = 1.0
		steer_value = 0.0
	elif _stress_phase == STRESS_PHASE_SLALOM:
		steer_value = _stress_slalom_steer(elapsed_seconds)
		if _stress_should_bias_outward(elapsed_seconds):
			var outward_steer: float = _stress_outward_steer_value()
			if absf(outward_steer) >= STRESS_OUTWARD_MIN_STEER:
				steer_value = 1.0 if outward_steer > 0.0 else -1.0
				_stress_outward_bias_held = true
	_stress_throttle_held = throttle > 0.0
	_apply_stress_controls(throttle, brake, steer_value)


func _stress_update_phase(dt: float) -> void:
	_stress_phase_elapsed += dt
	var speed: float = _vehicle_speed_mps()
	if _stress_phase == STRESS_PHASE_ACCEL:
		var top_speed_target: float = maxf(float(GameConfig.max_speed) * STRESS_TOP_SPEED_RATIO, STRESS_NEAR_STOP_SPEED_MPS)
		var hit_top_speed: bool = speed >= top_speed_target and _stress_phase_elapsed >= STRESS_ACCEL_MIN_SECONDS
		if hit_top_speed or _stress_phase_elapsed >= STRESS_ACCEL_MAX_SECONDS:
			_stress_set_phase(STRESS_PHASE_SLALOM)
	elif _stress_phase == STRESS_PHASE_SLALOM:
		if _stress_phase_elapsed >= STRESS_SLALOM_HOLD_SECONDS:
			_stress_set_phase(STRESS_PHASE_BRAKE)
	elif _stress_phase == STRESS_PHASE_BRAKE:
		if speed <= STRESS_NEAR_STOP_SPEED_MPS or _stress_phase_elapsed >= STRESS_BRAKE_MAX_SECONDS:
			_stress_cycle_count += 1
			_stress_launch_count += 1
			_stress_set_phase(STRESS_PHASE_ACCEL)


func _stress_set_phase(phase: int) -> void:
	_stress_phase = phase
	_stress_phase_elapsed = 0.0
	if phase == STRESS_PHASE_BRAKE:
		_stress_brake_count += 1


func _stress_slalom_steer(elapsed_seconds: float) -> float:
	var switch_index: int = int(floorf(elapsed_seconds / STRESS_STEER_SWITCH_SECONDS))
	return 1.0 if switch_index % 2 == 0 else -1.0


func _stress_should_bias_outward(elapsed_seconds: float) -> bool:
	var cycle_position: float = fposmod(elapsed_seconds, STRESS_OUTWARD_BIAS_PERIOD_SECONDS)
	return cycle_position <= STRESS_OUTWARD_BIAS_DURATION_SECONDS


func _stress_outward_steer_value() -> float:
	var vehicle_node: Node3D = _vehicle_node3d()
	if vehicle_node == null:
		return 0.0
	var target_direction: Vector3 = _stress_fresh_target_direction(vehicle_node)
	if target_direction.length() <= 0.001:
		return 0.0
	var right: Vector3 = vehicle_node.global_transform.basis.x
	right.y = 0.0
	if right.length() <= 0.001:
		return 0.0
	right = right.normalized()
	return clampf(-target_direction.dot(right) * STRESS_OUTWARD_STEER_GAIN, -1.0, 1.0)


func _stress_fresh_target_direction(vehicle_node: Node3D) -> Vector3:
	var current_cell: Vector2i = _current_cell(_tile_streamer())
	var vehicle_position: Vector3 = vehicle_node.global_position
	var outward: Vector3 = Vector3(vehicle_position.x, 0.0, vehicle_position.z)
	if outward.length() <= 0.001:
		outward = _vehicle_forward(vehicle_node)
	var candidates: Array[Vector2i] = _stress_outward_candidates(outward)
	for step in candidates:
		if step == Vector2i.ZERO:
			continue
		var target_cell: Vector2i = current_cell + step
		if not _stress_streamed_cells.has(target_cell):
			return Vector3(float(step.x), 0.0, float(step.y)).normalized()
	if candidates.is_empty():
		return Vector3.ZERO
	var fallback_step: Vector2i = candidates[0]
	if fallback_step == Vector2i.ZERO:
		return Vector3.ZERO
	return Vector3(float(fallback_step.x), 0.0, float(fallback_step.y)).normalized()


func _stress_outward_candidates(outward: Vector3) -> Array[Vector2i]:
	var sign_x: int = _stress_sign_step(outward.x)
	var sign_z: int = _stress_sign_step(outward.z)
	var x_step: Vector2i = Vector2i(sign_x, 0)
	var z_step: Vector2i = Vector2i(0, sign_z)
	var diagonal_step: Vector2i = Vector2i(sign_x, sign_z)
	var candidates: Array[Vector2i] = []
	if absf(outward.x) >= absf(outward.z):
		_stress_append_step(candidates, x_step)
		_stress_append_step(candidates, diagonal_step)
		_stress_append_step(candidates, z_step)
	else:
		_stress_append_step(candidates, z_step)
		_stress_append_step(candidates, diagonal_step)
		_stress_append_step(candidates, x_step)
	var forward_step: Vector2i = _stress_forward_step()
	_stress_append_step(candidates, forward_step)
	return candidates


func _stress_append_step(candidates: Array[Vector2i], step: Vector2i) -> void:
	if step == Vector2i.ZERO:
		return
	if not candidates.has(step):
		candidates.append(step)


func _stress_forward_step() -> Vector2i:
	var vehicle_node: Node3D = _vehicle_node3d()
	if vehicle_node == null:
		return Vector2i.ZERO
	var forward: Vector3 = _vehicle_forward(vehicle_node)
	if forward.length() <= 0.001:
		return Vector2i.ZERO
	if absf(forward.x) >= absf(forward.z):
		return Vector2i(_stress_sign_step(forward.x), 0)
	return Vector2i(0, _stress_sign_step(forward.z))


func _vehicle_forward(vehicle_node: Node3D) -> Vector3:
	var forward: Vector3 = -vehicle_node.global_transform.basis.z
	forward.y = 0.0
	if forward.length() <= 0.001:
		return Vector3.ZERO
	return forward.normalized()


func _stress_sign_step(value: float) -> int:
	if value > 0.0:
		return 1
	if value < 0.0:
		return -1
	return 0


func _apply_stress_controls(throttle: float, brake: float, steer_value: float) -> void:
	if throttle > 0.0:
		Input.action_press(&"throttle", throttle)
	else:
		Input.action_release(&"throttle")
	if brake > 0.0:
		Input.action_press(&"brake", brake)
	else:
		Input.action_release(&"brake")
	Input.action_release(&"reverse")
	Input.action_release(&"ebrake")
	if steer_value > STRESS_STEER_DEADZONE:
		Input.action_press(&"steer_left", steer_value)
		Input.action_release(&"steer_right")
	elif steer_value < -STRESS_STEER_DEADZONE:
		Input.action_press(&"steer_right", -steer_value)
		Input.action_release(&"steer_left")
	else:
		Input.action_release(&"steer_left")
		Input.action_release(&"steer_right")


func _release_input() -> void:
	Input.action_release(&"throttle")
	Input.action_release(&"brake")
	Input.action_release(&"reverse")
	Input.action_release(&"ebrake")
	Input.action_release(&"steer_left")
	Input.action_release(&"steer_right")
	_stress_throttle_held = false
	_stress_outward_bias_held = false


func _sample_frame(dt: float) -> void:
	_frame_index += 1
	var streamer: Node = _tile_streamer()
	var current_cell: Vector2i = _current_cell(streamer)
	var crossing_flag: bool = false
	if _has_last_cell and current_cell != _last_cell:
		crossing_flag = true
		_crossing_count += 1
		_last_crossing_frame = _frame_index
	_last_cell = current_cell
	_has_last_cell = true

	var dt_ms: float = dt * 1000.0
	var fps: float = float(Engine.get_frames_per_second())
	var draw_calls: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var primitives: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var objects: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	var process_ms: float = float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0
	var physics_ms: float = float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0
	var viewport: Viewport = get_viewport()
	var viewport_rid: RID = viewport.get_viewport_rid()
	var viewport_cpu_ms: float = maxf(float(RenderingServer.viewport_get_measured_render_time_cpu(viewport_rid)), 0.0)
	var viewport_gpu_ms: float = maxf(float(RenderingServer.viewport_get_measured_render_time_gpu(viewport_rid)), 0.0)
	var scaling_3d_scale: float = viewport.scaling_3d_scale
	var scaling_3d_scale_changed: bool = _scaling_3d_scale_changed(scaling_3d_scale)
	var dynamic_res_target_ms: float = _dynamic_resolution_target_frame_ms()
	var video_mem_mb: float = float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / (1024.0 * 1024.0)
	var static_mem_mb: float = float(Performance.get_monitor(Performance.MEMORY_STATIC)) / (1024.0 * 1024.0)
	var active_count: int = _active_cell_count(streamer)
	var ready_count: int = _ready_cell_count(streamer)
	var stream_tick: int = _stream_tick(streamer)
	var hitch_at_crossing: bool = _frame_index - _last_crossing_frame <= CROSSING_WINDOW_FRAMES
	var hitch_flag: bool = _is_hitch(dt_ms)
	if hitch_flag:
		_hitch_count += 1
		if hitch_at_crossing:
			_crossing_hitch_count += 1
		if scaling_3d_scale_changed:
			_scaling_change_hitch_count += 1
	if scaling_3d_scale_changed:
		_scaling_change_count += 1
	var window_focused: bool = DisplayServer.window_is_focused()
	if _scenario == SCENARIO_STRESS:
		_sample_stress_metrics(streamer, current_cell, crossing_flag, hitch_flag, dt_ms)

	_dt_samples_ms.append(dt_ms)
	_fps_samples.append(fps)
	_draw_call_samples.append(float(draw_calls))
	_video_mem_samples_mb.append(video_mem_mb)
	_focus_samples.append(1.0 if window_focused else 0.0)
	_viewport_cpu_samples_ms.append(viewport_cpu_ms)
	_viewport_gpu_samples_ms.append(viewport_gpu_ms)
	_scaling_3d_scale_samples.append(scaling_3d_scale)
	if viewport_gpu_ms > 0.0:
		_positive_gpu_sample_count += 1
	_frame_rows.append("%d,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.4f,%d,%.3f,%d,%d,%d,%.3f,%.3f,%s,%d,%d,%d,%d,%d,%d,%d" % [
		_frame_index,
		dt_ms,
		fps,
		process_ms,
		physics_ms,
		viewport_cpu_ms,
		viewport_gpu_ms,
		scaling_3d_scale,
		1 if scaling_3d_scale_changed else 0,
		dynamic_res_target_ms,
		draw_calls,
		primitives,
		objects,
		video_mem_mb,
		static_mem_mb,
		_cell_to_text(current_cell),
		active_count,
		ready_count,
		stream_tick,
		1 if crossing_flag else 0,
		1 if hitch_flag else 0,
		1 if hitch_at_crossing else 0,
		1 if window_focused else 0,
	])


func _sample_stress_metrics(streamer: Node, current_cell: Vector2i, crossing_flag: bool, hitch_flag: bool, dt_ms: float) -> void:
	_stress_record_streamed_cells(streamer)
	if _stress_throttle_held:
		_stress_longest_throttle_stall_ms = maxf(_stress_longest_throttle_stall_ms, dt_ms)
		if hitch_flag:
			_stress_throttle_hitch_count += 1
	if _stress_outward_bias_held:
		_stress_outward_bias_samples += 1
		if hitch_flag:
			_stress_outward_bias_hitches += 1
	if crossing_flag and not _stress_visited_drive_cells.has(current_cell):
		_stress_fresh_cell_crossings += 1
	_stress_visited_drive_cells[current_cell] = true


func _stress_record_streamed_cells(streamer: Node) -> void:
	if streamer == null:
		return
	if streamer.has_method("active_cells"):
		var active_cells: Array = streamer.call("active_cells")
		for active_cell_variant in active_cells:
			var active_cell: Vector2i = active_cell_variant
			_stress_streamed_cells[active_cell] = true
	if streamer.has_method("ready_cells"):
		var ready_cells: Array = streamer.call("ready_cells")
		for ready_cell_variant in ready_cells:
			var ready_cell: Vector2i = ready_cell_variant
			_stress_streamed_cells[ready_cell] = true


func _is_hitch(dt_ms: float) -> bool:
	if dt_ms <= _hitch_threshold_ms:
		return false
	var recent: Array[float] = []
	var start_index: int = maxi(_dt_samples_ms.size() - MEDIAN_WINDOW_SIZE, 0)
	for i in range(start_index, _dt_samples_ms.size()):
		recent.append(_dt_samples_ms[i])
	if recent.size() < 3:
		return false
	return dt_ms > _percentile(recent, 0.5) * HITCH_MEDIAN_MULTIPLIER


func _write_reports() -> void:
	if not _errors.is_empty():
		return
	var csv_path: String = _run_dir.path_join("frames.csv")
	var csv_file: FileAccess = FileAccess.open(csv_path, FileAccess.WRITE)
	if csv_file == null:
		_errors.append("failed to open perf CSV: " + csv_path)
		return
	for row in _frame_rows:
		csv_file.store_line(row)
	csv_file.close()

	var summary: String = _summary_text()
	var summary_path: String = _run_dir.path_join("summary.txt")
	var summary_file: FileAccess = FileAccess.open(summary_path, FileAccess.WRITE)
	if summary_file == null:
		_errors.append("failed to open perf summary: " + summary_path)
		return
	summary_file.store_string(summary)
	summary_file.close()
	print(summary)


func _summary_text() -> String:
	var duration: float = _sum(_dt_samples_ms) / 1000.0
	var avg_dt: float = _average(_dt_samples_ms)
	var p50_dt: float = _percentile(_dt_samples_ms, 0.5)
	var p95_dt: float = _percentile(_dt_samples_ms, 0.95)
	var p99_dt: float = _percentile(_dt_samples_ms, 0.99)
	var max_dt: float = _max_value(_dt_samples_ms)
	var avg_fps: float = _average(_fps_samples)
	var min_fps: float = _min_value(_fps_samples)
	var avg_draw_calls: float = _average(_draw_call_samples)
	var max_draw_calls: float = _max_value(_draw_call_samples)
	var avg_vram: float = _average(_video_mem_samples_mb)
	var max_vram: float = _max_value(_video_mem_samples_mb)
	var avg_viewport_cpu_ms: float = _average(_viewport_cpu_samples_ms)
	var p95_viewport_cpu_ms: float = _percentile(_viewport_cpu_samples_ms, 0.95)
	var max_viewport_cpu_ms: float = _max_value(_viewport_cpu_samples_ms)
	var avg_viewport_gpu_ms: float = _average(_viewport_gpu_samples_ms)
	var p95_viewport_gpu_ms: float = _percentile(_viewport_gpu_samples_ms, 0.95)
	var max_viewport_gpu_ms: float = _max_value(_viewport_gpu_samples_ms)
	var min_scaling_3d_scale: float = _min_value(_scaling_3d_scale_samples)
	var max_scaling_3d_scale: float = _max_value(_scaling_3d_scale_samples)
	var hitch_crossing_pct: float = 0.0
	if _hitch_count > 0:
		hitch_crossing_pct = float(_crossing_hitch_count) / float(_hitch_count) * 100.0
	var focus_ratio: float = _average(_focus_samples)
	var walls_110_145: int = _count_in_range(_dt_samples_ms, 110.0, 145.0)
	var lines: PackedStringArray = PackedStringArray([
		"ok: perf autodrive report " + _run_dir,
		"frames=%d duration_s=%.3f crossings=%d" % [_dt_samples_ms.size(), duration, _crossing_count],
		"frame_ms avg=%.3f p50=%.3f p95=%.3f p99=%.3f max=%.3f" % [avg_dt, p50_dt, p95_dt, p99_dt, max_dt],
		"fps avg=%.3f min=%.3f" % [avg_fps, min_fps],
		"window_is_focused ratio=%.3f  walls_110_145ms=%d" % [focus_ratio, walls_110_145],
		"hitches count=%d at_crossing=%d at_crossing_pct=%.1f threshold_ms=%.3f median_multiplier=%.1f crossing_window_frames=%d" % [_hitch_count, _crossing_hitch_count, hitch_crossing_pct, _hitch_threshold_ms, HITCH_MEDIAN_MULTIPLIER, CROSSING_WINDOW_FRAMES],
		"viewport_cpu_ms avg=%.3f p95=%.3f max=%.3f" % [avg_viewport_cpu_ms, p95_viewport_cpu_ms, max_viewport_cpu_ms],
		"viewport_gpu_ms positive_samples=%d/%d avg=%.3f p95=%.3f max=%.3f" % [_positive_gpu_sample_count, _viewport_gpu_samples_ms.size(), avg_viewport_gpu_ms, p95_viewport_gpu_ms, max_viewport_gpu_ms],
		"scaling_3d_scale min=%.4f max=%.4f changes=%d hitches_on_change=%d" % [min_scaling_3d_scale, max_scaling_3d_scale, _scaling_change_count, _scaling_change_hitch_count],
		"draw_calls avg=%.1f max=%.0f" % [avg_draw_calls, max_draw_calls],
		"video_mem_mb avg=%.1f max=%.1f" % [avg_vram, max_vram],
	])
	if _scenario == SCENARIO_STRESS:
		lines.append("stress launches=%d completed_cycles=%d brake_windows=%d longest_throttle_stall_ms=%.3f throttle_hitches=%d fresh_cell_crossings=%d outward_bias_samples=%d outward_bias_hitches=%d" % [
			_stress_launch_count,
			_stress_cycle_count,
			_stress_brake_count,
			_stress_longest_throttle_stall_ms,
			_stress_throttle_hitch_count,
			_stress_fresh_cell_crossings,
			_stress_outward_bias_samples,
			_stress_outward_bias_hitches,
		])
	lines.append("csv=" + _run_dir.path_join("frames.csv"))
	return "\n".join(lines)


func _finish() -> void:
	_release_input()
	_disable_viewport_render_time_measurement()
	var exit_code: int = 0
	if not _errors.is_empty():
		exit_code = FAIL_EXIT_CODE
		for error in _errors:
			push_error(error)
			print("FAIL: " + error)
	get_tree().quit(exit_code)


func _wait_frames(count: int) -> void:
	for _i in range(count):
		await get_tree().process_frame


func _tile_streamer() -> Node:
	return get_node_or_null("/root/TileStreamer")


func _vehicle() -> Node:
	if GameManager.active_vehicle != null:
		return GameManager.active_vehicle
	if _host != null:
		return _host.get_node_or_null("Vehicle")
	return null


func _vehicle_node3d() -> Node3D:
	var vehicle: Node = _vehicle()
	if vehicle == null:
		return null
	return vehicle as Node3D


func _vehicle_speed_mps() -> float:
	var vehicle: Node = _vehicle()
	if vehicle == null or not vehicle.has_method("get_state"):
		return 0.0
	var state: RefCounted = vehicle.call("get_state")
	if state == null:
		return 0.0
	var linear_velocity: Vector3 = state.get("linear_velocity")
	return linear_velocity.length()


func _vehicle_streaming_frozen(vehicle: Node) -> bool:
	if vehicle.has_method("is_streaming_collision_freeze_active"):
		return bool(vehicle.call("is_streaming_collision_freeze_active"))
	return false


func _current_cell(streamer: Node) -> Vector2i:
	if streamer != null and streamer.has_method("current_cell"):
		return streamer.call("current_cell")
	return Vector2i.ZERO


func _active_cell_count(streamer: Node) -> int:
	if streamer != null and streamer.has_method("active_cells"):
		var cells: Array = streamer.call("active_cells")
		return cells.size()
	return 0


func _ready_cell_count(streamer: Node) -> int:
	if streamer != null and streamer.has_method("ready_cells"):
		var cells: Array = streamer.call("ready_cells")
		return cells.size()
	return 0


func _stream_tick(streamer: Node) -> int:
	if streamer != null and streamer.has_method("current_stream_tick"):
		return int(streamer.call("current_stream_tick"))
	return 0


func _enable_viewport_render_time_measurement() -> void:
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return
	RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(), true)


func _disable_viewport_render_time_measurement() -> void:
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return
	RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(), false)


func _scaling_3d_scale_changed(scaling_3d_scale: float) -> bool:
	var changed: bool = false
	if _has_last_scaling_3d_scale:
		changed = absf(scaling_3d_scale - _last_scaling_3d_scale) > SCALE_CHANGE_EPSILON
	_last_scaling_3d_scale = scaling_3d_scale
	_has_last_scaling_3d_scale = true
	return changed


func _dynamic_resolution_target_frame_ms() -> float:
	var controller: Node = _dynamic_resolution_controller()
	if controller != null and controller.has_meta(DYNAMIC_RESOLUTION_TARGET_FRAME_MS_META):
		return float(controller.get_meta(DYNAMIC_RESOLUTION_TARGET_FRAME_MS_META))
	if Engine.max_fps > 0:
		return 1000.0 / float(Engine.max_fps)
	return 0.0


func _dynamic_resolution_controller() -> Node:
	if _host == null:
		return null
	return _host.get_node_or_null(NodePath(DYNAMIC_RESOLUTION_CONTROLLER_NAME))


func _cell_to_text(cell: Vector2i) -> String:
	return str(cell.x) + ":" + str(cell.y)


func _absolute_path(path: String) -> String:
	if path.is_absolute_path():
		return path
	return ProjectSettings.globalize_path("res://" + path)


func _sum(values: Array[float]) -> float:
	var total: float = 0.0
	for value in values:
		total += value
	return total


func _average(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	return _sum(values) / float(values.size())


func _percentile(values: Array[float], percentile: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted: Array[float] = values.duplicate()
	sorted.sort()
	var index: int = clampi(int(floor(percentile * float(sorted.size() - 1))), 0, sorted.size() - 1)
	return sorted[index]


func _count_in_range(values: Array[float], low: float, high: float) -> int:
	var count: int = 0
	for value in values:
		if value >= low and value <= high:
			count += 1
	return count


func _min_value(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var result: float = values[0]
	for value in values:
		result = minf(result, value)
	return result


func _max_value(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var result: float = values[0]
	for value in values:
		result = maxf(result, value)
	return result
