shader_type spatial;

// Custom light() replaces built-in diffuse/specular models
render_mode
    cull_back,
    depth_draw_opaque,
    diffuse_lambert,
    specular_disabled;

const int MAX_TERRAINS = 16;
const int MAX_SPLATS = 4;

uniform sampler2D albedo_tex[MAX_TERRAINS];
uniform sampler2D normal_tex[MAX_TERRAINS];
uniform sampler2D roughness_tex[MAX_TERRAINS];
uniform sampler2D ao_tex[MAX_TERRAINS];
uniform sampler2D height_tex[MAX_TERRAINS];

uniform sampler2D splat_tex[MAX_SPLATS];

uniform int terrain_count = 16;
uniform int splat_count = 4;

uniform float uv_scale = 6.0;
uniform float height_strength = 0.05;
// Height-based micro-detail in transition zones only (0 = off).
// Low values (0.5–2.0) add subtle variation where textures meet.
uniform float height_blend_sharpness = 1.0;

// Normal map depth (replaces old normal_strength; fed to NORMAL_MAP_DEPTH)
uniform float normal_map_depth : hint_range(0.0, 2.0) = 1.0;

// --- Blinn-Phong lighting ---
uniform float shininess : hint_range(2.0, 512.0) = 20.0;
uniform float specular_intensity : hint_range(0.0, 2.0) = 0.1;
uniform vec3  specular_color : source_color = vec3(1.0);
uniform float fresnel_power : hint_range(1.0, 10.0) = 5.0;
uniform float fresnel_strength : hint_range(0.0, 1.0) = 0.25;

// Subtle ambient fill so textures remain visible even in full shadow
// (Only needed if Environment ambient is disabled; keep at 0.0 otherwise)
uniform float ambient_fill : hint_range(0.0, 0.5) = 0.0;
uniform vec3  ambient_tint : source_color = vec3(0.4, 0.45, 0.55);

// Upper (later-painted) layers dominate the blended normal map
uniform float normal_layer_priority : hint_range(1.0, 8.0) = 2.5;

// Overall terrain brightness multiplier (lets you dim terrain independently
// of the scene's directional / ambient light so structures stay bright).
uniform float terrain_brightness : hint_range(0.0, 2.0) = 1.0;

// --- Grid-based height displacement ---
// A single-channel float texture (FORMAT_RF) the same size as the map grid.
// Each texel stores the world-space height for that cell.
uniform sampler2D grid_height_tex : filter_nearest;
uniform float grid_height_scale : hint_range(0.0, 10.0) = 1.0;

// --- Edge-only blending ---
// Raises weights to a power then renormalizes, making dominant textures
// occupy most of the surface with blending only at narrow transition edges.
uniform float blend_sharpness : hint_range(1.0, 32.0) = 8.0;
// Height uses an even sharper blend so terrain height snaps to the dominant
// layer quickly, avoiding mushy height transitions.
uniform float height_edge_sharpness : hint_range(1.0, 64.0) = 16.0;

// --- Layer mask (for split high-ground / low-ground planes) ---
// R8 texture same size as grid: 1.0 = render, 0.0 = discard.
// When not set (all white default) the full terrain is rendered.
uniform sampler2D layer_mask_tex : hint_default_white, filter_nearest;
uniform bool layer_mask_enabled = false;

// --- Terrain hole mask ---
// R8 texture same size as grid: 1.0 = render, 0.0 = discard.
// Used for decorative cutouts such as the vine pit under ResourceSpawner.
uniform sampler2D hole_mask_tex : hint_default_white, filter_nearest;
uniform bool hole_mask_enabled = false;

// --- Paintable alpha mask ---
// R8 texture same size as grid: 1.0 = fully opaque, 0.0 = transparent (discard).
// Painted by the AlphaBrush tool in the map editor.
uniform sampler2D alpha_mask_tex : hint_default_white, filter_linear;
uniform bool alpha_mask_enabled = false;

// Debug: flat colour override for visualising terrain layers.
uniform bool debug_layer_color_enabled = false;
uniform vec3 debug_layer_color : source_color = vec3(1.0);

// --- Creep overlay (Radix faction ground coverage) ---
// R8 texture, same size as the map grid: > 0 = creep present.
uniform sampler2D creep_tex : hint_default_black, filter_nearest, repeat_disable;
// Horizontal Wang 2-corner atlas (16 columns).
// 6-column × 3-row orthogonal + inner-corner atlas (960×960 px per tile).
uniform sampler2D creep_atlas_tex : hint_default_black, filter_linear, repeat_disable;
uniform bool creep_enabled = false;
uniform vec2 creep_map_size = vec2(50.0, 50.0);

