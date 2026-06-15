class_name RecoverableObject
extends Area3D

@export var object_id: StringName = &""
@export var vehicle_path: NodePath = NodePath("")

var _vehicle: Node = null
var _hold_ticks: int = 0
var _tagged: bool = false


func _ready() -> void:
	monitoring = false
	monitorable = false
	collision_layer = 0
	collision_mask = 0
	_refresh_radius_shape()
	if not vehicle_path.is_empty():
		_vehicle = get_node_or_null(vehicle_path)


func configure(new_object_id: StringName, world_position: Vector3) -> void:
	object_id = new_object_id
	position = world_position


func bind_vehicle(vehicle: Node) -> void:
	_vehicle = vehicle


func sample_vehicle_state(vehicle_state: RefCounted) -> bool:
	if vehicle_state == null:
		_hold_ticks = 0
		return false
	var position_value: Variant = vehicle_state.get("position")
	if not (position_value is Vector3):
		_hold_ticks = 0
		return false
	return sample_vehicle_position(position_value)


func sample_vehicle_position(vehicle_position: Vector3) -> bool:
	if _tagged:
		return false
	if object_id == &"":
		_hold_ticks = 0
		return false
	if _is_vehicle_inside_radius(vehicle_position):
		_hold_ticks += 1
	else:
		_hold_ticks = 0
	if _hold_ticks < GameConfig.recover_hold_ticks:
		return false
	_tagged = true
	_hold_ticks = 0
	EventBus.world_recoverable_object_tagged.emit(object_id)
	return true


func was_tagged() -> bool:
	return _tagged


func hold_ticks() -> int:
	return _hold_ticks


func _physics_process(_delta: float) -> void:
	var vehicle: Node = _resolve_vehicle()
	if vehicle == null:
		return
	var vehicle_state: RefCounted = vehicle.call("get_state") as RefCounted
	sample_vehicle_state(vehicle_state)


func _resolve_vehicle() -> Node:
	if _vehicle != null and is_instance_valid(_vehicle):
		return _vehicle
	if not vehicle_path.is_empty():
		_vehicle = get_node_or_null(vehicle_path)
		if _vehicle != null:
			return _vehicle
	var active_vehicle: Node = GameManager.active_vehicle
	if active_vehicle != null and is_instance_valid(active_vehicle):
		_vehicle = active_vehicle
		return _vehicle
	return null


func _is_vehicle_inside_radius(vehicle_position: Vector3) -> bool:
	var delta: Vector3 = vehicle_position - global_position
	delta.y = 0.0
	return delta.length() <= GameConfig.recover_radius


func _refresh_radius_shape() -> void:
	var collision: CollisionShape3D = get_node_or_null("RecoverRadius") as CollisionShape3D
	if collision == null:
		collision = CollisionShape3D.new()
		collision.name = "RecoverRadius"
		add_child(collision)
	var sphere: SphereShape3D = collision.shape as SphereShape3D
	if sphere == null:
		sphere = SphereShape3D.new()
		collision.shape = sphere
	sphere.radius = GameConfig.recover_radius
