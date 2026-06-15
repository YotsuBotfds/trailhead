shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

uniform vec4 stamp_color : source_color = vec4(0.35, 0.25, 0.0, 0.35);

void fragment() {
	vec2 centered_uv = UV * 2.0 - vec2(1.0);
	float radial = 1.0 - smoothstep(0.28, 1.0, length(centered_uv));
	float side_fade = 1.0 - smoothstep(0.62, 1.0, abs(centered_uv.x));
	float end_fade = 1.0 - smoothstep(0.70, 1.0, abs(centered_uv.y));
	float tread = smoothstep(0.82, 0.28, abs(centered_uv.x));
	float footprint = radial * side_fade * end_fade * mix(0.72, 1.0, tread);
	ALBEDO = stamp_color.rgb;
	ALPHA = stamp_color.a * footprint;
}
