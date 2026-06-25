extends Node

const CedarHollowPlayableScene: PackedScene = preload("res://scenes/cedar_hollow_playable.tscn")
const AtmosphereVisualBuilderScript: GDScript = preload("res://systems/render/atmosphere_visual_builder.gd")
const DustTiltShiftVisualBuilderScript: GDScript = preload("res://systems/render/dust_tilt_shift_visual_builder.gd")
const WaterVisualBuilderScript: GDScript = preload("res://systems/render/water_visual_builder.gd")
const FLOAT_EPSILON: float = 0.001
const COLOR_TOLERANCE: float = 0.02
const WATER_SHADER_PATH: String = "res://systems/render/water_visual.gdshader"
const DUSK_GOLDEN_SKY_SHADER_PATH: String = "res://systems/render/dusk_golden_sky.gdshader"
const ZION_REGION_ID: String = "cedar_hollow_zion"
const WORLD_REGION_ID_META: StringName = &"trailhead_world_region_id"
const TILT_SHIFT_SHADER_PATH: String = "res://systems/render/tilt_shift.gdshader"
const TILT_SHIFT_LAYER_NAME: String = "TiltShiftLayer"
const TILT_SHIFT_RECT_NAME: String = "TiltShiftOverlay"
const TILT_SHIFT_LAYER_INDEX: int = 2
const WATER_SURFACE_COUNT: int = 3
const ZION_WATER_SURFACE_COUNT: int = 2
const DUST_MOTE_COUNT_FLOOR: int = 1
const CONTACT_FILL_LIGHT_NAME: String = "VehicleContactFillLight"
const SOFT_SHADOW_FILTER_QUALITY_SETTING_PATH: String = "rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality"
const EXPECTED_SOFT_SHADOW_FILTER_QUALITY: int = 2
const VOLUMETRIC_FOG_VOLUME_SIZE_SETTING_PATH: String = "rendering/environment/volumetric_fog/volume_size"
const EXPECTED_VOLUMETRIC_FOG_VOLUME_SIZE: int = 16
const VOLUMETRIC_FOG_VOLUME_DEPTH_SETTING_PATH: String = "rendering/environment/volumetric_fog/volume_depth"
const EXPECTED_VOLUMETRIC_FOG_VOLUME_DEPTH: int = 16
const VOLUMETRIC_FOG_USE_FILTER_SETTING_PATH: String = "rendering/environment/volumetric_fog/use_filter"
const EXPECTED_VOLUMETRIC_FOG_USE_FILTER: int = 1
const PEBBLE_MATERIAL_META: StringName = &"vehicle_juice_pebble_material"
const SOFT_DUST_MATERIAL_META: StringName = &"vehicle_juice_soft_radial_alpha"
const VEHICLE_WHEEL_COUNT: int = 4
const REAR_ROOSTER_COUNT: int = 2
const PEBBLE_DRAW_MESH_MAX_EXTENT: float = 0.030
const BARE_WHITE_CHANNEL: float = 0.92
const ACTIVE_PARTICLE_RATIO_FLOOR: float = 0.01


class FakeJuiceVehicleState:
	extends RefCounted

	var on_ground: bool = true
	var linear_velocity: Vector3 = Vector3.ZERO
	var position: Vector3 = Vector3.ZERO
	var wheel_contact: Array[bool] = [true, true, true, true]
	var wheel_surface: Array[StringName] = [&"sand_wash", &"sand_wash", &"loose_rock", &"loose_rock"]
	var wheel_hit_point: Array[Vector3] = [
		Vector3(-0.38, 0.0, -0.42),
		Vector3(0.38, 0.0, -0.42),
		Vector3(-0.38, 0.0, 0.42),
		Vector3(0.38, 0.0, 0.42),
	]
	var basis: Basis = Basis.IDENTITY


