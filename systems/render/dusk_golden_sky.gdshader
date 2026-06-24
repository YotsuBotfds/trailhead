shader_type sky;

// Render-only golden-hour dusk sky for lower Zion (zionfid/sky lane).
// Replaces the dusk PhysicalSkyMaterial with a richer, art-directed sky: a
// three-stop zenith->horizon gradient (deep blue zenith, soft cyan mid, warm
// peach/gold horizon band), a believable sun disk + aureole placed at the real
// GoldenHourSun direction, and a subtle wind-stretched cirrus band.
//
// DETERMINISM: the gradient, sun glow, and cirrus are pure functions of EYEDIR.
// There is no per-frame clock input, no frame history, and no RNG seeding — so
// the sky radiance cubemap converges once and stays stable frame-to-frame,
// matching the static mood architecture and staying safe for the headless sim
// runner.
//
// DE-ORANGE PRESERVATION: the palette is blue-dominant (a deep-blue zenith over
// most of the dome, with the warm color confined to a thin horizon band + a
// localized sun aureole). Because ambient_light_source = BG samples this sky
// for canyon shadow-fill, keeping the warm contribution to a small solid angle
// is what holds the cool-shadow / de-orange direction
// (see planning/zion-art-direction-bible.md §4). Zenith/horizon/ground colors
// are fed from the existing GameConfig dusk_sky_* values so the blue zenith is
// never re-warmed.
//
// Color uniforms are plain vec3 (no source_color hint): the host passes linear
// Vector3 values directly, so the art-bible linear colors are used verbatim
// with no sRGB double-conversion. COLOR is authored in linear space (AgX pipeline).

uniform vec3 zenith_color  = vec3(0.18, 0.33, 0.64);  // deep blue (cool half of the complement)
uniform vec3 mid_color     = vec3(0.32, 0.55, 0.72);  // soft cyan middle band
uniform vec3 horizon_color = vec3(0.86, 0.63, 0.38);  // warm peach/gold horizon band
uniform vec3 ground_color  = vec3(0.36, 0.34, 0.31);  // muted fill below the horizon
uniform vec3 sun_color     = vec3(1.00, 0.80, 0.52);  // bright gold sun disk + halo
uniform vec3 cirrus_color  = vec3(0.82, 0.78, 0.72);  // pale warm-white, high sun-lit cloud

uniform vec3 sun_direction = vec3(0.0, 1.0, 0.0);     // world-space, set from GoldenHourSun basis.z
uniform float sun_disk_scale     = 1.7;               // matches PhysicalSkyMaterial dusk disk
uniform float sun_halo_strength  = 0.55;              // broad warm aureole around the sun
uniform float horizon_band_width = 0.34;              // elevation span of the warm horizon band
uniform float cirrus_coverage    = 0.62;              // threshold (higher = less cloud)
uniform float cirrus_intensity   = 0.16;              // peak opacity of the streaks
uniform float energy_multiplier  = 1.20;              // overall sky energy (was PhysicalSky 1.22)
uniform float dither_strength    = 0.0035;            // subtle direction-locked debanding noise
uniform float cirrus_angle       = -0.42;             // wind-streak rotation in sky UV space
uniform float cirrus_wispiness   = 0.72;              // higher = finer, more separated strands
uniform float zion_cobalt_amber_strength = 1.0;       // 0.0 = previous sky, 1.0 = tighter Zion cobalt/amber tune

const float SKY_PI = 3.14159265359;
const float SKY_TAU = 6.28318530718;
const vec3 ZION_COBALT_ZENITH = vec3(0.105, 0.245, 0.600);
const vec3 ZION_AMBER_HORIZON = vec3(0.960, 0.620, 0.300);
const float ZION_HORIZON_WIDTH_SCALE = 0.50;
const float ZION_HORIZON_WIDTH_MIN = 0.085;
const float ZION_HORIZON_WIDTH_MAX = 0.160;
const float ZION_AMBER_RIM_INTENSITY = 0.055;
const float ZION_COBALT_CAP_BLEND = 0.10;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
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

vec2 rotate2(vec2 p, float angle) {
	float s = sin(angle);
	float c = cos(angle);
	return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}

float direction_dither(vec3 dir) {
	vec2 uv = sky_uv(dir);
	vec2 cell = floor(uv * vec2(2048.0, 1024.0));
	return hash21(cell) - 0.5;
}

