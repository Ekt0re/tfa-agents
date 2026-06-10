shader_type canvas_item;

// Uniforms per la gestione della nebbia (sui livelli sottostanti)
uniform float fog_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 fog_color : source_color = vec4(0.05, 0.05, 0.1, 1.0); // Nebbia scura/bluastra

// Uniforms per la maschera di trasparenza circolare (quando il player passa sotto)
uniform bool use_mask = false;
uniform vec2 player_screen_position; // Posizione del player sullo schermo (in pixel)
uniform float mask_radius = 850.0;
uniform float mask_softness = 200.0;
uniform float ellipse_y_scale = 1.5; // Voglio un ovale orizzontale
uniform float semi_transparency_opacity : hint_range(0.0, 1.0) = 0.003; // Opacità NEL cerchio (0.0 = invisibile)

// NUOVO PARAMETRO: Controlla l'opacità del tetto ALL'ESTERNO del cerchio
uniform float base_roof_opacity : hint_range(0.0, 1.0) = 0.6; // 0.6 = il tetto fuori è trasparente al 40%

// Uniforms per le altre entità importanti a terra
uniform vec2 entity_screen_positions[24];
uniform int entity_count = 0;
uniform float entity_radius = 280.0;
uniform float entity_softness = 150.0;
void fragment() {
	// Preleva il colore originale della tile
	vec4 tex_color = texture(TEXTURE, UV);

	// Applica l'effetto fog miscelando con il colore della nebbia
	vec3 final_color = mix(tex_color.rgb, fog_color.rgb, fog_amount);

	// MODIFICA TRASPARENZA LIVELLI SOTTOSTANTI:
	// Più aumenta il fog_amount (ovvero più il livello è "in basso" rispetto al player),
	// più riduciamo l'alpha originaria del tile per farlo svanire nel vuoto.
	// Quando fog_amount è 0.75, l'opacità massima del livello sotto scenderà al 25% (1.0 - 0.75)
	float alpha = tex_color.a * (1.0 - (fog_amount * 0.85));

	if (use_mask) {
		float min_mask = 1.0;

		// 1. Maschera per il Player
		vec2 frag_coord_flipped = vec2(FRAGCOORD.x, FRAGCOORD.y);
		vec2 diff_player = frag_coord_flipped - vec2(player_screen_position.x, player_screen_position.y);
		diff_player.y *= ellipse_y_scale;
		float dist_player = length(diff_player);

		float mask_player = smoothstep(mask_radius - mask_softness, mask_radius, dist_player);
		min_mask = min(min_mask, mask_player);

		// 2. Maschera per le altre entità sul livello
		int safe_count = clamp(entity_count, 0, 24);
		for (int i = 0; i < safe_count; i++) {
			vec2 diff_ent = frag_coord_flipped - entity_screen_positions[i];
			diff_ent.y *= ellipse_y_scale;
			float dist_ent = length(diff_ent);
			float mask_ent = smoothstep(entity_radius - entity_softness, entity_radius, dist_ent);
			min_mask = min(min_mask, mask_ent);
		}

		float alpha_modifier = mix(semi_transparency_opacity, base_roof_opacity, min_mask);
		alpha *= alpha_modifier;
	}

	COLOR = vec4(final_color, alpha);
}
