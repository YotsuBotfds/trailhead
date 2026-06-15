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
const GRASS_SHADER_CODE: String = "shader_type spatial;\n" \
		+ "render_mode cull_disabled, diffuse_lambert, specular_schlick_ggx;\n" \
		+ "uniform vec4 blade_base_color : source_color = vec4(0.07, 0.18, 0.055, 1.0);\n" \
		+ "uniform vec4 blade_tip_color : source_color = vec4(0.48, 0.66, 0.23, 1.0);\n" \
		+ "uniform float blade_height_reference = 0.42;\n" \
		+ "uniform float wind_strength = 0.012;\n" \
		+ "varying float blade_height;\n" \
		+ "varying float tip_mix_shift;\n" \
		+ "void vertex() {\n" \
		+ "	blade_height = smoothstep(0.0, blade_height_reference, VERTEX.y);\n" \
		+ "	tip_mix_shift = INSTANCE_CUSTOM.w;\n" \
		+ "	float wind_phase = INSTANCE_CUSTOM.y * 6.28318530718;\n" \
		+ "	float sway = sin(wind_phase);\n" \
		+ "	float flutter = sin(wind_phase * 1.73 + INSTANCE_CUSTOM.z * 2.91);\n" \
		+ "	float bend = (sway * 0.75 + flutter * 0.25) * wind_strength * blade_height * blade_height * INSTANCE_CUSTOM.x;\n" \
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
	var positions: Array[Vector3] = [
		Vector3(-2.65, 0.3, -8.5),
		Vector3(-0.85, 0.22, -8.2),
		Vector3(-1.8, 0.16, -6.75),
		Vector3(4.9, 0.0, -6.95),
		Vector3(3.15, 0.0, -7.25)
	]
	for i in range(mini(EXPECTED_BOULDERS, positions.size())):
		var scale_factor: float = 0.75 + float(i % 3) * 0.15
		if i == 3:
			scale_factor = 0.62
		var scale: Vector3 = Vector3.ONE * scale_factor
		_instance_scatter(parent, BoulderScene, "boulder_" + str(i + 1), positions[i], Vector3(0.0, float(i) * 41.0, 0.0), scale)


static func _add_branches(parent: Node3D) -> void:
	var positions: Array[Vector3] = [
		Vector3(-1.95, 0.02, -0.35),
		Vector3(1.9, 0.02, -3.75),
		Vector3(0.95, 0.02, -5.85),
		Vector3(3.95, 0.02, -5.85),
		Vector3(-0.9, 0.02, -9.45)
	]
	for i in range(mini(EXPECTED_BRANCHES, positions.size())):
		_instance_scatter(parent, BranchScene, "branch_" + str(i + 1), positions[i], Vector3(0.0, float(i) * 29.0, 0.0), Vector3.ONE)


static func _add_pinecones(parent: Node3D) -> void:
	var positions: Array[Vector3] = [
		Vector3(-1.35, 0.02, -0.55),
		Vector3(-2.55, 0.02, -1.2),
		Vector3(1.35, 0.02, -1.55),
		Vector3(2.45, 0.02, -2.75),
		Vector3(1.55, 0.02, -4.75),
		Vector3(3.15, 0.02, -4.4),
		Vector3(4.4, 0.02, -6.0),
		Vector3(-1.9, 0.24, -8.9)
	]
	for i in range(mini(EXPECTED_PINECONES, positions.size())):
		var rotation: Vector3 = Vector3(float(i % 2) * 12.0, float(i) * 47.0, 0.0)
		_instance_scatter(parent, PineconeScene, "pinecone_" + str(i + 1), positions[i], rotation, Vector3.ONE)


static func _add_ferns(parent: Node3D) -> void:
	var positions: Array[Vector3] = [
		Vector3(2.2, 0.0, -4.65),
		Vector3(3.45, 0.0, -4.95),
		Vector3(2.75, 0.0, -6.45),
		Vector3(3.75, 0.0, -6.95),
		Vector3(4.85, 0.0, -6.65),
		Vector3(3.05, 0.0, -7.65)
	]
	for i in range(mini(EXPECTED_FERN_CLUMPS, positions.size())):
		var scale_factor: float = 0.8 + float(i % 3) * 0.12
		if i == 4:
			scale_factor = 0.68
		var scale: Vector3 = Vector3.ONE * scale_factor
		_instance_scatter(parent, FernClumpScene, "fern_clump_" + str(i + 1), positions[i], Vector3(0.0, float(i) * 53.0, 0.0), scale)


static func _add_cattails(parent: Node3D) -> void:
	var positions: Array[Vector3] = [
		Vector3(3.95, 0.0, -6.25),
		Vector3(4.55, 0.0, -6.1),
		Vector3(4.9, 0.0, -7.05),
		Vector3(3.85, 0.0, -7.35),
		Vector3(4.45, 0.0, -7.55)
	]
	for i in range(mini(EXPECTED_CATTAILS, positions.size())):
		var scale: Vector3 = Vector3.ONE * (0.75 + float(i % 2) * 0.1)
		_instance_scatter(parent, CattailScene, "cattail_" + str(i + 1), positions[i], Vector3(0.0, float(i) * 29.0, 0.0), scale)


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
	return material


static func _create_grass_clump(node_name: String, mesh: Mesh, material: ShaderMaterial, position: Vector3, clump_index: int, yaw_degrees: float, blade_count: int, radius: float, base_scale: Vector3) -> MultiMeshInstance3D:
	var instance: MultiMeshInstance3D = MultiMeshInstance3D.new()
	instance.name = node_name
	instance.position = position
	instance.material_override = material
	instance.extra_cull_margin = GRASS_WIND_CULL_MARGIN
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
	parent.add_child(reference)


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
