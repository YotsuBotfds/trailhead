extends Node3D

const CottonwoodScene: PackedScene = preload("res://assets/models/foliage/cottonwood.glb")
const WillowScene: PackedScene = preload("res://assets/models/foliage/willow.glb")
const JuniperScene: PackedScene = preload("res://assets/models/foliage/juniper.glb")

const WINDOW_SIZE: Vector2i = Vector2i(1280, 720)
const OUT_DIR: String = "tests/out/foliage_closeup"
const CHASE_CAPTURE_NAME: String = "foliage_closeup_chase.png"
const ORBIT_CAPTURE_NAME: String = "foliage_closeup_orbit.png"
const JUNIPER_CAPTURE_NAME: String = "foliage_closeup_juniper.png"
const RENDER_WAIT_FRAMES: int = 8
const SHUTDOWN_FRAMES: int = 3
const MIN_TREE_SURFACE_COUNT: int = 2
const MIN_COTTONWOOD_HEIGHT_M: float = 8.0
const MIN_WILLOW_HEIGHT_M: float = 4.0
const MIN_JUNIPER_HEIGHT_M: float = 2.5
const MIN_TREE_CANOPY_WIDTH_M: float = 3.0
const MIN_JUNIPER_CANOPY_WIDTH_M: float = 1.8

var _errors: PackedStringArray = PackedStringArray()
var _camera: Camera3D = null
var _cottonwood: Node3D = null
var _willow: Node3D = null
var _juniper: Node3D = null


func _ready() -> void:
	DisplayServer.window_set_size(WINDOW_SIZE)
	_prepare_output_dir()
	_build_scene()
	call_deferred("_run")


func _prepare_output_dir() -> void:
	var absolute_dir: String = ProjectSettings.globalize_path(OUT_DIR)
	var err: Error = DirAccess.make_dir_recursive_absolute(absolute_dir)
	if err != OK:
		_errors.append("failed to create foliage closeup output dir: " + absolute_dir + " error=" + str(err))


func _build_scene() -> void:
	_add_light()
	_add_ground()
	_add_trees()
	_add_camera()


func _add_light() -> void:
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.name = "CloseupSun"
	sun.light_energy = 2.5
	sun.rotation_degrees = Vector3(-48.0, -32.0, 0.0)
	add_child(sun)


func _add_ground() -> void:
	var ground_mesh: PlaneMesh = PlaneMesh.new()
	ground_mesh.size = Vector2(14.0, 12.0)
	var ground_material: StandardMaterial3D = StandardMaterial3D.new()
	ground_material.albedo_color = Color(0.46, 0.34, 0.22, 1.0)
	ground_material.roughness = 0.9
	ground_mesh.material = ground_material
	var ground: MeshInstance3D = MeshInstance3D.new()
	ground.name = "GroundReference"
	ground.mesh = ground_mesh
	add_child(ground)


func _add_trees() -> void:
	_cottonwood = CottonwoodScene.instantiate() as Node3D
	if _cottonwood == null:
		_errors.append("failed to instantiate cottonwood.glb")
	else:
		_cottonwood.name = "CottonwoodCloseup"
		_cottonwood.position = Vector3(-1.4, 0.0, 0.0)
		add_child(_cottonwood)
		_validate_tree_mesh(_cottonwood, "cottonwood", MIN_COTTONWOOD_HEIGHT_M, MIN_TREE_CANOPY_WIDTH_M)
	_willow = WillowScene.instantiate() as Node3D
	if _willow == null:
		_errors.append("failed to instantiate willow.glb")
	else:
		_willow.name = "WillowCloseup"
		_willow.position = Vector3(3.4, 0.0, 1.0)
		add_child(_willow)
		_validate_tree_mesh(_willow, "willow", MIN_WILLOW_HEIGHT_M, MIN_TREE_CANOPY_WIDTH_M)
	_juniper = JuniperScene.instantiate() as Node3D
	if _juniper == null:
		_errors.append("failed to instantiate juniper.glb")
	else:
		_juniper.name = "JuniperCloseup"
		_juniper.position = Vector3(0.6, 0.0, -2.8)
		add_child(_juniper)
		_validate_tree_mesh(_juniper, "juniper", MIN_JUNIPER_HEIGHT_M, MIN_JUNIPER_CANOPY_WIDTH_M)