class FakeJuiceVehicle:
	extends Node

	var state: FakeJuiceVehicleState = FakeJuiceVehicleState.new()

	func get_state() -> RefCounted:
		return state

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
	_inspect_screen_space_gi_tier_guard(world_environment, sun)
	_inspect_viewport_antialiasing()
	_inspect_mood_toggle(world_environment, sun)
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
	_require_color_close("dusk ambient color", environment.ambient_light_color, AtmosphereVisualBuilderScript.DUSK_HERO_AMBIENT_COLOR, COLOR_TOLERANCE)
	_require_float_close("dusk ambient energy", environment.ambient_light_energy, AtmosphereVisualBuilderScript.DUSK_HERO_AMBIENT_ENERGY, FLOAT_EPSILON)
	if environment.ambient_light_source != Environment.AMBIENT_SOURCE_COLOR:
		_errors.append("dusk mood should use color ambient source")
	_require_color_close("dusk fog light color", environment.fog_light_color, AtmosphereVisualBuilderScript.DUSK_HERO_FOG_LIGHT_COLOR, COLOR_TOLERANCE)
	if environment.volumetric_fog_enabled != GameConfig.resolved_atmosphere_volumetric_fog_enabled():
		_errors.append("atmosphere volumetric fog should follow the render quality tier")
	if environment.volumetric_fog_density <= 0.0:
		_errors.append("atmosphere should configure volumetric fog density")
	if absf(environment.volumetric_fog_anisotropy - GameConfig.resolved_atmosphere_volumetric_fog_anisotropy()) > FLOAT_EPSILON:
		_errors.append("atmosphere volumetric fog anisotropy should follow GameConfig")
	if not environment.glow_enabled:
		_errors.append("atmosphere should enable subtle golden-hour glow")
	if environment.tonemap_mode != Environment.TONE_MAPPER_FILMIC:
		_errors.append("atmosphere should use FILMIC tonemapping")
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
	if not GameConfig.atmosphere_ssao_enabled:
		_errors.append("atmosphere should keep SSAO enabled in GameConfig")
	if not environment.ssao_enabled:
		_errors.append("atmosphere should keep SSAO enabled on the environment")
	if absf(environment.ssao_radius - maxf(GameConfig.resolved_atmosphere_ssao_radius(), 0.0)) > FLOAT_EPSILON:
		_errors.append("atmosphere SSAO radius should follow GameConfig")
	if absf(environment.ssao_intensity - maxf(GameConfig.atmosphere_ssao_intensity, 0.0)) > FLOAT_EPSILON:
		_errors.append("atmosphere SSAO intensity should follow GameConfig")
	if absf(environment.ssao_light_affect - clampf(GameConfig.atmosphere_ssao_light_affect, 0.0, 1.0)) > FLOAT_EPSILON:
		_errors.append("atmosphere SSAO light affect should follow GameConfig")
	if environment.ssil_enabled != GameConfig.resolved_atmosphere_ssil_enabled():
		_errors.append("atmosphere SSIL enabled should follow the render screen-space GI tier")
	if absf(environment.ssil_radius - maxf(GameConfig.resolved_atmosphere_ssil_radius(), 0.0)) > FLOAT_EPSILON:
		_errors.append("atmosphere SSIL radius should follow GameConfig")
	if absf(environment.ssil_intensity - maxf(GameConfig.resolved_atmosphere_ssil_intensity(), 0.0)) > FLOAT_EPSILON:
		_errors.append("atmosphere SSIL intensity should follow GameConfig")
	if absf(environment.ssil_sharpness - clampf(GameConfig.atmosphere_ssil_sharpness, 0.0, 1.0)) > FLOAT_EPSILON:
		_errors.append("atmosphere SSIL sharpness should follow GameConfig")
	if sun == null:
		return
	if not sun.shadow_enabled:
		_errors.append("GoldenHourSun should cast long shadows")
	if sun.rotation_degrees.distance_to(AtmosphereVisualBuilderScript.DUSK_HERO_SUN_ROTATION_DEGREES) > FLOAT_EPSILON:
		_errors.append("GoldenHourSun dusk rotation expected " + str(AtmosphereVisualBuilderScript.DUSK_HERO_SUN_ROTATION_DEGREES) + ", got " + str(sun.rotation_degrees))
	_require_float_close("GoldenHourSun dusk energy", sun.light_energy, GameConfig.dusk_sun_energy, FLOAT_EPSILON)
	_require_color_close("GoldenHourSun dusk color", sun.light_color, AtmosphereVisualBuilderScript.DUSK_HERO_SUN_COLOR, COLOR_TOLERANCE)
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
	if absf(sun.light_volumetric_fog_energy - GameConfig.resolved_atmosphere_sun_volumetric_fog_energy()) > FLOAT_EPSILON:
		_errors.append("GoldenHourSun volumetric fog energy should follow GameConfig")
	if sun.directional_shadow_mode != _expected_directional_shadow_mode():
		_errors.append("GoldenHourSun directional shadow mode should follow GameConfig")
	if sun.directional_shadow_blend_splits:
		_errors.append("GoldenHourSun should not blend shadow splits")


