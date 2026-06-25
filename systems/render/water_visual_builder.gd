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
const FLOW_DIRECTION: Vector2 = Vector2(0.0, 1.0)
const FOAM_INTENSITY: float = 0.55
const RIPPLE_TIGHTNESS: float = 3.5
const ZION_RIVER_SURFACE_RISE_M: float = 0.30
# Variable-width river-width model — drives both the water ribbon envelope and
# the Virgin-River bank detail meshes (wet shoreline / gravel bars / riffles /
# cobbles) so the ribbon and its banks share one width profile.
const ZION_RIVER_MIN_WIDTH_M: float = 8.0
const ZION_RIVER_MAX_WIDTH_M: float = 15.0
const ZION_RIVER_BASE_WIDTH_M: float = 10.4
const ZION_RIVER_LATERAL_VERTEX_COUNT: int = 5
const ZION_BANK_DETAIL_ROOT_NAME: String = "VirginRiverBankDetails"
const ZION_BANK_DETAIL_GROUP: String = "render_river_bank_detail"
const ZION_BANK_WET_STRIP_WIDTH_M: float = 2.1
const ZION_BANK_WET_STRIP_INSET_M: float = 0.18
const ZION_BANK_DECAL_LIFT_M: float = 0.045
const ZION_GRAVEL_BAR_SURFACE_LIFT_M: float = 0.014
const ZION_GRAVEL_BAR_SEGMENTS: int = 12
const ZION_RIFFLE_SURFACE_LIFT_M: float = 0.020
const ZION_COBBLES_PER_BANK_POINT: int = 5
const ZION_COBBLE_SEGMENTS: int = 6
const ZION_WET_SHORELINE_COLOR: Color = Color(0.24, 0.20, 0.145, 0.56)
const ZION_GRAVEL_BAR_COLOR: Color = Color(0.57, 0.51, 0.40, 1.0)
const ZION_COBBLE_COLOR: Color = Color(0.48, 0.43, 0.35, 1.0)
const ZION_RIFFLE_COLOR: Color = Color(0.82, 0.76, 0.62, 0.34)
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
	Vector2(1605.0, 1618.0),
	Vector2(1705.0, 1636.0),
	Vector2(1810.0, 1646.0),
	Vector2(1905.0, 1652.0),
]
# EAST-river terminus (T-012). The east centerline runs from the west confluence
# at (1130,1300)/bed ~1191.4 m monotonically UPHILL to (1905,1652)/bed ~1209.5 m
# (~+18 m). The water surface is glued to the bed (_zion_river_surface_y =
# heightfield + ZION_RIVER_SURFACE_RISE_M), so the ribbon visibly climbed uphill.
# The Virgin River reaches its low point at the confluence; east of it the canyon
# floor rises into a bench, so the river runs out into the dry sand_wash floor.
# We keep only the gentle near-flat reach (confluence -> EAST_TERMINUS_INDEX, local
# grades <=~1.5%, +2.3 m total over ~229 m — visually flat at vis_range_water=24 m)
# and pinch the channel width to a thread over the last EAST_RUNOUT_M so it fades
# into sand instead of ending on a hard wall. Vertices still sit on bed+rise, so
# the zion_water_ribbon_height_fixture per-vertex contract is preserved. WEST is
# untouched (it never climbs past the terminus tolerance; truncation is east-only
# and opt-in). Indices E[3..9] (the +8..+18 m cliff) are dropped.
const ZION_RIVER_EAST_TERMINUS_INDEX: int = 2
const ZION_RIVER_EAST_RUNOUT_M: float = 130.0
# Width-taper floor at the very terminus (fraction of full half-width). Small but
# non-zero so the final cross-section is a thin thread, not a degenerate zero-area
# strip; the existing narrow-width riffle weighting then reads it as shallow/foamy.
const ZION_RIVER_RUNOUT_WIDTH_FLOOR: float = 0.12


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
	_add_water_ribbon(root, "virgin_river_west", ZION_RIVER_WEST_POINTS)
	_add_water_ribbon(root, "virgin_river_east", _zion_river_east_water_points(), ZION_RIVER_EAST_RUNOUT_M)
	_add_zion_bank_details(root)
	return root


