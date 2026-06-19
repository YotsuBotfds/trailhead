class_name AtmosphereVisualBuilder
extends RefCounted

const MOOD_DUSK: int = 0
const MOOD_DAWN: int = 1
const MOOD_NIGHT: int = 2
const DUSK_HERO_SUN_ROTATION_DEGREES: Vector3 = Vector3(-16.0, -62.0, 0.0)
const DUSK_HERO_SUN_ENERGY: float = 2.38
const DUSK_HERO_SUN_COLOR: Color = Color(1.0, 0.84, 0.64)
const DUSK_HERO_AMBIENT_COLOR: Color = Color(0.45, 0.49, 0.56)
const DUSK_HERO_AMBIENT_ENERGY: float = 0.31
const DUSK_HERO_FOG_LIGHT_COLOR: Color = Color(0.56, 0.59, 0.63)
const DUSK_HERO_VOLUMETRIC_FOG_ALBEDO: Color = Color(0.58, 0.62, 0.68)
const DUSK_AERIAL_FOG_DENSITY: float = 0.0012
const DAWN_VOLUMETRIC_FOG_ALBEDO: Color = Color(0.70, 0.78, 0.82)
const NIGHT_MOON_ROTATION_DEGREES: Vector3 = Vector3(-48.0, 36.0, 0.0)
const NIGHT_MOON_ENERGY: float = 0.34
const NIGHT_MOON_COLOR: Color = Color(0.52, 0.66, 0.92)
const NIGHT_AMBIENT_COLOR: Color = Color(0.045, 0.070, 0.120)
const NIGHT_AMBIENT_ENERGY: float = 0.055
const NIGHT_FOG_LIGHT_COLOR: Color = Color(0.16, 0.24, 0.36)
const NIGHT_VOLUMETRIC_FOG_ALBEDO: Color = Color(0.19, 0.28, 0.42)
const NIGHT_AERIAL_FOG_DENSITY: float = 0.0018
const NIGHT_HEIGHT_FOG_DENSITY: float = 0.014
const NIGHT_GLOW_INTENSITY: float = 0.035
const NIGHT_GLOW_STRENGTH: float = 0.11
const DUSK_GLOW_INTENSITY: float = 0.18
const DUSK_GLOW_STRENGTH: float = 0.32
const DAWN_GLOW_INTENSITY: float = 0.10
const DAWN_GLOW_STRENGTH: float = 0.20
const GLOW_BLOOM: float = 0.06
const DUSK_HEIGHT_FOG_DENSITY: float = 0.008
const DAWN_HEIGHT_FOG_DENSITY: float = 0.032
const VOLUMETRIC_FOG_DENSITY_FLOOR: float = 0.006
const VOLUMETRIC_FOG_LENGTH: float = 48.0
const FOG_HEIGHT: float = 0.18
const FOG_DEPTH_CURVE_FLOOR: float = 1.35
const FOG_AERIAL_PERSPECTIVE: float = 0.12
const FOG_SUN_SCATTER: float = 0.22
const FOG_SKY_AFFECT: float = 0.32
const VOLUMETRIC_FOG_SKY_AFFECT: float = 0.24
const SHADOW_FADE_START: float = 0.72
const CONTACT_FILL_LIGHT_NAME: String = "VehicleContactFillLight"
const CAMERA_ATTRIBUTES_OWNER_META: StringName = &"atmosphere_camera_attributes_instance_id"


static func apply_mood(world_environment: WorldEnvironment, sun: DirectionalLight3D, mood: int) -> void:
	if sun != null:
		_apply_mood_sun(sun, mood)
		_apply_sun_atmosphere(sun)
	if world_environment == null or world_environment.environment == null:
		return
	_apply_viewport_antialiasing(world_environment.get_viewport())
	var environment: Environment = world_environment.environment
	_apply_mood_environment(environment, mood)
	_apply_height_fog(environment, mood)
	_apply_volumetric_fog(environment, mood)
	_apply_golden_hour_glow(environment, mood)
	_apply_color_grade(environment)
	_apply_screen_space_grounding(environment)


