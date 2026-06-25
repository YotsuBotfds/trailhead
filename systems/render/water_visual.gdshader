shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform vec4 shallow_color : source_color = vec4(0.34, 0.27, 0.12, 1.0);
uniform vec4 deep_color : source_color = vec4(0.11, 0.105, 0.045, 1.0);
uniform float water_alpha : hint_range(0.0, 1.0) = 0.82;
uniform float depth_fade_distance : hint_range(0.001, 2.0) = 0.32;
uniform float foam_edge_width : hint_range(0.001, 0.5) = 0.14;
uniform float flow_speed : hint_range(0.0, 1.0) = 0.10;
uniform float wave_amplitude : hint_range(0.0, 0.1) = 0.010;
uniform float foam_normal_strength : hint_range(0.0, 1.0) = 0.14;
uniform float foam_normal_scale : hint_range(1.0, 64.0) = 14.0;
uniform float foam_normal_flow_speed : hint_range(0.0, 1.0) = 0.08;
uniform bool ssr_enabled = true;
uniform float ssr_intensity : hint_range(0.0, 1.0) = 0.20;
uniform int ssr_max_steps : hint_range(0, 32) = 8;
uniform float ssr_step_size : hint_range(0.005, 0.2) = 0.035;
uniform float ssr_thickness : hint_range(0.005, 0.3) = 0.08;
uniform float water_roughness : hint_range(0.0, 1.0) = 0.22;
uniform vec4 bed_tint_color : source_color = vec4(0.59, 0.46, 0.26, 1.0);
uniform float bed_tint_strength : hint_range(0.0, 1.0) = 0.50;
uniform float shallow_alpha : hint_range(0.0, 1.0) = 0.50;
uniform float downstream_flow_speed : hint_range(0.0, 0.5) = 0.10;
uniform vec4 foam_color : source_color = vec4(0.70, 0.63, 0.42, 1.0);
uniform float wetline_strength : hint_range(0.0, 1.0) = 0.28;
uniform float ripple_normal_strength : hint_range(0.0, 1.0) = 0.08;
uniform float ripple_normal_scale : hint_range(0.1, 8.0) = 1.60;
uniform float shoreline_softness : hint_range(0.001, 0.8) = 0.22;
uniform vec4 fresnel_glint_color : source_color = vec4(1.0, 0.74, 0.46, 1.0);
uniform float fresnel_glint_strength : hint_range(0.0, 0.5) = 0.12;
uniform vec2 flow_direction = vec2(0.0, 1.0);
uniform float foam_intensity : hint_range(0.0, 1.0) = 0.55;
uniform float ripple_tightness : hint_range(0.5, 16.0) = 3.5;
uniform vec4 ssr_sky_fallback_color : source_color = vec4(0.38, 0.54, 0.72, 1.0);
uniform float ssr_sky_fallback_strength : hint_range(0.0, 1.0) = 0.72;
uniform bool use_vertex_water_traits = false;

const int SSR_STEP_LIMIT = 32;
const float SSR_EDGE_FADE = 0.065;
const float FOAM_NORMAL_SAMPLE_RADIUS = 0.08;

varying vec2 world_xz;
varying vec2 downstream_dir;

float hash12(vec2 position) {
	return fract(sin(dot(position, vec2(127.1, 311.7))) * 43758.5453123);
}

float value_noise(vec2 position) {
	vec2 cell = floor(position);
	vec2 local = fract(position);
	vec2 smooth_local = local * local * (3.0 - 2.0 * local);
	float bottom_left = hash12(cell);
	float bottom_right = hash12(cell + vec2(1.0, 0.0));
	float top_left = hash12(cell + vec2(0.0, 1.0));
	float top_right = hash12(cell + vec2(1.0, 1.0));
	float bottom = mix(bottom_left, bottom_right, smooth_local.x);
	float top = mix(top_left, top_right, smooth_local.x);
	return mix(bottom, top, smooth_local.y);
}

