class_name ProceduralBuggyVisual
extends RefCounted


func attach(vehicle: Node) -> void:
	var body: Node3D = vehicle.get_node_or_null("PhysicsBody") as Node3D
	if body == null or body.has_node("VisualRoot"):
		return
	var visual_root: Node3D = Node3D.new()
	visual_root.name = "VisualRoot"
	body.add_child(visual_root)
	_add_chassis(visual_root)
	_add_roll_cage(visual_root)
	_add_wheel(visual_root, "wheel_front_left", Vector3(-0.08, -0.015, -0.10))
	_add_wheel(visual_root, "wheel_front_right", Vector3(0.08, -0.015, -0.10))
	_add_wheel(visual_root, "wheel_rear_left", Vector3(-0.08, -0.015, 0.10))
	_add_wheel(visual_root, "wheel_rear_right", Vector3(0.08, -0.015, 0.10))


func _add_chassis(parent: Node3D) -> void:
	var chassis: MeshInstance3D = MeshInstance3D.new()
	chassis.name = "body"
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3(0.16, 0.055, 0.28)
	chassis.mesh = mesh
	chassis.position = Vector3(0.0, 0.0, 0.0)
	chassis.material_override = _make_material(Color(0.95, 0.16, 0.08))
	parent.add_child(chassis)

	var nose: MeshInstance3D = MeshInstance3D.new()
	nose.name = "nose"
	var nose_mesh: BoxMesh = BoxMesh.new()
	nose_mesh.size = Vector3(0.12, 0.035, 0.08)
	nose.mesh = nose_mesh
	nose.position = Vector3(0.0, 0.01, -0.18)
	nose.material_override = _make_material(Color(0.98, 0.28, 0.08))
	parent.add_child(nose)


func _add_roll_cage(parent: Node3D) -> void:
	var cage: Node3D = Node3D.new()
	cage.name = "roll_cage"
	parent.add_child(cage)
	_add_bar(cage, "cage_left", Vector3(-0.055, 0.055, -0.02), Vector3(0.012, 0.075, 0.16))
	_add_bar(cage, "cage_right", Vector3(0.055, 0.055, -0.02), Vector3(0.012, 0.075, 0.16))
	_add_bar(cage, "cage_top", Vector3(0.0, 0.095, -0.02), Vector3(0.13, 0.012, 0.16))


func _add_bar(parent: Node3D, bar_name: String, position: Vector3, size: Vector3) -> void:
	var bar: MeshInstance3D = MeshInstance3D.new()
	bar.name = bar_name
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	bar.mesh = mesh
	bar.position = position
	bar.material_override = _make_material(Color(0.06, 0.06, 0.07))
	parent.add_child(bar)


func _add_wheel(parent: Node3D, socket_name: String, position: Vector3) -> void:
	var socket: Node3D = Node3D.new()
	socket.name = socket_name
	socket.position = position
	parent.add_child(socket)

	var wheel: MeshInstance3D = MeshInstance3D.new()
	wheel.name = "wheel_mesh"
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = GameConfig.wheel_radius
	mesh.bottom_radius = GameConfig.wheel_radius
	mesh.height = 0.035
	mesh.radial_segments = 18
	wheel.mesh = mesh
	wheel.rotation_degrees = Vector3(0.0, 0.0, 90.0)
	wheel.material_override = _make_material(Color(0.03, 0.03, 0.035))
	socket.add_child(wheel)


func _make_material(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	return material

