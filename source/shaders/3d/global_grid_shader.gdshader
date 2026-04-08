shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_always;

uniform float cell_size = 1.0;
uniform float line_width : hint_range(0.01, 0.15) = 0.05;
uniform float line_alpha : hint_range(0.0, 1.0) = 1.0;
uniform float fill_alpha : hint_range(0.0, 1.0) = 0.12;

varying vec3 local_pos;
varying vec4 cell_color;

void vertex() {
    local_pos = VERTEX;
    cell_color = COLOR;
}

void fragment() {
    vec2 uv = local_pos.xz / cell_size;
    vec2 grid = abs(fract(uv) - 0.5);
    float half_line = line_width * 0.5 / cell_size;
    float on_line = 1.0 - step(0.5 - half_line, max(grid.x, grid.y));

    ALBEDO = cell_color.rgb;
    float alpha = mix(fill_alpha, line_alpha, on_line);
    if (alpha < 0.001) {
        discard;
    }
    ALPHA = alpha;
}
