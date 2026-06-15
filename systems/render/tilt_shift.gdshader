shader_type canvas_item;

uniform float center : hint_range(0.0, 1.0) = 0.55;
uniform float band : hint_range(0.0, 0.5) = 0.22;
uniform float blur : hint_range(0.0, 6.0) = 2.5;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

void fragment() {
	float distance_from_band = abs(UV.y - center);
	float blend = clamp((distance_from_band - band) / max(band, 0.0001), 0.0, 1.0);
	COLOR = textureLod(screen_texture, SCREEN_UV, blur * blend);
}
