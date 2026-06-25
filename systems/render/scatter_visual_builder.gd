class_name ScatterVisualBuilder
extends RefCounted

const GrassTuftScene: PackedScene = preload("res://assets/models/scatter/grass_tuft.glb")
const BoulderScene: PackedScene = preload("res://assets/models/scatter/boulder_a.glb")
const BranchScene: PackedScene = preload("res://assets/models/scatter/branch_a.glb")
const PineconeScene: PackedScene = preload("res://assets/models/scatter/pinecone.glb")
const FernClumpScene: PackedScene = preload("res://assets/models/scatter/fern_clump.glb")
const CattailScene: PackedScene = preload("res://assets/models/scatter/cattail.glb")
const GrassShader: Shader = preload("res://systems/render/grass_billboard.gdshader")

const EXPECTED_GRASS_TUFTS: int = 72
const EXPECTED_BOULDERS: int = 5
const EXPECTED_BRANCHES: int = 5
const EXPECTED_PINECONES: int = 8
const EXPECTED_FERN_CLUMPS: int = 6
const EXPECTED_CATTAILS: int = 5
const EXPECTED_GRASS_OCCLUDERS: int = 16

const GRASS_MIN_SPACING: float = 0.45
const GRASS_OCCLUDER_MIN_SPACING: float = 0.75
const BLADE_SPIRAL_DEGREES: float = 137.5
const GRASS_PRIMARY_BLADE_MULTIPLIER: int = 4
const GRASS_LOW_BLADE_MULTIPLIER: int = 4
const GRASS_LOW_BLADE_HEIGHT_FACTOR: float = 0.34
const GRASS_LOW_BLADE_WIDTH_FACTOR: float = 1.55
const GRASS_LOW_BLADE_RADIUS_FACTOR: float = 1.36
const GRASS_BLADE_YAW_JITTER_DEGREES: float = 42.0
const GRASS_BLADE_LEAN_DEGREES: float = 17.0
const GRASS_BLADE_LEAN_MAGNITUDE_MIN: float = 0.35
const GRASS_BLADE_LEAN_MAGNITUDE_RANGE: float = 0.95
const GRASS_BLADE_SPIRAL_YAW_WEIGHT: float = 0.35
const GRASS_BLADE_SCALE_MIN: float = 0.58
const GRASS_BLADE_SCALE_RANGE: float = 0.74
const GRASS_BLADE_HEIGHT_MIN: float = 0.66
const GRASS_BLADE_HEIGHT_RANGE: float = 0.66
const GRASS_BLADE_WIDTH_JITTER_MIN: float = 0.86
const GRASS_BLADE_WIDTH_JITTER_RANGE: float = 0.32
const GRASS_BLADE_VALUE_MIN: float = 0.70
const GRASS_BLADE_VALUE_RANGE: float = 0.46
const GRASS_BLADE_WARM_SHIFT: float = 0.12
const GRASS_BLADE_COOL_SHIFT: float = 0.09
const GRASS_BLADE_YELLOW_BIAS: float = 0.07
const GRASS_BLADE_RADIAL_JITTER: float = 0.14
const GRASS_BLADE_ANGLE_JITTER_DEGREES: float = 32.0
const GRASS_PATTERN_MODULUS: int = 997
const GRASS_PATTERN_INDEX_MULTIPLIER: int = 37
const GRASS_PATTERN_SALT_MULTIPLIER: int = 101
const GRASS_PATTERN_CLUMP_STRIDE: int = 53
const GRASS_WIND_CULL_MARGIN: float = 0.05
const GRASS_BASE_COLOR: Color = Color(0.07, 0.18, 0.055, 1.0)
const GRASS_TIP_COLOR: Color = Color(0.48, 0.66, 0.23, 1.0)
const SCATTER_X_MIN: float = -2.8
const SCATTER_X_MAX: float = 5.05
const SCATTER_Z_MIN: float = -9.55
const SCATTER_Z_MAX: float = -0.3
const SCATTER_EDGE_MARGIN: float = 0.04
const SCATTER_ANCHOR_EMPTY: Vector3 = Vector3(999.0, 999.0, 999.0)
const SCATTER_MAX_ATTEMPTS: int = 180
const SCATTER_PATTERN_MODULUS: int = 1543
const SCATTER_PATTERN_INDEX_MULTIPLIER: int = 67
const SCATTER_PATTERN_ATTEMPT_MULTIPLIER: int = 113
const SCATTER_PATTERN_SALT_MULTIPLIER: int = 191
const SCATTER_FULL_TURN_RADIANS: float = 6.28318530718
const NEGATIVE_TRAIL_X_HALF_WIDTH: float = 0.58
const NEGATIVE_TRAIL_Z_MIN: float = -5.85
const NEGATIVE_TRAIL_Z_MAX: float = 0.35
const NEGATIVE_OLD_CEDAR_APPROACH_CENTER: Vector2 = Vector2(0.0, -3.55)
const NEGATIVE_OLD_CEDAR_APPROACH_RADIUS: float = 0.72
const NEGATIVE_BOARDWALK_CENTER: Vector2 = Vector2(3.25, -4.15)
const NEGATIVE_BOARDWALK_RADIUS_X: float = 0.48
const NEGATIVE_BOARDWALK_RADIUS_Z: float = 0.76
const CROSSING_CHASE_QA_POSITION: Vector3 = Vector3(4.25, 0.0, -6.55)
const CROSSING_CHASE_QA_YAW_DEGREES: float = -70.0
const CHASE_CLEAR_CORRIDOR_LENGTH: float = 0.7
const CHASE_CLEAR_CORRIDOR_HALF_WIDTH: float = 0.18
const GRASS_OCCLUDER_BAND_X_MIN: float = -2.8
const GRASS_OCCLUDER_BAND_X_MAX: float = 4.7
const GRASS_OCCLUDER_BAND_Z_MIN: float = -7.4
const GRASS_OCCLUDER_BAND_Z_MAX: float = -0.9
const GRASS_CLUSTER_SEED_COUNT: int = 14
const GRASS_CLUSTER_RADIUS: float = 0.85
const GRASS_CLUSTER_OFFSET_BIAS: float = 0.18
const GRASS_CLUSTER_SALT: int = 317
const GRASS_CLUSTER_LATTICE_X_CELLS: int = 13
const GRASS_CLUSTER_LATTICE_Z_CELLS: int = 19
const OCCLUDER_CLUSTER_SEED_COUNT: int = 5
const OCCLUDER_CLUSTER_RADIUS: float = 1.15
const OCCLUDER_CLUSTER_OFFSET_BIAS: float = 0.22
const OCCLUDER_CLUSTER_SALT: int = 419
const OCCLUDER_CLUSTER_LATTICE_X_CELLS: int = 11
const OCCLUDER_CLUSTER_LATTICE_Z_CELLS: int = 13
const CLUSTER_NUDGE_STEP: float = 0.6
const CLUSTER_NUDGE_MAX_ATTEMPTS: int = 6