func _inspect_screen_space_gi_tier_guard(world_environment: WorldEnvironment, sun: DirectionalLight3D) -> void:
	if world_environment == null or world_environment.environment == null:
		return
	var environment: Environment = world_environment.environment
	var previous_tier: int = GameConfig.render_screen_space_gi_tier
	GameConfig.render_screen_space_gi_tier = GameConfig.RENDER_SCREEN_SPACE_GI_TIER_LOW
	AtmosphereVisualBuilderScript.apply_mood(world_environment, sun, AtmosphereVisualBuilderScript.MOOD_DUSK)
	if environment.ssil_enabled:
		_errors.append("low screen-space GI tier should disable SSIL")
	if environment.volumetric_fog_enabled:
		_errors.append("low screen-space GI tier should disable volumetric fog")
	if sun != null and sun.light_volumetric_fog_energy > FLOAT_EPSILON:
		_errors.append("low screen-space GI tier should remove sun volumetric fog energy")
	if absf(environment.ssao_radius - maxf(GameConfig.atmosphere_ssao_low_tier_radius, 0.0)) > FLOAT_EPSILON:
		_errors.append("low screen-space GI tier should restore the small SSAO radius")
	GameConfig.render_screen_space_gi_tier = GameConfig.RENDER_SCREEN_SPACE_GI_TIER_HIGH
	AtmosphereVisualBuilderScript.apply_mood(world_environment, sun, AtmosphereVisualBuilderScript.MOOD_DUSK)
	if environment.ssil_enabled != GameConfig.atmosphere_ssil_enabled:
		_errors.append("high screen-space GI tier should honor GameConfig.atmosphere_ssil_enabled")
	if environment.volumetric_fog_enabled != GameConfig.atmosphere_volumetric_fog_enabled:
		_errors.append("high screen-space GI tier should honor GameConfig.atmosphere_volumetric_fog_enabled")
	if sun != null and absf(sun.light_volumetric_fog_energy - GameConfig.atmosphere_sun_volumetric_fog_energy) > FLOAT_EPSILON:
		_errors.append("high screen-space GI tier should restore sun volumetric fog energy")
	if absf(environment.ssao_radius - maxf(GameConfig.atmosphere_ssao_radius, 0.0)) > FLOAT_EPSILON:
		_errors.append("high screen-space GI tier should use the canyon-scale SSAO radius")
	GameConfig.render_screen_space_gi_tier = previous_tier
	AtmosphereVisualBuilderScript.apply_mood(world_environment, sun, AtmosphereVisualBuilderScript.MOOD_DUSK)


func _require_float_close(label: String, actual: float, expected: float, tolerance: float) -> void:
	if absf(actual - expected) > tolerance:
		_errors.append(label + " expected " + str(expected) + ", got " + str(actual))


func _require_color_close(label: String, actual: Color, expected: Color, tolerance: float) -> void:
	if absf(actual.r - expected.r) > tolerance or absf(actual.g - expected.g) > tolerance or absf(actual.b - expected.b) > tolerance or absf(actual.a - expected.a) > tolerance:
		_errors.append(label + " expected " + str(expected) + ", got " + str(actual))


func _expected_directional_shadow_mode() -> int:
	match GameConfig.atmosphere_directional_shadow_mode:
		GameConfig.DIRECTIONAL_SHADOW_ORTHOGONAL:
			return DirectionalLight3D.SHADOW_ORTHOGONAL
		GameConfig.DIRECTIONAL_SHADOW_PARALLEL_2_SPLITS:
			return DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		GameConfig.DIRECTIONAL_SHADOW_PARALLEL_4_SPLITS:
			return DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		_:
			return DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS


func _inspect_viewport_antialiasing() -> void:
	var viewport: Viewport = _scene_root.get_viewport()
	if viewport == null:
		_errors.append("Cedar scene should have a viewport for antialiasing settings")
		return
	if viewport.msaa_3d != GameConfig.render_msaa_3d:
		_errors.append("Cedar viewport MSAA should follow GameConfig.render_msaa_3d")
	if not viewport.use_taa:
		_errors.append("Cedar viewport should enable TAA for SSAO/SSIL")
	var soft_shadow_quality: int = int(ProjectSettings.get_setting(SOFT_SHADOW_FILTER_QUALITY_SETTING_PATH, -1))
	if soft_shadow_quality != EXPECTED_SOFT_SHADOW_FILTER_QUALITY:
		_errors.append("Cedar project " + SOFT_SHADOW_FILTER_QUALITY_SETTING_PATH + " expected " + str(EXPECTED_SOFT_SHADOW_FILTER_QUALITY) + ", got " + str(soft_shadow_quality))
	var volumetric_fog_volume_size: int = int(ProjectSettings.get_setting(VOLUMETRIC_FOG_VOLUME_SIZE_SETTING_PATH, -1))
	if volumetric_fog_volume_size != EXPECTED_VOLUMETRIC_FOG_VOLUME_SIZE:
		_errors.append("Cedar project " + VOLUMETRIC_FOG_VOLUME_SIZE_SETTING_PATH + " expected " + str(EXPECTED_VOLUMETRIC_FOG_VOLUME_SIZE) + ", got " + str(volumetric_fog_volume_size))
	var volumetric_fog_volume_depth: int = int(ProjectSettings.get_setting(VOLUMETRIC_FOG_VOLUME_DEPTH_SETTING_PATH, -1))
	if volumetric_fog_volume_depth != EXPECTED_VOLUMETRIC_FOG_VOLUME_DEPTH:
		_errors.append("Cedar project " + VOLUMETRIC_FOG_VOLUME_DEPTH_SETTING_PATH + " expected " + str(EXPECTED_VOLUMETRIC_FOG_VOLUME_DEPTH) + ", got " + str(volumetric_fog_volume_depth))
	var volumetric_fog_use_filter: int = int(ProjectSettings.get_setting(VOLUMETRIC_FOG_USE_FILTER_SETTING_PATH, -1))
	if volumetric_fog_use_filter != EXPECTED_VOLUMETRIC_FOG_USE_FILTER:
		_errors.append("Cedar project " + VOLUMETRIC_FOG_USE_FILTER_SETTING_PATH + " expected " + str(EXPECTED_VOLUMETRIC_FOG_USE_FILTER) + ", got " + str(volumetric_fog_use_filter))


