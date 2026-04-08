// Vine energy pulse shader for the ResourceSpawner root mesh.
// Emits expanding ring-pulses that originate at the XZ model center and
// travel outward, fading as they go. A noise texture breaks up the ring
// into an organic vine-like pattern rather than a perfect circle.
//
// Uniforms:
//   pulse_speed    – world units per second the ring expands outward
//   pulse_width    – how broad each pulse ring is (0 = razor thin, 1 = wide)
//   pulse_count    – simultaneous rings (evenly spaced in time/space)
//   radial_scale   – multiplier on the raw XZ radius (tune to model size)
//   noise_strength – how much the noise warps the ring (0 = perfect circle)
//   brightness     – overall glow luminance
//   intensity      – master fade (0 = invisible, 1 = full)
//   energy_color   – tint colour
//   fresnel_power  – rim-lighting falloff

shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_back;

uniform sampler2D noise : repeat_enable;
uniform float pulse_speed : hint_range(0.1, 5.0) = 1.2;
uniform float pulse_width : hint_range(0.01, 0.5) = 0.12;
uniform int pulse_count : hint_range(1, 6) = 2;
uniform float max_radius : hint_range(0.1, 10.0) = 2.0;
uniform float noise_strength : hint_range(0.0, 1.0) = 0.35;
uniform float brightness : hint_range(0.0, 10.0) = 4.0;
uniform float intensity : hint_range(0.0, 1.0) = 1.0;
uniform vec4 energy_color : source_color = vec4(0.2, 0.9, 0.15, 1.0);
uniform float fresnel_power : hint_range(0.5, 5.0) = 2.0;

// Pass model-space position to fragment — VERTEX in fragment() is view-space.
varying vec3 model_pos;

void vertex() {
	model_pos = VERTEX;
	VERTEX += NORMAL * 0.01;
}

void fragment() {
	float time = TIME;

	// Radius from centre in model space, normalized to 0..1 (0 = center, 1 = tip).
	float r = clamp(length(model_pos.xz) / max_radius, 0.0, 1.0);

	// Angular direction — used to animate noise non-uniformly around the ring.
	float angle = atan(model_pos.z, model_pos.x);

	// Sample noise to break up the perfect circle.
	// The noise is sampled in polar-like coordinates so it wraps around the ring.
	vec2 noise_uv = vec2(angle / TAU + 0.5, r - time * 0.15);
	float n = texture(noise, noise_uv).r;
	// Warp the radius slightly — creates organic jagged edges on the ring.
	float r_warped = clamp(r + (n - 0.5) * noise_strength * 0.3, 0.0, 1.1);

	// Sum contributions from pulse_count evenly offset rings.
	// Each ring is a smooth bell curve centred at its current radial position.
	float pulse_total = 0.0;
	float period = 1.0 / float(pulse_count);
	for (int i = 0; i < pulse_count; i++) {
		// Phase offset so each ring is evenly staggered (0, 1/n, 2/n …).
		float offset = float(i) * period;
		// Current leading edge of this ring, cycling 0..1 continuously.
		float front = fract(time * pulse_speed * period + offset);
		// Distance from the warped radius to this ring's leading edge.
		// fract wraps around, so we take the shorter of the two distances.
		float dist = abs(r_warped - front);
		dist = min(dist, 1.0 - dist);  // wrap-around distance
		// Bell-curve falloff: bright at dist=0, falls off over pulse_width.
		float ring = exp(-dist * dist / (pulse_width * pulse_width + 0.0001));
		// Tail fade: ring brightens near its leading edge, dims behind it.
		// This gives the sense of a wave front rather than a symmetric ring.
		float tail_phase = fract(r_warped - front);
		float tail_fade = smoothstep(0.0, 0.4, 1.0 - tail_phase);
		pulse_total += ring * tail_fade;
	}

	// Fade intensity toward the outer edge so the ring dissipates naturally.
	float radial_fade = 1.0 - smoothstep(0.6, 1.0, r_warped);

	// Fresnel rim — glow wraps more visibly around the silhouette.
	float fresnel = pow(1.0 - abs(dot(NORMAL, VIEW)), fresnel_power);

	float effect = pulse_total * radial_fade * brightness * (0.4 + fresnel * 0.6);

	ALBEDO = energy_color.rgb * effect * intensity;
	ALPHA = clamp(effect * intensity, 0.0, 1.0);
}