static func build_cedar_hollow(parent: Node3D) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = "ScatterVisuals"
	parent.add_child(root)
	_add_grass(root)
	_add_grass_occluders(root)
	_add_boulders(root)
	_add_branches(root)
	_add_pinecones(root)
	_add_ferns(root)
	_add_cattails(root)
	return root


static func _add_grass(parent: Node3D) -> void:
	var grass_mesh: Mesh = _extract_first_mesh(GrassTuftScene, "grass_tuft")
	if grass_mesh == null:
		return
	var grass_material: ShaderMaterial = _create_grass_material()
	var positions: Array[Vector3] = _grass_positions(maxi(GameConfig.grass_clump_count, 0))
	if positions.size() < GameConfig.grass_clump_count:
		push_error("ScatterVisualBuilder: failed to place requested grass clumps")
	for i in range(positions.size()):
		var blade_count: int = maxi(GameConfig.grass_blades_per_clump, 1)
		var radius: float = maxf(GameConfig.grass_clump_radius, 0.01)
		var yaw_degrees: float = float(i) * 37.0
		var scale_factor: float = 0.92 + float((i * 5) % 4) * 0.05
		var clump: MultiMeshInstance3D = _create_grass_clump(
			"grass_tuft_" + str(i + 1),
			grass_mesh,
			grass_material,
			positions[i],
			i,
			yaw_degrees,
			blade_count,
			radius,
			Vector3(scale_factor, 1.0 + float(i % 3) * 0.06, scale_factor)
		)
		parent.add_child(clump)


static func _add_grass_occluders(parent: Node3D) -> void:
	var grass_mesh: Mesh = _extract_first_mesh(GrassTuftScene, "grass_occluder")
	if grass_mesh == null:
		return
	var grass_material: ShaderMaterial = _create_grass_material()
	var positions: Array[Vector3] = _grass_occluder_positions(maxi(GameConfig.grass_occluder_band_count, 0))
	if positions.size() < GameConfig.grass_occluder_band_count:
		push_error("ScatterVisualBuilder: failed to place requested grass occluder bands")
	for i in range(positions.size()):
		var scale_y: float = 1.55 + float(i % 3) * 0.18
		var blade_count: int = maxi(GameConfig.grass_blades_per_clump + 2, 1)
		var radius: float = maxf(GameConfig.grass_clump_radius * 0.85, 0.01)
		var clump: MultiMeshInstance3D = _create_grass_clump(
			"grass_occluder_" + str(i + 1),
			grass_mesh,
			grass_material,
			positions[i],
			i + EXPECTED_GRASS_TUFTS,
			18.0 + float(i) * 41.0,
			blade_count,
			radius,
			Vector3(1.15, scale_y, 1.15)
		)
		parent.add_child(clump)


static func _add_boulders(parent: Node3D) -> void:
	var positions: Array[Vector3] = _boulder_positions(EXPECTED_BOULDERS)
	for i in range(mini(EXPECTED_BOULDERS, positions.size())):
		var scale_factor: float = 0.68 + _scatter_unit(i, 0, 71) * 0.32
		var scale: Vector3 = Vector3.ONE * scale_factor
		_instance_scatter(parent, BoulderScene, "boulder_" + str(i + 1), positions[i], Vector3(0.0, _scatter_yaw_degrees(i, 73), 0.0), scale)


static func _add_branches(parent: Node3D) -> void:
	var positions: Array[Vector3] = _branch_positions(EXPECTED_BRANCHES)
	for i in range(mini(EXPECTED_BRANCHES, positions.size())):
		var scale: Vector3 = Vector3.ONE * (0.92 + _scatter_unit(i, 0, 89) * 0.18)
		_instance_scatter(parent, BranchScene, "branch_" + str(i + 1), positions[i], Vector3(0.0, _scatter_yaw_degrees(i, 91), 0.0), scale)


