class_name VehicleJuiceRig
extends Node3D

const DUST_BURST_NAME: String = "DustSurfaceBurst"
const MUD_BURST_NAME: String = "MudSurfaceBurst"
const WATER_BURST_NAME: String = "WaterSurfaceBurst"
const BURST_SEED_DUST: int = 7101
const BURST_SEED_MUD: int = 7102
const BURST_SEED_WATER: int = 7103

# W3-DUST: continuous wheel dust + spray emitters (one GPUParticles3D per wheel).
# Driven entirely from sim state (state.wheel_contact / wheel_surface /
# wheel_hit_point + linear_velocity): no wall-clock, no RNG, fixed seeds. Each
# tick, amount_ratio scales with SPEED x a per-surface INTENSITY (sand strong,
# pavement faint, wet_stone = water spray) and a decaying KICK boost on landing /
# hard-accel / slide events; the process material color is retinted per surface
# (tan on sand, gray on gravel, pale cyan spray on wet_stone, brown on mud) so
# the kicked-up cloud reads as the surface the buggy is actually on.
const WHEEL_DUST_NAME_PREFIX: String = "WheelDust"
const WHEEL_DUST_FIXED_SEED: int = 7104
const WHEEL_COUNT: int = 4
const WHEEL_DUST_HEIGHT_OFFSET: float = 0.035
const WHEEL_DUST_BILLBOARD_SCALE: float = 0.018
const WHEEL_DUST_GRAVITY: float = -0.32
const WHEEL_DUST_INITIAL_VELOCITY_MIN: float = 0.10
const WHEEL_DUST_INITIAL_VELOCITY_MAX: float = 0.42
const WHEEL_DUST_SPREAD_DEG: float = 38.0
const WHEEL_DUST_DAMPING_MIN: float = 0.18
const WHEEL_DUST_DAMPING_MAX: float = 0.32
const WHEEL_DUST_KICK_MAX_RATIO: float = 1.0

var _vehicle: Node = null
var _camera: Camera3D = null
var _visual_root: Node3D = null
var _base_visual_scale: Vector3 = Vector3.ONE
var _previous_on_ground: bool = true
var _previous_vertical_velocity: float = 0.0
var _last_speed: float = 0.0
var _previous_speed: float = 0.0
var _shake_strength: float = 0.0
var _squash_strength: float = 0.0
var _surface_id: StringName = &""
var _wheel_dust: Array[GPUParticles3D] = []
var _dust_kick_boost: float = 0.0
var _was_hard_accel: bool = false
var _was_sliding: bool = false


func _ready() -> void:
	if not EventBus.vehicle_changed_surface.is_connected(_on_vehicle_changed_surface):
		EventBus.vehicle_changed_surface.connect(_on_vehicle_changed_surface)


func _exit_tree() -> void:
	if EventBus.vehicle_changed_surface.is_connected(_on_vehicle_changed_surface):
		EventBus.vehicle_changed_surface.disconnect(_on_vehicle_changed_surface)
	if _camera != null:
		_camera.h_offset = 0.0
		_camera.v_offset = 0.0
	if _visual_root != null:
		_visual_root.scale = _base_visual_scale


func configure(vehicle: Node, chase_camera: Camera3D, visual_root: Node3D) -> void:
	_vehicle = vehicle
	_camera = chase_camera
	_visual_root = visual_root
	if _visual_root != null:
		_base_visual_scale = _visual_root.scale
	_ensure_bursts()
	_ensure_wheel_dust()


func _process(delta: float) -> void:
	_update_from_vehicle_state()
	_update_camera_shake(delta)
	_update_squash(delta)
	_update_wheel_dust(delta)


func debug_trigger_landing(impact_speed: float) -> void:
	_trigger_landing_feedback(impact_speed)


func debug_trigger_surface_burst(surface_id: StringName, position: Vector3, speed: float) -> void:
	_last_speed = speed
	_emit_surface_burst(surface_id, position)


func debug_trigger_dust_kick() -> void:
	_dust_kick_boost = WHEEL_DUST_KICK_MAX_RATIO


func debug_wheel_dust_count() -> int:
	return _wheel_dust.size()