# East water reach: the centerline truncated at the terminus where the canyon
# floor begins its steep climb (see ZION_RIVER_EAST_TERMINUS_INDEX). The water
# ribbon and the wet shoreline use this; dry-bed debris (gravel bars, cobbles)
# keep the full east centerline so they read as wash material on the rising floor.
static func _zion_river_east_water_points() -> Array[Vector2]:
	var clipped: Array[Vector2] = []
	var last_index: int = clampi(ZION_RIVER_EAST_TERMINUS_INDEX, 1, ZION_RIVER_EAST_POINTS.size() - 1)
	for point_index in range(last_index + 1):
		clipped.append(ZION_RIVER_EAST_POINTS[point_index])
	return clipped


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


static func _add_water_ribbon(parent: Node3D, node_name: String, river_points_xz: Array[Vector2], runout_taper_m: float = 0.0) -> MeshInstance3D:
	if river_points_xz.size() < 2:
		return null
	var terrain_def: Resource = TerrainBuilderScript.cedar_hollow_10m_terrain_def()
	var horizontal_offset: Vector2 = TerrainBuilderScript.cedar_hollow_10m_streamed_horizontal_offset()
	var world_points: Array[Vector3] = _zion_river_surface_points(river_points_xz, terrain_def, horizontal_offset)
	var transform: Transform3D = _water_ribbon_transform(world_points)
	var inverse_basis: Basis = transform.basis.inverse()
	var cumulative_distances: PackedFloat32Array = _water_cumulative_distances(world_points)
	var total_distance_m: float = _water_total_distance(cumulative_distances)
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var colors: PackedColorArray = PackedColorArray()
	var tangents: PackedFloat32Array = PackedFloat32Array()
	var indices: PackedInt32Array = PackedInt32Array()
	for point_index in range(world_points.size()):
		var point: Vector3 = world_points[point_index]
		var distance_m: float = cumulative_distances[point_index]
		var distance_t: float = _water_distance_t(cumulative_distances, total_distance_m, point_index)
		var runout_scale: float = _zion_river_runout_scale(distance_m, total_distance_m, runout_taper_m)
		var width_m: float = _zion_river_width_m(world_points, point_index, distance_t) * runout_scale
		var half_width: float = width_m * 0.5
		var riffle_weight: float = _zion_river_riffle_weight(distance_t, width_m)
		var tangent_xz: Vector2 = _water_point_tangent_xz(world_points, point_index)
		var side_xz: Vector2 = Vector2(-tangent_xz.y, tangent_xz.x)
		var local_tangent: Vector3 = (inverse_basis * Vector3(tangent_xz.x, 0.0, tangent_xz.y)).normalized()
		var u: float = distance_m * 0.06
		for lateral_index in range(ZION_RIVER_LATERAL_VERTEX_COUNT):
			var lateral_t: float = float(lateral_index) / float(ZION_RIVER_LATERAL_VERTEX_COUNT - 1)
			var side_fraction: float = 1.0 - lateral_t * 2.0
			var lateral_offset: float = side_fraction * half_width
			var world_xz: Vector2 = Vector2(
				point.x + side_xz.x * lateral_offset,
				point.z + side_xz.y * lateral_offset
			)
			var world_vertex: Vector3 = Vector3(world_xz.x, _zion_river_surface_y(world_xz, terrain_def, horizontal_offset), world_xz.y)
			var local_vertex: Vector3 = inverse_basis * (world_vertex - transform.origin)
			var bank_weight: float = pow(absf(side_fraction), 1.45)
			var center_riffle: float = maxf(0.0, 1.0 - absf(side_fraction) * 1.45) * riffle_weight
			vertices.append(local_vertex)
			normals.append(Vector3.UP)
			uvs.append(Vector2(u, lateral_t))
			colors.append(Color(bank_weight, center_riffle, 0.0, 1.0))
			_append_tangent(tangents, local_tangent)
	for segment_index in range(world_points.size() - 1):
		for lateral_index in range(ZION_RIVER_LATERAL_VERTEX_COUNT - 1):
			var near_left: int = segment_index * ZION_RIVER_LATERAL_VERTEX_COUNT + lateral_index
			var near_right: int = near_left + 1
			var far_left: int = near_left + ZION_RIVER_LATERAL_VERTEX_COUNT
			var far_right: int = far_left + 1
			indices.append(near_left)
			indices.append(far_left)
			indices.append(near_right)
			indices.append(near_right)
			indices.append(far_left)
			indices.append(far_right)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.resource_name = node_name + "_ribbon_mesh"
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.transform = transform
	instance.material_override = _water_material(node_name, true)
	instance.visibility_range_end = GameConfig.vis_range_water
	instance.add_to_group(WATER_SURFACE_GROUP)
	instance.set_meta("water_visual_kind", node_name)
	instance.set_meta("water_visual_shape", "variable_width_braided_ribbon")
	parent.add_child(instance)
	return instance


