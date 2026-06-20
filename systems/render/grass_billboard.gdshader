shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_schlick_ggx;
uniform vec4 blade_base_color : source_color = vec4(0.07, 0.18, 0.055, 1.0);
uniform vec4 blade_tip_color : source_color = vec4(0.48, 0.66, 0.23, 1.0);
uniform float blade_height_reference = 0.42;
uniform float wind_strength = 0.012;
uniform float wind_speed = 0.65;
uniform float wind_time_factor = 1.0;
uniform vec4 backlight_color : source_color = vec4(1.0, 0.62, 0.30, 1.0);
uniform float backlight_energy = 0.32;
uniform vec3 vehicle_world_pos = vec3(0.0, 0.0, 0.0);
uniform float crush_radius = 1.2;
uniform float crush_strength = 0.75;
uniform float blade_half_width = 0.055;
uniform float blade_edge_softness = 0.025;
uniform float blade_alpha_scissor = 0.4;
uniform float canopy_cutout = 0.0;
uniform float canopy_alpha_scissor = 0.5;
varying float blade_height;
varying float tip_mix_shift;
varying vec2 leaf_uv;

// Single vertical grass blade contribution for the procedural cutout mask.
// `center` is the blade's UV.x position, `tip` its max height (0 base, 1 card top).
// `h` is the fragment's height (1.0 - UV.y, so 0 at the card base, 1 at the top).
// The blade is a soft vertical strip that anchors softly at the base, tapers to a
// point at `tip`, and is zero above it, so clusters of these read as discrete blades.
float blade_contribution(float center, float tip, float h, float uvx, float base_half, float edge_soft) {
	float within = smoothstep(0.0, 0.05, h) * smoothstep(tip, max(tip - 0.15, 0.0), h);
	float taper = clamp(h / max(tip, 0.001), 0.0, 1.0);
	float hw = base_half * (1.0 - taper);
	float d = abs(uvx - center);
	return smoothstep(hw + edge_soft, hw, d) * within;
}

void vertex() {
	leaf_uv = UV;
	blade_height = smoothstep(0.0, blade_height_reference, VERTEX.y);
	tip_mix_shift = INSTANCE_CUSTOM.w;
	float wind_phase = INSTANCE_CUSTOM.y * TAU;
	float wind_time = TIME * wind_speed * wind_time_factor;
	float sway = sin(wind_phase + wind_time);
	float flutter = sin(wind_phase * 1.73 + wind_time * 1.47 + INSTANCE_CUSTOM.z * 2.91);
	float gust = 0.88 + sin(wind_time * 0.37 + INSTANCE_CUSTOM.w * TAU) * 0.12;
	float bend = (sway * 0.72 + flutter * 0.28) * gust * wind_strength * blade_height * blade_height * INSTANCE_CUSTOM.x;
	VERTEX.x += bend;
	VERTEX.z += bend * (INSTANCE_CUSTOM.z * 0.7 - 0.35);
	vec3 vehicle_local_pos = (inverse(MODEL_MATRIX) * vec4(vehicle_world_pos, 1.0)).xyz;
	vec2 crush_delta = VERTEX.xz - vehicle_local_pos.xz;
	float crush_distance = length(crush_delta);
	float crush_falloff = 1.0 - smoothstep(0.0, max(crush_radius, 0.001), crush_distance);
	float crush_tip_weight = blade_height * blade_height;
	vec2 crush_dir = crush_distance > 0.001 ? crush_delta / crush_distance : vec2(1.0, 0.0);
	float crush_amount = crush_falloff * crush_tip_weight * max(crush_strength, 0.0);
	VERTEX.xz += crush_dir * crush_amount * 0.18;
	VERTEX.y -= crush_amount * 0.20;
}
void fragment() {
	float tip_mix = smoothstep(0.0, 1.0, blade_height + (tip_mix_shift - 0.5) * 0.22);
	vec3 blade_color = mix(blade_base_color.rgb, blade_tip_color.rgb, tip_mix);
	blade_color = mix(blade_color, blade_base_color.rgb * 0.72, (1.0 - blade_height) * 0.24);
	ALBEDO = blade_color * COLOR.rgb;
	ROUGHNESS = 0.86;
	SPECULAR = 0.16;
	BACKLIGHT = backlight_color.rgb * backlight_energy * (0.35 + blade_height * 0.65) * COLOR.rgb;
	// Procedural grass-blade cutout: turn the solid cross-quad into a cluster of a few
	// tapering vertical blades. `h` is 0 at the card base and 1 at the top (UV.y is
	// inverted relative to mesh height). ALPHA + ALPHA_SCISSOR_THRESHOLD keep the card
	// in the opaque pass (depth_prepass_alpha) — no transparency sort, deterministic.
	float h = 1.0 - UV.y;
	float edge_fade = smoothstep(0.0, 0.10, UV.x) * smoothstep(1.0, 0.90, UV.x);
	float mask = 0.0;
	mask = max(mask, blade_contribution(0.22, 0.92, h, UV.x, blade_half_width, blade_edge_softness));
	mask = max(mask, blade_contribution(0.40, 1.00, h, UV.x, blade_half_width, blade_edge_softness));
	mask = max(mask, blade_contribution(0.60, 0.96, h, UV.x, blade_half_width, blade_edge_softness));
	mask = max(mask, blade_contribution(0.78, 0.88, h, UV.x, blade_half_width, blade_edge_softness));
	ALPHA = mask * edge_fade;
	ALPHA_SCISSOR_THRESHOLD = blade_alpha_scissor;
	if (canopy_cutout > 0.0) {
		vec2 c = leaf_uv - vec2(0.5, 0.45);
		float r = length(c * vec2(1.0, 0.85));
		float lobes = 0.5 + 0.5 * sin(atan(c.y, c.x) * 5.0 + leaf_uv.y * 6.0);
		float canopy = smoothstep(0.62, 0.30, r) * mix(0.7, 1.0, lobes);
		float trunk_gap = smoothstep(0.0, 0.18, abs(leaf_uv.x - 0.5));
		float leaf_mask = mix(1.0, max(canopy, step(0.78, leaf_uv.y) * (1.0 - trunk_gap)), canopy_cutout);
		ALPHA = leaf_mask;
		ALPHA_SCISSOR_THRESHOLD = canopy_alpha_scissor;
	}
}