static func _add_pinecones(parent: Node3D) -> void:
	var positions: Array[Vector3] = _pinecone_positions(EXPECTED_PINECONES)
	for i in range(mini(EXPECTED_PINECONES, positions.size())):
		var rotation: Vector3 = Vector3((_scatter_unit(i, 0, 101) - 0.5) * 22.0, _scatter_yaw_degrees(i, 103), 0.0)
		_instance_scatter(parent, PineconeScene, "pinecone_" + str(i + 1), positions[i], rotation, Vector3.ONE)


static func _add_ferns(parent: Node3D) -> void:
	var positions: Array[Vector3] = _fern_positions(EXPECTED_FERN_CLUMPS)
	for i in range(mini(EXPECTED_FERN_CLUMPS, positions.size())):
		var scale_factor: float = 0.72 + _scatter_unit(i, 0, 127) * 0.28
		var scale: Vector3 = Vector3.ONE * scale_factor
		_instance_scatter(parent, FernClumpScene, "fern_clump_" + str(i + 1), positions[i], Vector3(0.0, _scatter_yaw_degrees(i, 131), 0.0), scale)


static func _add_cattails(parent: Node3D) -> void:
	var positions: Array[Vector3] = _cattail_positions(EXPECTED_CATTAILS)
	for i in range(mini(EXPECTED_CATTAILS, positions.size())):
		var scale: Vector3 = Vector3.ONE * (0.72 + _scatter_unit(i, 0, 149) * 0.16)
		_instance_scatter(parent, CattailScene, "cattail_" + str(i + 1), positions[i], Vector3(0.0, _scatter_yaw_degrees(i, 151), 0.0), scale)


static func _instance_scatter(parent: Node3D, scene: PackedScene, node_name: String, position: Vector3, rotation: Vector3, scale: Vector3) -> Node3D:
	var instance: Node3D = scene.instantiate() as Node3D
	if instance == null:
		push_error("ScatterVisualBuilder: failed to instantiate " + node_name)
		return null
	instance.name = node_name
	instance.position = position
	instance.rotation_degrees = rotation
	instance.scale = scale
	parent.add_child(instance)
	_apply_visibility_range(instance, GameConfig.vis_range_scatter)
	return instance


static func _extract_first_mesh(scene: PackedScene, node_name: String) -> Mesh:
	var root: Node = scene.instantiate()
	if root == null:
		push_error("ScatterVisualBuilder: failed to instantiate " + node_name)
		return null
	var mesh: Mesh = _find_first_mesh(root)
	root.free()
	if mesh == null:
		push_error("ScatterVisualBuilder: failed to extract mesh from " + node_name)
	return mesh


static func _find_first_mesh(parent: Node) -> Mesh:
	var mesh_instance: MeshInstance3D = parent as MeshInstance3D
	if mesh_instance != null and mesh_instance.mesh != null:
		return mesh_instance.mesh
	for child in parent.get_children():
		var child_mesh: Mesh = _find_first_mesh(child)
		if child_mesh != null:
			return child_mesh
	return null


static func _create_grass_material() -> ShaderMaterial:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = GrassShader
	material.set_shader_parameter(&"blade_base_color", GRASS_BASE_COLOR)
	material.set_shader_parameter(&"blade_tip_color", GRASS_TIP_COLOR)
	var wind_strength: float = 0.0
	var wind_time_factor: float = 0.0
	if GameConfig.grass_wind_enabled:
		wind_strength = maxf(GameConfig.grass_wind_strength, 0.0)
		if not GameConfig.grass_wind_freeze_for_capture:
			wind_time_factor = 1.0
	var backlight_energy: float = 0.0
	if GameConfig.grass_backlight_enabled:
		backlight_energy = maxf(GameConfig.grass_backlight_energy, 0.0)
	material.set_shader_parameter(&"wind_strength", wind_strength)
	material.set_shader_parameter(&"wind_speed", maxf(GameConfig.grass_wind_speed, 0.0))
	material.set_shader_parameter(&"wind_time_factor", wind_time_factor)
	material.set_shader_parameter(&"backlight_color", GameConfig.grass_backlight_color)
	material.set_shader_parameter(&"backlight_energy", backlight_energy)
	return material


