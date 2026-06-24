shader_type sky;

uniform vec3 horizon_color : source_color = vec3(0.015, 0.028, 0.060);
uniform vec3 zenith_color : source_color = vec3(0.002, 0.006, 0.018);
uniform vec3 star_color : source_color = vec3(0.72, 0.84, 1.0);
uniform float star_density = 0.985;
uniform float star_intensity = 0.85;
uniform float moon_glow = 0.18;
uniform vec3 moon_color : source_color = vec3(0.30, 0.42, 0.62);
uniform vec3 moon_direction = vec3(-0.25, 0.72, -0.64);
uniform vec3 milky_way_color : source_color = vec3(0.18, 0.28, 0.46);
uniform float horizon_haze = 0.16;
uniform float twinkle_strength = 0.07;
uniform float twinkle_phase = 0.0;
uniform float milky_way_intensity = 0.10;
uniform float milky_way_width = 0.22;

const float SKY_PI = 3.14159265359;
const float SKY_TAU = 6.28318530718;

float hash21(vec2 value) {
	return fract(sin(dot(value, vec2(127.1, 311.7))) * 43758.5453123);
}

vec2 hash22(vec2 value) {
	vec2 dots = vec2(dot(value, vec2(269.5, 183.3)), dot(value, vec2(419.2, 371.9)));
	return fract(sin(dots) * 43758.5453123);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

vec2 sky_uv(vec3 dir) {
	float azimuth = atan(dir.z, dir.x) / SKY_TAU + 0.5;
	float elevation = asin(clamp(dir.y, -1.0, 1.0)) / SKY_PI + 0.5;
	return vec2(azimuth, elevation);
}

vec3 star_field(vec3 dir) {
	vec2 uv = sky_uv(dir);
	vec2 grid = vec2(900.0, 360.0);
	vec2 cell = floor(uv * grid);
	vec2 local = fract(uv * grid);

	float seed = hash21(cell);
	float present = step(star_density, seed);
	vec2 star_pos = mix(
			vec2(0.24, 0.24),
			vec2(0.76, 0.76),
			hash22(cell + vec2(19.0, 7.0))
	);
	float size_seed = hash21(cell + vec2(53.2, 17.1));
	float radius = mix(0.035, 0.16, pow(size_seed, 6.0));
	float dist = length((local - star_pos) * vec2(1.0, 1.35));
	float shape = 1.0 - smoothstep(radius * 0.35, radius, dist);

	float magnitude_seed = hash21(cell + vec2(91.7, 41.2));
	float magnitude = mix(0.20, 1.0, pow(magnitude_seed, 3.5));
	float rare_bright = smoothstep(0.995, 1.0, seed) * 1.15;
	float twinkle = 1.0 + sin(twinkle_phase + seed * SKY_TAU) * clamp(twinkle_strength, 0.0, 0.18);

	float temperature = hash21(cell + vec2(5.4, 72.8));
	vec3 warm_star = vec3(1.0, 0.82, 0.62);
	vec3 cool_star = vec3(0.62, 0.76, 1.0);
	vec3 tint = mix(warm_star, star_color, smoothstep(0.18, 0.74, temperature));
	tint = mix(tint, cool_star, smoothstep(0.86, 1.0, temperature) * 0.45);

	return tint * shape * present * (magnitude + rare_bright) * twinkle;
}

float milky_way(vec3 dir) {
	vec3 band_normal = normalize(vec3(0.30, 0.55, 0.78));
	float band_distance = abs(dot(dir, band_normal));
	float band = 1.0 - smoothstep(milky_way_width * 0.35, milky_way_width, band_distance);
	vec2 uv = sky_uv(dir);
	float broad = value_noise(uv * vec2(9.0, 4.0) + vec2(3.0, 11.0));
	float fine = value_noise(uv * vec2(28.0, 12.0) + vec2(17.0, 5.0));
	float dust = smoothstep(0.30, 0.78, broad * 0.62 + fine * 0.38);
	float altitude = smoothstep(0.08, 0.38, dir.y);
	return band * mix(0.48, 1.0, dust) * altitude * milky_way_intensity;
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float h = clamp(dir.y, -1.0, 1.0);
	float up = clamp(h, 0.0, 1.0);

	vec3 sky_color = mix(horizon_color, zenith_color, smoothstep(0.0, 1.0, pow(up, 0.72)));
	float low_haze = (1.0 - smoothstep(0.0, 0.32, up)) * smoothstep(-0.04, 0.05, h);
	sky_color += horizon_color * low_haze * horizon_haze;
	sky_color = mix(sky_color * 0.16, sky_color, smoothstep(-0.12, 0.02, h));

	if (h > 0.045) {
		float star_visibility = smoothstep(0.045, 0.22, h);
		vec3 stars = star_field(dir) * star_visibility * star_intensity;
		float galaxy = milky_way(dir) * star_visibility;
		sky_color += milky_way_color * galaxy;
		sky_color += stars;
	}

	vec3 moon_dir = normalize(moon_direction);
	float md = clamp(dot(dir, moon_dir), -1.0, 1.0);
	float moon_angle = sqrt(max(0.0, 2.0 - 2.0 * md));
	float moon_disk = 1.0 - smoothstep(0.008, 0.014, moon_angle);
	float moon_halo = 1.0 - smoothstep(0.035, 0.24, moon_angle);
	float moon_visible = smoothstep(0.0, 0.08, moon_dir.y) * smoothstep(-0.015, 0.02, h);
	sky_color += moon_color * (moon_disk * 0.35 + moon_halo * moon_glow) * moon_visible;

	COLOR = max(sky_color, vec3(0.0));
}