float foam_noise_height(vec2 uv, float flow_time) {
	vec2 flow_a = vec2(flow_time, -flow_time * 0.62);
	vec2 flow_b = vec2(-flow_time * 0.43, flow_time * 0.81);
	float noise_a = value_noise(uv + flow_a);
	float noise_b = value_noise(uv.yx * 1.37 + flow_b);
	return noise_a * 0.62 + noise_b * 0.38;
}

vec2 foam_noise_gradient(vec2 uv, float flow_time) {
	vec2 sample_x = vec2(FOAM_NORMAL_SAMPLE_RADIUS, 0.0);
	vec2 sample_y = vec2(0.0, FOAM_NORMAL_SAMPLE_RADIUS);
	float height_x = foam_noise_height(uv + sample_x, flow_time) - foam_noise_height(uv - sample_x, flow_time);
	float height_y = foam_noise_height(uv + sample_y, flow_time) - foam_noise_height(uv - sample_y, flow_time);
	return vec2(height_x, height_y) / (FOAM_NORMAL_SAMPLE_RADIUS * 2.0);
}

vec2 flow_ripple_gradient(vec2 position, vec2 flow_dir, float flow_time) {
	vec2 side_dir = vec2(-flow_dir.y, flow_dir.x);
	float downstream_pos = dot(position, flow_dir) * ripple_normal_scale;
	float cross_pos = dot(position, side_dir) * ripple_normal_scale;
	// Primary downstream ripple layer
	float wave_a = sin(downstream_pos * 4.0 - flow_time * 8.0 + sin(cross_pos * 1.5) * 0.45);
	float wave_b = sin(downstream_pos * 7.5 + cross_pos * 2.2 - flow_time * 13.0);
	vec2 primary_grad = flow_dir * (wave_a * 0.70 + wave_b * 0.25) + side_dir * (wave_b * 0.18);
	// Secondary cross-hatch layer at 45-degree offset for finer surface texture
	vec2 diag_dir = normalize(flow_dir + side_dir);
	vec2 anti_dir = normalize(flow_dir - side_dir);
	float diag_pos = dot(position, diag_dir) * ripple_normal_scale * ripple_tightness;
	float anti_pos = dot(position, anti_dir) * ripple_normal_scale * ripple_tightness;
	float wave_c = sin(diag_pos * 3.1 - flow_time * 11.0 + sin(anti_pos * 0.8) * 0.3);
	float wave_d = sin(anti_pos * 5.0 + diag_pos * 1.4 - flow_time * 7.0);
	vec2 cross_grad = diag_dir * (wave_c * 0.38) + anti_dir * (wave_d * 0.28);
	return primary_grad * 0.72 + cross_grad * 0.28;
}

vec3 view_from_depth(vec2 uv, float raw_depth, mat4 inv_projection) {
	vec3 ndc = vec3(uv * 2.0 - 1.0, raw_depth);
	vec4 view_position = inv_projection * vec4(ndc, 1.0);
	view_position.xyz /= view_position.w;
	return view_position.xyz;
}

float edge_visibility(vec2 uv) {
	float edge_x = smoothstep(0.0, SSR_EDGE_FADE, uv.x) * smoothstep(0.0, SSR_EDGE_FADE, 1.0 - uv.x);
	float edge_y = smoothstep(0.0, SSR_EDGE_FADE, uv.y) * smoothstep(0.0, SSR_EDGE_FADE, 1.0 - uv.y);
	return edge_x * edge_y;
}

