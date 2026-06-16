extends Node

const SimRunnerScene: PackedScene = preload("res://scenes/sim_runner.tscn")
const TerrainVisualStreamerScript: GDScript = preload("res://systems/render/terrain_visual_streamer.gd")

const DEFAULT_WINDOW_SIZE: Vector2i = Vector2i(640, 360)
const DEFAULT_CAMERA_POSITION: Vector3 = Vector3(250.0, 90.0, 160.0)
const DEFAULT_CAMERA_TARGET: Vector3 = Vector3(250.0, 0.0, 250.0)

var _render_region_id: String = ""
var _visual_streamer: Node3D = null
var _reported_visual_activation: bool = false


func _ready() -> void:
	_parse_args()
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_size(DEFAULT_WINDOW_SIZE)
	_setup_render_shell()
	_setup_sim_runner()


func _exit_tree() -> void:
	if _visual_streamer != null:
		_visual_streamer.call("reset_stream")


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		var text: String = String(arg)
		if text.begins_with("--render-region="):
			_render_region_id = text.trim_prefix("--render-region=")


func _setup_render_shell() -> void:
	_setup_camera()
	_setup_light()
	_setup_environment()
	if _render_region_id.is_empty():
		return
	_visual_streamer = TerrainVisualStreamerScript.new() as Node3D
	if _visual_streamer == null:
		push_error("RenderNonFeedbackRunner failed to instantiate TerrainVisualStreamer")
		return
	_visual_streamer.name = "RenderTileStreamer"
	add_child(_visual_streamer)
	_visual_streamer.call("configure_region", _render_region_id)
	if not EventBus.world_tile_activated.is_connected(_on_world_tile_activated):
		EventBus.world_tile_activated.connect(_on_world_tile_activated)
	print("render_non_feedback_runner: visual streamer region=" + _render_region_id)


func _setup_camera() -> void:
	var camera: Camera3D = Camera3D.new()
	camera.name = "RenderNonFeedbackCamera"
	camera.current = true
	camera.fov = GameConfig.cam_fov_base
	camera.far = maxf(GameConfig.orbit_cam_far, 500.0)
	camera.look_at_from_position(DEFAULT_CAMERA_POSITION, DEFAULT_CAMERA_TARGET, Vector3.UP)
	add_child(camera)


func _setup_light() -> void:
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.name = "RenderNonFeedbackSun"
	sun.rotation_degrees = GameConfig.dusk_sun_rotation_degrees
	sun.light_energy = GameConfig.dusk_sun_energy
	sun.light_color = GameConfig.dusk_sun_color
	add_child(sun)


func _setup_environment() -> void:
	var world_environment: WorldEnvironment = WorldEnvironment.new()
	world_environment.name = "RenderNonFeedbackEnvironment"
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = GameConfig.dusk_background_color
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = GameConfig.dusk_ambient_color
	environment.ambient_light_energy = GameConfig.dusk_ambient_energy
	world_environment.environment = environment
	add_child(world_environment)


func _setup_sim_runner() -> void:
	var runner: Node = SimRunnerScene.instantiate()
	if runner == null:
		push_error("RenderNonFeedbackRunner failed to instantiate SimRunner")
		get_tree().quit(2)
		return
	runner.name = "SimRunner"
	add_child(runner)


func _on_world_tile_activated(cell: Vector2i) -> void:
	if _reported_visual_activation or _visual_streamer == null:
		return
	var visual_count: int = int(_visual_streamer.call("visual_cell_count"))
	if visual_count <= 0:
		return
	_reported_visual_activation = true
	print("render_non_feedback_runner: visual tiles active=" + str(visual_count) + " first_cell=" + str(cell))
