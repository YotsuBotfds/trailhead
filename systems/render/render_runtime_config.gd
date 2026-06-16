extends RefCounted

const RENDER_MAX_FPS_META: StringName = &"trailhead_render_max_fps"
const FRAME_CAP_SKIP_USER_ARG: String = "--render-runtime-skip-frame-cap"


static func apply_to(host: Node) -> void:
	if host == null:
		return
	if DisplayServer.get_name() == "headless":
		host.set_meta(RENDER_MAX_FPS_META, 0)
		return
	if frame_cap_skip_requested():
		host.set_meta(RENDER_MAX_FPS_META, 0)
		return
	if not GameConfig.render_frame_cap_enabled:
		host.set_meta(RENDER_MAX_FPS_META, 0)
		return
	var target_max_fps: int = maxi(GameConfig.render_max_fps, 0)
	if target_max_fps <= 0:
		host.set_meta(RENDER_MAX_FPS_META, 0)
		return
	Engine.max_fps = target_max_fps
	host.set_meta(RENDER_MAX_FPS_META, target_max_fps)


static func frame_cap_skip_requested() -> bool:
	for arg in OS.get_cmdline_user_args():
		var text: String = String(arg)
		if text == FRAME_CAP_SKIP_USER_ARG:
			return true
	for arg in OS.get_cmdline_args():
		var text: String = String(arg)
		if text == "--fixed-fps" or text.begins_with("--fixed-fps="):
			return true
	return false
