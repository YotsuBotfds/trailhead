class_name AtmosphereVisualBuilder
extends RefCounted

const MOOD_DUSK: int = 0
const MOOD_DAWN: int = 1
const DUSK_HEIGHT_FOG_DENSITY: float = 0.018
const DAWN_HEIGHT_FOG_DENSITY: float = 0.026
const VOLUMETRIC_FOG_DENSITY_FLOOR: float = 0.006
const VOLUMETRIC_FOG_LENGTH: float = 32.0
const FOG_HEIGHT: float = 0.06
const FOG_AERIAL_PERSPECTIVE: float = 0.38
const FOG_SUN_SCATTER: float = 0.42
const SHADOW_MAX_DISTANCE: float = 36.0
const SHADOW_FADE_START: float = 0.72
const SHADOW_BLUR: float = 1.25


static func apply_mood(world_environment: WorldEnvironment, sun: DirectionalLight3D, mood: int) -> void:
	if sun != null:
		_apply_sun_atmosphere(sun)
	if world_environment == null or world_environment.environment == null:
		return
	var environment: Environment = world_environment.environment
	_apply_height_fog(environment, mood)
	_apply_volumetric_fog(environment)
	_apply_golden_hour_glow(environment, mood)


static func _apply_sun_atmosphere(sun: DirectionalLight3D) -> void:
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = SHADOW_MAX_DISTANCE
	sun.directional_shadow_fade_start = SHADOW_FADE_START
	sun.shadow_blur = SHADOW_BLUR
	sun.light_volumetric_fog_energy = 0.82


static func _apply_height_fog(environment: Environment, mood: int) -> void:
	var fallback_density: float = DUSK_HEIGHT_FOG_DENSITY
	if mood == MOOD_DAWN:
		fallback_density = DAWN_HEIGHT_FOG_DENSITY
	environment.fog_height = FOG_HEIGHT
	environment.fog_height_density = _positive_float_or(GameConfig.atmosphere_height_fog_density, fallback_density)
	environment.fog_depth_curve = maxf(GameConfig.atmosphere_height_fog_falloff, 0.35)
	environment.fog_aerial_perspective = FOG_AERIAL_PERSPECTIVE
	environment.fog_sun_scatter = FOG_SUN_SCATTER
	environment.fog_sky_affect = 0.72


static func _apply_volumetric_fog(environment: Environment) -> void:
	environment.volumetric_fog_enabled = true
	environment.volumetric_fog_density = _positive_float_or(GameConfig.atmosphere_volumetric_fog_density, VOLUMETRIC_FOG_DENSITY_FLOOR)
	environment.volumetric_fog_length = VOLUMETRIC_FOG_LENGTH
	environment.volumetric_fog_albedo = GameConfig.dusk_fog_light_color
	environment.volumetric_fog_emission = Color(0.18, 0.14, 0.09)
	environment.volumetric_fog_emission_energy = 0.08
	environment.volumetric_fog_anisotropy = 0.32
	environment.volumetric_fog_ambient_inject = 0.28
	environment.volumetric_fog_sky_affect = 0.55
	environment.volumetric_fog_temporal_reprojection_enabled = true


static func _apply_golden_hour_glow(environment: Environment, mood: int) -> void:
	environment.glow_enabled = true
	environment.glow_normalized = true
	environment.glow_intensity = 0.18 if mood == MOOD_DUSK else 0.10
	environment.glow_strength = 0.32 if mood == MOOD_DUSK else 0.20
	environment.glow_bloom = 0.06


static func _positive_float_or(value: float, fallback: float) -> float:
	if value > 0.0:
		return value
	return fallback
