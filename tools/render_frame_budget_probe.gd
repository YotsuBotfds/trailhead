extends Node

const TerrainVisualStreamerScript: GDScript = preload("res://systems/render/terrain_visual_streamer.gd")
const RenderRuntimeConfigScript: GDScript = preload("res://systems/render/render_runtime_config.gd")

const DEFAULT_OUT_PATH: String = "res://tests/out/render_frame_budget/spike_streamed.json"
const DEFAULT_REGION_ID: String = "spike_1km"
const WINDOW_SIZE: Vector2i = Vector2i(1280, 720)
const CAMERA_POSITION: Vector3 = Vector3(508.0, 4.0, 208.0)
const CAMERA_TARGET: Vector3 = Vector3(540.0, 1.0, 245.0)
const SPIKE_INITIAL_MIN_CELL: Vector2i = Vector2i(2, 2)
const SPIKE_INITIAL_MAX_CELL: Vector2i = Vector2i(6, 6)
const ZION_REGION_ID: String = "cedar_hollow_zion"
const ZION_CAMERA_POSITION: Vector3 = Vector3(1148.0, 1201.0, 790.0)
const ZION_CAMERA_TARGET: Vector3 = Vector3(1255.0, 1200.0, 835.0)
const ZION_INITIAL_MIN_CELL: Vector2i = Vector2i(9, 6)
const ZION_INITIAL_MAX_CELL: Vector2i = Vector2i(13, 10)
const BASELINE_FRAMES: int = 12
const BURST_FRAMES: int = 24
const STEADY_FRAMES: int = 36
const READY_WAIT_FRAMES: int = 1200
const TARGET_FRAME_MS: float = 16.6667
const SAMPLE_LABEL_VISIBLE: String = "visible"
const SAMPLE_LABEL_SHADOW: String = "shadow"
const SAMPLE_LABEL_CANVAS: String = "canvas"

var _out_path: String = DEFAULT_OUT_PATH
var _region_id: String = DEFAULT_REGION_ID
var _camera_position: Vector3 = CAMERA_POSITION
var _camera_target: Vector3 = CAMERA_TARGET
var _initial_min_cell: Vector2i = SPIKE_INITIAL_MIN_CELL
var _initial_max_cell: Vector2i = SPIKE_INITIAL_MAX_CELL
var _streamer: Node3D = null
var _result: Dictionary[String, Variant] = {}
var _errors: PackedStringArray = PackedStringArray()


func _ready() -> void:
	RenderRuntimeConfigScript.apply_to(self)
	_parse_args()
	_apply_region_defaults()
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_size(WINDOW_SIZE)
	_setup_render_shell()
	call_deferred("_run")


func _exit_tree() -> void:
	if _streamer != null:
		_streamer.call("reset_stream")


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		var text: String = String(arg)
		if text.begins_with("--out="):
			_out_path = text.trim_prefix("--out=")
		elif text.begins_with("--region="):
			_region_id = text.trim_prefix("--region=")


func _apply_region_defaults() -> void:
	if _region_id != ZION_REGION_ID:
		return
	if _out_path == DEFAULT_OUT_PATH:
		_out_path = "res://tests/out/render_frame_budget/zion_streamed.json"
	_camera_position = ZION_CAMERA_POSITION
	_camera_target = ZION_CAMERA_TARGET
	_initial_min_cell = ZION_INITIAL_MIN_CELL
	_initial_max_cell = ZION_INITIAL_MAX_CELL


func _setup_render_shell() -> void:
	var camera: Camera3D = Camera3D.new()
	camera.name = "FrameBudgetCamera"
	camera.current = true
	camera.fov = GameConfig.cam_fov_base
	camera.far = maxf(GameConfig.orbit_cam_far, 500.0)
	camera.look_at_from_position(_camera_position, _camera_target, Vector3.UP)
	add_child(camera)

	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.name = "FrameBudgetSun"
	sun.rotation_degrees = GameConfig.dusk_sun_rotation_degrees
	sun.light_energy = GameConfig.dusk_sun_energy
	sun.light_color = GameConfig.dusk_sun_color
	add_child(sun)

	var world_environment: WorldEnvironment = WorldEnvironment.new()
	world_environment.name = "FrameBudgetEnvironment"
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = GameConfig.dusk_background_color
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = GameConfig.dusk_ambient_color
	environment.ambient_light_energy = GameConfig.dusk_ambient_energy
	world_environment.environment = environment
	add_child(world_environment)

	_streamer = TerrainVisualStreamerScript.new() as Node3D
	if _streamer == null:
		_errors.append("failed to instantiate TerrainVisualStreamer")
		return
	_streamer.name = "RenderFrameBudgetStreamer"
	add_child(_streamer)
	_streamer.call("configure_region", _region_id)


