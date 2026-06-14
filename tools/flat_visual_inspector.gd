extends Node

const FlatPlaneScene: PackedScene = preload("res://scenes/flat_plane.tscn")
const FLOAT_EPSILON: float = 0.001
const CAMERA_COMPOSITION_TOLERANCE: float = 0.01
const CAMERA_PITCH_TOLERANCE_DEG: float = 0.25

var _scene_root: Node = null
var _errors: PackedStringArray = PackedStringArray()


func _ready() -> void:
	_scene_root = FlatPlaneScene.instantiate()
	add_child(_scene_root)
	call_deferred("_inspect")


func _inspect() -> void:
	if _scene_root == null:
		_errors.append("failed to instantiate flat plane scene")
		_finish()
		return
	_inspect_flat_ground()
	var vehicle: Node = _require_node(_scene_root, "Vehicle")
	_inspect_vehicle_visuals(_scene_root, vehicle)
	var chase_camera: Camera3D = _require_node(_scene_root, "ChaseCamera") as Camera3D
	_inspect_chase_camera(vehicle, chase_camera)
	_require_node(_scene_root, "SurfaceMap")
	_require_node(_scene_root, "Sun")
	_finish()


func _inspect_flat_ground() -> void:
	var ground: StaticBody3D = _require_node(_scene_root, "flat_ground__surf_packed_dirt") as StaticBody3D
	if ground == null:
		return
	if not ground.is_in_group("surf_packed_dirt"):
		_errors.append("flat ground should be in surf_packed_dirt group")
	var collision: CollisionShape3D = _require_node(ground, "Collision") as CollisionShape3D
	if collision == null:
		return
	var box: BoxShape3D = collision.shape as BoxShape3D
	if box == null:
		_errors.append("flat ground collision should use BoxShape3D")
		return
	if box.size.distance_to(GameConfig.flat_ground_size) > FLOAT_EPSILON:
		_errors.append("flat ground collision size expected " + str(GameConfig.flat_ground_size) + ", got " + str(box.size))
	if collision.position.distance_to(GameConfig.flat_ground_center) > FLOAT_EPSILON:
		_errors.append("flat ground collision center expected " + str(GameConfig.flat_ground_center) + ", got " + str(collision.position))
	_require_node(ground, "GroundVisual")


func _inspect_vehicle_visuals(host: Node, vehicle: Node) -> void:
	if host == null or vehicle == null:
		return
	var visual_root: Node = _require_node(vehicle, "PhysicsBody/VisualRoot")
	if visual_root == null:
		return
	_require_node(visual_root, "body")
	_require_node(visual_root, "nose")
	_require_node(visual_root, "roll_cage")
	_require_node_position(visual_root, "wheel_front_left", Vector3(-0.08, -0.015, -0.10), FLOAT_EPSILON)
	_require_node_position(visual_root, "wheel_front_right", Vector3(0.08, -0.015, -0.10), FLOAT_EPSILON)
	_require_node_position(visual_root, "wheel_rear_left", Vector3(-0.08, -0.015, 0.10), FLOAT_EPSILON)
	_require_node_position(visual_root, "wheel_rear_right", Vector3(0.08, -0.015, 0.10), FLOAT_EPSILON)
	_require_wheel_socket_mesh(visual_root, "wheel_front_left")
	_require_wheel_socket_mesh(visual_root, "wheel_front_right")
	_require_wheel_socket_mesh(visual_root, "wheel_rear_left")
	_require_wheel_socket_mesh(visual_root, "wheel_rear_right")
	var visual_collision_count: int = _count_collision_objects(visual_root)
	if visual_collision_count > 0:
		_errors.append("flat vehicle VisualRoot contains collision objects: " + str(visual_collision_count))
	var visual_mesh_count: int = _count_mesh_instances(visual_root)
	if visual_mesh_count < 9:
		_errors.append("flat vehicle VisualRoot should include chassis, roll cage, and wheel meshes")
	_require_vehicle_steering_visuals(host, visual_root)


func _require_vehicle_steering_visuals(host: Node, visual_root: Node) -> void:
	var vehicle_input: RefCounted = host.get("_vehicle_input") as RefCounted
	if vehicle_input == null:
		_errors.append("FlatPlaneHost should expose vehicle input for visual wheel updates")
		return
	vehicle_input.set("steer", 1.0)
	host.call("_update_visual_wheels", GameConfig.FIXED_DT)
	var expected_steer: float = deg_to_rad(GameConfig.steer_limit_deg)
	_require_node_rotation_y(visual_root, "wheel_front_left", expected_steer, FLOAT_EPSILON)
	_require_node_rotation_y(visual_root, "wheel_front_right", expected_steer, FLOAT_EPSILON)
	_require_node_rotation_y(visual_root, "wheel_rear_left", 0.0, FLOAT_EPSILON)
	_require_node_rotation_y(visual_root, "wheel_rear_right", 0.0, FLOAT_EPSILON)
	vehicle_input.set("steer", 0.0)
	host.call("_update_visual_wheels", GameConfig.FIXED_DT)


