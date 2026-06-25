class_name CedarHollowHost
extends Node3D

const CedarRoute: Resource = preload("res://data/routes/cedar_hollow_zion_stream_route.tres")
const CEDAR_TERRAIN_DEF_PATH: String = "res://data/terrain/cedar_hollow_zion_terrain_def.tres"
const CedarTerrainDef: Resource = preload("res://data/terrain/cedar_hollow_zion_terrain_def.tres")
const VehicleScene: PackedScene = preload("res://scenes/vehicle.tscn")
const VehicleInputScript: GDScript = preload("res://systems/vehicle/vehicle_input.gd")
const ChaseCameraRigScript: GDScript = preload("res://systems/render/chase_camera_rig.gd")
const ChaseCameraMath: GDScript = preload("res://systems/render/chase_camera_math.gd")
const TerrainVisualBuilderScript: GDScript = preload("res://systems/render/terrain_visual_builder.gd")
const TerrainVisualStreamerScript: GDScript = preload("res://systems/render/terrain_visual_streamer.gd")
const WaterVisualBuilderScript: GDScript = preload("res://systems/render/water_visual_builder.gd")
const AtmosphereVisualBuilderScript: GDScript = preload("res://systems/render/atmosphere_visual_builder.gd")
const DustTiltShiftVisualBuilderScript: GDScript = preload("res://systems/render/dust_tilt_shift_visual_builder.gd")
const ProceduralBuggyVisualScript: GDScript = preload("res://systems/render/procedural_buggy_visual.gd")
const RenderRuntimeConfigScript: GDScript = preload("res://systems/render/render_runtime_config.gd")
const NightStarSkyShader: Shader = preload("res://systems/render/night_star_sky.gdshader")
const DuskGoldenSkyShader: Shader = preload("res://systems/render/dusk_golden_sky.gdshader")
const VehicleResidueVisualScript: GDScript = preload("res://systems/render/vehicle_residue_visual.gd")
const VehicleJuiceRigScript: GDScript = preload("res://systems/render/vehicle_juice_rig.gd")
const CedarAudioRigScript: GDScript = preload("res://systems/render/cedar_audio_rig.gd")
const LandmarkHintHudScript: GDScript = preload("res://systems/render/landmark_hint_hud.gd")
const SpeedHudScript: GDScript = preload("res://systems/render/speed_hud.gd")
const ControlsHintHudScript: GDScript = preload("res://systems/render/controls_hint_hud.gd")
const DebugOverlayHudScript: GDScript = preload("res://systems/render/debug_overlay_hud.gd")
const PhotographSystemScript: GDScript = preload("res://systems/render/photograph_system.gd")
const RecoverableObjectRenderScript: GDScript = preload("res://systems/render/recoverable_object_render.gd")
const GoldenLineTrackerScript: GDScript = preload("res://systems/sim/golden_line_tracker.gd")
const GoldenLineGhostScript: GDScript = preload("res://systems/render/golden_line_ghost.gd")
const TerrainTrackVisualPainterScript: GDScript = preload("res://systems/render/terrain_track_visual_painter.gd")
const FrequencyInputPanelScene: PackedScene = preload("res://ui/frequency_input_panel.tscn")
const GrasshopperLiveryScript: GDScript = preload("res://systems/render/grasshopper_livery.gd")
const SurfaceMapScript: GDScript = preload("res://systems/world/surface_map.gd")
const TerrainBuilderScript: GDScript = preload("res://systems/world/terrain_builder.gd")
const DesertPropBuilderScript: GDScript = preload("res://systems/render/desert_prop_builder.gd")
const GrassShader: Shader = preload("res://systems/render/grass_billboard.gdshader")
const CAMERA_MODE_CHASE: int = 0
const CAMERA_MODE_ORBIT: int = 1
const CAMERA_MODE_FPV: int = 2
const MOOD_DUSK: int = 0
const MOOD_DAWN: int = 1
const MOOD_NIGHT: int = 2
const ZION_DUSK_FOG_DENSITY: float = 0.0009
const ZION_DAWN_FOG_DENSITY: float = 0.0014
const ZION_NIGHT_FOG_DENSITY: float = 0.0016
const ZION_FOG_AERIAL_PERSPECTIVE: float = 0.05
const ZION_FOG_SKY_AFFECT: float = 0.10  # was 0.28 — high sky-affect dissolved distant mesas into the bright sky (bible: mesas read as silhouettes)
const ZION_VOLUMETRIC_FOG_SKY_AFFECT: float = 0.11
const ZION_NIGHT_FOG_SKY_AFFECT: float = 0.18
# Dusk golden-hour sky (zionfid/sky). The dusk PhysicalSkyMaterial was a plain
# two-stop gradient; this ShaderMaterial sky adds a soft cyan mid band, a sun
# disk + aureole at the real GoldenHourSun direction, and subtle cirrus streaks.
# Zenith/horizon/ground reuse the existing GameConfig dusk_sky_* values so the
# blue zenith + de-orange direction are preserved (sky drives ambient via
# AMBIENT_SOURCE_BG, so the warm color stays confined to a thin horizon band).
const DUSK_GOLDEN_MID_COLOR: Color = Color(0.32, 0.55, 0.72)
const DUSK_GOLDEN_SUN_COLOR: Color = Color(1.00, 0.80, 0.52)
const DUSK_GOLDEN_CIRRUS_COLOR: Color = Color(0.82, 0.78, 0.72)
const DUSK_GOLDEN_SUN_HALO_STRENGTH: float = 0.38
const DUSK_GOLDEN_HORIZON_BAND_WIDTH: float = 0.26  # tighter warm band (was 0.34); keeps blue dome dominant above, warm glow confined near horizon
const DUSK_GOLDEN_CIRRUS_COVERAGE: float = 0.62
const DUSK_GOLDEN_CIRRUS_INTENSITY: float = 0.16
const DUSK_GOLDEN_ENERGY_MULTIPLIER: float = 1.08  # vivid dusk sky (was 1.00); brightens the dome to read like a glowing Zion evening
const ZION_SHADOW_ATLAS_SIZE: int = 8192
const ZION_REGION_ID: String = "cedar_hollow_zion"
# Demo/initial vehicle spawn for the playable scene. Resolved to a Transform3D via
# CedarRoute.spawn_transform at _spawn_vehicle / _setup_terrain_tracks (and mirrored by
# tools/zion_playable_inspector.gd, which reads THIS constant to assert wherever the demo
# opens). zion_wall_vista faces east into the striated canyon walls from the flat floor at
# the wall base (terrain Y ~1209) so the demo opens on the scenic red-rock vista rather than
# the open western floor. Headless no-fall fixtures pin their own --spawn ids explicitly via
# the sim runner and are intentionally NOT coupled to this demo default.
const ZION_SPAWN_ID: StringName = &"zion_wall_vista"
const DEMO_PROPS_ROOT_NAME: StringName = &"DemoProps"
const DEMO_PROP_GROUND_Y_OFFSET: float = 0.02
const DEMO_PROP_VISTA_ANCHOR_XZ: Vector2 = Vector2(1900.0, 1650.0)
const WORLD_REGION_ID_META: StringName = &"trailhead_world_region_id"
const GAMEPAD_DEVICE_ANY: int = -1
const TRACK_APPLY_CELLS_PER_FRAME: int = 1
const PERF_LOG_USER_ARG: String = "--perf-log"
const PERF_LOG_DEFAULT_DIR: String = "user://trailhead/perf"
const PERF_LOG_FLUSH_ROW_COUNT: int = 120
const PERF_LOG_HEADER: String = "frame,dt_ms,fps,process_ms,physics_process_ms,viewport_cpu_ms,viewport_gpu_ms,scaling_3d_scale,scaling_3d_scale_changed,dynamic_res_target_ms,draw_calls,primitives,objects,video_mem_mb,static_mem_mb,current_cell,active_cells,ready_cells,stream_tick,crossing_flag,hitch_flag,hitch_at_crossing,window_is_focused"
const PERF_LOG_CROSSING_WINDOW_FRAMES: int = 5
const PERF_LOG_MEDIAN_WINDOW_SIZE: int = 121
const PERF_LOG_HITCH_MEDIAN_MULTIPLIER: float = 2.0
const PERF_LOG_HITCH_THRESHOLD_MS: float = 20.0
const PERF_LOG_DYNAMIC_RESOLUTION_CONTROLLER_NAME: String = "RenderDynamicResolutionController"
const PERF_LOG_DYNAMIC_RESOLUTION_TARGET_FRAME_MS_META: StringName = &"trailhead_dynamic_resolution_target_frame_ms"
const PERF_LOG_SCALE_CHANGE_EPSILON: float = 0.0001
const PERF_LOG_MB_DIVISOR: float = 1024.0 * 1024.0

var _world: Node3D = null
var _vehicle: Node = null
var _vehicle_input: RefCounted = VehicleInputScript.new()
var _camera: Camera3D = null
var _orbit_camera: Camera3D = null
var _fpv_camera: Camera3D = null
var _cinematic_camera: Camera3D = null
var _wheel_sockets: Array[Node3D] = []
var _vehicle_visual_root: Node = null
var _vehicle_residue_visual: RefCounted = VehicleResidueVisualScript.new()
var _wheel_spin: float = 0.0
var _visual_body_pitch: float = 0.0
var _visual_body_roll: float = 0.0
var _visual_body_pitch_velocity: float = 0.0
var _visual_body_roll_velocity: float = 0.0
var _visual_antenna_pitch: float = 0.0
var _visual_antenna_roll: float = 0.0
var _visual_antenna_pitch_velocity: float = 0.0
var _visual_antenna_roll_velocity: float = 0.0
var _visual_last_velocity: Vector3 = Vector3.ZERO
var _visual_last_velocity_valid: bool = false
var _grass_crush_materials: Array[ShaderMaterial] = []
var _grass_crush_collect_tick: int = 0
const GRASS_CRUSH_RECOLLECT_INTERVAL: int = 12
var _camera_mode: int = CAMERA_MODE_CHASE
var _photo_mode_active: bool = false
var _photo_mode_previous_camera_mode: int = CAMERA_MODE_CHASE
var _photo_mode_previous_speed_hud_visible: bool = false
var _photo_mode_previous_controls_hint_visible: bool = false
var _cinematic_tour_active: bool = false
var _cinematic_tour_elapsed: float = 0.0
var _cinematic_tour_previous_camera_mode: int = CAMERA_MODE_CHASE
var _cinematic_tour_previous_landmark_hud_visible: bool = false
var _cinematic_tour_previous_speed_hud_visible: bool = false
var _cinematic_tour_previous_controls_hint_visible: bool = false
var _cinematic_tour_previous_title_hud_visible: bool = false
var _chase_camera_rig: RefCounted = ChaseCameraRigScript.new()
var _chase_camera_initialized: bool = false
var _chase_look_target_current: Vector3 = Vector3.ZERO
var _chase_back_current: Vector3 = Vector3.ZERO
var _chase_up_current: Vector3 = Vector3.UP
var _chase_vehicle_y_current: float = 0.0
var _chase_bank_current_deg: float = 0.0
var _chase_pitch_current_deg: float = 0.0
var _chase_stop_locked: bool = false
var _chase_last_velocity: Vector3 = Vector3.ZERO
var _chase_last_velocity_valid: bool = false
var _orbit_camera_initialized: bool = false
var _orbit_vehicle_y_current: float = 0.0
var _orbit_yaw_degrees: float = 0.0
var _fpv_camera_initialized: bool = false
var _fpv_vehicle_y_current: float = 0.0
var _fpv_back_current: Vector3 = Vector3.ZERO
var _fpv_up_current: Vector3 = Vector3.UP
var _landmark_hint_hud: CanvasLayer = null
var _speed_hud: CanvasLayer = null
var _controls_hint_hud: CanvasLayer = null
var _debug_overlay_hud: CanvasLayer = null
var _title_card_hud: CanvasLayer = null
var _world_environment: WorldEnvironment = null
var _sun: DirectionalLight3D = null
var _mood: int = MOOD_DUSK
var _terrain_track_painter: Node = null
var _terrain_visual_streamer: Node3D = null
var _photograph_system: Node = null
var _recoverable_object_render: Node = null
var _golden_line_tracker: Node = null
var _golden_line_ghost: Node = null
var _sim_tick: int = 0
var _frequency_input_panel: CanvasLayer = null
var _grasshopper_livery: Node = null
var _drive_started: bool = false
var _track_texture_state_valid: bool = false
var _track_last_texture: Texture2D = null
var _track_last_bounds_min: Vector2 = Vector2.ZERO
var _track_last_bounds_max: Vector2 = Vector2.ZERO
var _track_apply_queue: Array[Vector2i] = []
var _track_apply_queue_lookup: Dictionary[Vector2i, bool] = {}
var _track_applied_cells: Dictionary[Vector2i, bool] = {}
# Cached snapshot of the active visual cell set from the last frame we actually
# ran the overlay sync/drain. Drives the change gate in
# _apply_terrain_tracks_to_streamed_tiles: when the streamer's active cells,
# the track RT's texture/bounds, and the apply queue are all unchanged, the
# per-frame re-apply is skipped (visually identical — see the gate comment).
var _track_last_active_cells: Dictionary[Vector2i, bool] = {}
var _cold_start_streaming_released: bool = false
var _cold_start_hold_elapsed: float = 0.0
var _audio_rig: Node = null
var _fps_cap_enabled: bool = true
var _perf_log_active: bool = false
var _perf_log_finalized: bool = false
var _perf_log_absolute_path: String = ""
var _perf_log_file: FileAccess = null
var _perf_log_rows: PackedStringArray = PackedStringArray()
var _perf_log_frame_index: int = 0
var _perf_log_last_usec: int = 0
var _perf_log_last_cell: Vector2i = Vector2i.ZERO
var _perf_log_has_last_cell: bool = false
var _perf_log_last_crossing_frame: int = -1000000
var _perf_log_last_scaling_3d_scale: float = 1.0
var _perf_log_has_last_scaling_3d_scale: bool = false
var _perf_log_dt_samples_ms: Array[float] = []


