class_name GoldenLineGhost
extends Node3D

var _active: bool = false
var _last_segment_id: StringName = &""
var _last_match_tick: int = -1
var _fade_ticks_remaining: int = 0


func _ready() -> void:
	if not EventBus.world_golden_line_matched.is_connected(_on_world_golden_line_matched):
		EventBus.world_golden_line_matched.connect(_on_world_golden_line_matched)


func _exit_tree() -> void:
	if EventBus.world_golden_line_matched.is_connected(_on_world_golden_line_matched):
		EventBus.world_golden_line_matched.disconnect(_on_world_golden_line_matched)


func _physics_process(_delta: float) -> void:
	if _fade_ticks_remaining <= 0:
		_active = false
		return
	_fade_ticks_remaining -= 1
	_active = _fade_ticks_remaining > 0


func is_active() -> bool:
	return _active


func last_segment_id() -> StringName:
	return _last_segment_id


func last_match_tick() -> int:
	return _last_match_tick


func fade_ticks_remaining() -> int:
	return _fade_ticks_remaining


func _on_world_golden_line_matched(segment_id: StringName, sim_tick: int) -> void:
	_last_segment_id = segment_id
	_last_match_tick = sim_tick
	_fade_ticks_remaining = maxi(GameConfig.egg_dev_line_ghost_fade_ticks, 0)
	_active = _fade_ticks_remaining > 0
