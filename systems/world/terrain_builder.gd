class_name TerrainBuilder
extends RefCounted

const SurfaceMapScript: GDScript = preload("res://systems/world/surface_map.gd")

const CEDAR_SCENE_ID: String = "cedar_hollow"
const CEDAR_HEIGHTMAP_COLLISION: HeightMapShape3D = preload("res://data/collision/cedar_hollow_heightmap_collision.tres")
const CEDAR_HEIGHTMAP_X_MIN: float = -5.5
const CEDAR_HEIGHTMAP_X_MAX: float = 5.5
const CEDAR_HEIGHTMAP_Z_MIN: float = -10.6
const CEDAR_HEIGHTMAP_Z_MAX: float = 1.6
const LOG_RAMP_SURFACE_ID: StringName = &"wood_plank"
const LOG_RAMP_TOP_CENTER_XZ: Vector2 = Vector2(1.290557, 0.164403)
const LOG_RAMP_AXIS_X_XZ: Vector2 = Vector2(0.422618, 0.906308)
const LOG_RAMP_AXIS_Z_XZ: Vector2 = Vector2(-0.906308, 0.422618)
const LOG_RAMP_HALF_EXTENTS_XZ: Vector2 = Vector2(0.275, 0.566264)
const OUTCROP_SURFACE_ID: StringName = &"loose_rock"
const OUTCROP_TOP_CENTER_XZ: Vector2 = Vector2(-1.2, -7.793908)
const OUTCROP_AXIS_X_XZ: Vector2 = Vector2.RIGHT
const OUTCROP_AXIS_Z_XZ: Vector2 = Vector2.UP
const OUTCROP_HALF_EXTENTS_XZ: Vector2 = Vector2(2.3, 2.42)
const BOARDWALK_SURFACE_ID: StringName = &"wood_plank"
const BOARDWALK_CENTER_XZ: Vector2 = Vector2(3.25, -3.35)
const BOARDWALK_HALF_EXTENTS_XZ: Vector2 = Vector2(0.9, 1.3)


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
		[_log_ramp_surface_override(), _outcrop_surface_override(), _boardwalk_surface_override()]
	)
	body.position = Vector3(
		(CEDAR_HEIGHTMAP_X_MIN + CEDAR_HEIGHTMAP_X_MAX) * 0.5,
		0.0,
		(CEDAR_HEIGHTMAP_Z_MIN + CEDAR_HEIGHTMAP_Z_MAX) * 0.5
	)
	parent.add_child(body)

	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.name = "Collision"
	collision.shape = CEDAR_HEIGHTMAP_COLLISION
	collision.scale = _heightmap_collision_scale(CEDAR_HEIGHTMAP_COLLISION)
	body.add_child(collision)
	return body


static func _log_ramp_surface_override() -> Dictionary:
	return {
		"surface_id": LOG_RAMP_SURFACE_ID,
		"center": LOG_RAMP_TOP_CENTER_XZ,
		"axis_x": LOG_RAMP_AXIS_X_XZ,
		"axis_z": LOG_RAMP_AXIS_Z_XZ,
		"half_extents": LOG_RAMP_HALF_EXTENTS_XZ
	}


static func _outcrop_surface_override() -> Dictionary:
	return {
		"surface_id": OUTCROP_SURFACE_ID,
		"center": OUTCROP_TOP_CENTER_XZ,
		"axis_x": OUTCROP_AXIS_X_XZ,
		"axis_z": OUTCROP_AXIS_Z_XZ,
		"half_extents": OUTCROP_HALF_EXTENTS_XZ
	}


static func _boardwalk_surface_override() -> Dictionary:
	return {
		"surface_id": BOARDWALK_SURFACE_ID,
		"center": BOARDWALK_CENTER_XZ,
		"axis_x": Vector2.RIGHT,
		"axis_z": Vector2.UP,
		"half_extents": BOARDWALK_HALF_EXTENTS_XZ
	}


static func _heightmap_collision_scale(shape: HeightMapShape3D) -> Vector3:
	var width_steps: int = maxi(shape.map_width - 1, 1)
	var depth_steps: int = maxi(shape.map_depth - 1, 1)
	return Vector3(
		(CEDAR_HEIGHTMAP_X_MAX - CEDAR_HEIGHTMAP_X_MIN) / float(width_steps),
		1.0,
		(CEDAR_HEIGHTMAP_Z_MAX - CEDAR_HEIGHTMAP_Z_MIN) / float(depth_steps)
	)
