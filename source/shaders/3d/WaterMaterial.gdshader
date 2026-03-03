shader_type spatial;

uniform sampler2D water_normal_noise;
uniform sampler2D water_normal_noise_b;
uniform float blend_amount : hint_range(0.0, 1.0) = 0.5;
uniform vec3 water_color : source_color;
uniform float time_scale : hint_range(0.0, 10.0, 0.25) = 1.0;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable;
uniform float uv_scale : hint_range(0.0, 1.0, 0.25) = 2.0;

//void vertex() {
	////float height = texture(water_normal_noise, UV).r * height_scale;
    ////VERTEX.y += height;
//}

void fragment() {
	// this code adds the waves
	vec2 _uv = UV * uv_scale;
	_uv.x += sin(TIME * time_scale + (_uv.x +_uv.y) * 25.0) * 0.01;
	_uv.y += cos(TIME * time_scale + (_uv.x -_uv.y) * 25.0) * 0.01;

	ALBEDO = texture(screen_texture, SCREEN_UV).rgb;
	// applies the noise from the Inspector to the normal map of the mesh
	vec3 normal1 = texture(water_normal_noise, _uv).rgb;
    vec3 normal2 = texture(water_normal_noise_b, _uv).rgb;
	//NORMAL_MAP = mix(normal1, normal2, blend_amount);
	NORMAL_MAP = normal1;
	NORMAL *= 0.5;
	ROUGHNESS = 0.2;
}