shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

uniform vec4 stamp_color : source_color = vec4(0.35, 0.25, 0.0, 0.35);

void fragment() {
	// Centered UV: x spans the tire width, y runs along the contact length.
	vec2 p = UV * 2.0 - vec2(1.0);
	float ax = abs(p.x);
	float ay = abs(p.y);
	// Rounded contact-patch envelope: soft shoulder across the width, rounded ends.
	float side = 1.0 - smoothstep(0.70, 1.0, ax);
	float end = 1.0 - smoothstep(0.40, 1.0, ay);
	float envelope = side * end;
	// Tread lugs: two outer paddle bars + a softer center bar, parted by shallow grooves.
	// Reads as a tread line (darker/displaced) rather than a flat smear.
	float shoulder = 1.0 - smoothstep(0.0, 0.16, abs(ax - 0.40));
	float center = 1.0 - smoothstep(0.0, 0.18, ax);
	float tread = clamp(shoulder + center * 0.55, 0.0, 1.0);
	float footprint = envelope * mix(0.45, 1.0, tread);
	ALBEDO = stamp_color.rgb;
	ALPHA = stamp_color.a * footprint;
}
