extends Node

const CedarHollowPlayableScene: PackedScene = preload("res://scenes/cedar_hollow_playable.tscn")
const VehicleStateScript: GDScript = preload("res://systems/vehicle/vehicle_state.gd")
const TERRAIN_TRACK_PAINTER_SCRIPT_PATH: String = "res://systems/render/terrain_track_visual_painter.gd"
const TERRAIN_TRACK_OVERLAY_SHADER_PATH: String = "res://systems/render/terrain_track_overlay.gdshader"
const TERRAIN_TRACK_STAMP_SHADER_PATH: String = "res://systems/render/terrain_track_stamp.gdshader"
const TRACK_RT_UNIFORM: StringName = &"track_rt"
const TRACK_BOUNDS_MIN_UNIFORM: StringName = &"track_bounds_min"
const TRACK_BOUNDS_MAX_UNIFORM: StringName = &"track_bounds_max"
const STAMP_COLOR_UNIFORM: StringName = &"stamp_color"
const ZION_REGION_ID: String = "cedar_hollow_zion"
const WORLD_REGION_ID_META: StringName = &"trailhead_world_region_id"
const FLOAT_EPSILON: float = 0.001
const STAMP_COLOR_MATCH_EPSILON: float = 0.003
const STAMP_COLOR_SEPARATION_EPSILON: float = 0.04
const MIN_STAMP_FOOTPRINT_PIXELS: float = 1.0
const STREAM_WAIT_FRAMES: int = 180

var _scene_root: Node = null
var _errors: PackedStringArray = PackedStringArray()
var _skipped_streamed_zion_tracks: bool = false


func _ready() -> void:
	_scene_root = CedarHollowPlayableScene.instantiate()
	add_child(_scene_root)
	call_deferred("_inspect")


func _inspect() -> void:
	if _scene_root == null:
		_errors.append("failed to instantiate Cedar Hollow playable scene")
		_finish()
		return
	if _is_streamed_zion_host():
		await _wait_for_streamed_zion_tracks()
	var painter: Node = _scene_root.get_node_or_null("CedarHollow/TerrainTrackVisualPainter")
	var terrain_root: Node = _scene_root.get_node_or_null("CedarHollow/TerrainVisuals")
	if terrain_root == null:
		terrain_root = _scene_root.get_node_or_null("CedarHollow/TerrainVisualStreamer/TerrainVisuals/TerrainDetailTiles")
	if terrain_root == null:
		terrain_root = _scene_root.get_node_or_null("CedarHollow/TerrainVisualStreamer/TerrainVisuals")
	if painter == null:
		if _is_streamed_zion_host():
			_skipped_streamed_zion_tracks = true
			_finish()
			return
		_errors.append("missing node: CedarHollow/TerrainTrackVisualPainter")
	if terrain_root == null:
		_errors.append("missing node: CedarHollow/TerrainVisuals")
	if painter != null:
		_inspect_painter_node(painter)
		_inspect_painter_stamp_response(painter)
	if painter != null and terrain_root != null:
		_inspect_terrain_track_materials(terrain_root, painter)
	_finish()


