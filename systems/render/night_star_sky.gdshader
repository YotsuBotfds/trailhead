shader_type sky;

uniform vec3 horizon_color : source_color = vec3(0.015, 0.028, 0.060);
uniform vec3 zenith_color : source_color = vec3(0.002, 0.006, 0.018);
uniform vec3 star_color : source_color = vec3(0.72, 0.84, 1.0);
uniform float star_density = 0.985;
uniform float star_intensity = 0.85;
uniform float moon_glow = 0.18;

float hash(vec2 value) {
	return fract(sin(dot(value, vec2(127.1, 311.7))) * 43758.5453123);
}

void sky() {
	float up_amount = clamp(EYEDIR.y * 0.5 + 0.5, 0.0, 1.0);
	vec3 sky_color = mix(horizon_color, zenith_color, up_amount);
	vec2 cell = floor(EYEDIR.xz * 720.0 + EYEDIR.y * 180.0);
	float star_seed = hash(cell);
	float star = smoothstep(star_density, 1.0, star_seed) * step(0.03, EYEDIR.y);
	float twinkle = hash(cell + vec2(17.0, 43.0));
	float star_energy = star * mix(0.35, 1.0, twinkle) * star_intensity;
	float moon = pow(max(dot(normalize(EYEDIR), normalize(vec3(-0.25, 0.72, -0.64))), 0.0), 96.0) * moon_glow;
	COLOR = sky_color + star_color * star_energy + vec3(0.30, 0.42, 0.62) * moon;
}
