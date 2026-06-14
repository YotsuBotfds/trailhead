class_name ScatterVisualBuilder
extends RefCounted

const GrassTuftScene: PackedScene = preload("res://assets/models/scatter/grass_tuft.glb")
const BoulderScene: PackedScene = preload("res://assets/models/scatter/boulder_a.glb")
const BranchScene: PackedScene = preload("res://assets/models/scatter/branch_a.glb")
const PineconeScene: PackedScene = preload("res://assets/models/scatter/pinecone.glb")
const FernClumpScene: PackedScene = preload("res://assets/models/scatter/fern_clump.glb")
const CattailScene: PackedScene = preload("res://assets/models/scatter/cattail.glb")

const EXPECTED_GRASS_TUFTS: int = 18
const EXPECTED_BOULDERS: int = 5
const EXPECTED_BRANCHES: int = 5
const EXPECTED_PINECONES: int = 8
const EXPECTED_FERN_CLUMPS: int = 6
const EXPECTED_CATTAILS: int = 5


static func build_cedar_hollow(parent: Node3D) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = "ScatterVisuals"
	parent.add_child(root)
	_add_grass(root)
	_add_boulders(root)
	_add_branches(root)
	_add_pinecones(root)
	_add_ferns(root)
	_add_cattails(root)
	return root


static func _add_grass(parent: Node3D) -> void:
	var positions: Array[Vector3] = [
		Vector3(-2.3, 0.0, -0.9),
		Vector3(-1.8, 0.0, -1.6),
		Vector3(-2.4, 0.0, -2.4),
		Vector3(-1.55, 0.0, -3.2),
		Vector3(-2.15, 0.0, -4.1),
		Vector3(-1.25, 0.0, -4.8),
		Vector3(1.15, 0.0, -0.8),
		Vector3(1.85, 0.0, -1.35),
		Vector3(2.3, 0.0, -2.05),
		Vector3(1.45, 0.0, -2.8),
		Vector3(2.1, 0.0, -3.55),
		Vector3(1.35, 0.0, -4.2),
		Vector3(2.65, 0.0, -4.85),
		Vector3(3.75, 0.0, -4.15),
		Vector3(4.25, 0.0, -5.35),
		Vector3(3.5, 0.0, -5.9),
		Vector3(4.7, 0.0, -6.35),
		Vector3(2.9, 0.0, -6.9)
	]
	for i in range(mini(EXPECTED_GRASS_TUFTS, positions.size())):
		var rotation: Vector3 = Vector3(0.0, float(i) * 37.0, 0.0)
		_instance_scatter(parent, GrassTuftScene, "grass_tuft_" + str(i + 1), positions[i], rotation, Vector3.ONE)


static func _add_boulders(parent: Node3D) -> void:
	var positions: Array[Vector3] = [
		Vector3(-2.65, 0.3, -8.5),
		Vector3(-0.85, 0.22, -8.2),
		Vector3(-1.8, 0.16, -6.75),
		Vector3(4.9, 0.0, -6.95),
		Vector3(3.55, 0.0, -6.55)
	]
	for i in range(mini(EXPECTED_BOULDERS, positions.size())):
		var scale: Vector3 = Vector3.ONE * (0.75 + float(i % 3) * 0.15)
		_instance_scatter(parent, BoulderScene, "boulder_" + str(i + 1), positions[i], Vector3(0.0, float(i) * 41.0, 0.0), scale)


static func _add_branches(parent: Node3D) -> void:
	var positions: Array[Vector3] = [
		Vector3(-1.95, 0.02, -0.35),
		Vector3(1.9, 0.02, -3.75),
		Vector3(0.95, 0.02, -5.85),
		Vector3(3.95, 0.02, -5.85),
		Vector3(-0.9, 0.02, -9.45)
	]
	for i in range(mini(EXPECTED_BRANCHES, positions.size())):
		_instance_scatter(parent, BranchScene, "branch_" + str(i + 1), positions[i], Vector3(0.0, float(i) * 29.0, 0.0), Vector3.ONE)


static func _add_pinecones(parent: Node3D) -> void:
	var positions: Array[Vector3] = [
		Vector3(-1.35, 0.02, -0.55),
		Vector3(-2.55, 0.02, -1.2),
		Vector3(1.35, 0.02, -1.55),
		Vector3(2.45, 0.02, -2.75),
		Vector3(1.55, 0.02, -4.75),
		Vector3(3.15, 0.02, -4.4),
		Vector3(4.4, 0.02, -6.0),
		Vector3(-1.9, 0.24, -8.9)
	]
	for i in range(mini(EXPECTED_PINECONES, positions.size())):
		var rotation: Vector3 = Vector3(float(i % 2) * 12.0, float(i) * 47.0, 0.0)
		_instance_scatter(parent, PineconeScene, "pinecone_" + str(i + 1), positions[i], rotation, Vector3.ONE)


static func _add_ferns(parent: Node3D) -> void:
	var positions: Array[Vector3] = [
		Vector3(2.2, 0.0, -4.65),
		Vector3(3.45, 0.0, -4.95),
		Vector3(2.75, 0.0, -6.45),
		Vector3(3.75, 0.0, -6.95),
		Vector3(4.85, 0.0, -6.65),
		Vector3(3.05, 0.0, -7.65)
	]
	for i in range(mini(EXPECTED_FERN_CLUMPS, positions.size())):
		var scale: Vector3 = Vector3.ONE * (0.8 + float(i % 3) * 0.12)
		_instance_scatter(parent, FernClumpScene, "fern_clump_" + str(i + 1), positions[i], Vector3(0.0, float(i) * 53.0, 0.0), scale)


static func _add_cattails(parent: Node3D) -> void:
	var positions: Array[Vector3] = [
		Vector3(3.95, 0.0, -6.25),
		Vector3(4.35, 0.0, -6.55),
		Vector3(4.75, 0.0, -6.9),
		Vector3(3.85, 0.0, -7.35),
		Vector3(4.45, 0.0, -7.55)
	]
	for i in range(mini(EXPECTED_CATTAILS, positions.size())):
		var scale: Vector3 = Vector3.ONE * (0.75 + float(i % 2) * 0.1)
		_instance_scatter(parent, CattailScene, "cattail_" + str(i + 1), positions[i], Vector3(0.0, float(i) * 29.0, 0.0), scale)


static func _instance_scatter(parent: Node3D, scene: PackedScene, node_name: String, position: Vector3, rotation: Vector3, scale: Vector3) -> Node3D:
	var instance: Node3D = scene.instantiate() as Node3D
	if instance == null:
		return parent
	instance.name = node_name
	instance.position = position
	instance.rotation_degrees = rotation
	instance.scale = scale
	parent.add_child(instance)
	return instance
