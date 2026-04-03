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

// ------- Dissolve effect -------
// progress = 0: fully visible/assembled. progress = 1: fully transparent/scattered.
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float y_min = -1.0;
uniform float y_max =  1.0;
uniform float cell_size : hint_range(0.01, 1.0) = 0.1;
uniform float sweep_spread : hint_range(0.0, 1.0) = 0.1;
uniform float fade_width : hint_range(0.0, 0.5) = 0.15;

varying float world_y_norm;
varying vec3  world_pos;

float hash2(vec2 p) {
    p = fract(p * vec2(127.1, 311.7));
    p += dot(p, p + 19.19);
    return fract(p.x * p.y);
}

void vertex() {
    vec4 wp = MODEL_MATRIX * vec4(VERTEX, 1.0);
    world_pos = wp.xyz;
    world_y_norm = clamp((wp.y - y_min) / max(y_max - y_min, 0.001), 0.0, 1.0);
}

void fragment() {
    // ---- PBR pass-through ----
    vec4 albedo_sample = albedo;
    if (use_albedo_texture) {
        albedo_sample *= texture(albedo_texture, UV);
    }
    ALBEDO = albedo_sample.rgb;
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

    // ---- Dissolve ----
    vec2 cell = floor(world_pos.xz / cell_size);
    float noise = hash2(cell);
    float depth = 1.0 - world_y_norm;
    float threshold = mix(-sweep_spread, 1.0 + sweep_spread + fade_width, progress);
    float value = noise * sweep_spread + depth;
    float alpha = smoothstep(threshold - fade_width, threshold, value);
    ALPHA = alpha;
}
