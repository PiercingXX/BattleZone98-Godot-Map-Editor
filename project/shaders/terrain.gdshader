shader_type spatial;
render_mode specular_schlick_ggx, cull_back;

uniform sampler2D height_tex : filter_linear, repeat_disable;
uniform sampler2D mat_tex : filter_nearest, repeat_disable;
uniform sampler2D atlas_tex : filter_linear, repeat_disable;
uniform bool use_atlas = false;
uniform vec4 mat_uvs[16];
uniform vec2 map_cells = vec2(256.0, 256.0);
uniform float cell_m = 5.0;
uniform vec2 uv_origin = vec2(0.0);
uniform vec2 uv_scale = vec2(1.0);
uniform bool show_slope = false;
uniform bool show_materials = true;
uniform bool show_grid = false;
uniform vec3 mat_colors[16];
uniform bool brush_on = false;
uniform vec2 brush_center = vec2(0.0);
uniform float brush_radius = 40.0;
uniform float brush_falloff = 0.65;
uniform int brush_shape = 0;
uniform float water_level = -1.0;

varying vec2 v_uv;
varying vec3 v_world;

void vertex() {
	v_uv = uv_origin + UV * uv_scale;
	float h = texture(height_tex, v_uv).r;
	VERTEX.y = h;
	v_world = VERTEX;
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
	if (show_materials) {
		float idx = texture(mat_tex, v_uv).r * 255.0;
		int mi = clamp(int(idx + 0.5), 0, 15);
		if (use_atlas) {
			vec4 rect = mat_uvs[mi];
			vec2 local = fract(vec2(v_world.x, v_world.z) / 20.0);
			ground = texture(atlas_tex, rect.xy + local * rect.zw).rgb;
		} else {
			ground = mix(mat_colors[mi] / 255.0, ground, 0.25);
		}
	}
	if (show_slope) {
		ground = mix(vec3(0.16, 0.28, 0.72), vec3(0.95, 0.95, 0.95), clamp(slope * 3.0, 0.0, 1.0));
	}
	float h = texture(height_tex, v_uv).r;
	if (h < 0.05) {
		float hatch = step(0.5, fract((v_uv.x + v_uv.y) * map_cells.x * 0.2));
		ground = mix(vec3(0.08, 0.08, 0.10), vec3(0.22, 0.06, 0.06), hatch);
	}
	if (show_grid) {
		vec2 world_xz = vec2(v_world.x, v_world.z);
		vec2 g = abs(fract(world_xz / 20.0) - 0.5);
		float line = 1.0 - smoothstep(0.46, 0.5, max(g.x, g.y) * 2.0);
		ground = mix(ground, vec3(0.05, 0.05, 0.06), line * 0.35);
	}
	if (brush_on) {
		vec2 d = vec2(v_world.x, v_world.z) - brush_center;
		float dist = brush_shape == 1 ? max(abs(d.x), abs(d.y)) : length(d);
		float edge = abs(dist - brush_radius);
		float ring = 1.0 - smoothstep(0.0, 2.5, edge);
		float inner = 1.0 - clamp(dist / max(brush_radius, 0.001), 0.0, 1.0);
		float fill = pow(inner, mix(1.0, 0.4, brush_falloff)) * 0.22;
		ground = mix(ground, vec3(0.95, 0.85, 0.25), max(ring, fill));
	}
	if (water_level >= 0.0 && h <= water_level + 0.05) {
		ground = mix(ground, vec3(0.12, 0.32, 0.62), 0.55);
	}
	ALBEDO = ground;
	ROUGHNESS = 0.92;
	METALLIC = 0.0;
}
