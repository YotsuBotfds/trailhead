class_name TerrainBuilder
extends RefCounted

const SurfaceMapScript: GDScript = preload("res://systems/world/surface_map.gd")

const CEDAR_SCENE_ID: String = "cedar_hollow"
const CEDAR_TERRAIN_DEF_PATH: String = "res://data/terrain/cedar_hollow_terrain_def.tres"
const CedarTerrainDef: Resource = preload(CEDAR_TERRAIN_DEF_PATH)


static func build_cedar_hollow(parent: Node) -> Array[StaticBody3D]:
	var bodies: Array[StaticBody3D] = []
	bodies.append(_build_heightmap_collision(parent))
	return bodies


static func _build_heightmap_collision(parent: Node) -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "cedar_hollow_heightmap_collision"
	body.add_to_group(SurfaceMapScript.TERRAIN_SURFACE_MAP_GROUP)
	body.set_meta(
		SurfaceMapScript.TERRAIN_SURFACE_OVERRIDE_RECTS_META,
		CedarTerrainDef.call("surface_override_rects")
	)
	var center: Vector2 = CedarTerrainDef.call("center_xz")
	body.position = Vector3(
		center.x,
		0.0,
		center.y
	)
	parent.add_child(body)

	var active_tiles: Array[Vector2i] = CedarTerrainDef.call("active_tile_indices")
	for tile_index in active_tiles:
		var collision: CollisionShape3D = CollisionShape3D.new()
		collision.name = _collision_node_name(tile_index)
		var shape: HeightMapShape3D = heightmap_collision_shape_for_tile(tile_index)
		if shape == null:
			continue
		var tile_bounds: Rect2 = CedarTerrainDef.call("tile_bounds", tile_index)
		var tile_center: Vector2 = tile_bounds.get_center()
		collision.position = Vector3(tile_center.x - center.x, 0.0, tile_center.y - center.y)
		collision.shape = shape
		collision.scale = _heightmap_collision_scale(shape, tile_index)
		body.add_child(collision)
	return body


static func cedar_terrain_def() -> Resource:
	return CedarTerrainDef


static func heightmap_collision_shape_for_tile(tile_index: Vector2i) -> HeightMapShape3D:
	var collision_path: String = CedarTerrainDef.call("collision_tile_path_for_tile", tile_index)
	if collision_path.is_empty():
		return null
	return load(collision_path) as HeightMapShape3D


static func _heightmap_collision_scale(shape: HeightMapShape3D, tile_index: Vector2i) -> Vector3:
	var tile_bounds: Rect2 = CedarTerrainDef.call("tile_bounds", tile_index)
	var width_steps: int = maxi(shape.map_width - 1, 1)
	var depth_steps: int = maxi(shape.map_depth - 1, 1)
	return Vector3(
		tile_bounds.size.x / float(width_steps),
		1.0,
		tile_bounds.size.y / float(depth_steps)
	)


static func _collision_node_name(tile_index: Vector2i) -> String:
	if tile_index == Vector2i.ZERO:
		return "Collision"
	return "Collision_" + str(tile_index.x) + "_" + str(tile_index.y)