static func configure_render_support(root: Node, vehicle: Node, chase_camera: Camera3D, orbit_camera: Camera3D, fpv_camera: Camera3D) -> void:
	if root != null:
		_apply_viewport_antialiasing(root.get_viewport())
	_apply_camera_attributes(chase_camera)
	_apply_camera_attributes(orbit_camera)
	_apply_camera_attributes(fpv_camera)
	_attach_contact_fill_light(vehicle)


static func _apply_mood_sun(sun: DirectionalLight3D, mood: int) -> void:
	if mood == MOOD_NIGHT:
		sun.rotation_degrees = NIGHT_MOON_ROTATION_DEGREES
		sun.light_energy = NIGHT_MOON_ENERGY
		sun.light_color = NIGHT_MOON_COLOR
		return
	if mood == MOOD_DAWN:
		sun.rotation_degrees = GameConfig.dawn_sun_rotation_degrees
		sun.light_energy = GameConfig.dawn_sun_energy
		sun.light_color = GameConfig.dawn_sun_color
		return
	sun.rotation_degrees = DUSK_HERO_SUN_ROTATION_DEGREES
	sun.light_energy = DUSK_HERO_SUN_ENERGY
	sun.light_color = DUSK_HERO_SUN_COLOR


static func _apply_sun_atmosphere(sun: DirectionalLight3D) -> void:
	sun.shadow_enabled = true
	sun.light_angular_distance = maxf(GameConfig.atmosphere_pcss_sun_angular_distance, 0.0)
	sun.directional_shadow_max_distance = maxf(GameConfig.atmosphere_pcss_shadow_max_distance, 0.1)
	sun.directional_shadow_fade_start = SHADOW_FADE_START
	sun.directional_shadow_mode = _directional_shadow_mode(GameConfig.atmosphere_directional_shadow_mode)
	sun.directional_shadow_blend_splits = GameConfig.atmosphere_directional_shadow_blend_splits
	sun.shadow_blur = maxf(GameConfig.atmosphere_pcss_shadow_blur, 0.0)
	sun.shadow_opacity = clampf(GameConfig.atmosphere_pcss_shadow_opacity, 0.0, 1.0)
	sun.light_volumetric_fog_energy = GameConfig.atmosphere_sun_volumetric_fog_energy


static func _directional_shadow_mode(mode: int) -> int:
	match mode:
		GameConfig.DIRECTIONAL_SHADOW_ORTHOGONAL:
			return DirectionalLight3D.SHADOW_ORTHOGONAL
		GameConfig.DIRECTIONAL_SHADOW_PARALLEL_2_SPLITS:
			return DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		GameConfig.DIRECTIONAL_SHADOW_PARALLEL_4_SPLITS:
			return DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		_:
			return DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS


static func _apply_mood_environment(environment: Environment, mood: int) -> void:
	environment.fog_enabled = true
	if mood == MOOD_NIGHT:
		environment.ambient_light_color = NIGHT_AMBIENT_COLOR
		environment.ambient_light_energy = NIGHT_AMBIENT_ENERGY
		environment.fog_density = NIGHT_AERIAL_FOG_DENSITY
		environment.fog_light_color = NIGHT_FOG_LIGHT_COLOR
		return
	if mood == MOOD_DAWN:
		environment.ambient_light_color = GameConfig.dawn_ambient_color
		environment.ambient_light_energy = GameConfig.dawn_ambient_energy
		environment.fog_density = GameConfig.dawn_fog_density
		environment.fog_light_color = GameConfig.dawn_fog_light_color
		return
	environment.ambient_light_color = DUSK_HERO_AMBIENT_COLOR
	environment.ambient_light_energy = DUSK_HERO_AMBIENT_ENERGY
	environment.fog_density = DUSK_AERIAL_FOG_DENSITY
	environment.fog_light_color = DUSK_HERO_FOG_LIGHT_COLOR


