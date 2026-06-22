extends Node

const PHYSICS_TICKS_PER_SECOND: int = 120
const FIXED_DT: float = 1.0 / float(PHYSICS_TICKS_PER_SECOND)
const UNITS_PER_METER: float = 1.0
const GRAVITY_MAGNITUDE: float = 9.8
const GRAVITY_VECTOR: Vector3 = Vector3.DOWN * GRAVITY_MAGNITUDE
const ZION_BAKE_SPEC_VERSION: String = "1.0.0-zion-1m"
const ZION_CORRIDOR_UTM_ORIGIN_E: float = 322481.824656
const ZION_CORRIDOR_UTM_ORIGIN_N: float = 4117712.509121
const ZION_CORRIDOR_UTM_MAX_E: float = 327921.583866
const ZION_CORRIDOR_UTM_MAX_N: float = 4123371.026063
const ZION_CORRIDOR_TILE_COLS: int = 55
const ZION_CORRIDOR_TILE_ROWS: int = 57
const ZION_SURFACE_ID_WATER: int = 1
const ZION_SURFACE_ID_ROCK: int = 2
const ZION_SURFACE_ID_FOREST: int = 3
const ZION_SURFACE_ID_LOOSE: int = 4
const ZION_SURFACE_ID_GRASS: int = 5
const ZION_SURFACE_ID_PAVEMENT: int = 6
const STREAM_TILE_SIZE_M: float = 100.0
const STREAM_ACTIVE_RADIUS: int = 3
const STREAM_PREFETCH_RADIUS: int = 4
const STREAM_PREFETCH_TRAVEL_LOOKAHEAD_CELLS: int = 2
const STREAM_PREFETCH_TRAVEL_MIN_DISTANCE_M: float = 0.05
const STREAM_TILE_DATA_BASE: String = "res://data/regions/"
const streaming_collision_freeze_max_ticks: int = 600
const DIRECTIONAL_SHADOW_ORTHOGONAL: int = 0
const DIRECTIONAL_SHADOW_PARALLEL_2_SPLITS: int = 1
const DIRECTIONAL_SHADOW_PARALLEL_4_SPLITS: int = 2
# 3D scaling modes mirror Viewport.Scaling3DMode exactly (Godot 4.6). Referenced
# via the Viewport enum so a 4.x rename is a compile error, not a silent miss.
const SCALING_3D_MODE_BILINEAR: int = Viewport.SCALING_3D_MODE_BILINEAR
const SCALING_3D_MODE_FSR: int = Viewport.SCALING_3D_MODE_FSR
const SCALING_3D_MODE_FSR2: int = Viewport.SCALING_3D_MODE_FSR2

var render_frame_cap_enabled: bool = true
var render_max_fps: int = 60
var render_visual_tile_commits_per_frame: int = 2
var render_visual_foliage_subcommits_per_frame: int = 16
var stream_collision_activations_per_tick: int = 3
var stream_collision_prebuild_per_tick: int = 1
var stream_collision_evictions_per_tick: int = 3
var stream_spawn_no_fall_probe_ticks: int = 840
var render_visual_tile_frees_per_frame: int = 2
# --- Render quality baseline (GLM perf-opt): explicit, GameConfig-driven 3D
# scaling + temporal AA. CedarHollowHost._apply_render_quality() pushes these to
# the game viewport once in _ready(). DEFAULT IS FSR1 (spatial), NOT FSR2:
# measured on Apple Silicon (Godot 4.6.1, Metal), FSR2's temporal pass costs
# ~5-6 ms/frame vs bilinear at equal scale and falls below the 45 fps floor
# under load, while FSR1 ties bilinear for cost yet sharpens the 0.65 upscale for
# free (a net fidelity win). The scale (0.65) -- not the mode -- is what banks
# the pixel savings; it is pinned by the dynamic-resolution band.
# render_scaling_3d_scale is the BASELINE; RenderDynamicResolutionController
# re-pins scaling_3d_scale to its min/max band every frame, so to move the
# steady-state scale also set render_dynamic_resolution_min_scale/_max_scale.
# Flip render_scaling_3d_mode to SCALING_3D_MODE_FSR2 for max fidelity when GPU
# budget allows; use_taa stays true (FSR2 needs its velocity buffer; headless
# visual inspectors assert it).
var render_scaling_3d_mode: int = SCALING_3D_MODE_FSR
# Native 1.0 baseline (Phase 4 display fix): the owner-confirmed target is crisp
# 1080p native. The dynamic-resolution controller (below) re-pins scale each
# frame, so the steady-state band is min..max; both are 1.0 here = native at
# rest, with the band left as a fallback hook (loosen min if 1080p drops frames
# on a given machine). project.godot's scaling_3d/scale mirrors this at 1.0.
var render_scaling_3d_scale: float = 1.0
var render_use_taa: bool = true
var render_dynamic_resolution_enabled: bool = true
# min below 1.0 so the controller can still drop under load (fallback); max=1.0
# so the steady-state/rest target is native 1080p.
var render_dynamic_resolution_min_scale: float = 0.85
var render_dynamic_resolution_max_scale: float = 1.0
var render_dynamic_resolution_step_down: float = 0.03
var render_dynamic_resolution_step_up: float = 0.01
var render_dynamic_resolution_ema_alpha: float = 0.18
var render_dynamic_resolution_downscale_ratio: float = 1.08
var render_dynamic_resolution_upscale_ratio: float = 0.82
var render_dynamic_resolution_warmup_frames: int = 8
var render_dynamic_resolution_adjust_frames: int = 3
var chassis_mass: float = 1.5
var chassis_collision_size: Vector3 = Vector3(0.18, 0.06, 0.30)
var chassis_collision_margin: float = 0.002
var center_of_mass_offset: Vector3 = Vector3(0.0, -0.04, 0.0)
var wheel_half_track: float = 0.095
var wheel_half_base: float = 0.10
var max_speed: float = 8.0
var v_stick: float = 0.15
var hold_static_mu_scale: float = 1.15
var hold_kinetic_mu_scale: float = 0.85
var brake_damping_per_second: float = 4.8
var ebrake_factor: float = 0.15
var lateral_grip_force: float = 1.0
var steer_limit_deg: float = 28.0
var steer_yaw_torque: float = 1.35
var steer_max_yaw_rate: float = 3.0
var steer_speed_half: float = 0.65
var steer_high_speed_falloff: float = 0.0
var steer_reverse_velocity_threshold: float = 0.08
var steer_inplace_yaw_rate_max: float = 0.24
var steer_yaw_damping: float = 0.35
var steer_low_speed_pivot_scale: float = 0.08
var anti_roll_stiffness: float = 6.0
# Deliberate feel value pending owner playtest signoff; not a 120 Hz artifact.
var launch_wheelie_torque: float = 0.82
var launch_wheelie_min_throttle: float = 0.95
var launch_wheelie_max_steer: float = 0.15
var launch_wheelie_speed_max: float = 0.7
var self_right_lift: float = 0.12
var self_right_min_upright_dot: float = 0.0
var self_right_stable_upright_dot: float = 0.55
var self_right_stable_contact_count: int = 3
var self_right_forward_epsilon: float = 0.001
var self_right_heading_tolerance_deg: float = 8.0
var self_right_velocity_retention: float = 0.25
var recover_to_trail_enabled: bool = true
var recover_radius: float = 0.4
var recover_hold_ticks: int = 36
var recover_stuck_window_ticks: int = 240
var recover_min_progress: float = 0.03
var recover_lift: float = 0.12
var recover_speed_retention: float = 0.2
var recover_min_throttle: float = 0.2
var recover_event_min_displacement: float = 0.025
var recover_tag_cue_enabled: bool = false
var motor_rpm_speed_scale: float = 100.0

