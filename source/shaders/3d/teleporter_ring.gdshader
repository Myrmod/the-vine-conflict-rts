shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 player_color : source_color = vec4(0.2, 0.8, 1.0, 1.0);
uniform float alpha : hint_range(0.0, 1.0) = 1.0;
uniform float emission_strength : hint_range(0.0, 10.0) = 0.0;

void fragment() {
	ALBEDO = player_color.rgb;
	ALPHA = alpha;
	EMISSION = player_color.rgb * emission_strength;
}
