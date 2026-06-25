extends Node

# Diagnosis capture — a render-only visual-diagnosis tool for the orchestrator.
#
# Problem it solves: normal/movie captures stall on the title card (the reveal gate needs real-time
# _process accumulation), and a plain frame can't tell you WHICH system drew a pixel (terrain? foliage?
# scatter?). This tool:
#   1. FORCE-REVEALS by dropping the cold-start title hold to ~0.1s (no title-card stall).
#   2. Waits for full streaming at each scenic waypoint (no void), then captures the viewport PNG.
#   3. With --recolor, flat-UNSHADED-colors every render instance BY SOURCE SYSTEM, so the captured
#      frame is a legend you can read: terrain-detail=GREEN, mid-LOD=CYAN, stream-HLOD=BLUE,
#      foliage-cell=YELLOW, scatter/other-MultiMesh=RED, water=MAGENTA, props/other=GREY.
#
# RENDER/HOST-ONLY. Touches nothing in the sim; asserts nothing about goldens. Args:
#   --out-dir=<dir>  --label=<str>  --recolor
const PlayableScene: PackedScene = preload("res://scenes/cedar_hollow_playable.tscn")
const TerrainBuilderScript: GDScript = preload("res://systems/world/terrain_builder.gd")
const TerrainVisualBuilderScript: GDScript = preload("res://systems/render/terrain_visual_builder.gd")

const DEFAULT_OUT_DIR: String = "tests/out/diag"
const WINDOW_SIZE: Vector2i = Vector2i(1280, 720)
const STREAM_WAIT_FRAMES: int = 2400
const SETTLE_FRAMES: int = 130
const SURFACE_LIFT_M: float = 1.0
const FORCED_TITLE_HOLD_SECONDS: float = 0.1

# Scenic waypoints (XZ) along the spawn corridor; a few spread points for coverage.
const WAYPOINTS_XZ: Array[Vector2] = [
	Vector2(1550.0, 1550.0),
	Vector2(1410.0, 1450.0),
	Vector2(1180.0, 1350.0),
	Vector2(1070.0, 1200.0),
	Vector2(920.0, 900.0),
]

const COLOR_DETAIL: Color = Color(0.15, 0.85, 0.20)    # terrain detail tiles
const COLOR_MIDLOD: Color = Color(0.15, 0.85, 0.85)    # terrain mid-LOD
const COLOR_HLOD: Color = Color(0.20, 0.35, 0.95)      # terrain stream-HLOD (far backdrop)
const COLOR_FOLIAGE: Color = Color(0.95, 0.90, 0.15)   # foliage-cell MultiMeshes
const COLOR_SCATTER: Color = Color(0.95, 0.20, 0.20)   # scatter / other MultiMeshes
const COLOR_WATER: Color = Color(0.90, 0.20, 0.90)     # water
const COLOR_OTHER: Color = Color(0.55, 0.55, 0.55)     # props / unknown

var _host: Node = null
var _out_dir: String = DEFAULT_OUT_DIR
var _label: String = "diag"
var _recolor: bool = false
var _custom_waypoints: Array[Vector2] = []
var _look_at: Vector2 = Vector2.ZERO
var _look_at_set: bool = false


func _ready() -> void:
	DisplayServer.window_set_size(WINDOW_SIZE)
	_parse_args()
	# Force the cold-start reveal so we never capture the title card.
	GameConfig.title_card_max_hold_seconds = FORCED_TITLE_HOLD_SECONDS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://" + _out_dir))
	_host = PlayableScene.instantiate()
	add_child(_host)
	call_deferred("_run")


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		var text: String = String(arg)
		if text.begins_with("--out-dir="):
			_out_dir = text.trim_prefix("--out-dir=")
		elif text.begins_with("--label="):
			_label = text.trim_prefix("--label=")
		elif text == "--recolor":
			_recolor = true
		elif text.begins_with("--waypoints="):
			for pair in text.trim_prefix("--waypoints=").split(";", false):
				var xz: PackedStringArray = pair.split(",", false)
				if xz.size() == 2:
					_custom_waypoints.append(Vector2(xz[0].to_float(), xz[1].to_float()))
		elif text.begins_with("--look-at="):
			var pt: PackedStringArray = text.trim_prefix("--look-at=").split(",", false)
			if pt.size() == 2:
				_look_at = Vector2(pt[0].to_float(), pt[1].to_float())
				_look_at_set = true