vec3 screen_space_reflection(
		vec3 view_position,
		vec3 normal_view,
		vec2 screen_uv,
		mat4 projection,
		mat4 inv_projection,
		out float hit_weight) {
	hit_weight = 0.0;
	vec3 view_direction = normalize(view_position);
	vec3 reflection_direction = normalize(reflect(view_direction, normal_view));
	vec3 reflected_color = texture(screen_texture, screen_uv).rgb;
	float step_length = ssr_step_size;
	for (int step_index = 0; step_index < SSR_STEP_LIMIT; step_index++) {
		if (step_index >= ssr_max_steps) {
			break;
		}
		vec3 ray_position = view_position + reflection_direction * step_length * float(step_index + 1);
		vec4 clip_position = projection * vec4(ray_position, 1.0);
		if (clip_position.w <= 0.0) {
			break;
		}
		vec2 ray_uv = clip_position.xy / clip_position.w * 0.5 + 0.5;
		if (ray_uv.x <= 0.0 || ray_uv.x >= 1.0 || ray_uv.y <= 0.0 || ray_uv.y >= 1.0) {
			break;
		}
		float scene_depth = -view_from_depth(ray_uv, texture(depth_texture, ray_uv).r, inv_projection).z;
		float ray_depth = -ray_position.z;
		float depth_delta = ray_depth - scene_depth;
		if (depth_delta > 0.0 && depth_delta < ssr_thickness) {
			float edge_fade = edge_visibility(ray_uv);
			float step_fade = 1.0 - (float(step_index) / float(max(ssr_max_steps, 1)));
			hit_weight = edge_fade * step_fade;
			reflected_color = texture(screen_texture, ray_uv).rgb;
			break;
		}
	}
	float fresnel = pow(1.0 - clamp(dot(-view_direction, normal_view), 0.0, 1.0), 5.0);
	hit_weight *= mix(0.35, 1.0, fresnel);
	return reflected_color;
}

void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	vec2 flow_xz = MODEL_MATRIX[0].xz;
	float flow_len = length(flow_xz);
	vec2 mesh_dir = flow_len > 0.00001 ? flow_xz / flow_len : vec2(1.0, 0.0);
	float user_dir_len = length(flow_direction);
	vec2 user_dir = user_dir_len > 0.00001 ? flow_direction / user_dir_len : vec2(0.0, 0.0);
	downstream_dir = normalize(mix(mesh_dir, user_dir, clamp(user_dir_len, 0.0, 1.0)));
	float downstream_pos = dot(world_xz, downstream_dir);
	VERTEX.y += sin((downstream_pos + TIME * flow_speed) * 18.0) * wave_amplitude;
}

