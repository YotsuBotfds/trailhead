class_name CedarHollowScene
extends Node3D

const TerrainBuilderScript: GDScript = preload("res://systems/world/terrain_builder.gd")
const RecoverableObjectScript: GDScript = preload("res://systems/world/recoverable_object.gd")
const MudKeyTriggerScript: GDScript = preload("res://systems/world/mud_key_trigger.gd")
const MudKeyClusterScene: PackedScene = preload("res://scenes/world/easter_eggs/mud_key_cluster.tscn")


func _ready() -> void:
	TerrainBuilderScript.build_cedar_hollow(self)
	_add_recoverable_objects()


func _add_recoverable_objects() -> void:
	_add_recoverable_object(&"ro_01_water_bottle", "RO_01_WaterBottle", Vector3(4.92, 0.04, -6.95))
	_add_recoverable_object(&"ro_02_boot", "RO_02_Boot", Vector3(4.34, 0.12, -7.58))
	var ro_03: Node3D = _add_recoverable_object(&"ro_03_carabiner", "RO_03_Carabiner", Vector3(-1.64, 0.18, -8.28))
	_add_mud_key_to_ro_03(ro_03)
	_add_recoverable_object(&"ro_04_frequency_sticker", "RO_04_FrequencySticker", Vector3(-4.46, 0.02, -3.06))
	_add_recoverable_object(&"ro_05_tent_stake", "RO_05_TentStake", Vector3(3.04, 0.03, -4.72))


func _add_recoverable_object(object_id: StringName, node_name: String, world_position: Vector3) -> Node3D:
	var recoverable: Node3D = RecoverableObjectScript.new() as Node3D
	if recoverable == null:
		return null
	recoverable.name = node_name
	recoverable.call("configure", object_id, world_position)
	add_child(recoverable)
	return recoverable


func _add_mud_key_to_ro_03(recoverable: Node3D) -> void:
	if recoverable == null:
		return
	var cluster: Node3D = MudKeyClusterScene.instantiate() as Node3D
	if cluster == null:
		return
	cluster.name = "MudKeyCluster"
	recoverable.add_child(cluster)
	var trigger: Node3D = MudKeyTriggerScript.new() as Node3D
	if trigger == null:
		return
	trigger.name = "MudKeyTrigger"
	recoverable.add_child(trigger)
	trigger.call("configure", cluster)
