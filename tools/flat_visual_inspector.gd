extends Node

const FlatPlaneScene: PackedScene = preload("res://scenes/flat_plane.tscn")
const FLOAT_EPSILON: float = 0.001
const CAMERA_COMPOSITION_TOLERANCE: float = 0.01
const CAMERA_PITCH_TOLERANCE_DEG: float = 0.25
const TILT_SHIFT_SHADER_PATH: String = "res://systems/render/tilt_shift.gdshader"
const TILT_SHIFT_LAYER_NAME: String = "TiltShiftLayer"
const TILT_SHIFT_RECT_NAME: String = "TiltShiftOverlay"
const TILT_SHIFT_LAYER_INDEX: int = 2
const EXPECTED_FOV_MIN: float = 68.0
const EXPECTED_FOV_MAX: float = 80.0
const RESIDUE_SHADER_PATH: String = "res://systems/render/vehicle_contamination_visual.gdshader"
const RESIDUE_BODY_OVERLAY: String = "body/residue_body_contamination_overlay"
const RESIDUE_NOSE_OVERLAY: String = "nose/residue_body_contamination_overlay"
const RESIDUE_TIRE_OVERLAY: String = "residue_tire_contamination_overlay"
const RESIDUE_MUD_BODY_MASK: String = "res://assets/textures/vehicle/residue/mud_body_mask.png"
const RESIDUE_DUST_BODY_MASK: String = "res://assets/textures/vehicle/residue/dust_body_mask.png"
const RESIDUE_WETNESS_BODY_MASK: String = "res://assets/textures/vehicle/residue/wetness_body_mask.png"
const RESIDUE_MUD_TIRE_MASK: String = "res://assets/textures/vehicle/residue/mud_tire_mask.png"
const RESIDUE_DUST_TIRE_MASK: String = "res://assets/textures/vehicle/residue/dust_tire_mask.png"
const RESIDUE_WETNESS_TIRE_MASK: String = "res://assets/textures/vehicle/residue/wetness_tire_mask.png"
const VEHICLE_BODY_BASE_POSITION: Vector3 = Vector3(0.0, 0.010, 0.015)
const VEHICLE_NOSE_BASE_POSITION: Vector3 = Vector3(0.0, 0.018, -0.155)
const VEHICLE_FRONT_LEFT_WHEEL_SOCKET_POSITION: Vector3 = Vector3(-0.08, -0.015, -0.10)
const WHEEL_SOCKET_NAMES: Array[String] = [
	"wheel_front_left",
	"wheel_front_right",
	"wheel_rear_left",
	"wheel_rear_right"
]

var _scene_root: Node = null
var _errors: PackedStringArray = PackedStringArray()


func _ready() -> void:
	_scene_root = FlatPlaneScene.instantiate()
	add_child(_scene_root)
	call_deferred("_inspect")


func _inspect() -> void:
	if _scene_root == null:
		_errors.append("failed to instantiate flat plane scene")
		_finish()
		return
	_inspect_flat_ground()
	var vehicle: Node = _require_node(_scene_root, "Vehicle")
	_inspect_vehicle_visuals(_scene_root, vehicle)
	var chase_camera: Camera3D = _require_node(_scene_root, "ChaseCamera") as Camera3D
	_inspect_chase_camera(vehicle, chase_camera)
	_inspect_render_camera_contract(_scene_root, chase_camera, null, null, "flat")
	_inspect_input_map()
	_inspect_reverse_input_output(_scene_root, "flat host")
	_require_node(_scene_root, "SurfaceMap")
	_require_node(_scene_root, "Sun")
	_finish()