static func _create_grass_clump(node_name: String, mesh: Mesh, material: ShaderMaterial, position: Vector3, clump_index: int, yaw_degrees: float, blade_count: int, radius: float, base_scale: Vector3) -> MultiMeshInstance3D:
	var instance: MultiMeshInstance3D = MultiMeshInstance3D.new()
	instance.name = node_name
	instance.position = position
	instance.material_override = material
	instance.extra_cull_margin = GRASS_WIND_CULL_MARGIN
	instance.visibility_range_end = GameConfig.vis_range_grass
	var primary_blade_count: int = maxi(blade_count * GRASS_PRIMARY_BLADE_MULTIPLIER, 1)
	var low_blade_count: int = maxi(blade_count * GRASS_LOW_BLADE_MULTIPLIER, 0)
	var total_blade_count: int = primary_blade_count + low_blade_count
	var multimesh: MultiMesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = mesh
	multimesh.instance_count = total_blade_count
	for i in range(total_blade_count):
		var low_pass: bool = i >= primary_blade_count
		var pattern_index: int = clump_index * GRASS_PATTERN_CLUMP_STRIDE + i
		var pass_height_factor: float = 1.0
		var pass_width_factor: float = 1.0
		var pass_radius: float = radius
		if low_pass:
			pass_height_factor = GRASS_LOW_BLADE_HEIGHT_FACTOR
			pass_width_factor = GRASS_LOW_BLADE_WIDTH_FACTOR
			pass_radius = radius * GRASS_LOW_BLADE_RADIUS_FACTOR
		var full_yaw: float = _pattern_unit(pattern_index, 61) * 360.0
		var yaw_jitter: float = (_pattern_unit(pattern_index, 3) - 0.5) * GRASS_BLADE_YAW_JITTER_DEGREES
		var blade_yaw: float = yaw_degrees + float(i) * BLADE_SPIRAL_DEGREES * GRASS_BLADE_SPIRAL_YAW_WEIGHT + full_yaw + yaw_jitter
		var blade_basis: Basis = Basis(Vector3.UP, deg_to_rad(blade_yaw))
		var lean_magnitude: float = GRASS_BLADE_LEAN_MAGNITUDE_MIN + _pattern_unit(pattern_index, 67) * GRASS_BLADE_LEAN_MAGNITUDE_RANGE
		var lean_x: float = (_pattern_unit(pattern_index, 5) - 0.5) * GRASS_BLADE_LEAN_DEGREES * lean_magnitude
		var lean_z: float = (_pattern_unit(pattern_index, 7) - 0.5) * GRASS_BLADE_LEAN_DEGREES * lean_magnitude
		blade_basis = blade_basis * Basis(Vector3(1.0, 0.0, 0.0), deg_to_rad(lean_x)) * Basis(Vector3(0.0, 0.0, 1.0), deg_to_rad(lean_z))
		var blade_scale_factor: float = GRASS_BLADE_SCALE_MIN + _pattern_unit(pattern_index, 11) * GRASS_BLADE_SCALE_RANGE
		var blade_height_factor: float = GRASS_BLADE_HEIGHT_MIN + _pattern_unit(pattern_index, 13) * GRASS_BLADE_HEIGHT_RANGE
		var blade_width_jitter: float = GRASS_BLADE_WIDTH_JITTER_MIN + _pattern_unit(pattern_index, 71) * GRASS_BLADE_WIDTH_JITTER_RANGE
		blade_basis = blade_basis.scaled(Vector3(
			base_scale.x * blade_scale_factor * pass_width_factor * blade_width_jitter,
			base_scale.y * blade_height_factor * pass_height_factor,
			base_scale.z * blade_scale_factor * pass_width_factor * blade_width_jitter
		))
		var pass_index: int = i
		var pass_count: int = primary_blade_count
		if low_pass:
			pass_index = i - primary_blade_count
			pass_count = low_blade_count
		var blade_transform: Transform3D = Transform3D(blade_basis, _blade_offset(pass_index, pass_count, pass_radius, pattern_index))
		multimesh.set_instance_transform(i, blade_transform)
		var color_factor: float = GRASS_BLADE_VALUE_MIN + _pattern_unit(pattern_index, 17) * GRASS_BLADE_VALUE_RANGE
		var warm_shift: float = _pattern_unit(pattern_index, 31) - 0.5
		var cool_shift: float = _pattern_unit(pattern_index, 37) - 0.5
		var yellow_bias: float = _pattern_unit(pattern_index, 79) - 0.5
		if low_pass:
			color_factor *= 0.76
			warm_shift -= 0.08
		var red_factor: float = color_factor + warm_shift * GRASS_BLADE_WARM_SHIFT + yellow_bias * GRASS_BLADE_YELLOW_BIAS
		var green_factor: float = color_factor + warm_shift * (GRASS_BLADE_WARM_SHIFT * 0.5) + yellow_bias * (GRASS_BLADE_YELLOW_BIAS * 0.5)
		var blue_factor: float = color_factor + cool_shift * GRASS_BLADE_COOL_SHIFT - yellow_bias * (GRASS_BLADE_YELLOW_BIAS * 0.9)
		multimesh.set_instance_color(i, Color(red_factor, green_factor, blue_factor, 1.0))
		var wind_weight: float = 0.54 + _pattern_unit(pattern_index, 19) * 0.64
		if low_pass:
			wind_weight *= 0.44
		multimesh.set_instance_custom_data(i, Color(wind_weight, _pattern_unit(pattern_index, 23), _pattern_unit(pattern_index, 29), _pattern_unit(pattern_index, 41)))
	instance.multimesh = multimesh
	_add_bounds_reference(instance, mesh, base_scale)
	return instance


static func _blade_offset(blade_index: int, blade_count: int, radius: float, pattern_index: int) -> Vector3:
	if blade_index == 0:
		return Vector3.ZERO
	var angle_jitter: float = (_pattern_unit(pattern_index, 43) - 0.5) * GRASS_BLADE_ANGLE_JITTER_DEGREES
	var angle: float = deg_to_rad(float(blade_index) * BLADE_SPIRAL_DEGREES + angle_jitter)
	var denominator: float = maxf(float(blade_count), 1.0)
	var ring_fraction: float = (float(blade_index) + 0.5) / denominator
	var radial_jitter: float = 1.0 + (_pattern_unit(pattern_index, 47) - 0.5) * GRASS_BLADE_RADIAL_JITTER
	var offset_radius: float = radius * (0.20 + ring_fraction * 0.80) * radial_jitter
	return Vector3(cos(angle) * offset_radius, 0.0, sin(angle) * offset_radius)


