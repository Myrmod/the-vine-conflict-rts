shader_type spatial;

// Use Godot's built-in PBR lighting (same as 3D models)
render_mode
    cull_back,
    depth_draw_opaque;

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
// Sampled with filter_linear so the GPU interpolates cell boundaries into
// a smooth 0→1 gradient that acts as an implicit SDF.
uniform sampler2D creep_tex : hint_default_black, filter_linear, repeat_disable;
// Tileable creep ground texture (single image, no atlas).
uniform sampler2D creep_ground_tex : source_color, hint_default_black, filter_linear, repeat_enable;
// Normal map for the creep ground texture.
uniform sampler2D creep_normal_tex : hint_default_white, filter_linear, repeat_enable;
uniform bool creep_enabled = false;
// Strength of the creep normal map (0 = flat, 1 = full).
uniform float creep_normal_strength : hint_range(0.0, 1.0) = 0.3;
uniform vec2 creep_map_size = vec2(50.0, 50.0);
// How many map cells the creep ground texture spans before repeating.
uniform float creep_uv_scale : hint_range(1.0, 16.0) = 4.0;
// Controls the width of the soft edge transition.
uniform float creep_edge_width : hint_range(0.01, 0.3) = 0.06;
// How much the procedural noise distorts the edge (0 = smooth circle, 0.3 = very organic).
uniform float creep_edge_distortion : hint_range(0.0, 0.5) = 0.18;
// Scale of the edge distortion pattern (higher = finer wobble).
uniform float creep_edge_noise_scale : hint_range(1.0, 20.0) = 5.0;

// Procedural hash-based value noise (no texture needed).
float _creep_hash(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float _creep_noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f); // smoothstep interpolation
    float a = _creep_hash(i);
    float b = _creep_hash(i + vec2(1.0, 0.0));
    float c = _creep_hash(i + vec2(0.0, 1.0));
    float d = _creep_hash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float _creep_fbm(vec2 p) {
    return _creep_noise(p) * 0.65 + _creep_noise(p * 2.13 + vec2(5.3, 1.7)) * 0.35;
}

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
    // Bilinear-filtered creep_tex gives a smooth 0→1 gradient at cell edges.
    // Procedural noise distorts the threshold for organic, irregular borders.
    if (creep_enabled) {
        float creep_sdf = texture(creep_tex, UV).r;
        if (creep_sdf > 0.01) {
            float noise = _creep_fbm(UV * creep_map_size * creep_edge_noise_scale);
            float threshold = mix(0.25 - creep_edge_distortion, 0.25 + creep_edge_distortion, noise);
            float creep_alpha = smoothstep(threshold, threshold + creep_edge_width, creep_sdf);

            if (creep_alpha > 0.001) {
                vec2 creep_uv = UV * creep_map_size / creep_uv_scale;
                vec3 creep_rgb = texture(creep_ground_tex, creep_uv).rgb;
                vec3 creep_nrm = mix(vec3(0.5, 0.5, 1.0), texture(creep_normal_tex, creep_uv).rgb, creep_normal_strength);

                ALBEDO           = mix(ALBEDO, creep_rgb, creep_alpha);
                final_normal_map = mix(final_normal_map, creep_nrm, creep_alpha);
                final_roughness  = mix(final_roughness, 0.8, creep_alpha);
                final_ao         = mix(final_ao, 1.0, creep_alpha);
            }
        }
    }

    // Apply terrain brightness to final albedo (affects both terrain and creep)
    ALBEDO *= terrain_brightness;

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