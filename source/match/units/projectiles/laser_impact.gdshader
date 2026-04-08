shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

uniform vec4 spark_color : source_color = vec4(0.3, 0.6, 1.0, 1.0);
uniform float intensity : hint_range(0.0, 10.0) = 4.0;

void fragment() {
	float dist = length(UV - vec2(0.5));
	float spark = smoothstep(0.5, 0.0, dist);
	float ring = smoothstep(0.35, 0.25, dist) * smoothstep(0.15, 0.25, dist) * 0.5;
	float combined = spark + ring;

	ALBEDO = spark_color.rgb;
	EMISSION = spark_color.rgb * combined * intensity;
	ALPHA = combined * spark_color.a * COLOR.a;
}