func _run() -> void:
	if _streamer == null:
		_finish()
		return

	var viewport_rid: RID = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport_rid, true)

	_result = {
		"schema": "trailhead.render_frame_budget.v1",
		"region_id": _region_id,
		"target_frame_ms": TARGET_FRAME_MS,
		"render_runtime": {
			"engine_max_fps": Engine.max_fps,
			"target_max_fps": GameConfig.render_max_fps,
			"visual_tile_commits_per_frame": GameConfig.render_visual_tile_commits_per_frame,
			"frame_cap_enabled": GameConfig.render_frame_cap_enabled,
			"frame_cap_skip_requested": RenderRuntimeConfigScript.frame_cap_skip_requested(),
			"frame_cap_applied": int(get_meta(RenderRuntimeConfigScript.RENDER_MAX_FPS_META, 0)) > 0,
			"dynamic_resolution_enabled": GameConfig.render_dynamic_resolution_enabled,
			"dynamic_resolution_installed": bool(get_meta(RenderRuntimeConfigScript.DYNAMIC_RESOLUTION_INSTALLED_META, false)),
		},
		"window_size": [WINDOW_SIZE.x, WINDOW_SIZE.y],
		"camera": {
			"position": _vector3_to_array(_camera_position),
			"target": _vector3_to_array(_camera_target),
		},
		"phases": [],
	}

	await _sample_phase("baseline_empty_streamer", BASELINE_FRAMES, 0.0, 0.0, {}, {})

	var initial_cells: Array[Vector2i] = _rect_cells(_initial_min_cell, _initial_max_cell)
	var initial_prefetch_ms: float = _emit_prefetches(initial_cells)
	var initial_prefetch_wait: Dictionary = await _wait_for_ready_visual_cell_count("initial_25_tile_prefetch", 25)
	var initial_activation_ms: float = _emit_activations(initial_cells)
	var initial_ready_wait: Dictionary = await _wait_for_visual_cell_count("initial_25_tile_burst", 25)
	await _sample_phase("initial_25_tile_burst", BURST_FRAMES, initial_activation_ms, initial_prefetch_ms, initial_ready_wait, initial_prefetch_wait)

	var shifted_out_cells: Array[Vector2i] = _rect_cells(_initial_min_cell, Vector2i(_initial_min_cell.x, _initial_max_cell.y))
	var shifted_in_cells: Array[Vector2i] = _rect_cells(Vector2i(_initial_max_cell.x + 1, _initial_min_cell.y), Vector2i(_initial_max_cell.x + 1, _initial_max_cell.y))
	var shift_prefetch_ms: float = _emit_prefetches(shifted_in_cells)
	var shift_prefetch_wait: Dictionary = await _wait_for_ready_visual_cell_count("east_shift_5_tile_prefetch", 5)
	var shift_activation_ms: float = _emit_shift(shifted_out_cells, shifted_in_cells)
	var shift_ready_wait: Dictionary = await _wait_for_visual_cell_count("east_shift_5_tile_burst", 25)
	await _sample_phase("east_shift_5_tile_burst", BURST_FRAMES, shift_activation_ms, shift_prefetch_ms, shift_ready_wait, shift_prefetch_wait)
	await _sample_phase("steady_streamed_window", STEADY_FRAMES, 0.0, 0.0, {}, {})

	_result["final_visual_cells"] = int(_streamer.call("visual_cell_count"))
	_result["active_visual_cells"] = _cells_to_arrays(_variant_to_cells(_streamer.call("active_visual_cells")))
	_write_result()
	_finish()


func _emit_activations(cells: Array[Vector2i]) -> float:
	var start_usec: int = Time.get_ticks_usec()
	for cell in cells:
		EventBus.world_tile_activated.emit(cell)
	return _usec_to_ms(Time.get_ticks_usec() - start_usec)


func _emit_prefetches(cells: Array[Vector2i]) -> float:
	var start_usec: int = Time.get_ticks_usec()
	for cell in cells:
		EventBus.world_tile_prefetched.emit(cell)
	return _usec_to_ms(Time.get_ticks_usec() - start_usec)


func _emit_shift(evicted_cells: Array[Vector2i], activated_cells: Array[Vector2i]) -> float:
	var start_usec: int = Time.get_ticks_usec()
	for cell in evicted_cells:
		EventBus.world_tile_evicted.emit(cell)
	for cell in activated_cells:
		EventBus.world_tile_activated.emit(cell)
	return _usec_to_ms(Time.get_ticks_usec() - start_usec)


