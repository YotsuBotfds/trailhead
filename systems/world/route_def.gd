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
@export var segment_ids: Array[StringName] = []
@export var segment_spawn_ids: Array[StringName] = []
@export var segment_target_landmark_ids: Array[StringName] = []
@export var segment_waypoint_offsets: Array[int] = []
@export var segment_waypoint_counts: Array[int] = []
@export var segment_waypoints: Array[Vector3] = []
@export var segment_max_ticks: Array[int] = []
@export var segment_target_radii: Array[float] = []


func validate() -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	if spawn_positions.size() < spawn_ids.size():
		errors.append("spawn_positions has fewer entries than spawn_ids")
	if spawn_yaw_degrees.size() < spawn_ids.size():
		errors.append("spawn_yaw_degrees has fewer entries than spawn_ids")
	if landmark_display_names.size() < landmark_ids.size():
		errors.append("landmark_display_names has fewer entries than landmark_ids")
	if landmark_positions.size() < landmark_ids.size():
		errors.append("landmark_positions has fewer entries than landmark_ids")
	if landmark_radii.size() < landmark_ids.size():
		errors.append("landmark_radii has fewer entries than landmark_ids")
	if segment_spawn_ids.size() < segment_ids.size():
		errors.append("segment_spawn_ids has fewer entries than segment_ids")
	if segment_target_landmark_ids.size() < segment_ids.size():
		errors.append("segment_target_landmark_ids has fewer entries than segment_ids")
	if segment_waypoint_offsets.size() < segment_ids.size():
		errors.append("segment_waypoint_offsets has fewer entries than segment_ids")
	if segment_waypoint_counts.size() < segment_ids.size():
		errors.append("segment_waypoint_counts has fewer entries than segment_ids")
	for i in range(segment_ids.size()):
		var spawn_id: StringName = segment_spawn_id(segment_ids[i], &"")
		if spawn_id == &"" or not has_spawn(spawn_id):
			errors.append("segment " + String(segment_ids[i]) + " references missing spawn")
		var target_id: StringName = segment_target_landmark_id(segment_ids[i], &"")
		if target_id == &"" or not has_landmark(target_id):
			errors.append("segment " + String(segment_ids[i]) + " references missing target landmark")
		var offset: int = _array_int(segment_waypoint_offsets, i, 0)
		var count: int = _array_int(segment_waypoint_counts, i, 0)
		if offset < 0 or count < 0 or offset + count > segment_waypoints.size():
			errors.append("segment " + String(segment_ids[i]) + " has invalid waypoint range")
	return errors


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


func has_segment(segment_id: StringName) -> bool:
	return _index_of_id(segment_ids, segment_id) != -1


func segment_spawn_id(segment_id: StringName, fallback: StringName) -> StringName:
	var index: int = _index_of_id(segment_ids, segment_id)
	if index == -1 or index >= segment_spawn_ids.size():
		return fallback
	return segment_spawn_ids[index]


func segment_target_landmark_id(segment_id: StringName, fallback: StringName) -> StringName:
	var index: int = _index_of_id(segment_ids, segment_id)
	if index == -1 or index >= segment_target_landmark_ids.size():
		return fallback
	return segment_target_landmark_ids[index]


func segment_waypoint_path(segment_id: StringName) -> Array[Vector3]:
	var points: Array[Vector3] = []
	var index: int = _index_of_id(segment_ids, segment_id)
	if index == -1:
		return points
	var offset: int = _array_int(segment_waypoint_offsets, index, 0)
	var count: int = _array_int(segment_waypoint_counts, index, 0)
	if offset < 0 or count < 0:
		return points
	var end_index: int = mini(offset + count, segment_waypoints.size())
	for i in range(offset, end_index):
		points.append(segment_waypoints[i])
	return points


func segment_max_ticks_for(segment_id: StringName, fallback: int) -> int:
	var index: int = _index_of_id(segment_ids, segment_id)
	var value: int = _array_int(segment_max_ticks, index, fallback)
	if value <= 0:
		return fallback
	return value


func segment_target_radius_for(segment_id: StringName, fallback: float) -> float:
	var index: int = _index_of_id(segment_ids, segment_id)
	if index == -1 or index >= segment_target_radii.size():
		return fallback
	var value: float = segment_target_radii[index]
	if value <= 0.0:
		return fallback
	return value


func _index_of_id(ids: Array[StringName], query_id: StringName) -> int:
	for i in range(ids.size()):
		if ids[i] == query_id:
			return i
	return -1


func _array_int(values: Array[int], index: int, fallback: int) -> int:
	if index < 0 or index >= values.size():
		return fallback
	return values[index]
