extends Node

const CedarHollowPlayableScene: PackedScene = preload("res://scenes/cedar_hollow_playable.tscn")
const FLOAT_EPSILON: float = 0.001
const WATER_SHADER_PATH: String = "res://systems/render/water_visual.gdshader"
const TILT_SHIFT_SHADER_PATH: String = "res://systems/render/tilt_shift.gdshader"
const TILT_SHIFT_LAYER_NAME: String = "TiltShiftLayer"
const TILT_SHIFT_RECT_NAME: String = "TiltShiftOverlay"
const TILT_SHIFT_LAYER_INDEX: int = 2
const WATER_SURFACE_COUNT: int = 3
const DUST_MOTE_COUNT_FLOOR: int = 1
const CONTACT_FILL_LIGHT_NAME: String = "VehicleContactFillLight"

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
	var world_environment: WorldEnvironment = _require_node(_scene_root, "GoldenHourEnvironment") as WorldEnvironment
	var sun: DirectionalLight3D = _require_node(_scene_root, "GoldenHourSun") as DirectionalLight3D
	_inspect_atmosphere(world_environment, sun)
	_inspect_viewport_antialiasing()
	_inspect_mood_toggle(world_environment)
	_inspect_dust_and_tilt_shift()
	_inspect_contact_fill_light()
	_inspect_vehicle_juice()
	_inspect_water_visuals()
	_finish()


func _inspect_atmosphere(world_environment: WorldEnvironment, sun: DirectionalLight3D) -> void:
	if world_environment == null or world_environment.environment == null:
		_errors.append("GoldenHourEnvironment should have an Environment resource")
		return
	var environment: Environment = world_environment.environment
	if not environment.fog_enabled:
		_errors.append("atmosphere should keep base fog enabled")
	if environment.fog_height_density <= 0.0:
		_errors.append("atmosphere should configure height fog density")
	if environment.fog_aerial_perspective <= 0.0:
		_errors.append("atmosphere should configure aerial perspective")
	if not environment.volumetric_fog_enabled:
		_errors.append("atmosphere should enable volumetric fog")
	if environment.volumetric_fog_density <= 0.0:
		_errors.append("atmosphere should configure volumetric fog density")
	if not environment.glow_enabled:
		_errors.append("atmosphere should enable subtle golden-hour glow")
	if environment.tonemap_mode != Environment.TONE_MAPPER_AGX:
		_errors.append("atmosphere should use AgX tonemapping")
	if environment.adjustment_enabled != GameConfig.atmosphere_grade_enabled:
		_errors.append("atmosphere grade enabled state should follow GameConfig")
	if absf(environment.adjustment_saturation - GameConfig.atmosphere_grade_saturation) > FLOAT_EPSILON:
		_errors.append("atmosphere grade saturation should follow GameConfig")
	if absf(environment.adjustment_contrast - GameConfig.atmosphere_grade_contrast) > FLOAT_EPSILON:
		_errors.append("atmosphere grade contrast should follow GameConfig")
	if absf(environment.adjustment_brightness - GameConfig.atmosphere_grade_brightness) > FLOAT_EPSILON:
		_errors.append("atmosphere grade brightness should follow GameConfig")
	if environment.sdfgi_enabled:
		_errors.append("atmosphere should keep SDFGI disabled")
	if environment.ssao_enabled != GameConfig.atmosphere_ssao_enabled:
		_errors.append("atmosphere SSAO enabled state should follow GameConfig")
	if absf(environment.ssao_radius - maxf(GameConfig.atmosphere_ssao_radius, 0.0)) > FLOAT_EPSILON:
		_errors.append("atmosphere SSAO radius should follow GameConfig")
	if absf(environment.ssao_intensity - maxf(GameConfig.atmosphere_ssao_intensity, 0.0)) > FLOAT_EPSILON:
		_errors.append("atmosphere SSAO intensity should follow GameConfig")
	if absf(environment.ssao_light_affect - clampf(GameConfig.atmosphere_ssao_light_affect, 0.0, 1.0)) > FLOAT_EPSILON:
		_errors.append("atmosphere SSAO light affect should follow GameConfig")
	if environment.ssil_enabled != GameConfig.atmosphere_ssil_enabled:
		_errors.append("atmosphere SSIL enabled state should follow GameConfig")
	if absf(environment.ssil_radius - maxf(GameConfig.atmosphere_ssil_radius, 0.0)) > FLOAT_EPSILON:
		_errors.append("atmosphere SSIL radius should follow GameConfig")
	if absf(environment.ssil_intensity - maxf(GameConfig.atmosphere_ssil_intensity, 0.0)) > FLOAT_EPSILON:
		_errors.append("atmosphere SSIL intensity should follow GameConfig")
	if absf(environment.ssil_sharpness - clampf(GameConfig.atmosphere_ssil_sharpness, 0.0, 1.0)) > FLOAT_EPSILON:
		_errors.append("atmosphere SSIL sharpness should follow GameConfig")
	if sun == null:
		return
	if not sun.shadow_enabled:
		_errors.append("GoldenHourSun should cast long shadows")
	if absf(sun.light_angular_distance - maxf(GameConfig.atmosphere_pcss_sun_angular_distance, 0.0)) > FLOAT_EPSILON:
		_errors.append("GoldenHourSun angular distance should follow GameConfig")
	if absf(sun.directional_shadow_max_distance - maxf(GameConfig.atmosphere_pcss_shadow_max_distance, 0.1)) > FLOAT_EPSILON:
		_errors.append("GoldenHourSun shadow distance should follow GameConfig")
	if absf(sun.shadow_blur - maxf(GameConfig.atmosphere_pcss_shadow_blur, 0.0)) > FLOAT_EPSILON:
		_errors.append("GoldenHourSun shadow blur should follow GameConfig")
	if absf(sun.shadow_opacity - clampf(GameConfig.atmosphere_pcss_shadow_opacity, 0.0, 1.0)) > FLOAT_EPSILON:
		_errors.append("GoldenHourSun shadow opacity should follow GameConfig")
	if sun.light_volumetric_fog_energy <= 0.0:
		_errors.append("GoldenHourSun should contribute to volumetric fog")