static func _apply_height_fog(environment: Environment, mood: int) -> void:
	var fallback_density: float = DUSK_HEIGHT_FOG_DENSITY
	if mood == MOOD_DAWN:
		fallback_density = DAWN_HEIGHT_FOG_DENSITY
	elif mood == MOOD_NIGHT:
		fallback_density = NIGHT_HEIGHT_FOG_DENSITY
	environment.fog_height = FOG_HEIGHT
	environment.fog_height_density = _positive_float_or(GameConfig.atmosphere_height_fog_density, fallback_density)
	environment.fog_depth_curve = maxf(GameConfig.atmosphere_height_fog_falloff, FOG_DEPTH_CURVE_FLOOR)
	environment.fog_aerial_perspective = FOG_AERIAL_PERSPECTIVE
	environment.fog_sun_scatter = FOG_SUN_SCATTER
	environment.fog_sky_affect = FOG_SKY_AFFECT


static func _apply_volumetric_fog(environment: Environment, mood: int) -> void:
	environment.volumetric_fog_enabled = GameConfig.atmosphere_volumetric_fog_enabled
	environment.volumetric_fog_density = _positive_float_or(GameConfig.atmosphere_volumetric_fog_density, VOLUMETRIC_FOG_DENSITY_FLOOR)
	environment.volumetric_fog_length = VOLUMETRIC_FOG_LENGTH
	if mood == MOOD_NIGHT:
		environment.volumetric_fog_albedo = NIGHT_VOLUMETRIC_FOG_ALBEDO
		environment.volumetric_fog_emission = Color(0.015, 0.030, 0.060)
		environment.volumetric_fog_emission_energy = 0.025
	elif mood == MOOD_DAWN:
		environment.volumetric_fog_albedo = DAWN_VOLUMETRIC_FOG_ALBEDO
		environment.volumetric_fog_emission = Color(0.08, 0.12, 0.14)
		environment.volumetric_fog_emission_energy = 0.06
	else:
		environment.volumetric_fog_albedo = DUSK_HERO_VOLUMETRIC_FOG_ALBEDO
		environment.volumetric_fog_emission = Color(0.20, 0.13, 0.07)
		environment.volumetric_fog_emission_energy = 0.10
	environment.volumetric_fog_anisotropy = GameConfig.atmosphere_volumetric_fog_anisotropy
	environment.volumetric_fog_ambient_inject = 0.28
	environment.volumetric_fog_sky_affect = VOLUMETRIC_FOG_SKY_AFFECT
	environment.volumetric_fog_temporal_reprojection_enabled = true


static func _apply_golden_hour_glow(environment: Environment, mood: int) -> void:
	environment.glow_enabled = true
	environment.glow_normalized = true
	environment.glow_bloom = GLOW_BLOOM
	if mood == MOOD_NIGHT:
		environment.glow_intensity = NIGHT_GLOW_INTENSITY
		environment.glow_strength = NIGHT_GLOW_STRENGTH
	elif mood == MOOD_DAWN:
		environment.glow_intensity = DAWN_GLOW_INTENSITY
		environment.glow_strength = DAWN_GLOW_STRENGTH
	else:
		environment.glow_intensity = DUSK_GLOW_INTENSITY
		environment.glow_strength = DUSK_GLOW_STRENGTH
		environment.glow_hdr_threshold = GameConfig.atmosphere_glow_hdr_threshold
		environment.glow_hdr_scale = GameConfig.atmosphere_glow_hdr_scale
		environment.glow_bloom = GameConfig.atmosphere_glow_bloom_dusk


static func _apply_color_grade(environment: Environment) -> void:
	environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	environment.adjustment_enabled = GameConfig.atmosphere_grade_enabled
	environment.adjustment_saturation = GameConfig.atmosphere_grade_saturation
	environment.adjustment_contrast = GameConfig.atmosphere_grade_contrast
	environment.adjustment_brightness = GameConfig.atmosphere_grade_brightness
	environment.adjustment_color_correction = _load_color_correction_texture(GameConfig.atmosphere_grade_color_correction_path)


