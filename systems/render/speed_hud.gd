class_name SpeedHud
extends CanvasLayer

const LAYER: int = 8

var _vehicle: Node = null
var _panel: Control = null


func _ready() -> void:
	layer = LAYER
	_panel = _SpeedHudPanel.new()
	_panel.name = "SpeedHudPanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_panel)
	_panel.configure(_vehicle)


func configure(vehicle: Node) -> void:
	_vehicle = vehicle
	if _panel != null:
		_panel.configure(_vehicle)


func set_drive_active(active: bool) -> void:
	if _panel != null:
		_panel.set_drive_active(active)


class _SpeedHudPanel:
	extends Control

	const MARGIN: float = 20.0
	const PANEL_WIDTH: float = 156.0
	const PANEL_HEIGHT: float = 60.0
	const CONTENT_INSET_X: float = 12.0
	const CONTENT_TOP: float = 9.0
	const BAR_TRACK_HEIGHT: float = 4.0
	const BAR_BOTTOM_MARGIN: float = 9.0
	const UNIT_GAP: float = 6.0
	const FADE_IN_SECONDS: float = 0.6
	const VALUE_FONT_SIZE: int = 30
	const UNIT_FONT_SIZE: int = 13
	const SPEED_UNIT: String = "m/s"
	const BG_COLOR: Color = Color(0.04, 0.05, 0.05, 0.36)
	const VALUE_COLOR: Color = Color(0.98, 0.95, 0.88, 0.95)
	const UNIT_COLOR: Color = Color(0.82, 0.72, 0.55, 0.60)
	const BAR_BG_COLOR: Color = Color(0.12, 0.11, 0.09, 0.55)
	const BAR_FILL_COLOR: Color = Color(0.93, 0.75, 0.38, 0.88)

	var _vehicle: Node = null
	var _drive_active: bool = false
	var _fade_alpha: float = 0.0


	func configure(vehicle: Node) -> void:
		_vehicle = vehicle
		queue_redraw()


	func set_drive_active(active: bool) -> void:
		if active == _drive_active:
			return
		_drive_active = active


	func _process(delta: float) -> void:
		var target_alpha: float = 1.0 if _drive_active else 0.0
		var step: float = delta / maxf(FADE_IN_SECONDS, 0.001)
		if _fade_alpha < target_alpha:
			_fade_alpha = minf(_fade_alpha + step, target_alpha)
		elif _fade_alpha > target_alpha:
			_fade_alpha = maxf(_fade_alpha - step, target_alpha)
		queue_redraw()


	func _draw() -> void:
		if _fade_alpha <= 0.0:
			return
		var a: float = clampf(_fade_alpha, 0.0, 1.0)
		var speed_mps: float = _current_speed_mps()
		var max_speed: float = maxf(GameConfig.max_speed, 0.001)
		var speed_ratio: float = clampf(speed_mps / max_speed, 0.0, 1.0)
		var origin: Vector2 = _panel_origin()
		var panel_rect: Rect2 = Rect2(origin, Vector2(PANEL_WIDTH, PANEL_HEIGHT))
		draw_rect(panel_rect, _with_alpha(BG_COLOR, a), true)
		var font: Font = get_theme_default_font()
		var value_text: String = "%.1f" % speed_mps
		var value_pos: Vector2 = Vector2(origin.x + CONTENT_INSET_X, origin.y + CONTENT_TOP)
		draw_string(font, value_pos, value_text, HORIZONTAL_ALIGNMENT_LEFT, 0.0, VALUE_FONT_SIZE, _with_alpha(VALUE_COLOR, a))
		var value_size: Vector2 = font.get_string_size(value_text, HORIZONTAL_ALIGNMENT_LEFT, 0.0, VALUE_FONT_SIZE)
		var unit_pos_x: float = value_pos.x + value_size.x + UNIT_GAP
		var unit_pos_y: float = origin.y + CONTENT_TOP + (float(VALUE_FONT_SIZE) - float(UNIT_FONT_SIZE)) * 0.5
		draw_string(font, Vector2(unit_pos_x, unit_pos_y), SPEED_UNIT, HORIZONTAL_ALIGNMENT_LEFT, 0.0, UNIT_FONT_SIZE, _with_alpha(UNIT_COLOR, a))
		var bar_x: float = origin.x + CONTENT_INSET_X
		var bar_w: float = PANEL_WIDTH - CONTENT_INSET_X * 2.0
		var bar_y: float = origin.y + PANEL_HEIGHT - BAR_BOTTOM_MARGIN - BAR_TRACK_HEIGHT
		draw_rect(Rect2(bar_x, bar_y, bar_w, BAR_TRACK_HEIGHT), _with_alpha(BAR_BG_COLOR, a), true)
		var fill_w: float = maxf(bar_w * speed_ratio, 0.0)
		if fill_w > 0.0:
			draw_rect(Rect2(bar_x, bar_y, fill_w, BAR_TRACK_HEIGHT), _with_alpha(BAR_FILL_COLOR, a), true)


	func _with_alpha(color: Color, a: float) -> Color:
		return Color(color.r, color.g, color.b, color.a * a)


	func _panel_origin() -> Vector2:
		var view_h: float = maxf(size.y, PANEL_HEIGHT + MARGIN)
		return Vector2(MARGIN, view_h - PANEL_HEIGHT - MARGIN)


	func _current_speed_mps() -> float:
		if _vehicle == null or not is_instance_valid(_vehicle):
			return 0.0
		var state: RefCounted = _vehicle.call("get_state")
		if state == null:
			return 0.0
		return clampf(float(state.call("speed")), 0.0, GameConfig.max_speed)