static func _zion_river_surface_points(river_points_xz: Array[Vector2], terrain_def: Resource, horizontal_offset: Vector2) -> Array[Vector3]:
	var world_points: Array[Vector3] = []
	for point_xz in river_points_xz:
		var surface_y: float = _zion_river_surface_y(point_xz, terrain_def, horizontal_offset)
		world_points.append(Vector3(point_xz.x, surface_y, point_xz.y))
	return world_points


static func _add_zion_bank_details(parent: Node3D) -> Node3D:
	var detail_root: Node3D = Node3D.new()
	detail_root.name = ZION_BANK_DETAIL_ROOT_NAME
	detail_root.add_to_group(ZION_BANK_DETAIL_GROUP)
	parent.add_child(detail_root)
	var terrain_def: Resource = TerrainBuilderScript.cedar_hollow_10m_terrain_def()
	# CRITICAL: bank detail meshes must sample the SAME streamed coord space the
	# water ribbon uses (cedar_hollow_10m_streamed_horizontal_offset, not the
	# un-streamed spawn-relative offset) or the banks float ~270m off the river.
	var horizontal_offset: Vector2 = TerrainBuilderScript.cedar_hollow_10m_streamed_horizontal_offset()
	var west_points: Array[Vector3] = _zion_river_surface_points(ZION_RIVER_WEST_POINTS, terrain_def, horizontal_offset)
	var east_points: Array[Vector3] = _zion_river_surface_points(ZION_RIVER_EAST_POINTS, terrain_def, horizontal_offset)
	# The WET shoreline marks ground that the water actually touches, so it ends at
	# the same terminus as the east water ribbon (no wet strip climbing the dry
	# rising floor). Gravel bars / riffles / cobbles keep the full east centerline:
	# past the terminus they read as dry wash debris on the rising sand floor.
	var east_water_points: Array[Vector3] = _zion_river_surface_points(_zion_river_east_water_points(), terrain_def, horizontal_offset)
	_add_zion_shoreline_mesh(detail_root, "virgin_river_wet_shoreline_west", west_points, terrain_def, horizontal_offset)
	_add_zion_shoreline_mesh(detail_root, "virgin_river_wet_shoreline_east", east_water_points, terrain_def, horizontal_offset)
	_add_zion_gravel_bar_mesh(detail_root, "virgin_river_gravel_bars_west", west_points, terrain_def, horizontal_offset)
	_add_zion_gravel_bar_mesh(detail_root, "virgin_river_gravel_bars_east", east_points, terrain_def, horizontal_offset)
	_add_zion_riffle_mesh(detail_root, "virgin_river_riffle_streaks_west", west_points, terrain_def, horizontal_offset)
	_add_zion_riffle_mesh(detail_root, "virgin_river_riffle_streaks_east", east_points, terrain_def, horizontal_offset)
	_add_zion_cobble_mesh(detail_root, "virgin_river_bank_cobbles_west", west_points, terrain_def, horizontal_offset)
	_add_zion_cobble_mesh(detail_root, "virgin_river_bank_cobbles_east", east_points, terrain_def, horizontal_offset)
	return detail_root


