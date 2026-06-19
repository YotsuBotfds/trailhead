extends Node

const CedarHollowPlayableScene: PackedScene = preload("res://scenes/cedar_hollow_playable.tscn")
const DEFAULT_OUT_DIR: String = "tests/out/zion_visual_qa"
const WINDOW_SIZE: Vector2i = Vector2i(1280, 720)
const STREAM_WAIT_FRAMES: int = 1800
const RENDER_WAIT_FRAMES: int = 40
const SHUTDOWN_FRAMES: int = 8
const VARIANCE_SAMPLE_STEP: int = 32
const MIN_LUMA_VARIANCE: float = 0.015
const BACKGROUND_DELTA_THRESHOLD: float = 0.045
const MIN_OFF_CENTER_WORLD_SAMPLES: int = 12
const MIN_VISTA_CAMERA_FAR_M: float = 1200.0
const CAPTURE_CAMERA_FOV: float = 62.0
const CAPTURE_CAMERA_NAME: String = "ZionCaptureCamera"
const CAMERA_MODE_CHASE: int = 0
const CAMERA_MODE_ORBIT: int = 1
const MOOD_DUSK: int = 0
const MOOD_DAWN: int = 1
const EXPECTED_STREAMED_CELLS: int = 25
const LABELED_OUT_DIR: String = "tests/out/zion_fidelity_wave"
const EXPECTED_CAPTURE_NAMES: Array[String] = [
	"zion_stream_west_dusk_chase",
	"zion_stream_west_dusk_orbit",
	"zion_seam_dusk_chase",
	"zion_stream_east_dawn_orbit",
]

var _host: Node = null
var _out_dir: String = DEFAULT_OUT_DIR
var _capture_label: String = ""
var _errors: PackedStringArray = PackedStringArray()
var _capture_paths_written: PackedStringArray = PackedStringArray()
var _capture_names_written: Array[String] = []
var _capture_camera: Camera3D = null
var _capture_camera_active: bool = false
var _custom_out_dir: bool = false


func _ready() -> void:
	_parse_args()
	DisplayServer.window_set_size(WINDOW_SIZE)
	_prepare_output_dir()
	_host = CedarHollowPlayableScene.instantiate()
	add_child(_host)
	_setup_capture_camera()
	call_deferred("_run")


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		var text: String = String(arg)
		if text.begins_with("--out-dir="):
			_out_dir = text.trim_prefix("--out-dir=")
			_custom_out_dir = true
		elif text.begins_with("--label="):
			_capture_label = text.trim_prefix("--label=")
	if not _custom_out_dir and not _capture_label.is_empty():
		_out_dir = LABELED_OUT_DIR


func _prepare_output_dir() -> void:
	var absolute_dir: String = _absolute_out_dir()
	var err: Error = DirAccess.make_dir_recursive_absolute(absolute_dir)
	if err != OK:
		_errors.append("failed to create Zion visual capture output dir: " + absolute_dir + " error=" + str(err))
		return
	var dir: DirAccess = DirAccess.open(absolute_dir)
	if dir == null:
		_errors.append("failed to open Zion visual capture output dir: " + absolute_dir)
		return
	for capture_name in EXPECTED_CAPTURE_NAMES:
		var file_name: String = _capture_file_basename(capture_name) + ".png"
		if dir.file_exists(file_name):
			var remove_err: Error = dir.remove(file_name)
			if remove_err != OK:
				_errors.append("failed to remove stale Zion visual capture: " + absolute_dir.path_join(file_name) + " error=" + str(remove_err))


func _setup_capture_camera() -> void:
	_capture_camera = Camera3D.new()
	_capture_camera.name = CAPTURE_CAMERA_NAME
	_capture_camera.current = false
	_capture_camera.fov = CAPTURE_CAMERA_FOV
	_capture_camera.far = GameConfig.cam_far
	if _host != null:
		_host.add_child(_capture_camera)
	else:
		add_child(_capture_camera)


