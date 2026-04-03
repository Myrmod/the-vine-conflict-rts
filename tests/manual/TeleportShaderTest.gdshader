shader_type spatial;
render_mode cull_back, blend_mix, depth_draw_opaque;

// progress = 0: fully visible. progress = 1: fully transparent.
uniform float progress : hint_range(0.0, 1.0) = 0.0;
// world-space Y range of the entire model (set from script)
uniform float y_min = -1.0;
uniform float y_max =  1.0;
// size of each noise "pixel" in world units
uniform float cell_size : hint_range(0.01, 1.0) = 0.1;
// how much the sweep spreads beyond a hard line (0 = sharp wave front)
uniform float sweep_spread : hint_range(0.0, 1.0) = 0.1;
// how long each cell takes to fade (in threshold units); 0 = instant snap
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
    vec2 cell = floor(world_pos.xz / cell_size);
    float noise = hash2(cell);
    float depth = 1.0 - world_y_norm;
    float threshold = mix(-sweep_spread, 1.0 + sweep_spread + fade_width, progress);
    float value = noise * sweep_spread + depth;
    float alpha = smoothstep(threshold - fade_width, threshold, value);
    ALPHA = alpha;
}