void vertex() {
    // Map each PlaneMesh vertex to the centre of its corresponding texel.
    // PlaneMesh has map_size+1 vertices (UV 0..1) but only map_size texels,
    // so boundary vertices sit between two texels.  Shift +0.5 texel and
    // clamp so the last vertex samples the last texel instead of wrapping.
    vec2 grid_ts = vec2(textureSize(grid_height_tex, 0));
    vec2 grid_uv = clamp(UV + 0.5 / grid_ts, 0.5 / grid_ts, 1.0 - 0.5 / grid_ts);

    // --- Grid-based height (macro displacement from MapResource.height_grid) ---
    if (grid_height_scale > 0.0) {
        float grid_h = texture(grid_height_tex, grid_uv).r;
        VERTEX.y += grid_h * grid_height_scale;
    }

    // --- Texture-based micro displacement (height maps per terrain layer) ---
    if (height_strength > 0.0) {
        vec2 tiled_uv = UV * uv_scale;

        float total_weight = 0.0;
        float height_accum = 0.0;

        // Collect raw splat weights first
        float raw_w[MAX_TERRAINS];
        for (int i = 0; i < MAX_TERRAINS; i++) raw_w[i] = 0.0;

        for (int s = 0; s < MAX_SPLATS; s++) {
            if (s >= splat_count) break;

            vec4 splat = texture(splat_tex[s], UV);

            for (int c = 0; c < 4; c++) {
                int idx = s * 4 + c;
                if (idx >= terrain_count) break;

                float w = splat[c];
                if (w <= 0.001) continue;
                raw_w[idx] = w;
            }
        }

        // Sharpen weights for height (snap to dominant layer)
        float sharp_total = 0.0;
        float sharp_w[MAX_TERRAINS];
        for (int i = 0; i < MAX_TERRAINS; i++) {
            sharp_w[i] = pow(raw_w[i], height_edge_sharpness);
            sharp_total += sharp_w[i];
        }

        if (sharp_total > 0.0) {
            for (int i = 0; i < MAX_TERRAINS; i++) {
                if (sharp_w[i] <= 0.0) continue;
                float w = sharp_w[i] / sharp_total;
                float h = texture(height_tex[i], tiled_uv).r;
                height_accum += h * w;
            }
            VERTEX.y += height_accum * height_strength;
        }
    }
}

