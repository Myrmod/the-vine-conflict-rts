shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec4 player_color : source_color = vec4(0.3, 0.8, 1.0, 1.0);
uniform float emission_strength : hint_range(0.0, 20.0) = 10.0;
uniform float flow_speed : hint_range(0.0, 0.5) = 0.06;
uniform float flow_scale : hint_range(0.1, 8.0) = 2.2;
uniform float rim_strength : hint_range(0.0, 3.0) = 0.9;
uniform float rim_power : hint_range(0.5, 8.0) = 2.8;
uniform float pulse_speed : hint_range(0.0, 3.0) = 0.22;
uniform float pulse_amount : hint_range(0.0, 1.0) = 0.16;

varying vec3 world_pos;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);

	float n000 = hash(i + vec3(0.0, 0.0, 0.0));
	float n100 = hash(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash(i + vec3(1.0, 1.0, 1.0));

	float nx00 = mix(n000, n100, f.x);
	float nx10 = mix(n010, n110, f.x);
	float nx01 = mix(n001, n101, f.x);
	float nx11 = mix(n011, n111, f.x);
	float nxy0 = mix(nx00, nx10, f.y);
	float nxy1 = mix(nx01, nx11, f.y);
	return mix(nxy0, nxy1, f.z);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 nrm = normalize(NORMAL);
	vec3 view_dir = normalize(VIEW);
	float t = TIME * flow_speed;

	vec3 p = (world_pos + nrm * 0.2) * flow_scale;
	float n1 = noise(p + vec3(t, 0.0, t * 0.7));
	float n2 = noise(p * 1.75 - vec3(0.0, t * 1.1, t * 0.35));
	float field = mix(n1, n2, 0.5);
	field = smoothstep(0.12, 0.88, field);

	float pulse = 1.0 + pulse_amount * sin(TIME * pulse_speed * 6.2831853);
	float rim = pow(1.0 - clamp(dot(nrm, view_dir), 0.0, 1.0), rim_power);

	vec3 base = player_color.rgb * (0.45 + field * 0.55);
	ALBEDO = base;
	ROUGHNESS = 0.22;
	METALLIC = 0.0;

	float glow = (0.35 + field * 0.65 + rim * rim_strength) * emission_strength * pulse;
	EMISSION = player_color.rgb * glow;
}