func _inspect_viewport_antialiasing() -> void:
	var viewport: Viewport = _scene_root.get_viewport()
	if viewport == null:
		_errors.append("Cedar scene should have a viewport for antialiasing settings")
		return
	if viewport.msaa_3d != Viewport.MSAA_DISABLED:
		_errors.append("Cedar viewport should use MSAA_DISABLED")
	if not viewport.use_taa:
		_errors.append("Cedar viewport should enable TAA for SSAO/SSIL")


func _inspect_mood_toggle(world_environment: WorldEnvironment) -> void:
	if world_environment == null or world_environment.environment == null:
		return
	var environment: Environment = world_environment.environment
	if environment.background_color != GameConfig.dusk_background_color:
		_errors.append("dusk mood background should remain GameConfig-driven")
	_scene_root.call("toggle_mood")
	if environment.background_color != GameConfig.dawn_background_color:
		_errors.append("dawn mood background should remain GameConfig-driven after toggle")
	if environment.fog_light_color != GameConfig.dawn_fog_light_color:
		_errors.append("dawn mood fog light color should remain GameConfig-driven")
	if environment.fog_height_density <= 0.0:
		_errors.append("dawn mood should keep height fog")
	if not environment.volumetric_fog_enabled:
		_errors.append("dawn mood should keep volumetric fog")
	_scene_root.call("toggle_mood")
	if environment.background_color != GameConfig.dusk_background_color:
		_errors.append("dusk mood background should restore after second toggle")