func _inspect_flat_ground() -> void:
	var ground: StaticBody3D = _require_node(_scene_root, "flat_ground__surf_packed_dirt") as StaticBody3D
	if ground == null:
		return
	if not ground.is_in_group("surf_packed_dirt"):
		_errors.append("flat ground should be in surf_packed_dirt group")
	var collision: CollisionShape3D = _require_node(ground, "Collision") as CollisionShape3D
	if collision == null:
		return
	var box: BoxShape3D = collision.shape as BoxShape3D
	if box == null:
		_errors.append("flat ground collision should use BoxShape3D")
		return
	if box.size.distance_to(GameConfig.flat_ground_size) > FLOAT_EPSILON:
		_errors.append("flat ground collision size expected " + str(GameConfig.flat_ground_size) + ", got " + str(box.size))
	if collision.position.distance_to(GameConfig.flat_ground_center) > FLOAT_EPSILON:
		_errors.append("flat ground collision center expected " + str(GameConfig.flat_ground_center) + ", got " + str(collision.position))
	_require_node(ground, "GroundVisual")


func _inspect_vehicle_visuals(host: Node, vehicle: Node) -> void:
	if host == null or vehicle == null:
		return
	var visual_root: Node = _require_node(vehicle, "PhysicsBody/VisualRoot")
	if visual_root == null:
		return
	_require_node(visual_root, "body")
	_require_node(visual_root, "nose")
	_require_node(visual_root, "roll_cage")
	_require_vehicle_chassis_drop(visual_root)
	_require_node_position(visual_root, "wheel_front_left", VEHICLE_FRONT_LEFT_WHEEL_SOCKET_POSITION, FLOAT_EPSILON)
	_require_node_position(visual_root, "wheel_front_right", Vector3(0.08, -0.015, -0.10), FLOAT_EPSILON)
	_require_node_position(visual_root, "wheel_rear_left", Vector3(-0.08, -0.015, 0.10), FLOAT_EPSILON)
	_require_node_position(visual_root, "wheel_rear_right", Vector3(0.08, -0.015, 0.10), FLOAT_EPSILON)
	_require_wheel_socket_mesh(visual_root, "wheel_front_left")
	_require_wheel_socket_mesh(visual_root, "wheel_front_right")
	_require_wheel_socket_mesh(visual_root, "wheel_rear_left")
	_require_wheel_socket_mesh(visual_root, "wheel_rear_right")
	var visual_collision_count: int = _count_collision_objects(visual_root)
	if visual_collision_count > 0:
		_errors.append("flat vehicle VisualRoot contains collision objects: " + str(visual_collision_count))
	var visual_mesh_count: int = _count_mesh_instances(visual_root)
	if visual_mesh_count < 9:
		_errors.append("flat vehicle VisualRoot should include chassis, roll cage, and wheel meshes")
	_require_vehicle_steering_visuals(host, visual_root)
	_require_vehicle_residue_visuals(host, vehicle, visual_root)


func _require_vehicle_chassis_drop(visual_root: Node) -> void:
	var drop_offset: Vector3 = Vector3(0.0, GameConfig.vehicle_visual_chassis_drop, 0.0)
	_require_node_position(visual_root, "body", VEHICLE_BODY_BASE_POSITION - drop_offset, FLOAT_EPSILON)
	_require_node_position(visual_root, "nose", VEHICLE_NOSE_BASE_POSITION - drop_offset, FLOAT_EPSILON)
	var body: Node3D = _require_node(visual_root, "body") as Node3D
	var wheel_socket: Node3D = _require_node(visual_root, "wheel_front_left") as Node3D
	if body == null or wheel_socket == null:
		return
	var visual_gap: float = body.position.y - wheel_socket.position.y
	if visual_gap > GameConfig.vehicle_visual_chassis_wheel_socket_max_gap:
		_errors.append("flat vehicle visual chassis-to-wheel socket gap expected <= " + str(GameConfig.vehicle_visual_chassis_wheel_socket_max_gap) + ", got " + str(visual_gap))


