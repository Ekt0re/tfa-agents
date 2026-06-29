// laser_beam.gdshader
// Shader per il raggio laser della torretta.
// Applicato su una Line2D (canvas_item).
// Parametri chiave:
//   color         — colore base del laser
//   glow_strength — intensità del bloom
//   pulse_speed   — velocità pulsazione
//   noise_amount  — distorsione del bordo (qualità alta)
//   quality       — 0.0 = bassa (solo colore), 1.0 = alta (glow + noise + pulse)
shader_type canvas_item;

uniform vec4  color         : source_color = vec4(1.0, 0.2, 0.1, 0.9);
uniform float glow_strength : hint_range(0.0, 4.0) = 2.0;
uniform float pulse_speed   : hint_range(0.0, 10.0) = 4.0;
uniform float noise_amount  : hint_range(0.0, 0.05) = 0.012;
uniform float quality       : hint_range(0.0, 1.0)  = 1.0;

// Pseudo-random hash 1D
float hash(float n) {
    return fract(sin(n) * 43758.5453123);
}

// Noise 1D semplice
float noise1(float x) {
    float i = floor(x);
    float f = fract(x);
    float u = f * f * (3.0 - 2.0 * f);
    return mix(hash(i), hash(i + 1.0), u);
}

void fragment() {
    vec2 uv = UV;

    // Distanza dal centro verticale della line (UV.y va da 0 a 1)
    float dist_center = abs(uv.y - 0.5) * 2.0; // 0 al centro, 1 ai bordi

    if (quality < 0.5) {
        // ── QUALITÀ BASSA: solo colore piatto con fade alfa bordi ──
        float alpha = smoothstep(1.0, 0.0, dist_center * 1.2);
        COLOR = vec4(color.rgb, color.a * alpha * COLOR.a);
    } else {
        // ── QUALITÀ ALTA ──

        // Pulsazione temporale
        float pulse = 0.75 + 0.25 * sin(TIME * pulse_speed);

        // Noise per bordi irregolari (solo alta qualità)
        float n = noise1(uv.x * 24.0 + TIME * 3.0) * noise_amount;
        float dist_noisy = abs(uv.y - 0.5 + n) * 2.0;

        // Core brillante stretto
        float core  = smoothstep(0.18, 0.0,  dist_noisy);
        // Glow morbido attorno
        float glow  = smoothstep(1.0,  0.0,  dist_noisy);
        // Bloom esterno (screen-space simulato)
        float bloom = smoothstep(1.2,  0.0,  dist_center) * glow_strength * 0.3;

        // Fade lungo UV.x per head e tail (evita clip duro)
        float edge_fade = smoothstep(0.0, 0.04, uv.x) * smoothstep(1.0, 0.96, uv.x);

        float intensity = (core * 1.5 + glow * 0.5 + bloom) * pulse * edge_fade;

        vec3 final_rgb = color.rgb + vec3(core) * glow_strength * 0.25;
        float final_a  = clamp(intensity * color.a, 0.0, 1.0);

        COLOR = vec4(final_rgb, final_a * COLOR.a);
    }
}