func _run() -> void:
	if _host == null:
		_errors.append("failed to instantiate Zion playable scene")
		await _finish()
		return
	_set_mood(MOOD_DUSK)
	_reset_vehicle(Vector3(1150.0, 1197.56, 800.0), -90.0)
	_disable_capture_camera()
	_set_camera_mode(CAMERA_MODE_CHASE)
	await _wait_for_streaming()
	await _wait_for_render()
	await _capture_checked("zion_stream_west_dusk_chase")
	_use_scenic_capture_camera(180.0, 42.0, 14.0, Vector3(0.0, -2.0, 38.0))
	await _capture_checked("zion_stream_west_dusk_orbit")
	_reset_vehicle(Vector3(1200.0, 1197.79, 800.0), -90.0)
	_disable_capture_camera()
	_set_camera_mode(CAMERA_MODE_CHASE)
	await _wait_for_streaming()
	await _wait_for_render()
	await _capture_checked("zion_seam_dusk_chase")
	_reset_vehicle(Vector3(1250.0, 1198.71, 850.0), -90.0)
	_disable_capture_camera()
	_set_mood(MOOD_DAWN)
	await _wait_for_streaming()
	await _wait_for_render()
	_use_scenic_capture_camera(0.0, 48.0, 16.0, Vector3(0.0, -2.0, -38.0))
	await _capture_checked("zion_stream_east_dawn_orbit")
	_verify_capture_set()
	await _finish()


func _wait_for_streaming() -> void:
	for _i in range(STREAM_WAIT_FRAMES):
		if _streaming_ready():
			return
		await get_tree().physics_frame
		await get_tree().process_frame
	_errors.append("Zion visual capture timed out waiting for streamed cells")


func _streaming_ready() -> bool:
	var streamer: Node = _host.get_node_or_null("CedarHollow/TerrainVisualStreamer") if _host != null else null
	if streamer == null:
		return false
	if int(streamer.call("visual_cell_count")) != EXPECTED_STREAMED_CELLS:
		return false
	if int(streamer.call("foliage_cell_count")) != EXPECTED_STREAMED_CELLS:
		return false
	if int(streamer.call("pending_midlod_build_count")) != 0:
		return false
	if int(streamer.call("pending_midlod_commit_count")) != 0:
		return false
	if int(streamer.call("ready_midlod_cell_count")) != 0:
		return false
	var desired_midlod_count: int = int(streamer.call("desired_midlod_cell_count"))
	if desired_midlod_count <= 0:
		return false
	if int(streamer.call("midlod_cell_count")) != desired_midlod_count:
		return false
	return true


func _wait_for_render() -> void:
	for _i in range(RENDER_WAIT_FRAMES):
		await get_tree().process_frame


func _reset_vehicle(position: Vector3, yaw_degrees: float) -> void:
	if _host == null:
		return
	var vehicle: Node = _host.get_node_or_null("Vehicle")
	if vehicle == null:
		_errors.append("Zion visual capture host is missing Vehicle")
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


func _use_scenic_capture_camera(yaw_degrees: float, distance: float, height: float, target_offset: Vector3) -> void:
	if _host == null:
		return
	var vehicle: Node = _host.get_node_or_null("Vehicle")
	if vehicle == null:
		_errors.append("Zion visual capture host is missing Vehicle")
		return
	if _capture_camera == null:
		_errors.append("Zion visual capture host is missing " + CAPTURE_CAMERA_NAME)
		return
	var state: RefCounted = vehicle.call("get_state")
	var vehicle_position: Vector3 = state.get("position")
	var yaw_radians: float = deg_to_rad(yaw_degrees)
	var target: Vector3 = vehicle_position + target_offset
	var offset: Vector3 = Vector3(sin(yaw_radians), 0.0, cos(yaw_radians)) * distance
	_capture_camera.global_position = target + offset + Vector3.UP * height
	_capture_camera.look_at(target, Vector3.UP)
	_capture_camera.fov = CAPTURE_CAMERA_FOV
	_capture_camera.far = GameConfig.cam_far
	_capture_camera_active = true
	_activate_capture_camera()


func _disable_capture_camera() -> void:
	_capture_camera_active = false
	if _capture_camera != null:
		_capture_camera.current = false


func _activate_capture_camera() -> void:
	if _capture_camera == null:
		_errors.append("Zion visual capture host is missing " + CAPTURE_CAMERA_NAME)
		return
	_set_host_cameras_current(false)
	_capture_camera.current = true
	_capture_camera.make_current()


func _set_host_cameras_current(is_current: bool) -> void:
	if _host == null:
		return
	var camera_names: Array[String] = ["ChaseCamera", "OrbitCamera", "FpvCamera"]
	for camera_name in camera_names:
		var camera: Camera3D = _host.get_node_or_null(camera_name) as Camera3D
		if camera != null:
			camera.current = is_current


