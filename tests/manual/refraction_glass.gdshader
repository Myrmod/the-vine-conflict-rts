shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, unshaded;

uniform float cell_scale_1 : hint_range(1.0, 40.0) = 12.0;
uniform float cell_scale_2 : hint_range(1.0, 40.0) = 5.0;
uniform float speed : hint_range(0.0, 5.0) = 2.0;
uniform float zoom_range : hint_range(0.0, 2.0) = 0.5;
uniform float edge_width : hint_range(0.0, 0.1) = 0.025;
uniform vec4 edge_color : source_color = vec4(0.85, 0.92, 0.98, 0.9);
uniform float edge_fade : hint_range(0.0, 2.0) = 0.1;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

// --- Voronoi helpers ---

vec2 random2(vec2 p) {
	return fract(sin(vec2(
		dot(p, vec2(127.1, 311.7)),
		dot(p, vec2(269.5, 183.3))
	)) * 43758.5453);
}

// Returns (min_dist, edge_dist).
// closest_cell: grid id of the nearest cell.
// to_pixel: vector from cell centre to this pixel (Voronoi UV space).
vec2 voronoi(vec2 uv, float t, out vec2 closest_cell, out vec2 to_pixel) {
	vec2 i_st = floor(uv);
	vec2 f_st = fract(uv);

	float min_dist = 1e10;
	float second_dist = 1e10;
	closest_cell = i_st;
	to_pixel = vec2(0.0);

	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 neighbor = vec2(float(x), float(y));
			vec2 seed = i_st + neighbor;
			// Jump to a new random position each time step.
			vec2 point = random2(seed + floor(t) * 0.173);
			vec2 diff = neighbor + point - f_st;
			float d = length(diff);
			if (d < min_dist) {
				second_dist = min_dist;
				min_dist = d;
				closest_cell = i_st + neighbor;
				to_pixel = -diff;
			} else if (d < second_dist) {
				second_dist = d;
			}
		}
	}
	return vec2(min_dist, second_dist - min_dist);
}

// Per-cell random zoom, fixed until cells jump.
float cell_zoom(vec2 cell_id, float t) {
	float h = fract(sin(dot(cell_id + floor(t) * 0.173, vec2(41.7, 289.3))) * 9837.123);
	return 1.0 + zoom_range * (h * 2.0 - 1.0);
}

void fragment() {
	float t = TIME * speed;

	// Build Jacobian to convert UV-space offset → SCREEN_UV-space offset.
	mat2 J_uv  = mat2(dFdx(UV), dFdy(UV));
	mat2 J_suv = mat2(dFdx(SCREEN_UV), dFdy(SCREEN_UV));
	float det = J_uv[0][0] * J_uv[1][1] - J_uv[0][1] * J_uv[1][0];
	mat2 J_uv_inv = mat2(
		vec2( J_uv[1][1], -J_uv[0][1]),
		vec2(-J_uv[1][0],  J_uv[0][0])
	) / det;
	mat2 uv_to_screen = J_suv * J_uv_inv;

	// --- Layer 1 (smaller cells) ---
	vec2 cell1, dir1;
	vec2 v1 = voronoi(UV * cell_scale_1, t, cell1, dir1);
	float edge1 = 1.0 - smoothstep(0.0, edge_width, v1.y);
	float zoom1 = cell_zoom(cell1, t);
	vec2 dir_screen1 = uv_to_screen * (dir1 / cell_scale_1);

	// --- Layer 2 (larger cells) ---
	// Offset seed so layers don't correlate.
	vec2 cell2, dir2;
	vec2 v2 = voronoi(UV * cell_scale_2 + 73.19, t * 0.7, cell2, dir2);
	float edge2 = 1.0 - smoothstep(0.0, edge_width, v2.y);
	float zoom2 = cell_zoom(cell2 + 137.0, t * 0.7);
	vec2 dir_screen2 = uv_to_screen * (dir2 / cell_scale_2);

	// Combine both zoom offsets additively.
	vec2 offset1 = dir_screen1 * (1.0 - 1.0 / zoom1);
	vec2 offset2 = dir_screen2 * (1.0 - 1.0 / zoom2);
	vec2 zoomed_uv = SCREEN_UV - offset1 - offset2;

	vec3 col = texture(screen_texture, zoomed_uv).rgb;

	// Overlay edges from both layers.
	float edge = max(edge1, edge2);
	vec3 final_color = mix(col, edge_color.rgb, edge * edge_color.a);

	// Fade to transparent near plane edges so cells don't touch the border.
	vec2 d = min(UV, 1.0 - UV);
	float border = smoothstep(0.0, edge_fade, min(d.x, d.y));

	ALBEDO = final_color;
	ALPHA = border;
}
