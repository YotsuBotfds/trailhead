class_name FlatWorldBuilder
extends RefCounted


static func build_collision(parent: Node) -> StaticBody3D:
	var ground: StaticBody3D = StaticBody3D.new()
	ground.name = "flat_ground__surf_packed_dirt"
	ground.add_to_group("surf_packed_dirt")
	parent.add_child(ground)

	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.name = "Collision"
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = GameConfig.flat_ground_size
	collision.shape = shape
	collision.position = GameConfig.flat_ground_center
	ground.add_child(collision)
	return ground
