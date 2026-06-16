class_name FlatWorldBuilder
extends RefCounted

const SurfaceMapScript: GDScript = preload("res://systems/world/surface_map.gd")
const CedarTerrainDef: Resource = preload("res://data/terrain/cedar_hollow_terrain_def.tres")
const ZionTerrainDef: Resource = preload("res://data/terrain/cedar_hollow_zion_terrain_def.tres")
const TERRAIN_SURFACE_MAP_PROBE_SCENE_ID: String = "terrain_surface_map_probe"
const ZION_TERRAIN_SURFACE_MAP_PROBE_SCENE_ID: String = "zion_surface_map_probe"
const SURFACE_STRIP_IDS: Array[StringName] = [
	&"paved_road",
	&"slickrock_dry",
	&"packed_gravel",
	&"packed_dirt",
	&"tall_grass",
	&"loose_rock",
	&"sand_wash",
	&"mud",
	&"wet_stone"
]
const ZION_SURFACE_PROBE_SURFACE_IDS: Array[StringName] = [
	&"wet_stone",
	&"packed_gravel",
	&"packed_dirt",
	&"loose_rock",
	&"tall_grass",
	&"paved_road",
	&"slickrock_dry",
	&"sand_wash"
]
const ZION_SURFACE_PROBE_TERRAIN_XZ: Array[Vector2] = [
	Vector2(324141.825, 4122932.509),
	Vector2(323978.825, 4122217.509),
	Vector2(324860.825, 4120711.509),
	Vector2(325231.825, 4120501.509),
	Vector2(325411.825, 4122132.509),
	Vector2(324070.825, 4119301.509),
	Vector2(327400.0, 4123000.0),
	Vector2(327650.0, 4123150.0)
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


static func build_terrain_surface_map_probe_collision(parent: Node) -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "terrain_surface_map_probe"
	body.add_to_group(SurfaceMapScript.TERRAIN_SURFACE_MAP_GROUP)
	body.set_meta(SurfaceMapScript.TERRAIN_SURFACE_WORLD_OFFSET_META, Vector2.ZERO)
	parent.add_child(body)

	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.name = "Collision"
	var shape: BoxShape3D = BoxShape3D.new()
	var bounds_min: Vector2 = CedarTerrainDef.get("bounds_min_xz")
	var bounds_max: Vector2 = CedarTerrainDef.get("bounds_max_xz")
	shape.size = Vector3(bounds_max.x - bounds_min.x, GameConfig.flat_ground_size.y, bounds_max.y - bounds_min.y)
	collision.shape = shape
	collision.position = Vector3(
		(bounds_min.x + bounds_max.x) * 0.5,
		GameConfig.flat_ground_center.y,
		(bounds_min.y + bounds_max.y) * 0.5
	)
	body.add_child(collision)
	return body


static func build_zion_terrain_surface_map_probe_collision(parent: Node) -> Array[StaticBody3D]:
	var segments: Array[StaticBody3D] = []
	var override_rects: Array[Variant] = ZionTerrainDef.call("surface_override_rects")
	for i in range(ZION_SURFACE_PROBE_TERRAIN_XZ.size()):
		var center: Vector3 = Vector3(
			0.0,
			GameConfig.flat_ground_center.y,
			GameConfig.surface_strip_start_z - float(i) * GameConfig.surface_strip_stride_z
		)
		segments.append(_build_terrain_surface_probe_segment(
			parent,
			ZION_SURFACE_PROBE_SURFACE_IDS[i],
			ZION_SURFACE_PROBE_TERRAIN_XZ[i],
			center,
			GameConfig.surface_strip_size,
			override_rects
		))
	return segments


static func _build_terrain_surface_probe_segment(parent: Node, surface_id: StringName, terrain_xz: Vector2, center: Vector3, size: Vector3, override_rects: Array[Variant]) -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "zion_surface_strip_" + String(surface_id)
	body.add_to_group(SurfaceMapScript.TERRAIN_SURFACE_MAP_GROUP)
	body.set_meta(
		SurfaceMapScript.TERRAIN_SURFACE_WORLD_OFFSET_META,
		Vector2(center.x, center.z) - terrain_xz
	)
	body.set_meta(SurfaceMapScript.TERRAIN_SURFACE_OVERRIDE_RECTS_META, override_rects)
	parent.add_child(body)

	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.name = "Collision"
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	collision.position = center
	body.add_child(collision)
	return body


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