static func _pattern_unit(index: int, salt: int) -> float:
	var value: int = (index * GRASS_PATTERN_INDEX_MULTIPLIER + salt * GRASS_PATTERN_SALT_MULTIPLIER) % GRASS_PATTERN_MODULUS
	return float(value) / float(GRASS_PATTERN_MODULUS - 1)


static func _add_bounds_reference(parent: Node3D, mesh: Mesh, reference_scale: Vector3) -> void:
	# Cedar visual inspector bounds still walk MeshInstance3D nodes, while the visible clump is MultiMesh.
	var reference: MeshInstance3D = MeshInstance3D.new()
	reference.name = "mesh_bounds_reference"
	reference.mesh = mesh
	reference.scale = reference_scale
	reference.visible = false
	reference.visibility_range_end = GameConfig.vis_range_grass
	parent.add_child(reference)


static func _boulder_positions(target_count: int) -> Array[Vector3]:
	var anchors: Array[Vector3] = _empty_scatter_anchors(target_count)
	if target_count > 0:
		anchors[0] = Vector3(-2.65, 0.3, -8.5)
	if target_count > 4:
		anchors[4] = Vector3(3.15, 0.0, -7.25)
	var macro_centers: Array[Vector3] = [
		Vector3(-2.25, 0.24, -8.35),
		Vector3(-1.65, 0.16, -6.95),
		Vector3(3.75, 0.0, -7.15),
		Vector3(4.72, 0.0, -6.82)
	]
	return _fractal_scatter_positions(target_count, anchors, macro_centers, 0.70, 0.82, 0.30, 17)


static func _branch_positions(target_count: int) -> Array[Vector3]:
	var anchors: Array[Vector3] = _empty_scatter_anchors(target_count)
	if target_count > 4:
		anchors[4] = Vector3(-0.9, 0.02, -9.45)
	var macro_centers: Array[Vector3] = [
		Vector3(-1.95, 0.02, -0.55),
		Vector3(1.85, 0.02, -3.75),
		Vector3(1.05, 0.02, -5.80),
		Vector3(3.95, 0.02, -5.88),
		Vector3(-1.10, 0.02, -9.10)
	]
	return _fractal_scatter_positions(target_count, anchors, macro_centers, 1.10, 0.46, 0.24, 29)


static func _pinecone_positions(target_count: int) -> Array[Vector3]:
	var anchors: Array[Vector3] = _empty_scatter_anchors(target_count)
	if target_count > 7:
		anchors[7] = Vector3(-1.9, 0.24, -8.9)
	var macro_centers: Array[Vector3] = [
		Vector3(-1.35, 0.02, -0.55),
		Vector3(-2.55, 0.02, -1.20),
		Vector3(1.35, 0.02, -1.55),
		Vector3(2.45, 0.02, -2.75),
		Vector3(1.55, 0.02, -4.75),
		Vector3(3.15, 0.02, -4.40),
		Vector3(4.40, 0.02, -6.00),
		Vector3(-2.35, 0.24, -8.45),
		Vector3(-1.35, 0.24, -9.25)
	]
	return _fractal_scatter_positions(target_count, anchors, macro_centers, 0.55, 0.34, 0.18, 43)


static func _fern_positions(target_count: int) -> Array[Vector3]:
	var anchors: Array[Vector3] = _empty_scatter_anchors(target_count)
	if target_count > 0:
		anchors[0] = Vector3(2.2, 0.0, -4.65)
	if target_count > 5:
		anchors[5] = Vector3(3.05, 0.0, -7.65)
	var macro_centers: Array[Vector3] = [
		Vector3(2.50, 0.0, -4.85),
		Vector3(3.55, 0.0, -5.15),
		Vector3(2.88, 0.0, -6.52),
		Vector3(3.75, 0.0, -6.95),
		Vector3(4.85, 0.0, -6.65),
		Vector3(3.12, 0.0, -7.20),
		Vector3(2.45, 0.0, -7.15)
	]
	return _fractal_scatter_positions(target_count, anchors, macro_centers, 0.70, 0.30, 0.18, 59)


static func _cattail_positions(target_count: int) -> Array[Vector3]:
	var anchors: Array[Vector3] = _empty_scatter_anchors(target_count)
	if target_count > 0:
		anchors[0] = Vector3(3.95, 0.0, -6.25)
	if target_count > 4:
		anchors[4] = Vector3(4.45, 0.0, -7.55)
	var macro_centers: Array[Vector3] = [
		Vector3(4.28, 0.0, -6.20),
		Vector3(4.78, 0.0, -6.95),
		Vector3(4.10, 0.0, -7.28),
		Vector3(4.55, 0.0, -7.38),
		Vector3(3.75, 0.0, -7.25)
	]
	return _fractal_scatter_positions(target_count, anchors, macro_centers, 0.35, 0.22, 0.12, 67)


static func _empty_scatter_anchors(target_count: int) -> Array[Vector3]:
	var anchors: Array[Vector3] = []
	for i in range(target_count):
		anchors.append(SCATTER_ANCHOR_EMPTY)
	return anchors