func _inspect_chase_camera(vehicle: Node, chase_camera: Camera3D) -> void:
	if vehicle == null or chase_camera == null:
		return
	var state: RefCounted = vehicle.call("get_state")
	var vehicle_position: Vector3 = state.get("position")
	if not chase_camera.current:
		_errors.append("flat ChaseCamera should be current")
	if absf(chase_camera.fov - GameConfig.cam_fov_base) > FLOAT_EPSILON:
		_errors.append("flat ChaseCamera should start at base FOV")
	if chase_camera.global_position.y <= vehicle_position.y:
		_errors.append("flat ChaseCamera should start above the vehicle")
	if chase_camera.global_position.z <= vehicle_position.z:
		_errors.append("flat ChaseCamera should start behind the spawn")
	_require_chase_camera_composition(state, chase_camera, "flat ChaseCamera")


func _require_chase_camera_composition(state: RefCounted, chase_camera: Camera3D, context: String) -> void:
	var vehicle_position: Vector3 = state.get("position")
	var vehicle_basis: Basis = state.get("basis")
	var back: Vector3 = vehicle_basis.z.normalized()
	var offset: Vector3 = chase_camera.global_position - vehicle_position
	var expected_offset_xz: Vector2 = Vector2(back.x, back.z) * GameConfig.cam_distance
	var actual_offset_xz: Vector2 = Vector2(offset.x, offset.z)
	if actual_offset_xz.distance_to(expected_offset_xz) > CAMERA_COMPOSITION_TOLERANCE:
		_errors.append(context + " rear offset expected " + str(expected_offset_xz) + ", got " + str(actual_offset_xz))
	if absf(offset.y - GameConfig.cam_height) > CAMERA_COMPOSITION_TOLERANCE:
		_errors.append(context + " height offset expected " + str(GameConfig.cam_height) + ", got " + str(offset.y))
	_require_camera_pitch(chase_camera, context)


func _require_camera_pitch(camera: Camera3D, context: String) -> void:
	var forward: Vector3 = -camera.global_transform.basis.z.normalized()
	var pitch_degrees: float = rad_to_deg(asin(clampf(forward.y, -1.0, 1.0)))
	if absf(pitch_degrees - GameConfig.cam_pitch_deg) > CAMERA_PITCH_TOLERANCE_DEG:
		_errors.append(context + " pitch expected " + str(GameConfig.cam_pitch_deg) + ", got " + str(pitch_degrees))


func _require_node(parent: Node, path: String) -> Node:
	var node: Node = parent.get_node_or_null(path)
	if node == null:
		_errors.append("missing node: " + path)
	return node


func _require_node_position(parent: Node, path: String, expected: Vector3, tolerance: float) -> void:
	var node: Node3D = _require_node(parent, path) as Node3D
	if node == null:
		return
	if node.position.distance_to(expected) > tolerance:
		_errors.append(path + " position expected " + str(expected) + ", got " + str(node.position))


func _require_node_rotation_y(parent: Node, path: String, expected: float, tolerance: float) -> void:
	var node: Node3D = _require_node(parent, path) as Node3D
	if node == null:
		return
	if absf(node.rotation.y - expected) > tolerance:
		_errors.append(path + " rotation.y expected " + str(expected) + ", got " + str(node.rotation.y))


func _require_wheel_socket_mesh(parent: Node, path: String) -> void:
	var socket: Node = _require_node(parent, path)
	if socket == null:
		return
	for child in socket.get_children():
		if child is MeshInstance3D:
			return
	_errors.append(path + " should contain a wheel mesh")


func _count_collision_objects(parent: Node) -> int:
	var count: int = 0
	for child in parent.get_children():
		if child is CollisionObject3D:
			count += 1
		count += _count_collision_objects(child)
	return count


func _count_mesh_instances(parent: Node) -> int:
	var count: int = 0
	for child in parent.get_children():
		if child is MeshInstance3D:
			count += 1
		count += _count_mesh_instances(child)
	return count


func _finish() -> void:
	if _errors.is_empty():
		print("ok: flat plane visuals, vehicle, camera, and surface nodes instantiated")
		if _scene_root != null:
			_scene_root.queue_free()
		await get_tree().process_frame
		get_tree().quit(0)
		return
	for error in _errors:
		push_error(error)
	if _scene_root != null:
		_scene_root.queue_free()
	await get_tree().process_frame
	get_tree().quit(1)