func _inspect_mood_toggle(world_environment: WorldEnvironment, sun: DirectionalLight3D) -> void:
	if world_environment == null or world_environment.environment == null:
		return
	var environment: Environment = world_environment.environment
	_require_dusk_golden_sky_environment(environment, sun, "dusk")
	_scene_root.call("toggle_mood")
	_require_physical_sky_environment(environment, "dawn")
	if environment.fog_light_color != GameConfig.dawn_fog_light_color:
		_errors.append("dawn mood fog light color should remain GameConfig-driven")
	if environment.fog_height_density <= 0.0:
		_errors.append("dawn mood should keep height fog")
	if not environment.volumetric_fog_enabled:
		_errors.append("dawn mood should keep volumetric fog")
	_scene_root.call("toggle_mood")
	_require_night_sky_environment(environment)
	_require_color_close("night ambient color", environment.ambient_light_color, AtmosphereVisualBuilderScript.NIGHT_AMBIENT_COLOR, COLOR_TOLERANCE)
	_require_float_close("night ambient energy", environment.ambient_light_energy, AtmosphereVisualBuilderScript.NIGHT_AMBIENT_ENERGY, FLOAT_EPSILON)
	_require_color_close("night fog light color", environment.fog_light_color, AtmosphereVisualBuilderScript.NIGHT_FOG_LIGHT_COLOR, COLOR_TOLERANCE)
	_scene_root.call("toggle_mood")
	_require_dusk_golden_sky_environment(environment, sun, "dusk restore")


func _require_physical_sky_environment(environment: Environment, label: String) -> void:
	if environment.background_mode != Environment.BG_SKY:
		_errors.append(label + " mood should use sky background mode")
	if environment.ambient_light_source != Environment.AMBIENT_SOURCE_BG:
		_errors.append(label + " mood should use sky ambient source")
	if environment.sky == null:
		_errors.append(label + " mood should assign a Sky resource")
	elif not (environment.sky.sky_material is PhysicalSkyMaterial):
		_errors.append(label + " mood should use PhysicalSkyMaterial")


func _require_night_sky_environment(environment: Environment) -> void:
	if environment.background_mode != Environment.BG_SKY:
		_errors.append("night mood should use sky background mode")
	if environment.ambient_light_source != Environment.AMBIENT_SOURCE_BG:
		_errors.append("night mood should use sky ambient source")
	if environment.sky == null:
		_errors.append("night mood should assign a Sky resource")
	elif not (environment.sky.sky_material is ShaderMaterial):
		_errors.append("night mood should use ShaderMaterial star sky")


func _require_dusk_golden_sky_environment(environment: Environment, sun: DirectionalLight3D, label: String) -> void:
	# zionfid/sky: dusk now uses the golden-hour ShaderMaterial sky instead of a
	# PhysicalSkyMaterial. This asserts the contract headlessly: the right shader
	# is attached, the blue zenith is preserved (de-orange invariant), and the
	# sun disk/halo is placed at the real GoldenHourSun direction (the one thing
	# a PhysicalSkyMaterial got for free). The sun direction is derived the same
	# way the host derives it (light basis.z), so a mismatch proves a wiring bug.
	if environment.background_mode != Environment.BG_SKY:
		_errors.append(label + " mood should use sky background mode")
	if environment.ambient_light_source != Environment.AMBIENT_SOURCE_COLOR:
		_errors.append(label + " mood should use color ambient source")
	if environment.sky == null:
		_errors.append(label + " mood should assign a Sky resource")
		return
	var sky_material: ShaderMaterial = environment.sky.sky_material as ShaderMaterial
	if sky_material == null:
		_errors.append(label + " mood should use the dusk golden sky ShaderMaterial")
		return
	if sky_material.shader == null or sky_material.shader.resource_path != DUSK_GOLDEN_SKY_SHADER_PATH:
		_errors.append(label + " mood sky shader expected " + DUSK_GOLDEN_SKY_SHADER_PATH + ", got " + (sky_material.shader.resource_path if sky_material.shader != null else "<null>"))
	var zenith: Vector3 = sky_material.get_shader_parameter("zenith_color") as Vector3
	if zenith.z <= zenith.x:
		_errors.append(label + " mood sky zenith must stay blue (de-orange): " + str(zenith))
	if sun != null:
		var expected_sun_dir: Vector3 = sun.global_transform.basis.z.normalized()
		var actual_sun_dir: Vector3 = sky_material.get_shader_parameter("sun_direction") as Vector3
		if expected_sun_dir.distance_to(actual_sun_dir) > FLOAT_EPSILON:
			_errors.append(label + " mood sky sun_direction expected " + str(expected_sun_dir) + ", got " + str(actual_sun_dir))
		if actual_sun_dir.y <= 0.0:
			_errors.append(label + " mood sky sun should sit above the horizon, got y=" + str(actual_sun_dir.y))