func _require_vehicle_steering_visuals(host: Node, visual_root: Node) -> void:
	var vehicle_input: RefCounted = host.get("_vehicle_input") as RefCounted
	if vehicle_input == null:
		_errors.append("FlatPlaneHost should expose vehicle input for visual wheel updates")
		return
	vehicle_input.set("steer", 1.0)
	host.call("_update_visual_wheels", GameConfig.FIXED_DT)
	var expected_steer: float = deg_to_rad(GameConfig.steer_limit_deg)
	_require_node_rotation_y(visual_root, "wheel_front_left", expected_steer, FLOAT_EPSILON)
	_require_node_rotation_y(visual_root, "wheel_front_right", expected_steer, FLOAT_EPSILON)
	_require_node_rotation_y(visual_root, "wheel_rear_left", 0.0, FLOAT_EPSILON)
	_require_node_rotation_y(visual_root, "wheel_rear_right", 0.0, FLOAT_EPSILON)
	vehicle_input.set("steer", 0.0)
	host.call("_update_visual_wheels", GameConfig.FIXED_DT)


func _require_vehicle_residue_visuals(host: Node, vehicle: Node, visual_root: Node) -> void:
	var state: RefCounted = vehicle.call("get_state")
	var contamination: RefCounted = state.get("contamination") as RefCounted
	if contamination == null:
		_errors.append("flat vehicle state should expose contamination")
		return
	contamination.call("set_values", 0.5, 0.25, 0.75)
	host.call("_update_vehicle_residue_visual", state)
	_require_residue_overlay_alpha(
		visual_root,
		RESIDUE_BODY_OVERLAY,
		0.5,
		0.25,
		0.75,
		GameConfig.vehicle_residue_mud_visual_alpha,
		GameConfig.vehicle_residue_dust_visual_alpha,
		GameConfig.vehicle_residue_wetness_visual_alpha,
		RESIDUE_MUD_BODY_MASK,
		RESIDUE_DUST_BODY_MASK,
		RESIDUE_WETNESS_BODY_MASK
	)
	_require_residue_overlay_visible(
		visual_root,
		RESIDUE_NOSE_OVERLAY,
		0.5,
		0.25,
		0.75,
		GameConfig.vehicle_residue_mud_visual_alpha,
		GameConfig.vehicle_residue_dust_visual_alpha,
		GameConfig.vehicle_residue_wetness_visual_alpha,
		RESIDUE_MUD_BODY_MASK,
		RESIDUE_DUST_BODY_MASK,
		RESIDUE_WETNESS_BODY_MASK
	)
	_require_tire_residue_overlays(visual_root)
	contamination.call("reset")
	host.call("_update_vehicle_residue_visual", state)
	_require_residue_overlay_hidden(visual_root, RESIDUE_BODY_OVERLAY)
	_require_residue_overlay_hidden(visual_root, RESIDUE_NOSE_OVERLAY)
	_require_tire_residue_overlays_hidden(visual_root)


func _require_tire_residue_overlays(visual_root: Node) -> void:
	for wheel_socket_name in WHEEL_SOCKET_NAMES:
		_require_tire_residue_overlay_visible(
			visual_root,
			wheel_socket_name,
			0.5,
			0.25,
			0.75,
			GameConfig.vehicle_residue_mud_visual_alpha * 0.82,
			GameConfig.vehicle_residue_dust_visual_alpha * 0.9,
			GameConfig.vehicle_residue_wetness_visual_alpha * 0.7,
			RESIDUE_MUD_TIRE_MASK,
			RESIDUE_DUST_TIRE_MASK,
			RESIDUE_WETNESS_TIRE_MASK
		)


func _require_tire_residue_overlays_hidden(visual_root: Node) -> void:
	for wheel_socket_name in WHEEL_SOCKET_NAMES:
		_require_tire_residue_overlay_hidden(visual_root, wheel_socket_name)


