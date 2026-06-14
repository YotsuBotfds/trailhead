class_name RouteDef
extends Resource

@export var scene_id: StringName = &""
@export var bounds_min: Vector3 = Vector3.ZERO
@export var bounds_max: Vector3 = Vector3.ZERO
@export var spawn_ids: Array[StringName] = []
@export var spawn_positions: Array[Vector3] = []
@export var spawn_yaw_degrees: Array[float] = []
@export var landmark_ids: Array[StringName] = []
@export var landmark_display_names: Array[String] = []
@export var landmark_positions: Array[Vector3] = []
@export var landmark_radii: Array[float] = []


func has_spawn(spawn_id: StringName) -> bool:
	return _index_of_id(spawn_ids, spawn_id) != -1


func spawn_transform(spawn_id: StringName) -> Transform3D:
	var index: int = _index_of_id(spawn_ids, spawn_id)
	if index == -1:
		return Transform3D(Basis.IDENTITY, Vector3.ZERO)
	var yaw_degrees: float = 0.0
	if index < spawn_yaw_degrees.size():
		yaw_degrees = spawn_yaw_degrees[index]
	return Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_degrees)), spawn_positions[index])


func has_landmark(landmark_id: StringName) -> bool:
	return _index_of_id(landmark_ids, landmark_id) != -1


func landmark_position(landmark_id: StringName) -> Vector3:
	var index: int = _index_of_id(landmark_ids, landmark_id)
	if index == -1:
		return Vector3.ZERO
	return landmark_positions[index]


func landmark_radius(landmark_id: StringName, fallback: float) -> float:
	var index: int = _index_of_id(landmark_ids, landmark_id)
	if index == -1 or index >= landmark_radii.size():
		return fallback
	return landmark_radii[index]


func _index_of_id(ids: Array[StringName], query_id: StringName) -> int:
	for i in range(ids.size()):
		if ids[i] == query_id:
			return i
	return -1
