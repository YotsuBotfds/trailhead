class_name FlatWorldBuilder
extends RefCounted

const SURFACE_STRIP_IDS: Array[StringName] = [
	&"packed_dirt",
	&"tall_grass",
	&"mud",
	&"wet_stone"
]


static func build_collision(parent: Node) -> StaticBody3D:
	return _build_segment(parent, &"packed_dirt", GameConfig.flat_ground_center, GameConfig.flat_ground_size)


static func build_surface_strip_collision(parent: Node) -> Array[StaticBody3D]:
	var segments: Array[StaticBody3D] = []
	for i in range(SURFACE_STRIP_IDS.size()):
		var surface_id: StringName = SURFACE_STRIP_IDS[i]
		var center: Vector3 = Vector3(
			0.0,
			GameConfig.flat_ground_center.y,
			GameConfig.surface_strip_start_z - float(i) * GameConfig.surface_strip_stride_z
		)
		segments.append(_build_segment(parent, surface_id, center, GameConfig.surface_strip_size, "strip_" + String.num_int64(i).pad_zeros(2)))
	return segments


static func _build_segment(parent: Node, surface_id: StringName, center: Vector3, size: Vector3, prefix: String = "flat_ground") -> StaticBody3D:
	var ground: StaticBody3D = StaticBody3D.new()
	ground.name = prefix + "__surf_" + String(surface_id)
	ground.add_to_group("surf_" + String(surface_id))
	parent.add_child(ground)

	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.name = "Collision"
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	collision.position = center
	ground.add_child(collision)
	return ground
