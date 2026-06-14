extends Node

const SurfaceMapScript: GDScript = preload("res://systems/world/surface_map.gd")
const CEDAR_TERRAIN_PALETTE_PATH: String = "res://data/surface_palettes/cedar_hollow_terrain.tres"

const SAMPLE_POINTS: Dictionary = {
	&"packed_gravel": Vector3(0.0, 0.0, 0.75),
	&"packed_dirt": Vector3(0.0, 0.0, -2.4),
	&"tall_grass": Vector3(-1.7, 0.0, -2.5),
	&"mud": Vector3(2.8, 0.0, -5.5),
	&"loose_rock": Vector3(-2.3, 0.0, -9.1),
	&"wet_stone": Vector3(4.8, 0.0, -7.8),
	&"wood_plank": Vector3(3.25, 0.0, -3.35)
}

var _surface_map: Node = null
var _errors: PackedStringArray = PackedStringArray()


func _ready() -> void:
	_surface_map = SurfaceMapScript.new()
	_surface_map.name = "SurfaceMap"
	add_child(_surface_map)
	call_deferred("_inspect")


func _inspect() -> void:
	if _surface_map == null:
		_errors.append("missing SurfaceMap")
		_finish()
		return
	if not bool(_surface_map.call("configure_terrain_palette", CEDAR_TERRAIN_PALETTE_PATH, GameConfig.cedar_surface_map_bounds_min, GameConfig.cedar_surface_map_bounds_max)):
		_errors.append("failed to configure terrain palette")
		_finish()
		return
	if not bool(_surface_map.call("is_terrain_sampler_ready")):
		_errors.append("terrain sampler should be ready after configure")
	for surface_key in SAMPLE_POINTS.keys():
		var expected_surface_id: StringName = surface_key
		var point: Vector3 = SAMPLE_POINTS[expected_surface_id]
		var observed_surface_id: StringName = _surface_map.call("surface_id_at_world_position", point, &"")
		if observed_surface_id != expected_surface_id:
			_errors.append("surface sample at " + str(point) + " expected " + String(expected_surface_id) + ", got " + String(observed_surface_id))
	_finish()


func _finish() -> void:
	if _errors.is_empty():
		print("ok: Cedar terrain surface sampler maps world points to palette ids")
		get_tree().quit(0)
		return
	for error in _errors:
		push_error(error)
	get_tree().quit(1)