var photo_hold_ticks: int = 24
var photo_max_speed_mps: float = 0.08
var photo_freeze_render_frames: int = 6
var logbook_route_seed_base: int = 36
var pace_clock_display_ticks_per_second: int = 120
var egg_default_trigger_radius_m: float = 0.3
var egg_default_dwell_ticks: int = 0
var egg_mud_key_threshold: float = 0.55
var egg_buried_receiver_dwell_ticks: int = 360
var egg_frequency_spot_count: int = 4
var egg_golden_run_tolerance_m: float = 0.12
var egg_dev_line_ghost_fade_ticks: int = 360

var susp_rest_length: float = 0.010
var susp_travel: float = 0.012
var susp_stiffness: float = 9.5
var susp_damping: float = 7.5
var susp_damping_force_ratio: float = 0.6
var susp_contact_angular_velocity_weight: float = 0.35
var susp_ray_length_headroom: float = 0.0
var susp_last_good_contact_ticks: int = 0
# Calibrated to the GLB wheel mesh (assets/models/vehicle/rc_buggy.glb, mesh
# `wheel_tire` POSITION accessor min/max X/Z = ±0.03765). The old 0.03 constant
# was ~7.65 mm short of the real tire radius, so every wheel ray was that much
# too short and the visual chassis dropped to compensate — visible as the tires
# sinking 7.65 mm through the ground. Mesh-as-truth: the GLB is the authority
# (see tools/check_glb.py wheel-radius contract + the de-circularized socket
# assertion in the render inspectors, both read the accessor min/max directly).
var wheel_radius: float = 0.03765

var default_friction: float = 1.0
var default_rolling_drag: float = 0.1
var default_slip: float = 0.0
var traction_base_force: float = 7.5
var traction_grip_force_ceiling_scale: float = 1.0
var offtrail_drag_relief: float = 1.0
var surface_rolling_drag_force: float = 2.5
var surface_bog_drag_force: float = 6.0
var surface_min_lateral_grip: float = 0.15
var default_bog_threshold: float = 0.2
var vehicle_contamination_pickup_per_second: float = 4.8
var vehicle_contamination_decay_per_second: float = 0.72
var vehicle_residue_visible_epsilon: float = 0.001
var vehicle_residue_mud_visual_alpha: float = 0.58
var vehicle_residue_dust_visual_alpha: float = 0.34
var vehicle_residue_wetness_visual_alpha: float = 0.42
var vehicle_visual_chassis_drop: float = 0.0
var vehicle_visual_chassis_wheel_socket_max_gap: float = 0.036
var wheel_visual_max_steer_deg: float = 28.0
var vehicle_visual_body_lean_max_deg: float = 5.0
var vehicle_visual_body_lean_spring: float = 42.0
var vehicle_visual_body_lean_damping: float = 11.0
var vehicle_visual_body_pitch_accel_gain: float = 0.010
var vehicle_visual_body_roll_steer_gain: float = 0.040
var vehicle_visual_body_roll_lateral_accel_gain: float = 0.008
var vehicle_visual_antenna_max_deg: float = 10.0
var vehicle_visual_antenna_spring: float = 54.0
var vehicle_visual_antenna_damping: float = 9.0
var vehicle_visual_antenna_speed_lean_gain: float = 0.012
var vehicle_visual_antenna_accel_gain: float = 0.018
var vehicle_visual_antenna_landing_gain: float = 0.010
var vehicle_residue_mud_color: Color = Color(0.17, 0.10, 0.05)
var vehicle_residue_dust_color: Color = Color(0.66, 0.55, 0.36)
var vehicle_residue_wetness_color: Color = Color(0.52, 0.62, 0.66)