func _inspect_dust_and_tilt_shift() -> void:
	_require_node(_scene_root, "DustTiltShiftVisuals")
	var chase_camera: Camera3D = _require_node(_scene_root, "ChaseCamera") as Camera3D
	var orbit_camera: Camera3D = _require_node(_scene_root, "OrbitCamera") as Camera3D
	var fpv_camera: Camera3D = _require_node(_scene_root, "FpvCamera") as Camera3D
	_inspect_camera_far_planes(chase_camera, orbit_camera, fpv_camera)
	if chase_camera != null:
		var dust: GPUParticles3D = _require_node(chase_camera, "DustMoteField") as GPUParticles3D
		_inspect_dust_field(dust)
	_inspect_tilt_shift_layer()
	_inspect_tilt_shift_camera(chase_camera, "ChaseCamera")
	_inspect_tilt_shift_camera(orbit_camera, "OrbitCamera")
	_inspect_tilt_shift_camera(fpv_camera, "FpvCamera")


func _inspect_dust_field(dust: GPUParticles3D) -> void:
	if dust == null:
		return
	if not dust.emitting:
		_errors.append("DustMoteField should emit")
	if dust.amount < DUST_MOTE_COUNT_FLOOR:
		_errors.append("DustMoteField should have particles")
	if not dust.use_fixed_seed:
		_errors.append("DustMoteField should use a fixed seed")
	if dust.randomness > FLOAT_EPSILON:
		_errors.append("DustMoteField should avoid particle randomness")
	if absf(dust.visibility_range_end - GameConfig.vis_range_dust) > FLOAT_EPSILON:
		_errors.append("DustMoteField visibility range should follow GameConfig")
	var process_material: ParticleProcessMaterial = dust.process_material as ParticleProcessMaterial
	if process_material == null:
		_errors.append("DustMoteField should use ParticleProcessMaterial")
		return
	if process_material.emission_shape != ParticleProcessMaterial.EMISSION_SHAPE_BOX:
		_errors.append("DustMoteField should use a box field around the camera")


func _inspect_camera_far_planes(chase_camera: Camera3D, orbit_camera: Camera3D, fpv_camera: Camera3D) -> void:
	_require_camera_far(chase_camera, "ChaseCamera", GameConfig.cam_far)
	_require_camera_far(orbit_camera, "OrbitCamera", GameConfig.orbit_cam_far)
	_require_camera_far(fpv_camera, "FpvCamera", GameConfig.fpv_cam_far)


func _require_camera_far(camera: Camera3D, label: String, expected_far: float) -> void:
	if camera == null:
		return
	if absf(camera.far - expected_far) > FLOAT_EPSILON:
		_errors.append(label + " far plane expected " + str(expected_far) + ", got " + str(camera.far))


func _inspect_tilt_shift_camera(camera: Camera3D, label: String) -> void:
	if camera == null:
		return
	var attributes: CameraAttributesPractical = camera.attributes as CameraAttributesPractical
	if attributes == null:
		_errors.append(label + " should have atmosphere-owned practical camera attributes")
		return
	if attributes.dof_blur_near_enabled:
		_errors.append(label + " should not enable near DOF blur")
	if attributes.dof_blur_far_enabled:
		_errors.append(label + " should not enable far DOF blur")
	if attributes.auto_exposure_enabled != GameConfig.atmosphere_auto_exposure_enabled:
		_errors.append(label + " auto exposure should follow GameConfig")
	var axis: Vector2 = camera.get_meta("tilt_shift_gradient_axis", Vector2.ZERO) as Vector2
	if axis.distance_to(Vector2(0.0, 1.0)) > FLOAT_EPSILON:
		_errors.append(label + " should declare a vertical tilt-shift gradient axis")
	var screen_layer: String = String(camera.get_meta("tilt_shift_screen_layer", ""))
	if screen_layer != TILT_SHIFT_LAYER_NAME:
		_errors.append(label + " should declare " + TILT_SHIFT_LAYER_NAME + " as its tilt-shift screen layer")
	var focus_band: float = float(camera.get_meta("tilt_shift_focus_band", -1.0))
	if absf(focus_band - GameConfig.tilt_shift_focus_band) > FLOAT_EPSILON:
		_errors.append(label + " tilt-shift focus band should follow GameConfig")