func _set_mood(mood: int) -> void:
	if _host == null:
		return
	_host.set("_mood", mood)
	_host.call("_apply_mood")


func _capture_checked(capture_name: String) -> void:
	await _flush_current_camera_frame(capture_name)
	_require_visible_streamed_terrain(capture_name)
	_capture(capture_name)


func _flush_current_camera_frame(capture_name: String) -> void:
	await get_tree().process_frame
	var camera: Camera3D = _current_camera()
	if camera == null:
		_errors.append(capture_name + " has no current camera to flush")
		return
	if _capture_camera_active:
		_activate_capture_camera()
	else:
		camera.make_current()
	await RenderingServer.frame_post_draw


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
	if not _image_has_off_center_world_coverage(image):
		_errors.append(capture_name + " captured no off-center streamed world coverage")
		return
	var path: String = _capture_file_path(capture_name)
	var err: Error = image.save_png(path)
	if err != OK:
		_errors.append(capture_name + " failed to save " + path + " error=" + str(err))
		return
	_capture_paths_written.append(ProjectSettings.globalize_path(path))
	_capture_names_written.append(capture_name)


func _require_visible_streamed_terrain(capture_name: String) -> void:
	var camera: Camera3D = _current_camera()
	if camera == null:
		_errors.append(capture_name + " has no current camera")
		return
	if camera.far < MIN_VISTA_CAMERA_FAR_M:
		_errors.append(capture_name + " current camera far plane should be vista-forward, got " + str(camera.far))
		return
	var streamer: Node = _host.get_node_or_null("CedarHollow/TerrainVisualStreamer") if _host != null else null
	if streamer == null:
		_errors.append(capture_name + " is missing TerrainVisualStreamer")
		return
	var active_cells: Variant = streamer.call("active_visual_cells")
	if not active_cells is Array:
		_errors.append(capture_name + " could not read active streamed terrain cells")
		return
	for cell_value in active_cells:
		if not cell_value is Vector2i:
			continue
		var cell: Vector2i = cell_value
		var tile: MeshInstance3D = streamer.call("visual_cell_node", cell) as MeshInstance3D
		if tile == null or tile.mesh == null:
			continue
		if _aabb_has_camera_visible_point(camera, tile.global_transform * tile.mesh.get_aabb()):
			return
	_errors.append(capture_name + " has no streamed terrain tile point inside the current camera frustum")


func _current_camera() -> Camera3D:
	if _capture_camera_active:
		return _capture_camera
	if _capture_camera != null and _capture_camera.current:
		return _capture_camera
	if _host == null:
		return null
	var camera_names: Array[String] = ["ChaseCamera", "OrbitCamera", "FpvCamera"]
	for camera_name in camera_names:
		var camera: Camera3D = _host.get_node_or_null(camera_name) as Camera3D
		if camera != null and camera.current:
			return camera
	return null


func _aabb_has_camera_visible_point(camera: Camera3D, aabb: AABB) -> bool:
	var min_point: Vector3 = aabb.position
	var max_point: Vector3 = aabb.position + aabb.size
	var points: Array[Vector3] = [
		aabb.get_center(),
		Vector3(min_point.x, min_point.y, min_point.z),
		Vector3(max_point.x, min_point.y, min_point.z),
		Vector3(min_point.x, max_point.y, min_point.z),
		Vector3(max_point.x, max_point.y, min_point.z),
		Vector3(min_point.x, min_point.y, max_point.z),
		Vector3(max_point.x, min_point.y, max_point.z),
		Vector3(min_point.x, max_point.y, max_point.z),
		Vector3(max_point.x, max_point.y, max_point.z),
	]
	for point in points:
		if camera.is_position_in_frustum(point):
			return true
	return false


func _verify_capture_set() -> void:
	for expected_name in EXPECTED_CAPTURE_NAMES:
		if not _capture_names_written.has(expected_name):
			_errors.append("missing expected Zion visual capture: " + expected_name + ".png")
	if _capture_names_written.size() != EXPECTED_CAPTURE_NAMES.size():
		_errors.append("expected " + str(EXPECTED_CAPTURE_NAMES.size()) + " Zion visual captures, wrote " + str(_capture_names_written.size()))
	var absolute_dir: String = _absolute_out_dir()
	var dir: DirAccess = DirAccess.open(absolute_dir)
	if dir == null:
		_errors.append("failed to inspect Zion visual capture output dir: " + absolute_dir)
		return
	var expected_file_basenames: Array[String] = _expected_capture_file_basenames()
	dir.list_dir_begin()
	while true:
		var file_name: String = dir.get_next()
		if file_name == "":
			break
		if dir.current_is_dir():
			continue
		if file_name.get_extension().to_lower() != "png":
			continue
		var capture_name: String = file_name.get_basename()
		if not expected_file_basenames.has(capture_name):
			_errors.append("unexpected Zion visual capture PNG in output dir: " + absolute_dir.path_join(file_name))
	dir.list_dir_end()
	_verify_capture_hashes_distinct()


