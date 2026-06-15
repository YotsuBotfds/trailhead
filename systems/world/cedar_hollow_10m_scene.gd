class_name CedarHollow10mScene
extends Node3D

const TerrainBuilderScript: GDScript = preload("res://systems/world/terrain_builder.gd")

@export var host_preview_vehicle: bool = true


func _ready() -> void:
	TerrainBuilderScript.build_cedar_hollow_10m(self)
	_configure_preview_vehicle()


func _configure_preview_vehicle() -> void:
	var preview_vehicle: Node = get_node_or_null("Vehicle")
	if preview_vehicle == null:
		return
	if not host_preview_vehicle:
		remove_child(preview_vehicle)
		preview_vehicle.queue_free()
		return
	preview_vehicle.call("reset_to", TerrainBuilderScript.cedar_hollow_10m_spawn_transform())
