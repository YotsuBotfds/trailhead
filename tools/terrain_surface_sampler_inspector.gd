extends Node

const SurfaceMapScript: GDScript = preload("res://systems/world/surface_map.gd")
const CEDAR_TERRAIN_DEF_PATH: String = "res://data/terrain/cedar_hollow_terrain_def.tres"
const ZION_TERRAIN_DEF_PATH: String = "res://data/terrain/cedar_hollow_zion_terrain_def.tres"

const SAMPLE_POINTS: Dictionary = {
	&"packed_gravel": Vector3(0.0, 0.0, 0.75),
	&"packed_dirt": Vector3(0.0, 0.0, -2.4),
	&"tall_grass": Vector3(-1.7, 0.0, -2.5),
	&"mud": Vector3(2.8, 0.0, -5.5),
	&"loose_rock": Vector3(-2.3, 0.0, -9.1),
	&"wet_stone": Vector3(4.8, 0.0, -7.8),
	&"wood_plank": Vector3(3.25, 0.0, -3.35)
}
const ZION_SAMPLE_SURFACE_IDS: Array[StringName] = [
	&"wet_stone",
	&"packed_gravel",
	&"packed_dirt",
	&"loose_rock",
	&"tall_grass",
	&"packed_gravel"
]
const ZION_SAMPLE_POINTS: Array[Vector3] = [
	Vector3(324141.825, 0.0, 4122932.509),
	Vector3(323978.825, 0.0, 4122217.509),
	Vector3(324860.825, 0.0, 4120711.509),
	Vector3(325231.825, 0.0, 4120501.509),
	Vector3(325411.825, 0.0, 4122132.509),
	Vector3(324070.825, 0.0, 4119301.509)
]

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
	_inspect_cedar_samples()
	_inspect_zion_samples()
	_finish()


func _inspect_cedar_samples() -> void:
	if not bool(_surface_map.call("configure_terrain_def", CEDAR_TERRAIN_DEF_PATH)):
		_errors.append("failed to configure Cedar terrain def")
		return
	if not bool(_surface_map.call("is_terrain_sampler_ready")):
		_errors.append("Cedar terrain sampler should be ready after configure")
	for surface_key in SAMPLE_POINTS.keys():
		var expected_surface_id: StringName = surface_key
		var point: Vector3 = SAMPLE_POINTS[expected_surface_id]
		var observed_surface_id: StringName = _surface_map.call("surface_id_at_world_position", point, &"")
		if observed_surface_id != expected_surface_id:
			_errors.append("Cedar surface sample at " + str(point) + " expected " + String(expected_surface_id) + ", got " + String(observed_surface_id))


func _inspect_zion_samples() -> void:
	if not bool(_surface_map.call("configure_terrain_def", ZION_TERRAIN_DEF_PATH)):
		_errors.append("failed to configure Zion terrain def")
		return
	if not bool(_surface_map.call("is_terrain_sampler_ready")):
		_errors.append("Zion terrain sampler should be ready after configure")
	for i in range(ZION_SAMPLE_POINTS.size()):
		var expected_surface_id: StringName = ZION_SAMPLE_SURFACE_IDS[i]
		var point: Vector3 = ZION_SAMPLE_POINTS[i]
		var observed_surface_id: StringName = _surface_map.call("surface_id_at_world_position", point, &"")
		if observed_surface_id != expected_surface_id:
			_errors.append("Zion surface sample " + str(i + 1) + " at " + str(point) + " expected " + String(expected_surface_id) + ", got " + String(observed_surface_id))


func _finish() -> void:
	if _errors.is_empty():
		print("ok: terrain surface sampler maps Cedar and Zion world points to palette ids")
		get_tree().quit(0)
		return
	for error in _errors:
		push_error(error)
	get_tree().quit(1)
