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

const BLAZE_BACKING_COLOR: Color = Color(0.035, 0.028, 0.018)
const BLAZE_STRIPE_COLOR: Color = Color(1.0, 0.92, 0.42)
const BLAZE_ARROW_COLOR: Color = Color(1.0, 0.34, 0.08)
const BLAZE_BACKING_SIZE: Vector2 = Vector2(0.26, 0.18)
const BLAZE_STRIPE_SIZE: Vector2 = Vector2(0.19, 0.048)
const BLAZE_FORWARD_OFFSET: float = -0.045


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
		Vector3(-4.68, 0.0, -2.55),
		Vector3(-4.62, 0.0, -6.62),
		Vector3(4.68, 0.0, -3.42),
		Vector3(4.62, 0.0, -7.0)
	]
	var rotations: Array[Vector3] = [
		Vector3(0.0, 80.0, 0.0),
		Vector3(0.0, 72.0, 0.0),
		Vector3(0.0, -82.0, 0.0),
		Vector3(0.0, -72.0, 0.0)
	]
	for i in range(mini(EXPECTED_TRAIL_BLAZES, positions.size())):
		var blaze: Node3D = _instance(parent, TrailBlazeScene, "trail_blaze_" + str(i + 1), positions[i], rotations[i], Vector3.ONE)
		_add_blaze_readability_markers(blaze)
		_apply_visibility_range(blaze, GameConfig.vis_range_scatter)


static func _instance(parent: Node3D, scene: PackedScene, node_name: String, position: Vector3, rotation: Vector3, scale: Vector3) -> Node3D:
	var instance: Node3D = scene.instantiate() as Node3D
	if instance == null:
		push_error("BoundaryVisualBuilder: failed to instantiate " + node_name)
		return null
	instance.name = node_name
	instance.position = position
	instance.rotation_degrees = rotation
	instance.scale = scale
	parent.add_child(instance)
	_apply_visibility_range(instance, GameConfig.vis_range_scatter)
	return instance


static func _add_blaze_readability_markers(parent: Node3D) -> void:
	if parent == null:
		return
	_add_blaze_quad(parent, "contrast_backing", BLAZE_BACKING_SIZE, Vector3(0.0, 0.38, BLAZE_FORWARD_OFFSET - 0.004), BLAZE_BACKING_COLOR)
	_add_blaze_quad(parent, "center_stripe", BLAZE_STRIPE_SIZE, Vector3(0.0, 0.39, BLAZE_FORWARD_OFFSET - 0.008), BLAZE_STRIPE_COLOR)
	_add_blaze_chevron(parent)


static func _add_blaze_quad(parent: Node3D, node_name: String, size: Vector2, position: Vector3, color: Color) -> void:
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.name = node_name
	var mesh: QuadMesh = QuadMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.position = position
	mesh_instance.rotation_degrees = Vector3(0.0, 180.0, 0.0)
	mesh_instance.material_override = _make_unshaded_material("trail_blaze_" + node_name, color)
	mesh_instance.visibility_range_end = GameConfig.vis_range_scatter
	parent.add_child(mesh_instance)


static func _add_blaze_chevron(parent: Node3D) -> void:
	_add_blaze_chevron_arm(parent, "arrow_left_arm", Vector3(-0.036, 0.305, BLAZE_FORWARD_OFFSET - 0.012), 32.0)
	_add_blaze_chevron_arm(parent, "arrow_right_arm", Vector3(0.036, 0.305, BLAZE_FORWARD_OFFSET - 0.012), -32.0)


static func _add_blaze_chevron_arm(parent: Node3D, node_name: String, position: Vector3, roll_degrees: float) -> void:
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.name = node_name
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3(0.028, 0.105, 0.012)
	mesh_instance.mesh = mesh
	mesh_instance.position = position
	mesh_instance.rotation_degrees = Vector3(0.0, 180.0, roll_degrees)
	mesh_instance.material_override = _make_unshaded_material("trail_blaze_arrow", BLAZE_ARROW_COLOR)
	mesh_instance.visibility_range_end = GameConfig.vis_range_scatter
	parent.add_child(mesh_instance)


static func _apply_visibility_range(parent: Node, visibility_range_end: float) -> void:
	if parent == null:
		return
	var geometry_instance: GeometryInstance3D = parent as GeometryInstance3D
	if geometry_instance != null:
		geometry_instance.visibility_range_end = visibility_range_end
	for child: Node in parent.get_children():
		_apply_visibility_range(child, visibility_range_end)


static func _make_unshaded_material(resource_name: String, albedo: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.resource_name = resource_name
	material.albedo_color = albedo
	material.roughness = 0.82
	material.metallic = 0.0
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material
