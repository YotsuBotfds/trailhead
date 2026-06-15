class_name TerrainBuilder
extends RefCounted

const SurfaceMapScript: GDScript = preload("res://systems/world/surface_map.gd")

const CEDAR_SCENE_ID: String = "cedar_hollow"
const CEDAR_TERRAIN_DEF_PATH: String = "res://data/terrain/cedar_hollow_terrain_def.tres"
const CEDAR_HOLLOW_10M_SCENE_ID: String = "cedar_hollow_zion"
const CEDAR_HOLLOW_10M_TERRAIN_DEF_PATH: String = "res://data/terrain/cedar_hollow_zion_terrain_def.tres"
const CEDAR_HOLLOW_10M_SPAWN_TERRAIN_XZ: Vector2 = Vector2(1180.0, 860.0)
const CedarTerrainDef: Resource = preload(CEDAR_TERRAIN_DEF_PATH)
const CedarHollow10mTerrainDef: Resource = preload(CEDAR_HOLLOW_10M_TERRAIN_DEF_PATH)

static var _heightmap_collision_shapes_by_path: Dictionary[String, HeightMapShape3D] = {}


static func build_cedar_hollow(parent: Node) -> Array[StaticBody3D]:
	var bodies: Array[StaticBody3D] = []
	bodies.append(_build_heightmap_collision(parent, CedarTerrainDef, Vector2.ZERO, "cedar_hollow_heightmap_collision", &""))
	return bodies


static func build_cedar_hollow_10m(parent: Node) -> Array[StaticBody3D]:
	var bodies: Array[StaticBody3D] = []
	bodies.append(_build_heightmap_collision(parent, CedarHollow10mTerrainDef, cedar_hollow_10m_horizontal_offset(), "cedar_hollow_10m_heightmap_collision", &"packed_dirt"))
	return bodies


static func _build_heightmap_collision(parent: Node, terrain_def: Resource, horizontal_offset: Vector2, collision_name: String, fallback_surface_id: StringName) -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = collision_name
	if fallback_surface_id == &"":
		body.add_to_group(SurfaceMapScript.TERRAIN_SURFACE_MAP_GROUP)
		body.set_meta(
			SurfaceMapScript.TERRAIN_SURFACE_OVERRIDE_RECTS_META,
			terrain_def.call("surface_override_rects")
		)
	else:
		body.name += "__surf_" + String(fallback_surface_id)
		body.add_to_group("surf_" + String(fallback_surface_id))
	var center: Vector2 = terrain_def.call("center_xz")
	body.position = Vector3(
		center.x + horizontal_offset.x,
		0.0,
		center.y + horizontal_offset.y
	)
	parent.add_child(body)

	var active_tiles: Array[Vector2i] = terrain_def.call("active_tile_indices")
	for tile_index in active_tiles:
		var collision: CollisionShape3D = CollisionShape3D.new()
		collision.name = _collision_node_name(tile_index)
		var shape: HeightMapShape3D = heightmap_collision_shape_for_terrain_tile(terrain_def, tile_index)
		if shape == null:
			continue
		var tile_bounds: Rect2 = terrain_def.call("tile_bounds", tile_index)
		var tile_center: Vector2 = tile_bounds.get_center()
		collision.position = Vector3(tile_center.x - center.x, 0.0, tile_center.y - center.y)
		collision.shape = shape
		collision.scale = _heightmap_collision_scale(terrain_def, shape, tile_index)
		body.add_child(collision)
	return body


static func cedar_terrain_def() -> Resource:
	return CedarTerrainDef


static func cedar_hollow_10m_terrain_def() -> Resource:
	return CedarHollow10mTerrainDef


static func cedar_hollow_10m_horizontal_offset() -> Vector2:
	var bounds_min: Vector2 = CedarHollow10mTerrainDef.get("bounds_min_xz")
	return -(bounds_min + CEDAR_HOLLOW_10M_SPAWN_TERRAIN_XZ)


static func cedar_hollow_10m_spawn_transform() -> Transform3D:
	var height: float = heightmap_height_at_world_xz(CedarHollow10mTerrainDef, Vector2.ZERO, cedar_hollow_10m_horizontal_offset())
	return Transform3D(Basis.IDENTITY, Vector3(0.0, height + _vehicle_spawn_clearance(0.0), 0.0))


static func heightmap_collision_shape_for_tile(tile_index: Vector2i) -> HeightMapShape3D:
	return heightmap_collision_shape_for_terrain_tile(CedarTerrainDef, tile_index)


static func heightmap_collision_shape_for_terrain_tile(terrain_def: Resource, tile_index: Vector2i) -> HeightMapShape3D:
	var collision_path: String = terrain_def.call("collision_tile_path_for_tile", tile_index)
	if collision_path.is_empty():
		return null
	if not _heightmap_collision_shapes_by_path.has(collision_path):
		var shape: HeightMapShape3D = ResourceLoader.load(collision_path) as HeightMapShape3D
		if shape == null:
			return null
		_heightmap_collision_shapes_by_path[collision_path] = shape
	return _heightmap_collision_shapes_by_path[collision_path]


static func heightmap_height_at_world_xz(terrain_def: Resource, world_xz: Vector2, horizontal_offset: Vector2) -> float:
	var terrain_xz: Vector2 = world_xz - horizontal_offset
	if not bool(terrain_def.call("contains_world_xz", terrain_xz)):
		return 0.0
	var tile_index: Vector2i = terrain_def.call("tile_index_for_world_xz", terrain_xz)
	var shape: HeightMapShape3D = heightmap_collision_shape_for_terrain_tile(terrain_def, tile_index)
	if shape == null:
		return 0.0
	var width: int = maxi(shape.map_width, 1)
	var depth: int = maxi(shape.map_depth, 1)
	var data: PackedFloat32Array = shape.map_data
	if data.size() != width * depth:
		return 0.0
	var uv: Vector2 = terrain_def.call("world_to_tile_heightmap_uv", terrain_xz, tile_index)
	var u: float = clampf(uv.x, 0.0, 1.0) * float(width - 1)
	var v: float = clampf(uv.y, 0.0, 1.0) * float(depth - 1)
	var x0: int = clampi(int(floor(u)), 0, width - 1)
	var z0: int = clampi(int(floor(v)), 0, depth - 1)
	var x1: int = mini(x0 + 1, width - 1)
	var z1: int = mini(z0 + 1, depth - 1)
	var tx: float = u - float(x0)
	var tz: float = v - float(z0)
	var h00: float = data[z0 * width + x0]
	var h10: float = data[z0 * width + x1]
	var h01: float = data[z1 * width + x0]
	var h11: float = data[z1 * width + x1]
	var h0: float = lerpf(h00, h10, tx)
	var h1: float = lerpf(h01, h11, tx)
	return lerpf(h0, h1, tz)


static func _heightmap_collision_scale(terrain_def: Resource, shape: HeightMapShape3D, tile_index: Vector2i) -> Vector3:
	var tile_bounds: Rect2 = terrain_def.call("tile_bounds", tile_index)
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


static func _vehicle_spawn_clearance(grade_deg: float) -> float:
	var ray_length: float = GameConfig.susp_rest_length + GameConfig.susp_travel + GameConfig.wheel_radius
	var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	var static_compression: float = clampf((GameConfig.chassis_mass * gravity * 0.25) / maxf(GameConfig.susp_stiffness, 0.001), 0.0, 1.0)
	var ray_distance: float = ray_length - static_compression * GameConfig.susp_travel
	var tilt_cos: float = maxf(cos(deg_to_rad(grade_deg)), 0.2)
	return ray_distance / tilt_cos
