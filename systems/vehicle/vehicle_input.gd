class_name VehicleInput
extends RefCounted

var throttle: float = 0.0
var steer: float = 0.0
var brake: float = 0.0
var ebrake: bool = false
var self_right: bool = false


func clear() -> void:
	throttle = 0.0
	steer = 0.0
	brake = 0.0
	ebrake = false
	self_right = false