func _wait_for_visual_cell_count(label: String, expected_count: int) -> Dictionary:
	var start_usec: int = Time.get_ticks_usec()
	var frames: int = 0
	while int(_streamer.call("visual_cell_count")) < expected_count and frames < READY_WAIT_FRAMES:
		frames += 1
		await get_tree().process_frame
	var wait_ms: float = _usec_to_ms(Time.get_ticks_usec() - start_usec)
	var observed_count: int = int(_streamer.call("visual_cell_count"))
	if observed_count < expected_count:
		_errors.append(label + " expected " + str(expected_count) + " visual cells before sampling, got " + str(observed_count))
	return {
		"frames": frames,
		"wall_ms": wait_ms,
		"expected_visual_cells": expected_count,
		"observed_visual_cells": observed_count,
	}


func _wait_for_ready_visual_cell_count(label: String, expected_count: int) -> Dictionary:
	var start_usec: int = Time.get_ticks_usec()
	var frames: int = 0
	while int(_streamer.call("ready_visual_cell_count")) < expected_count and frames < READY_WAIT_FRAMES:
		frames += 1
		await get_tree().process_frame
	var wait_ms: float = _usec_to_ms(Time.get_ticks_usec() - start_usec)
	var observed_count: int = int(_streamer.call("ready_visual_cell_count"))
	if observed_count < expected_count:
		_errors.append(label + " expected " + str(expected_count) + " ready visual cells before activation, got " + str(observed_count))
	return {
		"frames": frames,
		"wall_ms": wait_ms,
		"expected_ready_visual_cells": expected_count,
		"observed_ready_visual_cells": observed_count,
	}


func _sample_phase(phase_name: String, frame_count: int, activation_cpu_ms: float, prefetch_cpu_ms: float, ready_wait: Dictionary, prefetch_wait: Dictionary) -> void:
	var viewport_rid: RID = get_viewport().get_viewport_rid()
	var wall_ms: Array[float] = []
	var viewport_cpu_ms: Array[float] = []
	var viewport_gpu_ms: Array[float] = []
	var process_monitor_ms: Array[float] = []
	var physics_monitor_ms: Array[float] = []
	var video_mem_mb: Array[float] = []
	var visible_draw_calls: Array[int] = []
	var shadow_draw_calls: Array[int] = []
	var canvas_draw_calls: Array[int] = []
	var visible_primitives: Array[int] = []
	var shadow_primitives: Array[int] = []
	var canvas_primitives: Array[int] = []
	var visible_objects: Array[int] = []
	var shadow_objects: Array[int] = []
	var canvas_objects: Array[int] = []
	var total_draw_calls: Array[int] = []
	var total_objects: Array[int] = []

	for _i in range(frame_count):
		var frame_start_usec: int = Time.get_ticks_usec()
		await get_tree().process_frame
		wall_ms.append(_usec_to_ms(Time.get_ticks_usec() - frame_start_usec))
		viewport_cpu_ms.append(float(RenderingServer.viewport_get_measured_render_time_cpu(viewport_rid)))
		viewport_gpu_ms.append(float(RenderingServer.viewport_get_measured_render_time_gpu(viewport_rid)))
		process_monitor_ms.append(float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0)
		physics_monitor_ms.append(float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0)
		video_mem_mb.append(float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / (1024.0 * 1024.0))
		visible_draw_calls.append(_viewport_render_info(viewport_rid, SAMPLE_LABEL_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME))
		shadow_draw_calls.append(_viewport_render_info(viewport_rid, SAMPLE_LABEL_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME))
		canvas_draw_calls.append(_viewport_render_info(viewport_rid, SAMPLE_LABEL_CANVAS, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME))
		visible_primitives.append(_viewport_render_info(viewport_rid, SAMPLE_LABEL_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME))
		shadow_primitives.append(_viewport_render_info(viewport_rid, SAMPLE_LABEL_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME))
		canvas_primitives.append(_viewport_render_info(viewport_rid, SAMPLE_LABEL_CANVAS, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME))
		visible_objects.append(_viewport_render_info(viewport_rid, SAMPLE_LABEL_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME))
		shadow_objects.append(_viewport_render_info(viewport_rid, SAMPLE_LABEL_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME))
		canvas_objects.append(_viewport_render_info(viewport_rid, SAMPLE_LABEL_CANVAS, RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME))
		total_draw_calls.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		total_objects.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)))

	var phase: Dictionary = {
		"name": phase_name,
		"frames": frame_count,
		"prefetch_cpu_ms": prefetch_cpu_ms,
		"activation_cpu_ms": activation_cpu_ms,
		"prefetch_ready_wait": prefetch_wait,
		"activation_ready_wait": ready_wait,
		"active_visual_cells": int(_streamer.call("visual_cell_count")),
		"viewport_gpu_timing_available": _has_positive_value(viewport_gpu_ms),
		"timing_ms": {
			"frame_wall": _float_stats(wall_ms),
			"viewport_cpu": _float_stats(viewport_cpu_ms),
			"viewport_gpu": _float_stats(viewport_gpu_ms),
			"process_monitor": _float_stats(process_monitor_ms),
			"physics_monitor": _float_stats(physics_monitor_ms),
		},
		"memory_mb": {
			"render_video": _float_stats(video_mem_mb),
		},
		"render_info": {
			"visible": {
				"draw_calls": _int_stats(visible_draw_calls),
				"primitives": _int_stats(visible_primitives),
				"objects": _int_stats(visible_objects),
			},
			"shadow": {
				"draw_calls": _int_stats(shadow_draw_calls),
				"primitives": _int_stats(shadow_primitives),
				"objects": _int_stats(shadow_objects),
			},
			"canvas": {
				"draw_calls": _int_stats(canvas_draw_calls),
				"primitives": _int_stats(canvas_primitives),
				"objects": _int_stats(canvas_objects),
			},
			"performance_total": {
				"draw_calls": _int_stats(total_draw_calls),
				"objects": _int_stats(total_objects),
			},
		},
	}
	var phases: Array = _result.get("phases", [])
	phases.append(phase)
	_result["phases"] = phases