func _ready() -> void:
	RenderRuntimeConfigScript.apply_to(self)
	_sync_fps_cap_state_from_runtime()
	_apply_render_quality()
	_setup_perf_logging()
	_ensure_default_input_map()
	_setup_surface_map()
	_setup_world()
	_setup_demo_props()
	_spawn_vehicle()
	_report_render_subsystem_health()
	_setup_audio()
	_setup_recoverable_object_render()
	_setup_golden_line_systems()
	_setup_environment()
	_setup_light()
	_setup_camera()
	_setup_vehicle_juice()
	AtmosphereVisualBuilderScript.configure_render_support(self, _vehicle, _camera, _orbit_camera, _fpv_camera)
	_setup_photograph_system()
	_setup_hud()
	_setup_frequency_input_panel()
	if GameConfig.cinematic_auto_open:
		_enter_cinematic_tour()


func _apply_render_quality() -> void:
	# Render-only 3D scaling + temporal AA (GLM perf-opt). Pushes the
	# GameConfig-driven mode/scale/TAA to the game viewport once in _ready().
	# NOTE: project.godot's rendering/scaling_3d/mode=2 is NOT inherited by the
	# runtime viewport (it reads as mode=0/bilinear), so this explicit apply is
	# what actually selects the scaler. Default is FSR1 (spatial): on Apple
	# Silicon FSR2's temporal pass costs ~5-6 ms/frame at equal scale and falls
	# below the 45 fps floor, while FSR1 ties bilinear for cost and sharpens the
	# 0.85 upscale for free. Render-only: never touches sim/collision/determinism.
	# Inert under the headless DisplayServer (no GPU), matching RenderRuntimeConfig's
	# headless guard; headless inspectors read ProjectSettings + the atmosphere
	# builder's use_taa, so they stay green. RenderDynamicResolutionController
	# (installed just above via apply_to) rides on top and re-pins scaling_3d_scale
	# to its min/max band each frame.
	if DisplayServer.get_name() == &"headless":
		return
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return
	viewport.scaling_3d_mode = GameConfig.render_scaling_3d_mode
	viewport.scaling_3d_scale = GameConfig.render_scaling_3d_scale
	viewport.use_taa = GameConfig.render_use_taa


func _exit_tree() -> void:
	_finalize_perf_log()
	var streamer: Node = get_node_or_null("/root/TileStreamer")
	if streamer != null:
		streamer.call("reset")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_finalize_perf_log()


func _physics_process(delta: float) -> void:
	if _vehicle == null:
		return
	_update_vehicle_input()
	_update_cinematic_tour_input()
	_update_photo_mode_input()
	_update_camera_input()
	_update_hud_input()
	_update_perf_input()
	_update_frequency_input()
	_update_mood_input()
	_vehicle.call("apply_input", _vehicle_input)
	_sample_golden_line()
	_update_visual_wheels(delta)
	_update_terrain_tracks()
	if _runtime_camera_updates_enabled():
		_update_camera(delta)


func _process(delta: float) -> void:
	_update_cold_start_streaming_gate(delta)
	_sample_perf_log_frame()
	if _terrain_track_painter == null:
		return
	_apply_terrain_tracks_to_streamed_tiles()


func _unhandled_input(event: InputEvent) -> void:
	# Render/window-only fullscreen toggle. The action is bound to F11 AND
	# backslash in project.godot (backslash is a fallback for macOS Mission
	# Control grabbing F11). Uses WINDOW_MODE_FULLSCREEN (borderless fullscreen
	# in Godot 4.x) rather than EXCLUSIVE_FULLSCREEN -- borderless avoids the
	# display-mode switch flicker and stays at the desktop resolution. DisplayServer
	# is window-side only; this whole path is inert under the headless DisplayServer
	# and never touches sim/physics/deterministic state.
	if event.is_action_pressed(&"toggle_fullscreen"):
		_toggle_fullscreen()


func _toggle_fullscreen() -> void:
	if DisplayServer.get_name() == &"headless":
		return
	var mode: DisplayServer.WindowMode = DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _sync_fps_cap_state_from_runtime() -> void:
	_fps_cap_enabled = GameConfig.render_frame_cap_enabled and Engine.max_fps > 0


func _update_perf_input() -> void:
	if Input.is_action_just_pressed(&"toggle_fps_cap"):
		_toggle_fps_cap()


func _toggle_fps_cap() -> void:
	_fps_cap_enabled = not _fps_cap_enabled
	_apply_fps_cap_state()


func _apply_fps_cap_state() -> void:
	if not _windowed_rendering_enabled():
		return
	if _fps_cap_enabled:
		var target_max_fps: int = GameConfig.render_max_fps
		Engine.max_fps = target_max_fps
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
		print("perf: fps cap ON - " + str(target_max_fps) + ", vsync on")
	else:
		Engine.max_fps = 0
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		print("perf: fps cap OFF - uncapped, vsync off")


func _windowed_rendering_enabled() -> bool:
	return DisplayServer.get_name() != &"headless"


func _ensure_default_input_map() -> void:
	_ensure_action(&"throttle", [KEY_W, KEY_UP])
	_ensure_action(&"brake", [KEY_S, KEY_DOWN])
	_ensure_action(&"reverse", [KEY_S, KEY_DOWN])
	_ensure_action(&"steer_left", [KEY_A, KEY_LEFT])
	_ensure_action(&"steer_right", [KEY_D, KEY_RIGHT])
	_ensure_action(&"ebrake", [KEY_SPACE])
	_ensure_action(&"self_right", [KEY_R])
	_ensure_action(&"cam_toggle", [KEY_C])
	_ensure_action(&"map_toggle", [KEY_M])
	_ensure_action(&"mood_toggle", [KEY_N])
	_ensure_action(&"logbook_open", [KEY_TAB])
	_ensure_action(&"frequency_input", [KEY_P])
	_ensure_action(&"photograph", [KEY_F])
	_ensure_action(&"photo_mode", [KEY_V])
	_ensure_action(&"cinematic_tour", [KEY_T])
	_ensure_action(&"debug_overlay", [KEY_F3])
	_ensure_action(&"toggle_fps_cap", [KEY_F2])
	_ensure_action(&"toggle_fullscreen", [KEY_F11, KEY_BACKSLASH])
	_ensure_joypad_bindings()


func _ensure_action(action_name: StringName, keycodes: Array[int]) -> void:
	var action_string: String = String(action_name)
	if not InputMap.has_action(action_string):
		InputMap.add_action(action_string, 0.2)
	if InputMap.action_get_events(action_string).size() > 0:
		return
	for keycode in keycodes:
		var event: InputEventKey = InputEventKey.new()
		event.physical_keycode = keycode
		InputMap.action_add_event(action_string, event)


func _ensure_joypad_bindings() -> void:
	# Standard Xbox-style gamepad map. Additive + idempotent: never removes
	# existing keyboard events and never duplicates a joypad event already present,
	# so this is safe to call whether or not project.godot already binds gamepads.
	# Triggers (analog 0..1): RIGHT = throttle, LEFT = brake + reverse. LEFT mirrors
	# keyboard S -- the read in _update_vehicle_input() treats LT as brake when
	# throttle is applied and as reverse when stopped, so one trigger covers both.
	_ensure_action_axis(&"throttle", JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_ensure_action_axis(&"brake", JOY_AXIS_TRIGGER_LEFT, 1.0)
	_ensure_action_axis(&"reverse", JOY_AXIS_TRIGGER_LEFT, 1.0)
	# Left stick X (analog -1..+1). Binding each half to its own steer action lets
	# the existing strength(steer_left) - strength(steer_right) read yield a smooth
	# analog -1..+1 steer with no host read-logic change.
	_ensure_action_axis(&"steer_left", JOY_AXIS_LEFT_X, -1.0)
	_ensure_action_axis(&"steer_right", JOY_AXIS_LEFT_X, 1.0)
	# Digital face/shoulder buttons.
	_ensure_action_button(&"ebrake", JOY_BUTTON_A)
	_ensure_action_button(&"self_right", JOY_BUTTON_Y)
	_ensure_action_button(&"cam_toggle", JOY_BUTTON_RIGHT_SHOULDER)
	_ensure_action_button(&"map_toggle", JOY_BUTTON_BACK)
	_ensure_action_button(&"mood_toggle", JOY_BUTTON_LEFT_SHOULDER)
	_ensure_action_button(&"cinematic_tour", JOY_BUTTON_B)
	_ensure_action_button(&"photo_mode", JOY_BUTTON_X)


func _ensure_action_axis(action_name: StringName, axis: int, axis_value: float) -> void:
	var action_string: String = String(action_name)
	if not InputMap.has_action(action_string):
		InputMap.add_action(action_string, 0.2)
	if _has_joypad_motion(action_string, axis, axis_value):
		return
	var event: InputEventJoypadMotion = InputEventJoypadMotion.new()
	event.device = GAMEPAD_DEVICE_ANY
	event.axis = axis
	event.axis_value = axis_value
	InputMap.action_add_event(action_string, event)


func _ensure_action_button(action_name: StringName, button_index: int) -> void:
	var action_string: String = String(action_name)
	if not InputMap.has_action(action_string):
		InputMap.add_action(action_string, 0.2)
	if _has_joypad_button(action_string, button_index):
		return
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.device = GAMEPAD_DEVICE_ANY
	event.button_index = button_index
	InputMap.action_add_event(action_string, event)


func _has_joypad_motion(action_string: String, axis: int, axis_value: float) -> bool:
	for event in InputMap.action_get_events(action_string):
		var motion: InputEventJoypadMotion = event as InputEventJoypadMotion
		if motion != null and motion.axis == axis and is_equal_approx(motion.axis_value, axis_value):
			return true
	return false


func _has_joypad_button(action_string: String, button_index: int) -> bool:
	for event in InputMap.action_get_events(action_string):
		var button: InputEventJoypadButton = event as InputEventJoypadButton
		if button != null and button.button_index == button_index:
			return true
	return false


func _setup_perf_logging() -> void:
	var requested: bool = false
	var requested_path: String = ""
	for arg in OS.get_cmdline_user_args():
		var text: String = String(arg)
		if text == PERF_LOG_USER_ARG:
			requested = true
			requested_path = ""
		elif text.begins_with(PERF_LOG_USER_ARG + "="):
			requested = true
			requested_path = text.trim_prefix(PERF_LOG_USER_ARG + "=")
	if not requested:
		return
	if not _windowed_rendering_enabled():
		print("perf: --perf-log ignored under headless DisplayServer")
		return
	_perf_log_absolute_path = _resolve_perf_log_absolute_path(requested_path)
	if _perf_log_absolute_path.is_empty():
		push_error("perf: failed to resolve CSV path")
		return
	if not _ensure_perf_log_directory(_perf_log_absolute_path):
		return
	_perf_log_file = FileAccess.open(_perf_log_absolute_path, FileAccess.WRITE)
	if _perf_log_file == null:
		push_error("perf: failed to open CSV: " + _perf_log_absolute_path)
		return
	_perf_log_file.store_line(PERF_LOG_HEADER)
	_perf_log_file.flush()
	_perf_log_active = true
	_perf_log_finalized = false
	_perf_log_last_usec = Time.get_ticks_usec()
	_enable_perf_log_render_time_measurement()
	print("perf: logging frames CSV to " + _perf_log_absolute_path)


func _resolve_perf_log_absolute_path(requested_path: String) -> String:
	if requested_path.is_empty():
		return _default_perf_log_absolute_path()
	if _is_absolute_perf_log_path(requested_path):
		return requested_path
	if requested_path.begins_with("user://") or requested_path.begins_with("res://"):
		return ProjectSettings.globalize_path(requested_path)
	return ProjectSettings.globalize_path(PERF_LOG_DEFAULT_DIR.path_join(requested_path))


func _default_perf_log_absolute_path() -> String:
	var base_dir: String = ProjectSettings.globalize_path(PERF_LOG_DEFAULT_DIR)
	var session_index: int = int(Time.get_unix_time_from_system())
	var path: String = base_dir.path_join("session-" + str(session_index) + ".csv")
	while FileAccess.file_exists(path):
		session_index += 1
		path = base_dir.path_join("session-" + str(session_index) + ".csv")
	return path


func _is_absolute_perf_log_path(path: String) -> bool:
	if path.is_absolute_path():
		return true
	if path.begins_with("\\\\"):
		return true
	if path.length() >= 3 and path.substr(1, 1) == ":":
		var separator: String = path.substr(2, 1)
		return separator == "/" or separator == "\\"
	return false


func _ensure_perf_log_directory(absolute_path: String) -> bool:
	var directory: String = absolute_path.get_base_dir()
	if directory.is_empty():
		return true
	var error: Error = DirAccess.make_dir_recursive_absolute(directory)
	if error != OK:
		push_error("perf: failed to create CSV directory: " + directory + " error=" + error_string(error))
		return false
	return true


func _enable_perf_log_render_time_measurement() -> void:
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return
	RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(), true)


