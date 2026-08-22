shader_type spatial;
render_mode specular_schlick_ggx, cull_back;

uniform sampler2D height_tex : filter_linear, repeat_disable;
uniform sampler2D mat_tex : filter_nearest, repeat_disable;
uniform sampler2D atlas_tex : filter_linear, repeat_disable;
uniform sampler2D tile_lut : filter_nearest, repeat_disable;
uniform bool use_atlas = false;
uniform bool use_tile_lut = false;
uniform vec4 mat_uvs[16];
uniform vec2 map_cells = vec2(256.0, 256.0);
uniform float cell_m = 5.0;
uniform vec2 lod_center = vec2(0.0);
uniform float lod_span_quads = 65.0;
uniform vec2 lod_morph = vec2(0.72, 0.92);
uniform bool show_slope = false;
uniform bool show_materials = true;
uniform bool show_grid = false;
uniform vec3 mat_colors[16];
uniform bool brush_on = false;
uniform vec2 brush_center = vec2(0.0);
uniform vec2 brush_centers[4];
uniform int brush_count = 1;
uniform float brush_radius = 40.0;
uniform float brush_falloff = 0.65;
uniform int brush_shape = 0;
uniform float water_level = -1.0;
uniform sampler2D mask_tex : filter_nearest, repeat_disable;
uniform bool show_mask = false;
uniform vec3 mask_tint = vec3(0.12, 0.32, 0.62);
uniform float mask_water_level = -1.0;
uniform sampler2D selection_tex : filter_linear, repeat_disable;
uniform bool show_selection = false;

varying vec2 v_uv;
varying vec3 v_world;

vec2 world_to_uv(vec2 world_xz) {
	return world_xz / (map_cells * cell_m);
}

float height_at(vec2 world_xz) {
	return texture(height_tex, world_to_uv(world_xz)).r;
}

void vertex() {
	// Clipmap meshes carry flat XZ in *quad units*; the instance transform
	// supplies the ring's quad size. Reading it back out of the model matrix
	// is what lets every ring share one material.
	vec2 p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	float quad_m = length(MODEL_MATRIX[0].xyz);
	float h = height_at(p);
	// Geomorph (GPU Gems 2, 2.4.1): blend towards the height the next-coarser
	// ring would give this vertex, reaching 1.0 before the ring's outer edge.
	// A vertex the coarse ring does not have then lands exactly on the coarse
	// edge, so the LOD join has nothing to crack open and nothing to pop.
	float coarse_m = quad_m * 2.0;
	vec2 base = floor(p / coarse_m) * coarse_m;
	vec2 f = (p - base) / coarse_m;
	float h00 = height_at(base);
	float h10 = height_at(base + vec2(coarse_m, 0.0));
	float h01 = height_at(base + vec2(0.0, coarse_m));
	float h11 = height_at(base + vec2(coarse_m, coarse_m));
	float h_coarse = mix(mix(h00, h10, f.x), mix(h01, h11, f.x), f.y);
	vec2 d = abs(p - lod_center);
	float edge = max(d.x, d.y) / (lod_span_quads * quad_m);
	h = mix(h, h_coarse, smoothstep(lod_morph.x, lod_morph.y, edge));
	VERTEX.y = h;
	v_uv = world_to_uv(p);
	// True world position. Everything planar-projected off this — brush ring,
	// grid lines, hatch, atlas tile local UV — stays seamless across ring
	// boundaries instead of restarting at each seam.
	v_world = vec3(p.x, h, p.y);
}