// Directional, high-altitude cirrus: broad veil noise broken into thin
// wind-stretched strands. The existing coverage/intensity uniforms still own
// how much cloud is visible and how strongly it tints the sky.
float cirrus_pattern(vec3 dir, float height) {
	vec2 uv = sky_uv(dir);
	uv = (uv - vec2(0.5, 0.64)) * vec2(2.2, 1.25);
	uv = rotate2(uv, cirrus_angle);

	vec2 base_uv = vec2(uv.x * 2.0, uv.y * 12.0);
	float shear = value_noise(vec2(uv.x * 0.85, uv.y * 1.8) + vec2(3.7, 8.1)) - 0.5;
	base_uv.y += shear * 2.4;

	float broad = value_noise(base_uv * vec2(0.62, 0.18) + vec2(12.4, 2.7));
	float streak = value_noise(base_uv + vec2(5.1, 31.4));
	float fine = value_noise(base_uv * vec2(2.25, 1.7) + vec2(42.0, 17.0));
	float strand = 1.0 - abs(streak * 2.0 - 1.0);
	strand = pow(strand, mix(2.2, 5.0, clamp(cirrus_wispiness, 0.0, 1.0)));

	float veil = broad * 0.38 + strand * 0.42 + fine * 0.20;
	float altitude_mask = smoothstep(0.18, 0.42, height) * (1.0 - smoothstep(0.86, 1.0, height));
	float coverage_mask = smoothstep(cirrus_coverage, cirrus_coverage + 0.18, veil);
	float feather = mix(0.48, 1.0, smoothstep(0.24, 0.88, strand));
	return coverage_mask * feather * altitude_mask;
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float h = clamp(dir.y, -1.0, 1.0);
	float up = clamp(h, 0.0, 1.0);
	float zion_tune = clamp(zion_cobalt_amber_strength, 0.0, 1.0);
	float base_horizon_width = max(horizon_band_width, 0.001);
	float zion_horizon_width = min(base_horizon_width, clamp(base_horizon_width * ZION_HORIZON_WIDTH_SCALE, ZION_HORIZON_WIDTH_MIN, ZION_HORIZON_WIDTH_MAX));
	float active_horizon_width = mix(base_horizon_width, zion_horizon_width, zion_tune);
	vec3 active_zenith_color = mix(zenith_color, ZION_COBALT_ZENITH, zion_tune);
	vec3 active_horizon_color = mix(horizon_color, ZION_AMBER_HORIZON, zion_tune * 0.65);

	// Smooth Rayleigh-ish ramp: peach/gold at the horizon, clean cyan through
	// the lower dome, and a genuinely blue zenith for cool canyon shadow fill.
	float horizon_t = 1.0 - smoothstep(0.0, active_horizon_width, up);
	vec3 lower_dome = mix(active_horizon_color, mid_color, smoothstep(0.0, active_horizon_width, up));
	vec3 upper_dome = mix(mid_color, active_zenith_color, smoothstep(0.24, 1.0, pow(up, 0.72)));
	vec3 col = mix(lower_dome, upper_dome, smoothstep(0.10, 0.72, up));
	col += active_horizon_color * horizon_t * mix(0.035, 0.045, zion_tune);
	col += mid_color * smoothstep(0.18, 0.95, up) * mix(0.025, 0.016, zion_tune);
	float amber_rim = (1.0 - smoothstep(0.0, max(active_horizon_width * 0.38, 0.001), up)) * smoothstep(-0.012, 0.024, h);
	col += active_horizon_color * amber_rim * zion_tune * ZION_AMBER_RIM_INTENSITY;
	col = mix(col, active_zenith_color, smoothstep(0.50, 1.0, up) * zion_tune * ZION_COBALT_CAP_BLEND);
	// Below the horizon, fall to a muted ground color so the lower hemisphere
	// (ground reflections / fill) stays neutral instead of glowing warm.
	col = mix(col, ground_color, 1.0 - smoothstep(-0.25, 0.0, h));

	// Sun: angular disk, soft low-horizon aureole, and a cooler outer halo so
	// the glow warms the canyon edge without turning the whole dome orange.
	vec3 sun_dir = normalize(sun_direction);
	float sd = clamp(dot(dir, sun_dir), -1.0, 1.0);
	float sun_angle = sqrt(max(0.0, 2.0 - 2.0 * sd));
	float disk_radius = clamp(0.0048 * max(sun_disk_scale, 0.05), 0.0025, 0.030);
	float sun_above_horizon = smoothstep(-0.04, 0.04, sun_dir.y);
	float view_above_horizon = smoothstep(-0.015, 0.018, h);
	float disk = (1.0 - smoothstep(disk_radius * 0.65, disk_radius, sun_angle)) * sun_above_horizon * view_above_horizon;
	float limb = (1.0 - smoothstep(disk_radius, disk_radius * 2.7, sun_angle)) * sun_above_horizon * view_above_horizon;
	float inner_halo = 1.0 - smoothstep(disk_radius * 1.8, 0.075, sun_angle);
	float outer_halo = 1.0 - smoothstep(0.06, 0.38, sun_angle);
	float horizon_focus = 1.0 - smoothstep(0.10, 0.70, up);
	float low_sun = 1.0 - smoothstep(0.06, 0.46, max(sun_dir.y, 0.0));
	float halo = (inner_halo * 0.52 + outer_halo * 0.22) * sun_halo_strength;
	halo *= (0.65 + low_sun * 0.35) * (0.45 + horizon_focus * 0.55);
	vec3 inner_halo_color = mix(mid_color, sun_color, 0.42);
	vec3 outer_halo_color = mix(mid_color, active_horizon_color, 0.45);
	col += outer_halo_color * halo * 0.45;
	col += inner_halo_color * halo * 0.55;
	col += sun_color * (disk * 1.65 + limb * 0.32);

	// Subtle high-altitude cirrus, warm where it faces the sun and cooler as it
	// thins into the blue dome.
	if (h > 0.16) {
		float cloud = cirrus_pattern(dir, up);
		float sun_lit = smoothstep(0.0, 0.85, sd * 0.5 + 0.5);
		vec3 cloud_color = mix(mix(mid_color, cirrus_color, 0.55), cirrus_color, sun_lit);
		col = mix(col, cloud_color, cloud * cirrus_intensity);
		col += cirrus_color * cloud * cirrus_intensity * 0.10;
	}

	col += vec3(direction_dither(dir) * dither_strength);
	COLOR = max(col, vec3(0.0)) * energy_multiplier;
}