func _verify_capture_hashes_distinct() -> void:
	var capture_names_by_md5: Dictionary[String, String] = {}
	for capture_name in EXPECTED_CAPTURE_NAMES:
		var path: String = _capture_file_path(capture_name)
		if not FileAccess.file_exists(path):
			continue
		var md5: String = FileAccess.get_md5(path)
		if md5.is_empty():
			_errors.append("failed to hash Zion visual capture PNG: " + path)
			continue
		if capture_names_by_md5.has(md5):
			var first_capture_name: String = capture_names_by_md5[md5]
			_errors.append("Zion visual captures must be byte-distinct, but " + first_capture_name + ".png and " + capture_name + ".png share MD5 " + md5)
			continue
		capture_names_by_md5[md5] = capture_name


func _absolute_out_dir() -> String:
	if _out_dir.is_absolute_path():
		return _out_dir
	return ProjectSettings.globalize_path("res://" + _out_dir)


func _capture_file_path(capture_name: String) -> String:
	var file_name: String = _capture_file_basename(capture_name) + ".png"
	if _out_dir.is_absolute_path():
		return _out_dir.path_join(file_name)
	return ("res://" + _out_dir).path_join(file_name)


func _capture_file_basename(capture_name: String) -> String:
	if _capture_label.is_empty():
		return capture_name
	return _capture_label + "_" + capture_name


func _expected_capture_file_basenames() -> Array[String]:
	var basenames: Array[String] = []
	for capture_name in EXPECTED_CAPTURE_NAMES:
		basenames.append(_capture_file_basename(capture_name))
	return basenames


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


func _image_has_off_center_world_coverage(image: Image) -> bool:
	var width: int = image.get_width()
	var height: int = image.get_height()
	if width <= 0 or height <= 0:
		return false
	var background: Color = _average_corner_color(image)
	var sample_count: int = 0
	for y in range(0, height, VARIANCE_SAMPLE_STEP):
		for x in range(0, width, VARIANCE_SAMPLE_STEP):
			if _inside_vehicle_focus_box(x, y, width, height):
				continue
			if _color_delta(image.get_pixel(x, y), background) > BACKGROUND_DELTA_THRESHOLD:
				sample_count += 1
	return sample_count >= MIN_OFF_CENTER_WORLD_SAMPLES


func _average_corner_color(image: Image) -> Color:
	var width: int = image.get_width()
	var height: int = image.get_height()
	var corners: Array[Color] = [
		image.get_pixel(0, 0),
		image.get_pixel(width - 1, 0),
		image.get_pixel(0, height - 1),
		image.get_pixel(width - 1, height - 1),
	]
	var total: Color = Color(0.0, 0.0, 0.0, 0.0)
	for color in corners:
		total += color
	return total / float(corners.size())


func _inside_vehicle_focus_box(x: int, y: int, width: int, height: int) -> bool:
	var min_x: int = int(float(width) * 0.30)
	var max_x: int = int(float(width) * 0.70)
	var min_y: int = int(float(height) * 0.30)
	var max_y: int = int(float(height) * 0.76)
	return x >= min_x and x <= max_x and y >= min_y and y <= max_y


func _color_delta(a: Color, b: Color) -> float:
	var dr: float = a.r - b.r
	var dg: float = a.g - b.g
	var db: float = a.b - b.b
	return sqrt(dr * dr + dg * dg + db * db)


func _finish() -> void:
	if _errors.size() > 0:
		for error in _errors:
			push_error(error)
		_cleanup_host()
		await _wait_for_shutdown()
		get_tree().quit(1)
		return
	for path in _capture_paths_written:
		print("capture: " + path)
	print("ok: Zion windowed visual captures wrote exact set of " + str(_capture_paths_written.size()) + " files")
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