func _inspect_painter_node(painter: Node) -> void:
	var script: Script = painter.get_script() as Script
	if script == null or script.resource_path != TERRAIN_TRACK_PAINTER_SCRIPT_PATH:
		_errors.append("TerrainTrackVisualPainter should use " + TERRAIN_TRACK_PAINTER_SCRIPT_PATH)
	var collision_count: int = _count_collision_objects(painter)
	if collision_count > 0:
		_errors.append("TerrainTrackVisualPainter should be collision-free, got " + str(collision_count))
	var viewport: SubViewport = painter.call("debug_viewport") as SubViewport
	if viewport == null:
		_errors.append("TerrainTrackVisualPainter should expose a SubViewport")
		return
	var minimum_resolution: int = maxi(GameConfig.terrain_track_painter_resolution, 16)
	if viewport.size.x != viewport.size.y:
		_errors.append("track viewport should be square, got " + str(viewport.size))
	if viewport.size.x < minimum_resolution or viewport.size.y < minimum_resolution:
		_errors.append("track viewport resolution expected at least " + str(minimum_resolution) + ", got " + str(viewport.size))
	var actual_pixels_per_meter: float = _actual_pixels_per_meter(painter, viewport)
	var target_pixels_per_meter: float = maxf(GameConfig.terrain_track_painter_pixels_per_meter, 0.0)
	if actual_pixels_per_meter + FLOAT_EPSILON < target_pixels_per_meter:
		_errors.append("track viewport density expected at least " + str(target_pixels_per_meter) + " px/m, got " + str(actual_pixels_per_meter))
	if not viewport.own_world_3d:
		_errors.append("track viewport should render in its own 3D world")
	if not viewport.transparent_bg:
		_errors.append("track viewport should use a transparent background")
	if viewport.msaa_3d != Viewport.MSAA_DISABLED:
		_errors.append("track viewport should keep MSAA disabled")
	if viewport.render_target_update_mode != SubViewport.UPDATE_ONCE:
		_errors.append("track viewport should request render target updates explicitly with UPDATE_ONCE")
	if GameConfig.terrain_track_update_interval_ticks < 1:
		_errors.append("terrain_track_update_interval_ticks should be at least 1")
	if viewport.get_texture() == null:
		_errors.append("track viewport should expose a render target texture")
	var camera: Camera3D = viewport.get_node_or_null("TrackPaintCamera") as Camera3D
	if camera == null:
		_errors.append("track viewport should contain TrackPaintCamera")
	else:
		if camera.projection != Camera3D.PROJECTION_ORTHOGONAL:
			_errors.append("TrackPaintCamera should be orthographic")
		var render_bounds_min: Vector2 = painter.call("render_bounds_min")
		var render_bounds_max: Vector2 = painter.call("render_bounds_max")
		var expected_size: float = render_bounds_max.x - render_bounds_min.x
		if absf(camera.size - expected_size) > FLOAT_EPSILON:
			_errors.append("TrackPaintCamera size expected " + str(expected_size) + ", got " + str(camera.size))


func _inspect_painter_stamp_response(painter: Node) -> void:
	_inspect_surface_response_palette(painter)
	var before_count: int = int(painter.call("debug_stamp_count"))
	var state: RefCounted = VehicleStateScript.new()
	var stamp_origin: Vector3 = _stamp_origin_for_painter(painter)
	var first_hit_points: Array[Vector3] = [
		stamp_origin,
		stamp_origin + Vector3(0.18, 0.0, 0.0),
		stamp_origin + Vector3(0.36, 0.0, 0.0),
		stamp_origin + Vector3(0.54, 0.0, 0.0)
	]
	var wheel_surfaces: Array[StringName] = [&"sand_wash", &"packed_dirt", &"wet_stone", &"wood_plank"]
	state.set("wheel_hit_point", first_hit_points)
	state.set("wheel_surface", wheel_surfaces)
	painter.call("apply_vehicle_state", state, GameConfig.FIXED_DT)
	var after_first_count: int = int(painter.call("debug_stamp_count"))
	if after_first_count != before_count + 3:
		_errors.append("track painter should stamp sand/dirt/wet-stone and skip wood_plank wheel hits")
	painter.call("apply_vehicle_state", state, GameConfig.FIXED_DT)
	var after_repeat_count: int = int(painter.call("debug_stamp_count"))
	if after_repeat_count != after_first_count:
		_errors.append("track painter should not restamp unchanged wheel hit points")
	var movement_distance: float = maxf(GameConfig.terrain_track_stamp_radius * 2.0, 0.25)
	var moved_hit_points: Array[Vector3] = [
		stamp_origin + Vector3(0.0, 0.0, -movement_distance),
		stamp_origin + Vector3(0.18, 0.0, -movement_distance),
		stamp_origin + Vector3(0.36, 0.0, -movement_distance),
		stamp_origin + Vector3(0.54, 0.0, -movement_distance)
	]
	var moved_wheel_surfaces: Array[StringName] = [&"mud", &"packed_dirt", &"wet_stone", &"sand_wash"]
	state.set("wheel_hit_point", moved_hit_points)
	state.set("wheel_surface", moved_wheel_surfaces)
	painter.call("apply_vehicle_state", state, GameConfig.FIXED_DT)
	var after_move_count: int = int(painter.call("debug_stamp_count"))
	if after_move_count != after_first_count + 4:
		_errors.append("track painter should stamp deterministic moved mud/dirt/wet-stone/sand wheel hit points")
	var stamp_root: Node = _require_node(painter, "TrackPaintViewport/TrackStampRoot")
	if stamp_root != null:
		var viewport: SubViewport = painter.call("debug_viewport") as SubViewport
		var pixels_per_meter: float = 0.0
		if viewport == null:
			_errors.append("TerrainTrackVisualPainter should expose a SubViewport for stamp footprint inspection")
		else:
			pixels_per_meter = _actual_pixels_per_meter(painter, viewport)
		_require_stamp_color(stamp_root, _stamp_color_for(painter, &"sand_wash"), "sand_wash")
		_inspect_stamp_materials(stamp_root, pixels_per_meter)


