extends Node

# Throwaway verification tool: render the REAL demo spawn (demo_canyon_junction) from the
# chase cam after FULL streaming (mid-LOD queues drained), to confirm the Zion-fidelity wave
# renders the lush valley floor + striated walls at the POV the owner actually drives.
# Render-only; writes a PNG, asserts nothing about goldens.
const CedarHollowPlayableScene: PackedScene = preload("res://scenes/cedar_hollow_playable.tscn")
const DEFAULT_OUT_DIR: String = "tests/out/zion_fidelity_wave"
const WINDOW_SIZE: Vector2i = Vector2i(1280, 720)
const STREAM_WAIT_FRAMES: int = 3600
const SETTLE_FRAMES: int = 120
const DEMO_SPAWN_POSITION: Vector3 = Vector3(1550.0, 1203.597964, 1550.0)
const DEMO_SPAWN_YAW_DEGREES: float = 160.0
const CAMERA_MODE_CHASE: int = 0

var _host: Node = null
var _out_dir: String = DEFAULT_OUT_DIR
var _label: String = "spawn"


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
		push_error("zion_spawn_preview: failed to instantiate playable scene")
		get_tree().quit(1)
		return
	_reset_vehicle()
	_host.set("_camera_mode", CAMERA_MODE_CHASE)
	_host.set("_chase_camera_initialized", false)
	if _host.has_method("_update_camera"):
		_host.call("_update_camera", GameConfig.FIXED_DT)
	await _wait_for_streaming()
	for _i in SETTLE_FRAMES:
		await get_tree().process_frame
	if _host.has_method("_update_camera"):
		_host.call("_update_camera", GameConfig.FIXED_DT)
	await _capture(_label + "_demo_canyon_junction_chase")
	get_tree().quit()


func _reset_vehicle() -> void:
	var vehicle: Node = _host.get_node_or_null("Vehicle")
	if vehicle == null:
		push_error("zion_spawn_preview: host missing Vehicle")
		return
	var transform: Transform3D = Transform3D(Basis(Vector3.UP, deg_to_rad(DEMO_SPAWN_YAW_DEGREES)), DEMO_SPAWN_POSITION)
	vehicle.call("reset_to", transform)


func _wait_for_streaming() -> void:
	var streamer: Node = _host.get_node_or_null("CedarHollow/TerrainVisualStreamer")
	if streamer == null:
		push_error("zion_spawn_preview: missing TerrainVisualStreamer")
		return
	for _i in STREAM_WAIT_FRAMES:
		await get_tree().physics_frame
		await get_tree().process_frame
		var vis: int = int(streamer.call("visual_cell_count"))
		var fol: int = int(streamer.call("foliage_cell_count"))
		var mid: int = int(streamer.call("midlod_cell_count"))
		var pend_commit: int = int(streamer.call("pending_midlod_commit_count"))
		var pend_build: int = int(streamer.call("pending_midlod_build_count"))
		if vis > 0 and fol > 0 and mid > 0 and pend_commit == 0 and pend_build == 0:
			return
	push_error("zion_spawn_preview: timed out waiting for full streaming")


func _capture(image_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	if image == null:
		push_error("zion_spawn_preview: null viewport image")
		return
	var path: String = "res://" + _out_dir + "/" + image_name + ".png"
	image.save_png(path)
	print("capture: ", ProjectSettings.globalize_path(path))
