class_name VehicleState
extends RefCounted

const VehicleContaminationStateScript: GDScript = preload("res://systems/vehicle/vehicle_contamination_state.gd")

var position: Vector3 = Vector3.ZERO
var basis: Basis = Basis.IDENTITY
var linear_velocity: Vector3 = Vector3.ZERO
var angular_velocity: Vector3 = Vector3.ZERO
var on_ground: bool = false
var is_flipped: bool = false
var motor_rpm: float = 0.0
var wheel_contact: Array[bool] = [false, false, false, false]
var wheel_surface: Array[StringName] = [&"", &"", &"", &""]
var wheel_hit_point: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
var contamination: RefCounted = VehicleContaminationStateScript.new()


func speed() -> float:
	return linear_velocity.length()