func _stamp_origin_for_painter(painter: Node) -> Vector3:
	var bounds_min: Vector2 = painter.call("render_bounds_min")
	var bounds_max: Vector2 = painter.call("render_bounds_max")
	var center: Vector2 = (bounds_min + bounds_max) * 0.5
	return Vector3(center.x, 0.0, center.y)


func _inspect_surface_response_palette(painter: Node) -> void:
	var sand_response: float = _surface_response_for(painter, &"sand_wash")
	var wood_response: float = _surface_response_for(painter, &"wood_plank")
	if sand_response <= 0.0:
		_errors.append("track painter should give sand_wash a positive render-only stamp response")
	if wood_response > 0.0:
		_errors.append("track painter should keep wood_plank out of render-only terrain stamps")
	var sand_color: Color = _stamp_color_for(painter, &"sand_wash")
	var dust_color: Color = _stamp_color_for(painter, &"packed_dirt")
	var mud_color: Color = _stamp_color_for(painter, &"mud")
	var wet_color: Color = _stamp_color_for(painter, &"wet_stone")
	if _color_distance(sand_color, dust_color) <= STAMP_COLOR_SEPARATION_EPSILON:
		_errors.append("sand_wash stamp color should be distinguishable from dust response")
	if _color_distance(sand_color, mud_color) <= STAMP_COLOR_SEPARATION_EPSILON:
		_errors.append("sand_wash stamp color should be distinguishable from mud response")
	if _color_distance(sand_color, wet_color) <= STAMP_COLOR_SEPARATION_EPSILON:
		_errors.append("sand_wash stamp color should be distinguishable from wet-stone response")


func _surface_response_for(painter: Node, surface_id: StringName) -> float:
	return float(painter.call("_surface_track_response", surface_id))


func _stamp_color_for(painter: Node, surface_id: StringName) -> Color:
	var response: float = _surface_response_for(painter, surface_id)
	var color_value: Variant = painter.call("_stamp_color_for_surface", surface_id, response)
	if color_value is Color:
		return color_value
	return Color(0.0, 0.0, 0.0, 0.0)


func _require_stamp_color(stamp_root: Node, expected_color: Color, label: String) -> void:
	for child in stamp_root.get_children():
		var stamp: MeshInstance3D = child as MeshInstance3D
		if stamp == null:
			continue
		var material: ShaderMaterial = stamp.material_override as ShaderMaterial
		if material == null:
			continue
		var stamp_color: Color = material.get_shader_parameter(STAMP_COLOR_UNIFORM)
		if _color_distance(stamp_color, expected_color) <= STAMP_COLOR_MATCH_EPSILON:
			return
	_errors.append("track stamp root should contain a " + label + " stamp color")


func _color_distance(a: Color, b: Color) -> float:
	var dr: float = a.r - b.r
	var dg: float = a.g - b.g
	var db: float = a.b - b.b
	var da: float = a.a - b.a
	return sqrt(dr * dr + dg * dg + db * db + da * da)


