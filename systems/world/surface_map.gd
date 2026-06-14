class_name SurfaceMap
extends Node

const DEFAULT_SURFACE_ID: StringName = &"packed_dirt"

var _defs: Dictionary = {}
var _fallback: Resource = null


func _ready() -> void:
	load_defs("res://data/surfaces/")
	_fallback = _get_def(DEFAULT_SURFACE_ID)
	GameManager.register_surface_map(self)


func load_defs(dir_path: String) -> void:
	_defs.clear()
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		push_error("SurfaceMap failed to open: " + dir_path)
		return
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var resource_path: String = dir_path.path_join(file_name)
			var loaded: Resource = load(resource_path)
			if loaded != null:
				var surface_id: StringName = loaded.get("id")
				if surface_id != &"":
					_defs[surface_id] = loaded
		file_name = dir.get_next()
	dir.list_dir_end()


func resolve_from_collider(collider: Object) -> Resource:
	var surface_id: StringName = surface_id_from_collider(collider)
	return def_for_id(surface_id)


func def_for_id(surface_id: StringName) -> Resource:
	if _defs.has(surface_id):
		return _defs[surface_id]
	return _fallback


func surface_id_from_collider(collider: Object) -> StringName:
	var node: Node = collider as Node
	if node == null:
		return DEFAULT_SURFACE_ID
	for group_name in node.get_groups():
		var group_string: String = String(group_name)
		if group_string.begins_with("surf_"):
			return StringName(group_string.substr(5))
	var node_name: String = node.name
	var marker_index: int = node_name.find("__surf_")
	if marker_index != -1:
		return StringName(node_name.substr(marker_index + 7))
	return DEFAULT_SURFACE_ID


func fallback() -> Resource:
	return _fallback


func _get_def(surface_id: StringName) -> Resource:
	if _defs.has(surface_id):
		return _defs[surface_id]
	return null