void fragment() {
    // Discard fragments outside this layer.
    // No half-texel offset here — interpolated UVs already land inside the
    // correct texel.  Only clamp the upper bound so UV=1.0 doesn't wrap.
    if (layer_mask_enabled) {
        vec2 mask_ts = vec2(textureSize(layer_mask_tex, 0));
        vec2 mask_uv = min(UV, 1.0 - 0.5 / mask_ts);
        float mask_val = texture(layer_mask_tex, mask_uv).r;
        if (mask_val < 0.5) discard;
    }

    if (hole_mask_enabled) {
        vec2 hole_ts = vec2(textureSize(hole_mask_tex, 0));
        vec2 hole_uv = min(UV, 1.0 - 0.5 / hole_ts);
        float hole_val = texture(hole_mask_tex, hole_uv).r;
        if (hole_val < 0.5) discard;
    }

    if (alpha_mask_enabled) {
        vec2 alpha_ts = vec2(textureSize(alpha_mask_tex, 0));
        vec2 alpha_uv = min(UV, 1.0 - 0.5 / alpha_ts);
        float alpha_val = texture(alpha_mask_tex, alpha_uv).r;
        if (alpha_val < 0.5) discard;
    }

    vec2 tiled_uv = UV * uv_scale;

    float weights[MAX_TERRAINS];
    float total_weight = 0.0;

    // === Compute weights from painted splat maps ===
    for (int i = 0; i < MAX_TERRAINS; i++)
        weights[i] = 0.0;

    for (int s = 0; s < MAX_SPLATS; s++) {
        if (s >= splat_count) break;

        vec4 splat = texture(splat_tex[s], UV);

        for (int c = 0; c < 4; c++) {
            int idx = s * 4 + c;
            if (idx >= terrain_count) break;

            float base_w = splat[c];
            if (base_w <= 0.001) continue;

            weights[idx] = base_w;
            total_weight += base_w;
        }
    }

    if (total_weight < 0.0001) discard;

    // Normalise raw painted weights
    for (int i = 0; i < MAX_TERRAINS; i++)
        weights[i] /= total_weight;

    // --- Height micro-detail: only affects the transition zone ---
    // Detect whether this pixel is in a transition (multiple textures present).
    // Find the maximum painted weight to gauge dominance.
    float max_w = 0.0;
    for (int i = 0; i < MAX_TERRAINS; i++)
        max_w = max(max_w, weights[i]);

    // transition_amount is ~0 where one texture fully dominates, ~1 at 50/50 edges
    float transition_amount = 1.0 - max_w;

    if (height_blend_sharpness > 0.001 && transition_amount > 0.01) {
        // Modulate weights by height, scaled by how much we're in a transition
        float h_total = 0.0;
        for (int i = 0; i < MAX_TERRAINS; i++) {
            if (weights[i] <= 0.001) continue;
            float h = texture(height_tex[i], tiled_uv).r;
            // Only apply height influence proportional to transition_amount
            weights[i] *= mix(1.0, 1.0 + h * height_blend_sharpness, transition_amount);
            h_total += weights[i];
        }
        // Re-normalise after height adjustment
        if (h_total > 0.0) {
            for (int i = 0; i < MAX_TERRAINS; i++)
                weights[i] /= h_total;
        }
    }

    // === Sharpen weights so textures are crisp, blending only at edges ===
    float sharp_total = 0.0;
    for (int i = 0; i < MAX_TERRAINS; i++) {
        weights[i] = pow(weights[i], blend_sharpness);
        sharp_total += weights[i];
    }
    // Renormalise after sharpening
    if (sharp_total > 0.0) {
        for (int i = 0; i < MAX_TERRAINS; i++)
            weights[i] /= sharp_total;
    }

    vec3  final_albedo     = vec3(0.0);
    vec3  final_normal_map = vec3(0.0);
    float normal_w_total   = 0.0;
    float final_roughness  = 0.0;
    float final_ao         = 0.0;

    // === Blend layers – upper textures dominate normals ===
    for (int i = 0; i < terrain_count; i++) {
        float w = weights[i];
        if (w <= 0.0001) continue;

        vec3  albedo     = texture(albedo_tex[i], tiled_uv).rgb;
        // Keep raw [0,1] normal-map texel – Godot converts via NORMAL_MAP_DEPTH
        vec3  raw_normal = texture(normal_tex[i], tiled_uv).rgb;
        float rough      = texture(roughness_tex[i], tiled_uv).r;
        float ao         = texture(ao_tex[i], tiled_uv).r;

        // Priority ramp: layer 0 → 1×, last layer → normal_layer_priority ×
        float layer_t  = float(i) / float(max(terrain_count - 1, 1));
        float priority = mix(1.0, normal_layer_priority, layer_t);
        float nw       = w * priority;

        final_albedo     += albedo * w;
        final_normal_map += raw_normal * nw;
        normal_w_total   += nw;
        final_roughness  += rough * w;
        final_ao         += ao * w;
    }

    // Weighted-average normal (stays in [0,1] tangent-space encoding)
    if (normal_w_total > 0.0) {
        final_normal_map /= normal_w_total;
    }

    ALBEDO           = final_albedo;

    // === Creep overlay (Radix ground coverage) ===
    // Atlas: creep_terrain6x3.png — 6 cols × 3 rows (see CreepAtlas.gd).
    // Left half (col 0–2): outer boundary tiles, selected by orthogonal mask.
    // Right half (col 3–5): inner corner tiles, selected by diagonal absence.
    if (creep_enabled) {
        float creep_val = texture(creep_tex, UV).r;
        if (creep_val > 0.01) {
            // Cell coordinate from UV (UV 0..1 maps to 0..map_size cells).
            vec2 cell_coord = UV * creep_map_size;
            vec2 cell_floor = floor(cell_coord);
            vec2 cell_frac  = cell_coord - cell_floor;

            // Sample the four orthogonal neighbours (centre of each adjacent cell).
            vec2 inv_cs = 1.0 / creep_map_size;
            float c_n = step(0.01, texture(creep_tex, (cell_floor + vec2( 0.5, -0.5)) * inv_cs).r);
            float c_e = step(0.01, texture(creep_tex, (cell_floor + vec2( 1.5,  0.5)) * inv_cs).r);
            float c_s = step(0.01, texture(creep_tex, (cell_floor + vec2( 0.5,  1.5)) * inv_cs).r);
            float c_w = step(0.01, texture(creep_tex, (cell_floor + vec2(-0.5,  0.5)) * inv_cs).r);

            // 4-bit orthogonal mask: N=1, E=2, S=4, W=8.
            int ortho_mask = int(c_n) * 1 + int(c_e) * 2 + int(c_s) * 4 + int(c_w) * 8;

            float atlas_col;
            float atlas_row;
            if (ortho_mask == 15) {
                // All orthogonal neighbours present — fully covered interior cell.
                atlas_col = 4.0; atlas_row = 1.0; // ALL
            } else if (ortho_mask == 6)  { atlas_col = 0.0; atlas_row = 0.0; } // NW outer
            else if (ortho_mask == 14) { atlas_col = 1.0; atlas_row = 0.0; } // N  outer edge
            else if (ortho_mask == 12) { atlas_col = 2.0; atlas_row = 0.0; } // NE outer
            else if (ortho_mask == 7)  { atlas_col = 0.0; atlas_row = 1.0; } // W  outer edge
            else if (ortho_mask == 13) { atlas_col = 2.0; atlas_row = 1.0; } // E  outer edge
            else if (ortho_mask == 3)  { atlas_col = 0.0; atlas_row = 2.0; } // SW outer
            else if (ortho_mask == 11) { atlas_col = 1.0; atlas_row = 2.0; } // S  outer edge
            else if (ortho_mask == 9)  { atlas_col = 2.0; atlas_row = 2.0; } // SE outer
            else                       { atlas_col = 4.0; atlas_row = 1.0; } // fallback ALL

            float atlas_u = (atlas_col + cell_frac.x) / 6.0;
            float atlas_v = (atlas_row + cell_frac.y) / 3.0;
            vec4 creep_color = texture(creep_atlas_tex, vec2(atlas_u, atlas_v));

            // Creep is the topmost layer — fully replace terrain output.
            ALBEDO           = mix(ALBEDO, creep_color.rgb, creep_color.a);
            final_normal_map = mix(final_normal_map, vec3(0.5, 0.5, 1.0), creep_color.a);
            final_roughness  = mix(final_roughness, 0.8, creep_color.a);
            final_ao         = mix(final_ao, 1.0, creep_color.a);
        }
    }

    // Debug layer colour override
    if (debug_layer_color_enabled) {
        ALBEDO = debug_layer_color;
    }

    NORMAL_MAP       = final_normal_map;
    NORMAL_MAP_DEPTH = normal_map_depth;
    ROUGHNESS        = clamp(final_roughness, 0.05, 1.0);
    AO               = final_ao;

    // Ambient fill: optional emissive for shadow readability (default off;
    // Godot's Environment ambient light handles shadow fill instead)
    if (ambient_fill > 0.001) {
        EMISSION = ALBEDO * ambient_tint * ambient_fill * final_ao;
    }
}