static func _add_zion_shoreline_mesh(parent: Node3D, node_name: String, world_points: Array[Vector3], terrain_def: Resource, horizontal_offset: Vector2) -> MeshInstance3D:
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var indices: PackedInt32Array = PackedInt32Array()
	var cumulative_distances: PackedFloat32Array = _water_cumulative_distances(world_points)
	var total_distance_m: float = _water_total_distance(cumulative_distances)
	for side_index in range(2):
		var side_sign: float = -1.0 if side_index == 0 else 1.0
		var side_vertex_start: int = vertices.size()
		for point_index in range(world_points.size()):
			var point: Vector3 = world_points[point_index]
			var distance_t: float = _water_distance_t(cumulative_distances, total_distance_m, point_index)
			var width_m: float = _zion_river_width_m(world_points, point_index, distance_t)
			var half_width: float = width_m * 0.5
			var tangent_xz: Vector2 = _water_point_tangent_xz(world_points, point_index)
			var side_xz: Vector2 = Vector2(-tangent_xz.y, tangent_xz.x) * side_sign
			var inner_offset: float = half_width + ZION_BANK_WET_STRIP_INSET_M
			var outer_offset: float = inner_offset + ZION_BANK_WET_STRIP_WIDTH_M
			var inner_xz: Vector2 = Vector2(point.x + side_xz.x * inner_offset, point.z + side_xz.y * inner_offset)
			var outer_xz: Vector2 = Vector2(point.x + side_xz.x * outer_offset, point.z + side_xz.y * outer_offset)
			var inner_world: Vector3 = Vector3(inner_xz.x, _zion_bank_ground_y(inner_xz, terrain_def, horizontal_offset), inner_xz.y)
			var outer_world: Vector3 = Vector3(outer_xz.x, _zion_bank_ground_y(outer_xz, terrain_def, horizontal_offset), outer_xz.y)
			vertices.append(inner_world)
			vertices.append(outer_world)
			normals.append(Vector3.UP)
			normals.append(Vector3.UP)
			uvs.append(Vector2(cumulative_distances[point_index] * 0.08, 0.0))
			uvs.append(Vector2(cumulative_distances[point_index] * 0.08, 1.0))
		for segment_index in range(world_points.size() - 1):
			var inner_0: int = side_vertex_start + segment_index * 2
			var outer_0: int = inner_0 + 1
			var inner_1: int = inner_0 + 2
			var outer_1: int = inner_0 + 3
			indices.append(inner_0)
			indices.append(inner_1)
			indices.append(outer_0)
			indices.append(outer_0)
			indices.append(inner_1)
			indices.append(outer_1)
	return _add_zion_bank_mesh_instance(parent, node_name, vertices, normals, uvs, indices, _bank_material(node_name, ZION_WET_SHORELINE_COLOR, 0.34))


static func _add_zion_gravel_bar_mesh(parent: Node3D, node_name: String, world_points: Array[Vector3], terrain_def: Resource, horizontal_offset: Vector2) -> MeshInstance3D:
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var indices: PackedInt32Array = PackedInt32Array()
	var cumulative_distances: PackedFloat32Array = _water_cumulative_distances(world_points)
	var total_distance_m: float = _water_total_distance(cumulative_distances)
	for point_index in range(1, world_points.size() - 1):
		var distance_t: float = _water_distance_t(cumulative_distances, total_distance_m, point_index)
		var width_m: float = _zion_river_width_m(world_points, point_index, distance_t)
		var bend_strength: float = _zion_river_bend_strength(world_points, point_index)
		var bar_strength: float = clampf(bend_strength * 1.8 + _zion_river_riffle_weight(distance_t, width_m) * 0.45, 0.0, 1.0)
		if bar_strength <= 0.22:
			continue
		var tangent_xz: Vector2 = _water_point_tangent_xz(world_points, point_index)
		var side_xz: Vector2 = Vector2(-tangent_xz.y, tangent_xz.x)
		var bend_side: float = _zion_river_bend_side(world_points, point_index)
		var center_offset_m: float = bend_side * width_m * (0.12 + bar_strength * 0.12)
		var center: Vector2 = Vector2(world_points[point_index].x, world_points[point_index].z) + side_xz * center_offset_m
		var half_length_m: float = 5.4 + width_m * (0.42 + bar_strength * 0.18)
		var half_width_m: float = 0.75 + width_m * (0.10 + bar_strength * 0.045)
		_append_gravel_bar(vertices, normals, uvs, indices, center, tangent_xz, side_xz, half_length_m, half_width_m, terrain_def, horizontal_offset, float(point_index))
	return _add_zion_bank_mesh_instance(parent, node_name, vertices, normals, uvs, indices, _bank_material(node_name, ZION_GRAVEL_BAR_COLOR, 0.86))


