class_name WaterVisualBuilder
extends RefCounted

const WaterShader: Shader = preload("res://systems/render/water_visual.gdshader")
const TerrainBuilderScript: GDScript = preload("res://systems/world/terrain_builder.gd")
const ROOT_NAME: String = "WaterVisuals"
const WATER_SURFACE_GROUP: String = "render_water_surface"
const BED_TINT_COLOR: Color = Color(0.59, 0.46, 0.26)
const BED_TINT_STRENGTH: float = 0.50
const SHALLOW_ALPHA: float = 0.50
const DOWNSTREAM_FLOW_SPEED: float = 0.10
const FOAM_COLOR: Color = Color(0.70, 0.63, 0.42)
const WETLINE_STRENGTH: float = 0.28
const RIPPLE_NORMAL_STRENGTH: float = 0.08
const RIPPLE_NORMAL_SCALE: float = 1.60
const SHORELINE_SOFTNESS: float = 0.22
const FRESNEL_GLINT_COLOR: Color = Color(1.0, 0.74, 0.46)
const FRESNEL_GLINT_STRENGTH: float = 0.12
const ZION_RIVER_WIDTH_M: float = 9.5
const ZION_RIVER_SURFACE_RISE_M: float = 0.30
# Defensive guard band — same envelope as the terrain builder; see
# planning/codex-skyline-geometry-guard-plan.md §3.
const RIVER_HEIGHT_GUARD_MIN_M: float = -200.0
const RIVER_HEIGHT_GUARD_MAX_M: float = 4000.0
const RIVER_HEIGHT_GUARD_FALLBACK_M: float = 0.0
const ZION_RIVER_WEST_POINTS: Array[Vector2] = [
	Vector2(910.0, 500.0),
	Vector2(900.0, 700.0),
	Vector2(920.0, 900.0),
	Vector2(1000.0, 1000.0),
	Vector2(1070.0, 1200.0),
	Vector2(1130.0, 1300.0),
]
const ZION_RIVER_EAST_POINTS: Array[Vector2] = [
	Vector2(1130.0, 1300.0),
	Vector2(1180.0, 1350.0),
	Vector2(1330.0, 1400.0),
	Vector2(1410.0, 1450.0),
	Vector2(1500.0, 1550.0),
	Vector2(1530.0, 1600.0),
]


static func build_cedar_hollow(parent: Node3D) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = ROOT_NAME
	parent.add_child(root)
	_add_water_plane(root, "bog_pool_water", Vector3(2.80, GameConfig.water_surface_y + 0.018, -5.50), Vector2(2.10, 1.95), 4.0)
	_add_water_plane(root, "crossing_water", Vector3(4.20, GameConfig.water_surface_y + 0.020, -7.35), Vector2(3.12, 2.62), -7.0)
	_add_water_plane(root, "culvert_runoff_water", Vector3(-4.35, GameConfig.water_surface_y + 0.016, -3.05), Vector2(1.18, 2.35), 0.0)
	return root


static func build_zion_virgin_river(parent: Node3D) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = ROOT_NAME
	parent.add_child(root)
	_add_water_ribbon(root, "virgin_river_west", ZION_RIVER_WEST_POINTS, ZION_RIVER_WIDTH_M)
	_add_water_ribbon(root, "virgin_river_east", ZION_RIVER_EAST_POINTS, ZION_RIVER_WIDTH_M)
	return root


static func _add_water_plane(parent: Node3D, node_name: String, position: Vector3, size: Vector2, yaw_degrees: float) -> MeshInstance3D:
	var mesh: PlaneMesh = PlaneMesh.new()
	mesh.size = size
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.position = position
	instance.rotation_degrees = Vector3(0.0, yaw_degrees, 0.0)
	instance.material_override = _water_material(node_name)
	instance.visibility_range_end = GameConfig.vis_range_water
	instance.add_to_group(WATER_SURFACE_GROUP)
	instance.set_meta("water_visual_kind", node_name)
	parent.add_child(instance)
	return instance


