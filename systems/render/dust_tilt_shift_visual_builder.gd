class_name DustTiltShiftVisualBuilder
extends RefCounted

const ROOT_NAME: String = "DustTiltShiftVisuals"
const DUST_FIELD_NAME: String = "DustMoteField"
const TILT_SHIFT_LAYER_NAME: String = "TiltShiftLayer"
const TILT_SHIFT_RECT_NAME: String = "TiltShiftOverlay"
const TiltShiftShader: Shader = preload("res://systems/render/tilt_shift.gdshader")
const DUST_FIXED_SEED: int = 424242
const DUST_LIFETIME: float = 9.0
const DUST_PREPROCESS: float = 9.0
const DUST_SCALE: float = 0.0078
const DUST_DRIFT_DIRECTION_FALLBACK: Vector3 = Vector3(0.24, 0.05, -0.18)


static func build(parent: Node3D, chase_camera: Camera3D, orbit_camera: Camera3D, fpv_camera: Camera3D) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = ROOT_NAME
	parent.add_child(root)
	var dust_count: int = dust_mote_effective_count()
	if chase_camera != null and dust_count > 0:
		chase_camera.add_child(_make_dust_field(dust_count))
	_ensure_tilt_shift_layer(parent)
	_apply_tilt_shift(chase_camera)
	_apply_tilt_shift(orbit_camera)
	_apply_tilt_shift(fpv_camera)
	return root


static func dust_mote_effective_count() -> int:
	var base_count: int = maxi(GameConfig.dust_mote_count, 0)
	if base_count <= 0:
		return 0
	var tier: int = mini(maxi(GameConfig.dust_mote_quality_tier, GameConfig.DUST_MOTE_TIER_OFF), GameConfig.DUST_MOTE_TIER_HIGH)
	if tier <= GameConfig.DUST_MOTE_TIER_OFF:
		return 0
	if tier == GameConfig.DUST_MOTE_TIER_LOW:
		return mini(maxi(GameConfig.dust_mote_count_low_tier, 0), base_count)
	if tier == GameConfig.DUST_MOTE_TIER_MEDIUM:
		return mini(maxi(GameConfig.dust_mote_count_medium_tier, 0), base_count)
	return base_count


static func _make_dust_field(dust_count: int) -> GPUParticles3D:
	var particles: GPUParticles3D = GPUParticles3D.new()
	particles.name = DUST_FIELD_NAME
	particles.amount = maxi(dust_count, 0)
	particles.lifetime = DUST_LIFETIME
	particles.preprocess = DUST_PREPROCESS
	particles.emitting = true
	particles.use_fixed_seed = true
	particles.seed = DUST_FIXED_SEED
	particles.randomness = 0.0
	particles.fixed_fps = maxi(GameConfig.dust_mote_fixed_fps, 1)
	particles.draw_pass_1 = _dust_mesh()
	particles.process_material = _dust_process_material()
	particles.position = Vector3(0.0, 0.0, -1.6)
	particles.visibility_range_end = GameConfig.vis_range_dust
	particles.set_meta("visual_contract", "deterministic_dust_motes")
	return particles


static func _dust_process_material() -> ParticleProcessMaterial:
	var material: ParticleProcessMaterial = ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	material.emission_box_extents = GameConfig.dust_mote_field_size
	material.gravity = Vector3(0.0, 0.002, 0.0)
	var drift_direction: Vector3 = GameConfig.dust_mote_drift_direction
	if drift_direction.length_squared() <= 0.000001:
		drift_direction = DUST_DRIFT_DIRECTION_FALLBACK
	material.direction = drift_direction.normalized()
	material.initial_velocity_min = GameConfig.dust_mote_drift_speed * 0.45
	material.initial_velocity_max = GameConfig.dust_mote_drift_speed
	material.damping_min = 0.02
	material.damping_max = 0.04
	material.scale_min = DUST_SCALE * 0.55
	material.scale_max = DUST_SCALE
	material.color = Color(1.0, 0.88, 0.68, clampf(GameConfig.dust_mote_alpha, 0.0, 1.0))
	return material


static func _dust_mesh() -> QuadMesh:
	var mesh: QuadMesh = QuadMesh.new()
	mesh.size = Vector2(DUST_SCALE, DUST_SCALE)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.resource_name = "dust_mote_billboard_material"
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.88, 0.68, clampf(GameConfig.dust_mote_alpha, 0.0, 1.0))
	mesh.material = material
	return mesh


static func _apply_tilt_shift(camera: Camera3D) -> void:
	if camera == null:
		return
	camera.set_meta("tilt_shift_gradient_axis", Vector2(0.0, 1.0))
	camera.set_meta("tilt_shift_focus_band", clampf(GameConfig.tilt_shift_focus_band, 0.0, 0.5))
	camera.set_meta("tilt_shift_screen_layer", TILT_SHIFT_LAYER_NAME)


static func _ensure_tilt_shift_layer(parent: Node) -> CanvasLayer:
	var existing_layer: CanvasLayer = parent.get_node_or_null(TILT_SHIFT_LAYER_NAME) as CanvasLayer
	if existing_layer != null:
		_configure_tilt_shift_layer(existing_layer)
		return existing_layer
	var layer: CanvasLayer = CanvasLayer.new()
	layer.name = TILT_SHIFT_LAYER_NAME
	layer.layer = 2
	parent.add_child(layer)
	_configure_tilt_shift_layer(layer)
	return layer


static func _configure_tilt_shift_layer(layer: CanvasLayer) -> void:
	layer.visible = GameConfig.tilt_shift_enabled
	var overlay: ColorRect = layer.get_node_or_null(TILT_SHIFT_RECT_NAME) as ColorRect
	if overlay == null:
		overlay = ColorRect.new()
		overlay.name = TILT_SHIFT_RECT_NAME
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay.anchor_left = 0.0
		overlay.anchor_top = 0.0
		overlay.anchor_right = 1.0
		overlay.anchor_bottom = 1.0
		overlay.offset_left = 0.0
		overlay.offset_top = 0.0
		overlay.offset_right = 0.0
		overlay.offset_bottom = 0.0
		layer.add_child(overlay)
	var material: ShaderMaterial = overlay.material as ShaderMaterial
	if material == null:
		material = ShaderMaterial.new()
		overlay.material = material
	material.shader = TiltShiftShader
	# Track D V1: these parameters are the headless contract for the screen-space miniature band.
	material.set_shader_parameter("center", clampf(GameConfig.tilt_shift_band_center, 0.0, 1.0))
	material.set_shader_parameter("band", clampf(GameConfig.tilt_shift_focus_band, 0.0, 0.5))
	material.set_shader_parameter("blur", maxf(GameConfig.tilt_shift_blur_amount, 0.0))