static func _add_zion_riffle_mesh(parent: Node3D, node_name: String, world_points: Array[Vector3], terrain_def: Resource, horizontal_offset: Vector2) -> MeshInstance3D:
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var indices: PackedInt32Array = PackedInt32Array()
	var cumulative_distances: PackedFloat32Array = _water_cumulative_distances(world_points)
	var total_distance_m: float = _water_total_distance(cumulative_distances)
	for segment_index in range(world_points.size() - 1):
		var segment_start_t: float = _water_distance_t(cumulative_distances, total_distance_m, segment_index)
		var segment_end_t: float = _water_distance_t(cumulative_distances, total_distance_m, segment_index + 1)
		for riffle_index in range(2):
			var segment_t: float = 0.34 + float(riffle_index) * 0.27
			var distance_t: float = lerpf(segment_start_t, segment_end_t, segment_t)
			var center: Vector3 = world_points[segment_index].lerp(world_points[segment_index + 1], segment_t)
			var width_m: float = lerpf(
				_zion_river_width_m(world_points, segment_index, segment_start_t),
				_zion_river_width_m(world_points, segment_index + 1, segment_end_t),
				segment_t
			)
			var riffle_strength: float = _zion_river_riffle_weight(distance_t, width_m)
			if riffle_strength <= 0.35:
				continue
			var tangent_xz: Vector2 = _water_point_tangent_xz(world_points, segment_index)
			var side_xz: Vector2 = Vector2(-tangent_xz.y, tangent_xz.x)
			var half_length_m: float = width_m * (0.22 + riffle_strength * 0.12)
			var half_thickness_m: float = 0.16 + riffle_strength * 0.12
			var lateral_offset_m: float = (0.18 - float(riffle_index) * 0.36) * width_m
			var center_xz: Vector2 = Vector2(center.x, center.z) + side_xz * lateral_offset_m
			_append_riffle_band(vertices, normals, uvs, indices, center_xz, tangent_xz, side_xz, half_length_m, half_thickness_m, terrain_def, horizontal_offset)
	return _add_zion_bank_mesh_instance(parent, node_name, vertices, normals, uvs, indices, _bank_material(node_name, ZION_RIFFLE_COLOR, 0.18))


static func _add_zion_cobble_mesh(parent: Node3D, node_name: String, world_points: Array[Vector3], terrain_def: Resource, horizontal_offset: Vector2) -> MeshInstance3D:
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var indices: PackedInt32Array = PackedInt32Array()
	var cumulative_distances: PackedFloat32Array = _water_cumulative_distances(world_points)
	var total_distance_m: float = _water_total_distance(cumulative_distances)
	for point_index in range(world_points.size()):
		var distance_t: float = _water_distance_t(cumulative_distances, total_distance_m, point_index)
		var width_m: float = _zion_river_width_m(world_points, point_index, distance_t)
		var tangent_xz: Vector2 = _water_point_tangent_xz(world_points, point_index)
		var side_xz: Vector2 = Vector2(-tangent_xz.y, tangent_xz.x)
		for side_index in range(2):
			var side_sign: float = -1.0 if side_index == 0 else 1.0
			for cobble_index in range(ZION_COBBLES_PER_BANK_POINT):
				var hash_seed: float = float(point_index * 41 + side_index * 17 + cobble_index * 7)
				var along_m: float = (_hash01(hash_seed + 1.7) - 0.5) * 10.0
				var lateral_m: float = width_m * 0.5 + 0.55 + _hash01(hash_seed + 3.1) * 2.6
				var center_xz: Vector2 = Vector2(world_points[point_index].x, world_points[point_index].z) + tangent_xz * along_m + side_xz * side_sign * lateral_m
				var radius_x: float = 0.16 + _hash01(hash_seed + 5.9) * 0.28
				var radius_z: float = 0.10 + _hash01(hash_seed + 8.4) * 0.20
				var yaw_radians: float = _hash01(hash_seed + 11.0) * TAU
				_append_cobble(vertices, normals, uvs, indices, center_xz, radius_x, radius_z, yaw_radians, terrain_def, horizontal_offset)
	return _add_zion_bank_mesh_instance(parent, node_name, vertices, normals, uvs, indices, _bank_material(node_name, ZION_COBBLE_COLOR, 0.92))


