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

var _host: Node = null
var _duration_seconds: float = DEFAULT_DURATION_SECONDS
var _hitch_threshold_ms: float = DEFAULT_HITCH_THRESHOLD_MS
var _steer_strength: float = STEER_STRENGTH
var _out_root: String = DEFAULT_OUT_ROOT
var _run_dir: String = ""
var _errors: PackedStringArray = PackedStringArray()
var _frame_rows: PackedStringArray = PackedStringArray()
var _dt_samples_ms: Array[float] = []
var _fps_samples: Array[float] = []
var _draw_call_samples: Array[float] = []
var _video_mem_samples_mb: Array[float] = []
var _focus_samples: Array[float] = []
var _hitch_count: int = 0
var _crossing_hitch_count: int = 0
var _crossing_count: int = 0
var _frame_index: int = 0
var _last_cell: Vector2i = Vector2i.ZERO
var _has_last_cell: bool = false
var _last_crossing_frame: int = -1000000


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
	_frame_rows.append("frame,dt_ms,fps,process_ms,physics_process_ms,draw_calls,primitives,objects,video_mem_mb,static_mem_mb,current_cell,active_cells,ready_cells,stream_tick,crossing_flag,hitch_flag,hitch_at_crossing,window_is_focused")
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


func _release_input() -> void:
	Input.action_release(&"throttle")
	Input.action_release(&"steer_left")
	Input.action_release(&"steer_right")


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
	var window_focused: bool = DisplayServer.window_is_focused()

	_dt_samples_ms.append(dt_ms)
	_fps_samples.append(fps)
	_draw_call_samples.append(float(draw_calls))
	_video_mem_samples_mb.append(video_mem_mb)
	_focus_samples.append(1.0 if window_focused else 0.0)
	_frame_rows.append("%d,%.3f,%.3f,%.3f,%.3f,%d,%d,%d,%.3f,%.3f,%s,%d,%d,%d,%d,%d,%d,%d" % [
		_frame_index,
		dt_ms,
		fps,
		process_ms,
		physics_ms,
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
	var hitch_crossing_pct: float = 0.0
	if _hitch_count > 0:
		hitch_crossing_pct = float(_crossing_hitch_count) / float(_hitch_count) * 100.0
	var focus_ratio: float = _average(_focus_samples)
	var walls_110_145: int = _count_in_range(_dt_samples_ms, 110.0, 145.0)
	return "\n".join(PackedStringArray([
		"ok: perf autodrive report " + _run_dir,
		"frames=%d duration_s=%.3f crossings=%d" % [_dt_samples_ms.size(), duration, _crossing_count],
		"frame_ms avg=%.3f p50=%.3f p95=%.3f p99=%.3f max=%.3f" % [avg_dt, p50_dt, p95_dt, p99_dt, max_dt],
		"fps avg=%.3f min=%.3f" % [avg_fps, min_fps],
		"window_is_focused ratio=%.3f  walls_110_145ms=%d" % [focus_ratio, walls_110_145],
		"hitches count=%d at_crossing=%d at_crossing_pct=%.1f threshold_ms=%.3f median_multiplier=%.1f crossing_window_frames=%d" % [_hitch_count, _crossing_hitch_count, hitch_crossing_pct, _hitch_threshold_ms, HITCH_MEDIAN_MULTIPLIER, CROSSING_WINDOW_FRAMES],
		"draw_calls avg=%.1f max=%.0f" % [avg_draw_calls, max_draw_calls],
		"video_mem_mb avg=%.1f max=%.1f" % [avg_vram, max_vram],
		"csv=" + _run_dir.path_join("frames.csv"),
	]))


func _finish() -> void:
	_release_input()
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