var grass_clump_count: int = 72
var grass_blades_per_clump: int = 5
var grass_clump_radius: float = 0.30
var grass_occluder_band_count: int = 16
var foliage_grass_scrub_lod0_scale: Vector3 = Vector3(0.72, 0.90, 0.72)
var foliage_grass_scrub_lod1_scale: Vector3 = Vector3(0.62, 0.54, 0.62)
var scrub_density_bench_shrub: float = 0.90
var scrub_density_packed_gravel: float = 0.60
var scrub_density_paved_road: float = 0.75
var scrub_density_wet_stone: float = 0.12
var scrub_density_mud: float = 0.12
var riparian_grass_density: float = 0.84
var riparian_willow_density: float = 0.42
var riparian_cottonwood_density: float = 0.24
var boulder_density_packed_gravel: float = 0.08
var boulder_density_loose_rock: float = 0.14
var boulder_packed_gravel_candidate_share: float = 0.10
var boulder_loose_rock_candidate_share: float = 0.15

var golden_tick_tolerance: int = 2
var golden_position_tolerance_m: float = 0.08
var golden_velocity_tolerance_mps: float = 0.25
var golden_speed_tolerance_mps: float = 0.20
var golden_slip_tolerance_deg: float = 2.0
var golden_surface_tick_tolerance: int = 2
var golden_event_count_tolerance: int = 0
var golden_motor_rpm_tolerance: float = 10.0

var cam_height: float = 0.18
var cam_distance: float = 0.62
var cam_spring_xz: float = 9.0
var cam_yaw_spring: float = 12.0
var cam_spring_vy: float = 720.0
var cam_damping: float = 2.0
var cam_look_ahead: float = 0.65
var cam_look_turn_bias: float = 0.20
var cam_fov_base: float = 68.0
var cam_fov_speed_gain: float = 12.0
var cam_pitch_deg: float = -5.0
# Steer-coupled roll is now an ANTICIPATION term only (reduced from 3.5). The
# dominant bank is the real lateral-g lean below; this just hints the turn before
# lateral accel builds. Set 0.0 for pure accel-based bank.
var cam_roll_steer_deg: float = 1.5
# SR1: accel-driven chase-cam bank/pitch (render-only feel). The host computes real
# lateral/longitudinal accel from VehicleState.linear_velocity and passes it in; the
# rig damps these into a subtle roll (lean into slides) + pitch (nose-up under accel,
# nose-down under brake). Caps keep it golden-neutral, not a roller-coaster.
var cam_bank_lateral_gain: float = 0.8
var cam_bank_max_deg: float = 5.0
var cam_pitch_accel_gain: float = 0.35
var cam_pitch_max_deg: float = 2.0
var cam_bank_smooth: float = 8.0
var cam_gimbal_up_smooth: float = 1.0
# Stop-lock: when the vehicle is nearly stationary, FREEZE the chase camera's
# position AND orientation (not just position). The rigid-body vehicle is forced
# never-sleeping (raycast_vehicle_controller), so its basis/velocity carry
# sub-tick jitter every physics frame; the chase cam hard-follows that pose 1:1
# and the accel term divides velocity delta by ~delta (~60x noise gain), so the
# stationary cam visibly jitters. Freeze below cam_stop_lock_speed; release above
# the higher cam_stop_lock_release_speed (hysteresis) and SNAP to the current
# pose on release so the camera never lerps from a stale frozen state. Host-only:
# the sim never reads these.
var cam_stop_lock_speed: float = 0.15
var cam_stop_lock_release_speed: float = 0.25
var cam_stop_lock_yaw_speed: float = 0.05
var cam_vertical_follow_softness: float = 7.5
var orbit_cam_height: float = 0.65
var orbit_cam_distance: float = 1.05
var orbit_cam_spring: float = 10.0
var orbit_cam_look_height: float = 0.08
var orbit_cam_fov: float = 54.0
var orbit_cam_speed_deg: float = 18.0
var orbit_cam_start_yaw_deg: float = 35.0
var fpv_cam_height: float = 0.08
var fpv_cam_forward: float = 0.09
var fpv_cam_look_ahead: float = 0.55
var fpv_cam_look_height: float = 0.03
var fpv_cam_fov: float = 72.0
var cam_far: float = 2000.0
var orbit_cam_far: float = 2000.0
var fpv_cam_far: float = 2000.0
var cinematic_auto_open: bool = false
var cinematic_tour_duration_seconds: float = 42.0
var cinematic_tour_fov: float = 58.0
var cinematic_tour_far: float = 5000.0
var cinematic_tour_positions: Array[Vector3] = [
	Vector3(1548.0, 1226.0, 1548.0),
	Vector3(1518.0, 1232.0, 1488.0),
	Vector3(1438.0, 1228.0, 1320.0),
	Vector3(1306.0, 1220.0, 1028.0),
	Vector3(1168.0, 1217.0, 818.0)
]
var cinematic_tour_look_targets: Array[Vector3] = [
	Vector3(1505.0, 1255.0, 1450.0),
	Vector3(1410.0, 1268.0, 1390.0),
	Vector3(1515.0, 1278.0, 1210.0),
	Vector3(1200.0, 1252.0, 930.0),
	Vector3(1285.0, 1265.0, 900.0)
]
var minimap_size: float = 132.0
var minimap_margin: float = 16.0
var minimap_inner_padding: float = 12.0
var minimap_enabled_by_default: bool = false
var speed_hud_enabled: bool = true
var controls_hint_hud_enabled: bool = true
var controls_hint_hud_auto_dismiss_seconds: float = 16.0
var controls_hint_hud_fade_seconds: float = 0.6
var debug_overlay_enabled_by_default: bool = false
# Separate "start visible" knob so the capture/recording toolchain can force the
# overlay ON at startup (telemetry + hitch red-flash baked into the recording)
# without flipping the player-facing default. The host reads this in _ready().
var debug_overlay_start_visible: bool = false
var debug_overlay_frame_sample_count: int = 72
# Reference resolution for the debug overlay's viewport-relative scaling. The
# overlay computes a uniform scale from the shorter viewport axis over 1080 so
# its compact left-top panel reads at a consistent size across 1080p/1440p/4K
# instead of the old hard-coded pixels (which looked tiny at 4K).
var debug_overlay_reference_resolution: int = 1080
var debug_overlay_hitch_ms: float = 33.3
var debug_overlay_chunk_flash_seconds: float = 0.45
var debug_overlay_hitch_flash_seconds: float = 0.25
var title_card_enabled: bool = true
var title_card_display_seconds: float = 5.0
var title_card_fade_seconds: float = 1.5
var title_card_max_hold_seconds: float = 18.0
var minimap_route_line_width: float = 1.5
var minimap_dot_radius: float = 2.6
var minimap_player_radius: float = 4.0
var minimap_heading_length: float = 10.0

