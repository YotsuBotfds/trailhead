class_name AmbientLifeBuilder
extends RefCounted

const ROOT_NAME: String = "AmbientLife"
const BIRD_PREFIX: String = "bird_"
const BIRD_COUNT_META: StringName = &"trailhead_ambient_life_bird_count"
const PHASE_META: StringName = &"trailhead_ambient_life_phase"
const BIRD_INDEX_META: StringName = &"trailhead_ambient_life_bird_index"
const BIRD_PATTERN_MODULUS: int = 1613
const BIRD_PATTERN_INDEX_MULTIPLIER: int = 73
const BIRD_PATTERN_SALT_MULTIPLIER: int = 199
const ORIENTATION_SAMPLE_PHASE_DELTA: float = 0.018
const BASIS_EPSILON: float = 0.000001


static func build(parent: Node3D) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = ROOT_NAME
	if parent != null:
		parent.add_child(root)
	var bird_count: int = bird_effective_count()
	var bird_mesh: ArrayMesh = _bird_mesh()
	var bird_material: StandardMaterial3D = _bird_material()
	for bird_index in range(bird_count):
		var bird: MeshInstance3D = _bird_instance(bird_index, bird_mesh, bird_material)
		root.add_child(bird)
	root.set_meta(BIRD_COUNT_META, bird_count)
	apply_phase(root, 0.0)
	return root


static func bird_effective_count() -> int:
	return GameConfig.resolved_ambient_life_bird_count()


static func apply_phase(root: Node3D, phase: float) -> void:
	if root == null:
		return
	var safe_phase: float = fposmod(phase, TAU)
	root.set_meta(PHASE_META, safe_phase)
	for child in root.get_children():
		var bird: MeshInstance3D = child as MeshInstance3D
		if bird == null:
			continue
		var bird_index: int = int(bird.get_meta(BIRD_INDEX_META, 0))
		bird.transform = bird_transform_for_phase(safe_phase, bird_index)


static func bird_transform_for_phase(phase: float, bird_index: int) -> Transform3D:
	var position: Vector3 = bird_position_for_phase(phase, bird_index)
	var future_position: Vector3 = bird_position_for_phase(phase + ORIENTATION_SAMPLE_PHASE_DELTA, bird_index)
	var velocity: Vector3 = future_position - position
	var roll: float = sin(phase * 0.67 + _bird_unit(bird_index, 41) * TAU) * GameConfig.ambient_life_bird_roll_radians
	var base_scale: float = GameConfig.ambient_life_bird_scale * lerpf(0.82, 1.18, _bird_unit(bird_index, 43))
	var flap_phase: float = phase * GameConfig.ambient_life_bird_wing_flap_rate + _bird_unit(bird_index, 47) * TAU
	var flap_scale: float = 1.0 + sin(flap_phase) * clampf(GameConfig.ambient_life_bird_wing_flap_amplitude, 0.0, 0.85)
	var basis: Basis = _flight_basis(velocity, roll)
	basis = basis.scaled(Vector3(base_scale, base_scale * flap_scale, base_scale))
	return Transform3D(basis, position)


static func bird_position_for_phase(phase: float, bird_index: int) -> Vector3:
	var center: Vector3 = GameConfig.ambient_life_bird_center + Vector3(
		(_bird_unit(bird_index, 3) - 0.5) * GameConfig.ambient_life_bird_center_spread.x,
		(_bird_unit(bird_index, 5) - 0.5) * GameConfig.ambient_life_bird_center_spread.y,
		(_bird_unit(bird_index, 7) - 0.5) * GameConfig.ambient_life_bird_center_spread.z
	)
	var radius_x: float = lerpf(
		GameConfig.ambient_life_bird_radius_min,
		GameConfig.ambient_life_bird_radius_max,
		_bird_unit(bird_index, 11)
	)
	var radius_z: float = lerpf(
		GameConfig.ambient_life_bird_radius_min * 0.68,
		GameConfig.ambient_life_bird_radius_max * 0.86,
		_bird_unit(bird_index, 13)
	)
	var vertical_radius: float = maxf(GameConfig.ambient_life_bird_vertical_radius, 0.0) * lerpf(0.70, 1.20, _bird_unit(bird_index, 17))
	var seed_phase: float = _bird_unit(bird_index, 19) * TAU
	var speed_scale: float = lerpf(0.72, 1.18, _bird_unit(bird_index, 23))
	var theta: float = phase * speed_scale + seed_phase
	var lissajous: float = theta * lerpf(0.72, 0.94, _bird_unit(bird_index, 29)) + _bird_unit(bird_index, 31) * TAU
	return Vector3(
		center.x + cos(theta) * radius_x + sin(lissajous * 0.5) * radius_x * 0.14,
		center.y + sin(theta * 1.37 + seed_phase * 0.31) * vertical_radius,
		center.z + sin(lissajous) * radius_z
	)


static func _bird_instance(bird_index: int, mesh: ArrayMesh, material: StandardMaterial3D) -> MeshInstance3D:
	var bird: MeshInstance3D = MeshInstance3D.new()
	bird.name = BIRD_PREFIX + str(bird_index + 1)
	bird.mesh = mesh
	bird.material_override = material
	bird.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bird.extra_cull_margin = maxf(GameConfig.ambient_life_bird_scale * 2.0, 1.0)
	bird.visibility_range_end = maxf(GameConfig.ambient_life_bird_visibility_range, 0.0)
	bird.set_meta(BIRD_INDEX_META, bird_index)
	return bird


static func _bird_mesh() -> ArrayMesh:
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var normal: Vector3 = Vector3.UP
	_append_triangle(vertices, normals, Vector3(0.0, 0.0, -0.20), Vector3(-0.62, 0.0, 0.02), Vector3(-0.08, 0.0, 0.10), normal)
	_append_triangle(vertices, normals, Vector3(0.0, 0.0, -0.20), Vector3(0.08, 0.0, 0.10), Vector3(0.62, 0.0, 0.02), normal)
	_append_triangle(vertices, normals, Vector3(-0.07, 0.0, -0.15), Vector3(0.07, 0.0, -0.15), Vector3(0.0, 0.0, 0.24), normal)
	var arrays: Array[Variant] = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.resource_name = "ambient_life_bird_mesh"
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _append_triangle(vertices: PackedVector3Array, normals: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, normal: Vector3) -> void:
	vertices.append(a)
	vertices.append(b)
	vertices.append(c)
	normals.append(normal)
	normals.append(normal)
	normals.append(normal)


static func _bird_material() -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.resource_name = "ambient_life_bird_material"
	material.albedo_color = GameConfig.ambient_life_bird_color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


static func _flight_basis(velocity: Vector3, roll_radians: float) -> Basis:
	var forward: Vector3 = velocity
	if forward.length_squared() <= BASIS_EPSILON:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	var right: Vector3 = forward.cross(Vector3.UP)
	if right.length_squared() <= BASIS_EPSILON:
		right = Vector3.RIGHT
	right = right.normalized()
	var up: Vector3 = right.cross(forward).normalized()
	var roll_basis: Basis = Basis(forward, roll_radians)
	right = roll_basis * right
	up = roll_basis * up
	return Basis(right, up, -forward).orthonormalized()


static func _bird_unit(index: int, salt: int) -> float:
	var value: int = (index * BIRD_PATTERN_INDEX_MULTIPLIER + salt * BIRD_PATTERN_SALT_MULTIPLIER) % BIRD_PATTERN_MODULUS
	if value < 0:
		value += BIRD_PATTERN_MODULUS
	return float(value) / float(BIRD_PATTERN_MODULUS - 1)
