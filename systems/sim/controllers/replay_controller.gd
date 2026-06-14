class_name ReplayController
extends RefCounted

const VehicleInputScript: GDScript = preload("res://systems/vehicle/vehicle_input.gd")

var _done: bool = true


func configure_empty() -> void:
	_done = true


func next_input(_state: RefCounted) -> RefCounted:
	return VehicleInputScript.new()


func is_done() -> bool:
	return _done

