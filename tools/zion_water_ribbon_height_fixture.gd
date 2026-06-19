extends Node

const WaterVisualBuilderScript: GDScript = preload("res://systems/render/water_visual_builder.gd")
const TerrainBuilderScript: GDScript = preload("res://systems/world/terrain_builder.gd")
const WATER_RIBBON_HEIGHT_EPSILON_M: float = 0.025
const EXPECTED_RIBBONS: Array[String] = [
	"virgin_river_west",
	"virgin_river_east",
]

var _errors: PackedStringArray = PackedStringArray()


func _ready() -> void:
	var parent: Node3D = Node3D.new()
	add_child(parent)
	var water_root: Node3D = WaterVisualBuilderScript.build_zion_virgin_river(parent)
	_inspect_water_root(water_root)
	parent.queue_free()
	_finish()


func _inspect_water_root(water_root: Node3D) -> void:
	if water_root == null:
		_errors.append("Zion river fixture failed to build water root")
		return
	var terrain_def: Resource = TerrainBuilderScript.cedar_hollow_10m_terrain_def()
	var horizontal_offset: Vector2 = TerrainBuilderScript.cedar_hollow_10m_horizontal_offset()
	for ribbon_name in EXPECTED_RIBBONS:
		var ribbon: MeshInstance3D = water_root.get_node_or_null(ribbon_name) as MeshInstance3D
		if ribbon == null:
			_errors.append("missing Zion river ribbon: " + ribbon_name)
			continue
		_require_ribbon_vertices_at_heightfield(ribbon, terrain_def, horizontal_offset)


func _require_ribbon_vertices_at_heightfield(ribbon: MeshInstance3D, terrain_def: Resource, horizontal_offset: Vector2) -> void:
	if ribbon.mesh == null:
		_errors.append(String(ribbon.name) + " should have a mesh")
		return
	var checked_vertices: int = 0
	var max_error: float = 0.0
	var max_error_vertex: Vector3 = Vector3.ZERO
	var max_error_expected_y: float = 0.0
	for surface_index in range(ribbon.mesh.get_surface_count()):
		var vertices: PackedVector3Array = ribbon.mesh.surface_get_arrays(surface_index)[Mesh.ARRAY_VERTEX] as PackedVector3Array
		for local_vertex in vertices:
			var world_vertex: Vector3 = ribbon.global_transform * local_vertex
			var world_xz: Vector2 = Vector2(world_vertex.x, world_vertex.z)
			var bed_y: float = TerrainBuilderScript.heightmap_height_at_world_xz(terrain_def, world_xz, horizontal_offset)
			var expected_y: float = bed_y + WaterVisualBuilderScript.ZION_RIVER_SURFACE_RISE_M
			var error: float = absf(world_vertex.y - expected_y)
			if error > max_error:
				max_error = error
				max_error_vertex = world_vertex
				max_error_expected_y = expected_y
			checked_vertices += 1
	if checked_vertices <= 0:
		_errors.append(String(ribbon.name) + " should have ribbon vertices")
	elif max_error > WATER_RIBBON_HEIGHT_EPSILON_M:
		_errors.append(
			String(ribbon.name)
			+ " vertex Y should equal heightfield + river rise; max_error="
			+ str(max_error)
			+ " vertex="
			+ str(max_error_vertex)
			+ " expected_y="
			+ str(max_error_expected_y)
		)


func _finish() -> void:
	if _errors.is_empty():
		print("ok: Zion river ribbon vertices follow heightfield + rise")
		get_tree().quit(0)
		return
	for error in _errors:
		push_error(error)
	get_tree().quit(1)