func _require_tire_residue_overlay_visible(visual_root: Node, wheel_socket_name: String, expected_mud_amount: float, expected_dust_amount: float, expected_wetness_amount: float, expected_mud_alpha_scale: float, expected_dust_alpha_scale: float, expected_wetness_alpha_scale: float, expected_mud_texture_path: String, expected_dust_texture_path: String, expected_wetness_texture_path: String) -> void:
	var socket: Node = _require_node(visual_root, wheel_socket_name)
	if socket == null:
		return
	var overlay: MeshInstance3D = _find_named_residue_overlay(socket, RESIDUE_TIRE_OVERLAY)
	if overlay == null:
		_errors.append(wheel_socket_name + " should contain " + RESIDUE_TIRE_OVERLAY)
		return
	_require_residue_overlay_instance_visible(overlay, wheel_socket_name.path_join(String(overlay.name)), expected_mud_amount, expected_dust_amount, expected_wetness_amount, expected_mud_alpha_scale, expected_dust_alpha_scale, expected_wetness_alpha_scale, expected_mud_texture_path, expected_dust_texture_path, expected_wetness_texture_path)


func _require_tire_residue_overlay_hidden(visual_root: Node, wheel_socket_name: String) -> void:
	var socket: Node = _require_node(visual_root, wheel_socket_name)
	if socket == null:
		return
	var overlay: MeshInstance3D = _find_named_residue_overlay(socket, RESIDUE_TIRE_OVERLAY)
	if overlay == null:
		_errors.append(wheel_socket_name + " should contain " + RESIDUE_TIRE_OVERLAY)
		return
	_require_residue_overlay_instance_hidden(overlay, wheel_socket_name.path_join(String(overlay.name)))


func _find_named_residue_overlay(parent: Node, overlay_name: String) -> MeshInstance3D:
	for index: int in range(parent.get_child_count()):
		var child: Node = parent.get_child(index)
		var overlay: MeshInstance3D = child as MeshInstance3D
		if overlay != null and String(overlay.name) == overlay_name:
			return overlay
		var nested: MeshInstance3D = _find_named_residue_overlay(child, overlay_name)
		if nested != null:
			return nested
	return null


func _require_residue_overlay_visible(parent: Node, path: String, expected_mud_amount: float, expected_dust_amount: float, expected_wetness_amount: float, expected_mud_alpha_scale: float, expected_dust_alpha_scale: float, expected_wetness_alpha_scale: float, expected_mud_texture_path: String, expected_dust_texture_path: String, expected_wetness_texture_path: String) -> void:
	var overlay: MeshInstance3D = _require_node(parent, path) as MeshInstance3D
	if overlay == null:
		return
	_require_residue_overlay_instance_visible(overlay, path, expected_mud_amount, expected_dust_amount, expected_wetness_amount, expected_mud_alpha_scale, expected_dust_alpha_scale, expected_wetness_alpha_scale, expected_mud_texture_path, expected_dust_texture_path, expected_wetness_texture_path)


func _require_residue_overlay_instance_visible(overlay: MeshInstance3D, path: String, expected_mud_amount: float, expected_dust_amount: float, expected_wetness_amount: float, expected_mud_alpha_scale: float, expected_dust_alpha_scale: float, expected_wetness_alpha_scale: float, expected_mud_texture_path: String, expected_dust_texture_path: String, expected_wetness_texture_path: String) -> void:
	if not overlay.visible:
		_errors.append(path + " should be visible when contamination is nonzero")
	var material: ShaderMaterial = _require_residue_material(overlay, path)
	if material == null:
		return
	_require_shader_float(material, "mud_amount", expected_mud_amount, path)
	_require_shader_float(material, "dust_amount", expected_dust_amount, path)
	_require_shader_float(material, "wetness_amount", expected_wetness_amount, path)
	_require_shader_float(material, "mud_alpha_scale", expected_mud_alpha_scale, path)
	_require_shader_float(material, "dust_alpha_scale", expected_dust_alpha_scale, path)
	_require_shader_float(material, "wetness_alpha_scale", expected_wetness_alpha_scale, path)
	_require_residue_texture(material, path, "mud_mask", expected_mud_texture_path)
	_require_residue_texture(material, path, "dust_mask", expected_dust_texture_path)
	_require_residue_texture(material, path, "wetness_mask", expected_wetness_texture_path)


