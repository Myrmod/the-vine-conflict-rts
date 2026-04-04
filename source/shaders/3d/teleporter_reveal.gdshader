shader_type spatial;
render_mode cull_back, depth_draw_opaque;

// ------- Original material properties -------
uniform vec4 albedo : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform sampler2D albedo_texture : source_color, hint_default_white, filter_linear_mipmap;
uniform bool use_albedo_texture = false;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.5;
uniform float specular : hint_range(0.0, 1.0) = 0.5;
uniform sampler2D metallic_texture : hint_default_white, filter_linear_mipmap;
uniform bool use_metallic_texture = false;
uniform sampler2D roughness_texture : hint_default_white, filter_linear_mipmap;
uniform bool use_roughness_texture = false;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap;
uniform bool use_normal_texture = false;
uniform float normal_scale : hint_range(-16.0, 16.0) = 1.0;

// ------- Reveal / Dissolve -------
// reveal mode: 0 = fully hidden, 1 = fully visible (bottom-to-top)
// dissolve mode: 0 = fully visible, 1 = fully dissolved (top-to-bottom)
uniform float reveal_progress : hint_range(0.0, 1.0) = 0.0;
uniform bool dissolve_mode = false;
uniform float y_min = 0.0;
uniform float y_max = 1.0;
// Size of the pixelated squares in screen pixels
uniform int block_size : hint_range(2, 64) = 12;
uniform vec4 player_color : source_color = vec4(0.2, 0.8, 1.0, 1.0);
uniform float glow_strength : hint_range(0.0, 10.0) = 4.0;
uniform float glow_fade_range : hint_range(0.01, 0.5) = 0.15;

varying float v_world_y;

void vertex() {
	v_world_y = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	// Snap to block grid in screen space for the pixelated look.
	ivec2 block = ivec2(FRAGCOORD.xy) / block_size;
	// Per-block random value [0..1].
	float h = fract(sin(float(block.x) * 127.1 + float(block.y) * 311.7) * 43758.5453);

	// Normalised height: 0 = bottom of model, 1 = top.
	float y_norm = clamp((v_world_y - y_min) / max(y_max - y_min, 0.001), 0.0, 1.0);

	float threshold;
	float glow;
	if (dissolve_mode) {
		// Dissolve: top blocks disappear first (high y_norm → low threshold).
		threshold = (1.0 - y_norm) * 0.85 + h * 0.15;
		if (reveal_progress > threshold) {
			discard;
		}
		// Glow on blocks about to dissolve.
		float dist_to_edge = clamp((threshold - reveal_progress) / max(glow_fade_range, 0.001), 0.0, 1.0);
		glow = (1.0 - dist_to_edge) * glow_strength;
	} else {
		// Reveal: bottom blocks appear first (low y_norm → low threshold).
		threshold = y_norm * 0.85 + h * 0.15;
		if (reveal_progress < threshold) {
			discard;
		}
		// Glow on freshly revealed blocks.
		float age = clamp((reveal_progress - threshold) / max(glow_fade_range, 0.001), 0.0, 1.0);
		glow = (1.0 - age) * glow_strength;
	}

	// --- PBR pass-through ---
	vec4 col = albedo;
	if (use_albedo_texture) {
		col *= texture(albedo_texture, UV);
	}
	ALBEDO = col.rgb;

	METALLIC = metallic;
	if (use_metallic_texture) {
		METALLIC *= texture(metallic_texture, UV).r;
	}
	ROUGHNESS = roughness;
	if (use_roughness_texture) {
		ROUGHNESS *= texture(roughness_texture, UV).r;
	}
	SPECULAR = specular;
	if (use_normal_texture) {
		NORMAL_MAP = texture(normal_texture, UV).rgb;
		NORMAL_MAP_DEPTH = normal_scale;
	}
	EMISSION = player_color.rgb * glow;
}
