shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;

uniform vec4 color_top : source_color = vec4(0.176, 0.416, 0.106, 1.0);
uniform vec4 color_bottom : source_color = vec4(0.055, 0.165, 0.027, 1.0);
/// Controls how quickly the gradient goes from bottom to top. Higher = faster transition.
uniform float gradient_scale : hint_range(0.5, 10.0) = 2.5;

varying float v_height_above_base;

void vertex() {
	// Use world-space height above the instance origin so the gradient is
	// always bottom-to-top regardless of mesh orientation or scale.
	vec4 world_pos = MODEL_MATRIX * vec4(VERTEX, 1.0);
	float base_y = MODEL_MATRIX[3][1];
	v_height_above_base = world_pos.y - base_y;
}

void fragment() {
	float t = clamp(v_height_above_base * gradient_scale, 0.0, 1.0);
	ALBEDO = mix(color_bottom.rgb, color_top.rgb, t);
	ROUGHNESS = 0.9;
}
