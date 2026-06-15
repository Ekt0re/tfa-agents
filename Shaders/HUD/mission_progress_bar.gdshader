// mission_progress_bar.gdshader
// Applicare a MissionProgressBar (ProgressBar) come ShaderMaterial.
// Dal GDScript:
//   _progress_bar.material.set_shader_parameter("fill_pct", value / max_value)
//   _progress_bar.material.set_shader_parameter("mission_state", 0.0 / 1.0 / -1.0)
shader_type canvas_item;

uniform float fill_pct      : hint_range(0.0, 1.0) = 0.0;
uniform float mission_state : hint_range(-1.0, 1.0) = 0.0;

void fragment() {
	vec4 base = texture(TEXTURE, UV);

	// ---------------------------------------------------------------
	// Area vuota: trasparente (niente sfondo bianco)
	// ---------------------------------------------------------------
	if (UV.x > fill_pct) {
		COLOR = vec4(0.0, 0.0, 0.0, 0.0);
	} else {
		// Colore base: verde normale, verde brillante se completato, rosso se fallito
		float completed = smoothstep(0.5, 0.8, mission_state);
		float failed    = smoothstep(-0.8, -0.5, -mission_state);

		vec3 col_normal    = vec3(0.30, 0.85, 0.35);  // verde
		vec3 col_completed = vec3(0.10, 1.00, 0.40);  // verde brillante
		vec3 col_failed    = vec3(0.90, 0.15, 0.15);  // rosso

		vec3 bar_color = mix(col_normal, col_completed, completed);
		bar_color      = mix(bar_color,  col_failed,    failed);

		// --- Shimmer: luce che scorre da sinistra a destra ---
		float shimmer_pos = fract(TIME * 0.7);
		// Visibile solo dentro il fill (UV.x normalizzato sul fill)
		float uv_norm  = UV.x / max(fill_pct, 0.001);
		float shimmer  = smoothstep(0.08, 0.0, abs(uv_norm - shimmer_pos));
		shimmer       *= 0.35;

		// --- Gradiente verticale (top chiaro, bottom scuro) ---
		float v_grad = mix(1.0, 0.65, UV.y);

		// --- Edge glow al bordo destro del fill ---
		float edge_dist = fill_pct - UV.x;
		float edge_glow = smoothstep(0.05, 0.0, edge_dist);
		edge_glow      *= (0.5 + 0.5 * sin(TIME * 3.0)) * 0.30;

		// --- Strisce sottili animate ---
		float stripe = sin(UV.x * 20.0 - TIME * 2.0) * 0.5 + 0.5;
		stripe = smoothstep(0.4, 0.6, stripe) * 0.07;

		// --- Pulse su completato/fallito ---
		float state_pulse = (completed + failed) * (0.5 + 0.5 * sin(TIME * 5.0)) * 0.15;

		// --- Fill finale ---
		vec3 fill = bar_color * (1.0 + stripe) * v_grad;
		fill += vec3(1.0) * shimmer;
		fill += bar_color * state_pulse;
		fill += vec3(1.0, 1.0, 0.8) * edge_glow;
		fill  = clamp(fill, 0.0, 1.0);

		COLOR = vec4(fill, 1.0);
	}
}
