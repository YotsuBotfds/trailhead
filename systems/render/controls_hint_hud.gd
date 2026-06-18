class_name ControlsHintHud
extends CanvasLayer

const LAYER: int = 12

var _panel: Control = null


func _ready() -> void:
	layer = LAYER
	_panel = _ControlsHintPanel.new()
	_panel.name = "ControlsHintPanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_panel)


class _ControlsHintPanel:
	extends Control

	const MARGIN: float = 20.0
	const PANEL_PADDING_X: float = 14.0
	const PANEL_PADDING_Y: float = 9.0
	const FONT_SIZE: int = 13
	const HINT_LINE_DRIVE: String = "RT/W: Drive  \u00b7  LT/S: Reverse  \u00b7  A: Handbrake  \u00b7  Y: Reset"
	const HINT_LINE_FEATURES: String = "RB: Camera  \u00b7  B: Tour  \u00b7  X: Photo  \u00b7  LB: Mood  \u00b7  M: Map"
	const BG_COLOR: Color = Color(0.05, 0.05, 0.04, 0.42)
	const TEXT_COLOR: Color = Color(0.90, 0.86, 0.74, 0.80)

	var _elapsed: float = 0.0
	var _fading: bool = false
	var _alpha: float = 1.0


	func _process(delta: float) -> void:
		if _alpha > 0.0:
			_elapsed += delta
			if not _fading and (_drive_input_pressed() or _elapsed >= GameConfig.controls_hint_hud_auto_dismiss_seconds):
				_fading = true
			if _fading:
				_alpha = maxf(_alpha - delta / maxf(GameConfig.controls_hint_hud_fade_seconds, 0.001), 0.0)
			queue_redraw()


	func _drive_input_pressed() -> bool:
		return Input.get_action_strength("throttle") > 0.0 or Input.get_action_strength("reverse") > 0.0


	func _draw() -> void:
		if _alpha <= 0.0:
			return
		var alpha: float = clampf(_alpha, 0.0, 1.0)
		var font: Font = get_theme_default_font()
		var drive_size: Vector2 = font.get_string_size(HINT_LINE_DRIVE, HORIZONTAL_ALIGNMENT_LEFT, 0.0, FONT_SIZE)
		var features_size: Vector2 = font.get_string_size(HINT_LINE_FEATURES, HORIZONTAL_ALIGNMENT_LEFT, 0.0, FONT_SIZE)
		var text_w: float = maxf(drive_size.x, features_size.x)
		var panel_size: Vector2 = Vector2(text_w + PANEL_PADDING_X * 2.0, drive_size.y + features_size.y + PANEL_PADDING_Y * 2.0)
		var origin: Vector2 = _panel_origin(panel_size)
		draw_rect(
			Rect2(origin, panel_size),
			Color(BG_COLOR.r, BG_COLOR.g, BG_COLOR.b, BG_COLOR.a * alpha),
			true
		)
		var text_x: float = origin.x + PANEL_PADDING_X
		var text_color: Color = Color(TEXT_COLOR.r, TEXT_COLOR.g, TEXT_COLOR.b, TEXT_COLOR.a * alpha)
		draw_string(
			font,
			Vector2(text_x, origin.y + PANEL_PADDING_Y),
			HINT_LINE_DRIVE,
			HORIZONTAL_ALIGNMENT_LEFT,
			0.0,
			FONT_SIZE,
			text_color
		)
		draw_string(
			font,
			Vector2(text_x, origin.y + PANEL_PADDING_Y + drive_size.y),
			HINT_LINE_FEATURES,
			HORIZONTAL_ALIGNMENT_LEFT,
			0.0,
			FONT_SIZE,
			text_color
		)


	func _panel_origin(panel_size: Vector2) -> Vector2:
		var view_w: float = maxf(size.x, panel_size.x + MARGIN)
		var view_h: float = maxf(size.y, panel_size.y + MARGIN)
		return Vector2(view_w - panel_size.x - MARGIN, view_h - panel_size.y - MARGIN)