func _inspect_dust_and_tilt_shift() -> void:
	_require_node(_scene_root, "DustTiltShiftVisuals")
	var chase_camera: Camera3D = _require_node(_scene_root, "ChaseCamera") as Camera3D
	var orbit_camera: Camera3D = _require_node(_scene_root, "OrbitCamera") as Camera3D
	var fpv_camera: Camera3D = _require_node(_scene_root, "FpvCamera") as Camera3D
	_inspect_camera_far_planes(chase_camera, orbit_camera, fpv_camera)
	if chase_camera != null:
		var expected_count: int = DustTiltShiftVisualBuilderScript.dust_mote_effective_count()
		if expected_count > 0:
			var dust: GPUParticles3D = _require_node(chase_camera, DustTiltShiftVisualBuilderScript.DUST_FIELD_NAME) as GPUParticles3D
			_inspect_dust_field(dust)
		else:
			var disabled_dust: Node = chase_camera.get_node_or_null(DustTiltShiftVisualBuilderScript.DUST_FIELD_NAME)
			if disabled_dust != null:
				_errors.append("DustMoteField should be absent when the effective mote count is 0")
	_inspect_tilt_shift_layer()
	_inspect_tilt_shift_camera(chase_camera, "ChaseCamera")
	_inspect_tilt_shift_camera(orbit_camera, "OrbitCamera")
	_inspect_tilt_shift_camera(fpv_camera, "FpvCamera")


func _inspect_dust_field(dust: GPUParticles3D) -> void:
	if dust == null:
		return
	if not dust.emitting:
		_errors.append("DustMoteField should emit")
	var expected_count: int = DustTiltShiftVisualBuilderScript.dust_mote_effective_count()
	if dust.amount != expected_count:
		_errors.append("DustMoteField amount expected " + str(expected_count) + ", got " + str(dust.amount))
	if dust.amount < DUST_MOTE_COUNT_FLOOR:
		_errors.append("DustMoteField should have particles")
	if not dust.use_fixed_seed:
		_errors.append("DustMoteField should use a fixed seed")
	if dust.randomness > FLOAT_EPSILON:
		_errors.append("DustMoteField should avoid particle randomness")
	var expected_fixed_fps: int = maxi(GameConfig.dust_mote_fixed_fps, 1)
	if dust.fixed_fps != expected_fixed_fps:
		_errors.append("DustMoteField fixed_fps expected " + str(expected_fixed_fps) + ", got " + str(dust.fixed_fps))
	if absf(dust.visibility_range_end - GameConfig.vis_range_dust) > FLOAT_EPSILON:
		_errors.append("DustMoteField visibility range should follow GameConfig")
	var process_material: ParticleProcessMaterial = dust.process_material as ParticleProcessMaterial
	if process_material == null:
		_errors.append("DustMoteField should use ParticleProcessMaterial")
		return
	if process_material.emission_shape != ParticleProcessMaterial.EMISSION_SHAPE_BOX:
		_errors.append("DustMoteField should use a box field around the camera")
	_require_float_close("DustMoteField alpha", process_material.color.a, clampf(GameConfig.dust_mote_alpha, 0.0, 1.0), FLOAT_EPSILON)


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
	if GameConfig.vehicle_surface_burst_enabled:
		_require_surface_burst(juice_rig, "DustSurfaceBurst")
		_require_surface_burst(juice_rig, "MudSurfaceBurst")
		_require_surface_burst(juice_rig, "WaterSurfaceBurst")
	_inspect_vehicle_debris_particles(juice_rig)
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
	_inspect_driven_vehicle_juice_emitters()


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
	_require_soft_dust_draw_material(burst, 0, path + " draw_pass_1")


func _inspect_vehicle_debris_particles(juice_rig: Node) -> void:
	_inspect_wheel_dust_particles(juice_rig)
	_inspect_wheel_dust_quality_tiers()
	for rear_slot in range(REAR_ROOSTER_COUNT):
		var rooster_name: String = "RearRoosterDebris" + str(rear_slot)
		var rooster: GPUParticles3D = _require_node(juice_rig, rooster_name) as GPUParticles3D
		if rooster == null:
			continue
		if rooster.draw_passes != 2:
			_errors.append(rooster_name + " should keep dust + pebble draw passes")
		_require_soft_dust_draw_material(rooster, 0, rooster_name + " draw_pass_1")
		_require_pebble_draw_mesh(rooster, 1, rooster_name + " draw_pass_2")
	for wheel_index in range(VEHICLE_WHEEL_COUNT):
		var burst_name: String = "PebbleScatterBurst" + str(wheel_index)
		var burst: GPUParticles3D = _require_node(juice_rig, burst_name) as GPUParticles3D
		if burst == null:
			continue
		_require_pebble_draw_mesh(burst, 0, burst_name + " draw_pass_1")
		var ring_name: String = "LandingDustRing" + str(wheel_index)
		var ring: GPUParticles3D = _require_node(juice_rig, ring_name) as GPUParticles3D
		if ring == null:
			continue
		_require_soft_dust_draw_material(ring, 0, ring_name + " draw_pass_1")