static func _append_gravel_bar(vertices: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, indices: PackedInt32Array, center_xz: Vector2, tangent_xz: Vector2, side_xz: Vector2, half_length_m: float, half_width_m: float, terrain_def: Resource, horizontal_offset: Vector2, seed: float) -> void:
	var center_index: int = vertices.size()
	vertices.append(_zion_surface_detail_vertex(center_xz, terrain_def, horizontal_offset, ZION_GRAVEL_BAR_SURFACE_LIFT_M))
	normals.append(Vector3.UP)
	uvs.append(Vector2(0.5, 0.5))
	for segment_index in range(ZION_GRAVEL_BAR_SEGMENTS):
		var angle: float = TAU * float(segment_index) / float(ZION_GRAVEL_BAR_SEGMENTS)
		var irregular: float = 0.84 + _hash01(seed * 19.0 + float(segment_index) * 3.7) * 0.28
		var local_x: float = cos(angle) * half_length_m * irregular
		var local_z: float = sin(angle) * half_width_m * irregular
		var world_xz: Vector2 = center_xz + tangent_xz * local_x + side_xz * local_z
		vertices.append(_zion_surface_detail_vertex(world_xz, terrain_def, horizontal_offset, ZION_GRAVEL_BAR_SURFACE_LIFT_M))
		normals.append(Vector3.UP)
		uvs.append(Vector2(0.5 + cos(angle) * 0.5, 0.5 + sin(angle) * 0.5))
	for segment_index in range(ZION_GRAVEL_BAR_SEGMENTS):
		indices.append(center_index)
		indices.append(center_index + segment_index + 1)
		indices.append(center_index + ((segment_index + 1) % ZION_GRAVEL_BAR_SEGMENTS) + 1)


static func _append_riffle_band(vertices: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, indices: PackedInt32Array, center_xz: Vector2, tangent_xz: Vector2, side_xz: Vector2, half_length_m: float, half_thickness_m: float, terrain_def: Resource, horizontal_offset: Vector2) -> void:
	var vertex_start: int = vertices.size()
	var points: Array[Vector2] = [
		center_xz - side_xz * half_length_m - tangent_xz * half_thickness_m,
		center_xz + side_xz * half_length_m - tangent_xz * half_thickness_m,
		center_xz - side_xz * half_length_m + tangent_xz * half_thickness_m,
		center_xz + side_xz * half_length_m + tangent_xz * half_thickness_m,
	]
	var band_uvs: Array[Vector2] = [
		Vector2.ZERO,
		Vector2.RIGHT,
		Vector2.UP,
		Vector2.ONE,
	]
	for point_index in range(points.size()):
		vertices.append(_zion_surface_detail_vertex(points[point_index], terrain_def, horizontal_offset, ZION_RIFFLE_SURFACE_LIFT_M))
		normals.append(Vector3.UP)
		uvs.append(band_uvs[point_index])
	indices.append(vertex_start)
	indices.append(vertex_start + 2)
	indices.append(vertex_start + 1)
	indices.append(vertex_start + 1)
	indices.append(vertex_start + 2)
	indices.append(vertex_start + 3)


