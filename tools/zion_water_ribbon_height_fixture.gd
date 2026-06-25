extends Node

const WaterVisualBuilderScript: GDScript = preload("res://systems/render/water_visual_builder.gd")
const TerrainBuilderScript: GDScript = preload("res://systems/world/terrain_builder.gd")
const FLOAT_EPSILON: float = 0.001
const WATER_RIBBON_HEIGHT_EPSILON_M: float = 0.025
const WATER_RIBBON_CANYON_FLOOR_MAX_Y_M: float = 1330.0
const TANGENT_ALIGNMENT_MIN_DOT: float = 0.92
const TANGENT_VARIATION_MIN_RADIANS: float = 0.08
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
	var horizontal_offset: Vector2 = TerrainBuilderScript.cedar_hollow_10m_streamed_horizontal_offset()
	for ribbon_name in EXPECTED_RIBBONS:
		var ribbon: MeshInstance3D = water_root.get_node_or_null(ribbon_name) as MeshInstance3D
		if ribbon == null:
			_errors.append("missing Zion river ribbon: " + ribbon_name)
			continue
		_require_ribbon_material_uses_tangent_flow(ribbon)
		_require_ribbon_vertices_at_heightfield(ribbon, terrain_def, horizontal_offset)
		_require_ribbon_tangents_follow_centerline(ribbon)


func _require_ribbon_material_uses_tangent_flow(ribbon: MeshInstance3D) -> void:
	var material: ShaderMaterial = ribbon.material_override as ShaderMaterial
	if material == null:
		_errors.append(String(ribbon.name) + " should use ShaderMaterial")
		return
	if not bool(material.get_shader_parameter("use_vertex_water_traits")):
		_errors.append(String(ribbon.name) + " should enable vertex water traits")
	var flow_direction: Vector2 = material.get_shader_parameter("flow_direction")
	if flow_direction.length() > FLOAT_EPSILON:
		_errors.append(String(ribbon.name) + " tangent-driven ribbon should not use global flow_direction override; got " + str(flow_direction))


func _require_ribbon_vertices_at_heightfield(ribbon: MeshInstance3D, terrain_def: Resource, horizontal_offset: Vector2) -> void:
	if ribbon.mesh == null:
		_errors.append(String(ribbon.name) + " should have a mesh")
		return
	var checked_vertices: int = 0
	var max_error: float = 0.0
	var max_error_vertex: Vector3 = Vector3.ZERO
	var max_error_expected_y: float = 0.0
	var max_vertex_y: float = -INF
	var max_height_vertex: Vector3 = Vector3.ZERO
	for surface_index in range(ribbon.mesh.get_surface_count()):
		var vertices: PackedVector3Array = ribbon.mesh.surface_get_arrays(surface_index)[Mesh.ARRAY_VERTEX] as PackedVector3Array
		for local_vertex in vertices:
			var world_vertex: Vector3 = ribbon.global_transform * local_vertex
			if world_vertex.y > max_vertex_y:
				max_vertex_y = world_vertex.y
				max_height_vertex = world_vertex
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
	elif max_vertex_y > WATER_RIBBON_CANYON_FLOOR_MAX_Y_M:
		_errors.append(
			String(ribbon.name)
			+ " vertex Y should stay in Zion canyon-floor envelope; max_y="
			+ str(max_vertex_y)
			+ " max_allowed_y="
			+ str(WATER_RIBBON_CANYON_FLOOR_MAX_Y_M)
			+ " vertex="
			+ str(max_height_vertex)
		)


func _require_ribbon_tangents_follow_centerline(ribbon: MeshInstance3D) -> void:
	if ribbon.mesh == null:
		return
	for surface_index in range(ribbon.mesh.get_surface_count()):
		var arrays: Array = ribbon.mesh.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
		var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT] as PackedFloat32Array
		var lateral_count: int = WaterVisualBuilderScript.ZION_RIVER_LATERAL_VERTEX_COUNT
		if vertices.size() <= 0:
			continue
		if tangents.size() != vertices.size() * 4:
			_errors.append(String(ribbon.name) + " tangent array should have 4 floats per vertex")
			continue
		if vertices.size() % lateral_count != 0:
			_errors.append(String(ribbon.name) + " vertex rows should divide by lateral count")
			continue
		var row_count: int = floori(float(vertices.size()) / float(lateral_count))
		var center_lateral_index: int = floori(float(lateral_count) * 0.5)
		var first_tangent_xz: Vector2 = Vector2.ZERO
		var has_first_tangent: bool = false
		var max_tangent_delta: float = 0.0
		var worst_alignment: float = 1.0
		var worst_row: int = -1
		for row_index in range(row_count):
			var center_vertex_index: int = row_index * lateral_count + center_lateral_index
			var tangent_offset: int = center_vertex_index * 4
			var local_tangent: Vector3 = Vector3(
				tangents[tangent_offset],
				tangents[tangent_offset + 1],
				tangents[tangent_offset + 2]
			)
			var world_tangent: Vector3 = ribbon.global_transform.basis * local_tangent
			var world_tangent_xz: Vector2 = Vector2(world_tangent.x, world_tangent.z)
			if world_tangent_xz.length() <= FLOAT_EPSILON:
				_errors.append(String(ribbon.name) + " row " + str(row_index) + " should have non-zero tangent")
				continue
			world_tangent_xz = world_tangent_xz.normalized()
			var previous_center: Vector3 = _ribbon_center_world_vertex(ribbon, vertices, row_index - 1, row_count, lateral_count)
			var next_center: Vector3 = _ribbon_center_world_vertex(ribbon, vertices, row_index + 1, row_count, lateral_count)
			var expected_xz: Vector2 = Vector2(next_center.x - previous_center.x, next_center.z - previous_center.z)
			if expected_xz.length() <= FLOAT_EPSILON:
				continue
			expected_xz = expected_xz.normalized()
			var alignment: float = world_tangent_xz.dot(expected_xz)
			if alignment < worst_alignment:
				worst_alignment = alignment
				worst_row = row_index
			if has_first_tangent:
				max_tangent_delta = maxf(max_tangent_delta, absf(first_tangent_xz.angle_to(world_tangent_xz)))
			else:
				first_tangent_xz = world_tangent_xz
				has_first_tangent = true
		if worst_alignment < TANGENT_ALIGNMENT_MIN_DOT:
			_errors.append(
				String(ribbon.name)
				+ " tangents should align with ribbon centerline; worst_dot="
				+ str(worst_alignment)
				+ " row="
				+ str(worst_row)
			)
		if max_tangent_delta < TANGENT_VARIATION_MIN_RADIANS:
			_errors.append(String(ribbon.name) + " tangents should vary through bends; max_delta=" + str(max_tangent_delta))


func _ribbon_center_world_vertex(ribbon: MeshInstance3D, vertices: PackedVector3Array, row_index: int, row_count: int, lateral_count: int) -> Vector3:
	var safe_row_index: int = clampi(row_index, 0, row_count - 1)
	var center_lateral_index: int = floori(float(lateral_count) * 0.5)
	var vertex_index: int = safe_row_index * lateral_count + center_lateral_index
	return ribbon.global_transform * vertices[vertex_index]


func _finish() -> void:
	if _errors.is_empty():
		print("ok: Zion river ribbon vertices follow heightfield + rise")
		get_tree().quit(0)
		return
	for error in _errors:
		push_error(error)
	get_tree().quit(1)
