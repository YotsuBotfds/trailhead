extends Node

const DesertPropBuilderScript: GDScript = preload("res://systems/render/desert_prop_builder.gd")
const FLOAT_EPSILON: float = 0.002
const MAX_PROP_HEIGHT: float = 0.75
const MAX_PROP_WIDTH: float = 0.90
const PROP_IDS: Array[StringName] = [
	&"trailhead_sign",
	&"rock_cairn",
	&"bleached_dead_log",
	&"marker_post",
	&"desert_shrub"
]

var _errors: PackedStringArray = PackedStringArray()


func _ready() -> void:
	call_deferred("_inspect")


func _inspect() -> void:
	for prop_id in PROP_IDS:
		for seed in range(2):
			var prop: Node3D = DesertPropBuilderScript.build_prop(prop_id, seed)
			add_child(prop)
			_inspect_prop(prop_id, seed, prop)
			remove_child(prop)
			prop.queue_free()
	_finish()


func _inspect_prop(prop_id: StringName, seed: int, prop: Node3D) -> void:
	if prop == null:
		_errors.append(String(prop_id) + " seed " + str(seed) + " returned null")
		return
	var mesh_instances: Array[MeshInstance3D] = []
	_collect_mesh_instances(prop, mesh_instances)
	if mesh_instances.is_empty():
		_errors.append(String(prop_id) + " seed " + str(seed) + " produced no mesh instances")
		return
	var combined_aabb: AABB = AABB()
	var has_aabb: bool = false
	for mesh_instance in mesh_instances:
		_inspect_mesh_instance(prop_id, seed, mesh_instance)
		var mesh: Mesh = mesh_instance.mesh
		if mesh == null:
			continue
		var local_aabb: AABB = mesh.get_aabb()
		var transformed_aabb: AABB = mesh_instance.transform * local_aabb
		if not has_aabb:
			combined_aabb = transformed_aabb
			has_aabb = true
		else:
			combined_aabb = combined_aabb.merge(transformed_aabb)
	if not has_aabb:
		_errors.append(String(prop_id) + " seed " + str(seed) + " has no valid AABB")
		return
	if absf(combined_aabb.position.y) > FLOAT_EPSILON:
		_errors.append(String(prop_id) + " seed " + str(seed) + " base should sit at y=0, got " + str(combined_aabb.position.y))
	if combined_aabb.size.y <= 0.02 or combined_aabb.size.y > MAX_PROP_HEIGHT:
		_errors.append(String(prop_id) + " seed " + str(seed) + " height is out of RC prop range: " + str(combined_aabb.size.y))
	if combined_aabb.size.x <= 0.02 or combined_aabb.size.x > MAX_PROP_WIDTH:
		_errors.append(String(prop_id) + " seed " + str(seed) + " width is out of RC prop range: " + str(combined_aabb.size.x))
	if combined_aabb.size.z <= 0.005 or combined_aabb.size.z > MAX_PROP_WIDTH:
		_errors.append(String(prop_id) + " seed " + str(seed) + " depth is out of RC prop range: " + str(combined_aabb.size.z))
	print("ok: " + String(prop_id) + " seed " + str(seed) + " meshes=" + str(mesh_instances.size()) + " aabb=" + str(combined_aabb.size))


func _inspect_mesh_instance(prop_id: StringName, seed: int, mesh_instance: MeshInstance3D) -> void:
	var mesh: Mesh = mesh_instance.mesh
	if mesh == null:
		_errors.append(String(prop_id) + " seed " + str(seed) + " mesh instance " + String(mesh_instance.name) + " has no mesh")
		return
	if mesh.get_surface_count() <= 0:
		_errors.append(String(prop_id) + " seed " + str(seed) + " mesh " + String(mesh_instance.name) + " has no surfaces")
		return
	for surface_index in range(mesh.get_surface_count()):
		var material: Material = mesh.surface_get_material(surface_index)
		var primitive_mesh: PrimitiveMesh = mesh as PrimitiveMesh
		if material == null and primitive_mesh != null:
			material = primitive_mesh.material
		if material == null:
			_errors.append(String(prop_id) + " seed " + str(seed) + " mesh " + String(mesh_instance.name) + " surface " + str(surface_index) + " has no material")


func _collect_mesh_instances(node: Node, mesh_instances: Array[MeshInstance3D]) -> void:
	var mesh_instance: MeshInstance3D = node as MeshInstance3D
	if mesh_instance != null:
		mesh_instances.append(mesh_instance)
	for child in node.get_children():
		_collect_mesh_instances(child, mesh_instances)


func _finish() -> void:
	if _errors.is_empty():
		print("ok: desert prop builder library instantiated")
		get_tree().quit(0)
		return
	for error in _errors:
		push_error(error)
	get_tree().quit(1)
