class_name TerrainBuilder
extends RefCounted

const CEDAR_SCENE_ID: String = "cedar_hollow"


static func build_cedar_hollow(parent: Node) -> Array[StaticBody3D]:
	var bodies: Array[StaticBody3D] = []
	bodies.append(_build_surface_box(parent, "trailhead_gravel", &"packed_gravel", Vector3(0.0, -0.05, 0.75), Vector3(2.0, 0.1, 1.5)))
	bodies.append(_build_surface_box(parent, "main_trail_00", &"packed_dirt", Vector3(0.0, -0.05, -2.4), Vector3(1.2, 0.1, 4.8)))
	bodies.append(_build_surface_box(parent, "old_cedar_pad", &"packed_dirt", Vector3(0.0, -0.05, -5.3), Vector3(2.0, 0.1, 1.2)))
	bodies.append(_build_surface_box(parent, "meadow_left", &"tall_grass", Vector3(-1.7, -0.05, -2.5), Vector3(2.0, 0.1, 5.5)))
	bodies.append(_build_surface_box(parent, "meadow_right", &"tall_grass", Vector3(1.7, -0.05, -2.5), Vector3(2.0, 0.1, 5.5)))
	return bodies


static func _build_surface_box(parent: Node, base_name: String, surface_id: StringName, center: Vector3, size: Vector3) -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = base_name + "__surf_" + String(surface_id)
	body.add_to_group("surf_" + String(surface_id))
	parent.add_child(body)

	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.name = "Collision"
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	collision.position = center
	body.add_child(collision)
	return body
