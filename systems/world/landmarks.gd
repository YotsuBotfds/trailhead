class_name Landmarks
extends Node

var _route: Resource = null
var _reached: Dictionary[StringName, bool] = {}


func configure(route: Resource) -> void:
	_route = route
	_reached.clear()


func sample_position(position: Vector3) -> void:
	if _route == null:
		return
	var landmark_ids: Array[StringName] = _route.get("landmark_ids")
	for value in landmark_ids:
		var landmark_id: StringName = StringName(value)
		if _reached.has(landmark_id):
			continue
		var landmark_position: Vector3 = _route.call("landmark_position", landmark_id)
		var radius: float = float(_route.call("landmark_radius", landmark_id, GameConfig.default_landmark_radius))
		var delta: Vector3 = landmark_position - position
		delta.y = 0.0
		if delta.length() <= radius:
			_reached[landmark_id] = true
			EventBus.world_reached_landmark.emit(landmark_id)


func was_reached(landmark_id: StringName) -> bool:
	return _reached.has(landmark_id)