void fragment() {
	// Outer rings reach far past the map; the terrain still ends where the
	// heightfield does rather than smearing its clamped edge outward.
	if (v_uv.x < 0.0 || v_uv.y < 0.0 || v_uv.x > 1.0 || v_uv.y > 1.0) {
		discard;
	}
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
		// Full .mat tile word (F2 §2): R = orientation<<4 | variant,
		// G = base<<4 | transition.
		vec2 word = texture(mat_tex, v_uv).rg * 255.0;
		int b0 = int(word.x + 0.5);
		int b1 = int(word.y + 0.5);
		int orient = b0 >> 4;
		int variant = b0 & 15;
		int base_m = b1 >> 4;
		int trans_m = b1 & 15;
		int mi = base_m;
		vec2 local = fract(vec2(v_world.x, v_world.z) / 20.0);
		if (use_atlas && use_tile_lut) {
			// kind: solid / cap / diagonal — decided by the word itself.
			int kind = 0;
			if (base_m != trans_m) {
				kind = orient < 8 ? 1 : 2;
			}
			vec4 rect = texelFetch(tile_lut,
				ivec2(base_m * 16 + trans_m, kind * 11 + min(variant, 10)), 0);
			if (rect.z <= 0.0) {
				rect = mat_uvs[mi];  // no such tile shipped — solid fallback
			} else {
				// Orientation → rotation quarter-turns + mirror (F2 §2).
				// Identity (orient 14 on diagonals) is the atlas D tile as
				// shipped: the corner faces left. 13/12/15 are +90/180/−90.
				int c = orient;
				int rot;
				bool mirror;
				if (c < 8) {
					mirror = c < 4;
					rot = mirror ? (1 - c) & 3 : (7 - c) & 3;
				} else {
					mirror = c < 12;
					rot = mirror ? (9 - c) & 3 : (14 - c) & 3;
				}
				vec2 p = local - 0.5;
				for (int r = 0; r < rot; r++) {
					p = vec2(-p.y, p.x);
				}
				if (mirror) {
					p.x = -p.x;
				}
				local = p + 0.5;
			}
			// Half-texel inset against atlas bleed between adjacent tiles.
			vec2 atlas_px = vec2(textureSize(atlas_tex, 0));
			vec2 inset = 0.5 / atlas_px;
			ground = texture(atlas_tex,
				rect.xy + inset + local * (rect.zw - 2.0 * inset)).rgb;
		} else if (use_atlas) {
			vec4 rect = mat_uvs[mi];
			ground = texture(atlas_tex, rect.xy + local * rect.zw).rgb;
		} else {
			ground = mix(mat_colors[mi], ground, 0.15);
		}
	}
	if (show_slope) {
		vec3 slope_col = mix(vec3(0.16, 0.28, 0.72), vec3(0.95, 0.95, 0.95), clamp(slope * 3.0, 0.0, 1.0));
		ground = mix(ground, slope_col, 0.55);
	}
	float h = texture(height_tex, v_uv).r;
	// Void cells (raw height 0) hatch only in the diagnostic flat-colour
	// view; with the atlas active the game just draws their tiles.
	if (h < 0.05 && !(show_materials && use_atlas)) {
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
		float acc = 0.0;
		int n = clamp(brush_count, 1, 4);
		for (int i = 0; i < 4; i++) {
			if (i >= n) {
				break;
			}
			vec2 center = brush_centers[i];
			vec2 d = vec2(v_world.x, v_world.z) - center;
			float dist = brush_shape == 1 ? max(abs(d.x), abs(d.y)) : length(d);
			float edge = abs(dist - brush_radius);
			float ring = 1.0 - smoothstep(0.0, 2.5, edge);
			float inner = 1.0 - clamp(dist / max(brush_radius, 0.001), 0.0, 1.0);
			float fill = pow(inner, mix(1.0, 0.4, brush_falloff)) * 0.22;
			acc = max(acc, max(ring, fill));
		}
		ground = mix(ground, vec3(0.95, 0.85, 0.25), acc);
	}
	if (water_level >= 0.0 && h <= water_level + 0.05) {
		ground = mix(ground, vec3(0.12, 0.32, 0.62), 0.55);
	}
	if (show_mask) {
		float m = texture(mask_tex, v_uv).r;
		if (m > 0.001) {
			float a = 0.42;
			if (mask_water_level >= 0.0 && h <= mask_water_level + 0.05) {
				a = 0.62;
			}
			ground = mix(ground, mask_tint, a);
		}
	}
	if (show_selection) {
		float s = texture(selection_tex, v_uv).r;
		if (s > 0.001) {
			ground = mix(ground, vec3(0.18, 0.52, 0.95), 0.14 * s);
			float s_l = texture(selection_tex, v_uv + vec2(-texel.x, 0.0)).r;
			float s_r = texture(selection_tex, v_uv + vec2(texel.x, 0.0)).r;
			float s_d = texture(selection_tex, v_uv + vec2(0.0, -texel.y)).r;
			float s_u = texture(selection_tex, v_uv + vec2(0.0, texel.y)).r;
			float edge = max(abs(s - s_l), max(abs(s - s_r), max(abs(s - s_d), abs(s - s_u))));
			float pulse = 0.40 + 0.60 * (0.5 + 0.5 * sin(TIME * 5.0));
			ground = mix(ground, vec3(0.95, 0.97, 1.0), clamp(edge * 3.0, 0.0, 1.0) * pulse);
		}
	}
	ALBEDO = ground;
	ROUGHNESS = 0.92;
	METALLIC = 0.0;
}
