extends Node

const SpikeRegionScene: PackedScene = preload("res://scenes/regions/spike_1km.tscn")
const EXPECTED_DETAIL_TILE_COUNT: int = 100
const EXPECTED_REGION_SIZE_M: float = 1000.0
const FLOAT_EPSILON: float = 0.001
const BOUNDS_EPSILON_M: float = 0.5
const TILE_INDEX_META: StringName = &"trailhead_tile_index"
const REGION_LOD_META: StringName = &"trailhead_region_lod"
const EXPECTED_FOLIAGE_LOD0_META: String = "foliage_lod0"
const EXPECTED_FOLIAGE_LOD1_META: String = "foliage_lod1"
const EXPECTED_FOLIAGE_LOD0_SHADOW_CASTING: int = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
const EXPECTED_FOLIAGE_LOD1_SHADOW_CASTING: int = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

var _scene_root: Node = null
var _errors: PackedStringArray = PackedStringArray()


func _ready() -> void:
	_scene_root = SpikeRegionScene.instantiate()
	add_child(_scene_root)
	call_deferred("_inspect")


func _inspect() -> void:
	if _scene_root == null:
		_errors.append("failed to instantiate spike_1km scene")
		_finish()
		return

	var terrain_root: Node = _require_node(_scene_root, "TerrainVisuals")
	if terrain_root == null:
		_finish()
		return

	var hlod: MeshInstance3D = _require_node(terrain_root, "TerrainHLOD") as MeshInstance3D
	if hlod == null:
		_errors.append("TerrainHLOD should be a MeshInstance3D")
	else:
		_require_mesh_surfaces(hlod, "TerrainHLOD")
		_require_xz_bounds(hlod, "TerrainHLOD", EXPECTED_REGION_SIZE_M, EXPECTED_REGION_SIZE_M)
		if absf(hlod.visibility_range_begin - 96.0) > FLOAT_EPSILON:
			_errors.append("TerrainHLOD visibility_range_begin expected 96.0, got " + str(hlod.visibility_range_begin))
		if absf(hlod.visibility_range_end) > FLOAT_EPSILON:
			_errors.append("TerrainHLOD visibility_range_end should be open-ended")

	var detail_root: Node = _require_node(terrain_root, "TerrainDetailTiles")
	if detail_root != null:
		_require_direct_mesh_child_count(detail_root, EXPECTED_DETAIL_TILE_COUNT)
		_inspect_detail_tiles(detail_root)

	var foliage_root: Node = _require_node(terrain_root, "FoliageCells")
	if foliage_root != null:
		_inspect_foliage_cells(foliage_root)
		var foliage_instances: int = _count_multimesh_render_instances(foliage_root)
		if foliage_instances <= 0:
			_errors.append("FoliageCells should contain nonzero foliage instances")

	var collision_count: int = _count_collision_objects(terrain_root)
	if collision_count > 0:
		_errors.append("spike_1km render scene should not contain collision objects: " + str(collision_count))

	var mesh_count: int = _count_mesh_instances(terrain_root)
	if mesh_count <= 0:
		_errors.append("spike_1km render scene should contain mesh instances")

	_finish()


func _inspect_detail_tiles(detail_root: Node) -> void:
	for child in detail_root.get_children():
		var mesh_instance: MeshInstance3D = child as MeshInstance3D
		if mesh_instance == null:
			_errors.append("TerrainDetailTiles child should be MeshInstance3D: " + String(child.name))
			continue
		_require_mesh_surfaces(mesh_instance, "TerrainDetailTiles/" + String(child.name))
		if mesh_instance.visibility_parent.is_empty():
			_errors.append("TerrainDetailTiles/" + String(child.name) + " should set visibility_parent")
		if absf(mesh_instance.visibility_range_end - 120.0) > FLOAT_EPSILON:
			_errors.append("TerrainDetailTiles/" + String(child.name) + " visibility_range_end expected 120.0, got " + str(mesh_instance.visibility_range_end))
		if not mesh_instance.has_meta(TILE_INDEX_META):
			_errors.append("TerrainDetailTiles/" + String(child.name) + " missing tile index metadata")


