class_name CampfireSilenceZone
extends Area3D

const SILENCE_VOLUME_DB: float = -60.0
const FADE_SECONDS: float = 0.5
const STONE_COUNT: int = 10
const RING_RADIUS: float = 0.32

var _inside_bodies: Array[Node] = []
var _saved_ambient_volume_db: float = 0.0
var _fade_start_volume_db: float = 0.0
var _fade_target_volume_db: float = 0.0
var _fade_elapsed_seconds: float = 0.0
var _fade_active: bool = false
var _has_saved_volume: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_build_placeholder_prop()
	_configure_cold_smoke()


func _exit_tree() -> void:
	if _has_saved_volume:
		GameConfig.audio_bus_ambient_volume_db = _saved_ambient_volume_db


func _physics_process(delta: float) -> void:
	if not _fade_active:
		return
	_fade_elapsed_seconds += delta
	var t: float = clampf(_fade_elapsed_seconds / FADE_SECONDS, 0.0, 1.0)
	GameConfig.audio_bus_ambient_volume_db = lerpf(_fade_start_volume_db, _fade_target_volume_db, t)
	if t >= 1.0:
		_fade_active = false
		if _inside_bodies.is_empty():
			_has_saved_volume = false


func _on_body_entered(body: Node) -> void:
	if not _is_vehicle_physics_body(body) or _inside_bodies.has(body):
		return
	_inside_bodies.append(body)
	if not _has_saved_volume:
		_saved_ambient_volume_db = GameConfig.audio_bus_ambient_volume_db
		_has_saved_volume = true
	_begin_fade(SILENCE_VOLUME_DB)


func _on_body_exited(body: Node) -> void:
	if not _inside_bodies.has(body):
		return
	_inside_bodies.erase(body)
	if _inside_bodies.is_empty() and _has_saved_volume:
		_begin_fade(_saved_ambient_volume_db)


func _begin_fade(target_volume_db: float) -> void:
	_fade_start_volume_db = GameConfig.audio_bus_ambient_volume_db
	_fade_target_volume_db = target_volume_db
	_fade_elapsed_seconds = 0.0
	_fade_active = true


func _is_vehicle_physics_body(body: Node) -> bool:
	if body == null or body.name != "PhysicsBody":
		return false
	var parent: Node = body.get_parent()
	return parent != null and parent.has_method("get_state")


func _build_placeholder_prop() -> void:
	var prop_root: Node3D = get_node_or_null("PropRoot") as Node3D
	if prop_root == null or prop_root.get_child_count() > 0:
		return
	var stone_material: StandardMaterial3D = _make_material("cold_fire_ring_stone", Color(0.12, 0.12, 0.11))
	var cup_material: StandardMaterial3D = _make_material("cold_fire_ring_tin", Color(0.42, 0.45, 0.46))
	var coal_material: StandardMaterial3D = _make_material("cold_fire_ring_ash", Color(0.035, 0.035, 0.033))
	var wire_material: StandardMaterial3D = _make_material("cold_fire_ring_wire", Color(0.07, 0.07, 0.065))

	for i in range(STONE_COUNT):
		var angle: float = TAU * float(i) / float(STONE_COUNT)
		var stone: MeshInstance3D = MeshInstance3D.new()
		stone.name = "stone_" + str(i + 1)
		var stone_mesh: BoxMesh = BoxMesh.new()
		stone_mesh.size = Vector3(0.16 + float(i % 3) * 0.025, 0.055, 0.11 + float(i % 2) * 0.025)
		stone.mesh = stone_mesh
		stone.position = Vector3(cos(angle) * RING_RADIUS, 0.03, sin(angle) * RING_RADIUS)
		stone.rotation_degrees = Vector3(0.0, rad_to_deg(-angle), 0.0)
		stone.material_override = stone_material
		prop_root.add_child(stone)

	var ash: MeshInstance3D = MeshInstance3D.new()
	ash.name = "cold_ash"
	var ash_mesh: CylinderMesh = CylinderMesh.new()
	ash_mesh.top_radius = 0.25
	ash_mesh.bottom_radius = 0.25
	ash_mesh.height = 0.012
	ash_mesh.radial_segments = 16
	ash.mesh = ash_mesh
	ash.position = Vector3(0.0, 0.008, 0.0)
	ash.material_override = coal_material
	prop_root.add_child(ash)

	var tin_cup: MeshInstance3D = MeshInstance3D.new()
	tin_cup.name = "tipped_tin_cup_placeholder"
	var cup_mesh: CylinderMesh = CylinderMesh.new()
	cup_mesh.top_radius = 0.055
	cup_mesh.bottom_radius = 0.045
	cup_mesh.height = 0.14
	cup_mesh.radial_segments = 10
	tin_cup.mesh = cup_mesh
	tin_cup.position = Vector3(0.18, 0.055, -0.18)
	tin_cup.rotation_degrees = Vector3(72.0, -28.0, 0.0)
	tin_cup.material_override = cup_material
	prop_root.add_child(tin_cup)

	var wire: MeshInstance3D = MeshInstance3D.new()
	wire.name = "wire_coil_placeholder"
	var wire_mesh: TorusMesh = TorusMesh.new()
	wire_mesh.inner_radius = 0.035
	wire_mesh.outer_radius = 0.075
	wire_mesh.ring_segments = 16
	wire.mesh = wire_mesh
	wire.position = Vector3(-0.16, 0.04, 0.16)
	wire.rotation_degrees = Vector3(88.0, 18.0, 0.0)
	wire.material_override = wire_material
	prop_root.add_child(wire)


func _configure_cold_smoke() -> void:
	var smoke: GPUParticles3D = get_node_or_null("ColdSmoke") as GPUParticles3D
	if smoke == null:
		return
	if DisplayServer.get_name() == "headless":
		smoke.emitting = false


func _make_material(resource_name: String, albedo: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.resource_name = resource_name
	material.albedo_color = albedo
	material.roughness = 0.92
	material.metallic = 0.0
	return material