static func _fractal_scatter_positions(target_count: int, anchor_positions: Array[Vector3], macro_centers: Array[Vector3], min_spacing: float, macro_radius: float, micro_radius: float, salt: int) -> Array[Vector3]:
	var positions: Array[Vector3] = _empty_scatter_anchors(target_count)
	for i in range(mini(target_count, anchor_positions.size())):
		if _has_scatter_position(anchor_positions[i]):
			positions[i] = anchor_positions[i]
	for i in range(target_count):
		if _has_scatter_position(positions[i]):
			continue
		var placed: bool = false
		for attempt in range(SCATTER_MAX_ATTEMPTS):
			var candidate: Vector3 = _fractal_scatter_candidate(macro_centers, i, attempt, macro_radius, micro_radius, salt)
			if _scatter_candidate_allowed(candidate, positions, min_spacing):
				positions[i] = candidate
				placed = true
				break
		if not placed:
			push_error("ScatterVisualBuilder: failed to place fractal scatter index " + str(i))
			positions[i] = _clamp_scatter_position(macro_centers[mini(i, maxi(macro_centers.size() - 1, 0))] if not macro_centers.is_empty() else Vector3.ZERO)
	return positions


static func _fractal_scatter_candidate(macro_centers: Array[Vector3], item_index: int, attempt: int, macro_radius: float, micro_radius: float, salt: int) -> Vector3:
	if macro_centers.is_empty():
		return Vector3.ZERO
	var macro_index: int = (item_index + attempt + salt) % macro_centers.size()
	var macro_center: Vector3 = macro_centers[macro_index]
	var micro_angle: float = _scatter_unit(item_index, attempt, salt + 3) * SCATTER_FULL_TURN_RADIANS
	var micro_distance: float = macro_radius * (0.18 + _scatter_unit(item_index, attempt, salt + 5) * 0.82)
	var micro_center: Vector3 = macro_center + Vector3(cos(micro_angle) * micro_distance, 0.0, sin(micro_angle) * micro_distance)
	var item_angle: float = _scatter_unit(item_index, attempt, salt + 7) * SCATTER_FULL_TURN_RADIANS
	var item_distance: float = micro_radius * (0.22 + _scatter_unit(item_index, attempt, salt + 11) * 0.78)
	var candidate: Vector3 = micro_center + Vector3(cos(item_angle) * item_distance, 0.0, sin(item_angle) * item_distance)
	candidate.y = macro_center.y
	return _clamp_scatter_position(candidate)


static func _scatter_candidate_allowed(candidate: Vector3, positions: Array[Vector3], min_spacing: float) -> bool:
	if candidate.x < SCATTER_X_MIN or candidate.x > SCATTER_X_MAX or candidate.z < SCATTER_Z_MIN or candidate.z > SCATTER_Z_MAX:
		return false
	if _is_protected_negative_space(candidate):
		return false
	for i in range(positions.size()):
		if not _has_scatter_position(positions[i]):
			continue
		var existing: Vector3 = positions[i]
		var delta: Vector2 = Vector2(candidate.x - existing.x, candidate.z - existing.z)
		if delta.length() < min_spacing:
			return false
	return true


static func _clamp_scatter_position(position: Vector3) -> Vector3:
	return Vector3(
		clampf(position.x, SCATTER_X_MIN + SCATTER_EDGE_MARGIN, SCATTER_X_MAX - SCATTER_EDGE_MARGIN),
		position.y,
		clampf(position.z, SCATTER_Z_MIN + SCATTER_EDGE_MARGIN, SCATTER_Z_MAX - SCATTER_EDGE_MARGIN)
	)


static func _has_scatter_position(position: Vector3) -> bool:
	return position.x < SCATTER_ANCHOR_EMPTY.x - 1.0


static func _scatter_unit(index: int, attempt: int, salt: int) -> float:
	var value: int = (index * SCATTER_PATTERN_INDEX_MULTIPLIER + attempt * SCATTER_PATTERN_ATTEMPT_MULTIPLIER + salt * SCATTER_PATTERN_SALT_MULTIPLIER) % SCATTER_PATTERN_MODULUS
	return float(value) / float(SCATTER_PATTERN_MODULUS - 1)


static func _scatter_yaw_degrees(index: int, salt: int) -> float:
	return _scatter_unit(index, 0, salt) * 360.0


static func _is_protected_negative_space(position: Vector3) -> bool:
	if position.z > NEGATIVE_TRAIL_Z_MIN and position.z < NEGATIVE_TRAIL_Z_MAX and absf(position.x) < NEGATIVE_TRAIL_X_HALF_WIDTH:
		return true
	if _inside_circle_xz(position, NEGATIVE_OLD_CEDAR_APPROACH_CENTER, NEGATIVE_OLD_CEDAR_APPROACH_RADIUS):
		return true
	if _inside_ellipse_xz(position, NEGATIVE_BOARDWALK_CENTER, NEGATIVE_BOARDWALK_RADIUS_X, NEGATIVE_BOARDWALK_RADIUS_Z):
		return true
	return _blocks_crossing_chase_corridor(position)


static func _inside_circle_xz(position: Vector3, center: Vector2, radius: float) -> bool:
	var dx: float = position.x - center.x
	var dz: float = position.z - center.y
	return dx * dx + dz * dz < radius * radius


static func _inside_ellipse_xz(position: Vector3, center: Vector2, radius_x: float, radius_z: float) -> bool:
	var dx: float = (position.x - center.x) / radius_x
	var dz: float = (position.z - center.y) / radius_z
	return dx * dx + dz * dz < 1.0