static func _add_water_ribbon(parent: Node3D, node_name: String, river_points_xz: Array[Vector2], width_m: float) -> MeshInstance3D:
	if river_points_xz.size() < 2:
		return null
	var terrain_def: Resource = TerrainBuilderScript.cedar_hollow_10m_terrain_def()
	var horizontal_offset: Vector2 = TerrainBuilderScript.cedar_hollow_10m_streamed_horizontal_offset()
	var world_points: Array[Vector3] = _zion_river_surface_points(river_points_xz, terrain_def, horizontal_offset)
	var transform: Transform3D = _water_ribbon_transform(world_points)
	var inverse_basis: Basis = transform.basis.inverse()
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var tangents: PackedFloat32Array = PackedFloat32Array()
	var indices: PackedInt32Array = PackedInt32Array()
	var half_width: float = width_m * 0.5
	var distance_m: float = 0.0
	for point_index in range(world_points.size()):
		var point: Vector3 = world_points[point_index]
		if point_index > 0:
			distance_m += _water_xz_distance(world_points[point_index - 1], point)
		var tangent_xz: Vector2 = _water_point_tangent_xz(world_points, point_index)
		var side_xz: Vector2 = Vector2(-tangent_xz.y, tangent_xz.x)
		var local_tangent: Vector3 = (inverse_basis * Vector3(tangent_xz.x, 0.0, tangent_xz.y)).normalized()
		var left_xz: Vector2 = Vector2(point.x + side_xz.x * half_width, point.z + side_xz.y * half_width)
		var right_xz: Vector2 = Vector2(point.x - side_xz.x * half_width, point.z - side_xz.y * half_width)
		var left_world: Vector3 = Vector3(left_xz.x, _zion_river_surface_y(left_xz, terrain_def, horizontal_offset), left_xz.y)
		var right_world: Vector3 = Vector3(right_xz.x, _zion_river_surface_y(right_xz, terrain_def, horizontal_offset), right_xz.y)
		var left_local: Vector3 = inverse_basis * (left_world - transform.origin)
		var right_local: Vector3 = inverse_basis * (right_world - transform.origin)
		vertices.append(left_local)
		vertices.append(right_local)
		normals.append(Vector3.UP)
		normals.append(Vector3.UP)
		var u: float = distance_m * 0.06
		uvs.append(Vector2(u, 0.0))
		uvs.append(Vector2(u, 1.0))
		_append_tangent(tangents, local_tangent)
		_append_tangent(tangents, local_tangent)
	for segment_index in range(world_points.size() - 1):
		var left_0: int = segment_index * 2
		var right_0: int = left_0 + 1
		var left_1: int = left_0 + 2
		var right_1: int = left_0 + 3
		indices.append(left_0)
		indices.append(left_1)
		indices.append(right_0)
		indices.append(right_0)
		indices.append(left_1)
		indices.append(right_1)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.resource_name = node_name + "_ribbon_mesh"
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.transform = transform
	instance.material_override = _water_material(node_name)
	instance.visibility_range_end = GameConfig.vis_range_water
	instance.add_to_group(WATER_SURFACE_GROUP)
	instance.set_meta("water_visual_kind", node_name)
	instance.set_meta("water_visual_shape", "thalweg_ribbon")
	parent.add_child(instance)
	return instance


static func _zion_river_surface_points(river_points_xz: Array[Vector2], terrain_def: Resource, horizontal_offset: Vector2) -> Array[Vector3]:
	var world_points: Array[Vector3] = []
	for point_xz in river_points_xz:
		var surface_y: float = _zion_river_surface_y(point_xz, terrain_def, horizontal_offset)
		world_points.append(Vector3(point_xz.x, surface_y, point_xz.y))
	return world_points


static func _guarded_river_height(raw_height: float, world_xz: Vector2) -> float:
	if not is_finite(raw_height):
		push_warning("WaterVisualBuilder non-finite river bed height at " + str(world_xz) + " value " + str(raw_height))
		return RIVER_HEIGHT_GUARD_FALLBACK_M
	if raw_height < RIVER_HEIGHT_GUARD_MIN_M or raw_height > RIVER_HEIGHT_GUARD_MAX_M:
		push_warning("WaterVisualBuilder out-of-band river bed height at " + str(world_xz) + " value " + str(raw_height))
		return clampf(raw_height, RIVER_HEIGHT_GUARD_MIN_M, RIVER_HEIGHT_GUARD_MAX_M)
	return raw_height


static func _zion_river_surface_y(world_xz: Vector2, terrain_def: Resource, horizontal_offset: Vector2) -> float:
	var bed_y: float = _guarded_river_height(TerrainBuilderScript.heightmap_height_at_world_xz(terrain_def, world_xz, horizontal_offset), world_xz)
	return bed_y + ZION_RIVER_SURFACE_RISE_M