func _require_residue_overlay_alpha(parent: Node, path: String, expected_mud_amount: float, expected_dust_amount: float, expected_wetness_amount: float, expected_mud_alpha_scale: float, expected_dust_alpha_scale: float, expected_wetness_alpha_scale: float, expected_mud_texture_path: String, expected_dust_texture_path: String, expected_wetness_texture_path: String) -> void:
	_require_residue_overlay_visible(parent, path, expected_mud_amount, expected_dust_amount, expected_wetness_amount, expected_mud_alpha_scale, expected_dust_alpha_scale, expected_wetness_alpha_scale, expected_mud_texture_path, expected_dust_texture_path, expected_wetness_texture_path)


func _require_residue_overlay_hidden(parent: Node, path: String) -> void:
	var overlay: MeshInstance3D = _require_node(parent, path) as MeshInstance3D
	if overlay == null:
		return
	_require_residue_overlay_instance_hidden(overlay, path)


func _require_residue_overlay_instance_hidden(overlay: MeshInstance3D, path: String) -> void:
	var material: ShaderMaterial = _require_residue_material(overlay, path)
	if material == null:
		return
	if overlay.visible:
		_errors.append(path + " should hide after contamination reset")
	_require_shader_float(material, "mud_amount", 0.0, path)
	_require_shader_float(material, "dust_amount", 0.0, path)
	_require_shader_float(material, "wetness_amount", 0.0, path)


func _require_residue_material(overlay: MeshInstance3D, path: String) -> ShaderMaterial:
	if overlay.mesh is BoxMesh:
		_errors.append(path + " should use a conformed duplicate source mesh, not BoxMesh")
	var material: ShaderMaterial = overlay.material_override as ShaderMaterial
	if material == null:
		_errors.append(path + " should use ShaderMaterial")
		return null
	if material.shader == null:
		_errors.append(path + " should have a residue shader")
	elif material.shader.resource_path != RESIDUE_SHADER_PATH:
		_errors.append(path + " shader expected " + RESIDUE_SHADER_PATH + ", got " + material.shader.resource_path)
	return material


func _require_residue_texture(material: ShaderMaterial, path: String, parameter_name: String, expected_texture_path: String) -> void:
	var texture: Texture2D = material.get_shader_parameter(parameter_name) as Texture2D
	if texture == null:
		_errors.append(path + " should set shader texture " + parameter_name)
		return
	if texture.resource_path != expected_texture_path:
		_errors.append(path + " " + parameter_name + " expected " + expected_texture_path + ", got " + texture.resource_path)


func _require_shader_float(material: ShaderMaterial, parameter_name: String, expected: float, label: String) -> void:
	var value: float = float(material.get_shader_parameter(parameter_name))
	if absf(value - expected) > FLOAT_EPSILON:
		_errors.append(label + " shader parameter " + parameter_name + " expected " + str(expected) + ", got " + str(value))


func _inspect_chase_camera(vehicle: Node, chase_camera: Camera3D) -> void:
	if vehicle == null or chase_camera == null:
		return
	var state: RefCounted = vehicle.call("get_state")
	var vehicle_position: Vector3 = state.get("position")
	if not chase_camera.current:
		_errors.append("flat ChaseCamera should be current")
	if absf(chase_camera.fov - GameConfig.cam_fov_base) > FLOAT_EPSILON:
		_errors.append("flat ChaseCamera should start at base FOV")
	if chase_camera.global_position.y <= vehicle_position.y:
		_errors.append("flat ChaseCamera should start above the vehicle")
	if chase_camera.global_position.z <= vehicle_position.z:
		_errors.append("flat ChaseCamera should start behind the spawn")
	_require_chase_camera_composition(state, chase_camera, "flat ChaseCamera")


