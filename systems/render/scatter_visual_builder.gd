class_name ScatterVisualBuilder
extends RefCounted

const GrassTuftScene: PackedScene = preload("res://assets/models/scatter/grass_tuft.glb")
const BoulderScene: PackedScene = preload("res://assets/models/scatter/boulder_a.glb")
const BranchScene: PackedScene = preload("res://assets/models/scatter/branch_a.glb")
const PineconeScene: PackedScene = preload("res://assets/models/scatter/pinecone.glb")
const FernClumpScene: PackedScene = preload("res://assets/models/scatter/fern_clump.glb")
const CattailScene: PackedScene = preload("res://assets/models/scatter/cattail.glb")

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
const GRASS_BLADE_LEAN_DEGREES: float = 11.0
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
const GRASS_SHADER_CODE: String = "shader_type spatial;\n" \
		+ "render_mode cull_disabled, diffuse_lambert, specular_schlick_ggx;\n" \
		+ "uniform vec4 blade_base_color : source_color = vec4(0.07, 0.18, 0.055, 1.0);\n" \
		+ "uniform vec4 blade_tip_color : source_color = vec4(0.48, 0.66, 0.23, 1.0);\n" \
		+ "uniform float blade_height_reference = 0.42;\n" \
		+ "uniform float wind_strength = 0.012;\n" \
		+ "uniform float wind_speed = 0.65;\n" \
		+ "uniform float wind_time_factor = 1.0;\n" \
		+ "uniform vec4 backlight_color : source_color = vec4(1.0, 0.62, 0.30, 1.0);\n" \
		+ "uniform float backlight_energy = 0.32;\n" \
		+ "varying float blade_height;\n" \
		+ "varying float tip_mix_shift;\n" \
		+ "void vertex() {\n" \
		+ "	blade_height = smoothstep(0.0, blade_height_reference, VERTEX.y);\n" \
		+ "	tip_mix_shift = INSTANCE_CUSTOM.w;\n" \
		+ "	float wind_phase = INSTANCE_CUSTOM.y * TAU;\n" \
		+ "	float wind_time = TIME * wind_speed * wind_time_factor;\n" \
		+ "	float sway = sin(wind_phase + wind_time);\n" \
		+ "	float flutter = sin(wind_phase * 1.73 + wind_time * 1.47 + INSTANCE_CUSTOM.z * 2.91);\n" \
		+ "	float gust = 0.88 + sin(wind_time * 0.37 + INSTANCE_CUSTOM.w * TAU) * 0.12;\n" \
		+ "	float bend = (sway * 0.72 + flutter * 0.28) * gust * wind_strength * blade_height * blade_height * INSTANCE_CUSTOM.x;\n" \
		+ "	VERTEX.x += bend;\n" \
		+ "	VERTEX.z += bend * (INSTANCE_CUSTOM.z * 0.7 - 0.35);\n" \
		+ "}\n" \
		+ "void fragment() {\n" \
		+ "	float tip_mix = smoothstep(0.0, 1.0, blade_height + (tip_mix_shift - 0.5) * 0.22);\n" \
		+ "	vec3 blade_color = mix(blade_base_color.rgb, blade_tip_color.rgb, tip_mix);\n" \
		+ "	blade_color = mix(blade_color, blade_base_color.rgb * 0.72, (1.0 - blade_height) * 0.24);\n" \
		+ "	ALBEDO = blade_color * COLOR.rgb;\n" \
		+ "	ROUGHNESS = 0.86;\n" \
		+ "	SPECULAR = 0.16;\n" \
		+ "	BACKLIGHT = backlight_color.rgb * backlight_energy * (0.35 + blade_height * 0.65) * COLOR.rgb;\n" \
		+ "}\n"


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
	var shader: Shader = Shader.new()
	shader.code = GRASS_SHADER_CODE
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = shader
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
		var yaw_jitter: float = (_pattern_unit(pattern_index, 3) - 0.5) * GRASS_BLADE_YAW_JITTER_DEGREES
		var blade_basis: Basis = Basis(Vector3.UP, deg_to_rad(yaw_degrees + float(i) * BLADE_SPIRAL_DEGREES + yaw_jitter))
		var lean_x: float = (_pattern_unit(pattern_index, 5) - 0.5) * GRASS_BLADE_LEAN_DEGREES
		var lean_z: float = (_pattern_unit(pattern_index, 7) - 0.5) * GRASS_BLADE_LEAN_DEGREES
		blade_basis = blade_basis * Basis(Vector3(1.0, 0.0, 0.0), deg_to_rad(lean_x)) * Basis(Vector3(0.0, 0.0, 1.0), deg_to_rad(lean_z))
		var blade_scale_factor: float = 0.62 + _pattern_unit(pattern_index, 11) * 0.66
		var blade_height_factor: float = 0.70 + _pattern_unit(pattern_index, 13) * 0.58
		blade_basis = blade_basis.scaled(Vector3(
			base_scale.x * blade_scale_factor * pass_width_factor,
			base_scale.y * blade_height_factor * pass_height_factor,
			base_scale.z * blade_scale_factor * pass_width_factor
		))
		var pass_index: int = i
		var pass_count: int = primary_blade_count
		if low_pass:
			pass_index = i - primary_blade_count
			pass_count = low_blade_count
		var blade_transform: Transform3D = Transform3D(blade_basis, _blade_offset(pass_index, pass_count, pass_radius, pattern_index))
		multimesh.set_instance_transform(i, blade_transform)
		var color_factor: float = 0.78 + _pattern_unit(pattern_index, 17) * 0.36
		var warm_shift: float = _pattern_unit(pattern_index, 31) - 0.5
		var cool_shift: float = _pattern_unit(pattern_index, 37) - 0.5
		if low_pass:
			color_factor *= 0.76
			warm_shift -= 0.08
		var red_factor: float = color_factor + warm_shift * 0.08
		var green_factor: float = color_factor + warm_shift * 0.04
		var blue_factor: float = color_factor + cool_shift * 0.05
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
	var z_values: Array[float] = [-0.42, -0.95, -1.48, -2.01, -2.54, -3.07, -3.6, -4.13, -4.66, -5.19, -5.72, -6.25, -6.78, -7.31, -7.84, -8.37, -8.9, -9.43]
	var x_lanes: Array[float] = [-2.75, 4.75, -1.25, 3.75, 1.25, 2.25, -2.25, 3.25, -1.75, 4.25, 0.75, 2.75]
	for x_index in range(x_lanes.size()):
		for z_index in range(z_values.size()):
			var z_source_index: int = z_index
			if x_index % 2 == 1:
				z_source_index = z_values.size() - 1 - z_index
			var drift_index: int = ((x_index * 7 + z_index * 3) % 5) - 2
			var candidate: Vector3 = Vector3(x_lanes[x_index] + float(drift_index) * 0.025, 0.0, z_values[z_source_index])
			if _append_if_spaced(positions, candidate, GRASS_MIN_SPACING):
				if positions.size() >= target_count:
					return positions
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
	var candidates: Array[Vector3] = [
		Vector3(-1.85, 0.0, -1.75),
		Vector3(-1.65, 0.0, -3.55),
		Vector3(0.85, 0.0, -2.05),
		Vector3(1.7, 0.0, -3.15),
		Vector3(4.35, 0.0, -4.75),
		Vector3(3.65, 0.0, -6.75)
	]
	for i in range(candidates.size()):
		if _append_if_spaced(positions, candidates[i], GRASS_OCCLUDER_MIN_SPACING):
			if positions.size() >= target_count:
				return positions
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
