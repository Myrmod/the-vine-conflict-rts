shader_type spatial;
render_mode cull_back, blend_mix, depth_draw_opaque;

// ------- Original material properties (copied at setup time) -------
uniform vec4 albedo : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform sampler2D albedo_texture : source_color, hint_default_white, filter_linear_mipmap;
uniform bool use_albedo_texture = false;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.5;
uniform float specular : hint_range(0.0, 1.0) = 0.5;
uniform sampler2D roughness_texture : hint_default_white, filter_linear_mipmap;
uniform bool use_roughness_texture = false;
uniform sampler2D metallic_texture : hint_default_white, filter_linear_mipmap;
uniform bool use_metallic_texture = false;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap;
uniform bool use_normal_texture = false;
uniform float normal_scale : hint_range(-16.0, 16.0) = 1.0;

// ------- Assembly displacement -------
// progress = 0: fully assembled (vertices at real positions, original colour).
// progress = 1: all vertices at cylinder top, fully player-coloured.
uniform float progress : hint_range(0.0, 1.0) = 1.0;
uniform float y_min = 0.0;
uniform float y_max = 10.0;
uniform float cylinder_top = 12.0;     // world-Y of the cylinder top
uniform float cylinder_radius = 6.0;   // XZ radius of the cylinder
uniform vec4 player_color : source_color = vec4(0.3, 0.9, 1.0, 1.0);

// Per-vertex noise to stagger when each vertex settles.
float hash3(vec3 p) {
	p = fract(p * vec3(127.1, 311.7, 74.7));
	p += dot(p, p.yzx + 19.19);
	return fract((p.x + p.y) * p.z);
}

varying float v_displacement_amount;

void vertex() {
	vec4 wp = MODEL_MATRIX * vec4(VERTEX, 1.0);
	float y_range = max(y_max - y_min, 0.001);

	// Normalized height of this vertex (0 = bottom, 1 = top).
	float y_norm = clamp((wp.y - y_min) / y_range, 0.0, 1.0);

	// Per-vertex random offset so vertices don't all settle at the same time.
	float noise = hash3(VERTEX * 10.0);

	// Each vertex has a personal threshold: vertices with higher y_norm and
	// lower noise settle earlier (they're closer to the top already).
	// At progress=1 everything is at the top; as progress decreases toward 0,
	// vertices progressively move to their real position.
	float settle_threshold = noise * 0.6 + (1.0 - y_norm) * 0.4;
	float t = smoothstep(settle_threshold, settle_threshold + 0.15, progress);

	// Displaced position: same XZ but Y pushed to cylinder_top.
	vec3 displaced = wp.xyz;
	displaced.y = cylinder_top;

	// Lerp between real position and displaced position.
	vec3 final_pos = mix(wp.xyz, displaced, t);

	// Write back to local space.
	VERTEX = (inverse(MODEL_MATRIX) * vec4(final_pos, 1.0)).xyz;

	v_displacement_amount = t;
}

void fragment() {
	// ---- PBR pass-through ----
	vec4 albedo_sample = albedo;
	if (use_albedo_texture) {
		albedo_sample *= texture(albedo_texture, UV);
	}

	// Tint with player color based on how displaced this vertex still is.
	vec3 base_color = albedo_sample.rgb;
	vec3 tinted = mix(base_color, player_color.rgb, v_displacement_amount * 0.85);
	ALBEDO = tinted;

	// Add glow on displaced vertices.
	EMISSION = player_color.rgb * v_displacement_amount * 0.4;

	METALLIC = metallic;
	ROUGHNESS = roughness;
	SPECULAR = specular;
	if (use_roughness_texture) {
		ROUGHNESS *= texture(roughness_texture, UV).r;
	}
	if (use_metallic_texture) {
		METALLIC *= texture(metallic_texture, UV).r;
	}
	if (use_normal_texture) {
		NORMAL_MAP = texture(normal_texture, UV).rgb;
		NORMAL_MAP_DEPTH = normal_scale;
	}
}
