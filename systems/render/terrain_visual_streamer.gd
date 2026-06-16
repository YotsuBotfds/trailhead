extends Node3D

const TerrainVisualBuilderScript: GDScript = preload("res://systems/render/terrain_visual_builder.gd")

var _region_id: String = ""
var _visual_root: Node3D = null
var _detail_root: Node3D = null
var _stream_generation: int = 0
var _configured: bool = false
var _events_connected: bool = false
var _visual_tiles_by_cell: Dictionary[Vector2i, Node3D] = {}
var _load_failures_by_cell: Dictionary[Vector2i, String] = {}


func _ready() -> void:
	if _configured:
		_ensure_event_connections()


func _exit_tree() -> void:
	reset_stream()


func configure_region(new_region_id: String) -> void:
	reset_stream()
	_region_id = new_region_id
	_configured = not _region_id.is_empty()
	if not _configured:
		return
	_visual_root = TerrainVisualBuilderScript.build_region_stream_root(self, _region_id)
	_detail_root = _visual_root.get_node_or_null(TerrainVisualBuilderScript.REGION_DETAIL_ROOT_NAME) as Node3D
	if _detail_root == null:
		_load_failures_by_cell[Vector2i.ZERO] = "region detail root missing"
		_configured = false
		return
	_ensure_event_connections()


func reset_stream() -> void:
	_stream_generation += 1
	_disconnect_event_connections()
	for cell in _sorted_cells(_visual_tiles_by_cell.keys()):
		_free_visual_cell(cell)
	_visual_tiles_by_cell.clear()
	_load_failures_by_cell.clear()
	_configured = false
	_region_id = ""
	_detail_root = null
	if _visual_root != null:
		remove_child(_visual_root)
		_visual_root.queue_free()
		_visual_root = null


func active_visual_cells() -> Array[Vector2i]:
	return _sorted_cells(_visual_tiles_by_cell.keys())


func visual_cell_count() -> int:
	return _visual_tiles_by_cell.size()


func has_visual_cell(cell: Vector2i) -> bool:
	return _visual_tiles_by_cell.has(cell)


func visual_cell_node(cell: Vector2i) -> Node3D:
	if not _visual_tiles_by_cell.has(cell):
		return null
	return _visual_tiles_by_cell[cell]


func load_failures() -> Dictionary[Vector2i, String]:
	var copy: Dictionary[Vector2i, String] = {}
	for cell in _sorted_cells(_load_failures_by_cell.keys()):
		copy[cell] = _load_failures_by_cell[cell]
	return copy


func _ensure_event_connections() -> void:
	if _events_connected:
		return
	if not EventBus.world_tile_activated.is_connected(_on_world_tile_activated):
		EventBus.world_tile_activated.connect(_on_world_tile_activated)
	if not EventBus.world_tile_evicted.is_connected(_on_world_tile_evicted):
		EventBus.world_tile_evicted.connect(_on_world_tile_evicted)
	_events_connected = true


func _disconnect_event_connections() -> void:
	if not _events_connected:
		return
	if EventBus.world_tile_activated.is_connected(_on_world_tile_activated):
		EventBus.world_tile_activated.disconnect(_on_world_tile_activated)
	if EventBus.world_tile_evicted.is_connected(_on_world_tile_evicted):
		EventBus.world_tile_evicted.disconnect(_on_world_tile_evicted)
	_events_connected = false


func _on_world_tile_activated(cell: Vector2i) -> void:
	if not _configured or _detail_root == null:
		return
	if _visual_tiles_by_cell.has(cell):
		return
	var generation: int = _stream_generation
	var visual_tile: MeshInstance3D = TerrainVisualBuilderScript.add_region_visual_tile(_detail_root, _region_id, cell)
	if generation != _stream_generation:
		if visual_tile != null:
			visual_tile.queue_free()
		return
	if visual_tile == null:
		_load_failures_by_cell[cell] = "visual tile failed to load"
		return
	_visual_tiles_by_cell[cell] = visual_tile
	_load_failures_by_cell.erase(cell)


func _on_world_tile_evicted(cell: Vector2i) -> void:
	if not _configured:
		return
	_free_visual_cell(cell)
	_load_failures_by_cell.erase(cell)


func _free_visual_cell(cell: Vector2i) -> void:
	if not _visual_tiles_by_cell.has(cell):
		return
	var visual_tile: Node3D = _visual_tiles_by_cell[cell]
	_visual_tiles_by_cell.erase(cell)
	if visual_tile == null:
		return
	if visual_tile.get_parent() != null:
		visual_tile.get_parent().remove_child(visual_tile)
	visual_tile.queue_free()


func _sorted_cells(value: Array) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for item in value:
		if item is Vector2i:
			cells.append(item)
	cells.sort_custom(Callable(self, "_cell_less"))
	return cells


func _cell_less(left: Vector2i, right: Vector2i) -> bool:
	if left.x == right.x:
		return left.y < right.y
	return left.x < right.x