func _validate_tree_mesh(tree: Node3D, label: String, min_height_m: float, min_canopy_width_m: float) -> void:
	var mesh_instance: MeshInstance3D = _find_first_mesh_instance(tree)
	if mesh_instance == null or mesh_instance.mesh == null:
		_errors.append(label + " has no MeshInstance3D mesh")
		return
	var mesh: Mesh = mesh_instance.mesh
	if mesh.get_surface_count() < MIN_TREE_SURFACE_COUNT:
		_errors.append(label + " should keep bark and leaf surfaces")
	var bounds: AABB = mesh.get_aabb()
	if bounds.size.y < min_height_m:
		_errors.append(label + " height too small: " + str(bounds.size.y))
	var canopy_width: float = maxf(bounds.size.x, bounds.size.z)
	if canopy_width < min_canopy_width_m:
		_errors.append(label + " canopy width too small: " + str(canopy_width))


func _find_first_mesh_instance(parent: Node) -> MeshInstance3D:
	var mesh_instance: MeshInstance3D = parent as MeshInstance3D
	if mesh_instance != null and mesh_instance.mesh != null:
		return mesh_instance
	for child in parent.get_children():
		var child_mesh: MeshInstance3D = _find_first_mesh_instance(child)
		if child_mesh != null:
			return child_mesh
	return null


func _add_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "CloseupCamera"
	_camera.fov = 58.0
	_camera.near = 0.04
	_camera.far = 60.0
	add_child(_camera)
	_camera.current = true


func _run() -> void:
	if _camera == null:
		_errors.append("missing closeup camera")
		await _finish()
		return
	_set_camera(Vector3(4.8, 1.15, 9.2), Vector3(0.4, 4.0, 0.0))
	await _wait_for_render()
	await _capture(CHASE_CAPTURE_NAME)
	_set_camera(Vector3(8.2, 3.2, 4.8), Vector3(0.4, 4.8, 0.1))
	await _wait_for_render()
	await _capture(ORBIT_CAPTURE_NAME)
	_set_juniper_only_view(true)
	_set_camera(Vector3(4.0, 1.55, 1.2), Vector3(0.6, 1.45, -2.8))
	await _wait_for_render()
	await _capture(JUNIPER_CAPTURE_NAME)
	await _finish()


func _set_juniper_only_view(enabled: bool) -> void:
	if _cottonwood != null:
		_cottonwood.visible = not enabled
	if _willow != null:
		_willow.visible = not enabled
	if _juniper != null:
		_juniper.visible = true


func _set_camera(position: Vector3, target: Vector3) -> void:
	if _camera == null:
		return
	_camera.global_position = position
	_camera.look_at(target, Vector3.UP)
	_camera.make_current()


func _wait_for_render() -> void:
	for _i in range(RENDER_WAIT_FRAMES):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw


func _capture(file_name: String) -> void:
	var viewport_texture: ViewportTexture = get_viewport().get_texture()
	if viewport_texture == null:
		_errors.append(file_name + " has no viewport texture")
		return
	var image: Image = viewport_texture.get_image()
	if image == null or image.is_empty():
		_errors.append(file_name + " captured an empty image")
		return
	var path: String = OUT_DIR.path_join(file_name)
	var err: Error = image.save_png(path)
	if err != OK:
		_errors.append(file_name + " failed to save " + path + " error=" + str(err))


func _finish() -> void:
	for _i in range(SHUTDOWN_FRAMES):
		await get_tree().process_frame
	if _errors.size() > 0:
		for error in _errors:
			push_error(error)
		get_tree().quit(1)
		return
	print("ok: foliage closeup captures wrote " + OUT_DIR)
	get_tree().quit(0)