void fragment() {
	float raw_depth = texture(depth_texture, SCREEN_UV).r;
	vec3 scene_position = view_from_depth(SCREEN_UV, raw_depth, INV_PROJECTION_MATRIX);
	float scene_depth = -scene_position.z;
	float fragment_depth = -VERTEX.z;
	float depth_delta = max(scene_depth - fragment_depth, 0.0);
	float depth_ratio = clamp(depth_delta / depth_fade_distance, 0.0, 1.0);
	float depth_mix = smoothstep(0.0, 1.0, depth_ratio);
	float foam = 1.0 - smoothstep(0.0, foam_edge_width, depth_delta);
	float shoreline = 1.0 - smoothstep(0.0, shoreline_softness, depth_delta);
	float downstream_pos = dot(world_xz, downstream_dir);
	float ripple = sin(downstream_pos * 11.0 - TIME * flow_speed * 9.0) * 0.5 + 0.5;
	float vertex_shallow = use_vertex_water_traits ? clamp(COLOR.r, 0.0, 1.0) : 0.0;
	float vertex_riffle = use_vertex_water_traits ? clamp(COLOR.g, 0.0, 1.0) : 0.0;
	float trait_depth_lift = vertex_shallow * 0.34 + vertex_riffle * 0.22;
	depth_mix = clamp(depth_mix - trait_depth_lift, 0.0, 1.0);
	foam = max(foam, vertex_riffle * (0.24 + ripple * 0.22));
	shoreline = max(shoreline, vertex_shallow * 0.46);
	vec2 foam_uv = world_xz * foam_normal_scale - downstream_dir * TIME * downstream_flow_speed;
	vec2 foam_gradient = foam_noise_gradient(foam_uv, TIME * foam_normal_flow_speed);
	vec2 ripple_gradient = flow_ripple_gradient(world_xz, downstream_dir, TIME * flow_speed);
	float foam_normal_weight = mix(0.25, 1.0, foam);
	float depth_ripple_weight = mix(0.55, 1.0, depth_mix);
	vec2 combined_gradient = foam_gradient * foam_normal_weight + ripple_gradient * depth_ripple_weight;
	float normal_strength = clamp(foam_normal_strength * foam_normal_weight + ripple_normal_strength * depth_ripple_weight, 0.0, 1.0);
	vec3 tangent_normal = normalize(vec3(-combined_gradient.x, -combined_gradient.y, 1.0));
	// NORMAL_MAP is the intended perturbation path (mesh has tangents; Forward+ uses it correctly).
	// The direct NORMAL write is dropped to prevent double perturbation (H3 fix).
	// normal_view is still computed for SSR ray direction and Fresnel — it is NOT written to NORMAL.
	NORMAL_MAP = tangent_normal;
	NORMAL_MAP_DEPTH = normal_strength;
	vec3 normal_view = normalize(NORMAL + (TANGENT * tangent_normal.x + BINORMAL * tangent_normal.y) * normal_strength);
	vec3 water_color = mix(shallow_color.rgb, deep_color.rgb, depth_mix);
	float bed_visibility = pow(1.0 - depth_mix, 1.35);
	water_color = mix(water_color, bed_tint_color.rgb, bed_visibility * bed_tint_strength);
	water_color = mix(water_color, foam_color.rgb, shoreline * foam_intensity * (0.55 + ripple * 0.22));
	water_color = mix(water_color, foam_color.rgb, foam * foam_intensity * (0.32 + ripple * 0.18));
	float wetline_inside = smoothstep(foam_edge_width, shoreline_softness, depth_delta);
	float wetline_deep = 1.0 - smoothstep(shoreline_softness, shoreline_softness * 2.8, depth_delta);
	water_color *= mix(1.0, 0.82, wetline_inside * wetline_deep * wetline_strength);
	vec3 view_direction = normalize(VERTEX);
	float view_fresnel = pow(1.0 - clamp(dot(-view_direction, normal_view), 0.0, 1.0), 5.0);
	float glint_weight = view_fresnel * smoothstep(0.35, 1.0, ripple) * mix(0.55, 1.0, depth_mix) * fresnel_glint_strength;
	water_color = mix(water_color, fresnel_glint_color.rgb, glint_weight);
	if (ssr_enabled && ssr_intensity > 0.0 && ssr_max_steps > 0) {
		float reflection_weight = 0.0;
		vec3 reflection_color = screen_space_reflection(
				VERTEX,
				normal_view,
				SCREEN_UV,
				PROJECTION_MATRIX,
				INV_PROJECTION_MATRIX,
				reflection_weight);
		// On SSR hit: blend in the screen reflection.
		// On SSR miss: fade toward sky/fog color at grazing angles (Fresnel) to avoid a
		// dark-water artifact where no geometry is behind the reflected ray.
		float miss_weight = (1.0 - reflection_weight) * view_fresnel * ssr_sky_fallback_strength * ssr_intensity;
		vec3 blended = mix(water_color, reflection_color, reflection_weight * ssr_intensity);
		water_color = mix(blended, ssr_sky_fallback_color.rgb, miss_weight);
	}
	ALBEDO = water_color;
	float shoreline_alpha = mix(shallow_alpha, shallow_alpha * 0.82, shoreline);
	float base_alpha = mix(shoreline_alpha, water_alpha, depth_mix);
	ALPHA = clamp(base_alpha + foam * 0.16, 0.0, 1.0);
	ROUGHNESS = water_roughness;
	SPECULAR = mix(0.40, 0.62, view_fresnel);
}
