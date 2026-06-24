extends Node

# W8-DRIVE-CAPTURE: gameplay-POV drive-and-capture tool.
#
# Loads the real Cedar Hollow playable scene (streamed Zion terrain + foliage +
# boulders + buggy), waits for the visual streamer + title-card auto-dismiss,
# then AUTO-DRIVES forward via Input.action_press(throttle) with the same gentle
# deterministic steering profile perf_autodrive uses, and screenshots the demo's
# real CHASE camera (the gameplay view) at intervals so QA can judge the
# boulder/foliage/surface-micro-detail fill from the DRIVING perspective.
#
# Windowed, NOT --headless — real GPU. Observe-and-drive only: this tool does
# NOT modify the host, sim, vehicle, tile_streamer, terrain, shaders, or
# GameConfig. It reads autoloads, calls existing read-only vehicle accessors,
# and presses Input actions.

const CedarHollowPlayableScene: PackedScene = preload("res://scenes/cedar_hollow_playable.tscn")
const CedarRoute: Resource = preload("res://data/routes/cedar_hollow_zion_stream_route.tres")
const DEFAULT_OUT_ROOT: String = "tests/out/drive_capture"
const WINDOW_SIZE: Vector2i = Vector2i(1280, 720)
const STREAM_WAIT_FRAMES: int = 1800
const TITLE_CARD_WAIT_FRAMES: int = 600
const RENDER_SETTLE_FRAMES: int = 30
const SHUTDOWN_FRAMES: int = 8
const MIN_STREAMED_CELLS: int = 25  # MINIMUM streamed visual+foliage cells before driving; was an exact ==25 gate that rotted when STREAM_ACTIVE_RADIUS grew 2->3 (now 49 active cells)
const CAPTURE_CAMERA_FOV: float = 62.0
const CAPTURE_CAMERA_NAME: String = "DriveCaptureLookbackCamera"
const LOOKBACK_FORWARD_OFFSET: float = 2.5
const LOOKBACK_HEIGHT: float = 0.8
const LOOKBACK_TARGET_BACK: float = 3.0
const VARIANCE_SAMPLE_STEP: int = 32
const MIN_LUMA_VARIANCE: float = 0.015
const STEER_PERIOD_SECONDS: float = 9.5
const STEER_STRENGTH: float = 0.18
const FAIL_EXIT_CODE: int = 1
const DEFAULT_DURATION_SECONDS: float = 32.0
const DEFAULT_SHOT_COUNT: int = 5
# Default cadence per W8 spec: front-loaded early detail, then wider spacing as
# terrain varies more slowly. Used verbatim unless --shots or --duration is
# passed, in which case shot times become evenly-spaced across the duration.
const DEFAULT_SHOT_TIMES_SECONDS: Array[float] = [4.0, 9.0, 15.0, 22.0, 30.0]
const DEFAULT_SPAWN_ID: StringName = &"stream_west"

var _host: Node = null
var _out_root: String = DEFAULT_OUT_ROOT
var _run_dir: String = ""
var _spawn_id: StringName = DEFAULT_SPAWN_ID
var _duration_seconds: float = DEFAULT_DURATION_SECONDS
var _shot_count: int = DEFAULT_SHOT_COUNT
var _shot_times_seconds: Array[float] = []
var _lookback_index: int = 0
var _lookback_camera: Camera3D = null
var _errors: PackedStringArray = PackedStringArray()
var _capture_paths_written: PackedStringArray = PackedStringArray()
var _custom_shots: bool = false
var _custom_duration: bool = false


func _ready() -> void:
	_parse_args()
	DisplayServer.window_set_size(WINDOW_SIZE)
	_compute_shot_times()
	_prepare_output_dir()
	_host = CedarHollowPlayableScene.instantiate()
	add_child(_host)
	_setup_lookback_camera()
	call_deferred("_run")


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		var text: String = String(arg)
		if text.begins_with("--duration="):
			_duration_seconds = maxf(text.trim_prefix("--duration=").to_float(), 4.0)
			_custom_duration = true
		elif text.begins_with("--shots="):
			_shot_count = maxi(text.trim_prefix("--shots=").to_int(), 1)
			_custom_shots = true
		elif text.begins_with("--spawn="):
			_spawn_id = StringName(text.trim_prefix("--spawn="))
		elif text.begins_with("--out-root="):
			_out_root = text.trim_prefix("--out-root=")


func _compute_shot_times() -> void:
	_shot_times_seconds.clear()
	if _custom_shots or _custom_duration:
		# Evenly-spaced fractions of duration, leaving a small tail so the car
		# keeps moving past the last capture for framing/momentum.
		var last_shot_time: float = maxf(_duration_seconds - 2.0, 4.0)
		for i in range(_shot_count):
			var fraction: float = float(i + 1) / float(_shot_count + 1)
			_shot_times_seconds.append(last_shot_time * fraction)
	else:
		_shot_times_seconds = DEFAULT_SHOT_TIMES_SECONDS.duplicate()
		_shot_count = _shot_times_seconds.size()
	_lookback_index = clampi(_shot_count / 2, 0, _shot_count - 1)


