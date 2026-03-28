// Electricity arc shader for 3D meshes.
// Applied as a next_pass on vine materials. The "intensity" uniform is driven
// by GDScript based on the vine's resource ratio (0 below 10%, linear to 1 at 100%).
//
// Two scrolling noise textures are blended and thresholded via smoothstep to
// produce bright arc lines with dark gaps between them.  A third noise sample
// at higher frequency adds occasional spark flashes.  Fresnel rim lighting
// makes arcs more visible at glancing angles.
//
// Adjustable uniforms:
//   brightness      – overall arc luminance
//   time_scale      – animation speed
//   intensity       – master fade (0 = invisible, 1 = full)
//   electricity_color – tint colour of the arcs
//   fresnel_power   – rim-lighting falloff (lower = wider rim)
//   gap_threshold   – lower bound of the arc smoothstep; raise for wider dark
//                     gaps between arcs, lower for denser coverage
//   arc_edge        – upper bound of the arc smoothstep; controls how soft
//                     the transition from gap to bright arc is

shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_back;

uniform sampler2D noise : repeat_enable;
uniform sampler2D noise2 : repeat_enable;
uniform float brightness : hint_range(0.0, 10.0) = 4.0;
uniform float time_scale : hint_range(0.0, 5.0) = 1.5;
uniform float intensity : hint_range(0.0, 1.0) = 1.0;
uniform vec4 electricity_color : source_color = vec4(0.2, 0.9, 0.1, 1.0);
uniform float fresnel_power : hint_range(0.5, 5.0) = 1.5;
uniform float gap_threshold : hint_range(0.0, 0.9) = 0.55;
uniform float arc_edge : hint_range(0.1, 1.0) = 0.85;

void vertex() {
	// Push vertices slightly outward along their normal to avoid z-fighting
	// with the base material pass underneath.
	VERTEX += NORMAL * 0.01;
}

void fragment() {
	float time = TIME * time_scale;

	// Fresnel rim — effect is stronger at glancing angles so arcs wrap
	// visibly around the silhouette of the mesh.
	float fresnel = pow(1.0 - abs(dot(NORMAL, VIEW)), fresnel_power);

	// Two scrolling noise layers at different scales and speeds.
	// The offset between them creates evolving interference patterns.
	vec2 uv1 = UV * 2.0 + vec2(-time * 0.3, -time * 0.15);
	vec2 uv2 = UV * 3.0 + vec2(time * 0.2, -time * 0.35);
	float n1 = texture(noise, uv1).r;
	float n2 = texture(noise2, uv2).r;

	// Blend noises and threshold into arcs.
	// gap_threshold..arc_edge controls the smoothstep window:
	//   - Raising gap_threshold widens the dark gaps between arcs.
	//   - Lowering it fills more of the surface with electricity.
	float combined = n1 * 0.6 + n2 * 0.4;
	float arcs = smoothstep(gap_threshold, arc_edge, combined) * brightness;

	// High-frequency spark layer — rare bright flashes.
	vec2 uv3 = UV * 6.0 + vec2(-time * 1.0, time * 0.6);
	float sparks = smoothstep(0.85, 1.0, texture(noise, uv3).r) * 2.0;

	// Combine arcs + sparks, modulated by fresnel rim.
	float effect = (arcs + sparks) * (0.4 + fresnel * 0.6);

	ALBEDO = electricity_color.rgb * effect * intensity;
	ALPHA = clamp(effect * intensity, 0.0, 1.0);
}