func _inspect_tilt_shift_layer() -> void:
	var layer: CanvasLayer = _require_node(_scene_root, TILT_SHIFT_LAYER_NAME) as CanvasLayer
	if layer == null:
		return
	if layer.layer != TILT_SHIFT_LAYER_INDEX:
		_errors.append("TiltShiftLayer layer expected " + str(TILT_SHIFT_LAYER_INDEX) + ", got " + str(layer.layer))
	if layer.visible != GameConfig.tilt_shift_enabled:
		_errors.append("TiltShiftLayer visible state should follow GameConfig")
	var overlay: ColorRect = _require_node(layer, TILT_SHIFT_RECT_NAME) as ColorRect
	if overlay == null:
		return
	if absf(overlay.anchor_left) > FLOAT_EPSILON or absf(overlay.anchor_top) > FLOAT_EPSILON or absf(overlay.anchor_right - 1.0) > FLOAT_EPSILON or absf(overlay.anchor_bottom - 1.0) > FLOAT_EPSILON:
		_errors.append("TiltShiftOverlay should be full-rect anchored")
	var material: ShaderMaterial = overlay.material as ShaderMaterial
	if material == null:
		_errors.append("TiltShiftOverlay should use ShaderMaterial")
		return
	if material.shader == null:
		_errors.append("TiltShiftOverlay should have a shader")
	elif material.shader.resource_path != TILT_SHIFT_SHADER_PATH:
		_errors.append("TiltShiftOverlay shader expected " + TILT_SHIFT_SHADER_PATH + ", got " + material.shader.resource_path)
	_require_shader_float(material, "center", GameConfig.tilt_shift_band_center, "TiltShiftOverlay")
	_require_shader_float(material, "band", GameConfig.tilt_shift_focus_band, "TiltShiftOverlay")
	_require_shader_float(material, "blur", GameConfig.tilt_shift_blur_amount, "TiltShiftOverlay")


func _inspect_contact_fill_light() -> void:
	var body: Node = _require_node(_scene_root, "Vehicle/PhysicsBody")
	if body == null:
		return
	var node: Node = body.get_node_or_null(CONTACT_FILL_LIGHT_NAME)
	if not GameConfig.contact_fill_light_enabled:
		if node != null:
			_errors.append("VehicleContactFillLight should not exist when disabled")
		return
	var light: OmniLight3D = _require_node(body, CONTACT_FILL_LIGHT_NAME) as OmniLight3D
	if light == null:
		return
	if light.get_parent() != body:
		_errors.append("VehicleContactFillLight should be parented to the vehicle physics body")
	var expected_position: Vector3 = Vector3(0.0, -maxf(GameConfig.contact_fill_light_height, 0.0), 0.0)
	if light.position.distance_to(expected_position) > FLOAT_EPSILON:
		_errors.append("VehicleContactFillLight position should follow GameConfig")
	if absf(light.light_energy - maxf(GameConfig.contact_fill_light_energy, 0.0)) > FLOAT_EPSILON:
		_errors.append("VehicleContactFillLight energy should follow GameConfig")
	if absf(light.omni_range - maxf(GameConfig.contact_fill_light_range, 0.001)) > FLOAT_EPSILON:
		_errors.append("VehicleContactFillLight range should follow GameConfig")
	if light.light_color != GameConfig.contact_fill_light_color:
		_errors.append("VehicleContactFillLight color should follow GameConfig")
	if light.shadow_enabled:
		_errors.append("VehicleContactFillLight should be a soft fill light without its own shadow map")
	if light.get_meta("visual_contract", "") != "vehicle_parented_contact_fill_light":
		_errors.append("VehicleContactFillLight should declare its vehicle-parented contract")