func _inspect_stamp_materials(stamp_root: Node, pixels_per_meter: float) -> void:
	var stamp_count: int = 0
	for child in stamp_root.get_children():
		var stamp: MeshInstance3D = child as MeshInstance3D
		if stamp == null:
			continue
		stamp_count += 1
		var plane_mesh: PlaneMesh = stamp.mesh as PlaneMesh
		if plane_mesh == null:
			_errors.append("track stamp " + String(stamp.name) + " should use PlaneMesh")
		else:
			var stamp_footprint_pixels: float = minf(plane_mesh.size.x * pixels_per_meter, plane_mesh.size.y * pixels_per_meter)
			if stamp_footprint_pixels + FLOAT_EPSILON < MIN_STAMP_FOOTPRINT_PIXELS:
				_errors.append("track stamp " + String(stamp.name) + " footprint expected at least " + str(MIN_STAMP_FOOTPRINT_PIXELS) + " px, got " + str(stamp_footprint_pixels))
		var material: ShaderMaterial = stamp.material_override as ShaderMaterial
		if material == null:
			_errors.append("track stamp " + String(stamp.name) + " should use ShaderMaterial")
			continue
		if material.shader == null or material.shader.resource_path != TERRAIN_TRACK_STAMP_SHADER_PATH:
			_errors.append("track stamp " + String(stamp.name) + " should use " + TERRAIN_TRACK_STAMP_SHADER_PATH)
		var stamp_color: Color = material.get_shader_parameter(STAMP_COLOR_UNIFORM)
		if stamp_color.r <= 0.0:
			_errors.append("track stamp " + String(stamp.name) + " should write the track channel")
		if stamp_color.g <= 0.0:
			_errors.append("track stamp " + String(stamp.name) + " should write the deformation channel")
	if stamp_count <= 0:
		_errors.append("track stamp root should contain deterministic stamp quads after synthetic state")


func _inspect_terrain_track_materials(terrain_root: Node, painter: Node) -> void:
	if _is_streamed_zion_host():
		_inspect_streamed_terrain_track_materials(painter)
		return
	var track_texture: Texture2D = painter.call("track_texture") as Texture2D
	var expected_bounds_min: Vector2 = painter.call("render_bounds_min")
	var expected_bounds_max: Vector2 = painter.call("render_bounds_max")
	var material_count: int = _inspect_terrain_material_node(terrain_root, track_texture, expected_bounds_min, expected_bounds_max)
	if material_count <= 0:
		_errors.append("TerrainVisuals should expose terrain materials for track RT inspection")


func _inspect_terrain_material_node(parent: Node, track_texture: Texture2D, expected_bounds_min: Vector2, expected_bounds_max: Vector2) -> int:
	var count: int = 0
	var mesh_instance: MeshInstance3D = parent as MeshInstance3D
	if mesh_instance != null:
		if not _is_streamed_zion_host() and absf(mesh_instance.visibility_range_end - GameConfig.vis_range_terrain) > FLOAT_EPSILON:
			_errors.append(String(mesh_instance.name) + " visibility_range_end should use GameConfig.vis_range_terrain")
		count += _inspect_terrain_mesh_materials(mesh_instance, track_texture, expected_bounds_min, expected_bounds_max)
	for child in parent.get_children():
		count += _inspect_terrain_material_node(child, track_texture, expected_bounds_min, expected_bounds_max)
	return count