static func _water_ribbon_transform(world_points: Array[Vector3]) -> Transform3D:
	var origin: Vector3 = Vector3.ZERO
	for point in world_points:
		origin += point
	origin /= float(world_points.size())
	var start_xz: Vector2 = Vector2(world_points[0].x, world_points[0].z)
	var end_point: Vector3 = world_points[world_points.size() - 1]
	var end_xz: Vector2 = Vector2(end_point.x, end_point.z)
	var direction_xz: Vector2 = end_xz - start_xz
	if direction_xz.length() <= 0.001:
		direction_xz = Vector2.RIGHT
	else:
		direction_xz = direction_xz.normalized()
	var x_axis: Vector3 = Vector3(direction_xz.x, 0.0, direction_xz.y)
	var y_axis: Vector3 = Vector3.UP
	var z_axis: Vector3 = x_axis.cross(y_axis).normalized()
	return Transform3D(Basis(x_axis, y_axis, z_axis), origin)


static func _water_point_tangent_xz(world_points: Array[Vector3], point_index: int) -> Vector2:
	var previous_point: Vector3 = world_points[maxi(point_index - 1, 0)]
	var next_point: Vector3 = world_points[mini(point_index + 1, world_points.size() - 1)]
	var tangent: Vector2 = Vector2(next_point.x - previous_point.x, next_point.z - previous_point.z)
	if tangent.length() <= 0.001:
		return Vector2.RIGHT
	return tangent.normalized()


static func _water_xz_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))


static func _append_tangent(tangents: PackedFloat32Array, tangent: Vector3) -> void:
	tangents.append(tangent.x)
	tangents.append(tangent.y)
	tangents.append(tangent.z)
	tangents.append(1.0)


static func _water_material(resource_name: String) -> ShaderMaterial:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.resource_name = resource_name + "_material"
	material.shader = WaterShader
	material.set_shader_parameter("shallow_color", GameConfig.water_shallow_color)
	material.set_shader_parameter("deep_color", GameConfig.water_deep_color)
	material.set_shader_parameter("water_alpha", GameConfig.water_alpha)
	material.set_shader_parameter("depth_fade_distance", GameConfig.water_depth_fade_distance)
	material.set_shader_parameter("foam_edge_width", GameConfig.water_foam_edge_width)
	material.set_shader_parameter("flow_speed", GameConfig.water_flow_speed)
	material.set_shader_parameter("wave_amplitude", GameConfig.water_wave_amplitude)
	material.set_shader_parameter("foam_normal_strength", GameConfig.water_foam_normal_strength)
	material.set_shader_parameter("foam_normal_scale", GameConfig.water_foam_normal_scale)
	material.set_shader_parameter("foam_normal_flow_speed", GameConfig.water_foam_normal_flow_speed)
	material.set_shader_parameter("ssr_enabled", GameConfig.water_ssr_enabled)
	material.set_shader_parameter("ssr_intensity", GameConfig.water_ssr_intensity)
	material.set_shader_parameter("ssr_max_steps", GameConfig.water_ssr_max_steps)
	material.set_shader_parameter("ssr_step_size", GameConfig.water_ssr_step_size)
	material.set_shader_parameter("ssr_thickness", GameConfig.water_ssr_thickness)
	material.set_shader_parameter("water_roughness", GameConfig.water_roughness)
	material.set_shader_parameter("bed_tint_color", BED_TINT_COLOR)
	material.set_shader_parameter("bed_tint_strength", BED_TINT_STRENGTH)
	material.set_shader_parameter("shallow_alpha", SHALLOW_ALPHA)
	material.set_shader_parameter("downstream_flow_speed", DOWNSTREAM_FLOW_SPEED)
	material.set_shader_parameter("foam_color", FOAM_COLOR)
	material.set_shader_parameter("wetline_strength", WETLINE_STRENGTH)
	material.set_shader_parameter("ripple_normal_strength", RIPPLE_NORMAL_STRENGTH)
	material.set_shader_parameter("ripple_normal_scale", RIPPLE_NORMAL_SCALE)
	material.set_shader_parameter("shoreline_softness", SHORELINE_SOFTNESS)
	material.set_shader_parameter("fresnel_glint_color", FRESNEL_GLINT_COLOR)
	material.set_shader_parameter("fresnel_glint_strength", FRESNEL_GLINT_STRENGTH)
	return material
