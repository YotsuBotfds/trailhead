class_name MinimapView
extends Control

const BG_COLOR: Color = Color(0.04, 0.05, 0.045, 0.58)
const BORDER_COLOR: Color = Color(0.88, 0.75, 0.55, 0.58)
const ROUTE_COLOR: Color = Color(0.86, 0.70, 0.45, 0.62)
const LANDMARK_COLOR: Color = Color(0.93, 0.86, 0.68, 0.82)
const NEAREST_COLOR: Color = Color(1.0, 0.74, 0.36, 0.72)
const PLAYER_COLOR: Color = Color(0.34, 0.78, 0.92, 0.92)
const HEADING_COLOR: Color = Color(0.86, 0.96, 1.0, 0.88)

var _route: Resource = null
var _vehicle: Node = null
var _process_usec_last_frame: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(GameConfig.minimap_size, GameConfig.minimap_size)
	custom_minimum_size = Vector2(GameConfig.minimap_size, GameConfig.minimap_size)


func configure(route: Resource, vehicle: Node) -> void:
	_route = route
	_vehicle = vehicle
	queue_redraw()


func _process(_delta: float) -> void:
	var process_start_usec: int = Time.get_ticks_usec()
	_process_body()
	_process_usec_last_frame = maxi(Time.get_ticks_usec() - process_start_usec, 0)


func process_usec_last_frame() -> int:
	return _process_usec_last_frame


func _process_body() -> void:
	if _route != null and _vehicle != null:
		queue_redraw()


func _draw() -> void:
	if _route == null:
		return
	var panel_rect: Rect2 = Rect2(Vector2.ZERO, size)
	draw_rect(panel_rect, BG_COLOR, true)
	draw_rect(panel_rect, BORDER_COLOR, false, 1.0)
	_draw_route_segments()
	_draw_landmarks()
	_draw_vehicle()


func _draw_route_segments() -> void:
	var segment_ids: Array = _route.get("segment_ids")
	for value in segment_ids:
		var segment_id: StringName = StringName(value)
		var points: Array[Vector2] = _map_points_for_segment(segment_id)
		for i in range(1, points.size()):
			draw_line(points[i - 1], points[i], ROUTE_COLOR, GameConfig.minimap_route_line_width)


func _map_points_for_segment(segment_id: StringName) -> Array[Vector2]:
	var points: Array[Vector2] = []
	var spawn_id: StringName = _route.call("segment_spawn_id", segment_id, &"")
	if spawn_id != &"":
		var spawn_transform: Transform3D = _route.call("spawn_transform", spawn_id)
		points.append(_world_to_map(spawn_transform.origin))
	var waypoint_positions: Array[Vector3] = _route.call("segment_waypoint_path", segment_id)
	for waypoint in waypoint_positions:
		points.append(_world_to_map(waypoint))
	var target_id: StringName = _route.call("segment_target_landmark_id", segment_id, &"")
	if target_id != &"":
		points.append(_world_to_map(_route.call("landmark_position", target_id)))
	return points


func _draw_landmarks() -> void:
	var landmark_positions: Array = _route.get("landmark_positions")
	var landmark_ids: Array = _route.get("landmark_ids")
	var landmark_count: int = mini(landmark_positions.size(), landmark_ids.size())
	var nearest_index: int = _nearest_landmark_index()
	for i in range(landmark_count):
		var position: Vector3 = landmark_positions[i]
		var map_position: Vector2 = _world_to_map(position)
		if i == nearest_index:
			draw_circle(map_position, GameConfig.minimap_dot_radius * 2.0, NEAREST_COLOR)
		draw_circle(map_position, GameConfig.minimap_dot_radius, LANDMARK_COLOR)


func _draw_vehicle() -> void:
	if _vehicle == null:
		return
	var state: RefCounted = _vehicle.call("get_state")
	var vehicle_position: Vector3 = state.get("position")
	var vehicle_basis: Basis = state.get("basis")
	var map_position: Vector2 = _world_to_map(vehicle_position)
	var forward: Vector3 = -vehicle_basis.z.normalized()
	var heading: Vector2 = Vector2(forward.x, -forward.z)
	if heading.length_squared() > 0.0001:
		heading = heading.normalized()
		draw_line(map_position, map_position + heading * GameConfig.minimap_heading_length, HEADING_COLOR, 2.0)
	draw_circle(map_position, GameConfig.minimap_player_radius, PLAYER_COLOR)


func _nearest_landmark_index() -> int:
	if _vehicle == null:
		return -1
	var state: RefCounted = _vehicle.call("get_state")
	var vehicle_position: Vector3 = state.get("position")
	var landmark_positions: Array = _route.get("landmark_positions")
	var best_index: int = -1
	var best_distance_sq: float = INF
	for i in range(landmark_positions.size()):
		var landmark_position: Vector3 = landmark_positions[i]
		var delta: Vector3 = landmark_position - vehicle_position
		delta.y = 0.0
		var distance_sq: float = delta.length_squared()
		if distance_sq < best_distance_sq:
			best_distance_sq = distance_sq
			best_index = i
	return best_index


func _world_to_map(world_position: Vector3) -> Vector2:
	var bounds_min: Vector3 = _route.get("bounds_min")
	var bounds_max: Vector3 = _route.get("bounds_max")
	var width: float = maxf(bounds_max.x - bounds_min.x, 0.001)
	var depth: float = maxf(bounds_max.z - bounds_min.z, 0.001)
	var map_min: float = GameConfig.minimap_inner_padding
	var map_max_x: float = maxf(size.x - GameConfig.minimap_inner_padding, map_min)
	var map_max_y: float = maxf(size.y - GameConfig.minimap_inner_padding, map_min)
	var x_t: float = clampf((world_position.x - bounds_min.x) / width, 0.0, 1.0)
	var z_t: float = clampf((world_position.z - bounds_min.z) / depth, 0.0, 1.0)
	return Vector2(lerpf(map_min, map_max_x, x_t), lerpf(map_max_y, map_min, z_t))
