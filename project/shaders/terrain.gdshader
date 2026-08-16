shader_type spatial;
render_mode specular_schlick_ggx, cull_back;

uniform sampler2D height_tex : filter_linear, repeat_disable;
uniform vec2 map_cells = vec2(256.0, 256.0);
uniform float cell_m = 5.0;
uniform vec2 uv_origin = vec2(0.0);
uniform vec2 uv_scale = vec2(1.0);
uniform bool show_slope = true;

varying vec2 v_uv;

void vertex() {
	v_uv = uv_origin + UV * uv_scale;
	float h = texture(height_tex, v_uv).r;
	VERTEX.y = h;
}

void fragment() {
	vec2 texel = 1.0 / map_cells;
	float h_l = texture(height_tex, v_uv + vec2(-texel.x, 0.0)).r;
	float h_r = texture(height_tex, v_uv + vec2(texel.x, 0.0)).r;
	float h_d = texture(height_tex, v_uv + vec2(0.0, -texel.y)).r;
	float h_u = texture(height_tex, v_uv + vec2(0.0, texel.y)).r;
	vec3 dx = vec3(2.0 * cell_m, h_r - h_l, 0.0);
	vec3 dz = vec3(0.0, h_u - h_d, 2.0 * cell_m);
	vec3 n = normalize(cross(dz, dx));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);

	float slope = 1.0 - clamp(n.y, 0.0, 1.0);
	vec3 ground = mix(vec3(0.42, 0.34, 0.24), vec3(0.58, 0.56, 0.50), clamp(slope * 2.5, 0.0, 1.0));
	if (show_slope) {
		ground = mix(vec3(0.16, 0.28, 0.72), vec3(0.95, 0.95, 0.95), clamp(slope * 3.0, 0.0, 1.0));
	}
	float h = texture(height_tex, v_uv).r;
	if (h < 0.05) {
		float hatch = step(0.5, fract((v_uv.x + v_uv.y) * map_cells.x * 0.2));
		ground = mix(vec3(0.08, 0.08, 0.10), vec3(0.22, 0.06, 0.06), hatch);
	}
	ALBEDO = ground;
	ROUGHNESS = 0.92;
	METALLIC = 0.0;
}