func _inspect_vehicle_juice() -> void:
	var juice_rig: Node = _require_node(_scene_root, "VehicleJuiceRig")
	if juice_rig == null:
		return
	var callable: Callable = Callable(juice_rig, "_on_vehicle_changed_surface")
	if not EventBus.vehicle_changed_surface.is_connected(callable):
		_errors.append("VehicleJuiceRig should listen for vehicle_changed_surface")
	_require_surface_burst(juice_rig, "DustSurfaceBurst")
	_require_surface_burst(juice_rig, "MudSurfaceBurst")
	_require_surface_burst(juice_rig, "WaterSurfaceBurst")
	var chase_camera: Camera3D = _require_node(_scene_root, "ChaseCamera") as Camera3D
	var visual_root: Node3D = _require_node(_scene_root, "Vehicle/PhysicsBody/VisualRoot") as Node3D
	var base_scale: Vector3 = Vector3.ONE
	if visual_root != null:
		base_scale = visual_root.scale
	juice_rig.call("debug_trigger_landing", GameConfig.cam_shake_landing_speed_threshold * 2.0)
	juice_rig.call("_process", GameConfig.FIXED_DT)
	if chase_camera != null and absf(chase_camera.h_offset) <= FLOAT_EPSILON and absf(chase_camera.v_offset) <= FLOAT_EPSILON:
		_errors.append("VehicleJuiceRig landing feedback should apply camera shake offsets")
	if visual_root != null and visual_root.scale.distance_to(base_scale) <= FLOAT_EPSILON:
		_errors.append("VehicleJuiceRig landing feedback should squash/stretch only the visual root")
	juice_rig.call("debug_trigger_surface_burst", &"mud", Vector3(2.8, 0.0, -5.5), GameConfig.surface_burst_speed_threshold * 2.0)
	var mud_burst: GPUParticles3D = juice_rig.get_node_or_null("MudSurfaceBurst") as GPUParticles3D
	if mud_burst != null and not mud_burst.emitting:
		_errors.append("VehicleJuiceRig should emit mud burst particles for mud surface changes")


func _require_surface_burst(parent: Node, path: String) -> void:
	var burst: GPUParticles3D = _require_node(parent, path) as GPUParticles3D
	if burst == null:
		return
	if not burst.one_shot:
		_errors.append(path + " should be one-shot")
	if not burst.use_fixed_seed:
		_errors.append(path + " should use a fixed seed")
	if burst.randomness > FLOAT_EPSILON:
		_errors.append(path + " should avoid particle randomness")
	if burst.amount < DUST_MOTE_COUNT_FLOOR:
		_errors.append(path + " should have particles")


func _inspect_water_visuals() -> void:
	var water_root: Node = _require_node(_scene_root, "CedarHollow/WaterVisuals")
	if water_root == null:
		return
	var water_count: int = 0
	for child in water_root.get_children():
		var water: MeshInstance3D = child as MeshInstance3D
		if water == null:
			continue
		water_count += 1
		_inspect_water_surface(water)
	if water_count != WATER_SURFACE_COUNT:
		_errors.append("WaterVisuals expected " + str(WATER_SURFACE_COUNT) + " water surfaces, got " + str(water_count))
	_require_node(water_root, "bog_pool_water")
	_require_node(water_root, "crossing_water")
	_require_node(water_root, "culvert_runoff_water")