func _inspect_wheel_dust_particles(juice_rig: Node) -> void:
	for wheel_index in range(VEHICLE_WHEEL_COUNT):
		var dust_name: String = "WheelDust" + str(wheel_index)
		var dust: GPUParticles3D = _require_node(juice_rig, dust_name) as GPUParticles3D
		if dust == null:
			continue
		if dust.amount != GameConfig.resolved_wheel_dust_particles_per_wheel():
			_errors.append(dust_name + " should use resolved GameConfig wheel dust particle count")
		if absf(dust.lifetime - GameConfig.resolved_wheel_dust_lifetime()) > FLOAT_EPSILON:
			_errors.append(dust_name + " should use resolved GameConfig wheel dust lifetime")
		if dust.local_coords:
			_errors.append(dust_name + " should leave particles in world space for a trailing plume")
		if not dust.use_fixed_seed:
			_errors.append(dust_name + " should use a fixed seed")
		if dust.randomness > FLOAT_EPSILON:
			_errors.append(dust_name + " should avoid particle randomness")
		if absf(dust.visibility_range_end - GameConfig.vis_range_dust) > FLOAT_EPSILON:
			_errors.append(dust_name + " visibility range should follow GameConfig")
		if dust.get_meta("visual_contract", "") != "deterministic_wheel_dust":
			_errors.append(dust_name + " should declare deterministic wheel dust contract")
		var process_material: ParticleProcessMaterial = dust.process_material as ParticleProcessMaterial
		if process_material == null:
			_errors.append(dust_name + " should use ParticleProcessMaterial")
		else:
			if absf(process_material.emission_sphere_radius - GameConfig.resolved_wheel_dust_emission_radius()) > FLOAT_EPSILON:
				_errors.append(dust_name + " should use resolved GameConfig wheel dust emission radius")
			if process_material.color_ramp == null:
				_errors.append(dust_name + " should use a lifetime color ramp for tight alpha fade")
		var mesh: Mesh = dust.get_draw_pass_mesh(0) as Mesh
		if _particle_draw_material(mesh) == null:
			_errors.append(dust_name + " should have a materialized dust draw pass")
		_require_soft_dust_draw_material(dust, 0, dust_name + " draw_pass_1")


func _inspect_wheel_dust_quality_tiers() -> void:
	var original_tier: int = GameConfig.wheel_dust_quality_tier
	var fake_vehicle: FakeJuiceVehicle = FakeJuiceVehicle.new()
	fake_vehicle.name = "WheelDustTierFakeVehicle"
	add_child(fake_vehicle)
	GameConfig.wheel_dust_quality_tier = GameConfig.WHEEL_DUST_TIER_LOW
	var low_rig: VehicleJuiceRig = VehicleJuiceRig.new()
	low_rig.name = "LowTierWheelDustRig"
	add_child(low_rig)
	low_rig.configure(fake_vehicle, null, null)
	_require_wheel_dust_preset(
		low_rig,
		GameConfig.wheel_dust_particles_per_wheel,
		GameConfig.wheel_dust_lifetime,
		GameConfig.wheel_dust_emission_radius,
		"low-tier"
	)
	low_rig.queue_free()
	GameConfig.wheel_dust_quality_tier = GameConfig.WHEEL_DUST_TIER_HIGH
	var high_rig: VehicleJuiceRig = VehicleJuiceRig.new()
	high_rig.name = "HighTierWheelDustRig"
	add_child(high_rig)
	high_rig.configure(fake_vehicle, null, null)
	_require_wheel_dust_preset(
		high_rig,
		GameConfig.wheel_dust_particles_per_wheel_high_tier,
		GameConfig.wheel_dust_lifetime_high_tier,
		GameConfig.wheel_dust_emission_radius_high_tier,
		"high-tier"
	)
	high_rig.queue_free()
	fake_vehicle.queue_free()
	GameConfig.wheel_dust_quality_tier = original_tier


func _require_wheel_dust_preset(rig: Node, expected_amount: int, expected_lifetime: float, expected_radius: float, context: String) -> void:
	var dust: GPUParticles3D = rig.get_node_or_null("WheelDust0") as GPUParticles3D
	if dust == null:
		_errors.append(context + " wheel dust should create an emitter")
		return
	if dust.amount != expected_amount:
		_errors.append(context + " wheel dust amount expected " + str(expected_amount) + ", got " + str(dust.amount))
	if absf(dust.lifetime - expected_lifetime) > FLOAT_EPSILON:
		_errors.append(context + " wheel dust lifetime expected " + str(expected_lifetime) + ", got " + str(dust.lifetime))
	var process_material: ParticleProcessMaterial = dust.process_material as ParticleProcessMaterial
	if process_material == null:
		_errors.append(context + " wheel dust should use ParticleProcessMaterial")
		return
	if absf(process_material.emission_sphere_radius - expected_radius) > FLOAT_EPSILON:
		_errors.append(context + " wheel dust emission radius expected " + str(expected_radius) + ", got " + str(process_material.emission_sphere_radius))