static func _blocks_crossing_chase_corridor(position: Vector3) -> bool:
	var basis: Basis = Basis(Vector3.UP, deg_to_rad(CROSSING_CHASE_QA_YAW_DEGREES))
	var forward: Vector3 = -basis.z.normalized()
	var forward_xz: Vector2 = Vector2(forward.x, forward.z).normalized()
	var delta: Vector2 = Vector2(
		position.x - CROSSING_CHASE_QA_POSITION.x,
		position.z - CROSSING_CHASE_QA_POSITION.z
	)
	var along: float = delta.dot(forward_xz)
	if along <= 0.0 or along > CHASE_CLEAR_CORRIDOR_LENGTH:
		return false
	var lateral: float = absf(delta.x * forward_xz.y - delta.y * forward_xz.x)
	return lateral < CHASE_CLEAR_CORRIDOR_HALF_WIDTH


static func _apply_visibility_range(parent: Node, visibility_range_end: float) -> void:
	var geometry_instance: GeometryInstance3D = parent as GeometryInstance3D
	if geometry_instance != null:
		geometry_instance.visibility_range_end = visibility_range_end
	for child in parent.get_children():
		_apply_visibility_range(child, visibility_range_end)


static func _grass_positions(target_count: int) -> Array[Vector3]:
	var positions: Array[Vector3] = [
		Vector3(-2.3, 0.0, -0.9),
		Vector3(-1.8, 0.0, -1.6),
		Vector3(-2.4, 0.0, -2.4),
		Vector3(-1.55, 0.0, -3.2),
		Vector3(-2.15, 0.0, -4.1),
		Vector3(-1.25, 0.0, -4.8),
		Vector3(1.15, 0.0, -0.8),
		Vector3(1.85, 0.0, -1.35),
		Vector3(2.3, 0.0, -2.05),
		Vector3(0.85, 0.0, -2.85),
		Vector3(2.1, 0.0, -3.55),
		Vector3(1.35, 0.0, -4.2),
		Vector3(2.65, 0.0, -4.85),
		Vector3(3.75, 0.0, -4.15),
		Vector3(4.25, 0.0, -5.35),
		Vector3(3.5, 0.0, -5.9),
		Vector3(4.7, 0.0, -6.35),
		Vector3(2.9, 0.0, -6.9)
	]
	_trim_positions(positions, target_count)
	if positions.size() >= target_count:
		return positions
	_fill_clustered(
		positions,
		target_count,
		GRASS_CLUSTER_SEED_COUNT,
		GRASS_CLUSTER_RADIUS,
		GRASS_MIN_SPACING,
		SCATTER_X_MIN + SCATTER_EDGE_MARGIN,
		SCATTER_X_MAX - SCATTER_EDGE_MARGIN,
		SCATTER_Z_MIN + SCATTER_EDGE_MARGIN,
		SCATTER_Z_MAX - SCATTER_EDGE_MARGIN,
		GRASS_CLUSTER_SALT,
		GRASS_CLUSTER_OFFSET_BIAS,
		GRASS_CLUSTER_LATTICE_X_CELLS,
		GRASS_CLUSTER_LATTICE_Z_CELLS
	)
	return positions


static func _grass_occluder_positions(target_count: int) -> Array[Vector3]:
	var positions: Array[Vector3] = [
		Vector3(-2.65, 0.0, -1.25),
		Vector3(-2.55, 0.0, -2.75),
		Vector3(-2.35, 0.0, -4.35),
		Vector3(-1.45, 0.0, -5.35),
		Vector3(1.35, 0.0, -1.05),
		Vector3(2.35, 0.0, -2.35),
		Vector3(2.75, 0.0, -3.85),
		Vector3(3.55, 0.0, -5.15),
		Vector3(4.55, 0.0, -6.05),
		Vector3(2.65, 0.0, -7.25)
	]
	_trim_positions(positions, target_count)
	if positions.size() >= target_count:
		return positions
	_fill_clustered(
		positions,
		target_count,
		OCCLUDER_CLUSTER_SEED_COUNT,
		OCCLUDER_CLUSTER_RADIUS,
		GRASS_OCCLUDER_MIN_SPACING,
		GRASS_OCCLUDER_BAND_X_MIN + SCATTER_EDGE_MARGIN,
		GRASS_OCCLUDER_BAND_X_MAX - SCATTER_EDGE_MARGIN,
		GRASS_OCCLUDER_BAND_Z_MIN + SCATTER_EDGE_MARGIN,
		GRASS_OCCLUDER_BAND_Z_MAX - SCATTER_EDGE_MARGIN,
		OCCLUDER_CLUSTER_SALT,
		OCCLUDER_CLUSTER_OFFSET_BIAS,
		OCCLUDER_CLUSTER_LATTICE_X_CELLS,
		OCCLUDER_CLUSTER_LATTICE_Z_CELLS
	)
	return positions


static func _trim_positions(positions: Array[Vector3], target_count: int) -> void:
	while positions.size() > target_count:
		positions.pop_back()


static func _append_if_spaced(positions: Array[Vector3], candidate: Vector3, min_spacing: float) -> bool:
	for i in range(positions.size()):
		var existing: Vector3 = positions[i]
		var delta: Vector2 = Vector2(candidate.x - existing.x, candidate.z - existing.z)
		if delta.length() < min_spacing:
			return false
	positions.append(candidate)
	return true


