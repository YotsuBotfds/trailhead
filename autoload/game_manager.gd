extends Node

var active_vehicle: Node = null
var active_surface_map: Node = null


func register_vehicle(vehicle: Node) -> void:
	active_vehicle = vehicle


func register_surface_map(surface_map: Node) -> void:
	active_surface_map = surface_map

