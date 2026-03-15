shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

varying vec4 v_color;

void vertex() {
	v_color = INSTANCE_CUSTOM;

	// Billboard the plane so its face always points toward the camera.
	vec3 beam_dir = normalize((MODEL_MATRIX * vec4(1, 0, 0, 0)).xyz);
	float beam_length = length((MODEL_MATRIX * vec4(1, 0, 0, 0)).xyz);
	float beam_width = length((MODEL_MATRIX * vec4(0, 0, 1, 0)).xyz);
	vec3 center = (MODEL_MATRIX * vec4(0, 0, 0, 1)).xyz;

	// Use camera forward (INV_VIEW_MATRIX column 2) so the billboard
	// is stable under orthographic rotation.
	vec3 to_cam = INV_VIEW_MATRIX[2].xyz;
	vec3 right_raw = cross(beam_dir, to_cam);
	// Fallback when beam is nearly parallel to camera view
	if (length(right_raw) < 0.001) {
		right_raw = cross(beam_dir, vec3(0.0, 1.0, 0.0));
	}
	vec3 right = normalize(right_raw);

	// PlaneMesh vertices lie in XZ: VERTEX.x = along beam, VERTEX.z = width
	vec3 world_pos = center
		+ beam_dir * VERTEX.x * beam_length
		+ right * VERTEX.z * beam_width;

	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world_pos, 1.0);
}

void fragment() {
	// UV.y runs across the width of the PlaneMesh
	float dist = abs(UV.y - 0.5);

	// Bright core
	float core = smoothstep(0.1, 0.0, dist);
	// Softer glow around the core
	float glow = smoothstep(0.2, 0.1, dist) * 0.5;

	float beam = core + glow;

	ALBEDO = v_color.rgb;
	EMISSION = v_color.rgb * beam * 3.0;
	ALPHA = beam * v_color.a;
}