var dusk_sky_top_color: Color = Color(0.18, 0.33, 0.64, 1.0)
var dusk_sky_horizon_color: Color = Color(0.86, 0.63, 0.38, 1.0)
var dusk_sky_ground_color: Color = Color(0.36, 0.34, 0.31, 1.0)
var dusk_sky_turbidity: float = 4.2
var dusk_sky_sun_disk_scale: float = 1.7
var dusk_sky_mie_coefficient: float = 0.0075
var dusk_sky_mie_eccentricity: float = 0.86
var dusk_sun_rotation_degrees: Vector3 = Vector3(-18.0, -48.0, 0.0)
var dusk_sun_energy: float = 2.38
var dusk_sun_color: Color = Color(1.0, 0.84, 0.64)
var dusk_background_color: Color = Color(0.46, 0.50, 0.56)
var dusk_ambient_color: Color = Color(0.45, 0.49, 0.56)
var dusk_ambient_energy: float = 0.30
var dusk_fog_density: float = 0.0012
var dusk_fog_light_color: Color = Color(0.56, 0.59, 0.63)
var dawn_sky_top_color: Color = Color(0.28, 0.40, 0.62, 1.0)
var dawn_sky_horizon_color: Color = Color(0.72, 0.65, 0.55, 1.0)
var dawn_sky_ground_color: Color = Color(0.46, 0.37, 0.28, 1.0)
var dawn_sky_turbidity: float = 5.2
var dawn_sun_rotation_degrees: Vector3 = Vector3(-22.0, 42.0, 0.0)
var dawn_sun_energy: float = 1.8
var dawn_sun_color: Color = Color(1.0, 0.87, 0.66)
var dawn_background_color: Color = Color(0.42, 0.50, 0.58)
var dawn_ambient_color: Color = Color(0.48, 0.52, 0.58)
var dawn_ambient_energy: float = 0.30
var dawn_fog_density: float = 0.0040
var dawn_fog_light_color: Color = Color(0.55, 0.58, 0.62)
var atmosphere_volumetric_fog_enabled: bool = true
var atmosphere_volumetric_fog_density: float = 0.0038
var atmosphere_volumetric_fog_anisotropy: float = 0.40
var atmosphere_height_fog_density: float = 0.0045
var atmosphere_height_fog_falloff: float = 2.8
var atmosphere_grade_enabled: bool = true
var atmosphere_grade_saturation: float = 1.20
var atmosphere_grade_contrast: float = 1.16
var atmosphere_grade_brightness: float = 1.02
var atmosphere_grade_color_correction_path: String = ""
var atmosphere_auto_exposure_enabled: bool = false
var atmosphere_ssao_enabled: bool = true
var atmosphere_ssao_radius: float = 0.18
var atmosphere_ssao_intensity: float = 1.45
var atmosphere_ssao_light_affect: float = 0.38
var atmosphere_ssil_enabled: bool = false
var atmosphere_ssil_radius: float = 1.0
var atmosphere_ssil_intensity: float = 1.0
var atmosphere_ssil_sharpness: float = 0.98
var atmosphere_glow_hdr_threshold: float = 0.82
var atmosphere_glow_hdr_scale: float = 1.4
var atmosphere_glow_bloom_dusk: float = 0.06
var atmosphere_pcss_sun_angular_distance: float = 0.2
var atmosphere_pcss_shadow_blur: float = 0.20
var atmosphere_pcss_shadow_opacity: float = 0.78
var atmosphere_pcss_shadow_max_distance: float = 40.0
var atmosphere_directional_shadow_mode: int = DIRECTIONAL_SHADOW_PARALLEL_2_SPLITS
var atmosphere_directional_shadow_blend_splits: bool = false
var atmosphere_sun_volumetric_fog_energy: float = 0.82
var contact_fill_light_enabled: bool = false
var contact_fill_light_energy: float = 0.18
var contact_fill_light_range: float = 0.55
var contact_fill_light_height: float = 0.09
var contact_fill_light_color: Color = Color(1.0, 0.76, 0.48)
var dust_mote_count: int = 72
var dust_mote_field_size: Vector3 = Vector3(10.0, 2.0, 10.0)
var dust_mote_drift_speed: float = 0.05
var tilt_shift_enabled: bool = true
var tilt_shift_blur_amount: float = 0.8
var tilt_shift_band_center: float = 0.55
var tilt_shift_focus_band: float = 0.22
var tilt_shift_gradient_softness: float = 0.35
var cam_shake_max_offset: float = 0.018
var cam_shake_decay: float = 8.0
var cam_shake_landing_speed_threshold: float = 2.0
var surface_burst_max_particles: int = 50
var surface_burst_speed_threshold: float = 2.0
var surface_burst_lifetime: float = 0.80
var landing_squash_amount: float = 0.10
var landing_squash_recover_speed: float = 8.0
# --- W3-DUST: continuous wheel dust + spray feel polish (render-only).
# Per-wheel continuous GPUParticles3D emitter driven off sim state (no wall-clock).
# amount_ratio is computed each tick from SPEED (between threshold..full) times a
# per-surface INTENSITY (sand strong, pavement faint, water=spray), then tinted by
# a per-surface COLOR. Hard-accel / slide / landing add a decaying KICK boost that
# also re-fires the existing surface burst for a bigger pop. All values live-tunable.
var wheel_dust_enabled: bool = true
var wheel_dust_particles_per_wheel: int = 20
var wheel_dust_speed_threshold: float = 0.6
var wheel_dust_speed_full: float = 4.5
var wheel_dust_lifetime: float = 0.85
var wheel_dust_emission_radius: float = 0.045
var wheel_dust_kick_boost: float = 1.6
var wheel_dust_kick_decay: float = 6.0
var wheel_dust_accel_delta_threshold: float = 0.18
var wheel_dust_slide_lateral_threshold: float = 1.2
var wheel_dust_intensity_sand_wash: float = 1.0
var wheel_dust_intensity_loose_rock: float = 0.85
var wheel_dust_intensity_packed_dirt: float = 0.70
var wheel_dust_intensity_packed_gravel: float = 0.55
var wheel_dust_intensity_tall_grass: float = 0.30
var wheel_dust_intensity_slickrock_dry: float = 0.15
var wheel_dust_intensity_wood_plank: float = 0.10
var wheel_dust_intensity_paved_road: float = 0.08
var wheel_dust_intensity_wet_stone: float = 0.70
var wheel_dust_intensity_mud: float = 0.65
var wheel_dust_color_sand_wash: Color = Color(0.82, 0.68, 0.46, 0.42)
var wheel_dust_color_loose_rock: Color = Color(0.62, 0.58, 0.52, 0.42)
var wheel_dust_color_packed_dirt: Color = Color(0.66, 0.55, 0.36, 0.42)
var wheel_dust_color_packed_gravel: Color = Color(0.58, 0.55, 0.50, 0.42)
var wheel_dust_color_tall_grass: Color = Color(0.55, 0.60, 0.32, 0.42)
var wheel_dust_color_slickrock_dry: Color = Color(0.78, 0.55, 0.36, 0.42)
var wheel_dust_color_wood_plank: Color = Color(0.55, 0.40, 0.26, 0.42)
var wheel_dust_color_paved_road: Color = Color(0.50, 0.50, 0.52, 0.42)
var wheel_dust_color_wet_stone: Color = Color(0.72, 0.84, 0.88, 0.46)
var wheel_dust_color_mud: Color = Color(0.30, 0.20, 0.12, 0.50)
# --- W17-VEHICLE-JUICE: rear-wheel debris jets, pebble kicks, landing rings.
var wheel_rooster_particles_per_rear_wheel: int = 34
var wheel_rooster_lifetime: float = 0.72
var wheel_rooster_speed_threshold: float = 1.4
var wheel_rooster_speed_full: float = 7.5
var wheel_rooster_trigger_boost: float = 1.35
var wheel_rooster_emission_radius: float = 0.032
var wheel_rooster_smoke_color: Color = Color(0.82, 0.84, 0.82, 0.48)
var wheel_rooster_smoke_surface_boost: float = 1.45
var pebble_burst_particles: int = 18
var pebble_burst_lifetime: float = 0.55
var pebble_burst_speed_threshold: float = 2.4
var pebble_burst_scale: float = 0.026
var landing_ring_particles_per_wheel: int = 36
var landing_ring_lifetime: float = 0.62
var landing_ring_scale: float = 0.075
var landing_ring_speed_threshold: float = 2.0
var grass_backlight_enabled: bool = true
var grass_backlight_color: Color = Color(1.0, 0.62, 0.30)
var grass_backlight_energy: float = 0.32
var grass_wind_enabled: bool = true
var grass_wind_freeze_for_capture: bool = false
var grass_wind_strength: float = 0.010
var grass_wind_speed: float = 0.65
var grass_crush_radius: float = 0.45
var grass_crush_strength: float = 0.75
var buggy_clearcoat_enabled: bool = true
var buggy_clearcoat: float = 0.70
var buggy_clearcoat_roughness: float = 0.40
# --- Buggy detail polish (W6-VEHICLE): subtle material upgrade so the chassis
# body + roll cage don't read flat under golden-hour light. Keeps the existing
# palette (albedo) intact; the clearcoat layer above remains in charge of gloss.
# Edge wear would need a shader/texture (out of scope); these StandardMaterial3D
# levers (metallic flake in the paint, rim light, cage metalness) are the cheap
# headless-safe path to "not flat".
var buggy_body_metallic: float = 0.18
var buggy_body_rim_enabled: bool = true
var buggy_body_rim_energy: float = 0.35
var buggy_cage_metallic: float = 0.65
var buggy_cage_roughness: float = 0.42
var brake_light_energy: float = 1.8
# --- Headlight tunables (Q46): promoted from procedural_buggy_visual.gd local
# consts so the golden-hour cones are live-tunable. Range tightened from 6.0 m
# to 4.0 m for a 1:10 RC-scale read (searchlight -> car-length throw). Default
# ON; the L-key toggle is deferred (needs the host).
var headlight_emission_color: Color = Color(1.0, 0.949, 0.847)
var headlight_emission_energy: float = 1.6
var headlight_light_color: Color = Color(1.0, 0.949, 0.847)
var headlight_light_energy: float = 3.0
var headlight_spot_range: float = 4.0
var headlight_spot_angle_deg: float = 35.0
var headlight_pitch_deg: float = 12.0
var terrain_pom_enabled: bool = true
var terrain_pom_depth_scale: float = 0.028
var terrain_pom_min_layers: int = 4
var terrain_pom_max_layers: int = 6