func _prepare_output_dir() -> void:
	var stamp: String = Time.get_datetime_string_from_system(false, true).replace(":", "").replace("-", "").replace("T", "_")
	_run_dir = _absolute_path(_out_root.path_join(stamp))
	var err: Error = DirAccess.make_dir_recursive_absolute(_run_dir)
	if err != OK:
		_errors.append("failed to create drive_capture output dir: " + _run_dir + " error=" + str(err))


func _setup_lookback_camera() -> void:
	_lookback_camera = Camera3D.new()
	_lookback_camera.name = CAPTURE_CAMERA_NAME
	_lookback_camera.current = false
	_lookback_camera.fov = CAPTURE_CAMERA_FOV
	_lookback_camera.far = GameConfig.cam_far
	if _host != null:
		_host.add_child(_lookback_camera)
	else:
		add_child(_lookback_camera)


func _run() -> void:
	if _host == null:
		_errors.append("failed to instantiate Cedar Hollow playable scene")
		await _finish()
		return
	_apply_spawn_if_overridden()
	await _wait_for_streaming()
	await _wait_for_title_card_dismissed()
	await _wait_frames(RENDER_SETTLE_FRAMES)
	if not _errors.is_empty():
		await _finish()
		return
	await _drive_and_capture()
	_release_input()
	await _finish()


func _apply_spawn_if_overridden() -> void:
	if _spawn_id == DEFAULT_SPAWN_ID:
		return
	var vehicle: Node = _vehicle()
	if vehicle == null:
		_errors.append("--spawn override failed: host Vehicle not found")
		return
	var xform: Variant = CedarRoute.call("spawn_transform", _spawn_id)
	if xform == null or not xform is Transform3D:
		_errors.append("--spawn override failed: no spawn transform for " + String(_spawn_id))
		return
	vehicle.call("reset_to", xform)


func _wait_for_streaming() -> void:
	for _i in range(STREAM_WAIT_FRAMES):
		if _streaming_ready():
			return
		await get_tree().physics_frame
		await get_tree().process_frame
	_errors.append("drive_capture timed out waiting for streamed visual cells")


func _streaming_ready() -> bool:
	var streamer: Node = _visual_streamer()
	if streamer == null:
		return false
	if int(streamer.call("visual_cell_count")) < MIN_STREAMED_CELLS:
		return false
	if int(streamer.call("foliage_cell_count")) < MIN_STREAMED_CELLS:
		return false
	return true


func _wait_for_title_card_dismissed() -> void:
	# The host's _update_vehicle_input() sets _drive_started once any input
	# arrives and immediately dismisses the title card; the panel then fades
	# itself out on its own _process. We have not pressed anything yet, so the
	# card's internal timer must auto-dismiss it. Poll the inner panel's
	# visibility so we know the fade is done before we start driving/capturing.
	var title_card_hud: Node = _host.get_node_or_null("TitleCardHud") if _host != null else null
	if title_card_hud == null:
		return
	for _i in range(TITLE_CARD_WAIT_FRAMES):
		var panel: CanvasItem = title_card_hud.get_node_or_null("TitleCardPanel") as CanvasItem
		if panel == null or not panel.visible:
			return
		await get_tree().process_frame
	_errors.append("drive_capture timed out waiting for title card dismiss")


func _drive_and_capture() -> void:
	Input.action_press(&"throttle", 1.0)
	var elapsed_seconds: float = 0.0
	var shot_index: int = 0
	var lookback_done: bool = false
	while shot_index < _shot_times_seconds.size() and elapsed_seconds < _duration_seconds:
		await get_tree().process_frame
		var dt: float = get_process_delta_time()
		elapsed_seconds += dt
		_apply_steering(elapsed_seconds)
		while shot_index < _shot_times_seconds.size() and elapsed_seconds >= _shot_times_seconds[shot_index]:
			var shot_time: float = _shot_times_seconds[shot_index]
			await _capture_chase(shot_time)
			if shot_index == _lookback_index and not lookback_done:
				await _capture_lookback(shot_time)
				lookback_done = true
			shot_index += 1


func _apply_steering(elapsed_seconds: float) -> void:
	# Mirror perf_autodrive's deterministic sin-wave steering so the driven path
	# matches what the perf harness measures; gentle enough to keep the car on
	# the trail while still varying the captured terrain.
	var steer_value: float = sin(elapsed_seconds / STEER_PERIOD_SECONDS * TAU) * STEER_STRENGTH
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


func _capture_chase(shot_time: float) -> void:
	_restore_chase_camera_current()
	await _flush_frame()
	var file_name: String = "drive_t%02d_chase.png" % [int(round(shot_time))]
	_capture_to(file_name)


