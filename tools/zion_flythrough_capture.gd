extends Node

# Streaming-aware corridor flythrough: steps the vehicle along scenic waypoints, waits for
# FULL terrain streaming at each, captures a chase-cam frame. Frames -> ffmpeg video offline.
# Movie-maker mode (--write-movie) cannot be used: it decouples the fixed-step sim from the
# async streaming workers, so the car outruns the streamed world into a void. This waits.
# Render-only; writes PNGs; asserts nothing about goldens.
const CedarHollowPlayableScene: PackedScene = preload("res://scenes/cedar_hollow_playable.tscn")
const TerrainBuilderScript: GDScript = preload("res://systems/world/terrain_builder.gd")
const DEFAULT_OUT_DIR: String = "tests/out/zion_flythrough"
const WINDOW_SIZE: Vector2i = Vector2i(1280, 720)
const STREAM_WAIT_FRAMES: int = 3600
const SETTLE_FRAMES: int = 80
const SURFACE_LIFT_M: float = 1.0
const CAMERA_MODE_CHASE: int = 0

# Scenic river-corridor waypoints (XZ) along ZION_RIVER_THALWEG, spawn-end first.
const WAYPOINTS_XZ: Array[Vector2] = [
	Vector2(1550.0, 1550.0),
	Vector2(1500.0, 1550.0),
	Vector2(1410.0, 1450.0),
	Vector2(1330.0, 1400.0),
	Vector2(1180.0, 1350.0),
	Vector2(1130.0, 1300.0),
	Vector2(1070.0, 1200.0),
	Vector2(1000.0, 1000.0),
	Vector2(920.0, 900.0),
]

var _host: Node = null
var _out_dir: String = DEFAULT_OUT_DIR
var _label: String = "fly"


func _ready() -> void:
	DisplayServer.window_set_size(WINDOW_SIZE)
	_parse_args()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://" + _out_dir))
	_host = CedarHollowPlayableScene.instantiate()
	add_child(_host)
	call_deferred("_run")


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		var text: String = String(arg)
		if text.begins_with("--out-dir="):
			_out_dir = text.trim_prefix("--out-dir=")
		elif text.begins_with("--label="):
			_label = text.trim_prefix("--label=")


func _run() -> void:
	if _host == null:
		push_error("zion_flythrough: failed to instantiate playable scene")
		get_tree().quit(1)
		return
	_host.set("_camera_mode", CAMERA_MODE_CHASE)
	var terrain_def: Resource = TerrainBuilderScript.cedar_hollow_10m_terrain_def()
	var off: Vector2 = TerrainBuilderScript.cedar_hollow_10m_horizontal_offset()
	for i: int in WAYPOINTS_XZ.size():
		var wp: Vector2 = WAYPOINTS_XZ[i]
		var next: Vector2 = WAYPOINTS_XZ[mini(i + 1, WAYPOINTS_XZ.size() - 1)]
		var dir: Vector2 = next - wp
		var yaw_deg: float = 160.0 if dir.length() < 0.01 else rad_to_deg(atan2(dir.x, dir.y)) + 180.0
		var bed_y: float = TerrainBuilderScript.heightmap_height_at_world_xz(terrain_def, wp, off)
		var pos: Vector3 = Vector3(wp.x, bed_y + SURFACE_LIFT_M, wp.y)
		_reset_vehicle(pos, yaw_deg)
		await _wait_for_streaming()
		for _s: int in SETTLE_FRAMES:
			await get_tree().process_frame
		if _host.has_method("_update_camera"):
			_host.call("_update_camera", GameConfig.FIXED_DT)
		await _capture("%s_%02d" % [_label, i])
	get_tree().quit()


func _reset_vehicle(position: Vector3, yaw_degrees: float) -> void:
	var vehicle: Node = _host.get_node_or_null("Vehicle")
	if vehicle == null:
		push_error("zion_flythrough: host missing Vehicle")
		return
	var transform: Transform3D = Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_degrees)), position)
	vehicle.call("reset_to", transform)
	_host.set("_chase_camera_initialized", false)


func _wait_for_streaming() -> void:
	var streamer: Node = _host.get_node_or_null("CedarHollow/TerrainVisualStreamer")
	if streamer == null:
		return
	for _i: int in STREAM_WAIT_FRAMES:
		await get_tree().physics_frame
		await get_tree().process_frame
		var vis: int = int(streamer.call("visual_cell_count"))
		var fol: int = int(streamer.call("foliage_cell_count"))
		var mid: int = int(streamer.call("midlod_cell_count"))
		var pend_c: int = int(streamer.call("pending_midlod_commit_count"))
		var pend_b: int = int(streamer.call("pending_midlod_build_count"))
		if vis > 0 and fol > 0 and mid > 0 and pend_c == 0 and pend_b == 0:
			return


func _capture(image_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	if image == null:
		return
	var path: String = "res://" + _out_dir + "/" + image_name + ".png"
	image.save_png(path)
	print("capture: ", ProjectSettings.globalize_path(path))
