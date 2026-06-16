class_name TerrainTrackVisualPainter
extends Node3D

const TerrainTrackStampShader: Shader = preload("res://systems/render/terrain_track_stamp.gdshader")
const CedarTerrainDef: Resource = preload("res://data/terrain/cedar_hollow_terrain_def.tres")
const VIEWPORT_NAME: String = "TrackPaintViewport"
const CAMERA_NAME: String = "TrackPaintCamera"
const STAMP_ROOT_NAME: String = "TrackStampRoot"
const STAMP_NODE_PREFIX: String = "track_stamp_"
const STAMP_COLOR_UNIFORM: StringName = &"stamp_color"
const WHEEL_COUNT: int = 4
const MIN_VIEWPORT_RESOLUTION: int = 16
const MIN_BOUNDS_EXTENT: float = 0.001
const TRACK_CAMERA_HEIGHT: float = 8.0
const STAMP_Y: float = 0.0
const MIN_STAMP_RADIUS: float = 0.005
const STAMP_WIDTH_MULTIPLIER: float = 2.0
const STAMP_LENGTH_MULTIPLIER: float = 3.0
const STAMP_SPACING_RADIUS_FACTOR: float = 0.55
const MIN_STAMP_SPACING: float = 0.006
const STAMP_DIRECTION_EPSILON: float = 0.001
const STAMP_ALPHA_EPSILON: float = 0.01
const MIN_STAMPS_PER_WHEEL: int = 8
const RUT_MUD_SCALE: float = 1.0
const RUT_WET_SCALE: float = 0.48
const RUT_SAND_SCALE: float = 0.62
const RUT_DUST_SCALE: float = 0.26
const WET_MUD_CHANNEL: float = 0.85
const WET_STONE_CHANNEL: float = 0.70

var _viewport: SubViewport = null
var _camera: Camera3D = null
var _stamp_root: Node3D = null
var _render_bounds_min: Vector2 = Vector2.ZERO
var _render_bounds_max: Vector2 = Vector2.ZERO
var _stamp_nodes: Array[MeshInstance3D] = []
var _stamp_colors: Array[Color] = []
var _last_wheel_points: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
var _last_wheel_surfaces: Array[StringName] = [&"", &"", &"", &""]
var _last_wheel_has_stamp: Array[bool] = [false, false, false, false]
var _stamp_sequence: int = 0
var _max_stamp_count: int = WHEEL_COUNT * MIN_STAMPS_PER_WHEEL
var _track_update_tick: int = 0
var _pending_decay_delta: float = 0.0


func _ready() -> void:
	if _viewport == null:
		configure(_default_bounds_min(), _default_bounds_max())


func configure(bounds_min: Vector2, bounds_max: Vector2) -> void:
	_configure_bounds(bounds_min, bounds_max)
	_max_stamp_count = maxi(_target_viewport_resolution(), WHEEL_COUNT * MIN_STAMPS_PER_WHEEL)
	_ensure_viewport()
	_configure_viewport()


func track_texture() -> Texture2D:
	if _viewport == null:
		configure(_default_bounds_min(), _default_bounds_max())
	return _viewport.get_texture()


func render_bounds_min() -> Vector2:
	return _render_bounds_min


func render_bounds_max() -> Vector2:
	return _render_bounds_max


func apply_vehicle_state(state: RefCounted, fixed_delta: float) -> void:
	if not GameConfig.terrain_track_painter_enabled:
		return
	if state == null:
		return
	if _viewport == null:
		configure(_default_bounds_min(), _default_bounds_max())
	if _advance_track_update_tick(fixed_delta):
		if _age_stamps(_pending_decay_delta):
			_request_viewport_update()
		_pending_decay_delta = 0.0
	var wheel_hit_points: Array[Vector3] = state.get("wheel_hit_point")
	var wheel_surfaces: Array[StringName] = state.get("wheel_surface")
	var wheel_count: int = mini(mini(wheel_hit_points.size(), wheel_surfaces.size()), WHEEL_COUNT)
	for wheel_index in range(wheel_count):
		var surface_id: StringName = wheel_surfaces[wheel_index]
		if surface_id == &"":
			continue
		var hit_point: Vector3 = wheel_hit_points[wheel_index]
		if not _point_inside_bounds(hit_point):
			continue
		var surface_response: float = _surface_track_response(surface_id)
		if surface_response <= 0.0:
			continue
		if not _should_stamp(wheel_index, hit_point, surface_id):
			continue
		_add_stamp(wheel_index, hit_point, surface_id, surface_response)
		_request_viewport_update()


func debug_viewport() -> SubViewport:
	return _viewport


func debug_stamp_count() -> int:
	return _stamp_nodes.size()


func _default_bounds_min() -> Vector2:
	return CedarTerrainDef.get("bounds_min_xz")