func _require_chase_camera_composition(state: RefCounted, chase_camera: Camera3D, context: String) -> void:
	var vehicle_position: Vector3 = state.get("position")
	var vehicle_basis: Basis = state.get("basis")
	var back: Vector3 = vehicle_basis.z.normalized()
	var expected_position: Vector3 = vehicle_position + back * GameConfig.cam_distance + Vector3.UP * GameConfig.cam_height
	if chase_camera.global_position.distance_to(expected_position) > CAMERA_COMPOSITION_TOLERANCE:
		_errors.append(context + " initial position expected " + str(expected_position) + ", got " + str(chase_camera.global_position))
	var offset: Vector3 = chase_camera.global_position - vehicle_position
	var expected_offset_xz: Vector2 = Vector2(back.x, back.z) * GameConfig.cam_distance
	var actual_offset_xz: Vector2 = Vector2(offset.x, offset.z)
	if actual_offset_xz.distance_to(expected_offset_xz) > CAMERA_COMPOSITION_TOLERANCE:
		_errors.append(context + " rear offset expected " + str(expected_offset_xz) + ", got " + str(actual_offset_xz))
	if absf(offset.y - GameConfig.cam_height) > CAMERA_COMPOSITION_TOLERANCE:
		_errors.append(context + " height offset expected " + str(GameConfig.cam_height) + ", got " + str(offset.y))
	_require_camera_pitch(chase_camera, context)


func _require_camera_pitch(camera: Camera3D, context: String) -> void:
	var forward: Vector3 = -camera.global_transform.basis.z.normalized()
	var pitch_degrees: float = rad_to_deg(asin(clampf(forward.y, -1.0, 1.0)))
	if absf(pitch_degrees - GameConfig.cam_pitch_deg) > CAMERA_PITCH_TOLERANCE_DEG:
		_errors.append(context + " pitch expected " + str(GameConfig.cam_pitch_deg) + ", got " + str(pitch_degrees))


func _inspect_render_camera_contract(host: Node, chase_camera: Camera3D, orbit_camera: Camera3D, fpv_camera: Camera3D, context: String) -> void:
	_inspect_tilt_shift_layer(host, context)
	_inspect_viewport_antialiasing(host, context)
	_inspect_project_scaling_settings(context)
	_inspect_fov_range(context)
	_require_camera_dof_disabled(chase_camera, context + " ChaseCamera")
	_require_camera_dof_disabled(orbit_camera, context + " OrbitCamera")
	_require_camera_dof_disabled(fpv_camera, context + " FpvCamera")


func _inspect_tilt_shift_layer(host: Node, context: String) -> void:
	if host == null:
		return
	var layer: CanvasLayer = _require_node(host, TILT_SHIFT_LAYER_NAME) as CanvasLayer
	if layer == null:
		return
	if layer.layer != TILT_SHIFT_LAYER_INDEX:
		_errors.append(context + " TiltShiftLayer layer expected " + str(TILT_SHIFT_LAYER_INDEX) + ", got " + str(layer.layer))
	if layer.visible != GameConfig.tilt_shift_enabled:
		_errors.append(context + " TiltShiftLayer visible state should follow GameConfig")
	var overlay: ColorRect = _require_node(layer, TILT_SHIFT_RECT_NAME) as ColorRect
	if overlay == null:
		return
	if absf(overlay.anchor_left) > FLOAT_EPSILON or absf(overlay.anchor_top) > FLOAT_EPSILON or absf(overlay.anchor_right - 1.0) > FLOAT_EPSILON or absf(overlay.anchor_bottom - 1.0) > FLOAT_EPSILON:
		_errors.append(context + " TiltShiftOverlay should be full-rect anchored")
	var material: ShaderMaterial = overlay.material as ShaderMaterial
	if material == null:
		_errors.append(context + " TiltShiftOverlay should use ShaderMaterial")
		return
	if material.shader == null:
		_errors.append(context + " TiltShiftOverlay should have a shader")
	elif material.shader.resource_path != TILT_SHIFT_SHADER_PATH:
		_errors.append(context + " TiltShiftOverlay shader expected " + TILT_SHIFT_SHADER_PATH + ", got " + material.shader.resource_path)
	_require_shader_float(material, "center", GameConfig.tilt_shift_band_center, context + " TiltShiftOverlay")
	_require_shader_float(material, "band", GameConfig.tilt_shift_focus_band, context + " TiltShiftOverlay")
	_require_shader_float(material, "blur", GameConfig.tilt_shift_blur_amount, context + " TiltShiftOverlay")


