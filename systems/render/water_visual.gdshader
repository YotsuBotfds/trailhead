shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform vec4 shallow_color : source_color = vec4(0.45, 0.68, 0.70, 1.0);
uniform vec4 deep_color : source_color = vec4(0.10, 0.22, 0.25, 1.0);
uniform float water_alpha : hint_range(0.0, 1.0) = 0.55;
uniform float depth_fade_distance : hint_range(0.001, 2.0) = 0.45;
uniform float foam_edge_width : hint_range(0.001, 0.5) = 0.08;
uniform float flow_speed : hint_range(0.0, 1.0) = 0.08;
uniform float wave_amplitude : hint_range(0.0, 0.1) = 0.015;
uniform float foam_normal_strength : hint_range(0.0, 1.0) = 0.18;
uniform float foam_normal_scale : hint_range(1.0, 64.0) = 18.0;
uniform float foam_normal_flow_speed : hint_range(0.0, 1.0) = 0.06;
uniform bool ssr_enabled = true;
uniform float ssr_intensity : hint_range(0.0, 1.0) = 0.24;
uniform int ssr_max_steps : hint_range(0, 32) = 16;
uniform float ssr_step_size : hint_range(0.005, 0.2) = 0.035;
uniform float ssr_thickness : hint_range(0.005, 0.3) = 0.08;
uniform float water_roughness : hint_range(0.0, 1.0) = 0.18;
uniform vec4 bed_tint_color : source_color = vec4(0.84, 0.78, 0.60, 1.0);
uniform float bed_tint_strength : hint_range(0.0, 1.0) = 0.35;
uniform float shallow_alpha : hint_range(0.0, 1.0) = 0.38;
uniform float downstream_flow_speed : hint_range(0.0, 0.5) = 0.06;
uniform vec4 foam_color : source_color = vec4(0.86, 0.90, 0.84, 1.0);
uniform float wetline_strength : hint_range(0.0, 1.0) = 0.20;

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
	downstream_dir = flow_len > 0.00001 ? flow_xz / flow_len : vec2(1.0, 0.0);
	float downstream_pos = dot(world_xz, downstream_dir);
	VERTEX.y += sin((downstream_pos + TIME * flow_speed) * 18.0) * wave_amplitude;
}

void fragment() {
	float raw_depth = texture(depth_texture, SCREEN_UV).r;
	vec3 scene_position = view_from_depth(SCREEN_UV, raw_depth, INV_PROJECTION_MATRIX);
	float scene_depth = -scene_position.z;
	float fragment_depth = -VERTEX.z;
	float depth_delta = max(scene_depth - fragment_depth, 0.0);
	float depth_mix = clamp(depth_delta / depth_fade_distance, 0.0, 1.0);
	float foam = 1.0 - smoothstep(0.0, foam_edge_width, depth_delta);
	float downstream_pos = dot(world_xz, downstream_dir);
	float ripple = sin(downstream_pos * 11.0 - TIME * flow_speed * 9.0) * 0.5 + 0.5;
	vec2 foam_uv = world_xz * foam_normal_scale - downstream_dir * TIME * downstream_flow_speed;
	vec2 foam_gradient = foam_noise_gradient(foam_uv, TIME * foam_normal_flow_speed);
	float foam_normal_weight = mix(0.35, 1.0, foam);
	vec3 tangent_normal = normalize(vec3(-foam_gradient.x, -foam_gradient.y, 1.0));
	vec3 normal_view = normalize(NORMAL + (TANGENT * tangent_normal.x + BINORMAL * tangent_normal.y) * foam_normal_strength * foam_normal_weight);
	NORMAL_MAP = tangent_normal;
	NORMAL_MAP_DEPTH = foam_normal_strength * foam_normal_weight;
	NORMAL = normal_view;
	vec3 water_color = mix(shallow_color.rgb, deep_color.rgb, depth_mix);
	float bed_visibility = pow(1.0 - depth_mix, 1.5);
	water_color = mix(water_color, bed_tint_color.rgb, bed_visibility * bed_tint_strength);
	water_color = mix(water_color, foam_color.rgb, foam * (0.45 + ripple * 0.25));
	float wetline_inside = smoothstep(foam_edge_width, foam_edge_width * 2.0, depth_delta);
	float wetline_deep = 1.0 - smoothstep(foam_edge_width * 2.0, foam_edge_width * 6.0, depth_delta);
	water_color *= mix(1.0, 0.82, wetline_inside * wetline_deep * wetline_strength);
	if (ssr_enabled && ssr_intensity > 0.0 && ssr_max_steps > 0) {
		float reflection_weight = 0.0;
		vec3 reflection_color = screen_space_reflection(
				VERTEX,
				normal_view,
				SCREEN_UV,
				PROJECTION_MATRIX,
				INV_PROJECTION_MATRIX,
				reflection_weight);
		water_color = mix(water_color, reflection_color, reflection_weight * ssr_intensity);
	}
	ALBEDO = water_color;
	float base_alpha = mix(shallow_alpha, water_alpha, depth_mix);
	ALPHA = clamp(base_alpha + foam * 0.25, 0.0, 1.0);
	ROUGHNESS = water_roughness;
	SPECULAR = 0.55;
}
