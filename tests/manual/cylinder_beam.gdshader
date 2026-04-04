shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

// Cylinder effect: glowing rings at top/bottom, short laser beams descending.
uniform vec4 beam_color : source_color = vec4(0.3, 0.9, 1.0, 1.0);
uniform float ring_width : hint_range(0.001, 0.1) = 0.02;
uniform float ring_glow : hint_range(0.0, 5.0) = 2.0;
uniform int beam_count : hint_range(2, 40) = 12;
uniform float beam_width : hint_range(0.001, 0.2) = 0.04;
uniform float beam_length : hint_range(0.02, 0.5) = 0.15;
uniform float beam_speed : hint_range(0.1, 5.0) = 1.5;
uniform float overall_alpha : hint_range(0.0, 1.0) = 0.8;

varying vec2 v_uv;

void vertex() {
	// CylinderMesh UV: U wraps around (0→1), V goes top(0) to bottom(1).
	v_uv = UV;
}

float hash11(float p) {
	return fract(sin(p * 127.1) * 43758.5453);
}

void fragment() {
	float u = v_uv.x; // angular position 0..1
	float v = v_uv.y; // vertical position: 0 = top, 1 = bottom

	// --- Rings at top and bottom ---
	float ring_top = 1.0 - smoothstep(0.0, ring_width, v);
	float ring_bot = 1.0 - smoothstep(0.0, ring_width, 1.0 - v);
	float rings = (ring_top + ring_bot) * ring_glow;

	// --- Short laser beams traveling down the sides ---
	float beams = 0.0;
	float f_beam_count = float(beam_count);
	for (int i = 0; i < beam_count; i++) {
		float fi = float(i);
		// Each beam at a fixed angular position.
		float beam_u = fi / f_beam_count;
		// Random width variation per beam (0.5x to 1.5x).
		float w_scale = 0.5 + hash11(fi * 7.3);
		float bw = beam_width * w_scale;

		// Angular distance (wrapping).
		float du = abs(u - beam_u);
		du = min(du, 1.0 - du);
		float angular = 1.0 - smoothstep(0.0, bw, du);

		// Beam vertical position — descend at slightly different speeds.
		float speed_scale = 0.7 + hash11(fi * 3.1) * 0.6;
		float phase = hash11(fi * 11.7); // random start offset
		float beam_center = fract(TIME * beam_speed * speed_scale + phase);

		// Random length variation per beam.
		float len = beam_length * (0.5 + hash11(fi * 5.3));
		float dv = abs(v - beam_center);
		// Handle wrapping for beams near top/bottom.
		dv = min(dv, 1.0 - dv);
		float vertical = 1.0 - smoothstep(0.0, len, dv);

		// Fade beam near top/bottom edges so it appears/disappears from the ring.
		float edge_fade = smoothstep(0.0, 0.05, v) * smoothstep(0.0, 0.05, 1.0 - v);

		beams += angular * vertical * edge_fade;
	}
	beams = clamp(beams, 0.0, 1.0);

	float intensity = clamp(rings + beams, 0.0, 1.0);
	ALBEDO = beam_color.rgb * intensity;
	ALPHA = intensity * overall_alpha;
}