// ============================================================
//  Blinn-Phong per-light function
// ============================================================
void light() {
    // Half-vector between view and light
    vec3 H = normalize(VIEW + LIGHT);

    // --- Diffuse (Lambert with soft wrap) ---
    float NdotL = dot(NORMAL, LIGHT);
    // Slight wrap so shadow transition is softer / more natural
    float wrap           = 0.03;
    float wrapped_NdotL  = max((NdotL + wrap) / (1.0 + wrap), 0.0);

    vec3 diffuse = ALBEDO * wrapped_NdotL;

    // --- Specular (Blinn-Phong) ---
    float NdotH = max(dot(NORMAL, H), 0.0);

    // Roughness narrows / broadens the highlight
    float r2 = ROUGHNESS * ROUGHNESS;
    float eff_shininess = shininess * max(1.0 - r2, 0.04);
    eff_shininess = max(eff_shininess, 2.0);

    float spec = pow(NdotH, eff_shininess);

    // Energy-conserving normalization (Blinn-Phong)
    float norm_factor = (eff_shininess + 8.0) / (8.0 * 3.14159265);

    // Fresnel (Schlick approximation) – brighter highlights at glancing angles
    float NdotV      = max(dot(NORMAL, VIEW), 0.0);
    float fresnel    = pow(1.0 - NdotV, fresnel_power);
    float spec_scale = specular_intensity + fresnel * fresnel_strength;

    // Attenuate specular on rough surfaces
    spec_scale *= (1.0 - ROUGHNESS * 0.7);

    vec3 specular = specular_color * spec * spec_scale * norm_factor;

    // Accumulate (+=, not =, so multiple lights and shadows stack correctly)
    DIFFUSE_LIGHT  += diffuse  * ATTENUATION * LIGHT_COLOR * terrain_brightness;
    SPECULAR_LIGHT += specular * ATTENUATION * LIGHT_COLOR * terrain_brightness;
}