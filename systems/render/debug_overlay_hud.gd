class_name DebugOverlayHud
extends CanvasLayer

const LAYER: int = 30

var _host: Node = null
var _panel: Control = null


func _ready() -> void:
	layer = LAYER
	_panel = _DebugOverlayPanel.new()
	_panel.name = "DebugOverlayPanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_panel)
	_panel.configure(_host)


func configure(host: Node) -> void:
	_host = host
	if _panel != null:
		_panel.configure(_host)


class _DebugOverlayPanel:
	extends Control

	const MARGIN: float = 14.0
	const PANEL_WIDTH: float = 340.0
	const PANEL_HEIGHT: float = 252.0
	const PADDING: float = 10.0
	const LINE_HEIGHT: float = 15.0
	const FONT_SIZE: int = 12
	const TITLE_FONT_SIZE: int = 13
	const GRAPH_HEIGHT: float = 34.0
	const GRAPH_GAP: float = 2.0
	const GRAPH_MS_MAX: float = 50.0
	const MB_DIVISOR: float = 1048576.0
	const BG_COLOR: Color = Color(0.02, 0.025, 0.025, 0.72)
	const BORDER_COLOR: Color = Color(0.72, 0.82, 0.80, 0.34)
	const TEXT_COLOR: Color = Color(0.88, 0.94, 0.90, 0.92)
	const MUTED_COLOR: Color = Color(0.58, 0.68, 0.64, 0.88)
	const GOOD_COLOR: Color = Color(0.48, 0.86, 0.62, 0.88)
	const WARN_COLOR: Color = Color(1.0, 0.68, 0.30, 0.94)
	const HITCH_COLOR: Color = Color(1.0, 0.16, 0.12, 0.96)
	const CHUNK_COLOR: Color = Color(0.20, 0.72, 1.0, 0.98)

	var _host: Node = null
	var _frame_ms_samples: Array[float] = []
	var _last_cell: Vector2i = Vector2i(2147483647, 2147483647)
	var _chunk_flash_seconds: float = 0.0
	var _hitch_flash_seconds: float = 0.0
	# Viewport-relative scale: recomputed each frame from the shorter viewport
	# axis vs debug_overlay_reference_resolution. All dimensions/fonts in _draw
	# multiply the BASE constants by this so the panel reads at a consistent
	# size on 1080p/1440p/4K instead of the old hard pixels (tiny at 4K).
	var _scale: float = 1.0


	func configure(host: Node) -> void:
		_host = host
		queue_redraw()


	func _process(delta: float) -> void:
		if not visible:
			return
		_update_scale()
		var frame_ms: float = delta * 1000.0
		_frame_ms_samples.append(frame_ms)
		var sample_count: int = maxi(GameConfig.debug_overlay_frame_sample_count, 1)
		while _frame_ms_samples.size() > sample_count:
			_frame_ms_samples.pop_front()
		if frame_ms >= GameConfig.debug_overlay_hitch_ms:
			_hitch_flash_seconds = GameConfig.debug_overlay_hitch_flash_seconds
		else:
			_hitch_flash_seconds = maxf(_hitch_flash_seconds - delta, 0.0)
		var current_cell: Vector2i = _stream_current_cell()
		if _last_cell != Vector2i(2147483647, 2147483647) and current_cell != _last_cell:
			_chunk_flash_seconds = GameConfig.debug_overlay_chunk_flash_seconds
		_last_cell = current_cell
		_chunk_flash_seconds = maxf(_chunk_flash_seconds - delta, 0.0)
		queue_redraw()


	func _update_scale() -> void:
		var viewport: Viewport = get_viewport()
		if viewport == null:
			_scale = 1.0
			return
		var ref: int = maxi(GameConfig.debug_overlay_reference_resolution, 1)
		var shorter: float = minf(float(viewport.size.x), float(viewport.size.y))
		# Clamp to [0.75, 2.5] so the overlay never gets unreadably small or huge.
		_scale = clampf(shorter / float(ref), 0.75, 2.5)


	func _draw() -> void:
		if not visible:
			return
		var s: float = _scale
		var margin: float = MARGIN * s
		var padding: float = PADDING * s
		var panel_w: float = PANEL_WIDTH * s
		var panel_h: float = PANEL_HEIGHT * s
		var line_h: float = LINE_HEIGHT * s
		var font_size: int = maxi(int(roundf(float(FONT_SIZE) * s)), 8)
		var title_font_size: int = maxi(int(roundf(float(TITLE_FONT_SIZE) * s)), 8)
		var graph_h: float = GRAPH_HEIGHT * s
		var origin: Vector2 = Vector2(margin, margin)
		var rect: Rect2 = Rect2(origin, Vector2(panel_w, panel_h))
		var bg: Color = HITCH_COLOR if _hitch_flash_seconds > 0.0 else BG_COLOR
		draw_rect(rect, bg, true)
		draw_rect(rect, BORDER_COLOR, false, 1.0)
		var font: Font = get_theme_default_font()
		var y: float = origin.y + padding
		draw_string(font, Vector2(origin.x + padding, y), "DEBUG  F3", HORIZONTAL_ALIGNMENT_LEFT, 0.0, title_font_size, TEXT_COLOR)
		y += line_h + 3.0 * s
		var frame_ms: float = _latest_frame_ms()
		var fps: int = Engine.get_frames_per_second()
		var perf_color: Color = HITCH_COLOR if frame_ms >= GameConfig.debug_overlay_hitch_ms else TEXT_COLOR
		draw_string(font, Vector2(origin.x + padding, y), "fps " + str(fps) + "   frame " + _format_float(frame_ms, 2) + " ms", HORIZONTAL_ALIGNMENT_LEFT, 0.0, font_size, perf_color)
		y += line_h
		_draw_frame_graph(Rect2(origin.x + padding, y, panel_w - padding * 2.0, graph_h))
		y += graph_h + 8.0 * s
		var cell: Vector2i = _stream_current_cell()
		var cell_color: Color = CHUNK_COLOR if _chunk_flash_seconds > 0.0 else TEXT_COLOR
		draw_string(font, Vector2(origin.x + padding, y), "cell " + _cell_text(cell) + "   stream tick " + str(_stream_tick()), HORIZONTAL_ALIGNMENT_LEFT, 0.0, font_size, cell_color)
		y += line_h
		draw_string(font, Vector2(origin.x + padding, y), "active " + str(_active_count()) + "   ready " + str(_ready_count()) + "   prefetch " + str(_prefetch_ready_count()), HORIZONTAL_ALIGNMENT_LEFT, 0.0, font_size, TEXT_COLOR)
		y += line_h + 3.0 * s
		draw_string(font, Vector2(origin.x + padding, y), "draws " + str(_monitor_int(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)) + "   prims " + str(_monitor_int(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)), HORIZONTAL_ALIGNMENT_LEFT, 0.0, font_size, TEXT_COLOR)
		y += line_h
		draw_string(font, Vector2(origin.x + padding, y), "objects " + str(_monitor_int(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)) + "   materials/tex " + _format_float(_monitor_mb(Performance.RENDER_TEXTURE_MEM_USED), 1) + " MB", HORIZONTAL_ALIGNMENT_LEFT, 0.0, font_size, TEXT_COLOR)
		y += line_h
		draw_string(font, Vector2(origin.x + padding, y), "video " + _format_float(_monitor_mb(Performance.RENDER_VIDEO_MEM_USED), 1) + " MB   tex " + _format_float(_monitor_mb(Performance.RENDER_TEXTURE_MEM_USED), 1) + " MB", HORIZONTAL_ALIGNMENT_LEFT, 0.0, font_size, TEXT_COLOR)
		y += line_h
		draw_string(font, Vector2(origin.x + padding, y), "buffers " + _format_float(_monitor_mb(Performance.RENDER_BUFFER_MEM_USED), 1) + " MB", HORIZONTAL_ALIGNMENT_LEFT, 0.0, font_size, MUTED_COLOR)
		y += line_h + 3.0 * s
		draw_string(font, Vector2(origin.x + padding, y), "mood " + _mood_text() + "   camera " + _camera_text(), HORIZONTAL_ALIGNMENT_LEFT, 0.0, font_size, GOOD_COLOR)
		if _chunk_flash_seconds > 0.0:
			draw_rect(Rect2(origin.x + panel_w - padding - 52.0 * s, origin.y + padding, 52.0 * s, 5.0 * s), CHUNK_COLOR, true)


	func _draw_frame_graph(rect: Rect2) -> void:
		draw_rect(rect, Color(0.0, 0.0, 0.0, 0.32), true)
		if _frame_ms_samples.is_empty():
			return
		var sample_count: int = _frame_ms_samples.size()
		var bar_w: float = maxf((rect.size.x - GRAPH_GAP * _scale * float(sample_count - 1)) / float(sample_count), 1.0)
		var x: float = rect.position.x
		for sample in _frame_ms_samples:
			var ratio: float = clampf(sample / GRAPH_MS_MAX, 0.0, 1.0)
			var h: float = maxf(rect.size.y * ratio, 1.0)
			var color: Color = HITCH_COLOR if sample >= GameConfig.debug_overlay_hitch_ms else WARN_COLOR if sample >= 16.7 else GOOD_COLOR
			draw_rect(Rect2(x, rect.position.y + rect.size.y - h, bar_w, h), color, true)
			x += bar_w + GRAPH_GAP * _scale


	func _latest_frame_ms() -> float:
		if _frame_ms_samples.is_empty():
			return 0.0
		return _frame_ms_samples[_frame_ms_samples.size() - 1]


	func _streamer() -> Node:
		return get_node_or_null("/root/TileStreamer")


	func _stream_current_cell() -> Vector2i:
		var streamer: Node = _streamer()
		if streamer == null or not streamer.has_method("current_cell"):
			return Vector2i.ZERO
		return streamer.call("current_cell") as Vector2i


	func _stream_tick() -> int:
		var streamer: Node = _streamer()
		if streamer == null or not streamer.has_method("current_stream_tick"):
			return 0
		return int(streamer.call("current_stream_tick"))


	func _active_count() -> int:
		var streamer: Node = _streamer()
		if streamer == null or not streamer.has_method("active_cells"):
			return 0
		var cells: Array = streamer.call("active_cells") as Array
		return cells.size()


	func _ready_count() -> int:
		var streamer: Node = _streamer()
		if streamer == null or not streamer.has_method("ready_cells"):
			return 0
		var cells: Array = streamer.call("ready_cells") as Array
		return cells.size()


	func _prefetch_ready_count() -> int:
		return maxi(_ready_count() - _active_count(), 0)


	func _monitor_int(monitor: Performance.Monitor) -> int:
		return int(Performance.get_monitor(monitor))


	func _monitor_mb(monitor: Performance.Monitor) -> float:
		return float(Performance.get_monitor(monitor)) / MB_DIVISOR


	func _mood_text() -> String:
		if _host == null or not is_instance_valid(_host):
			return "unknown"
		var mood: int = int(_host.get("_mood"))
		if mood == 1:
			return "dawn"
		if mood == 2:
			return "night"
		return "dusk"


	func _camera_text() -> String:
		if _host == null or not is_instance_valid(_host):
			return "unknown"
		if bool(_host.get("_cinematic_tour_active")):
			return "tour"
		var mode: int = int(_host.get("_camera_mode"))
		if mode == 1:
			return "orbit"
		if mode == 2:
			return "fpv"
		return "chase"


	func _cell_text(cell: Vector2i) -> String:
		return "(" + str(cell.x) + "," + str(cell.y) + ")"


	func _format_float(value: float, decimals: int) -> String:
		return "%.*f" % [decimals, value]