func _run() -> void:
	if _host == null:
		push_error("diagnosis_capture: failed to instantiate playable scene")
		get_tree().quit(1)
		return
	var terrain_def: Resource = TerrainBuilderScript.cedar_hollow_10m_terrain_def()
	var off: Vector2 = TerrainBuilderScript.cedar_hollow_10m_horizontal_offset()
	var waypoints: Array[Vector2] = _custom_waypoints if not _custom_waypoints.is_empty() else WAYPOINTS_XZ
	for i in waypoints.size():
		var wp: Vector2 = waypoints[i]
		var yaw_deg: float
		if _look_at_set:
			var ldir: Vector2 = _look_at - wp
			yaw_deg = 160.0 if ldir.length() < 0.01 else rad_to_deg(atan2(ldir.x, ldir.y)) + 180.0
		else:
			var next: Vector2 = waypoints[mini(i + 1, waypoints.size() - 1)]
			var dir: Vector2 = next - wp
			yaw_deg = 160.0 if dir.length() < 0.01 else rad_to_deg(atan2(dir.x, dir.y)) + 180.0
		var bed_y: float = TerrainBuilderScript.heightmap_height_at_world_xz(terrain_def, wp, off)
		var pos: Vector3 = Vector3(wp.x, bed_y + SURFACE_LIFT_M, wp.y)
		_reset_vehicle(pos, yaw_deg)
		await _wait_for_streaming()
		for _s in SETTLE_FRAMES:
			await get_tree().process_frame
		if _recolor:
			_recolor_by_source(_host)
		if _host.has_method("_update_camera"):
			_host.call("_update_camera", GameConfig.FIXED_DT)
		await _capture("%s_%02d" % [_label, i])
	get_tree().quit()


func _reset_vehicle(position: Vector3, yaw_degrees: float) -> void:
	var vehicle: Node = _host.get_node_or_null("Vehicle")
	if vehicle == null:
		push_error("diagnosis_capture: host missing Vehicle")
		return
	var transform: Transform3D = Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_degrees)), position)
	vehicle.call("reset_to", transform)
	_host.set("_chase_camera_initialized", false)


func _wait_for_streaming() -> void:
	var streamer: Node = _host.get_node_or_null("CedarHollow/TerrainVisualStreamer")
	if streamer == null:
		return
	for _i in STREAM_WAIT_FRAMES:
		await get_tree().physics_frame
		await get_tree().process_frame
		var vis: int = int(streamer.call("visual_cell_count"))
		var fol: int = int(streamer.call("foliage_cell_count"))
		var mid: int = int(streamer.call("midlod_cell_count"))
		var pend_c: int = int(streamer.call("pending_midlod_commit_count"))
		var pend_b: int = int(streamer.call("pending_midlod_build_count"))
		if vis > 0 and fol > 0 and mid > 0 and pend_c == 0 and pend_b == 0:
			return


func _recolor_by_source(root: Node) -> void:
	for child in root.get_children():
		if child is GeometryInstance3D:
			var color: Color = _source_color(child)
			var material: StandardMaterial3D = StandardMaterial3D.new()
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			material.albedo_color = color
			(child as GeometryInstance3D).material_override = material
		_recolor_by_source(child)


func _source_color(node: Node) -> Color:
	# Classify by the nearest named ancestor / node-name convention, then by instance type.
	var cursor: Node = node
	while cursor != null:
		var node_name: String = String(cursor.name)
		if node_name == TerrainVisualBuilderScript.REGION_DETAIL_ROOT_NAME:
			return COLOR_DETAIL
		if node_name == TerrainVisualBuilderScript.REGION_STREAM_MIDLOD_ROOT_NAME:
			return COLOR_MIDLOD
		if node_name == TerrainVisualBuilderScript.REGION_HLOD_NAME or node_name.begins_with(TerrainVisualBuilderScript.REGION_HLOD_TILE_NAME_PREFIX):
			return COLOR_HLOD
		if node_name == TerrainVisualBuilderScript.REGION_STREAMED_FOLIAGE_ROOT_NAME or node_name == TerrainVisualBuilderScript.REGION_FOLIAGE_ROOT_NAME:
			return COLOR_FOLIAGE
		if node_name.findn("water") != -1 or node_name.findn("river") != -1:
			return COLOR_WATER
		cursor = cursor.get_parent()
	# Not under a known terrain/foliage/water root: a MultiMesh here is scatter; else generic.
	if node is MultiMeshInstance3D:
		return COLOR_SCATTER
	return COLOR_OTHER


func _capture(image_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	if image == null:
		return
	var path: String = "res://" + _out_dir + "/" + image_name + ".png"
	image.save_png(path)
	print("capture: ", ProjectSettings.globalize_path(path))
