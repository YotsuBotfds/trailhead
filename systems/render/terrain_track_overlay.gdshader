shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

uniform sampler2D track_rt : source_color, repeat_disable, filter_linear;
uniform vec2 track_bounds_min = vec2(-6.1, -10.6);
uniform vec2 track_bounds_max = vec2(6.1, 1.6);
uniform float track_darkening : hint_range(0.0, 1.0) = 0.34;
uniform float rut_darkening : hint_range(0.0, 1.0) = 0.25;

varying vec2 world_xz;

void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	vec2 track_uv = (world_xz - track_bounds_min) / (track_bounds_max - track_bounds_min);
	if (track_uv.x < 0.0 || track_uv.x > 1.0 || track_uv.y < 0.0 || track_uv.y > 1.0) {
		ALPHA = 0.0;
	} else {
		vec4 track_sample = texture(track_rt, track_uv);
		float track_strength = clamp(track_sample.r, 0.0, 1.0);
		float rut_strength = clamp(track_sample.g, 0.0, 1.0);
		float wet_strength = clamp(track_sample.b, 0.0, 1.0);
		float combined = clamp(track_strength + rut_strength * 0.65, 0.0, 1.0);
		vec3 dry_track = vec3(0.085, 0.060, 0.035);
		vec3 wet_track = vec3(0.035, 0.028, 0.020);
		ALBEDO = mix(dry_track, wet_track, wet_strength);
		ALPHA = combined * clamp(track_darkening + rut_strength * rut_darkening, 0.0, 1.0);
		ROUGHNESS = mix(0.92, 0.48, wet_strength);
	}
}
