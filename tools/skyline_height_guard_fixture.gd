extends Node

const TerrainVisualBuilderScript: GDScript = preload("res://systems/render/terrain_visual_builder.gd")
const TILE_WIDTH: int = 8
const TILE_DEPTH: int = 8
const TILE_SIZE_M: float = 100.0
const SANE_MIN_Y: float = -200.0
const SANE_MAX_Y: float = 4000.0
const NOMINAL_HEIGHT_M: float = 1200.0

var _errors: PackedStringArray = PackedStringArray()


func _ready() -> void:
	call_deferred("_inspect")


func _inspect() -> void:
	# A clean tile with one NaN and one absurd out-of-range spike injected.
	var heights: PackedFloat32Array = PackedFloat32Array()
	heights.resize(TILE_WIDTH * TILE_DEPTH)
	for index in range(heights.size()):
		heights[index] = NOMINAL_HEIGHT_M
	heights[10] = NAN
	heights[20] = 1.0e30
	heights[30] = -1.0e30

	var tile_data: Variant = TerrainVisualBuilderScript.RegionTileData.new()
	tile_data.cell = Vector2i(3, 4)
	tile_data.key = "3_4"
	tile_data.tile_size_m = TILE_SIZE_M
	tile_data.width = TILE_WIDTH
	tile_data.depth = TILE_DEPTH
	tile_data.heights = heights

	var mesh_data: Variant = TerrainVisualBuilderScript.build_region_surface_index_mesh_data(tile_data, 1, "skyline_guard_test", Vector2.ZERO)
	var mesh: ArrayMesh = TerrainVisualBuilderScript.region_mesh_from_data(mesh_data, false)
	if mesh == null or mesh.get_surface_count() <= 0:
		_errors.append("guard fixture produced no mesh surface")
		_finish()
		return

	var vertex_count: int = 0
	for surface_index in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for vertex in vertices:
			vertex_count += 1
			if not is_finite(vertex.y):
				_errors.append("vertex Y not finite: " + str(vertex.y))
			elif vertex.y < SANE_MIN_Y or vertex.y > SANE_MAX_Y:
				_errors.append("vertex Y out of sane band: " + str(vertex.y))

	# Also exercise the foliage-cull AABB consumer with the same poisoned tile.
	var aabb: AABB = TerrainVisualBuilderScript._tile_foliage_custom_aabb(tile_data)
	if not is_finite(aabb.position.y) or not is_finite(aabb.size.y):
		_errors.append("foliage AABB Y not finite: " + str(aabb))
	if aabb.position.y < SANE_MIN_Y or (aabb.position.y + aabb.size.y) > SANE_MAX_Y + 100.0:
		_errors.append("foliage AABB Y out of sane band: " + str(aabb))

	if vertex_count <= 0:
		_errors.append("guard fixture produced zero vertices")
	_finish()


func _finish() -> void:
	if _errors.is_empty():
		print("ok: skyline height guard")
		get_tree().quit(0)
		return
	for error in _errors:
		push_error(error)
	get_tree().quit(1)