func _sample_perf_log_frame() -> void:
	if not _perf_log_active or _perf_log_file == null:
		return
	var now_usec: int = Time.get_ticks_usec()
	if _perf_log_last_usec <= 0:
		_perf_log_last_usec = now_usec
		return
	var dt: float = maxf(float(now_usec - _perf_log_last_usec) / 1000000.0, 0.0)
	_perf_log_last_usec = now_usec
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return

	_perf_log_frame_index += 1
	var streamer: Node = _perf_log_tile_streamer()
	var current_cell: Vector2i = _perf_log_current_cell(streamer)
	var crossing_flag: bool = false
	if _perf_log_has_last_cell and current_cell != _perf_log_last_cell:
		crossing_flag = true
		_perf_log_last_crossing_frame = _perf_log_frame_index
	_perf_log_last_cell = current_cell
	_perf_log_has_last_cell = true

	var dt_ms: float = dt * 1000.0
	var fps: float = float(Engine.get_frames_per_second())
	var draw_calls: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var primitives: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var objects: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	var process_ms: float = float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0
	var physics_ms: float = float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0
	var viewport_rid: RID = viewport.get_viewport_rid()
	var viewport_cpu_ms: float = maxf(float(RenderingServer.viewport_get_measured_render_time_cpu(viewport_rid)), 0.0)
	var viewport_gpu_ms: float = maxf(float(RenderingServer.viewport_get_measured_render_time_gpu(viewport_rid)), 0.0)
	var scaling_3d_scale: float = viewport.scaling_3d_scale
	var scaling_3d_scale_changed: bool = _perf_log_scaling_3d_scale_changed(scaling_3d_scale)
	var dynamic_res_target_ms: float = _perf_log_dynamic_resolution_target_frame_ms()
	var video_mem_mb: float = float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / PERF_LOG_MB_DIVISOR
	var static_mem_mb: float = float(Performance.get_monitor(Performance.MEMORY_STATIC)) / PERF_LOG_MB_DIVISOR
	var active_count: int = _perf_log_active_cell_count(streamer)
	var ready_count: int = _perf_log_ready_cell_count(streamer)
	var stream_tick: int = _perf_log_stream_tick(streamer)
	var hitch_at_crossing: bool = _perf_log_frame_index - _perf_log_last_crossing_frame <= PERF_LOG_CROSSING_WINDOW_FRAMES
	var hitch_flag: bool = _perf_log_is_hitch(dt_ms)
	var window_focused: bool = DisplayServer.window_is_focused()
	_perf_log_dt_samples_ms.append(dt_ms)

	_perf_log_rows.append("%d,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.4f,%d,%.3f,%d,%d,%d,%.3f,%.3f,%s,%d,%d,%d,%d,%d,%d,%d" % [
		_perf_log_frame_index,
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
		_perf_log_cell_to_text(current_cell),
		active_count,
		ready_count,
		stream_tick,
		1 if crossing_flag else 0,
		1 if hitch_flag else 0,
		1 if hitch_at_crossing else 0,
		1 if window_focused else 0,
	])
	if _perf_log_rows.size() >= PERF_LOG_FLUSH_ROW_COUNT:
		_flush_perf_log_rows()


func _flush_perf_log_rows() -> void:
	if _perf_log_file == null or _perf_log_rows.is_empty():
		return
	for row in _perf_log_rows:
		_perf_log_file.store_line(row)
	_perf_log_rows.clear()
	_perf_log_file.flush()


func _finalize_perf_log() -> void:
	if _perf_log_finalized:
		return
	if not _perf_log_active and _perf_log_file == null:
		return
	_flush_perf_log_rows()
	if _perf_log_file != null:
		_perf_log_file.close()
		_perf_log_file = null
	_perf_log_active = false
	_perf_log_finalized = true
	if not _perf_log_absolute_path.is_empty():
		print("perf: frames CSV finalized at " + _perf_log_absolute_path)


func _perf_log_tile_streamer() -> Node:
	return get_node_or_null("/root/TileStreamer")


func _perf_log_current_cell(streamer: Node) -> Vector2i:
	if streamer != null and streamer.has_method("current_cell"):
		return streamer.call("current_cell")
	return Vector2i.ZERO


func _perf_log_active_cell_count(streamer: Node) -> int:
	if streamer != null and streamer.has_method("active_cells"):
		var cells: Array = streamer.call("active_cells")
		return cells.size()
	return 0


func _perf_log_ready_cell_count(streamer: Node) -> int:
	if streamer != null and streamer.has_method("ready_cells"):
		var cells: Array = streamer.call("ready_cells")
		return cells.size()
	return 0


func _perf_log_stream_tick(streamer: Node) -> int:
	if streamer != null and streamer.has_method("current_stream_tick"):
		return int(streamer.call("current_stream_tick"))
	return 0


func _perf_log_scaling_3d_scale_changed(scaling_3d_scale: float) -> bool:
	var changed: bool = false
	if _perf_log_has_last_scaling_3d_scale:
		changed = absf(scaling_3d_scale - _perf_log_last_scaling_3d_scale) > PERF_LOG_SCALE_CHANGE_EPSILON
	_perf_log_last_scaling_3d_scale = scaling_3d_scale
	_perf_log_has_last_scaling_3d_scale = true
	return changed


func _perf_log_dynamic_resolution_target_frame_ms() -> float:
	var controller: Node = get_node_or_null(NodePath(PERF_LOG_DYNAMIC_RESOLUTION_CONTROLLER_NAME))
	if controller != null and controller.has_meta(PERF_LOG_DYNAMIC_RESOLUTION_TARGET_FRAME_MS_META):
		return float(controller.get_meta(PERF_LOG_DYNAMIC_RESOLUTION_TARGET_FRAME_MS_META))
	if Engine.max_fps > 0:
		return 1000.0 / float(Engine.max_fps)
	return 0.0


func _perf_log_is_hitch(dt_ms: float) -> bool:
	if dt_ms <= PERF_LOG_HITCH_THRESHOLD_MS:
		return false
	var recent: Array[float] = []
	var start_index: int = maxi(_perf_log_dt_samples_ms.size() - PERF_LOG_MEDIAN_WINDOW_SIZE, 0)
	for i in range(start_index, _perf_log_dt_samples_ms.size()):
		recent.append(_perf_log_dt_samples_ms[i])
	if recent.size() < 3:
		return false
	return dt_ms > _perf_log_percentile(recent, 0.5) * PERF_LOG_HITCH_MEDIAN_MULTIPLIER