func _inspect_viewport_antialiasing(host: Node, context: String) -> void:
	if host == null:
		return
	var viewport: Viewport = host.get_viewport()
	if viewport == null:
		_errors.append(context + " host should have a viewport")
		return
	if viewport.msaa_3d != Viewport.MSAA_DISABLED:
		_errors.append(context + " viewport msaa_3d expected MSAA_DISABLED, got " + str(viewport.msaa_3d))
	if not viewport.use_taa:
		_errors.append(context + " viewport should keep TAA enabled")


func _inspect_project_scaling_settings(context: String) -> void:
	var mode_value: int = int(ProjectSettings.get_setting("rendering/scaling_3d/mode", -1))
	var scale_value: float = float(ProjectSettings.get_setting("rendering/scaling_3d/scale", 0.0))
	var sharpness_value: float = float(ProjectSettings.get_setting("rendering/scaling_3d/fsr_sharpness", -1.0))
	if mode_value != 2:
		_errors.append(context + " project scaling_3d/mode expected 2, got " + str(mode_value))
	if absf(scale_value - 0.71) > FLOAT_EPSILON:
		_errors.append(context + " project scaling_3d/scale expected 0.71, got " + str(scale_value))
	if absf(sharpness_value - 0.1) > FLOAT_EPSILON:
		_errors.append(context + " project scaling_3d/fsr_sharpness expected 0.1, got " + str(sharpness_value))


func _inspect_fov_range(context: String) -> void:
	var rest_fov: float = GameConfig.get_fov_for_speed(0.0)
	var max_fov: float = GameConfig.get_fov_for_speed(GameConfig.max_speed)
	if absf(rest_fov - EXPECTED_FOV_MIN) > FLOAT_EPSILON:
		_errors.append(context + " FOV at rest expected " + str(EXPECTED_FOV_MIN) + ", got " + str(rest_fov))
	if absf(max_fov - EXPECTED_FOV_MAX) > FLOAT_EPSILON:
		_errors.append(context + " FOV at max speed expected " + str(EXPECTED_FOV_MAX) + ", got " + str(max_fov))


func _require_camera_dof_disabled(camera: Camera3D, label: String) -> void:
	if camera == null:
		return
	var existing_attributes: CameraAttributes = camera.attributes
	if existing_attributes != null and not (existing_attributes is CameraAttributesPractical):
		_errors.append(label + " should use CameraAttributesPractical when attributes are present")
		return
	var attributes: CameraAttributesPractical = existing_attributes as CameraAttributesPractical
	if attributes == null:
		_errors.append(label + " should have atmosphere-owned practical attributes")
		return
	if attributes.dof_blur_near_enabled:
		_errors.append(label + " should not enable near DOF blur")
	if attributes.dof_blur_far_enabled:
		_errors.append(label + " should not enable far DOF blur")
	if attributes.auto_exposure_enabled != GameConfig.atmosphere_auto_exposure_enabled:
		_errors.append(label + " auto exposure should follow GameConfig")


func _inspect_input_map() -> void:
	_require_input_action_keys(&"throttle", [KEY_W, KEY_UP])
	_require_input_action_keys(&"brake", [KEY_S, KEY_DOWN])
	_require_input_action_keys(&"reverse", [KEY_S, KEY_DOWN])
	_require_input_action_keys(&"steer_left", [KEY_A, KEY_LEFT])
	_require_input_action_keys(&"steer_right", [KEY_D, KEY_RIGHT])
	_require_input_action_keys(&"ebrake", [KEY_SPACE])
	_require_input_action_keys(&"self_right", [KEY_R])
	_require_input_action_keys(&"cam_toggle", [KEY_C])


