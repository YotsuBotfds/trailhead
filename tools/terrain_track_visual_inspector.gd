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
const FLOAT_EPSILON: float = 0.001

var _scene_root: Node = null
var _errors: PackedStringArray = PackedStringArray()


func _ready() -> void:
	_scene_root = CedarHollowPlayableScene.instantiate()
	add_child(_scene_root)
	call_deferred("_inspect")


func _inspect() -> void:
	if _scene_root == null:
		_errors.append("failed to instantiate Cedar Hollow playable scene")
		_finish()
		return
	var painter: Node = _require_node(_scene_root, "CedarHollow/TerrainTrackVisualPainter")
	var terrain_root: Node = _require_node(_scene_root, "CedarHollow/TerrainVisuals")
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
	var expected_resolution: int = maxi(GameConfig.terrain_track_painter_resolution, 16)
	if viewport.size != Vector2i(expected_resolution, expected_resolution):
		_errors.append("track viewport resolution expected " + str(expected_resolution) + ", got " + str(viewport.size))
	if not viewport.own_world_3d:
		_errors.append("track viewport should render in its own 3D world")
	if not viewport.transparent_bg:
		_errors.append("track viewport should use a transparent background")
	if viewport.msaa_3d != Viewport.MSAA_DISABLED:
		_errors.append("track viewport should keep MSAA disabled")
	if viewport.render_target_update_mode != SubViewport.UPDATE_ALWAYS:
		_errors.append("track viewport should update its render target every frame")
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
	var before_count: int = int(painter.call("debug_stamp_count"))
	var state: RefCounted = VehicleStateScript.new()
	var first_hit_points: Array[Vector3] = [
		Vector3(0.0, 0.0, -4.0),
		Vector3(0.18, 0.0, -4.0),
		Vector3(0.36, 0.0, -4.0),
		Vector3(0.54, 0.0, -4.0)
	]
	var wheel_surfaces: Array[StringName] = [&"mud", &"packed_dirt", &"wet_stone", &"wood_plank"]
	state.set("wheel_hit_point", first_hit_points)
	state.set("wheel_surface", wheel_surfaces)
	painter.call("apply_vehicle_state", state, GameConfig.FIXED_DT)
	var after_first_count: int = int(painter.call("debug_stamp_count"))
	if after_first_count < before_count + 3:
		_errors.append("track painter should stamp mud/dirt/wet-stone wheel hits")
	painter.call("apply_vehicle_state", state, GameConfig.FIXED_DT)
	var after_repeat_count: int = int(painter.call("debug_stamp_count"))
	if after_repeat_count != after_first_count:
		_errors.append("track painter should not restamp unchanged wheel hit points")
	var moved_hit_points: Array[Vector3] = [
		Vector3(0.0, 0.0, -4.0 - GameConfig.terrain_track_stamp_radius),
		Vector3(0.18, 0.0, -4.0 - GameConfig.terrain_track_stamp_radius),
		Vector3(0.36, 0.0, -4.0 - GameConfig.terrain_track_stamp_radius),
		Vector3(0.54, 0.0, -4.0 - GameConfig.terrain_track_stamp_radius)
	]
	state.set("wheel_hit_point", moved_hit_points)
	painter.call("apply_vehicle_state", state, GameConfig.FIXED_DT)
	var after_move_count: int = int(painter.call("debug_stamp_count"))
	if after_move_count < after_first_count + 3:
		_errors.append("track painter should stamp deterministic moved wheel hit points")
	var stamp_root: Node = _require_node(painter, "TrackPaintViewport/TrackStampRoot")
	if stamp_root != null:
		_inspect_stamp_materials(stamp_root)


func _inspect_stamp_materials(stamp_root: Node) -> void:
	var stamp_count: int = 0
	for child in stamp_root.get_children():
		var stamp: MeshInstance3D = child as MeshInstance3D
		if stamp == null:
			continue
		stamp_count += 1
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
		if absf(mesh_instance.visibility_range_end - GameConfig.vis_range_terrain) > FLOAT_EPSILON:
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


func _count_collision_objects(parent: Node) -> int:
	var count: int = 0
	for child in parent.get_children():
		if child is CollisionObject3D:
			count += 1
		count += _count_collision_objects(child)
	return count


func _finish() -> void:
	if _errors.is_empty():
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