func _capture_lookback(shot_time: float) -> void:
	_position_lookback_camera()
	if not _errors.is_empty():
		return
	await _flush_frame()
	var file_name: String = "drive_t%02d_lookback.png" % [int(round(shot_time))]
	_capture_to(file_name)


func _position_lookback_camera() -> void:
	var vehicle: Node = _vehicle()
	if vehicle == null:
		_errors.append("lookback capture: host Vehicle not found")
		return
	if _lookback_camera == null:
		_errors.append("lookback capture: " + CAPTURE_CAMERA_NAME + " missing")
		return
	var state: RefCounted = vehicle.call("get_state")
	if state == null:
		_errors.append("lookback capture: vehicle state unavailable")
		return
	var forward: Vector3 = -state.basis.z
	if forward.length_squared() < 1e-06:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	var pos: Vector3 = state.position
	_lookback_camera.global_position = pos + forward * LOOKBACK_FORWARD_OFFSET + Vector3.UP * LOOKBACK_HEIGHT
	_lookback_camera.look_at(pos - forward * LOOKBACK_TARGET_BACK, Vector3.UP)
	_lookback_camera.fov = CAPTURE_CAMERA_FOV
	_lookback_camera.far = GameConfig.cam_far
	_activate_lookback_camera()


func _activate_lookback_camera() -> void:
	_set_host_cameras_current(false)
	_lookback_camera.current = true
	_lookback_camera.make_current()


func _restore_chase_camera_current() -> void:
	if _lookback_camera != null:
		_lookback_camera.current = false
	_set_host_cameras_current(true)
	if _host == null:
		return
	var chase_camera: Camera3D = _host.get_node_or_null("ChaseCamera") as Camera3D
	if chase_camera != null:
		chase_camera.make_current()


func _set_host_cameras_current(is_current: bool) -> void:
	if _host == null:
		return
	var camera_names: Array[String] = ["ChaseCamera", "OrbitCamera", "FpvCamera"]
	for camera_name in camera_names:
		var camera: Camera3D = _host.get_node_or_null(camera_name) as Camera3D
		if camera != null:
			camera.current = is_current


func _flush_frame() -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw


func _capture_to(file_name: String) -> void:
	var viewport_texture: ViewportTexture = get_viewport().get_texture()
	if viewport_texture == null:
		_errors.append(file_name + ": no viewport texture")
		return
	var image: Image = viewport_texture.get_image()
	if image == null or image.is_empty():
		_errors.append(file_name + ": captured empty image")
		return
	if not _image_has_variance(image):
		_errors.append(file_name + ": captured near-blank image")
		return
	var path: String = _run_dir.path_join(file_name)
	var err: Error = image.save_png(path)
	if err != OK:
		_errors.append(file_name + ": save failed " + path + " error=" + str(err))
		return
	_capture_paths_written.append(path)


func _finish() -> void:
	_release_input()
	if _errors.size() > 0:
		for error in _errors:
			push_error(error)
			print("FAIL: " + error)
		_cleanup_host()
		await _wait_for_shutdown()
		get_tree().quit(FAIL_EXIT_CODE)
		return
	for path in _capture_paths_written:
		print("capture: " + ProjectSettings.globalize_path(path))
	print("ok: drive_capture wrote " + str(_capture_paths_written.size()) + " PNGs in " + ProjectSettings.globalize_path(_run_dir))
	_cleanup_host()
	await _wait_for_shutdown()
	get_tree().quit(0)


func _cleanup_host() -> void:
	if _host == null:
		return
	_host.queue_free()
	_host = null


func _wait_for_shutdown() -> void:
	for _i in range(SHUTDOWN_FRAMES):
		await get_tree().process_frame


func _wait_frames(count: int) -> void:
	for _i in range(count):
		await get_tree().process_frame


func _visual_streamer() -> Node:
	if _host == null:
		return null
	return _host.get_node_or_null("CedarHollow/TerrainVisualStreamer")


func _vehicle() -> Node:
	if _host == null:
		return null
	if GameManager.active_vehicle != null:
		return GameManager.active_vehicle
	return _host.get_node_or_null("Vehicle")


func _absolute_path(path: String) -> String:
	if path.is_absolute_path():
		return path
	return ProjectSettings.globalize_path("res://" + path)


func _image_has_variance(image: Image) -> bool:
	var width: int = image.get_width()
	var height: int = image.get_height()
	if width <= 0 or height <= 0:
		return false
	var min_luma: float = 999999.0
	var max_luma: float = -999999.0
	for y in range(0, height, VARIANCE_SAMPLE_STEP):
		for x in range(0, width, VARIANCE_SAMPLE_STEP):
			var color: Color = image.get_pixel(x, y)
			var luma: float = color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722
			min_luma = minf(min_luma, luma)
			max_luma = maxf(max_luma, luma)
	return max_luma - min_luma >= MIN_LUMA_VARIANCE