func _inspect_driven_vehicle_juice_emitters() -> void:
	var fake_vehicle: FakeJuiceVehicle = FakeJuiceVehicle.new()
	fake_vehicle.name = "DrivenJuiceFakeVehicle"
	fake_vehicle.state.position = Vector3(3.0, 0.0, -9.0)
	fake_vehicle.state.linear_velocity = Vector3(1.2, 0.0, -GameConfig.cam_drive_chatter_speed_full)
	var camera: Camera3D = Camera3D.new()
	camera.name = "DrivenJuiceCamera"
	var rig: VehicleJuiceRig = VehicleJuiceRig.new()
	rig.name = "DrivenVehicleJuiceRig"
	add_child(fake_vehicle)
	add_child(camera)
	add_child(rig)
	rig.configure(fake_vehicle, camera, null)
	rig.call("debug_trigger_dust_kick")
	rig.call("_process", GameConfig.FIXED_DT)
	if absf(camera.h_offset) <= FLOAT_EPSILON and absf(camera.v_offset) <= FLOAT_EPSILON:
		_errors.append("driven VehicleJuiceRig should apply speed/surface camera chatter")
	for wheel_index in range(VEHICLE_WHEEL_COUNT):
		var dust_name: String = "WheelDust" + str(wheel_index)
		var dust: GPUParticles3D = rig.get_node_or_null(dust_name) as GPUParticles3D
		if dust == null:
			_errors.append("driven " + dust_name + " should exist")
			continue
		if not dust.emitting:
			_errors.append("driven " + dust_name + " should emit from contacted moving wheels")
		if dust.amount_ratio <= ACTIVE_PARTICLE_RATIO_FLOOR:
			_errors.append("driven " + dust_name + " should have a nonzero amount_ratio, got " + str(dust.amount_ratio))
		_require_particle_not_bare_white(dust, dust_name)
	for rear_slot in range(REAR_ROOSTER_COUNT):
		var rooster_name: String = "RearRoosterDebris" + str(rear_slot)
		var rooster: GPUParticles3D = rig.get_node_or_null(rooster_name) as GPUParticles3D
		if rooster == null:
			_errors.append("driven " + rooster_name + " should exist")
			continue
		if not rooster.emitting:
			_errors.append("driven " + rooster_name + " should emit under hard drive")
		if rooster.amount_ratio <= ACTIVE_PARTICLE_RATIO_FLOOR:
			_errors.append("driven " + rooster_name + " should have a nonzero amount_ratio, got " + str(rooster.amount_ratio))
		_require_particle_not_bare_white(rooster, rooster_name)
	if GameConfig.vehicle_surface_burst_enabled:
		rig.call("debug_trigger_surface_burst", &"loose_rock", fake_vehicle.state.position, GameConfig.surface_burst_speed_threshold * 2.0)
		var dust_burst: GPUParticles3D = rig.get_node_or_null("DustSurfaceBurst") as GPUParticles3D
		if dust_burst == null:
			_errors.append("driven DustSurfaceBurst should exist when surface bursts are enabled")
		else:
			if not dust_burst.emitting:
				_errors.append("driven DustSurfaceBurst should emit for contacted loose_rock rear wheels")
			var expected_burst_position: Vector3 = Vector3(0.0, 0.035, 0.42)
			if dust_burst.global_position.distance_to(expected_burst_position) > 0.025:
				_errors.append("driven DustSurfaceBurst should spawn from rear wheel contacts, got " + str(dust_burst.global_position))
			_require_soft_dust_draw_material(dust_burst, 0, "driven DustSurfaceBurst draw_pass_1")
	fake_vehicle.state.linear_velocity = Vector3.ZERO
	rig.call("_process", GameConfig.FIXED_DT)
	if absf(camera.h_offset) > FLOAT_EPSILON or absf(camera.v_offset) > FLOAT_EPSILON:
		_errors.append("driven VehicleJuiceRig should clear camera chatter when speed drops to zero")
	rig.queue_free()
	camera.queue_free()
	fake_vehicle.queue_free()


func _require_particle_not_bare_white(particles: GPUParticles3D, context: String) -> void:
	var process_material: ParticleProcessMaterial = particles.process_material as ParticleProcessMaterial
	if process_material == null:
		_errors.append(context + " should have a ParticleProcessMaterial")
		return
	var color: Color = process_material.color
	if color.r >= BARE_WHITE_CHANNEL and color.g >= BARE_WHITE_CHANNEL and color.b >= BARE_WHITE_CHANNEL:
		_errors.append(context + " should tint particles from the contacted surface")


