class_name VehicleController
extends Node3D

const VehicleStateScript: GDScript = preload("res://systems/vehicle/vehicle_state.gd")


func apply_input(_input: VehicleInput) -> void:
	push_error("VehicleController.apply_input not implemented")


func get_state() -> VehicleState:
	push_error("VehicleController.get_state not implemented")
	return VehicleStateScript.new()


func reset_to(_spawn: Transform3D) -> void:
	push_error("VehicleController.reset_to not implemented")


func self_right() -> void:
	push_error("VehicleController.self_right not implemented")