func _update_from_vehicle_state() -> void:
	if _vehicle == null:
		return
	var state: RefCounted = _vehicle.call("get_state") as RefCounted
	if state == null:
		return
	var on_ground: bool = bool(state.get("on_ground"))
	var linear_velocity: Vector3 = state.get("linear_velocity")
	_previous_speed = _last_speed
	_last_speed = linear_velocity.length()
	if on_ground and not _previous_on_ground:
		var impact_speed: float = maxf(-_previous_vertical_velocity, 0.0)
		if impact_speed >= GameConfig.cam_shake_landing_speed_threshold:
			_trigger_landing_feedback(impact_speed)
	elif on_ground:
		_update_dust_kick_events(state, linear_velocity)
	_previous_on_ground = on_ground
	_previous_vertical_velocity = linear_velocity.y
	global_position = state.get("position")


func _trigger_landing_feedback(impact_speed: float) -> void:
	var threshold: float = maxf(GameConfig.cam_shake_landing_speed_threshold, 0.001)
	var normalized: float = clampf((impact_speed - threshold) / threshold, 0.0, 1.0)
	_shake_strength = maxf(_shake_strength, normalized)
	_squash_strength = maxf(_squash_strength, normalized)
	_dust_kick_boost = maxf(_dust_kick_boost, WHEEL_DUST_KICK_MAX_RATIO)
	if _last_speed >= GameConfig.surface_burst_speed_threshold:
		_emit_surface_burst(_surface_id, global_position)


# W3-DUST: hard-accel + slide edge detection. Fires the existing surface burst
# (bigger kick) on rising edges only so the one-shot burst gets to develop
# instead of being restart()-ed every tick. Always raises _dust_kick_boost to
# momentarily densify the continuous wheel emitters.
func _update_dust_kick_events(state: RefCounted, linear_velocity: Vector3) -> void:
	var accel_delta: float = maxf(_last_speed - _previous_speed, 0.0)
	var hard_accel: bool = accel_delta >= GameConfig.wheel_dust_accel_delta_threshold
	var slide: bool = false
	if _last_speed >= GameConfig.wheel_dust_speed_threshold:
		var basis: Basis = state.get("basis")
		var forward_dir: Vector3 = basis * Vector3.FORWARD
		if forward_dir.length() > 0.001:
			forward_dir = forward_dir.normalized()
			var forward_speed: float = linear_velocity.dot(forward_dir)
			if forward_speed > 0.0:
				var lateral_velocity: Vector3 = linear_velocity - forward_dir * forward_speed
				slide = lateral_velocity.length() >= GameConfig.wheel_dust_slide_lateral_threshold
	var edge_event: bool = (hard_accel and not _was_hard_accel) or (slide and not _was_sliding)
	_was_hard_accel = hard_accel
	_was_sliding = slide
	if edge_event:
		_dust_kick_boost = maxf(_dust_kick_boost, WHEEL_DUST_KICK_MAX_RATIO)
		if _last_speed >= GameConfig.surface_burst_speed_threshold:
			_emit_surface_burst(_surface_id, global_position)


func _update_camera_shake(delta: float) -> void:
	if _camera == null:
		return
	if _shake_strength <= 0.001:
		_camera.h_offset = 0.0
		_camera.v_offset = 0.0
		_shake_strength = 0.0
		return
	var max_offset: float = maxf(GameConfig.cam_shake_max_offset, 0.0)
	var phase: float = _shake_strength * 11.0
	_camera.h_offset = sin(phase * 1.7) * max_offset * _shake_strength
	_camera.v_offset = cos(phase * 2.1) * max_offset * 0.6 * _shake_strength
	_shake_strength = maxf(0.0, _shake_strength - maxf(GameConfig.cam_shake_decay, 0.1) * delta)


func _update_squash(delta: float) -> void:
	if _visual_root == null:
		return
	if _squash_strength <= 0.001:
		_visual_root.scale = _base_visual_scale
		_squash_strength = 0.0
		return
	var amount: float = maxf(GameConfig.landing_squash_amount, 0.0) * _squash_strength
	_visual_root.scale = Vector3(
		_base_visual_scale.x * (1.0 + amount * 0.35),
		_base_visual_scale.y * (1.0 - amount),
		_base_visual_scale.z * (1.0 + amount * 0.18)
	)
	_squash_strength = maxf(0.0, _squash_strength - maxf(GameConfig.landing_squash_recover_speed, 0.1) * delta)