func _require_soft_dust_draw_material(particles: GPUParticles3D, pass_index: int, context: String) -> void:
	var mesh: Mesh = particles.get_draw_pass_mesh(pass_index) as Mesh
	var material: StandardMaterial3D = _particle_draw_material(mesh)
	if material == null:
		_errors.append(context + " should have a StandardMaterial3D soft dust material")
		return
	if not bool(material.get_meta(SOFT_DUST_MATERIAL_META, false)):
		_errors.append(context + " should use the tagged soft radial dust material")
	if material.albedo_texture == null:
		_errors.append(context + " should use a soft alpha texture instead of a hard-edged quad")
	if not material.vertex_color_use_as_albedo:
		_errors.append(context + " should use particle vertex color for lifetime fade/tint")
	if material.transparency != BaseMaterial3D.TRANSPARENCY_ALPHA:
		_errors.append(context + " should render as alpha-blended dust")
	if material.billboard_mode != BaseMaterial3D.BILLBOARD_ENABLED:
		_errors.append(context + " should stay billboarded toward the camera")


func _require_pebble_draw_mesh(particles: GPUParticles3D, pass_index: int, context: String) -> void:
	var mesh: Mesh = particles.get_draw_pass_mesh(pass_index) as Mesh
	if mesh == null:
		_errors.append(context + " should have a pebble draw mesh")
		return
	if mesh is BoxMesh:
		_errors.append(context + " should not use BoxMesh; box particles render as cube artifacts")
	var aabb: AABB = mesh.get_aabb()
	var max_extent: float = maxf(maxf(aabb.size.x, aabb.size.y), aabb.size.z)
	if max_extent > PEBBLE_DRAW_MESH_MAX_EXTENT:
		_errors.append(context + " pebble mesh is too large: " + str(max_extent))
	var material: StandardMaterial3D = _particle_draw_material(mesh)
	if material == null:
		_errors.append(context + " should have a StandardMaterial3D")
		return
	if not bool(material.get_meta(PEBBLE_MATERIAL_META, false)):
		_errors.append(context + " should use the tagged vehicle pebble material")
	if material.albedo_color.r >= BARE_WHITE_CHANNEL and material.albedo_color.g >= BARE_WHITE_CHANNEL and material.albedo_color.b >= BARE_WHITE_CHANNEL:
		_errors.append(context + " should not render with a bare white material")
	if material.albedo_color.a < 1.0 - FLOAT_EPSILON:
		_errors.append(context + " should render as solid dirt/pebble material, not translucent dust")


func _particle_draw_material(mesh: Mesh) -> StandardMaterial3D:
	if mesh == null:
		return null
	if mesh.get_surface_count() > 0:
		var surface_material: StandardMaterial3D = mesh.surface_get_material(0) as StandardMaterial3D
		if surface_material != null:
			return surface_material
	var primitive_mesh: PrimitiveMesh = mesh as PrimitiveMesh
	if primitive_mesh != null:
		return primitive_mesh.material as StandardMaterial3D
	return null


func _inspect_water_visuals() -> void:
	var water_root: Node = _scene_root.get_node_or_null("CedarHollow/WaterVisuals")
	if water_root == null:
		_errors.append("missing node CedarHollow/WaterVisuals")
		return
	var water_count: int = 0
	for child in water_root.get_children():
		var water: MeshInstance3D = child as MeshInstance3D
		if water == null:
			continue
		water_count += 1
		_inspect_water_surface(water)
	if _is_streamed_zion_host():
		if water_count != ZION_WATER_SURFACE_COUNT:
			_errors.append("Zion WaterVisuals expected " + str(ZION_WATER_SURFACE_COUNT) + " water surfaces, got " + str(water_count))
		_require_node(water_root, "virgin_river_west")
		_require_node(water_root, "virgin_river_east")
		return
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
	_require_shader_int(material, "ssr_max_steps", WaterVisualBuilderScript.water_ssr_effective_max_steps(), String(water.name))
	_require_shader_float(material, "ssr_intensity", WaterVisualBuilderScript.water_ssr_effective_intensity(), String(water.name))
	_require_shader_float(material, "ssr_step_size", GameConfig.water_ssr_step_size, String(water.name))
	_require_shader_float(material, "ssr_thickness", GameConfig.water_ssr_thickness, String(water.name))
	_require_shader_float(material, "water_roughness", GameConfig.water_roughness, String(water.name))
	_require_shader_color(material, "ssr_sky_fallback_color", WaterVisualBuilderScript.SSR_SKY_FALLBACK_COLOR, String(water.name))
	_require_shader_float(material, "ssr_sky_fallback_strength", WaterVisualBuilderScript.SSR_SKY_FALLBACK_STRENGTH, String(water.name))


func _is_streamed_zion_host() -> bool:
	if _scene_root == null:
		return false
	var world: Node = _scene_root.get_node_or_null("CedarHollow")
	if world == null or not world.has_meta(WORLD_REGION_ID_META):
		return false
	return String(world.get_meta(WORLD_REGION_ID_META)) == ZION_REGION_ID


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
