class_name BoundaryVisualBuilder
extends RefCounted

const GrassTuftScene: PackedScene = preload("res://assets/models/scatter/grass_tuft.glb")
const BoulderScene: PackedScene = preload("res://assets/models/scatter/boulder_a.glb")
const BranchScene: PackedScene = preload("res://assets/models/scatter/branch_a.glb")
const TrailBlazeScene: PackedScene = preload("res://assets/models/scatter/trail_blaze.glb")

const EXPECTED_BOUNDARY_GRASS: int = 20
const EXPECTED_BOUNDARY_BOULDERS: int = 8
const EXPECTED_BOUNDARY_BRANCHES: int = 6
const EXPECTED_TRAIL_BLAZES: int = 4


static func build_cedar_hollow(parent: Node3D) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = "BoundaryVisuals"
	parent.add_child(root)
	_add_boundary_grass(root)
	_add_boundary_boulders(root)
	_add_boundary_branches(root)
	_add_trail_blazes(root)
	return root


static func _add_boundary_grass(parent: Node3D) -> void:
	var positions: Array[Vector3] = [
		Vector3(-5.05, 0.0, 0.8),
		Vector3(-5.25, 0.0, -0.4),
		Vector3(-5.35, 0.0, -1.6),
		Vector3(-5.25, 0.0, -2.9),
		Vector3(-5.05, 0.0, -4.2),
		Vector3(-4.95, 0.0, -5.4),
		Vector3(-4.85, 0.0, -6.7),
		Vector3(-4.8, 0.0, -8.4),
		Vector3(5.1, 0.0, 0.6),
		Vector3(5.25, 0.0, -0.7),
		Vector3(5.3, 0.0, -1.9),
		Vector3(5.15, 0.0, -3.1),
		Vector3(5.35, 0.0, -4.4),
		Vector3(5.2, 0.0, -5.7),
		Vector3(5.05, 0.0, -7.1),
		Vector3(4.95, 0.0, -8.5),
		Vector3(-3.5, 0.25, -10.0),
		Vector3(-2.1, 0.34, -10.15),
		Vector3(-0.6, 0.28, -10.0),
		Vector3(1.0, 0.12, -9.95)
	]
	for i in range(mini(EXPECTED_BOUNDARY_GRASS, positions.size())):
		var scale: Vector3 = Vector3.ONE * (1.15 + float(i % 4) * 0.12)
		_instance(parent, GrassTuftScene, "boundary_grass_" + str(i + 1), positions[i], Vector3(0.0, float(i) * 31.0, 0.0), scale)


static func _add_boundary_boulders(parent: Node3D) -> void:
	var positions: Array[Vector3] = [
		Vector3(-5.15, 0.0, -0.9),
		Vector3(-5.0, 0.0, -3.7),
		Vector3(-4.65, 0.08, -8.95),
		Vector3(5.05, 0.0, -1.45),
		Vector3(5.25, 0.0, -4.95),
		Vector3(4.85, 0.0, -7.85),
		Vector3(-2.8, 0.34, -10.2),
		Vector3(0.15, 0.18, -10.05)
	]
	for i in range(mini(EXPECTED_BOUNDARY_BOULDERS, positions.size())):
		var scale: Vector3 = Vector3.ONE * (1.05 + float(i % 3) * 0.18)
		_instance(parent, BoulderScene, "boundary_boulder_" + str(i + 1), positions[i], Vector3(0.0, float(i) * 43.0, 0.0), scale)


static func _add_boundary_branches(parent: Node3D) -> void:
	var positions: Array[Vector3] = [
		Vector3(-4.9, 0.02, -2.2),
		Vector3(-4.7, 0.02, -6.0),
		Vector3(5.0, 0.02, -0.2),
		Vector3(4.85, 0.02, -3.6),
		Vector3(4.75, 0.02, -6.75),
		Vector3(-1.55, 0.31, -10.05)
	]
	for i in range(mini(EXPECTED_BOUNDARY_BRANCHES, positions.size())):
		_instance(parent, BranchScene, "boundary_branch_" + str(i + 1), positions[i], Vector3(0.0, float(i) * 37.0, 0.0), Vector3.ONE)


static func _add_trail_blazes(parent: Node3D) -> void:
	var positions: Array[Vector3] = [
		Vector3(-5.18, 0.0, -2.85),
		Vector3(-5.02, 0.0, -6.95),
		Vector3(5.12, 0.0, -3.65),
		Vector3(5.08, 0.0, -7.25)
	]
	for i in range(mini(EXPECTED_TRAIL_BLAZES, positions.size())):
		_instance(parent, TrailBlazeScene, "trail_blaze_" + str(i + 1), positions[i], Vector3(0.0, float(i) * 180.0, 0.0), Vector3.ONE)


static func _instance(parent: Node3D, scene: PackedScene, node_name: String, position: Vector3, rotation: Vector3, scale: Vector3) -> Node3D:
	var instance: Node3D = scene.instantiate() as Node3D
	if instance == null:
		return parent
	instance.name = node_name
	instance.position = position
	instance.rotation_degrees = rotation
	instance.scale = scale
	parent.add_child(instance)
	return instance