static func _append_cobble(vertices: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, indices: PackedInt32Array, center_xz: Vector2, radius_x: float, radius_z: float, yaw_radians: float, terrain_def: Resource, horizontal_offset: Vector2) -> void:
	var center_index: int = vertices.size()
	vertices.append(Vector3(center_xz.x, _zion_bank_ground_y(center_xz, terrain_def, horizontal_offset) + 0.012, center_xz.y))
	normals.append(Vector3.UP)
	uvs.append(Vector2(0.5, 0.5))
	var yaw_basis_x: Vector2 = Vector2(cos(yaw_radians), sin(yaw_radians))
	var yaw_basis_z: Vector2 = Vector2(-yaw_basis_x.y, yaw_basis_x.x)
	for segment_index in range(ZION_COBBLE_SEGMENTS):
		var angle: float = TAU * float(segment_index) / float(ZION_COBBLE_SEGMENTS)
		var world_xz: Vector2 = center_xz + yaw_basis_x * (cos(angle) * radius_x) + yaw_basis_z * (sin(angle) * radius_z)
		vertices.append(Vector3(world_xz.x, _zion_bank_ground_y(world_xz, terrain_def, horizontal_offset) + 0.012, world_xz.y))
		normals.append(Vector3.UP)
		uvs.append(Vector2(0.5 + cos(angle) * 0.5, 0.5 + sin(angle) * 0.5))
	for segment_index in range(ZION_COBBLE_SEGMENTS):
		indices.append(center_index)
		indices.append(center_index + segment_index + 1)
		indices.append(center_index + ((segment_index + 1) % ZION_COBBLE_SEGMENTS) + 1)


static func _add_zion_bank_mesh_instance(parent: Node3D, node_name: String, vertices: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, indices: PackedInt32Array, material: Material) -> MeshInstance3D:
	if vertices.size() <= 0 or indices.size() <= 0:
		return null
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.resource_name = node_name + "_mesh"
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = material
	instance.visibility_range_end = GameConfig.vis_range_water
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.add_to_group(ZION_BANK_DETAIL_GROUP)
	parent.add_child(instance)
	return instance


static func _bank_material(resource_name: String, color: Color, roughness: float) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.resource_name = resource_name + "_material"
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = 0.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if color.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material


static func _zion_bank_ground_y(world_xz: Vector2, terrain_def: Resource, horizontal_offset: Vector2) -> float:
	var bed_y: float = _guarded_river_height(TerrainBuilderScript.heightmap_height_at_world_xz(terrain_def, world_xz, horizontal_offset), world_xz)
	return bed_y + ZION_BANK_DECAL_LIFT_M


static func _zion_surface_detail_vertex(world_xz: Vector2, terrain_def: Resource, horizontal_offset: Vector2, lift_m: float) -> Vector3:
	return Vector3(world_xz.x, _zion_river_surface_y(world_xz, terrain_def, horizontal_offset) + lift_m, world_xz.y)


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


static func _water_cumulative_distances(world_points: Array[Vector3]) -> PackedFloat32Array:
	var cumulative_distances: PackedFloat32Array = PackedFloat32Array()
	var distance_m: float = 0.0
	for point_index in range(world_points.size()):
		if point_index > 0:
			distance_m += _water_xz_distance(world_points[point_index - 1], world_points[point_index])
		cumulative_distances.append(distance_m)
	return cumulative_distances


static func _water_total_distance(cumulative_distances: PackedFloat32Array) -> float:
	if cumulative_distances.size() <= 0:
		return 0.0
	return cumulative_distances[cumulative_distances.size() - 1]


static func _water_distance_t(cumulative_distances: PackedFloat32Array, total_distance_m: float, point_index: int) -> float:
	if total_distance_m <= 0.001 or cumulative_distances.size() <= 0:
		return 0.0
	var safe_index: int = clampi(point_index, 0, cumulative_distances.size() - 1)
	return cumulative_distances[safe_index] / total_distance_m


static func _zion_river_width_m(world_points: Array[Vector3], point_index: int, distance_t: float) -> float:
	var meander: float = sin(distance_t * TAU * 2.15 + 0.35) * 1.65
	var secondary: float = sin(distance_t * TAU * 5.10 + 1.20) * 0.85
	var bend_widening: float = _zion_river_bend_strength(world_points, point_index) * 3.4
	var width_m: float = ZION_RIVER_BASE_WIDTH_M + meander + secondary + bend_widening
	return clampf(width_m, ZION_RIVER_MIN_WIDTH_M, ZION_RIVER_MAX_WIDTH_M)


