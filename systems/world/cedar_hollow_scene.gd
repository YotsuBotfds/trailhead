class_name CedarHollowScene
extends Node3D

const TerrainBuilderScript: GDScript = preload("res://systems/world/terrain_builder.gd")


func _ready() -> void:
	TerrainBuilderScript.build_cedar_hollow(self)
