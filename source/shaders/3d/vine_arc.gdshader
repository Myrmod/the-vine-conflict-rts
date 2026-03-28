// 3D port of the 2D electricity shader (source/shaders/2d/electricity.gdshader).
// Uses the same PlaneMesh billboard technique as laser_beam.gdshader.
// MODEL_MATRIX column 0 = beam direction * length, column 2 = perpendicular * width.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

uniform vec3 effect_color : source_color = vec3(0.2, 0.3, 0.8);
uniform int octave_count : hint_range(1, 20) = 10;
uniform float amp_start = 0.5;
uniform float amp_coeff = 0.5;
uniform float freq_coeff = 2.0;
uniform float speed = 0.25;
uniform float fade : hint_range(0.0, 1.0) = 1.0;

float hash12(vec2 x) {
	return fract(cos(mod(dot(x, vec2(13.9898, 8.141)), 3.14)) * 43758.5453);
}

vec2 hash22(vec2 uv) {
	uv = vec2(dot(uv, vec2(127.1, 311.7)),
			dot(uv, vec2(269.5, 183.3)));
	return 2.0 * fract(sin(uv) * 43758.5453123) - 1.0;
}

float noise(vec2 uv) {
	vec2 iuv = floor(uv);
	vec2 fuv = fract(uv);
	vec2 blur = smoothstep(0.0, 1.0, fuv);
	return mix(mix(dot(hash22(iuv + vec2(0.0, 0.0)), fuv - vec2(0.0, 0.0)),
					dot(hash22(iuv + vec2(1.0, 0.0)), fuv - vec2(1.0, 0.0)), blur.x),
				mix(dot(hash22(iuv + vec2(0.0, 1.0)), fuv - vec2(0.0, 1.0)),
					dot(hash22(iuv + vec2(1.0, 1.0)), fuv - vec2(1.0, 1.0)), blur.x), blur.y) + 0.5;
}

float fbm(vec2 uv, int octaves) {
	float value = 0.0;
	float amplitude = amp_start;
	float frequency = 1.0;
	for (int i = 0; i < octaves; i++) {
		value += amplitude * noise(uv * frequency);
		uv *= freq_coeff;
		amplitude *= amp_coeff;
	}
	return value;
}

// --- Vertex: billboard (identical to laser_beam) ---

void vertex() {
	vec3 beam_dir = normalize((MODEL_MATRIX * vec4(1, 0, 0, 0)).xyz);
	float beam_length = length((MODEL_MATRIX * vec4(1, 0, 0, 0)).xyz);
	float beam_width = length((MODEL_MATRIX * vec4(0, 0, 1, 0)).xyz);
	vec3 center = (MODEL_MATRIX * vec4(0, 0, 0, 1)).xyz;

	vec3 to_cam = INV_VIEW_MATRIX[2].xyz;
	vec3 right_raw = cross(beam_dir, to_cam);
	if (length(right_raw) < 0.001) {
		right_raw = cross(beam_dir, vec3(0.0, 1.0, 0.0));
	}
	vec3 right = normalize(right_raw);

	vec3 world_pos = center
		+ beam_dir * VERTEX.x * beam_length
		+ right * VERTEX.z * beam_width;

	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world_pos, 1.0);
}

// --- Fragment: electricity (ported from 2D) ---
// In the 2D shader, UV.x is across the bolt and UV.y is along it.
// On the PlaneMesh, UV.x runs along the beam and UV.y runs across width.
// So we swap: along = UV.x, across = UV.y.

void fragment() {
	// Map PlaneMesh UVs to match the 2D shader's coordinate system
	// 2D shader expects: x = across (-1..1), y = along (-1..1)
	vec2 uv = vec2(
		2.0 * UV.y - 1.0,  // across the bolt width
		2.0 * UV.x - 1.0   // along the bolt length
	);

	uv += 2.0 * fbm(uv + TIME * speed, octave_count) - 1.0;

	float dist = abs(uv.x);
	vec3 color = effect_color * mix(0.0, 0.05, hash12(vec2(TIME))) / dist;
	color *= fade;

	float alpha = clamp(length(color), 0.0, 1.0);
	ALBEDO = color;
	EMISSION = color;
	ALPHA = alpha;
}
