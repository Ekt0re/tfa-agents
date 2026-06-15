shader_type canvas_item;

uniform float health_pct : hint_range(0.0, 1.0) = 1.0;
uniform float time_scale : hint_range(0.1, 4.0) = 1.0;
uniform float glow_width : hint_range(0.01, 0.15) = 0.06;

void fragment() {
	// Fuori dall'area riempita: pixel completamente trasparente
	if (UV.x > health_pct) {
		COLOR = vec4(0.0);
	} else {
		// --- Health-dependent color ---
		vec3 full_col = vec3(0.55, 0.88, 0.05);
		vec3 mid_col  = vec3(0.92, 0.80, 0.08);
		vec3 low_col  = vec3(0.90, 0.18, 0.12);

		vec3 bar_color;
		if (health_pct > 0.5) {
			bar_color = mix(mid_col, full_col, (health_pct - 0.5) * 2.0);
		} else {
			bar_color = mix(low_col, mid_col, health_pct * 2.0);
		}

		// --- Pulsazione globale ---
		float pulse = 1.0 + 0.04 * sin(TIME * time_scale * 2.0);

		// --- Glow sul bordo del riempimento ---
		float edge_dist = health_pct - UV.x;
		float edge_glow = smoothstep(glow_width, 0.0, edge_dist);
		edge_glow *= (0.5 + 0.5 * sin(TIME * time_scale * 2.2)) * 0.55;

		// --- Fill finale ---
		vec3 fill = bar_color * pulse;
		fill += vec3(1.0, 1.0, 0.85) * edge_glow;

		COLOR = vec4(clamp(fill, 0.0, 1.0), 1.0);
	}
}