class_name TerrainBuilder
extends RefCounted

const CEDAR_SCENE_ID: String = "cedar_hollow"


static func build_cedar_hollow(parent: Node) -> Array[StaticBody3D]:
	var bodies: Array[StaticBody3D] = []
	bodies.append(_build_surface_box(parent, "trailhead_gravel", &"packed_gravel", Vector3(0.0, -0.05, 0.75), Vector3(2.0, 0.1, 1.5)))
	bodies.append(_build_surface_box(parent, "log_ramp_apron", &"tall_grass", Vector3(1.78, -0.05, 0.62), Vector3(1.6, 0.1, 1.1)))
	bodies.append(_build_surface_box(parent, "main_trail_00", &"packed_dirt", Vector3(0.0, -0.05, -2.4), Vector3(1.2, 0.1, 4.8)))
	bodies.append(_build_oriented_surface_box(parent, "log_ramp", &"wood_plank", Vector3(1.3, 0.06, 0.16), Vector3(0.55, 0.12, 1.15), -65.0, 10.0))
	bodies.append(_build_surface_box(parent, "old_cedar_pad", &"packed_dirt", Vector3(0.0, -0.05, -5.3), Vector3(2.0, 0.1, 1.2)))
	bodies.append(_build_surface_box(parent, "meadow_left", &"tall_grass", Vector3(-1.7, -0.05, -2.5), Vector3(2.0, 0.1, 5.5)))
	bodies.append(_build_surface_box(parent, "meadow_right", &"tall_grass", Vector3(1.7, -0.05, -2.0), Vector3(2.0, 0.1, 4.4)))
	bodies.append(_build_surface_box(parent, "culvert_spur", &"packed_dirt", Vector3(-2.2, -0.04, -1.75), Vector3(4.8, 0.1, 1.6)))
	bodies.append(_build_surface_box(parent, "culvert_mouth_floor", &"packed_dirt", Vector3(-4.35, -0.04, -3.05), Vector3(1.7, 0.1, 3.0)))
	bodies.append(_build_oriented_surface_box(parent, "outcrop_climb", &"loose_rock", Vector3(-1.2, 0.15, -7.8), Vector3(4.6, 0.1, 4.6), 0.0, 5.0))
	bodies.append(_build_surface_box(parent, "switchback_entry_bridge", &"packed_dirt", Vector3(0.25, 0.35, -8.0), Vector3(1.8, 0.1, 1.0)))
	bodies.append(_build_oriented_surface_box(parent, "switchback_outer_run", &"packed_dirt", Vector3(1.55, 0.2, -6.6), Vector3(1.4, 0.1, 2.6), 0.0, 6.0))
	bodies.append(_build_surface_box(parent, "switchback_lower_landing", &"packed_dirt", Vector3(0.95, 0.15, -5.25), Vector3(1.8, 0.1, 1.4)))
	bodies.append(_build_surface_box(parent, "overlook_ridge_pad", &"loose_rock", Vector3(-2.3, 0.31, -9.1), Vector3(3.8, 0.1, 2.4)))
	bodies.append(_build_surface_box(parent, "bog_approach", &"packed_dirt", Vector3(1.4, -0.05, -5.25), Vector3(2.0, 0.1, 1.0)))
	bodies.append(_build_surface_box(parent, "bog_bottom", &"mud", Vector3(2.8, -0.05, -5.5), Vector3(2.4, 0.1, 2.4)))
	bodies.append(_build_surface_box(parent, "boardwalk_creek_connector", &"mud", Vector3(3.9, -0.05, -4.75), Vector3(2.2, 0.1, 2.6)))
	bodies.append(_build_surface_box(parent, "creek_bank", &"mud", Vector3(3.2, -0.05, -6.85), Vector3(2.2, 0.1, 1.9)))
	bodies.append(_build_surface_box(parent, "wet_stone_crossing", &"wet_stone", Vector3(4.2, -0.05, -7.45), Vector3(3.0, 0.1, 2.8)))
	bodies.append(_build_surface_box(parent, "boardwalk", &"wood_plank", Vector3(3.25, -0.02, -3.35), Vector3(1.4, 0.1, 2.6)))
	return bodies


static func _build_surface_box(parent: Node, base_name: String, surface_id: StringName, center: Vector3, size: Vector3) -> StaticBody3D:
	return _build_surface_box_transform(parent, base_name, surface_id, Transform3D(Basis.IDENTITY, center), size)


static func _build_oriented_surface_box(parent: Node, base_name: String, surface_id: StringName, center: Vector3, size: Vector3, yaw_degrees: float, pitch_degrees: float) -> StaticBody3D:
	var yaw_basis: Basis = Basis(Vector3.UP, deg_to_rad(yaw_degrees))
	var pitch_basis: Basis = Basis(Vector3.RIGHT, deg_to_rad(pitch_degrees))
	return _build_surface_box_transform(parent, base_name, surface_id, Transform3D(yaw_basis * pitch_basis, center), size)


static func _build_surface_box_transform(parent: Node, base_name: String, surface_id: StringName, transform: Transform3D, size: Vector3) -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = base_name + "__surf_" + String(surface_id)
	body.add_to_group("surf_" + String(surface_id))
	body.transform = transform
	parent.add_child(body)

	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.name = "Collision"
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	return body