func _default_bounds_max() -> Vector2:
	return CedarTerrainDef.get("bounds_max_xz")


func _configure_bounds(bounds_min: Vector2, bounds_max: Vector2) -> void:
	var center: Vector2 = (bounds_min + bounds_max) * 0.5
	var bounds_size: Vector2 = bounds_max - bounds_min
	var square_extent: float = maxf(maxf(bounds_size.x, bounds_size.y), MIN_BOUNDS_EXTENT)
	var half_extents: Vector2 = Vector2(square_extent, square_extent) * 0.5
	_render_bounds_min = center - half_extents
	_render_bounds_max = center + half_extents


func _ensure_viewport() -> void:
	if _viewport == null:
		_viewport = SubViewport.new()
		_viewport.name = VIEWPORT_NAME
		add_child(_viewport)
	if _camera == null:
		_camera = Camera3D.new()
		_camera.name = CAMERA_NAME
		_camera.current = true
		_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		_viewport.add_child(_camera)
	if _stamp_root == null:
		_stamp_root = Node3D.new()
		_stamp_root.name = STAMP_ROOT_NAME
		_viewport.add_child(_stamp_root)


func _configure_viewport() -> void:
	var resolution: int = _target_viewport_resolution()
	_viewport.size = Vector2i(resolution, resolution)
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_DISABLED
	_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	var center: Vector2 = (_render_bounds_min + _render_bounds_max) * 0.5
	var extent: float = maxf(_render_bounds_max.x - _render_bounds_min.x, MIN_BOUNDS_EXTENT)
	_camera.position = Vector3(center.x, TRACK_CAMERA_HEIGHT, center.y)
	_camera.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	_camera.size = extent
	_camera.near = 0.01
	_camera.far = TRACK_CAMERA_HEIGHT * 2.0


func _target_viewport_resolution() -> int:
	var pixels_per_meter: float = maxf(GameConfig.terrain_track_painter_pixels_per_meter, 0.0)
	var extent_resolution: int = _ceil_positive_to_int(_render_square_extent() * pixels_per_meter)
	return maxi(maxi(GameConfig.terrain_track_painter_resolution, extent_resolution), MIN_VIEWPORT_RESOLUTION)


func _render_square_extent() -> float:
	var bounds_size: Vector2 = _render_bounds_max - _render_bounds_min
	return maxf(maxf(bounds_size.x, bounds_size.y), MIN_BOUNDS_EXTENT)


func _ceil_positive_to_int(value: float) -> int:
	var truncated: int = int(value)
	if float(truncated) < value:
		return truncated + 1
	return truncated


func _advance_track_update_tick(fixed_delta: float) -> bool:
	_pending_decay_delta += maxf(fixed_delta, 0.0)
	var update_interval_ticks: int = maxi(GameConfig.terrain_track_update_interval_ticks, 1)
	_track_update_tick += 1
	if _track_update_tick < update_interval_ticks:
		return false
	_track_update_tick = 0
	return true


func _age_stamps(fixed_delta: float) -> bool:
	var decay: float = maxf(GameConfig.terrain_track_decay_per_second, 0.0) * maxf(fixed_delta, 0.0)
	if decay <= 0.0:
		return false
	var changed: bool = false
	var index: int = _stamp_nodes.size() - 1
	while index >= 0:
		var color: Color = _stamp_colors[index]
		var next_alpha: float = maxf(color.a - decay, 0.0)
		if next_alpha <= STAMP_ALPHA_EPSILON:
			_remove_stamp_at(index)
			changed = true
		else:
			var alpha_scale: float = next_alpha / maxf(color.a, STAMP_ALPHA_EPSILON)
			color = Color(color.r * alpha_scale, color.g * alpha_scale, color.b * alpha_scale, next_alpha)
			_stamp_colors[index] = color
			_apply_stamp_color(_stamp_nodes[index], color)
			changed = true
		index -= 1
	return changed


func _point_inside_bounds(point: Vector3) -> bool:
	return point.x >= _render_bounds_min.x \
		and point.x <= _render_bounds_max.x \
		and point.z >= _render_bounds_min.y \
		and point.z <= _render_bounds_max.y


func _should_stamp(wheel_index: int, hit_point: Vector3, surface_id: StringName) -> bool:
	if wheel_index < 0 or wheel_index >= WHEEL_COUNT:
		return false
	if not _last_wheel_has_stamp[wheel_index]:
		return true
	if _last_wheel_surfaces[wheel_index] != surface_id:
		return true
	var previous_point: Vector3 = _last_wheel_points[wheel_index]
	var spacing: float = maxf(GameConfig.terrain_track_stamp_radius * STAMP_SPACING_RADIUS_FACTOR, MIN_STAMP_SPACING)
	var delta: Vector2 = Vector2(hit_point.x - previous_point.x, hit_point.z - previous_point.z)
	return delta.length() >= spacing


