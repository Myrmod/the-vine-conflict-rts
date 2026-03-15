shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

uniform vec4 beam_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float core_width : hint_range(0.0, 0.5) = 0.1;
uniform float glow_width : hint_range(0.0, 0.5) = 0.2;
uniform float intensity : hint_range(0.0, 10.0) = 3.0;

void fragment() {
	// UV.x runs across the width of the PlaneMesh
	float dist = abs(UV.x - 0.5);

	// Bright core
	float core = smoothstep(core_width, 0.0, dist);
	// Softer glow around the core
	float glow = smoothstep(glow_width, core_width, dist) * 0.5;

	float beam = core + glow;

	ALBEDO = beam_color.rgb;
	EMISSION = beam_color.rgb * beam * intensity;
	ALPHA = beam * beam_color.a;
}