func _require_input_action_keys(action_name: StringName, expected_keycodes: Array[int]) -> void:
	var action_string: String = String(action_name)
	if not InputMap.has_action(action_string):
		_errors.append("InputMap missing action: " + action_string)
		return
	var observed_keycodes: Array[int] = []
	for event in InputMap.action_get_events(action_string):
		var key_event: InputEventKey = event as InputEventKey
		if key_event != null:
			if key_event.physical_keycode != 0:
				observed_keycodes.append(key_event.physical_keycode)
			if key_event.keycode != 0:
				observed_keycodes.append(key_event.keycode)
	for keycode in expected_keycodes:
		if not observed_keycodes.has(keycode):
			_errors.append("InputMap action " + action_string + " missing keycode " + str(keycode))


func _inspect_reverse_input_output(host: Node, context: String) -> void:
	if host == null:
		return
	var vehicle_input: RefCounted = host.get("_vehicle_input") as RefCounted
	if vehicle_input == null:
		_errors.append(context + " should expose vehicle input for reverse inspection")
		return
	Input.action_press(&"brake", 1.0)
	Input.action_press(&"reverse", 1.0)
	host.call("_update_vehicle_input")
	var reverse_throttle: float = float(vehicle_input.get("throttle"))
	var reverse_brake: float = float(vehicle_input.get("brake"))
	Input.action_release(&"reverse")
	Input.action_release(&"brake")
	if reverse_throttle >= -0.99:
		_errors.append(context + " reverse action should produce negative throttle, got " + str(reverse_throttle))
	if reverse_brake > FLOAT_EPSILON:
		_errors.append(context + " should not apply brake damping during pure reverse, got " + str(reverse_brake))
	Input.action_press(&"throttle", 1.0)
	Input.action_press(&"brake", 1.0)
	Input.action_press(&"reverse", 1.0)
	host.call("_update_vehicle_input")
	var opposed_throttle: float = float(vehicle_input.get("throttle"))
	var opposed_brake: float = float(vehicle_input.get("brake"))
	Input.action_release(&"reverse")
	Input.action_release(&"brake")
	Input.action_release(&"throttle")
	if absf(opposed_throttle) > FLOAT_EPSILON:
		_errors.append(context + " opposed forward/reverse should neutralize throttle, got " + str(opposed_throttle))
	if opposed_brake < 0.99:
		_errors.append(context + " opposed forward/reverse should apply brake, got " + str(opposed_brake))


func _require_node(parent: Node, path: String) -> Node:
	var node: Node = parent.get_node_or_null(path)
	if node == null:
		_errors.append("missing node: " + path)
	return node


func _require_node_position(parent: Node, path: String, expected: Vector3, tolerance: float) -> void:
	var node: Node3D = _require_node(parent, path) as Node3D
	if node == null:
		return
	if node.position.distance_to(expected) > tolerance:
		_errors.append(path + " position expected " + str(expected) + ", got " + str(node.position))


func _require_node_rotation_y(parent: Node, path: String, expected: float, tolerance: float) -> void:
	var node: Node3D = _require_node(parent, path) as Node3D
	if node == null:
		return
	if absf(node.rotation.y - expected) > tolerance:
		_errors.append(path + " rotation.y expected " + str(expected) + ", got " + str(node.rotation.y))


func _require_wheel_socket_mesh(parent: Node, path: String) -> void:
	var socket: Node = _require_node(parent, path)
	if socket == null:
		return
	for child in socket.get_children():
		if child is MeshInstance3D:
			return
	_errors.append(path + " should contain a wheel mesh")


func _count_collision_objects(parent: Node) -> int:
	var count: int = 0
	for child in parent.get_children():
		if child is CollisionObject3D:
			count += 1
		count += _count_collision_objects(child)
	return count


func _count_mesh_instances(parent: Node) -> int:
	var count: int = 0
	for child in parent.get_children():
		if child is MeshInstance3D:
			count += 1
		count += _count_mesh_instances(child)
	return count


func _finish() -> void:
	if _errors.is_empty():
		print("ok: flat plane visuals, vehicle, camera, and surface nodes instantiated")
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