func _on_vehicle_changed_surface(surface_id: StringName) -> void:
	_surface_id = surface_id
	if _vehicle == null:
		return
	var state: RefCounted = _vehicle.call("get_state") as RefCounted
	if state == null:
		return
	_emit_surface_burst(surface_id, state.get("position"))


func _emit_surface_burst(surface_id: StringName, position: Vector3) -> void:
	if _last_speed < GameConfig.surface_burst_speed_threshold:
		return
	var particles: GPUParticles3D = _burst_for_surface(surface_id)
	if particles == null:
		return
	particles.global_position = position + Vector3.UP * 0.035
	particles.restart()
	particles.emitting = true


func _burst_for_surface(surface_id: StringName) -> GPUParticles3D:
	if surface_id == &"mud":
		return get_node_or_null(MUD_BURST_NAME) as GPUParticles3D
	if surface_id == &"wet_stone":
		return get_node_or_null(WATER_BURST_NAME) as GPUParticles3D
	if surface_id == &"packed_dirt" or surface_id == &"packed_gravel" or surface_id == &"loose_rock":
		return get_node_or_null(DUST_BURST_NAME) as GPUParticles3D
	if surface_id == &"sand_wash":
		return get_node_or_null(DUST_BURST_NAME) as GPUParticles3D
	return null


func _ensure_bursts() -> void:
	if get_node_or_null(DUST_BURST_NAME) == null:
		add_child(_make_burst(DUST_BURST_NAME, BURST_SEED_DUST, Color(0.74, 0.61, 0.42, 0.45), 0.20))
	if get_node_or_null(MUD_BURST_NAME) == null:
		add_child(_make_burst(MUD_BURST_NAME, BURST_SEED_MUD, Color(0.20, 0.12, 0.055, 0.62), 0.16))
	if get_node_or_null(WATER_BURST_NAME) == null:
		add_child(_make_burst(WATER_BURST_NAME, BURST_SEED_WATER, Color(0.48, 0.72, 0.76, 0.52), 0.18))


func _make_burst(node_name: String, seed: int, color: Color, particle_scale: float) -> GPUParticles3D:
	var particles: GPUParticles3D = GPUParticles3D.new()
	particles.name = node_name
	particles.amount = maxi(GameConfig.surface_burst_max_particles, 0)
	particles.lifetime = GameConfig.surface_burst_lifetime
	particles.one_shot = true
	particles.emitting = false
	particles.use_fixed_seed = true
	particles.seed = seed
	particles.randomness = 0.0
	particles.fixed_fps = 30
	particles.draw_pass_1 = _burst_mesh(node_name, color, particle_scale)
	particles.process_material = _burst_process_material(color, particle_scale)
	particles.set_meta("surface_feedback", node_name)
	return particles


func _burst_process_material(color: Color, particle_scale: float) -> ParticleProcessMaterial:
	var material: ParticleProcessMaterial = ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = 0.05
	material.direction = Vector3(0.0, 1.0, 0.0)
	material.gravity = Vector3(0.0, -0.22, 0.0)
	material.initial_velocity_min = 0.08
	material.initial_velocity_max = 0.28
	material.spread = 55.0
	material.damping_min = 0.02
	material.damping_max = 0.06
	material.scale_min = particle_scale * 0.35
	material.scale_max = particle_scale
	material.color = color
	return material


func _burst_mesh(node_name: String, color: Color, particle_scale: float) -> QuadMesh:
	var mesh: QuadMesh = QuadMesh.new()
	mesh.size = Vector2(particle_scale, particle_scale)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.resource_name = node_name + "_material"
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	mesh.material = material
	return mesh


# === W3-DUST: continuous wheel dust + spray ============================================