func _inspect_foliage_cells(foliage_root: Node) -> void:
	var lod0_count: int = 0
	var lod1_count: int = 0
	for child in foliage_root.get_children():
		var multimesh_instance: MultiMeshInstance3D = child as MultiMeshInstance3D
		if multimesh_instance == null:
			continue
		if not multimesh_instance.has_meta(REGION_LOD_META):
			_errors.append("FoliageCells/" + String(child.name) + " missing region LOD metadata")
			continue
		var region_lod: String = String(multimesh_instance.get_meta(REGION_LOD_META))
		if region_lod == EXPECTED_FOLIAGE_LOD0_META:
			lod0_count += 1
			if multimesh_instance.cast_shadow != EXPECTED_FOLIAGE_LOD0_SHADOW_CASTING:
				_errors.append("FoliageCells/" + String(child.name) + " LOD0 cast_shadow expected ON, got " + str(multimesh_instance.cast_shadow))
		elif region_lod == EXPECTED_FOLIAGE_LOD1_META:
			lod1_count += 1
			if multimesh_instance.cast_shadow != EXPECTED_FOLIAGE_LOD1_SHADOW_CASTING:
				_errors.append("FoliageCells/" + String(child.name) + " LOD1 cast_shadow expected OFF, got " + str(multimesh_instance.cast_shadow))
	if lod0_count <= 0:
		_errors.append("FoliageCells should contain foliage_lod0 cells")
	if lod1_count <= 0:
		_errors.append("FoliageCells should contain foliage_lod1 cells")


func _require_mesh_surfaces(mesh_instance: MeshInstance3D, label: String) -> void:
	if mesh_instance.mesh == null:
		_errors.append(label + " missing mesh")
		return
	if mesh_instance.mesh.get_surface_count() <= 0:
		_errors.append(label + " mesh has no surfaces")


func _require_xz_bounds(mesh_instance: MeshInstance3D, label: String, expected_x: float, expected_z: float) -> void:
	if mesh_instance.mesh == null:
		return
	var bounds: AABB = mesh_instance.mesh.get_aabb()
	if absf(bounds.size.x - expected_x) > BOUNDS_EPSILON_M:
		_errors.append(label + " bounds X expected " + str(expected_x) + ", got " + str(bounds.size.x))
	if absf(bounds.size.z - expected_z) > BOUNDS_EPSILON_M:
		_errors.append(label + " bounds Z expected " + str(expected_z) + ", got " + str(bounds.size.z))


func _require_direct_mesh_child_count(parent: Node, expected_count: int) -> void:
	var count: int = 0
	for child in parent.get_children():
		if child is MeshInstance3D:
			count += 1
	if count != expected_count:
		_errors.append(String(parent.name) + " direct MeshInstance3D count expected " + str(expected_count) + ", got " + str(count))


func _require_node(parent: Node, path: String) -> Node:
	var node: Node = parent.get_node_or_null(path)
	if node == null:
		_errors.append("missing node: " + path)
	return node


func _count_mesh_instances(parent: Node) -> int:
	var count: int = 0
	var mesh_instance: MeshInstance3D = parent as MeshInstance3D
	if mesh_instance != null and mesh_instance.mesh != null:
		count += 1
	for child in parent.get_children():
		count += _count_mesh_instances(child)
	return count


func _count_multimesh_instances(parent: Node) -> int:
	var count: int = 0
	var multimesh_instance: MultiMeshInstance3D = parent as MultiMeshInstance3D
	if multimesh_instance != null and multimesh_instance.multimesh != null:
		count += 1
	for child in parent.get_children():
		count += _count_multimesh_instances(child)
	return count


func _count_multimesh_render_instances(parent: Node) -> int:
	var count: int = 0
	var multimesh_instance: MultiMeshInstance3D = parent as MultiMeshInstance3D
	if multimesh_instance != null and multimesh_instance.multimesh != null:
		count += multimesh_instance.multimesh.instance_count
	for child in parent.get_children():
		count += _count_multimesh_render_instances(child)
	return count


func _count_collision_objects(parent: Node) -> int:
	var count: int = 0
	if parent is CollisionObject3D:
		count += 1
	for child in parent.get_children():
		count += _count_collision_objects(child)
	return count


func _finish() -> void:
	if _errors.is_empty():
		print("PASS spike_1km render inspector")
		get_tree().quit(0)
		return
	for error in _errors:
		push_error(error)
	get_tree().quit(1)
