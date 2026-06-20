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

// Elongated fBm so the cloud reads as wind-stretched cirrus streaks, not blobs.
// Project the view direction onto an overhead plane (divide by elevation) and
// stretch one axis to fake the linear jet-stream grain. Only called above the
// horizon band, so the max(dir.y, 0.08) guard never divides by ~0.
float cirrus_noise(vec3 dir) {
	vec2 uv = vec2(dir.x, dir.z) / max(dir.y, 0.08);
	uv *= vec2(2.4, 7.5);
	float n = value_noise(uv) * 0.60;
	n += value_noise(uv * 2.07 + 11.3) * 0.27;
	n += value_noise(uv * 4.31 + 41.7) * 0.13;
	return n;
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float h = clamp(dir.y, -1.0, 1.0);

	// Three-stop gradient: warm horizon band -> soft cyan mid -> deep blue zenith.
	float horizon_t = 1.0 - smoothstep(0.0, horizon_band_width, max(h, 0.0));
	vec3 col = mix(mid_color, zenith_color, smoothstep(0.28, 0.82, h));
	col = mix(col, horizon_color, horizon_t);
	// Below the horizon, fall to a muted ground color so the lower hemisphere
	// (ground reflections / fill) stays neutral instead of glowing warm.
	col = mix(col, ground_color, 1.0 - smoothstep(-0.25, 0.0, h));

	// Sun: a tight warm disk + a broad aureole, placed at the real sun direction.
	vec3 sun_dir = normalize(sun_direction);
	float sd = max(dot(dir, sun_dir), 0.0);
	float disk_radius = clamp(0.0024 / max(sun_disk_scale, 0.05), 0.0008, 0.02);
	float disk = smoothstep(1.0 - disk_radius * 2.0, 1.0 - disk_radius, sd);
	float halo = pow(sd, 12.0) * 0.45 + pow(sd, 3.2) * 0.18;
	col += sun_color * (disk + halo * sun_halo_strength);

	// Subtle high-altitude cirrus: only above the warm band, fading out at zenith.
	if (h > 0.28) {
		float streak = cirrus_noise(dir);
		float mask = smoothstep(0.28, 0.55, h) * (1.0 - smoothstep(0.8, 1.0, h));
		float cloud = smoothstep(cirrus_coverage, cirrus_coverage + 0.22, streak) * mask;
		col = mix(col, cirrus_color, cloud * cirrus_intensity);
	}

	COLOR = col * energy_multiplier;
}