func _ensure_wheel_dust() -> void:
	_wheel_dust.clear()
	for wheel_index in range(WHEEL_COUNT):
		var node_name: String = WHEEL_DUST_NAME_PREFIX + str(wheel_index)
		var emitter: GPUParticles3D = get_node_or_null(node_name) as GPUParticles3D
		if emitter == null:
			emitter = _make_wheel_dust_emitter(node_name, WHEEL_DUST_FIXED_SEED + wheel_index)
			add_child(emitter)
		if emitter.emitting:
			emitter.emitting = false
		_wheel_dust.append(emitter)


func _update_wheel_dust(delta: float) -> void:
	var decay_rate: float = maxf(GameConfig.wheel_dust_kick_decay, 0.1)
	_dust_kick_boost = maxf(0.0, _dust_kick_boost - decay_rate * delta)
	if _wheel_dust.is_empty():
		return
	if not GameConfig.wheel_dust_enabled or _vehicle == null:
		_disable_all_wheel_dust()
		return
	var state: RefCounted = _vehicle.call("get_state") as RefCounted
	if state == null:
		_disable_all_wheel_dust()
		return
	var wheel_contact: Array[bool] = state.get("wheel_contact")
	var wheel_surfaces: Array[StringName] = state.get("wheel_surface")
	var wheel_hit_points: Array[Vector3] = state.get("wheel_hit_point")
	var speed_floor: float = maxf(GameConfig.wheel_dust_speed_threshold, 0.001)
	var speed_full: float = maxf(GameConfig.wheel_dust_speed_full, speed_floor + 0.001)
	var speed_ratio: float = clampf((_last_speed - speed_floor) / (speed_full - speed_floor), 0.0, 1.0)
	var boost: float = 1.0 + _dust_kick_boost * maxf(GameConfig.wheel_dust_kick_boost, 0.0)
	for wheel_index in range(_wheel_dust.size()):
		_update_single_wheel_dust(
			wheel_index,
			wheel_contact,
			wheel_surfaces,
			wheel_hit_points,
			speed_ratio,
			speed_floor,
			boost
		)


func _update_single_wheel_dust(
		wheel_index: int,
		wheel_contact: Array[bool],
		wheel_surfaces: Array[StringName],
		wheel_hit_points: Array[Vector3],
		speed_ratio: float,
		speed_floor: float,
		boost: float) -> void:
	var emitter: GPUParticles3D = _wheel_dust[wheel_index]
	var active: bool = false
	var target_ratio: float = 0.0
	var tint: Color = Color.WHITE
	if wheel_index < wheel_contact.size() \
			and bool(wheel_contact[wheel_index]) \
			and _last_speed >= speed_floor \
			and wheel_index < wheel_surfaces.size():
		var surface_id: StringName = wheel_surfaces[wheel_index]
		var intensity: float = _wheel_dust_intensity(surface_id)
		if intensity > 0.0:
			active = true
			tint = _wheel_dust_color(surface_id)
			target_ratio = clampf(speed_ratio * intensity * boost, 0.0, 1.0)
	if active:
		var material: ParticleProcessMaterial = emitter.process_material as ParticleProcessMaterial
		if material != null:
			material.color = tint
		emitter.amount_ratio = target_ratio
		if wheel_index < wheel_hit_points.size():
			emitter.global_position = wheel_hit_points[wheel_index] + Vector3.UP * WHEEL_DUST_HEIGHT_OFFSET
		if not emitter.emitting:
			emitter.emitting = true
	elif emitter.emitting:
		emitter.emitting = false


func _disable_all_wheel_dust() -> void:
	for emitter in _wheel_dust:
		if emitter.emitting:
			emitter.emitting = false


