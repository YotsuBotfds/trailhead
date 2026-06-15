class_name MudKeyTrigger
extends Area3D

const EGG_ID: StringName = &"mud_key"

@export var vehicle_path: NodePath = NodePath("")
@export var cluster_path: NodePath = NodePath("")

var _vehicle: Node = null
var _cluster: Node3D = null
var _checked_once: bool = false
var _triggered: bool = false


func _ready() -> void:
	monitoring = false
	monitorable = false
	collision_layer = 0
	collision_mask = 0
	_refresh_radius_shape()
	_resolve_cluster()
	_set_cluster_enabled(false)
	if not vehicle_path.is_empty():
		_vehicle = get_node_or_null(vehicle_path)


func configure(cluster: Node3D) -> void:
	_cluster = cluster
	_set_cluster_enabled(false)


func sample_vehicle_state(vehicle_state: RefCounted) -> bool:
	if _checked_once:
		return false
	if vehicle_state == null:
		return false
	var position_value: Variant = vehicle_state.get("position")
	if not (position_value is Vector3):
		return false
	if not _is_vehicle_inside_radius(position_value):
		return false
	_checked_once = true
	var mud_scalar: float = _mud_scalar(vehicle_state)
	if mud_scalar <= GameConfig.egg_mud_key_threshold:
		return false
	_triggered = true
	_set_cluster_enabled(true)
	EventBus.world_egg_triggered.emit(EGG_ID)
	return true


func was_checked() -> bool:
	return _checked_once


func was_triggered() -> bool:
	return _triggered


func cluster_enabled() -> bool:
	var cluster: Node3D = _resolve_cluster()
	return cluster != null and cluster.visible


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


func _resolve_cluster() -> Node3D:
	if _cluster != null and is_instance_valid(_cluster):
		return _cluster
	if not cluster_path.is_empty():
		_cluster = get_node_or_null(cluster_path) as Node3D
	return _cluster


func _set_cluster_enabled(enabled: bool) -> void:
	var cluster: Node3D = _resolve_cluster()
	if cluster == null:
		return
	cluster.visible = enabled
	cluster.process_mode = Node.PROCESS_MODE_INHERIT if enabled else Node.PROCESS_MODE_DISABLED


func _mud_scalar(vehicle_state: RefCounted) -> float:
	var contamination: RefCounted = vehicle_state.get("contamination") as RefCounted
	if contamination == null:
		return 0.0
	var mud_value: Variant = contamination.get("mud")
	if mud_value is float or mud_value is int:
		return clampf(float(mud_value), 0.0, 1.0)
	var mud_scalar_value: Variant = contamination.get("mud_scalar")
	if mud_scalar_value is float or mud_scalar_value is int:
		return clampf(float(mud_scalar_value), 0.0, 1.0)
	return 0.0


func _is_vehicle_inside_radius(vehicle_position: Vector3) -> bool:
	var delta: Vector3 = vehicle_position - global_position
	delta.y = 0.0
	return delta.length() <= GameConfig.egg_default_trigger_radius_m


func _refresh_radius_shape() -> void:
	var collision: CollisionShape3D = get_node_or_null("MudKeyRadius") as CollisionShape3D
	if collision == null:
		collision = CollisionShape3D.new()
		collision.name = "MudKeyRadius"
		add_child(collision)
	var sphere: SphereShape3D = collision.shape as SphereShape3D
	if sphere == null:
		sphere = SphereShape3D.new()
		collision.shape = sphere
	sphere.radius = GameConfig.egg_default_trigger_radius_m