func _perf_log_percentile(values: Array[float], percentile: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted: Array[float] = values.duplicate()
	sorted.sort()
	var index: int = clampi(int(floorf(percentile * float(sorted.size() - 1))), 0, sorted.size() - 1)
	return sorted[index]


func _perf_log_cell_to_text(cell: Vector2i) -> String:
	return str(cell.x) + ":" + str(cell.y)


func _setup_surface_map() -> void:
	var surface_map: Node = SurfaceMapScript.new()
	surface_map.name = "SurfaceMap"
	add_child(surface_map)
	if not bool(surface_map.call("configure_terrain_def", CEDAR_TERRAIN_DEF_PATH)):
		push_error("CedarHollowHost failed to configure terrain surface map")


func _setup_world() -> void:
	_world = Node3D.new()
	_world.name = "CedarHollow"
	_world.set_meta(WORLD_REGION_ID_META, ZION_REGION_ID)
	add_child(_world)
	_terrain_visual_streamer = TerrainVisualStreamerScript.new() as Node3D
	if _terrain_visual_streamer == null:
		push_error("CedarHollowHost failed to instantiate TerrainVisualStreamer")
		return
	_terrain_visual_streamer.name = "TerrainVisualStreamer"
	_world.add_child(_terrain_visual_streamer)
	# Pay the ~44 MB surface-index Texture2DArray realization + shared terrain
	# ShaderMaterial build HERE in _ready (before the drive) so the first live terrain
	# commit is a pure cache hit. configure_region's pipeline-warmup mesh binds the same
	# cached material right after, so nothing is rebuilt. Render-only; inert effect on the
	# sim. (Cold-start boot-freeze fix — kept ahead of configure_region so the cache is
	# warm before the first tile activation enqueues a build.)
	TerrainVisualBuilderScript.prewarm_surface_index_pipeline()
	_terrain_visual_streamer.call("configure_region", ZION_REGION_ID)
	_setup_terrain_tracks(_terrain_visual_streamer)
	WaterVisualBuilderScript.build_zion_virgin_river(_world)


func _setup_terrain_tracks(terrain_root: Node3D) -> void:
	if terrain_root == null or not GameConfig.terrain_track_painter_enabled:
		return
	_terrain_track_painter = TerrainTrackVisualPainterScript.new() as Node
	if _terrain_track_painter == null:
		return
	_terrain_track_painter.name = "TerrainTrackVisualPainter"
	_world.add_child(_terrain_track_painter)
	var spawn_transform: Transform3D = CedarRoute.call("spawn_transform", ZION_SPAWN_ID)
	var spawn_xz: Vector2 = Vector2(spawn_transform.origin.x, spawn_transform.origin.z)
	_terrain_track_painter.call("configure", spawn_xz, spawn_xz)
	var track_texture: Texture2D = _terrain_track_painter.call("track_texture") as Texture2D
	var track_bounds_min: Vector2 = _terrain_track_painter.call("render_bounds_min")
	var track_bounds_max: Vector2 = _terrain_track_painter.call("render_bounds_max")
	_remember_track_texture_state(track_texture, track_bounds_min, track_bounds_max)


func _setup_demo_props() -> void:
	# Static, render-only hero-prop dressing (Q67): a small hand-placed cluster of real
	# prop GLBs near the demo spawn and along the drivable corridor toward the Virgin
	# River confluence, so the streamed Zion world reads as an inhabited trail rather
	# than empty desert. Deterministic + cheap (no streaming, no collision); built once
	# here. Y is sampled from the same heightfield the water visual uses, so each prop
	# sits ON the ground instead of floating or buried. DemoProps is intentionally NOT a
	# strip-only root name (see zion_playable_inspector STRIP_ONLY_ROOTS) and carries no
	# CollisionObject3D/CollisionShape3D, so the playable inspector stays green.
	if _world == null:
		return
	var root: Node3D = Node3D.new()
	root.name = String(DEMO_PROPS_ROOT_NAME)
	_world.add_child(root)
	# Trailhead rest-stop cluster at zion_wall_vista. Offsets are relative to the
	# vista anchor so the dressing can be tuned or moved back as one reversible set.
	_place_demo_prop_offset(root, DesertPropBuilderScript.PROP_TRAILHEAD_SIGN, Vector2(-12.0, -18.0), 210.0, 11)
	_place_demo_prop_offset(root, DesertPropBuilderScript.PROP_PICNIC_TABLE, Vector2(10.0, -4.0), 25.0, 0)
	_place_demo_prop_offset(root, DesertPropBuilderScript.PROP_FIRE_RING, Vector2(24.0, -20.0), 0.0, 0)
	# Scenic pullout dressing along the new east Virgin River thalweg.
	_place_demo_prop_offset(root, DesertPropBuilderScript.PROP_PARK_BENCH, Vector2(-28.0, 18.0), 250.0, 0)
	_place_demo_prop_offset(root, DesertPropBuilderScript.PROP_MARKER_POST, Vector2(-82.0, -12.0), 90.0, 7)
	_place_demo_prop_offset(root, DesertPropBuilderScript.PROP_TRAILHEAD_SIGN, Vector2(-145.0, -22.0), 275.0, 23)
	_place_demo_prop_offset(root, DesertPropBuilderScript.PROP_PARK_BENCH, Vector2(-205.0, -28.0), 35.0, 0)
	_place_demo_prop_offset(root, DesertPropBuilderScript.PROP_FIRE_RING, Vector2(-282.0, -40.0), 175.0, 0)


func _place_demo_prop_offset(parent: Node3D, prop_id: StringName, offset_xz: Vector2, yaw_degrees: float, seed: int) -> void:
	var world_xz: Vector2 = DEMO_PROP_VISTA_ANCHOR_XZ + offset_xz
	_place_demo_prop(parent, prop_id, world_xz.x, world_xz.y, yaw_degrees, seed)


func _place_demo_prop(parent: Node3D, prop_id: StringName, world_x: float, world_z: float, yaw_degrees: float, seed: int) -> void:
	var ground_y: float = TerrainBuilderScript.heightmap_height_at_world_xz(
			TerrainBuilderScript.cedar_hollow_10m_terrain_def(),
			Vector2(world_x, world_z),
			TerrainBuilderScript.cedar_hollow_10m_horizontal_offset())
	var prop: Node3D = DesertPropBuilderScript.build_prop(prop_id, seed)
	prop.rotation_degrees = Vector3(0.0, yaw_degrees, 0.0)
	prop.position = Vector3(world_x, ground_y + DEMO_PROP_GROUND_Y_OFFSET, world_z)
	parent.add_child(prop)


func _spawn_vehicle() -> void:
	_vehicle = VehicleScene.instantiate()
	add_child(_vehicle)
	_configure_streaming_collision()
	_vehicle.call("reset_to", CedarRoute.call("spawn_transform", ZION_SPAWN_ID))
	var visual_builder: RefCounted = ProceduralBuggyVisualScript.new()
	visual_builder.call("attach", _vehicle)
	_collect_visual_wheels()
	_setup_grasshopper_livery()


func _report_render_subsystem_health() -> void:
	# The render host's per-frame visual/camera updates deref sub-systems that are
	# only non-null when their backing scripts compiled and their asset preloads
	# (rc_buggy.glb, residue PNGs) imported. A stale/missing `.godot/imported`
	# cache (or a broken preload) leaves these null; without this check the host
	# spams 3 push_error lines every physics frame (lines 872/1234/1239) and the
	# resulting hitches light up the debug overlay's red HITCH_COLOR banner.
	# Flag the failure exactly once here so the headless harness sees it; the
	# per-frame update paths null-guard and stay quiet (see _update_visual_wheels
	# / _update_chase_camera).
	if _vehicle_visual_root == null:
		push_error("CedarHollowHost render subsystem broken: vehicle visual root missing (procedural_buggy_visual.gd or rc_buggy.glb import failed); visual updates skipped")
	if _vehicle_residue_visual == null:
		push_error("CedarHollowHost render subsystem broken: vehicle residue visual missing (vehicle_residue_visual.gd or residue texture import failed); residue updates skipped")
	if _chase_camera_rig == null:
		push_error("CedarHollowHost render subsystem broken: chase camera rig missing (chase_camera_rig.gd failed to instantiate); chase camera updates skipped")


func _configure_streaming_collision() -> void:
	var body: Node3D = _vehicle.get_node_or_null("PhysicsBody") as Node3D
	if body == null:
		push_error("CedarHollowHost could not configure TileStreamer without Vehicle/PhysicsBody")
		return
	var streamer: Node = get_node_or_null("/root/TileStreamer")
	if streamer == null:
		push_error("CedarHollowHost requires TileStreamer autoload for streamed Zion collision")
		return
	streamer.call("configure_region", ZION_REGION_ID, body)


func _setup_grasshopper_livery() -> void:
	_grasshopper_livery = GrasshopperLiveryScript.new() as Node
	if _grasshopper_livery == null:
		return
	_grasshopper_livery.name = "GrasshopperLivery"
	add_child(_grasshopper_livery)
	_grasshopper_livery.call("configure", _vehicle_visual_root)


func _setup_light() -> void:
	_sun = DirectionalLight3D.new()
	_sun.name = "GoldenHourSun"
	add_child(_sun)
	_apply_mood()


func _setup_audio() -> void:
	if not GameConfig.audio_enabled or _audio_disabled_by_cmdline():
		return
	_audio_rig = CedarAudioRigScript.new()
	_audio_rig.name = "CedarAudioRig"
	add_child(_audio_rig)
	_audio_rig.call("configure", _vehicle)


func _audio_disabled_by_cmdline() -> bool:
	for arg in OS.get_cmdline_user_args():
		if String(arg) == "--no-audio":
			return true
	return false


func _setup_recoverable_object_render() -> void:
	_recoverable_object_render = RecoverableObjectRenderScript.new() as Node
	if _recoverable_object_render == null:
		return
	_recoverable_object_render.name = "RecoverableObjectRender"
	add_child(_recoverable_object_render)
	_recoverable_object_render.call("configure", _world)


func _setup_golden_line_systems() -> void:
	_golden_line_tracker = GoldenLineTrackerScript.new() as Node
	if _golden_line_tracker != null:
		_golden_line_tracker.name = "GoldenLineTracker"
		add_child(_golden_line_tracker)
		_golden_line_tracker.call("configure")
	_golden_line_ghost = GoldenLineGhostScript.new() as Node
	if _golden_line_ghost != null:
		_golden_line_ghost.name = "GoldenLineGhost"
		add_child(_golden_line_ghost)


func _setup_environment() -> void:
	_world_environment = WorldEnvironment.new()
	_world_environment.name = "GoldenHourEnvironment"
	var environment: Environment = Environment.new()
	_world_environment.environment = environment
	add_child(_world_environment)
	_apply_mood()


func _setup_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "ChaseCamera"
	_camera.current = true
	_camera.fov = GameConfig.cam_fov_base
	_camera.far = GameConfig.cam_far
	add_child(_camera)
	_orbit_camera = Camera3D.new()
	_orbit_camera.name = "OrbitCamera"
	_orbit_camera.current = false
	_orbit_camera.fov = GameConfig.orbit_cam_fov
	_orbit_camera.far = GameConfig.orbit_cam_far
	add_child(_orbit_camera)
	_fpv_camera = Camera3D.new()
	_fpv_camera.name = "FpvCamera"
	_fpv_camera.current = false
	_fpv_camera.fov = GameConfig.fpv_cam_fov
	_fpv_camera.far = GameConfig.fpv_cam_far
	add_child(_fpv_camera)
	_cinematic_camera = Camera3D.new()
	_cinematic_camera.name = "CinematicTourCamera"
	_cinematic_camera.current = false
	_cinematic_camera.fov = GameConfig.cinematic_tour_fov
	_cinematic_camera.far = GameConfig.cinematic_tour_far
	add_child(_cinematic_camera)
	DustTiltShiftVisualBuilderScript.build(self, _camera, _orbit_camera, _fpv_camera)
	_orbit_yaw_degrees = GameConfig.orbit_cam_start_yaw_deg
	_update_camera(GameConfig.FIXED_DT)


func _setup_vehicle_juice() -> void:
	var juice_rig: Node = VehicleJuiceRigScript.new()
	juice_rig.name = "VehicleJuiceRig"
	add_child(juice_rig)
	juice_rig.call("configure", _vehicle, _camera, _vehicle_visual_root as Node3D)


func _setup_photograph_system() -> void:
	_photograph_system = PhotographSystemScript.new() as Node
	if _photograph_system == null:
		return
	_photograph_system.name = "PhotographSystem"
	add_child(_photograph_system)
	_photograph_system.call("configure", CedarRoute, _vehicle)


func _setup_hud() -> void:
	_landmark_hint_hud = LandmarkHintHudScript.new() as CanvasLayer
	_landmark_hint_hud.name = "LandmarkHintHud"
	_landmark_hint_hud.visible = GameConfig.minimap_enabled_by_default
	add_child(_landmark_hint_hud)
	_landmark_hint_hud.call("configure", CedarRoute, _vehicle)
	_speed_hud = SpeedHudScript.new() as CanvasLayer
	_speed_hud.name = "SpeedHud"
	_speed_hud.visible = GameConfig.speed_hud_enabled
	add_child(_speed_hud)
	_speed_hud.call("configure", _vehicle)
	_setup_title_card_hud()
	_controls_hint_hud = ControlsHintHudScript.new() as CanvasLayer
	_controls_hint_hud.name = "ControlsHintHud"
	_controls_hint_hud.visible = GameConfig.controls_hint_hud_enabled
	add_child(_controls_hint_hud)
	_debug_overlay_hud = DebugOverlayHudScript.new() as CanvasLayer
	_debug_overlay_hud.name = "DebugOverlayHud"
	# Start-visible is a separate knob from the player-facing default so the
	# recording/capture toolchain can bake telemetry + the hitch red-flash into
	# the recording (debug_overlay_start_visible) without flipping the in-game
	# default (debug_overlay_enabled_by_default). Either true -> visible.
	_debug_overlay_hud.visible = GameConfig.debug_overlay_enabled_by_default or GameConfig.debug_overlay_start_visible
	add_child(_debug_overlay_hud)
	_debug_overlay_hud.call("configure", self)


func _setup_title_card_hud() -> void:
	if _title_card_hud != null or not GameConfig.title_card_enabled:
		return
	_title_card_hud = TitleCardHud.new() as CanvasLayer
	_title_card_hud.name = "TitleCardHud"
	add_child(_title_card_hud)


func _update_cold_start_streaming_gate(delta: float) -> void:
	if _cold_start_streaming_released:
		return
	_cold_start_hold_elapsed += maxf(delta, 0.0)
	if _visual_streaming_ready_for_reveal() or _cold_start_hold_elapsed >= maxf(GameConfig.title_card_max_hold_seconds, 0.0):
		_release_cold_start_streaming_gate()


func _release_cold_start_streaming_gate() -> void:
	if _cold_start_streaming_released:
		return
	_cold_start_streaming_released = true
	if _audio_rig != null:
		_audio_rig.call("start")
	if _title_card_hud != null and _title_card_hud.has_method("notify_world_ready"):
		_title_card_hud.call("notify_world_ready")


func _visual_streaming_ready_for_reveal() -> bool:
	if _terrain_visual_streamer == null:
		return false
	if not _terrain_visual_streamer.has_method("active_visual_cells"):
		return false
	var active_cells: Array = _terrain_visual_streamer.call("active_visual_cells")
	var active_count: int = active_cells.size()
	if active_count <= 0:
		return false
	var expected_count: int = _expected_spawn_visual_cell_count()
	if expected_count <= 0:
		return _visual_streaming_ready_signal_observed(active_count)
	if active_count < expected_count:
		return false
	if not _spawn_visual_cells_committed_for_reveal(active_cells):
		return false
	if _terrain_visual_streamer.has_method("foliage_cell_count"):
		var foliage_count: int = int(_terrain_visual_streamer.call("foliage_cell_count"))
		if foliage_count < expected_count:
			return false
	return true


func _spawn_visual_cells_committed_for_reveal(active_cells: Array) -> bool:
	# Reveal as soon as every expected spawn cell has a COMMITTED visual tile at ANY
	# resolution (coarse step=5 is fine). Previously this blocked the title card until
	# all ~49 spawn tiles reached fullres step=1, which serialized 49 heavy step-1 GPU
	# uploads on the main thread -> a multi-second boot freeze. The streamer now commits
	# the coarse tile first and progressively upgrades each active cell to fullres after
	# reveal (see terrain_visual_streamer._on_world_tile_activated), so the world appears
	# fast and sharpens over the next frames instead of stalling the boot.
	if _terrain_visual_streamer == null:
		return false
	if not _terrain_visual_streamer.has_method("committed_visual_cell_sample_step"):
		return false
	var expected_cells: Array[Vector2i] = _expected_spawn_visual_cells()
	if expected_cells.is_empty():
		return true
	var active_lookup: Dictionary[Vector2i, bool] = {}
	for active_cell_variant in active_cells:
		if active_cell_variant is Vector2i:
			active_lookup[active_cell_variant] = true
	for cell in expected_cells:
		if not active_lookup.has(cell):
			return false
		var sample_step: int = int(_terrain_visual_streamer.call("committed_visual_cell_sample_step", cell))
		# -1 == not committed yet; any step >= fullres (i.e. >= 1) means a tile is on screen.
		if sample_step < TerrainVisualBuilderScript.REGION_DETAIL_FULLRES_SAMPLE_STEP:
			return false
	return true


func _visual_streaming_ready_signal_observed(active_count: int) -> bool:
	if active_count <= 0:
		return false
	if not _terrain_visual_streamer.has_method("ready_visual_cell_count"):
		return false
	var ready_visual_count: int = int(_terrain_visual_streamer.call("ready_visual_cell_count"))
	if ready_visual_count < active_count:
		return false
	if _terrain_visual_streamer.has_method("ready_foliage_cell_count"):
		var ready_foliage_count: int = int(_terrain_visual_streamer.call("ready_foliage_cell_count"))
		if ready_foliage_count < active_count:
			return false
	return true


func _expected_spawn_visual_cell_count() -> int:
	return _expected_spawn_visual_cells().size()


func _expected_spawn_visual_cells() -> Array[Vector2i]:
	var streamer: Node = get_node_or_null("/root/TileStreamer")
	if streamer == null or not streamer.has_method("expected_active_cells_for_position"):
		return []
	var cells: Array = streamer.call("expected_active_cells_for_position", _vehicle_world_position())
	var typed_cells: Array[Vector2i] = []
	for cell_variant in cells:
		if cell_variant is Vector2i:
			typed_cells.append(cell_variant)
	return typed_cells



func _vehicle_world_position() -> Vector3:
	if _vehicle != null:
		var body: Node3D = _vehicle.get_node_or_null("PhysicsBody") as Node3D
		if body != null:
			return body.global_position
	return global_position


func _sample_golden_line() -> void:
	if _golden_line_tracker == null:
		_sim_tick += 1
		return
	var state: RefCounted = _vehicle.call("get_state")
	_golden_line_tracker.call("sample_vehicle_state", state, _sim_tick)
	_sim_tick += 1


func _setup_frequency_input_panel() -> void:
	_frequency_input_panel = FrequencyInputPanelScene.instantiate() as CanvasLayer
	if _frequency_input_panel == null:
		push_error("CedarHollowHost failed to instantiate frequency input panel")
		return
	_frequency_input_panel.name = "FrequencyInputPanel"
	add_child(_frequency_input_panel)
	_frequency_input_panel.visible = false
	if _frequency_input_panel.has_signal("ui_submitted_frequency_code"):
		_frequency_input_panel.connect("ui_submitted_frequency_code", Callable(self, "_on_frequency_code_submitted"))


func _update_vehicle_input() -> void:
	var forward_throttle: float = Input.get_action_strength("throttle")
	var reverse_throttle: float = Input.get_action_strength("reverse")
	var brake_action: float = Input.get_action_strength("brake")
	var throttle: float = forward_throttle - reverse_throttle
	var brake: float = 0.0
	if forward_throttle > 0.0 or reverse_throttle <= 0.0:
		brake = brake_action
	var steer: float = Input.get_action_strength("steer_left") - Input.get_action_strength("steer_right")
	if not _cold_start_streaming_released:
		_vehicle_input.set("throttle", 0.0)
		_vehicle_input.set("brake", 0.0)
		_vehicle_input.set("steer", 0.0)
		_vehicle_input.set("ebrake", false)
		_vehicle_input.set("self_right", false)
		return
	_vehicle_input.set("throttle", clampf(throttle, -1.0, 1.0))
	_vehicle_input.set("brake", brake)
	_vehicle_input.set("steer", clampf(steer, -1.0, 1.0))
	_vehicle_input.set("ebrake", Input.is_action_pressed("ebrake"))
	_vehicle_input.set("self_right", Input.is_action_just_pressed("self_right"))
	if _has_drive_input_active(throttle, brake, steer):
		_drive_started = true
		if _cinematic_tour_active:
			_exit_cinematic_tour()


func _update_cinematic_tour_input() -> void:
	if not Input.is_action_just_pressed("cinematic_tour"):
		return
	if _read_has_drive_input_active():
		if _cinematic_tour_active:
			_exit_cinematic_tour()
		return
	toggle_cinematic_tour()


func _read_has_drive_input_active() -> bool:
	var forward_throttle: float = Input.get_action_strength("throttle")
	var reverse_throttle: float = Input.get_action_strength("reverse")
	var brake_action: float = Input.get_action_strength("brake")
	var throttle: float = forward_throttle - reverse_throttle
	var steer: float = Input.get_action_strength("steer_left") - Input.get_action_strength("steer_right")
	var brake: float = 0.0
	if forward_throttle > 0.0 or reverse_throttle <= 0.0:
		brake = brake_action
	return _has_drive_input_active(throttle, brake, steer)


func _has_drive_input_active(throttle: float, brake: float, steer: float) -> bool:
	return absf(throttle) > 0.0 or brake > 0.0 or absf(steer) > 0.0 or Input.is_action_pressed("ebrake")


func toggle_cinematic_tour() -> void:
	if _cinematic_tour_active:
		_exit_cinematic_tour()
	else:
		_enter_cinematic_tour()


func _enter_cinematic_tour() -> void:
	if _cinematic_tour_active or _cinematic_camera == null:
		return
	if _photo_mode_active:
		_exit_photo_mode()
	_cinematic_tour_active = true
	_cinematic_tour_elapsed = 0.0
	_cinematic_tour_previous_camera_mode = _camera_mode
	_cinematic_tour_previous_landmark_hud_visible = _landmark_hint_hud.visible if _landmark_hint_hud != null else false
	_cinematic_tour_previous_speed_hud_visible = _speed_hud.visible if _speed_hud != null else false
	_cinematic_tour_previous_controls_hint_visible = _controls_hint_hud.visible if _controls_hint_hud != null else false
	_cinematic_tour_previous_title_hud_visible = _title_card_hud.visible if _title_card_hud != null else false
	_set_cinematic_tour_hud_visible(false)
	_update_cinematic_camera(0.0)


func _exit_cinematic_tour() -> void:
	if not _cinematic_tour_active:
		return
	_cinematic_tour_active = false
	_camera_mode = _cinematic_tour_previous_camera_mode
	_restore_cinematic_tour_hud()
	if _cinematic_camera != null:
		_cinematic_camera.current = false
	_update_camera(GameConfig.FIXED_DT)


func _set_cinematic_tour_hud_visible(hud_visible: bool) -> void:
	if _landmark_hint_hud != null:
		_landmark_hint_hud.visible = hud_visible
	if _speed_hud != null:
		_speed_hud.visible = hud_visible
	if _controls_hint_hud != null:
		_controls_hint_hud.visible = hud_visible
	if _title_card_hud != null:
		_title_card_hud.visible = hud_visible


func _restore_cinematic_tour_hud() -> void:
	if _landmark_hint_hud != null:
		_landmark_hint_hud.visible = _cinematic_tour_previous_landmark_hud_visible
	if _speed_hud != null:
		_speed_hud.visible = _cinematic_tour_previous_speed_hud_visible
	if _controls_hint_hud != null:
		_controls_hint_hud.visible = _cinematic_tour_previous_controls_hint_visible
	if _title_card_hud != null:
		_title_card_hud.visible = _cinematic_tour_previous_title_hud_visible


func _update_photo_mode_input() -> void:
	if _cinematic_tour_active:
		return
	if not Input.is_action_just_pressed("photo_mode"):
		return
	toggle_photo_mode()


func toggle_photo_mode() -> void:
	if _photo_mode_active:
		_exit_photo_mode()
	else:
		_enter_photo_mode()


func _enter_photo_mode() -> void:
	if _photo_mode_active:
		return
	_photo_mode_active = true
	_photo_mode_previous_camera_mode = _camera_mode
	_photo_mode_previous_speed_hud_visible = _speed_hud.visible if _speed_hud != null else false
	_photo_mode_previous_controls_hint_visible = _controls_hint_hud.visible if _controls_hint_hud != null else false
	_camera_mode = CAMERA_MODE_FPV
	_set_photo_mode_hud_visible(false)
	_update_camera(GameConfig.FIXED_DT)


func _exit_photo_mode() -> void:
	if not _photo_mode_active:
		return
	_photo_mode_active = false
	_camera_mode = _photo_mode_previous_camera_mode
	_restore_photo_mode_hud()
	_update_camera(GameConfig.FIXED_DT)


func _set_photo_mode_hud_visible(hud_visible: bool) -> void:
	if _speed_hud != null:
		_speed_hud.visible = hud_visible
	if _controls_hint_hud != null:
		_controls_hint_hud.visible = hud_visible


func _restore_photo_mode_hud() -> void:
	if _speed_hud != null:
		_speed_hud.visible = _photo_mode_previous_speed_hud_visible
	if _controls_hint_hud != null:
		_controls_hint_hud.visible = _photo_mode_previous_controls_hint_visible


func _update_camera_input() -> void:
	if _cinematic_tour_active:
		return
	if not Input.is_action_just_pressed("cam_toggle"):
		return
	cycle_camera_mode()


func cycle_camera_mode() -> void:
	if _photo_mode_active:
		_exit_photo_mode()
		return
	if _camera_mode == CAMERA_MODE_CHASE:
		_camera_mode = CAMERA_MODE_ORBIT
		_update_camera(GameConfig.FIXED_DT)
		return
	if _camera_mode == CAMERA_MODE_ORBIT:
		_camera_mode = CAMERA_MODE_FPV
		_update_camera(GameConfig.FIXED_DT)
		return
	_camera_mode = CAMERA_MODE_CHASE
	_update_camera(GameConfig.FIXED_DT)


func _update_hud_input() -> void:
	if _drive_started and _speed_hud != null:
		_speed_hud.call("set_drive_active", true)
	if _drive_started and _title_card_hud != null:
		_title_card_hud.call("dismiss")
	if _debug_overlay_hud != null and Input.is_action_just_pressed("debug_overlay"):
		toggle_debug_overlay_hud()
	if _landmark_hint_hud == null or not Input.is_action_just_pressed("map_toggle"):
		return
	toggle_landmark_hint_hud()


func toggle_landmark_hint_hud() -> void:
	if _landmark_hint_hud == null:
		return
	_landmark_hint_hud.visible = not _landmark_hint_hud.visible


func toggle_debug_overlay_hud() -> void:
	if _debug_overlay_hud == null:
		return
	_debug_overlay_hud.visible = not _debug_overlay_hud.visible


func _update_frequency_input() -> void:
	if _frequency_input_panel == null or not Input.is_action_just_pressed("frequency_input"):
		return
	if not _drive_started:
		return
	_frequency_input_panel.call("toggle_panel")


func _on_frequency_code_submitted(code: String) -> void:
	if _grasshopper_livery == null:
		return
	_grasshopper_livery.call("try_unlock_with_code", code)


func _update_mood_input() -> void:
	if not Input.is_action_just_pressed("mood_toggle"):
		return
	toggle_mood()


func toggle_mood() -> void:
	if _mood == MOOD_DUSK:
		_mood = MOOD_DAWN
	elif _mood == MOOD_DAWN:
		_mood = MOOD_NIGHT
	else:
		_mood = MOOD_DUSK
	_apply_mood()


func _apply_mood() -> void:
	if _sun != null:
		if _mood == MOOD_DAWN:
			_sun.rotation_degrees = GameConfig.dawn_sun_rotation_degrees
			_sun.light_energy = GameConfig.dawn_sun_energy
			_sun.light_color = GameConfig.dawn_sun_color
		else:
			_sun.rotation_degrees = GameConfig.dusk_sun_rotation_degrees
			_sun.light_energy = GameConfig.dusk_sun_energy
			_sun.light_color = GameConfig.dusk_sun_color
	if _world_environment == null or _world_environment.environment == null:
		return
	var environment: Environment = _world_environment.environment
	var sky_material: Material = _ensure_mood_sky(environment)
	environment.background_mode = Environment.BG_SKY
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_BG
	environment.fog_enabled = true
	if _mood == MOOD_DAWN:
		environment.ambient_light_energy = GameConfig.dawn_ambient_energy
		environment.fog_density = GameConfig.dawn_fog_density
		environment.fog_light_color = GameConfig.dawn_fog_light_color
	else:
		environment.ambient_light_energy = GameConfig.dusk_ambient_energy
		environment.fog_density = GameConfig.dusk_fog_density
		environment.fog_light_color = GameConfig.dusk_fog_light_color
	AtmosphereVisualBuilderScript.apply_mood(_world_environment, _sun, _mood)
	_apply_zion_vista_mood(environment, sky_material)
	var shadow_viewport: Viewport = get_viewport()
	if shadow_viewport != null:
		shadow_viewport.positional_shadow_atlas_size = ZION_SHADOW_ATLAS_SIZE


func _ensure_mood_sky(environment: Environment) -> Material:
	var sky: Sky = environment.sky
	if sky == null:
		sky = Sky.new()
	sky.radiance_size = Sky.RADIANCE_SIZE_2048
	# NIGHT and DUSK both use ShaderMaterials but different shaders, so the
	# resource identity (not just the type) decides whether to rebuild the
	# material. Checking only `is ShaderMaterial` (the old dusk path) would keep
	# the wrong shader when toggling between two shader moods. DAWN keeps the
	# PhysicalSkyMaterial (dawn is unchanged).
	var desired_shader: Shader = null
	if _mood == MOOD_NIGHT:
		desired_shader = NightStarSkyShader
	elif _mood == MOOD_DUSK:
		desired_shader = DuskGoldenSkyShader
	if desired_shader != null:
		var shader_material: ShaderMaterial = sky.sky_material as ShaderMaterial
		if shader_material == null or shader_material.shader != desired_shader:
			shader_material = ShaderMaterial.new()
			shader_material.shader = desired_shader
			sky.sky_material = shader_material
	else:
		if not (sky.sky_material is PhysicalSkyMaterial):
			sky.sky_material = PhysicalSkyMaterial.new()
	environment.sky = sky
	return sky.sky_material


func _apply_zion_vista_mood(environment: Environment, sky_material: Material) -> void:
	if sky_material == null:
		return
	environment.fog_aerial_perspective = ZION_FOG_AERIAL_PERSPECTIVE
	environment.fog_sky_affect = ZION_FOG_SKY_AFFECT
	environment.volumetric_fog_sky_affect = ZION_VOLUMETRIC_FOG_SKY_AFFECT
	if _mood == MOOD_NIGHT:
		environment.fog_density = ZION_NIGHT_FOG_DENSITY
		environment.fog_sky_affect = ZION_NIGHT_FOG_SKY_AFFECT
		environment.volumetric_fog_sky_affect = ZION_NIGHT_FOG_SKY_AFFECT
		return
	if _mood == MOOD_DUSK:
		environment.fog_density = ZION_DUSK_FOG_DENSITY
		_apply_dusk_golden_sky(sky_material)
		return
	# MOOD_DAWN keeps the PhysicalSkyMaterial path (unchanged).
	environment.fog_density = ZION_DAWN_FOG_DENSITY
	var physical_sky_material: PhysicalSkyMaterial = sky_material as PhysicalSkyMaterial
	if physical_sky_material == null:
		return
	physical_sky_material.use_debanding = true
	physical_sky_material.rayleigh_color = GameConfig.dawn_sky_top_color
	physical_sky_material.mie_color = GameConfig.dawn_sky_horizon_color
	physical_sky_material.ground_color = GameConfig.dawn_sky_ground_color
	physical_sky_material.turbidity = GameConfig.dawn_sky_turbidity
	physical_sky_material.sun_disk_scale = 1.0
	physical_sky_material.mie_coefficient = 0.0045
	physical_sky_material.mie_eccentricity = 0.80
	physical_sky_material.energy_multiplier = 1.15


func _apply_dusk_golden_sky(sky_material: Material) -> void:
	# Feeds the dusk_golden_sky.gdshader. Zenith/horizon/ground reuse the tuned
	# GameConfig dusk_sky_* values (blue zenith + de-orange preserved); the cyan
	# mid band, gold sun, and cirrus are the zionfid/sky enrichment. The sun
	# direction is derived from the real GoldenHourSun transform so the disk +
	# aureole sit exactly where PhysicalSkyMaterial placed them (sun source =
	# light basis.z, the direction opposite the light's -Z emission axis).
	var dusk_material: ShaderMaterial = sky_material as ShaderMaterial
	if dusk_material == null:
		return
	dusk_material.set_shader_parameter("zenith_color", _rgb(GameConfig.dusk_sky_top_color))
	dusk_material.set_shader_parameter("mid_color", _rgb(DUSK_GOLDEN_MID_COLOR))
	dusk_material.set_shader_parameter("horizon_color", _rgb(GameConfig.dusk_sky_horizon_color))
	dusk_material.set_shader_parameter("ground_color", _rgb(GameConfig.dusk_sky_ground_color))
	dusk_material.set_shader_parameter("sun_color", _rgb(DUSK_GOLDEN_SUN_COLOR))
	dusk_material.set_shader_parameter("cirrus_color", _rgb(DUSK_GOLDEN_CIRRUS_COLOR))
	var sun_dir: Vector3 = Vector3(0.0, 1.0, 0.0)
	if _sun != null:
		sun_dir = _sun.global_transform.basis.z.normalized()
	dusk_material.set_shader_parameter("sun_direction", sun_dir)
	dusk_material.set_shader_parameter("sun_disk_scale", maxf(GameConfig.dusk_sky_sun_disk_scale, 0.05))
	dusk_material.set_shader_parameter("sun_halo_strength", DUSK_GOLDEN_SUN_HALO_STRENGTH)
	dusk_material.set_shader_parameter("horizon_band_width", DUSK_GOLDEN_HORIZON_BAND_WIDTH)
	dusk_material.set_shader_parameter("cirrus_coverage", DUSK_GOLDEN_CIRRUS_COVERAGE)
	dusk_material.set_shader_parameter("cirrus_intensity", DUSK_GOLDEN_CIRRUS_INTENSITY)
	dusk_material.set_shader_parameter("energy_multiplier", DUSK_GOLDEN_ENERGY_MULTIPLIER)


static func _rgb(color: Color) -> Vector3:
	# Plain-vec3 sky uniforms receive linear Vector3 values directly (no
	# source_color hint), so the art-bible linear colors are used verbatim.
	return Vector3(color.r, color.g, color.b)


func _collect_visual_wheels() -> void:
	_wheel_sockets.clear()
	_vehicle_visual_root = null
	_visual_body_pitch = 0.0
	_visual_body_roll = 0.0
	_visual_body_pitch_velocity = 0.0
	_visual_body_roll_velocity = 0.0
	_visual_antenna_pitch = 0.0
	_visual_antenna_roll = 0.0
	_visual_antenna_pitch_velocity = 0.0
	_visual_antenna_roll_velocity = 0.0
	_visual_last_velocity = Vector3.ZERO
	_visual_last_velocity_valid = false
	var body: Node = _vehicle.get_node_or_null("PhysicsBody")
	if body == null:
		return
	var visual_root: Node = body.get_node_or_null("VisualRoot")
	if visual_root == null:
		return
	_vehicle_visual_root = visual_root
	var names: Array[String] = [
		"wheel_front_left",
		"wheel_front_right",
		"wheel_rear_left",
		"wheel_rear_right"
	]
	for socket_name in names:
		var socket: Node3D = visual_root.get_node_or_null(socket_name) as Node3D
		if socket != null:
			_wheel_sockets.append(socket)


func _update_visual_wheels(delta: float) -> void:
	if _vehicle_visual_root == null:
		return
	var state: RefCounted = _vehicle.call("get_state")
	var acceleration: Vector3 = _visual_acceleration(state, delta)
	if _vehicle_residue_runtime_updates_enabled():
		_update_vehicle_residue_visual(state)
	_update_vehicle_visual_body(state, acceleration, delta)
	_update_whip_antenna_visual(state, acceleration, delta)
	if _runtime_shader_feedback_enabled():
		_update_grass_crush(state)
	if _runtime_shader_feedback_enabled():
		var tail_material: StandardMaterial3D = ProceduralBuggyVisualScript.get_tail_light_material(_vehicle_visual_root)
		if tail_material != null:
			var braking: float = float(_vehicle_input.get("brake"))
			var ebrake: bool = bool(_vehicle_input.get("ebrake"))
			var glowing: bool = braking > 0.0 or ebrake
			tail_material.emission_energy_multiplier = GameConfig.brake_light_energy if glowing else 0.0
	if _wheel_sockets.is_empty():
		return
	ProceduralBuggyVisualScript.sync_wheel_socket_heights(_vehicle_visual_root, _wheel_sockets, state)
	var speed: float = float(state.call("speed"))
	var spin_step: float = speed * delta / maxf(GameConfig.wheel_radius, 0.001)
	var throttle: float = float(_vehicle_input.get("throttle"))
	if throttle < 0.0:
		spin_step *= -1.0
	_wheel_spin += spin_step
	var steer: float = float(_vehicle_input.get("steer"))
	var steer_angle: float = deg_to_rad(GameConfig.wheel_visual_max_steer_deg) * steer
	for socket in _wheel_sockets:
		var is_front: bool = socket.name.begins_with("wheel_front")
		socket.rotation = Vector3(0.0, steer_angle if is_front else 0.0, 0.0)
		var wheel_mesh: Node3D = _wheel_mesh_for_socket(socket)
		if wheel_mesh != null:
			wheel_mesh.rotation = Vector3(_wheel_spin, 0.0, deg_to_rad(90.0))
	var hit_points: Array[Vector3] = state.get("wheel_hit_point")
	for i in range(mini(ProceduralBuggyVisualScript.SHOCK_NODE_NAMES.size(), hit_points.size())):
		var shock_name: String = String(ProceduralBuggyVisualScript.SHOCK_NODE_NAMES[i])
		var shock: Node3D = _vehicle_visual_root.find_child(shock_name, true, false) as Node3D
		if shock == null:
			continue
		var spring: Node3D = shock.find_child(shock_name + "_spring", false, false) as Node3D
		if spring == null:
			continue
		var compression: float = clampf((shock.global_position.y - hit_points[i].y - GameConfig.wheel_radius) / maxf(GameConfig.susp_travel, 0.001), 0.0, 1.0)
		spring.scale.y = lerpf(1.0, 0.55, compression)


func _update_vehicle_visual_body(state: RefCounted, acceleration: Vector3, delta: float) -> void:
	var visual_root: Node3D = _vehicle_visual_root as Node3D
	if visual_root == null:
		return
	var basis: Basis = state.get("basis")
	var forward: Vector3 = -basis.z.normalized()
	var right: Vector3 = basis.x.normalized()
	var forward_accel: float = acceleration.dot(forward)
	var lateral_accel: float = acceleration.dot(right)
	var steer: float = clampf(float(_vehicle_input.get("steer")), -1.0, 1.0)
	var limit: float = deg_to_rad(maxf(GameConfig.vehicle_visual_body_lean_max_deg, 0.0))
	var target_pitch: float = clampf(
			-forward_accel * GameConfig.vehicle_visual_body_pitch_accel_gain,
			-limit,
			limit
	)
	var target_roll: float = clampf(
			-steer * GameConfig.vehicle_visual_body_roll_steer_gain
					-lateral_accel * GameConfig.vehicle_visual_body_roll_lateral_accel_gain,
			-limit,
			limit
	)
	_visual_body_pitch = _spring_scalar(
			_visual_body_pitch,
			target_pitch,
			delta,
			GameConfig.vehicle_visual_body_lean_spring,
			GameConfig.vehicle_visual_body_lean_damping,
			&"_visual_body_pitch_velocity"
	)
	_visual_body_roll = _spring_scalar(
			_visual_body_roll,
			target_roll,
			delta,
			GameConfig.vehicle_visual_body_lean_spring,
			GameConfig.vehicle_visual_body_lean_damping,
			&"_visual_body_roll_velocity"
	)
	visual_root.rotation = Vector3(_visual_body_pitch, 0.0, _visual_body_roll)


func _update_whip_antenna_visual(state: RefCounted, acceleration: Vector3, delta: float) -> void:
	var visual_root: Node3D = _vehicle_visual_root as Node3D
	if visual_root == null:
		return
	var antenna: Node3D = ProceduralBuggyVisualScript.get_whip_antenna(visual_root)
	if antenna == null:
		return
	var basis: Basis = state.get("basis")
	var forward: Vector3 = -basis.z.normalized()
	var right: Vector3 = basis.x.normalized()
	var velocity: Vector3 = state.get("linear_velocity")
	var speed: float = velocity.length()
	var forward_accel: float = acceleration.dot(forward)
	var lateral_accel: float = acceleration.dot(right)
	var landing_impulse: float = maxf(0.0, -acceleration.y) * GameConfig.vehicle_visual_antenna_landing_gain
	var limit: float = deg_to_rad(maxf(GameConfig.vehicle_visual_antenna_max_deg, 0.0))
	var target_pitch: float = clampf(
			speed * GameConfig.vehicle_visual_antenna_speed_lean_gain
					-forward_accel * GameConfig.vehicle_visual_antenna_accel_gain
					+ landing_impulse,
			-limit,
			limit
	)
	var target_roll: float = clampf(
			-lateral_accel * GameConfig.vehicle_visual_antenna_accel_gain,
			-limit,
			limit
	)
	_visual_antenna_pitch = _spring_scalar(
			_visual_antenna_pitch,
			target_pitch,
			delta,
			GameConfig.vehicle_visual_antenna_spring,
			GameConfig.vehicle_visual_antenna_damping,
			&"_visual_antenna_pitch_velocity"
	)
	_visual_antenna_roll = _spring_scalar(
			_visual_antenna_roll,
			target_roll,
			delta,
			GameConfig.vehicle_visual_antenna_spring,
			GameConfig.vehicle_visual_antenna_damping,
			&"_visual_antenna_roll_velocity"
	)
	antenna.rotation = Vector3(_visual_antenna_pitch, 0.0, _visual_antenna_roll)


func _visual_acceleration(state: RefCounted, delta: float) -> Vector3:
	var velocity: Vector3 = state.get("linear_velocity")
	if not _visual_last_velocity_valid:
		_visual_last_velocity = velocity
		_visual_last_velocity_valid = true
		return Vector3.ZERO
	var safe_delta: float = maxf(delta, GameConfig.FIXED_DT)
	var acceleration: Vector3 = (velocity - _visual_last_velocity) / safe_delta
	_visual_last_velocity = velocity
	return acceleration


func _chase_acceleration(state: RefCounted, delta: float) -> Vector3:
	var velocity: Vector3 = state.get("linear_velocity")
	var angular_velocity: Vector3 = state.get("angular_velocity")
	if not _chase_last_velocity_valid:
		_chase_last_velocity = velocity
		_chase_last_velocity_valid = true
		return Vector3.ZERO
	# Stop-lock: when the vehicle is essentially stationary, the velocity carries
	# only never-sleeping rigid-body jitter; dividing that by ~delta amplifies it
	# ~60x and pumps the camera's bank/pitch. Return zero AND re-pin the last
	# velocity to the current reading so the post-release first delta doesn't
	# explode from a stale accumulated difference.
	if velocity.length() < GameConfig.cam_stop_lock_speed and absf(angular_velocity.y) < GameConfig.cam_stop_lock_yaw_speed:
		_chase_last_velocity = velocity
		return Vector3.ZERO
	var safe_delta: float = maxf(delta, GameConfig.FIXED_DT)
	var acceleration: Vector3 = (velocity - _chase_last_velocity) / safe_delta
	_chase_last_velocity = velocity
	return acceleration


func _spring_scalar(current: float, target: float, delta: float, spring: float, damping: float, velocity_property: StringName) -> float:
	var velocity: float = float(get(velocity_property))
	velocity += (target - current) * maxf(spring, 0.0) * delta
	velocity *= maxf(0.0, 1.0 - maxf(damping, 0.0) * delta)
	set(velocity_property, velocity)
	return current + velocity * delta


func _update_grass_crush(state: RefCounted) -> void:
	# Re-collect grass materials only periodically, scoped to the foliage streamer
	# subtree (NOT the whole host tree — that pulled in the track painter's stamp
	# nodes and grew unbounded, scanning more nodes every physics tick).
	_grass_crush_collect_tick += 1
	if _grass_crush_materials.is_empty() or _grass_crush_collect_tick >= GRASS_CRUSH_RECOLLECT_INTERVAL:
		_grass_crush_collect_tick = 0
		_grass_crush_materials.clear()
		if _terrain_visual_streamer != null:
			_collect_grass_crush_materials(_terrain_visual_streamer)
	var vehicle_position: Vector3 = state.get("position")
	for material in _grass_crush_materials:
		if material == null:
			continue
		material.set_shader_parameter(&"vehicle_world_pos", vehicle_position)
		material.set_shader_parameter(&"crush_radius", maxf(GameConfig.grass_crush_radius, 0.0))
		material.set_shader_parameter(&"crush_strength", maxf(GameConfig.grass_crush_strength, 0.0))


func _collect_grass_crush_materials(root: Node) -> void:
	for child in root.get_children():
		var multimesh_instance: MultiMeshInstance3D = child as MultiMeshInstance3D
		if multimesh_instance != null:
			var material: ShaderMaterial = multimesh_instance.material_override as ShaderMaterial
			if material != null and material.shader == GrassShader and not _grass_crush_materials.has(material):
				_grass_crush_materials.append(material)
		_collect_grass_crush_materials(child)


func _update_vehicle_residue_visual(state: RefCounted) -> void:
	if _vehicle_visual_root == null:
		return
	_vehicle_residue_visual.call("apply_state", _vehicle_visual_root, state)


func _vehicle_residue_runtime_updates_enabled() -> bool:
	return DisplayServer.get_name() != &"headless"


func _runtime_shader_feedback_enabled() -> bool:
	return DisplayServer.get_name() != &"headless"


func _runtime_camera_updates_enabled() -> bool:
	return DisplayServer.get_name() != &"headless"


func _update_terrain_tracks() -> void:
	if _terrain_track_painter == null:
		return
	var state: RefCounted = _vehicle.call("get_state")
	_terrain_track_painter.call("apply_vehicle_state", state, GameConfig.FIXED_DT)
	# Re-applying the track texture to streamed tiles (a full streamer-tree walk)
	# happens once per RENDER frame in _process(); doing it here too meant ~120Hz
	# whole-tree material walks on top of the ~60Hz one. Stamp painting stays here.


func _apply_terrain_tracks_to_streamed_tiles() -> void:
	if _terrain_visual_streamer == null:
		return
	var track_texture: Texture2D = _terrain_track_painter.call("track_texture") as Texture2D
	if track_texture == null:
		return
	var track_bounds_min: Vector2 = _terrain_track_painter.call("render_bounds_min")
	var track_bounds_max: Vector2 = _terrain_track_painter.call("render_bounds_max")
	var track_state_changed: bool = _track_texture_state_changed(track_texture, track_bounds_min, track_bounds_max)
	if track_state_changed:
		_remember_track_texture_state(track_texture, track_bounds_min, track_bounds_max)
		_track_apply_queue.clear()
		_track_apply_queue_lookup.clear()
	if not _terrain_visual_streamer.has_method("active_visual_cells"):
		return
	var active_cells: Array = _terrain_visual_streamer.call("active_visual_cells")
	# Change gate: skip the per-frame overlay re-apply when nothing it depends on
	# has changed. The two signals it tracks are (1) the track RT's texture +
	# bounds (already computed above) and (2) the streamer's committed active
	# visual cell set. When both are stable AND no queued applies remain, the
	# sync pass would queue nothing new and the drain would do nothing, so the
	# re-apply is pure busywork.
	#
	# Visual identity holds because:
	#   - Newly committed/evicted visual tiles always mutate
	#     active_visual_cells() (it returns _visual_tiles_by_cell.keys()), so the
	#     set comparison fires exactly when a tile needs first-time apply or
	#     cleanup.
	#   - Stamp paint updates mutate the RT's *pixels*, not its Texture2D object
	#     identity or bounds; materials on already-applied tiles sample that same
	#     viewport texture on the GPU every frame, so fresh paint shows up with no
	#     host-side re-apply.
	#   - The queue-empty check guarantees any in-flight work still drains.
	if not track_state_changed \
			and _track_apply_queue.is_empty() \
			and _active_cells_unchanged(active_cells):
		return
	_remember_active_cells(active_cells)
	_sync_track_apply_queue(active_cells, track_bounds_min, track_bounds_max, track_state_changed)
	_drain_track_apply_queue(track_texture, track_bounds_min, track_bounds_max)


func _remember_track_texture_state(track_texture: Texture2D, bounds_min: Vector2, bounds_max: Vector2) -> void:
	_track_texture_state_valid = true
	_track_last_texture = track_texture
	_track_last_bounds_min = bounds_min
	_track_last_bounds_max = bounds_max


func _track_texture_state_changed(track_texture: Texture2D, bounds_min: Vector2, bounds_max: Vector2) -> bool:
	return not _track_texture_state_valid \
		or _track_last_texture != track_texture \
		or _track_last_bounds_min != bounds_min \
		or _track_last_bounds_max != bounds_max


func _active_cells_unchanged(active_cells: Array) -> bool:
	# Cheap structural equality vs the cached snapshot: same count, then every
	# current cell is present in the cache. active_visual_cells() is already a
	# sorted Array[Vector2i], so a single forward sweep suffices; no per-cell
	# Dictionary build on the hot path.
	if active_cells.size() != _track_last_active_cells.size():
		return false
	for cell_variant in active_cells:
		if not _track_last_active_cells.has(cell_variant):
			return false
	return true


func _remember_active_cells(active_cells: Array) -> void:
	_track_last_active_cells.clear()
	for cell_variant in active_cells:
		_track_last_active_cells[cell_variant] = true


func _sync_track_apply_queue(active_cells: Array, bounds_min: Vector2, bounds_max: Vector2, force_refresh: bool) -> void:
	var active_lookup: Dictionary[Vector2i, bool] = {}
	for cell_variant in active_cells:
		var cell: Vector2i = cell_variant
		active_lookup[cell] = true
		if not _track_cell_intersects_bounds(cell, bounds_min, bounds_max):
			if _track_applied_cells.has(cell):
				_clear_track_apply_cell(cell)
			_unqueue_track_apply_cell(cell)
			continue
		if force_refresh or not _track_applied_cells.has(cell):
			_queue_track_apply_cell(cell)
			continue
		# Streamed visual tiles can be swapped during full-res upgrades; re-queue
		# if the fresh node no longer carries the track overlay we recorded.
		var visual_cell: Node = _visual_cell_node(cell)
		if visual_cell == null or not TerrainVisualBuilderScript.has_track_texture(visual_cell, _track_last_texture):
			_track_applied_cells.erase(cell)
			_queue_track_apply_cell(cell)
	for applied_cell_variant in _track_applied_cells.keys():
		var applied_cell: Vector2i = applied_cell_variant
		if not active_lookup.has(applied_cell):
			_track_applied_cells.erase(applied_cell)
		elif not _track_cell_intersects_bounds(applied_cell, bounds_min, bounds_max):
			_clear_track_apply_cell(applied_cell)


func _queue_track_apply_cell(cell: Vector2i) -> void:
	if _track_apply_queue_lookup.has(cell):
		return
	_track_apply_queue.append(cell)
	_track_apply_queue_lookup[cell] = true


func _unqueue_track_apply_cell(cell: Vector2i) -> void:
	if not _track_apply_queue_lookup.has(cell):
		return
	_track_apply_queue.erase(cell)
	_track_apply_queue_lookup.erase(cell)


func _clear_track_apply_cell(cell: Vector2i) -> void:
	var visual_cell: Node = _visual_cell_node(cell)
	if visual_cell != null:
		TerrainVisualBuilderScript.clear_track_texture(visual_cell, _track_last_texture)
	_track_applied_cells.erase(cell)


func _drain_track_apply_queue(track_texture: Texture2D, bounds_min: Vector2, bounds_max: Vector2) -> void:
	var applied_count: int = 0
	var not_ready_cells: Array[Vector2i] = []
	while applied_count < TRACK_APPLY_CELLS_PER_FRAME and not _track_apply_queue.is_empty():
		var cell: Vector2i = _track_apply_queue.pop_front()
		_track_apply_queue_lookup.erase(cell)
		if not _track_cell_intersects_bounds(cell, bounds_min, bounds_max):
			continue
		var visual_cell: Node = _visual_cell_node(cell)
		if visual_cell == null:
			not_ready_cells.append(cell)
			continue
		TerrainVisualBuilderScript.apply_track_texture(visual_cell, track_texture, bounds_min, bounds_max)
		_track_applied_cells[cell] = true
		applied_count += 1
	for cell in not_ready_cells:
		_queue_track_apply_cell(cell)


func _visual_cell_node(cell: Vector2i) -> Node:
	if _terrain_visual_streamer == null or not _terrain_visual_streamer.has_method("visual_cell_node"):
		return null
	return _terrain_visual_streamer.call("visual_cell_node", cell) as Node


func _track_cell_intersects_bounds(cell: Vector2i, bounds_min: Vector2, bounds_max: Vector2) -> bool:
	var tile_size_m: float = GameConfig.STREAM_TILE_SIZE_M
	var cell_min: Vector2 = Vector2(float(cell.x) * tile_size_m, float(cell.y) * tile_size_m)
	var cell_max: Vector2 = cell_min + Vector2(tile_size_m, tile_size_m)
	return cell_max.x >= bounds_min.x \
		and cell_min.x <= bounds_max.x \
		and cell_max.y >= bounds_min.y \
		and cell_min.y <= bounds_max.y


func _wheel_mesh_for_socket(socket: Node3D) -> Node3D:
	var named_mesh: Node3D = socket.get_node_or_null("wheel_mesh") as Node3D
	if named_mesh != null:
		return named_mesh
	for child in socket.get_children():
		var mesh_child: MeshInstance3D = child as MeshInstance3D
		if mesh_child != null:
			return mesh_child
	return null


func _update_camera(delta: float) -> void:
	if _vehicle == null:
		return
	if _cinematic_tour_active:
		_update_cinematic_camera(delta)
		return
	var state: RefCounted = _vehicle.call("get_state")
	_update_chase_camera(delta, state)
	_update_orbit_camera(delta, state)
	_update_fpv_camera(delta, state)


func _update_cinematic_camera(delta: float) -> void:
	if _cinematic_camera == null:
		return
	var position_count: int = GameConfig.cinematic_tour_positions.size()
	var look_count: int = GameConfig.cinematic_tour_look_targets.size()
	if position_count < 2 or look_count != position_count:
		push_error("Cinematic tour requires matching position/look target arrays with at least two points")
		_exit_cinematic_tour()
		return
	if _camera != null:
		_camera.current = false
	if _orbit_camera != null:
		_orbit_camera.current = false
	if _fpv_camera != null:
		_fpv_camera.current = false
	_cinematic_tour_elapsed += delta
	var duration: float = maxf(GameConfig.cinematic_tour_duration_seconds, 0.001)
	var loop_progress: float = fposmod(_cinematic_tour_elapsed, duration) / duration
	var scaled_progress: float = loop_progress * float(position_count)
	var segment_index: int = int(floorf(scaled_progress)) % position_count
	var segment_t: float = scaled_progress - floorf(scaled_progress)
	var eased_t: float = segment_t
	var position: Vector3 = _cinematic_catmull(GameConfig.cinematic_tour_positions, segment_index, eased_t)
	var look_target: Vector3 = _cinematic_catmull(GameConfig.cinematic_tour_look_targets, segment_index, eased_t)
	_cinematic_camera.global_position = position
	_cinematic_camera.look_at(look_target, Vector3.UP)
	_cinematic_camera.fov = GameConfig.cinematic_tour_fov
	_cinematic_camera.far = GameConfig.cinematic_tour_far
	_cinematic_camera.current = true


func _cinematic_catmull(points: Array[Vector3], index: int, t: float) -> Vector3:
	var count: int = points.size()
	var p0: Vector3 = points[wrapi(index - 1, 0, count)]
	var p1: Vector3 = points[wrapi(index, 0, count)]
	var p2: Vector3 = points[wrapi(index + 1, 0, count)]
	var p3: Vector3 = points[wrapi(index + 2, 0, count)]
	var t2: float = t * t
	var t3: float = t2 * t
	return (
		p1 * 2.0
		+ (p2 - p0) * t
		+ (p0 * 2.0 - p1 * 5.0 + p2 * 4.0 - p3) * t2
		+ (-p0 + p1 * 3.0 - p2 * 3.0 + p3) * t3
	) * 0.5


func _cinematic_ease(t: float) -> float:
	var clamped_t: float = clampf(t, 0.0, 1.0)
	return clamped_t * clamped_t * (3.0 - 2.0 * clamped_t)


func _update_chase_camera(delta: float, state: RefCounted) -> void:
	if _camera == null:
		return
	if _chase_camera_rig == null:
		return
	var steer: float = clampf(float(_vehicle_input.get("steer")), -1.0, 1.0)
	var basis: Basis = state.get("basis")
	var forward: Vector3 = (-basis.z).normalized()
	var right: Vector3 = basis.x.normalized()
	var acceleration: Vector3 = _chase_acceleration(state, delta)
	var lateral_accel: float = acceleration.dot(right)
	var longitudinal_accel: float = acceleration.dot(forward)
	_sync_chase_camera_rig_from_legacy()
	_chase_camera_rig.call("update", _camera, state, steer, delta, true, _camera_mode == CAMERA_MODE_CHASE, lateral_accel, longitudinal_accel)
	_sync_chase_camera_legacy_from_rig()


func _sync_chase_camera_rig_from_legacy() -> void:
	_chase_camera_rig.set("initialized", _chase_camera_initialized)
	_chase_camera_rig.set("look_target_current", _chase_look_target_current)
	_chase_camera_rig.set("back_current", _chase_back_current)
	_chase_camera_rig.set("up_current", _chase_up_current)
	_chase_camera_rig.set("vehicle_y_current", _chase_vehicle_y_current)
	_chase_camera_rig.set("_bank_current_deg", _chase_bank_current_deg)
	_chase_camera_rig.set("_pitch_current_deg", _chase_pitch_current_deg)
	_chase_camera_rig.set("_stop_locked", _chase_stop_locked)


func _sync_chase_camera_legacy_from_rig() -> void:
	_chase_camera_initialized = bool(_chase_camera_rig.get("initialized"))
	_chase_look_target_current = _chase_camera_rig.get("look_target_current")
	_chase_back_current = _chase_camera_rig.get("back_current")
	_chase_up_current = _chase_camera_rig.get("up_current")
	_chase_vehicle_y_current = float(_chase_camera_rig.get("vehicle_y_current"))
	_chase_bank_current_deg = float(_chase_camera_rig.get("_bank_current_deg"))
	_chase_pitch_current_deg = float(_chase_camera_rig.get("_pitch_current_deg"))
	_chase_stop_locked = bool(_chase_camera_rig.get("_stop_locked"))


func _update_orbit_camera(delta: float, state: RefCounted) -> void:
	if _orbit_camera == null:
		return
	var vehicle_position: Vector3 = state.get("position")
	var followed_position: Vector3 = _smoothed_orbit_follow_position(vehicle_position, delta)
	if _camera_mode == CAMERA_MODE_ORBIT:
		_orbit_yaw_degrees += GameConfig.orbit_cam_speed_deg * delta
	var yaw_radians: float = deg_to_rad(_orbit_yaw_degrees)
	var orbit_offset: Vector3 = Vector3(sin(yaw_radians), 0.0, cos(yaw_radians)) * GameConfig.orbit_cam_distance
	var desired_position: Vector3 = followed_position + orbit_offset + Vector3.UP * GameConfig.orbit_cam_height
	var follow_alpha: float = clampf(GameConfig.orbit_cam_spring * delta, 0.0, 1.0)
	if not _orbit_camera_initialized:
		_orbit_camera.global_position = desired_position
		_orbit_camera_initialized = true
	else:
		_orbit_camera.global_position = _orbit_camera.global_position.lerp(desired_position, follow_alpha)
	_orbit_camera.look_at(followed_position + Vector3.UP * GameConfig.orbit_cam_look_height, Vector3.UP)
	_orbit_camera.fov = GameConfig.orbit_cam_fov
	_orbit_camera.current = _camera_mode == CAMERA_MODE_ORBIT


func _smoothed_orbit_follow_position(vehicle_position: Vector3, delta: float) -> Vector3:
	if not _orbit_camera_initialized:
		_orbit_vehicle_y_current = vehicle_position.y
	else:
		var vertical_alpha: float = clampf(GameConfig.cam_vertical_follow_softness * delta, 0.0, 1.0)
		_orbit_vehicle_y_current = lerpf(_orbit_vehicle_y_current, vehicle_position.y, vertical_alpha)
	return Vector3(vehicle_position.x, _orbit_vehicle_y_current, vehicle_position.z)


func _update_fpv_camera(delta: float, state: RefCounted) -> void:
	if _fpv_camera == null:
		return
	var vehicle_position: Vector3 = state.get("position")
	var vehicle_basis: Basis = state.get("basis")
	var back: Vector3 = ChaseCameraMath.rod_back(vehicle_basis, _fpv_back_current)
	var up: Vector3 = ChaseCameraMath.rod_up(vehicle_basis, back, _fpv_up_current, GameConfig.cam_gimbal_up_smooth)
	var forward: Vector3 = -back
	var followed_position: Vector3 = _smoothed_fpv_follow_position(vehicle_position, delta)
	_fpv_back_current = back
	_fpv_up_current = up
	_fpv_camera.global_position = followed_position + forward * GameConfig.fpv_cam_forward + up * GameConfig.fpv_cam_height
	_fpv_camera.look_at(followed_position + forward * GameConfig.fpv_cam_look_ahead + up * GameConfig.fpv_cam_look_height, up)
	_fpv_camera.fov = GameConfig.fpv_cam_fov
	_fpv_camera.current = _camera_mode == CAMERA_MODE_FPV


func _smoothed_fpv_follow_position(vehicle_position: Vector3, delta: float) -> Vector3:
	if not _fpv_camera_initialized:
		_fpv_vehicle_y_current = vehicle_position.y
		_fpv_camera_initialized = true
	else:
		var vertical_alpha: float = clampf(GameConfig.cam_vertical_follow_softness * delta, 0.0, 1.0)
		_fpv_vehicle_y_current = lerpf(_fpv_vehicle_y_current, vehicle_position.y, vertical_alpha)
	return Vector3(vehicle_position.x, _fpv_vehicle_y_current, vehicle_position.z)


class TitleCardHud:
	extends CanvasLayer

	const LAYER: int = 13

	var _panel: Control = null


	func _ready() -> void:
		layer = LAYER
		_panel = _TitleCardPanel.new()
		_panel.name = "TitleCardPanel"
		_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(_panel)


	func dismiss() -> void:
		if _panel != null:
			_panel.dismiss()


	func notify_world_ready() -> void:
		if _panel != null:
			_panel.notify_world_ready()


	class _TitleCardPanel:
		extends Control

		const TITLE_TEXT: String = "Cedar Hollow"
		const SUBTITLE_TEXT: String = "LOWER ZION CANYON"
		const TITLE_FONT_SIZE: int = 54
		const SUBTITLE_FONT_SIZE: int = 18
		const LOCATION_TEXT: String = "Zion National Park, Utah"
		const LOCATION_FONT_SIZE: int = 12
		const LOCATION_SUBTITLE_GAP: float = 8.0
		const LOCATION_COLOR: Color = Color(0.75, 0.55, 0.22, 0.70)
		const TITLE_SUBTITLE_GAP: float = 12.0
		const TITLE_COLOR: Color = Color(0.96, 0.66, 0.32, 0.96)
		const SUBTITLE_COLOR: Color = Color(0.93, 0.78, 0.50, 0.82)
		const SHADOW_COLOR: Color = Color(0.08, 0.05, 0.03, 0.52)
		const SHADOW_OFFSET: Vector2 = Vector2(0.0, 2.0)
		const COVER_COLOR: Color = Color(0.06, 0.05, 0.05, 1.0)

		var _elapsed: float = 0.0
		var _alpha: float = 1.0
		var _fading: bool = false
		var _world_ready: bool = false


		func dismiss() -> void:
			_world_ready = true
			_fading = true


		func notify_world_ready() -> void:
			if _world_ready:
				return
			_world_ready = true
			queue_redraw()


		func _process(delta: float) -> void:
			if _alpha <= 0.0:
				visible = false
				return
			if not _world_ready:
				queue_redraw()
				return
			if not _fading:
				_elapsed += delta
				if _elapsed >= GameConfig.title_card_display_seconds:
					_fading = true
			if _fading:
				_alpha = maxf(_alpha - delta / maxf(GameConfig.title_card_fade_seconds, 0.001), 0.0)
			queue_redraw()


		func _draw() -> void:
			if _alpha <= 0.0:
				return
			draw_rect(Rect2(Vector2.ZERO, size), _with_alpha(COVER_COLOR))
			var font: Font = get_theme_default_font()
			var title_size: Vector2 = font.get_string_size(TITLE_TEXT, HORIZONTAL_ALIGNMENT_CENTER, 0.0, TITLE_FONT_SIZE)
			var subtitle_size: Vector2 = font.get_string_size(SUBTITLE_TEXT, HORIZONTAL_ALIGNMENT_CENTER, 0.0, SUBTITLE_FONT_SIZE)
			var location_size: Vector2 = font.get_string_size(LOCATION_TEXT, HORIZONTAL_ALIGNMENT_CENTER, 0.0, LOCATION_FONT_SIZE)
			var block_height: float = title_size.y + TITLE_SUBTITLE_GAP + subtitle_size.y + LOCATION_SUBTITLE_GAP + location_size.y
			var center: Vector2 = size * 0.5
			var title_pos: Vector2 = Vector2(center.x, center.y - block_height * 0.5)
			var subtitle_pos: Vector2 = Vector2(center.x, title_pos.y + title_size.y + TITLE_SUBTITLE_GAP)
			_draw_centered_string(font, TITLE_TEXT, title_pos + SHADOW_OFFSET, TITLE_FONT_SIZE, _with_alpha(SHADOW_COLOR))
			_draw_centered_string(font, SUBTITLE_TEXT, subtitle_pos + SHADOW_OFFSET, SUBTITLE_FONT_SIZE, _with_alpha(SHADOW_COLOR))
			_draw_centered_string(font, TITLE_TEXT, title_pos, TITLE_FONT_SIZE, _with_alpha(TITLE_COLOR))
			_draw_centered_string(font, SUBTITLE_TEXT, subtitle_pos, SUBTITLE_FONT_SIZE, _with_alpha(SUBTITLE_COLOR))
			var location_pos: Vector2 = Vector2(center.x, subtitle_pos.y + subtitle_size.y + LOCATION_SUBTITLE_GAP)
			_draw_centered_string(font, LOCATION_TEXT, location_pos + SHADOW_OFFSET, LOCATION_FONT_SIZE, _with_alpha(SHADOW_COLOR))
			_draw_centered_string(font, LOCATION_TEXT, location_pos, LOCATION_FONT_SIZE, _with_alpha(LOCATION_COLOR))


		func _draw_centered_string(font: Font, text: String, baseline_pos: Vector2, font_size: int, color: Color) -> void:
			var text_size: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, 0.0, font_size)
			draw_string(
				font,
				Vector2(baseline_pos.x - text_size.x * 0.5, baseline_pos.y),
				text,
				HORIZONTAL_ALIGNMENT_LEFT,
				0.0,
				font_size,
				color
			)


		func _with_alpha(color: Color) -> Color:
			return Color(color.r, color.g, color.b, color.a * clampf(_alpha, 0.0, 1.0))
