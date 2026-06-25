shader_type canvas_item;
render_mode blend_mul;

uniform float vignette_active : hint_range(0.0, 1.0) = 0.0;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.18;
uniform float vignette_feather : hint_range(0.0, 1.0) = 0.55;
uniform vec4 vignette_warm_tint : source_color = vec4(1.0, 0.93, 0.82, 1.0);

void fragment() {
	float d = length(SCREEN_UV - vec2(0.5));
	float falloff = smoothstep(vignette_feather, 0.95, d);
	vec3 mul = mix(vec3(1.0), vignette_warm_tint.rgb * (1.0 - vignette_strength), falloff * vignette_active);
	COLOR = vec4(mul, 1.0);
}