func _wheel_dust_intensity(surface_id: StringName) -> float:
	if surface_id == &"sand_wash":
		return clampf(GameConfig.wheel_dust_intensity_sand_wash, 0.0, 1.0)
	if surface_id == &"loose_rock":
		return clampf(GameConfig.wheel_dust_intensity_loose_rock, 0.0, 1.0)
	if surface_id == &"packed_dirt":
		return clampf(GameConfig.wheel_dust_intensity_packed_dirt, 0.0, 1.0)
	if surface_id == &"packed_gravel":
		return clampf(GameConfig.wheel_dust_intensity_packed_gravel, 0.0, 1.0)
	if surface_id == &"tall_grass":
		return clampf(GameConfig.wheel_dust_intensity_tall_grass, 0.0, 1.0)
	if surface_id == &"slickrock_dry":
		return clampf(GameConfig.wheel_dust_intensity_slickrock_dry, 0.0, 1.0)
	if surface_id == &"wood_plank":
		return clampf(GameConfig.wheel_dust_intensity_wood_plank, 0.0, 1.0)
	if surface_id == &"paved_road":
		return clampf(GameConfig.wheel_dust_intensity_paved_road, 0.0, 1.0)
	if surface_id == &"wet_stone":
		return clampf(GameConfig.wheel_dust_intensity_wet_stone, 0.0, 1.0)
	if surface_id == &"mud":
		return clampf(GameConfig.wheel_dust_intensity_mud, 0.0, 1.0)
	return 0.0


func _wheel_dust_color(surface_id: StringName) -> Color:
	if surface_id == &"sand_wash":
		return GameConfig.wheel_dust_color_sand_wash
	if surface_id == &"loose_rock":
		return GameConfig.wheel_dust_color_loose_rock
	if surface_id == &"packed_dirt":
		return GameConfig.wheel_dust_color_packed_dirt
	if surface_id == &"packed_gravel":
		return GameConfig.wheel_dust_color_packed_gravel
	if surface_id == &"tall_grass":
		return GameConfig.wheel_dust_color_tall_grass
	if surface_id == &"slickrock_dry":
		return GameConfig.wheel_dust_color_slickrock_dry
	if surface_id == &"wood_plank":
		return GameConfig.wheel_dust_color_wood_plank
	if surface_id == &"paved_road":
		return GameConfig.wheel_dust_color_paved_road
	if surface_id == &"wet_stone":
		return GameConfig.wheel_dust_color_wet_stone
	if surface_id == &"mud":
		return GameConfig.wheel_dust_color_mud
	return Color.WHITE


func _make_wheel_dust_emitter(node_name: String, seed: int) -> GPUParticles3D:
	var particles: GPUParticles3D = GPUParticles3D.new()
	particles.name = node_name
	particles.amount = maxi(GameConfig.wheel_dust_particles_per_wheel, 1)
	particles.lifetime = maxf(GameConfig.wheel_dust_lifetime, 0.05)
	particles.one_shot = false
	particles.emitting = false
	particles.use_fixed_seed = true
	particles.seed = seed
	particles.randomness = 0.0
	particles.fixed_fps = 30
	particles.amount_ratio = 0.0
	particles.visibility_range_end = GameConfig.vis_range_dust
	particles.draw_pass_1 = _wheel_dust_mesh()
	particles.process_material = _wheel_dust_process_material()
	particles.set_meta("surface_feedback", node_name)
	particles.set_meta("visual_contract", "deterministic_wheel_dust")
	return particles


func _wheel_dust_process_material() -> ParticleProcessMaterial:
	var material: ParticleProcessMaterial = ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = maxf(GameConfig.wheel_dust_emission_radius, 0.001)
	material.direction = Vector3(0.0, 1.0, 0.0)
	material.spread = WHEEL_DUST_SPREAD_DEG
	material.gravity = Vector3(0.0, WHEEL_DUST_GRAVITY, 0.0)
	material.initial_velocity_min = WHEEL_DUST_INITIAL_VELOCITY_MIN
	material.initial_velocity_max = WHEEL_DUST_INITIAL_VELOCITY_MAX
	material.damping_min = WHEEL_DUST_DAMPING_MIN
	material.damping_max = WHEEL_DUST_DAMPING_MAX
	material.scale_min = WHEEL_DUST_BILLBOARD_SCALE * 0.5
	material.scale_max = WHEEL_DUST_BILLBOARD_SCALE
	material.color = Color.WHITE
	return material


func _wheel_dust_mesh() -> QuadMesh:
	var mesh: QuadMesh = QuadMesh.new()
	mesh.size = Vector2(WHEEL_DUST_BILLBOARD_SCALE, WHEEL_DUST_BILLBOARD_SCALE)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.resource_name = "wheel_dust_billboard_material"
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color.WHITE
	mesh.material = material
	return mesh
