shader_type spatial;
render_mode cull_back;

// Dissolve controls
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float edge_width : hint_range(0.0, 0.2) = 0.06;
uniform vec3 edge_color : source_color = vec3(0.3, 0.8, 1.0);
uniform float edge_intensity : hint_range(0.0, 20.0) = 6.0;
uniform float noise_scale : hint_range(0.5, 20.0) = 4.0;

// Original surface properties
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool has_albedo_tex = false;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D metallic_tex : filter_linear_mipmap, repeat_enable;
uniform bool has_metallic_tex = false;
uniform int metallic_tex_channel = 0;
uniform float roughness : hint_range(0.0, 1.0) = 0.5;
uniform sampler2D roughness_tex : filter_linear_mipmap, repeat_enable;
uniform bool has_roughness_tex = false;
uniform int roughness_tex_channel = 1;
uniform sampler2D normal_tex : filter_linear_mipmap, repeat_enable;
uniform bool has_normal_tex = false;

varying vec3 model_pos;

vec3 _hash(vec3 p) {
	p = vec3(dot(p, vec3(127.1, 311.7, 74.7)),
			  dot(p, vec3(269.5, 183.3, 246.1)),
			  dot(p, vec3(113.5, 271.9, 124.6)));
	return fract(sin(p) * 43758.5453123);
}

float noise3d(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);

	float a = dot(_hash(i), vec3(1.0));
	float b = dot(_hash(i + vec3(1, 0, 0)), vec3(1.0));
	float c = dot(_hash(i + vec3(0, 1, 0)), vec3(1.0));
	float d = dot(_hash(i + vec3(1, 1, 0)), vec3(1.0));
	float e = dot(_hash(i + vec3(0, 0, 1)), vec3(1.0));
	float ff = dot(_hash(i + vec3(1, 0, 1)), vec3(1.0));
	float g = dot(_hash(i + vec3(0, 1, 1)), vec3(1.0));
	float h = dot(_hash(i + vec3(1, 1, 1)), vec3(1.0));

	float x1 = mix(a, b, f.x);
	float x2 = mix(c, d, f.x);
	float x3 = mix(e, ff, f.x);
	float x4 = mix(g, h, f.x);
	float y1 = mix(x1, x2, f.y);
	float y2 = mix(x3, x4, f.y);
	return fract(mix(y1, y2, f.z));
}

float channel_value(vec4 tex, int ch) {
	if (ch == 0) return tex.r;
	if (ch == 1) return tex.g;
	if (ch == 2) return tex.b;
	if (ch == 3) return tex.a;
	return dot(tex.rgb, vec3(0.333333)); // channel 4 = grayscale
}

void vertex() {
	model_pos = VERTEX;
}

void fragment() {
	// --- Dissolve ---
	float n = noise3d(model_pos * noise_scale);
	// Sweep top-to-bottom: top dissolves first
	float height_bias = 1.0 - (model_pos.y + 1.0) * 0.5;
	float dissolve = mix(n, height_bias, 0.6);
	float threshold = progress * 1.3;

	if (dissolve < threshold) {
		discard;
	}

	// --- Original surface ---
	vec4 albedo = albedo_color;
	if (has_albedo_tex) {
		albedo *= texture(albedo_tex, UV);
	}
	ALBEDO = albedo.rgb;

	float m = metallic;
	if (has_metallic_tex) {
		m *= channel_value(texture(metallic_tex, UV), metallic_tex_channel);
	}
	METALLIC = m;

	float r = roughness;
	if (has_roughness_tex) {
		r *= channel_value(texture(roughness_tex, UV), roughness_tex_channel);
	}
	ROUGHNESS = r;

	if (has_normal_tex) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
	}

	// --- Edge glow ---
	float edge = smoothstep(threshold, threshold + edge_width, dissolve);
	EMISSION = edge_color * edge_intensity * (1.0 - edge);
}
