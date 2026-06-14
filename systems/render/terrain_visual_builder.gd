class_name TerrainVisualBuilder
extends RefCounted

const HeightmeshScene: PackedScene = preload("res://assets/models/terrain/cedar_hollow_heightmesh.glb")
const HEIGHTMESH_NAME: String = "cedar_hollow_heightmesh"


static func build_cedar_hollow(parent: Node3D) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = "TerrainVisuals"
	parent.add_child(root)

	var heightmesh: Node3D = HeightmeshScene.instantiate() as Node3D
	if heightmesh == null:
		return root
	heightmesh.name = HEIGHTMESH_NAME
	root.add_child(heightmesh)
	return root
