// minimap_overlay.gdshader — Sci-Fi tactical radar, dark version
shader_type canvas_item;

uniform float time_scale        : hint_range(0.1, 3.0) = 1.0;
uniform float grid_alpha        : hint_range(0.0, 0.2) = 0.04;
uniform float sweep_alpha       : hint_range(0.0, 0.2) = 0.10;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.50;

void fragment() {
    vec4 base = texture(TEXTURE, UV);
    vec3 result = base.rgb;

    vec2 uv_c = UV - vec2(0.5);
    float dist = length(uv_c);
    float luma = dot(result, vec3(0.299, 0.587, 0.114));
    float darkness = 1.0 - luma; // maschera: 1.0 sui pixel scuri, 0.0 sui dot

    // -------------------------------------------------------
    // 1. VIGNETTE — scurisce i bordi, rispetta il centro
    //    Applicata PRIMA, così tutto il resto è coerente
    // -------------------------------------------------------
    float vignette = 1.0 - smoothstep(0.28, 0.50, dist) * vignette_strength;
    result *= vignette;

    // -------------------------------------------------------
    // 2. TINT FREDDO MINIMO — quasi impercettibile
    //    Solo un lievissimo shift verso blu/cyan sullo sfondo
    // -------------------------------------------------------
    result = mix(result, result * vec3(0.90, 0.97, 1.05), 0.15 * darkness);

    // -------------------------------------------------------
    // 3. GRIGLIA TATTICA — solo sullo sfondo scuro
    // -------------------------------------------------------
    float grid_size = 8.0;
    float gx = smoothstep(0.03, 0.0, abs(fract(UV.x * grid_size) - 0.5) - 0.47);
    float gy = smoothstep(0.03, 0.0, abs(fract(UV.y * grid_size) - 0.5) - 0.47);
    float grid = max(gx, gy) * darkness;
    result += vec3(0.0, 0.4, 0.7) * grid * grid_alpha;

    // -------------------------------------------------------
    // 4. RADAR SWEEP — sottile, mascherato sui pixel luminosi
    // -------------------------------------------------------
    float angle       = atan(uv_c.y, uv_c.x);
    float sweep_angle = mod(TIME * time_scale * 0.6, 6.28318);
    float sweep_diff  = mod(angle - sweep_angle + 6.28318, 6.28318);
    float sweep_trail = smoothstep(1.2, 0.0, sweep_diff) * sweep_alpha;
    sweep_trail *= smoothstep(0.48, 0.10, dist);
    float sweep_mask = 1.0 - smoothstep(0.15, 0.55, luma);
    result += vec3(0.0, 0.8, 0.45) * sweep_trail * sweep_mask;

    // -------------------------------------------------------
    // 5. ANELLI CONCENTRICI — appena visibili sullo sfondo
    // -------------------------------------------------------
    float ring_spacing = 0.16;
    float ring_raw = abs(fract(dist / ring_spacing + 0.5) - 0.5);
    float ring = smoothstep(0.015, 0.0, ring_raw) * 0.05 * darkness;
    result += vec3(0.0, 0.35, 0.65) * ring;

    // -------------------------------------------------------
    // 6. SCANLINES impercettibili
    // -------------------------------------------------------
    float scanline = 0.985 + 0.015 * sin(UV.y * 120.0 + TIME * time_scale * 0.3);
    result *= scanline;

    // -------------------------------------------------------
    // 7. BORDER GLOW — solo sull'anello del bordo
    // -------------------------------------------------------
    float border = smoothstep(0.46, 0.50, dist) * smoothstep(0.53, 0.50, dist);
    result += vec3(0.0, 0.6, 0.9) * border * 0.35;

    result = clamp(result, 0.0, 1.0);
    COLOR = vec4(result, base.a);
}