# --- Terrain tire-track painter: local render window, not whole-region bounds.
var terrain_track_painter_enabled: bool = true
var terrain_track_painter_resolution: int = 512
var terrain_track_painter_pixels_per_meter: float = 8.0
var terrain_track_painter_window_meters: float = 256.0
var terrain_track_painter_max_resolution: int = 2048
var terrain_track_painter_device_max_resolution: int = 2048
var terrain_track_max_stamps: int = 256
var terrain_track_update_interval_ticks: int = 2
var terrain_track_stamp_radius: float = 0.065
var terrain_track_stamp_strength: float = 0.72
var terrain_track_decay_per_second: float = 0.008
var terrain_track_surface_mud_strength: float = 1.0
var terrain_track_surface_dust_strength: float = 0.62
var terrain_track_surface_sand_strength: float = 0.90
var terrain_track_surface_wet_strength: float = 0.55
var visual_bar_lighting_spec_version: int = 1

var audio_mix_rate: float = 22050.0
var audio_buffer_length: float = 0.08
var audio_motor_base_hz: float = 90.0
var audio_motor_speed_hz_gain: float = 32.0
var audio_motor_volume: float = 0.058
var audio_tire_base_hz: float = 260.0
var audio_tire_volume: float = 0.025
var audio_tire_speed_volume_gain: float = 0.004
var audio_ambient_wind_volume: float = 0.018
var audio_ambient_wind_base_hz: float = 68.0
var audio_ambient_bird_volume: float = 0.028
var audio_ambient_bird_hz: float = 960.0
var audio_water_center: Vector3 = Vector3(1155.0, 1197.0, 800.0)
var audio_water_audible_radius: float = 60.0
var audio_water_volume: float = 0.048
var audio_water_base_hz: float = 180.0
var audio_plank_volume: float = 0.045
var audio_plank_base_hz: float = 5.0
var audio_plank_speed_hz_gain: float = 2.4
var audio_plank_decay: float = 0.993
var audio_ambient_insect_volume: float = 0.020
var audio_ambient_insect_hz: float = 1800.0
var audio_bus_master_volume_db: float = 0.0
var audio_bus_motor_volume_db: float = 0.0
var audio_bus_tire_volume_db: float = 0.0
var audio_bus_ambient_volume_db: float = 0.0
var audio_bus_water_volume_db: float = 0.0
var audio_bus_reverb_wet: float = 0.20
var water_surface_y: float = 0.0
var water_depth_fade_distance: float = 0.45
var water_foam_edge_width: float = 0.08
var water_flow_speed: float = 0.08
var water_wave_amplitude: float = 0.015
var water_foam_normal_strength: float = 0.18
var water_foam_normal_scale: float = 18.0
var water_foam_normal_flow_speed: float = 0.06
var water_ssr_enabled: bool = true
var water_ssr_intensity: float = 0.18
var water_ssr_max_steps: int = 24
var water_ssr_step_size: float = 0.035
var water_ssr_thickness: float = 0.08
var water_shallow_color: Color = Color(0.78, 0.74, 0.58)
var water_deep_color: Color = Color(0.12, 0.18, 0.14)
var water_alpha: float = 0.65
var water_roughness: float = 0.30
var vis_range_terrain: float = 140.0
var vis_range_ground_detail: float = 14.0
var vis_range_grass: float = 35.0
var vis_range_scatter: float = 18.0
var vis_range_props: float = 22.0
var vis_range_vehicle: float = 24.0
var vis_range_water: float = 300.0
var vis_range_tracks: float = 28.0
var vis_range_dust: float = 18.0

