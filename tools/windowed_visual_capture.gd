extends Node

const CedarHollowPlayableScene: PackedScene = preload("res://scenes/cedar_hollow_playable.tscn")
const DEFAULT_OUT_DIR: String = "tests/out/visual_qa"
const WINDOW_SIZE: Vector2i = Vector2i(1280, 720)
const WAIT_FRAMES: int = 8
const SHUTDOWN_FRAMES: int = 8
const VARIANCE_SAMPLE_STEP: int = 32
const MIN_LUMA_VARIANCE: float = 0.05
const CAMERA_MODE_CHASE: int = 0
const CAMERA_MODE_ORBIT: int = 1
const CAMERA_MODE_FPV: int = 2
const MOOD_DUSK: int = 0
const MOOD_DAWN: int = 1

var _host: Node = null
var _out_dir: String = DEFAULT_OUT_DIR
var _errors: PackedStringArray = PackedStringArray()
var _captures_written: PackedStringArray = PackedStringArray()


func _ready() -> void:
	_parse_args()
	DisplayServer.window_set_size(WINDOW_SIZE)
	_prepare_output_dir()
	_host = CedarHollowPlayableScene.instantiate()
	add_child(_host)
	call_deferred("_run")


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		var text: String = String(arg)
		if text.begins_with("--out-dir="):
			_out_dir = text.trim_prefix("--out-dir=")


func _prepare_output_dir() -> void:
	var absolute_dir: String = ProjectSettings.globalize_path("res://" + _out_dir)
	var err: Error = DirAccess.make_dir_recursive_absolute(absolute_dir)
	if err != OK:
		_errors.append("failed to create visual capture output dir: " + absolute_dir + " error=" + str(err))


func _run() -> void:
	if _host == null:
		_errors.append("failed to instantiate Cedar Hollow playable scene")
		await _finish()
		return
	_reset_vehicle(Vector3(0.0, 0.12, 0.75), 0.0)
	_set_mood(MOOD_DUSK)
	_set_camera_mode(CAMERA_MODE_CHASE)
	await _wait_for_render()
	_capture("trailhead_dusk_chase")
	_host.call("toggle_landmark_hint_hud")
	await _wait_for_render()
	_capture("trailhead_dusk_chase_map")
	_host.call("toggle_landmark_hint_hud")
	_reset_vehicle(Vector3(1.45, 0.12, -2.8), 205.0)
	_set_mood(MOOD_DUSK)
	_set_camera_mode(CAMERA_MODE_CHASE)
	await _wait_for_render()
	_capture("meadow_dusk_chase")
	_set_camera_mode(CAMERA_MODE_ORBIT)
	await _wait_for_render()
	_capture("meadow_dusk_orbit")
	_reset_vehicle(Vector3(2.85, 0.12, -5.3), 30.0)
	_set_camera_mode(CAMERA_MODE_CHASE)
	await _wait_for_render()
	_capture("bog_bottom_dusk_chase")
	_reset_vehicle(Vector3(4.25, 0.12, -6.55), -70.0)
	_set_mood(MOOD_DAWN)
	_set_camera_mode(CAMERA_MODE_CHASE)
	await _wait_for_render()
	_capture("crossing_dawn_chase")
	_set_mood(MOOD_DUSK)
	_reset_vehicle(Vector3(3.25, 0.12, -4.15), 180.0)
	_set_camera_mode(CAMERA_MODE_CHASE)
	await _wait_for_render()
	_capture("boardwalk_dusk_chase")
	_set_camera_mode(CAMERA_MODE_FPV)
	await _wait_for_render()
	_capture("boardwalk_dusk_fpv")
	_reset_vehicle(Vector3(-2.1, 0.45, -8.9), 245.0)
	_set_camera_mode(CAMERA_MODE_ORBIT)
	await _wait_for_render()
	_capture("overlook_dusk_orbit")
	_reset_vehicle(Vector3(0.0, 0.12, -4.45), 0.0)
	_set_camera_mode(CAMERA_MODE_CHASE)
	await _wait_for_render()
	_capture("old_cedar_dusk_chase")
	await _finish()


func _wait_for_render() -> void:
	for _i in range(WAIT_FRAMES):
		await get_tree().process_frame


func _reset_vehicle(position: Vector3, yaw_degrees: float) -> void:
	if _host == null:
		return
	var vehicle: Node = _host.get_node_or_null("Vehicle")
	if vehicle == null:
		_errors.append("capture host is missing Vehicle")
		return
	var transform: Transform3D = Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_degrees)), position)
	vehicle.call("reset_to", transform)
	_host.set("_chase_camera_initialized", false)
	_host.set("_orbit_camera_initialized", false)
	_host.set("_orbit_yaw_degrees", GameConfig.orbit_cam_start_yaw_deg)
	_host.call("_update_camera", GameConfig.FIXED_DT)


func _set_camera_mode(mode: int) -> void:
	if _host == null:
		return
	_host.set("_camera_mode", mode)
	_host.call("_update_camera", GameConfig.FIXED_DT)


func _set_mood(mood: int) -> void:
	if _host == null:
		return
	_host.set("_mood", mood)
	_host.call("_apply_mood")


func _capture(capture_name: String) -> void:
	var viewport_texture: ViewportTexture = get_viewport().get_texture()
	if viewport_texture == null:
		_errors.append(capture_name + " has no viewport texture")
		return
	var image: Image = viewport_texture.get_image()
	if image == null or image.is_empty():
		_errors.append(capture_name + " captured an empty image")
		return
	if not _image_has_variance(image):
		_errors.append(capture_name + " captured a near-blank image")
		return
	var path: String = "res://" + _out_dir + "/" + capture_name + ".png"
	var err: Error = image.save_png(path)
	if err != OK:
		_errors.append(capture_name + " failed to save " + path + " error=" + str(err))
		return
	_captures_written.append(ProjectSettings.globalize_path(path))


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


func _finish() -> void:
	if _errors.size() > 0:
		for error in _errors:
			push_error(error)
		_cleanup_host()
		await _wait_for_shutdown()
		get_tree().quit(1)
		return
	for path in _captures_written:
		print("capture: " + path)
	print("ok: windowed visual captures wrote " + str(_captures_written.size()) + " files")
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
