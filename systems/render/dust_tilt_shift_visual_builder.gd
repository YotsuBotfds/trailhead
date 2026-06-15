class_name DustTiltShiftVisualBuilder
extends RefCounted

const ROOT_NAME: String = "DustTiltShiftVisuals"
const DUST_FIELD_NAME: String = "DustMoteField"
const DUST_FIXED_SEED: int = 424242
const DUST_LIFETIME: float = 9.0
const DUST_PREPROCESS: float = 9.0
const DUST_SCALE: float = 0.006
const DUST_ALPHA: float = 0.30
const CAMERA_NEAR_DOF_DISTANCE: float = 0.20
const CAMERA_FAR_DOF_DISTANCE: float = 1.55
const CAMERA_DOF_TRANSITION_SCALE: float = 1.25


static func build(parent: Node3D, chase_camera: Camera3D, orbit_camera: Camera3D, fpv_camera: Camera3D) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = ROOT_NAME
	parent.add_child(root)
	if chase_camera != null:
		chase_camera.add_child(_make_dust_field())
	_apply_tilt_shift(chase_camera)
	_apply_tilt_shift(orbit_camera)
	_apply_tilt_shift(fpv_camera)
	return root


static func _make_dust_field() -> GPUParticles3D:
	var particles: GPUParticles3D = GPUParticles3D.new()
	particles.name = DUST_FIELD_NAME
	particles.amount = maxi(GameConfig.dust_mote_count, 0)
	particles.lifetime = DUST_LIFETIME
	particles.preprocess = DUST_PREPROCESS
	particles.emitting = true
	particles.use_fixed_seed = true
	particles.seed = DUST_FIXED_SEED
	particles.randomness = 0.0
	particles.fixed_fps = 30
	particles.draw_pass_1 = _dust_mesh()
	particles.process_material = _dust_process_material()
	particles.position = Vector3(0.0, 0.0, -1.6)
	particles.set_meta("visual_contract", "deterministic_dust_motes")
	return particles


static func _dust_process_material() -> ParticleProcessMaterial:
	var material: ParticleProcessMaterial = ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	material.emission_box_extents = GameConfig.dust_mote_field_size
	material.gravity = Vector3(0.0, 0.002, 0.0)
	material.direction = Vector3(0.18, 0.04, -0.10).normalized()
	material.initial_velocity_min = GameConfig.dust_mote_drift_speed * 0.45
	material.initial_velocity_max = GameConfig.dust_mote_drift_speed
	material.damping_min = 0.02
	material.damping_max = 0.04
	material.scale_min = DUST_SCALE * 0.55
	material.scale_max = DUST_SCALE
	material.color = Color(1.0, 0.88, 0.68, DUST_ALPHA)
	return material


static func _dust_mesh() -> QuadMesh:
	var mesh: QuadMesh = QuadMesh.new()
	mesh.size = Vector2(DUST_SCALE, DUST_SCALE)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.resource_name = "dust_mote_billboard_material"
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.88, 0.68, DUST_ALPHA)
	mesh.material = material
	return mesh


static func _apply_tilt_shift(camera: Camera3D) -> void:
	if camera == null:
		return
	var attributes: CameraAttributesPractical = camera.attributes as CameraAttributesPractical
	if attributes == null:
		attributes = CameraAttributesPractical.new()
		camera.attributes = attributes
	var blur_amount: float = maxf(GameConfig.tilt_shift_blur_amount, 0.0)
	var focus_band: float = clampf(GameConfig.tilt_shift_focus_band, 0.1, 0.9)
	var softness: float = maxf(GameConfig.tilt_shift_gradient_softness, 0.1)
	attributes.dof_blur_near_enabled = true
	attributes.dof_blur_far_enabled = true
	attributes.dof_blur_amount = blur_amount
	attributes.dof_blur_near_distance = CAMERA_NEAR_DOF_DISTANCE + focus_band * 0.18
	attributes.dof_blur_far_distance = CAMERA_FAR_DOF_DISTANCE + focus_band * 0.45
	attributes.dof_blur_near_transition = softness * CAMERA_DOF_TRANSITION_SCALE
	attributes.dof_blur_far_transition = softness * CAMERA_DOF_TRANSITION_SCALE
	camera.set_meta("tilt_shift_gradient_axis", Vector2(0.0, 1.0))
	camera.set_meta("tilt_shift_focus_band", focus_band)