static func _apply_screen_space_grounding(environment: Environment) -> void:
	environment.sdfgi_enabled = false
	environment.ssao_enabled = GameConfig.atmosphere_ssao_enabled
	environment.ssao_radius = maxf(GameConfig.atmosphere_ssao_radius, 0.0)
	environment.ssao_intensity = maxf(GameConfig.atmosphere_ssao_intensity, 0.0)
	environment.ssao_light_affect = clampf(GameConfig.atmosphere_ssao_light_affect, 0.0, 1.0)
	environment.ssil_enabled = GameConfig.atmosphere_ssil_enabled
	environment.ssil_radius = maxf(GameConfig.atmosphere_ssil_radius, 0.0)
	environment.ssil_intensity = maxf(GameConfig.atmosphere_ssil_intensity, 0.0)
	environment.ssil_sharpness = clampf(GameConfig.atmosphere_ssil_sharpness, 0.0, 1.0)


static func _apply_viewport_antialiasing(viewport: Viewport) -> void:
	if viewport == null:
		return
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.use_taa = true


static func _apply_camera_attributes(camera: Camera3D) -> void:
	if camera == null:
		return
	var existing_attributes: CameraAttributes = camera.attributes
	if existing_attributes != null and not (existing_attributes is CameraAttributesPractical):
		var type_message: String = "AtmosphereVisualBuilder expected CameraAttributesPractical on " + String(camera.name) + ", got " + existing_attributes.get_class()
		push_error(type_message)
		assert(false, type_message)
		return
	var attributes: CameraAttributesPractical = existing_attributes as CameraAttributesPractical
	if attributes == null:
		attributes = CameraAttributesPractical.new()
		camera.attributes = attributes
	var previous_id: int = int(camera.get_meta(CAMERA_ATTRIBUTES_OWNER_META, 0))
	var current_id: int = attributes.get_instance_id()
	if previous_id != 0 and previous_id != current_id:
		var replace_message: String = "CameraAttributesPractical was replaced after AtmosphereVisualBuilder configured " + String(camera.name)
		push_error(replace_message)
		assert(false, replace_message)
		return
	camera.set_meta(CAMERA_ATTRIBUTES_OWNER_META, current_id)
	attributes.auto_exposure_enabled = GameConfig.atmosphere_auto_exposure_enabled


static func _attach_contact_fill_light(vehicle: Node) -> void:
	if vehicle == null:
		return
	var body: Node3D = vehicle.get_node_or_null("PhysicsBody") as Node3D
	if body == null:
		return
	var existing: OmniLight3D = body.get_node_or_null(CONTACT_FILL_LIGHT_NAME) as OmniLight3D
	if not GameConfig.contact_fill_light_enabled:
		if existing != null:
			existing.queue_free()
		return
	var light: OmniLight3D = existing
	if light == null:
		light = OmniLight3D.new()
		light.name = CONTACT_FILL_LIGHT_NAME
		body.add_child(light)
	light.position = Vector3(0.0, -maxf(GameConfig.contact_fill_light_height, 0.0), 0.0)
	light.light_color = GameConfig.contact_fill_light_color
	light.light_energy = maxf(GameConfig.contact_fill_light_energy, 0.0)
	light.omni_range = maxf(GameConfig.contact_fill_light_range, 0.001)
	light.shadow_enabled = false
	light.light_volumetric_fog_energy = 0.0
	light.set_meta("visual_contract", "vehicle_parented_contact_fill_light")


static func _load_color_correction_texture(path: String) -> Texture3D:
	if path.is_empty():
		return null
	var resource: Resource = ResourceLoader.load(path) as Resource
	var texture: Texture3D = resource as Texture3D
	if texture == null:
		push_warning("Atmosphere color correction path is not a Texture3D: " + path)
	return texture


static func _positive_float_or(value: float, fallback: float) -> float:
	if value > 0.0:
		return value
	return fallback