func _add_stamp(wheel_index: int, hit_point: Vector3, surface_id: StringName, surface_response: float) -> void:
	while _stamp_nodes.size() >= _max_stamp_count:
		_remove_stamp_at(0)
	var stamp: MeshInstance3D = MeshInstance3D.new()
	stamp.name = STAMP_NODE_PREFIX + str(_stamp_sequence)
	_stamp_sequence += 1
	var radius: float = maxf(GameConfig.terrain_track_stamp_radius, MIN_STAMP_RADIUS)
	var mesh: PlaneMesh = PlaneMesh.new()
	mesh.size = Vector2(radius * STAMP_WIDTH_MULTIPLIER, radius * STAMP_LENGTH_MULTIPLIER)
	stamp.mesh = mesh
	stamp.position = Vector3(hit_point.x, STAMP_Y, hit_point.z)
	stamp.rotation_degrees = Vector3(0.0, rad_to_deg(_stamp_yaw_for_wheel(wheel_index, hit_point)), 0.0)
	var stamp_color: Color = _stamp_color_for_surface(surface_id, surface_response)
	stamp.material_override = _stamp_material(stamp_color)
	_stamp_root.add_child(stamp)
	_stamp_nodes.append(stamp)
	_stamp_colors.append(stamp_color)
	_last_wheel_points[wheel_index] = hit_point
	_last_wheel_surfaces[wheel_index] = surface_id
	_last_wheel_has_stamp[wheel_index] = true


func _stamp_yaw_for_wheel(wheel_index: int, hit_point: Vector3) -> float:
	if wheel_index < 0 or wheel_index >= WHEEL_COUNT:
		return 0.0
	if not _last_wheel_has_stamp[wheel_index]:
		return 0.0
	var previous_point: Vector3 = _last_wheel_points[wheel_index]
	var delta: Vector2 = Vector2(hit_point.x - previous_point.x, hit_point.z - previous_point.z)
	if delta.length() <= STAMP_DIRECTION_EPSILON:
		return 0.0
	return atan2(delta.x, delta.y)


func _surface_track_response(surface_id: StringName) -> float:
	if surface_id == &"mud":
		return clampf(GameConfig.terrain_track_surface_mud_strength, 0.0, 1.0)
	if surface_id == &"wet_stone":
		return clampf(GameConfig.terrain_track_surface_wet_strength, 0.0, 1.0)
	if surface_id == &"sand_wash":
		return clampf(GameConfig.terrain_track_surface_sand_strength, 0.0, 1.0)
	if surface_id == &"packed_dirt" \
			or surface_id == &"packed_gravel" \
			or surface_id == &"tall_grass" \
			or surface_id == &"loose_rock":
		return clampf(GameConfig.terrain_track_surface_dust_strength, 0.0, 1.0)
	return 0.0


func _stamp_color_for_surface(surface_id: StringName, surface_response: float) -> Color:
	var base_strength: float = clampf(GameConfig.terrain_track_stamp_strength * surface_response, 0.0, 1.0)
	var rut_scale: float = RUT_DUST_SCALE
	var wet_channel: float = 0.0
	if surface_id == &"mud":
		rut_scale = RUT_MUD_SCALE
		wet_channel = WET_MUD_CHANNEL
	elif surface_id == &"wet_stone":
		rut_scale = RUT_WET_SCALE
		wet_channel = WET_STONE_CHANNEL
	elif surface_id == &"sand_wash":
		rut_scale = RUT_SAND_SCALE
	var rut_strength: float = clampf(base_strength * rut_scale, 0.0, 1.0)
	return Color(base_strength, rut_strength, wet_channel * base_strength, base_strength)


func _stamp_material(stamp_color: Color) -> ShaderMaterial:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.resource_name = "terrain_track_stamp_material"
	material.shader = TerrainTrackStampShader
	material.set_shader_parameter(STAMP_COLOR_UNIFORM, stamp_color)
	return material


func _apply_stamp_color(stamp: MeshInstance3D, stamp_color: Color) -> void:
	var material: ShaderMaterial = stamp.material_override as ShaderMaterial
	if material == null:
		return
	material.set_shader_parameter(STAMP_COLOR_UNIFORM, stamp_color)


func _remove_stamp_at(index: int) -> void:
	if index < 0 or index >= _stamp_nodes.size():
		return
	var stamp: MeshInstance3D = _stamp_nodes[index]
	_stamp_nodes.remove_at(index)
	_stamp_colors.remove_at(index)
	if stamp == null:
		return
	if is_instance_valid(stamp):
		stamp.visible = false
		stamp.queue_free()


func _request_viewport_update() -> void:
	if _viewport == null:
		return
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