func _viewport_render_info(viewport_rid: RID, sample_label: String, info: int) -> int:
	var sample_type: int = RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE
	if sample_label == SAMPLE_LABEL_SHADOW:
		sample_type = RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW
	elif sample_label == SAMPLE_LABEL_CANVAS:
		sample_type = RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS
	return int(RenderingServer.viewport_get_render_info(viewport_rid, sample_type, info))


func _rect_cells(min_cell: Vector2i, max_cell: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for x in range(min_cell.x, max_cell.x + 1):
		for y in range(min_cell.y, max_cell.y + 1):
			cells.append(Vector2i(x, y))
	return cells


func _variant_to_cells(value: Variant) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if not (value is Array):
		return cells
	for item in value:
		if item is Vector2i:
			cells.append(item)
	cells.sort_custom(Callable(self, "_cell_less"))
	return cells


func _cell_less(left: Vector2i, right: Vector2i) -> bool:
	if left.x == right.x:
		return left.y < right.y
	return left.x < right.x


func _cells_to_arrays(cells: Array[Vector2i]) -> Array[Array]:
	var output: Array[Array] = []
	for cell in cells:
		output.append([cell.x, cell.y])
	return output


func _vector3_to_array(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]


func _float_stats(values: Array[float]) -> Dictionary:
	var sorted_values: Array[float] = _copy_float_array(values)
	sorted_values.sort()
	var count: int = sorted_values.size()
	if count <= 0:
		return {"min": 0.0, "max": 0.0, "avg": 0.0, "p50": 0.0, "p95": 0.0}
	var sum: float = 0.0
	for value in sorted_values:
		sum += value
	return {
		"min": sorted_values[0],
		"max": sorted_values[count - 1],
		"avg": sum / float(count),
		"p50": sorted_values[_percentile_index(count, 0.5)],
		"p95": sorted_values[_percentile_index(count, 0.95)],
	}


func _int_stats(values: Array[int]) -> Dictionary:
	var floats: Array[float] = []
	for value in values:
		floats.append(float(value))
	return _float_stats(floats)


func _copy_float_array(values: Array[float]) -> Array[float]:
	var copy: Array[float] = []
	for value in values:
		copy.append(value)
	return copy


func _has_positive_value(values: Array[float]) -> bool:
	for value in values:
		if value > 0.0:
			return true
	return false


func _percentile_index(count: int, percentile: float) -> int:
	var raw_index: int = int(ceil(float(count) * percentile)) - 1
	return mini(maxi(raw_index, 0), count - 1)


func _usec_to_ms(usec: int) -> float:
	return float(usec) / 1000.0


func _write_result() -> void:
	var absolute_dir: String = ProjectSettings.globalize_path(_out_path.get_base_dir())
	var err: Error = DirAccess.make_dir_recursive_absolute(absolute_dir)
	if err != OK:
		_errors.append("failed to create output dir " + absolute_dir + " error=" + str(err))
		return
	var file: FileAccess = FileAccess.open(_out_path, FileAccess.WRITE)
	if file == null:
		_errors.append("failed to open output file " + _out_path + " error=" + str(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify(_result, "\t") + "\n")
	file.close()


func _finish() -> void:
	if _errors.is_empty():
		print("ok: render frame budget probe wrote " + _out_path)
		get_tree().quit(0)
		return
	for error in _errors:
		push_error(error)
	get_tree().quit(1)
