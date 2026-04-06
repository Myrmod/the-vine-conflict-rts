// Vine energy glow shader for 3D meshes.
// Applied as a next_pass on vine materials. The "intensity" uniform is driven
// by GDScript based on the vine's resource ratio (0 below 10%, linear to 1 at 100%).
//
// Two scrolling noise textures are blended and thresholded via smoothstep to
// produce bright energy veins with dark gaps between them. A third noise sample
// at higher frequency adds occasional pulse flashes. Fresnel rim lighting
// makes the glow more visible at glancing angles.
//
// Adjustable uniforms:
//   brightness      – overall glow luminance
//   time_scale      – animation speed
//   intensity       – master fade (0 = invisible, 1 = full)
//   energy_color    – tint colour of the energy glow
//   fresnel_power   – rim-lighting falloff (lower = wider rim)
//   gap_threshold   – lower bound of the vein smoothstep; raise for wider dark
//                     gaps between veins, lower for denser coverage
//   vein_edge       – upper bound of the vein smoothstep; controls how soft
//                     the transition from gap to bright vein is

shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_back;

uniform sampler2D noise : repeat_enable;
uniform sampler2D noise2 : repeat_enable;
uniform float brightness : hint_range(0.0, 10.0) = 3.0;
uniform float time_scale : hint_range(0.0, 5.0) = 0.5;
uniform float intensity : hint_range(0.0, 1.0) = 0.8;
uniform vec4 energy_color : source_color = vec4(0.2, 0.9, 0.1, 1.0);
uniform float fresnel_power : hint_range(0.5, 5.0) = 2.0;
uniform float gap_threshold : hint_range(0.0, 0.9) = 0.55;
uniform float vein_edge : hint_range(0.1, 1.0) = 0.85;

void vertex() {
	// Push vertices slightly outward along their normal to avoid z-fighting
	// with the base material pass underneath.
	VERTEX += NORMAL * 0.01;
}

void fragment() {
	float time = TIME * time_scale;

	// Fresnel rim — effect is stronger at glancing angles so the glow wraps
	// visibly around the silhouette of the mesh.
	float fresnel = pow(1.0 - abs(dot(NORMAL, VIEW)), fresnel_power);

	// Two scrolling noise layers at different scales and speeds.
	// The offset between them creates evolving interference patterns.
	vec2 uv1 = UV * 2.0 + vec2(-time * 0.3, -time * 0.15);
	vec2 uv2 = UV * 3.0 + vec2(time * 0.2, -time * 0.35);
	float n1 = texture(noise, uv1).r;
	float n2 = texture(noise2, uv2).r;

	// Blend noises and threshold into energy veins.
	// gap_threshold..vein_edge controls the smoothstep window:
	//   - Raising gap_threshold widens the dark gaps between veins.
	//   - Lowering it fills more of the surface with energy glow.
	float combined = n1 * 0.6 + n2 * 0.4;
	float veins = smoothstep(gap_threshold, vein_edge, combined) * brightness;

	// High-frequency pulse layer — rare bright flashes.
	vec2 uv3 = UV * 6.0 + vec2(-time * 1.0, time * 0.6);
	float pulses = smoothstep(0.85, 1.0, texture(noise, uv3).r) * 2.0;

	// Combine veins + pulses, modulated by fresnel rim.
	float effect = (veins + pulses) * (0.4 + fresnel * 0.6);

	ALBEDO = energy_color.rgb * effect * intensity;
	ALPHA = clamp(effect * intensity, 0.0, 1.0);
}