func _inspect_terrain_mesh_materials(mesh_instance: MeshInstance3D, track_texture: Texture2D, expected_bounds_min: Vector2, expected_bounds_max: Vector2) -> int:
	var mesh: Mesh = mesh_instance.mesh
	if mesh == null:
		return 0
	var count: int = 0
	for surface_index in range(mesh.get_surface_count()):
		var material: StandardMaterial3D = mesh_instance.get_surface_override_material(surface_index) as StandardMaterial3D
		if material == null:
			continue
		count += 1
		if GameConfig.terrain_pom_enabled:
			if not material.heightmap_enabled:
				_errors.append(material.resource_name + " should enable StandardMaterial3D height mapping")
			if material.heightmap_texture == null:
				_errors.append(material.resource_name + " should have a heightmap texture")
			if not material.heightmap_deep_parallax:
				_errors.append(material.resource_name + " should enable deep parallax height mapping")
			if material.heightmap_min_layers != GameConfig.terrain_pom_min_layers:
				_errors.append(material.resource_name + " min POM layers should come from GameConfig")
			if material.heightmap_max_layers != GameConfig.terrain_pom_max_layers:
				_errors.append(material.resource_name + " max POM layers should come from GameConfig")
		var overlay: ShaderMaterial = material.next_pass as ShaderMaterial
		if overlay == null:
			_errors.append(material.resource_name + " should attach a track RT shader next pass")
			continue
		if overlay.shader == null or overlay.shader.resource_path != TERRAIN_TRACK_OVERLAY_SHADER_PATH:
			_errors.append(material.resource_name + " track overlay should use " + TERRAIN_TRACK_OVERLAY_SHADER_PATH)
		var overlay_texture: Texture2D = overlay.get_shader_parameter(TRACK_RT_UNIFORM) as Texture2D
		if overlay_texture == null:
			_errors.append(material.resource_name + " track overlay should set track_rt")
		elif overlay_texture != track_texture:
			_errors.append(material.resource_name + " track_rt should be the painter viewport texture")
		var bounds_min: Vector2 = overlay.get_shader_parameter(TRACK_BOUNDS_MIN_UNIFORM)
		var bounds_max: Vector2 = overlay.get_shader_parameter(TRACK_BOUNDS_MAX_UNIFORM)
		if bounds_min.distance_to(expected_bounds_min) > FLOAT_EPSILON:
			_errors.append(material.resource_name + " track bounds min should match painter bounds")
		if bounds_max.distance_to(expected_bounds_max) > FLOAT_EPSILON:
			_errors.append(material.resource_name + " track bounds max should match painter bounds")
	return count


func _require_node(parent: Node, path: String) -> Node:
	var node: Node = parent.get_node_or_null(path)
	if node == null:
		_errors.append("missing node: " + path)
	return node


func _is_streamed_zion_host() -> bool:
	if _scene_root == null:
		return false
	var world: Node = _scene_root.get_node_or_null("CedarHollow")
	if world == null or not world.has_meta(WORLD_REGION_ID_META):
		return false
	return String(world.get_meta(WORLD_REGION_ID_META)) == ZION_REGION_ID


func _wait_for_streamed_zion_tracks() -> void:
	var streamer: Node = _scene_root.get_node_or_null("CedarHollow/TerrainVisualStreamer")
	if streamer == null:
		return
	for _frame in range(STREAM_WAIT_FRAMES):
		if _streamed_track_overlay_state_ready():
			return
		await get_tree().process_frame
		await get_tree().physics_frame


func _streamed_track_overlay_state_ready() -> bool:
	var painter: Node = _scene_root.get_node_or_null("CedarHollow/TerrainTrackVisualPainter")
	var streamer: Node = _scene_root.get_node_or_null("CedarHollow/TerrainVisualStreamer")
	if painter == null or streamer == null:
		return false
	var track_texture: Texture2D = painter.call("track_texture") as Texture2D
	if track_texture == null:
		return false
	var bounds_min: Vector2 = painter.call("render_bounds_min")
	var bounds_max: Vector2 = painter.call("render_bounds_max")
	var active_cells: Array = streamer.call("active_visual_cells")
	var has_intersecting_tracked_cell: bool = false
	var has_outside_untracked_cell: bool = false
	for cell_variant in active_cells:
		var cell: Vector2i = cell_variant
		var visual_cell: Node = streamer.call("visual_cell_node", cell) as Node
		if visual_cell == null:
			continue
		var track_material_count: int = _count_track_materials(visual_cell, track_texture)
		if _cell_intersects_track_bounds(cell, bounds_min, bounds_max):
			if track_material_count <= 0:
				return false
			has_intersecting_tracked_cell = true
		else:
			if track_material_count > 0:
				return false
			has_outside_untracked_cell = true
	return has_intersecting_tracked_cell and has_outside_untracked_cell


