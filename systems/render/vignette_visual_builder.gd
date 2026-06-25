class_name VignetteVisualBuilder
extends RefCounted

const VIGNETTE_LAYER_NAME: String = "VignetteLayer"
const VIGNETTE_RECT_NAME: String = "VignetteOverlay"
const VIGNETTE_LAYER_INDEX: int = 3
const VignetteShader: Shader = preload("res://systems/render/vignette.gdshader")


static func build(parent: Node) -> CanvasLayer:
	return _ensure_vignette_layer(parent)


static func _ensure_vignette_layer(parent: Node) -> CanvasLayer:
	var existing_layer: CanvasLayer = parent.get_node_or_null(VIGNETTE_LAYER_NAME) as CanvasLayer
	if existing_layer != null:
		_configure_vignette_layer(existing_layer)
		return existing_layer
	var layer: CanvasLayer = CanvasLayer.new()
	layer.name = VIGNETTE_LAYER_NAME
	layer.layer = VIGNETTE_LAYER_INDEX
	parent.add_child(layer)
	_configure_vignette_layer(layer)
	return layer


static func _configure_vignette_layer(layer: CanvasLayer) -> void:
	layer.visible = GameConfig.vignette_enabled
	var overlay: ColorRect = layer.get_node_or_null(VIGNETTE_RECT_NAME) as ColorRect
	if overlay == null:
		overlay = ColorRect.new()
		overlay.name = VIGNETTE_RECT_NAME
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
	material.shader = VignetteShader
	material.set_shader_parameter("vignette_active", 1.0 if GameConfig.vignette_enabled else 0.0)
	material.set_shader_parameter("vignette_strength", clampf(GameConfig.vignette_strength, 0.0, 1.0))
	material.set_shader_parameter("vignette_feather", clampf(GameConfig.vignette_feather, 0.0, 1.0))
	material.set_shader_parameter("vignette_warm_tint", GameConfig.vignette_warm_tint)
