class_name CedarHollowScene
extends Node3D

const TerrainBuilderScript: GDScript = preload("res://systems/world/terrain_builder.gd")
const FeatureVisualBuilderScript: GDScript = preload("res://systems/render/feature_visual_builder.gd")


func _ready() -> void:
	TerrainBuilderScript.build_cedar_hollow(self)
	FeatureVisualBuilderScript.build_cedar_hollow(self)
