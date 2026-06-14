class_name WaterVisualBuilder
extends RefCounted

const WaterShader: Shader = preload("res://systems/render/water_visual.gdshader")
const ROOT_NAME: String = "WaterVisuals"
const WATER_SURFACE_GROUP: String = "render_water_surface"


static func build_cedar_hollow(parent: Node3D) -> Node3D:
	var root: Node3D = Node3D.new()
	root.name = ROOT_NAME
	parent.add_child(root)
	_add_water_plane(root, "bog_pool_water", Vector3(2.80, GameConfig.water_surface_y + 0.018, -5.50), Vector2(2.10, 1.95), 4.0)
	_add_water_plane(root, "crossing_water", Vector3(4.20, GameConfig.water_surface_y + 0.020, -7.35), Vector2(3.12, 2.62), -7.0)
	_add_water_plane(root, "culvert_runoff_water", Vector3(-4.35, GameConfig.water_surface_y + 0.016, -3.05), Vector2(1.18, 2.35), 0.0)
	return root


static func _add_water_plane(parent: Node3D, node_name: String, position: Vector3, size: Vector2, yaw_degrees: float) -> MeshInstance3D:
	var mesh: PlaneMesh = PlaneMesh.new()
	mesh.size = size
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.position = position
	instance.rotation_degrees = Vector3(0.0, yaw_degrees, 0.0)
	instance.material_override = _water_material(node_name)
	instance.add_to_group(WATER_SURFACE_GROUP)
	instance.set_meta("water_visual_kind", node_name)
	parent.add_child(instance)
	return instance


static func _water_material(resource_name: String) -> ShaderMaterial:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.resource_name = resource_name + "_material"
	material.shader = WaterShader
	material.set_shader_parameter("shallow_color", GameConfig.water_shallow_color)
	material.set_shader_parameter("deep_color", GameConfig.water_deep_color)
	material.set_shader_parameter("water_alpha", GameConfig.water_alpha)
	material.set_shader_parameter("depth_fade_distance", GameConfig.water_depth_fade_distance)
	material.set_shader_parameter("foam_edge_width", GameConfig.water_foam_edge_width)
	material.set_shader_parameter("flow_speed", GameConfig.water_flow_speed)
	material.set_shader_parameter("wave_amplitude", GameConfig.water_wave_amplitude)
	return material
