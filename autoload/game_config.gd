extends Node

const PHYSICS_TICKS_PER_SECOND: int = 60
const FIXED_DT: float = 1.0 / 60.0
const UNITS_PER_METER: float = 1.0

var chassis_mass: float = 1.5
var center_of_mass_offset: Vector3 = Vector3(0.0, -0.02, 0.0)
var motor_torque: float = 6.0
var max_speed: float = 8.0
var brake_force: float = 4.0
var ebrake_factor: float = 0.4
var steer_limit_deg: float = 28.0
var steer_rate_deg: float = 90.0
var air_pitch_torque: float = 2.0
var self_right_impulse: float = 5.0

var susp_rest_length: float = 0.06
var susp_travel: float = 0.05
var susp_stiffness: float = 30.0
var susp_damping: float = 4.0
var wheel_radius: float = 0.03

var default_friction: float = 1.0
var default_rolling_drag: float = 0.1
var default_slip: float = 0.0

var cam_height: float = 0.12
var cam_distance: float = 0.35
var cam_spring: float = 12.0
var cam_damping: float = 2.0
var cam_look_ahead: float = 0.15
var cam_fov_base: float = 60.0
var cam_fov_speed_gain: float = 12.0
var cam_pitch_deg: float = -6.0

var stuck_window_ticks: int = 180
var stuck_min_progress: float = 0.05
var max_flipped_ticks: int = 300

var default_landmark_radius: float = 0.4


func get_fov_for_speed(speed: float) -> float:
	var t: float = clampf(speed / maxf(max_speed, 0.001), 0.0, 1.0)
	return cam_fov_base + cam_fov_speed_gain * t