# Longitudinal run-out multiplier (1.0 except in the final runout_taper_m of a
# terminated ribbon, where it eases to ZION_RIVER_RUNOUT_WIDTH_FLOOR so the
# channel pinches to a thread and fades into the dry wash). Returns 1.0 when
# runout_taper_m <= 0 (west ribbon and any non-terminated ribbon are unaffected).
static func _zion_river_runout_scale(distance_m: float, total_distance_m: float, runout_taper_m: float) -> float:
	if runout_taper_m <= 0.0 or total_distance_m <= 0.001:
		return 1.0
	var taper_start_m: float = maxf(total_distance_m - runout_taper_m, 0.0)
	if distance_m <= taper_start_m:
		return 1.0
	var taper_span_m: float = maxf(total_distance_m - taper_start_m, 0.001)
	var taper_t: float = clampf((distance_m - taper_start_m) / taper_span_m, 0.0, 1.0)
	var eased: float = taper_t * taper_t * (3.0 - 2.0 * taper_t)
	return lerpf(1.0, ZION_RIVER_RUNOUT_WIDTH_FLOOR, eased)


static func _zion_river_riffle_weight(distance_t: float, width_m: float) -> float:
	var narrow_weight: float = clampf((10.3 - width_m) / 2.3, 0.0, 1.0)
	var cadence: float = sin(distance_t * TAU * 6.0 + 0.85) * 0.5 + 0.5
	return clampf(narrow_weight * 0.70 + cadence * 0.38, 0.0, 1.0)


static func _zion_river_bend_strength(world_points: Array[Vector3], point_index: int) -> float:
	if point_index <= 0 or point_index >= world_points.size() - 1:
		return 0.0
	var previous: Vector2 = Vector2(world_points[point_index - 1].x, world_points[point_index - 1].z)
	var current: Vector2 = Vector2(world_points[point_index].x, world_points[point_index].z)
	var next: Vector2 = Vector2(world_points[point_index + 1].x, world_points[point_index + 1].z)
	var in_dir: Vector2 = (current - previous).normalized()
	var out_dir: Vector2 = (next - current).normalized()
	var angle: float = absf(in_dir.angle_to(out_dir))
	return clampf(angle / 1.15, 0.0, 1.0)


static func _zion_river_bend_side(world_points: Array[Vector3], point_index: int) -> float:
	if point_index <= 0 or point_index >= world_points.size() - 1:
		return 1.0
	var previous: Vector2 = Vector2(world_points[point_index - 1].x, world_points[point_index - 1].z)
	var current: Vector2 = Vector2(world_points[point_index].x, world_points[point_index].z)
	var next: Vector2 = Vector2(world_points[point_index + 1].x, world_points[point_index + 1].z)
	var in_dir: Vector2 = (current - previous).normalized()
	var out_dir: Vector2 = (next - current).normalized()
	var turn_cross: float = in_dir.x * out_dir.y - in_dir.y * out_dir.x
	return -1.0 if turn_cross >= 0.0 else 1.0


static func _hash01(seed: float) -> float:
	return fposmod(sin(seed * 12.9898) * 43758.5453, 1.0)


static func _append_tangent(tangents: PackedFloat32Array, tangent: Vector3) -> void:
	tangents.append(tangent.x)
	tangents.append(tangent.y)
	tangents.append(tangent.z)
	tangents.append(1.0)


static func _water_material(resource_name: String, use_vertex_water_traits: bool = false) -> ShaderMaterial:
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
	material.set_shader_parameter("flow_direction", FLOW_DIRECTION)
	material.set_shader_parameter("foam_intensity", FOAM_INTENSITY)
	material.set_shader_parameter("ripple_tightness", RIPPLE_TIGHTNESS)
	material.set_shader_parameter("use_vertex_water_traits", use_vertex_water_traits)
	return material