func _inspect_water_surface(water: MeshInstance3D) -> void:
	if not water.is_in_group("render_water_surface"):
		_errors.append(String(water.name) + " should be in render_water_surface group")
	if absf(water.visibility_range_end - GameConfig.vis_range_water) > FLOAT_EPSILON:
		_errors.append(String(water.name) + " visibility range should follow GameConfig")
	if _count_collision_objects(water) > 0:
		_errors.append(String(water.name) + " should be render-only and collision-free")
	var material: ShaderMaterial = water.material_override as ShaderMaterial
	if material == null:
		_errors.append(String(water.name) + " should use ShaderMaterial")
		return
	if material.shader == null:
		_errors.append(String(water.name) + " should have a shader")
		return
	if material.shader.resource_path != WATER_SHADER_PATH:
		_errors.append(String(water.name) + " shader expected " + WATER_SHADER_PATH + ", got " + material.shader.resource_path)
	_require_shader_color(material, "shallow_color", GameConfig.water_shallow_color, String(water.name))
	_require_shader_color(material, "deep_color", GameConfig.water_deep_color, String(water.name))
	_require_shader_float(material, "water_alpha", GameConfig.water_alpha, String(water.name))
	_require_shader_float(material, "depth_fade_distance", GameConfig.water_depth_fade_distance, String(water.name))
	_require_shader_float(material, "foam_edge_width", GameConfig.water_foam_edge_width, String(water.name))
	_require_shader_float(material, "flow_speed", GameConfig.water_flow_speed, String(water.name))
	_require_shader_float(material, "wave_amplitude", GameConfig.water_wave_amplitude, String(water.name))
	_require_shader_float(material, "foam_normal_strength", GameConfig.water_foam_normal_strength, String(water.name))
	_require_shader_float(material, "foam_normal_scale", GameConfig.water_foam_normal_scale, String(water.name))
	_require_shader_float(material, "foam_normal_flow_speed", GameConfig.water_foam_normal_flow_speed, String(water.name))
	_require_shader_bool(material, "ssr_enabled", GameConfig.water_ssr_enabled, String(water.name))
	_require_shader_int(material, "ssr_max_steps", GameConfig.water_ssr_max_steps, String(water.name))
	_require_shader_float(material, "ssr_intensity", GameConfig.water_ssr_intensity, String(water.name))
	_require_shader_float(material, "ssr_step_size", GameConfig.water_ssr_step_size, String(water.name))
	_require_shader_float(material, "ssr_thickness", GameConfig.water_ssr_thickness, String(water.name))
	_require_shader_float(material, "water_roughness", GameConfig.water_roughness, String(water.name))


func _require_shader_color(material: ShaderMaterial, parameter_name: String, expected: Color, label: String) -> void:
	var value: Color = material.get_shader_parameter(parameter_name) as Color
	if value != expected:
		_errors.append(label + " shader parameter " + parameter_name + " mismatch")


func _require_shader_float(material: ShaderMaterial, parameter_name: String, expected: float, label: String) -> void:
	var value: float = float(material.get_shader_parameter(parameter_name))
	if absf(value - expected) > FLOAT_EPSILON:
		_errors.append(label + " shader parameter " + parameter_name + " expected " + str(expected) + ", got " + str(value))


func _require_shader_int(material: ShaderMaterial, parameter_name: String, expected: int, label: String) -> void:
	var value: int = int(material.get_shader_parameter(parameter_name))
	if value != expected:
		_errors.append(label + " shader parameter " + parameter_name + " expected " + str(expected) + ", got " + str(value))


func _require_shader_bool(material: ShaderMaterial, parameter_name: String, expected: bool, label: String) -> void:
	var value: bool = bool(material.get_shader_parameter(parameter_name))
	if value != expected:
		_errors.append(label + " shader parameter " + parameter_name + " expected " + str(expected) + ", got " + str(value))


func _count_collision_objects(node: Node) -> int:
	var count: int = 0
	if node is CollisionObject3D or node is CollisionShape3D:
		count += 1
	for child in node.get_children():
		count += _count_collision_objects(child)
	return count


func _require_node(parent: Node, path: String) -> Node:
	if parent == null:
		_errors.append("missing parent while requiring " + path)
		return null
	var node: Node = parent.get_node_or_null(path)
	if node == null:
		_errors.append("missing node " + path)
	return node


func _finish() -> void:
	if not _errors.is_empty():
		for error in _errors:
			push_error(error)
		get_tree().quit(1)
		return
	print("ok: Cedar Hollow mood, dust, water, and vehicle juice visuals instantiated")
	get_tree().quit(0)