static func _fill_clustered(positions: Array[Vector3], target_count: int, cluster_count: int, cluster_radius: float, min_spacing: float, bounds_x_min: float, bounds_x_max: float, bounds_z_min: float, bounds_z_max: float, salt: int, offset_bias: float, lattice_x_cells: int, lattice_z_cells: int) -> void:
	if positions.size() >= target_count or cluster_count <= 0:
		return
	var cluster_centers: Array[Vector3] = _cluster_centers(cluster_count, bounds_x_min, bounds_x_max, bounds_z_min, bounds_z_max, salt)
	var cluster_weights: Array[float] = []
	var weight_total: float = 0.0
	for c in range(cluster_count):
		var weight: float = 0.45 + _scatter_unit(c, 2, salt + 17) * 1.55
		cluster_weights.append(weight)
		weight_total += weight
	var cumulative: Array[float] = []
	var running: float = 0.0
	for c in range(cluster_count):
		var share: float = cluster_weights[c] / weight_total if weight_total > 0.0 else 1.0 / float(cluster_count)
		running += share
		cumulative.append(running)
	var slot: int = positions.size()
	while positions.size() < target_count:
		var placed: bool = false
		for attempt in range(SCATTER_MAX_ATTEMPTS):
			var cluster_pick: int = _weighted_cluster_pick(slot, attempt, salt, cumulative)
			var center: Vector3 = cluster_centers[cluster_pick]
			var offset_angle: float = _scatter_unit(slot, attempt, salt + 29) * SCATTER_FULL_TURN_RADIANS
			var offset_distance: float = cluster_radius * (offset_bias + _scatter_unit(slot, attempt, salt + 31) * (1.0 - offset_bias))
			var candidate: Vector3 = center + Vector3(cos(offset_angle) * offset_distance, 0.0, sin(offset_angle) * offset_distance)
			candidate = Vector3(clampf(candidate.x, bounds_x_min, bounds_x_max), 0.0, clampf(candidate.z, bounds_z_min, bounds_z_max))
			if _is_protected_negative_space(candidate):
				continue
			if _append_if_spaced(positions, candidate, min_spacing):
				placed = true
				break
		if not placed:
			var lattice_ok: bool = _lattice_append_spaced(positions, min_spacing, bounds_x_min, bounds_x_max, bounds_z_min, bounds_z_max, slot, lattice_x_cells, lattice_z_cells, salt)
			if not lattice_ok:
				push_error("ScatterVisualBuilder: clustered scatter lattice exhausted before reaching target count " + str(target_count))
				break
		slot += 1


static func _cluster_centers(cluster_count: int, bounds_x_min: float, bounds_x_max: float, bounds_z_min: float, bounds_z_max: float, salt: int) -> Array[Vector3]:
	var centers: Array[Vector3] = []
	for c in range(cluster_count):
		var center: Vector3 = Vector3(
			lerpf(bounds_x_min, bounds_x_max, _scatter_unit(c, 0, salt + 7)),
			0.0,
			lerpf(bounds_z_min, bounds_z_max, _scatter_unit(c, 1, salt + 13))
		)
		var nudge: int = 0
		while _is_protected_negative_space(center) and nudge < CLUSTER_NUDGE_MAX_ATTEMPTS:
			var angle: float = _scatter_unit(c, nudge + 3, salt + 19) * SCATTER_FULL_TURN_RADIANS
			center = center + Vector3(cos(angle) * CLUSTER_NUDGE_STEP, 0.0, sin(angle) * CLUSTER_NUDGE_STEP)
			center = Vector3(clampf(center.x, bounds_x_min, bounds_x_max), 0.0, clampf(center.z, bounds_z_min, bounds_z_max))
			nudge += 1
		centers.append(center)
	return centers


static func _weighted_cluster_pick(slot: int, attempt: int, salt: int, cumulative: Array[float]) -> int:
	var roll: float = _scatter_unit(slot, attempt, salt + 23)
	var count: int = cumulative.size()
	for c in range(count):
		if roll <= cumulative[c]:
			return c
	return count - 1


static func _lattice_append_spaced(positions: Array[Vector3], min_spacing: float, bounds_x_min: float, bounds_x_max: float, bounds_z_min: float, bounds_z_max: float, slot: int, lattice_x_cells: int, lattice_z_cells: int, salt: int) -> bool:
	var cell_count: int = lattice_x_cells * lattice_z_cells
	for cell in range(cell_count):
		var ix: int = cell % lattice_x_cells
		var iz: int = cell / lattice_x_cells
		if iz % 2 == 1:
			ix = lattice_x_cells - 1 - ix
		var base_x: float = lerpf(bounds_x_min, bounds_x_max, (float(ix) + 0.5) / float(lattice_x_cells))
		var base_z: float = lerpf(bounds_z_min, bounds_z_max, (float(iz) + 0.5) / float(lattice_z_cells))
		var jitter_span: float = (bounds_x_max - bounds_x_min) / float(lattice_x_cells) * 0.45
		var jitter_x: float = (_scatter_unit(slot, cell, salt + 43) - 0.5) * jitter_span
		var jitter_z: float = (_scatter_unit(slot, cell, salt + 47) - 0.5) * jitter_span
		var candidate: Vector3 = Vector3(clampf(base_x + jitter_x, bounds_x_min, bounds_x_max), 0.0, clampf(base_z + jitter_z, bounds_z_min, bounds_z_max))
		if _is_protected_negative_space(candidate):
			continue
		if _append_if_spaced(positions, candidate, min_spacing):
			return true
	return false