var stuck_window_ticks: int = 360
var stuck_window_seconds: float = 3.0
var stuck_min_progress: float = 0.05
var max_flipped_ticks: int = 600
var max_flipped_seconds: float = 5.0
var flat_spawn_height: float = 0.12
var flat_target_bounds_y_min: float = -1.0
var flat_target_bounds_y_max: float = 2.0
var flat_ground_size: Vector3 = Vector3(12.0, 0.1, 16.0)
var flat_ground_center: Vector3 = Vector3(2.0, -0.05, -1.0)
var flat_probe_bounds_min: Vector3 = Vector3(-4.5, -1.0, -8.0)
var flat_probe_bounds_max: Vector3 = Vector3(7.5, 2.0, 6.0)
var real_terrain_probe_bounds_margin_xz: float = 6.0
var real_terrain_probe_bounds_margin_y: float = 25.0
var real_terrain_flat_segment_distance_m: float = 50.0
var real_terrain_flat_segment_throttle: float = 0.5
var real_terrain_flat_segment_max_ticks: int = 6000
var real_terrain_flat_segment_min_contact_ticks: int = 120
var heightmap_ramp_probe_grade_percent: float = 15.0
var heightmap_ramp_probe_size_m: float = 100.0
var heightmap_ramp_probe_grid_samples: int = 101
var heightmap_ramp_probe_spawn_z: float = 20.0
var heightmap_ramp_probe_bounds_min: Vector3 = Vector3(-6.0, -8.0, -32.0)
var heightmap_ramp_probe_bounds_max: Vector3 = Vector3(6.0, 8.0, 24.0)
var surface_strip_size: Vector3 = Vector3(10.0, 0.1, 2.2)
var surface_strip_start_z: float = 0.0
var surface_strip_stride_z: float = 2.2
var surface_probe_ticks: int = 500
var surface_probe_throttle: float = 0.9
var surface_probe_steer: float = 0.35
var surface_probe_steer_start_tick: int = 300
var surface_probe_warmup_ticks: int = 40
var surface_probe_bounds_min: Vector3 = Vector3(-8.0, -1.0, -22.0)
var surface_probe_bounds_max: Vector3 = Vector3(8.0, 2.0, 1.5)
var surface_probe_min_ticks_per_surface: int = 8
var surface_probe_min_mud_speed_delta_drop: float = 0.025
var surface_probe_min_wet_stone_slip_gain: float = 2.0
var surface_probe_min_hard_surface_delta_gain: float = 0.004
var surface_probe_min_sand_drag_delta_drop: float = 0.015
var surface_probe_min_loose_rock_slip_gain: float = 0.01
var scripted_stop_brake: float = 1.0
var hill_hold_probe_ticks: int = 180
var event_bus_coverage_probe_ticks: int = 96
var event_bus_coverage_spawn_position: Vector3 = Vector3(-1.64, 0.45, -8.28)
var event_bus_coverage_spawn_mud: float = 1.0
var hill_hold_grade_deg: float = 12.0
var hill_hold_steep_grade_deg: float = 50.0
var hill_hold_ground_size: Vector3 = Vector3(6.0, 0.1, 8.0)
var hill_hold_spawn_height: float = 0.17
var hill_hold_max_drift: float = 0.04
var hill_hold_steep_min_creep: float = 0.08
var hill_hold_steep_max_creep: float = 1.6
var hill_hold_probe_bounds_min: Vector3 = Vector3(-3.0, -2.0, -4.0)
var hill_hold_probe_bounds_max: Vector3 = Vector3(3.0, 2.0, 4.0)
var lateral_slide_accel_ticks: int = 90
var lateral_slide_steer_ticks: int = 60
var lateral_slide_settle_ticks: int = 180
var lateral_slide_throttle: float = 0.9
var lateral_slide_ebrake_throttle: float = 0.25
var lateral_slide_steer: float = 1.0
var lateral_slide_min_peak_lateral_speed: float = 0.18
var lateral_slide_max_final_lateral_speed: float = 0.08
var suspension_drop_spawn_height: float = 0.42
var suspension_drop_probe_ticks: int = 260
var suspension_drop_settle_start_tick: int = 150
var suspension_drop_min_contact_ticks: int = 80
var suspension_drop_min_peak_speed: float = 2.0
var suspension_drop_max_settle_y_amplitude: float = 0.02
var suspension_drop_max_settle_vertical_speed: float = 0.08
var resting_ride_height_probe_ticks: int = 360
var resting_ride_height_settle_start_tick: int = 240
var resting_ride_height_min_sample_ticks: int = 80
var resting_ride_height_min_y: float = 0.047
var resting_ride_height_max_y: float = 0.062
# Rest-height band shifted up ~7.65 mm vs the prior [0.040, 0.055] to track the
# calibrated wheel_radius (0.03 -> 0.03765, the real GLB wheel_tire radius). The
# buggy now rests at its correct ride height (~0.055 m) instead of 7.65 mm low;
# the 15 mm tolerance window is unchanged, only its center moved. This bound
# drives the resting_ride_height scenario predicate (sim_runner.gd); the suite
# assertion in 13_feel_control_probes.sh mirrors it. See Phase 1 of the vehicle
# visual-fixes plan.
var roll_stability_probe_ticks: int = 260
var roll_stability_side_slope_deg: float = 18.0
var roll_stability_ground_size: Vector3 = Vector3(7.0, 0.1, 10.0)
var roll_stability_spawn_height: float = 0.18
var roll_stability_probe_throttle: float = 0.65
var roll_stability_min_forward_distance: float = 1.2
var roll_stability_min_contact_ticks: int = 80
var roll_stability_min_contact_normal_tilt_deg: float = 16.0
var roll_stability_max_abs_roll_deg: float = 35.0
var roll_stability_probe_bounds_min: Vector3 = Vector3(-4.0, -1.0, -5.5)
var roll_stability_probe_bounds_max: Vector3 = Vector3(4.0, 2.0, 1.5)
var standstill_yaw_probe_ticks: int = 260
var standstill_yaw_probe_steer: float = 1.0
var standstill_yaw_probe_max_multiplier: float = 1.08
var standstill_yaw_probe_min_rate: float = 0.06
var steering_speed_probe_ticks: int = 320
var steering_speed_probe_throttle: float = 0.75
var steering_speed_probe_steer: float = 1.0
var steering_speed_probe_low_min_speed: float = 0.35
var steering_speed_probe_low_max_speed: float = 1.25
var steering_speed_probe_mid_min_speed: float = 1.75
var steering_speed_probe_mid_max_speed: float = 2.75
var steering_speed_probe_high_min_speed: float = 3.25
var steering_speed_probe_min_bucket_ticks: int = 6
var steering_speed_probe_min_high_yaw_gain: float = 0.25
var steering_speed_probe_monotone_slack: float = 0.03
var offtrail_escape_probe_ticks: int = 200
var offtrail_escape_probe_throttle: float = 1.0
var offtrail_escape_min_distance: float = 0.55
var recovery_probe_drive_ticks: int = 360
var recovery_probe_request_ticks: int = 32
var recovery_probe_throttle: float = 1.0
var recovery_trap_wall_center: Vector3 = Vector3(0.0, 0.2, -0.55)
var recovery_trap_wall_size: Vector3 = Vector3(1.2, 0.4, 0.12)
var drift_probe_accel_ticks: int = 110
var drift_probe_ebrake_ticks: int = 130
var drift_probe_recover_ticks: int = 40
var drift_probe_accel_throttle: float = 0.8
var drift_probe_ebrake_throttle: float = 0.65
var drift_probe_ebrake_steer: float = 1.0
var drift_probe_recover_throttle: float = 0.2
var drift_probe_recover_brake: float = 0.2
var drift_min_peak_slip_angle_deg: float = 12.0
var drift_min_yaw_rate: float = 0.8
var drift_min_ebrake_ticks: int = 60
var drift_min_speed: float = 0.5
var wheelie_probe_ticks: int = 140
var wheelie_probe_throttle: float = 1.0
var wheelie_min_peak_pitch_deg: float = 8.0
var wheelie_min_front_air_rear_contact_ticks: int = 12
var reverse_probe_ticks: int = 180
var reverse_probe_throttle: float = -0.65
var reverse_probe_forward_epsilon: float = 0.001
var reverse_min_ticks: int = 140
var reverse_min_distance: float = 0.45
var reverse_steer_probe_ticks: int = 180
var reverse_steer_probe_throttle: float = -0.65
var reverse_steer_probe_steer: float = 1.0
var reverse_steer_min_control_right_displacement: float = 0.04
var reverse_steer_min_reverse_distance: float = 0.35
var log_ramp_probe_ticks: int = 240
var log_ramp_probe_target: Vector3 = Vector3(1.2, 0.0, 0.5)
var log_ramp_probe_throttle: float = 0.4
var log_ramp_probe_steer_gain: float = 2.4
var log_ramp_probe_forward_epsilon: float = 0.001
var log_ramp_min_wood_ticks: int = 8
var log_ramp_min_peak_y: float = 0.115
var log_ramp_min_peak_pitch_deg: float = 2.0
var clip_descent_probe_ticks: int = 360
var clip_descent_probe_target: Vector3 = Vector3(0.0, 0.0, -5.25)
var clip_descent_probe_throttle: float = 0.9
var clip_descent_probe_steer_gain: float = 2.2
var clip_descent_min_clearance_samples: int = 80
var clip_descent_min_speed: float = 2.5
var clip_descent_min_descent: float = 0.18
var clip_descent_max_chassis_penetration: float = 0.01

var default_target_radius: float = 0.35
var pd_waypoint_kp: float = 2.0
var pd_waypoint_kd: float = 0.4
var pd_waypoint_forward_epsilon: float = 0.001
var pd_waypoint_default_min_throttle: float = 0.25
var pd_waypoint_default_steer_throttle_drop: float = 0.75
var pd_waypoint_min_throttle: float = 0.25
var pd_waypoint_steer_throttle_drop: float = 0.75
var pd_waypoint_air_throttle: float = 0.05
var pd_waypoint_intermediate_radius: float = 0.45

var default_landmark_radius: float = 0.4


func get_fov_for_speed(speed: float) -> float:
	var t: float = clampf(speed / maxf(max_speed, 0.001), 0.0, 1.0)
	return cam_fov_base + cam_fov_speed_gain * t
