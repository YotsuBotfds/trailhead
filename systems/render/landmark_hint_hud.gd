class_name LandmarkHintHud
extends CanvasLayer

const MinimapViewScript: GDScript = preload("res://systems/render/minimap_view.gd")

var _route: Resource = null
var _vehicle: Node = null
var _state_provider: Node = null
var _minimap: Control = null


func _ready() -> void:
	layer = 10
	_ensure_minimap()


func configure(route: Resource, vehicle: Node, state_provider: Node = null) -> void:
	_route = route
	_vehicle = vehicle
	_state_provider = state_provider
	if is_inside_tree():
		_ensure_minimap()


func _ensure_minimap() -> void:
	if _minimap == null:
		_minimap = MinimapViewScript.new() as Control
		_minimap.name = "MinimapView"
		_minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_minimap.position = Vector2(GameConfig.minimap_margin, GameConfig.minimap_margin)
		_minimap.size = Vector2(GameConfig.minimap_size, GameConfig.minimap_size)
		_minimap.custom_minimum_size = Vector2(GameConfig.minimap_size, GameConfig.minimap_size)
		add_child(_minimap)
	if _route != null and _vehicle != null:
		_minimap.call("configure", _route, _vehicle, _state_provider)
