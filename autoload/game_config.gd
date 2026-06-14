extends Node

const PHYSICS_TICKS_PER_SECOND: int = 60
const FIXED_DT: float = 1.0 / 60.0
const UNITS_PER_METER: float = 1.0

var chassis_mass: float = 1.5
var center_of_mass_offset: Vector3 = Vector3(0.0, -0.02, 0.0)
var motor_torque: float = 6.0
var max_speed: float = 8.0
var brake_force: float = 4.0
var brake_damping_per_tick: float = 0.08
var ebrake_factor: float = 0.4
var lateral_grip_force: float = 3.0
var steer_limit_deg: float = 28.0
var steer_rate_deg: float = 90.0
var steer_yaw_torque: float = 0.75
var air_pitch_torque: float = 2.0
var launch_wheelie_torque: float = 0.03
var launch_wheelie_min_throttle: float = 0.95
var launch_wheelie_max_steer: float = 0.15
var launch_wheelie_speed_max: float = 0.7
var self_right_impulse: float = 5.0

var susp_rest_length: float = 0.06
var susp_travel: float = 0.05
var susp_stiffness: float = 30.0
var susp_damping: float = 4.0
var wheel_radius: float = 0.03

var default_friction: float = 1.0
var default_rolling_drag: float = 0.1
var default_slip: float = 0.0
var surface_rolling_drag_force: float = 2.5
var surface_bog_drag_force: float = 6.0
var surface_min_lateral_grip: float = 0.15

var cam_height: float = 0.12
var cam_distance: float = 0.35
var cam_spring: float = 12.0
var cam_damping: float = 2.0
var cam_look_ahead: float = 0.15
var cam_fov_base: float = 60.0
var cam_fov_speed_gain: float = 12.0
var cam_pitch_deg: float = -6.0

var dusk_sun_rotation_degrees: Vector3 = Vector3(-34.0, -48.0, 0.0)
var dusk_sun_energy: float = 2.8
var dusk_sun_color: Color = Color(1.0, 0.78, 0.52)
var dusk_background_color: Color = Color(0.58, 0.46, 0.36)
var dusk_ambient_color: Color = Color(0.42, 0.35, 0.32)
var dusk_ambient_energy: float = 0.35
var dusk_fog_density: float = 0.018
var dusk_fog_light_color: Color = Color(0.78, 0.57, 0.38)

var audio_mix_rate: float = 22050.0
var audio_buffer_length: float = 0.08
var audio_motor_base_hz: float = 90.0
var audio_motor_speed_hz_gain: float = 32.0
var audio_motor_volume: float = 0.045
var audio_tire_base_hz: float = 260.0
var audio_tire_volume: float = 0.025
var audio_tire_speed_volume_gain: float = 0.004
var audio_tire_gain_gravel: float = 1.1
var audio_tire_gain_dirt: float = 0.8
var audio_tire_gain_grass: float = 0.45
var audio_tire_gain_mud: float = 1.35
var audio_tire_gain_rock: float = 1.25
var audio_tire_gain_stone: float = 1.15
var audio_tire_gain_wood: float = 0.9
var audio_tire_pitch_gravel: float = 1.2
var audio_tire_pitch_dirt: float = 0.95
var audio_tire_pitch_grass: float = 0.6
var audio_tire_pitch_mud: float = 0.42
var audio_tire_pitch_rock: float = 1.35
var audio_tire_pitch_stone: float = 1.55
var audio_tire_pitch_wood: float = 1.05

var stuck_window_ticks: int = 180
var stuck_min_progress: float = 0.05
var max_flipped_ticks: int = 300
var flat_ground_size: Vector3 = Vector3(12.0, 0.1, 12.0)
var flat_ground_center: Vector3 = Vector3(2.0, -0.05, 0.0)
var flat_probe_bounds_min: Vector3 = Vector3(-3.5, -1.0, -6.0)
var flat_probe_bounds_max: Vector3 = Vector3(7.5, 2.0, 6.0)
var surface_strip_size: Vector3 = Vector3(3.0, 0.1, 2.2)
var surface_strip_start_z: float = 0.0
var surface_strip_stride_z: float = 2.2
var surface_probe_ticks: int = 160
var surface_probe_throttle: float = 0.9
var surface_probe_steer: float = 0.35
var surface_probe_steer_start_tick: int = 120
var surface_probe_warmup_ticks: int = 20
var surface_probe_bounds_min: Vector3 = Vector3(-2.0, -1.0, -9.5)
var surface_probe_bounds_max: Vector3 = Vector3(2.0, 2.0, 1.5)
var surface_probe_min_ticks_per_surface: int = 4
var surface_probe_min_mud_speed_delta_drop: float = 0.05
var surface_probe_min_wet_stone_slip_gain: float = 2.0
var drift_probe_accel_ticks: int = 55
var drift_probe_ebrake_ticks: int = 85
var drift_probe_recover_ticks: int = 20
var drift_probe_accel_throttle: float = 0.8
var drift_probe_ebrake_throttle: float = 0.65
var drift_min_peak_slip_angle_deg: float = 12.0
var drift_min_yaw_rate: float = 0.8
var drift_min_ebrake_ticks: int = 30
var drift_min_speed: float = 0.5
var wheelie_probe_ticks: int = 70
var wheelie_min_peak_pitch_deg: float = 8.0
var wheelie_min_front_air_rear_contact_ticks: int = 6

var pd_waypoint_default_min_throttle: float = 0.15
var pd_waypoint_default_steer_throttle_drop: float = 0.55
var pd_waypoint_min_throttle: float = 0.25
var pd_waypoint_steer_throttle_drop: float = 0.75
var pd_waypoint_air_throttle: float = 0.05
var pd_waypoint_intermediate_radius: float = 0.45

var default_landmark_radius: float = 0.4


func get_fov_for_speed(speed: float) -> float:
	var t: float = clampf(speed / maxf(max_speed, 0.001), 0.0, 1.0)
	return cam_fov_base + cam_fov_speed_gain * t
