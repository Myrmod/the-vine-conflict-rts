shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

uniform vec4 line_color : source_color = vec4(0.5, 1.0, 0.5, 0.7);
uniform float dash_length : hint_range(0.05, 2.0) = 0.3;
uniform float gap_length : hint_range(0.05, 2.0) = 0.2;

varying float v_distance;

void vertex() {
	v_distance = UV.x;
}

void fragment() {
	float pattern = mod(v_distance, dash_length + gap_length);
	if (pattern > dash_length) {
		discard;
	}
	ALBEDO = line_color.rgb;
	ALPHA = line_color.a;
}
