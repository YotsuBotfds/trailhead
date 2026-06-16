shader_type spatial;
render_mode unshaded, cull_disabled;
instance uniform bool tagged = false;
uniform vec4 untagged_color : source_color = vec4(0.42, 0.33, 0.23, 1.0);
uniform vec4 tagged_color : source_color = vec4(1.0, 0.47, 0.11, 1.0);
void fragment() {
	vec4 color = tagged ? tagged_color : untagged_color;
	ALBEDO = color.rgb;
	ALPHA = color.a;
}
