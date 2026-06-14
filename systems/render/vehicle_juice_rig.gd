class_name VehicleJuiceRig
extends Node3D

const DUST_BURST_NAME: String = "DustSurfaceBurst"
const MUD_BURST_NAME: String = "MudSurfaceBurst"
const WATER_BURST_NAME: String = "WaterSurfaceBurst"
const DEFAULT_SHAKE_MAX_OFFSET: float = 0.018
const DEFAULT_SURFACE_BURST_PARTICLES: int = 18
const DEFAULT_LANDING_SQUASH_AMOUNT: float = 0.10
const BURST_SEED_DUST: int = 7101
const BURST_SEED_MUD: int = 7102
const BURST_SEED_WATER: int = 7103

var _vehicle: Node = null
var _camera: Camera3D = null
var _visual_root: Node3D = null
var _base_visual_scale: Vector3 = Vector3.ONE
var _previous_on_ground: bool = true
var _previous_vertical_velocity: float = 0.0
var _last_speed: float = 0.0
var _shake_strength: float = 0.0
var _squash_strength: float = 0.0
var _surface_id: StringName = &""


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


func _process(delta: float) -> void:
	_update_from_vehicle_state()
	_update_camera_shake(delta)
	_update_squash(delta)


func debug_trigger_landing(impact_speed: float) -> void:
	_trigger_landing_feedback(impact_speed)


func debug_trigger_surface_burst(surface_id: StringName, position: Vector3, speed: float) -> void:
	_last_speed = speed
	_emit_surface_burst(surface_id, position)


func _update_from_vehicle_state() -> void:
	if _vehicle == null:
		return
	var state: RefCounted = _vehicle.call("get_state") as RefCounted
	if state == null:
		return
	var on_ground: bool = bool(state.get("on_ground"))
	var linear_velocity: Vector3 = state.get("linear_velocity")
	_last_speed = linear_velocity.length()
	if on_ground and not _previous_on_ground:
		var impact_speed: float = maxf(-_previous_vertical_velocity, 0.0)
		if impact_speed >= GameConfig.cam_shake_landing_speed_threshold:
			_trigger_landing_feedback(impact_speed)
	_previous_on_ground = on_ground
	_previous_vertical_velocity = linear_velocity.y
	global_position = state.get("position")


func _trigger_landing_feedback(impact_speed: float) -> void:
	var threshold: float = maxf(GameConfig.cam_shake_landing_speed_threshold, 0.001)
	var normalized: float = clampf((impact_speed - threshold) / threshold, 0.0, 1.0)
	_shake_strength = maxf(_shake_strength, normalized)
	_squash_strength = maxf(_squash_strength, normalized)


func _update_camera_shake(delta: float) -> void:
	if _camera == null:
		return
	if _shake_strength <= 0.001:
		_camera.h_offset = 0.0
		_camera.v_offset = 0.0
		_shake_strength = 0.0
		return
	var max_offset: float = _positive_float_or(GameConfig.cam_shake_max_offset, DEFAULT_SHAKE_MAX_OFFSET)
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
	var amount: float = _positive_float_or(GameConfig.landing_squash_amount, DEFAULT_LANDING_SQUASH_AMOUNT) * _squash_strength
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
	particles.amount = _positive_int_or(GameConfig.surface_burst_max_particles, DEFAULT_SURFACE_BURST_PARTICLES)
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


func _positive_int_or(value: int, fallback: int) -> int:
	if value > 0:
		return value
	return fallback


func _positive_float_or(value: float, fallback: float) -> float:
	if value > 0.0:
		return value
	return fallback
