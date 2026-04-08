shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled;

uniform float cell_size = 1.0;
uniform float line_width : hint_range(0.01, 0.15) = 0.05;
uniform vec4 fill_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 line_color : source_color = vec4(1.0, 1.0, 1.0, 0.2);

varying vec3 local_pos;

void vertex() {
    local_pos = VERTEX;
}

void fragment() {
    vec2 uv = (local_pos.xz + cell_size * 0.5) / cell_size;
    vec2 grid = abs(fract(uv) - 0.5);
	// technically those lines are shifted 0.5 now on the real lines, but ingame it matches correctly
    float half_line = line_width * 0.5 / cell_size;
    float on_line = 1.0 - step(0.5 - half_line, max(grid.x, grid.y));

    vec3 col = mix(fill_color.rgb, line_color.rgb, on_line);
    float alpha = mix(fill_color.a, line_color.a, on_line);
    ALBEDO = col;
    if (alpha < 0.01) {
        discard;
    }
    ALPHA = alpha;
}