func _inspect_streamed_terrain_track_materials(painter: Node) -> void:
	var streamer: Node = _scene_root.get_node_or_null("CedarHollow/TerrainVisualStreamer")
	if streamer == null:
		_errors.append("missing node: CedarHollow/TerrainVisualStreamer")
		return
	var track_texture: Texture2D = painter.call("track_texture") as Texture2D
	if track_texture == null:
		_errors.append("streamed Zion track painter should expose a texture")
		return
	var bounds_min: Vector2 = painter.call("render_bounds_min")
	var bounds_max: Vector2 = painter.call("render_bounds_max")
	var active_cells: Array = streamer.call("active_visual_cells")
	var intersecting_cell_count: int = 0
	var outside_cell_count: int = 0
	var tracked_material_count: int = 0
	for cell_variant in active_cells:
		var cell: Vector2i = cell_variant
		var visual_cell: Node = streamer.call("visual_cell_node", cell) as Node
		if visual_cell == null:
			continue
		var cell_track_material_count: int = _count_track_materials(visual_cell, track_texture)
		if _cell_intersects_track_bounds(cell, bounds_min, bounds_max):
			intersecting_cell_count += 1
			if cell_track_material_count <= 0:
				_errors.append("streamed Zion track-intersecting cell " + str(cell) + " should expose terrain track RT materials")
			tracked_material_count += cell_track_material_count
		else:
			outside_cell_count += 1
			if cell_track_material_count > 0:
				_errors.append("streamed Zion non-intersecting cell " + str(cell) + " should not carry a terrain track next_pass")
	if intersecting_cell_count <= 0:
		_errors.append("streamed Zion should have loaded detail cells intersecting the track painter window")
	if outside_cell_count <= 0:
		_errors.append("streamed Zion should leave at least one loaded detail cell outside the track painter window un-overlaid")
	if tracked_material_count <= 0:
		_errors.append("streamed Zion detail tiles should expose terrain track RT materials inside the track painter window")


func _count_track_materials(parent: Node, track_texture: Texture2D) -> int:
	var count: int = 0
	var mesh_instance: MeshInstance3D = parent as MeshInstance3D
	if mesh_instance != null:
		var mesh: Mesh = mesh_instance.mesh
		if mesh != null:
			for surface_index in range(mesh.get_surface_count()):
				var material: Material = mesh_instance.get_surface_override_material(surface_index)
				if material == null:
					continue
				var overlay: ShaderMaterial = material.next_pass as ShaderMaterial
				if overlay == null:
					continue
				var overlay_texture: Texture2D = overlay.get_shader_parameter(TRACK_RT_UNIFORM) as Texture2D
				if overlay_texture == track_texture:
					count += 1
	for child in parent.get_children():
		count += _count_track_materials(child, track_texture)
	return count


func _cell_intersects_track_bounds(cell: Vector2i, bounds_min: Vector2, bounds_max: Vector2) -> bool:
	var tile_size_m: float = GameConfig.STREAM_TILE_SIZE_M
	var cell_min: Vector2 = Vector2(float(cell.x) * tile_size_m, float(cell.y) * tile_size_m)
	var cell_max: Vector2 = cell_min + Vector2(tile_size_m, tile_size_m)
	return cell_max.x >= bounds_min.x \
		and cell_min.x <= bounds_max.x \
		and cell_max.y >= bounds_min.y \
		and cell_min.y <= bounds_max.y


func _count_collision_objects(parent: Node) -> int:
	var count: int = 0
	for child in parent.get_children():
		if child is CollisionObject3D:
			count += 1
		count += _count_collision_objects(child)
	return count


func _actual_pixels_per_meter(painter: Node, viewport: SubViewport) -> float:
	var render_bounds_min: Vector2 = painter.call("render_bounds_min")
	var render_bounds_max: Vector2 = painter.call("render_bounds_max")
	var bounds_size: Vector2 = render_bounds_max - render_bounds_min
	var square_extent: float = maxf(maxf(bounds_size.x, bounds_size.y), FLOAT_EPSILON)
	var limiting_viewport_axis: float = minf(float(viewport.size.x), float(viewport.size.y))
	return limiting_viewport_axis / square_extent


func _finish() -> void:
	if _errors.is_empty():
		if _skipped_streamed_zion_tracks:
			print("ok: streamed Zion host skips strip terrain track painter")
		else:
			print("ok: terrain track painter, SubViewport RT, terrain POM fields, and track sampler are wired")
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
