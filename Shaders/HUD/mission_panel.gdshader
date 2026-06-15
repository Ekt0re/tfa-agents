// mission_panel.gdshader
// Applicare a MissionPanelInner (PanelContainer) come ShaderMaterial.
// Dal GDScript, imposta gli uniform tramite:
//   _panel.material.set_shader_parameter("mission_state", 0.0)  # normale
//   _panel.material.set_shader_parameter("mission_state", 1.0)  # completato
//   _panel.material.set_shader_parameter("mission_state", -1.0) # fallito
//   _panel.material.set_shader_parameter("state_time", 0.0)     # reset al cambio stato
shader_type canvas_item;

// 0 = normale, 1 = completato, -1 = fallito
uniform float mission_state   : hint_range(-1.0, 1.0) = 0.0;
// Tempo da quando è cambiato lo stato (reset a 0 ad ogni cambio)
uniform float state_time      : hint_range(0.0, 10.0) = 0.0;
// Intensità bordo animato (0 = niente)
uniform float border_strength : hint_range(0.0, 1.0) = 0.7;

void fragment() {
	vec4 base = texture(TEXTURE, UV);

	// ---------------------------------------------------------------
	// Distanze dai bordi (0 = sul bordo, sale verso il centro)
	// ---------------------------------------------------------------
	float dx = min(UV.x, 1.0 - UV.x);
	float dy = min(UV.y, 1.0 - UV.y);
	float edge = min(dx, dy);

	// Maschera bordo: 1 sul perimetro, 0 verso il centro
	float border_mask = 1.0 - smoothstep(0.0, 0.025, edge);
	// Maschera sfondo leggera (esclude solo il centro puro)
	float bg_mask = 1.0 - smoothstep(0.02, 0.12, edge);

	// ---------------------------------------------------------------
	// Luce viaggiante lungo i bordi (stato normale)
	// ---------------------------------------------------------------
	float travel = fract(TIME * 0.45);
	// Top edge
	float top  = smoothstep(0.012, 0.0, UV.y)
	           * smoothstep(0.07, 0.0, abs(UV.x - travel));
	// Bottom edge (sfasata di 0.5)
	float bot  = smoothstep(0.012, 0.0, 1.0 - UV.y)
	           * smoothstep(0.07, 0.0, abs(UV.x - fract(travel + 0.5)));
	// Left edge
	float lft  = smoothstep(0.012, 0.0, UV.x)
	           * smoothstep(0.07, 0.0, abs(UV.y - fract(travel + 0.25)));
	// Right edge
	float rgt  = smoothstep(0.012, 0.0, 1.0 - UV.x)
	           * smoothstep(0.07, 0.0, abs(UV.y - fract(travel + 0.75)));
	float traveling = (top + bot + lft + rgt) * 0.55 * border_strength;

	// Pulse lento del bordo (sempre attivo)
	float pulse = 0.4 + 0.6 * (0.5 + 0.5 * sin(TIME * 1.8));
	float border_glow = border_mask * pulse * border_strength * 0.5;

	// Colore bordo neutro (quasi bianco/azzurro)
	vec3 neutral_border = vec3(0.75, 0.85, 1.0) * (border_glow + traveling);

	// ---------------------------------------------------------------
	// Stato COMPLETATO (mission_state > 0.5)
	// ---------------------------------------------------------------
	float completed = smoothstep(0.5, 0.8, mission_state);

	// Fade-in rapido poi stabile
	float c_fade  = smoothstep(0.0, 0.25, state_time);
	// Pulse verde pulsante dopo il fade
	float c_pulse = 0.6 + 0.4 * sin(state_time * 4.0 - 1.0);
	float c_intensity = c_fade * c_pulse * completed;

	// Bordo verde
	vec3 green_border = vec3(0.15, 0.95, 0.35) * border_mask * c_intensity * 0.9;
	// Tint verde leggero sullo sfondo
	vec3 green_bg     = vec3(0.05, 0.25, 0.08) * bg_mask * c_intensity * 0.18;

	// ---------------------------------------------------------------
	// Stato FALLITO (mission_state < -0.5)
	// ---------------------------------------------------------------
	float failed = smoothstep(-0.8, -0.5, -mission_state);

	float f_fade  = smoothstep(0.0, 0.2, state_time);
	// Shake visivo: vibrazione rapida che si smorza
	float f_shake = sin(state_time * 28.0) * exp(-state_time * 4.0);
	float f_pulse = 0.7 + 0.3 * f_shake;
	float f_intensity = f_fade * f_pulse * failed;

	// Bordo rosso
	vec3 red_border = vec3(1.0, 0.18, 0.18) * border_mask * f_intensity * 0.9;
	// Tint rosso leggero
	vec3 red_bg     = vec3(0.25, 0.03, 0.03) * bg_mask * f_intensity * 0.18;

	// ---------------------------------------------------------------
	// Combina tutto
	// ---------------------------------------------------------------

	// I colori di stato sostituiscono il bordo neutro (non si sommano)
	float state_strength = clamp(completed + failed, 0.0, 1.0);
	vec3 final_border = mix(neutral_border,
	                        green_border + red_border,
	                        state_strength);

	vec3 final_bg = green_bg + red_bg;

	// Proteggi il testo: non alteriamo pixel già chiari (testo bianco/colorato)
	float lum = dot(base.rgb, vec3(0.299, 0.587, 0.114));
	float text_protect = 1.0 - smoothstep(0.45, 0.75, lum);

	vec3 result = base.rgb
	            + final_border * text_protect
	            + final_bg     * text_protect;

	result = clamp(result, 0.0, 1.0);
	COLOR = vec4(result, base.a);
}
