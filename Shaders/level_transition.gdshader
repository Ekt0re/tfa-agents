shader_type canvas_item;

// Uniforms per la gestione della nebbia (sui livelli sottostanti)
uniform float fog_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 fog_color : source_color = vec4(0.05, 0.05, 0.1, 1.0); // Nebbia scura/bluastra

// Uniforms per la maschera di trasparenza circolare (quando il player passa sotto)
uniform bool use_mask = false;
uniform vec2 player_screen_position; // Posizione del player sullo schermo (in pixel)
uniform float mask_radius = 1850.0; 
uniform float mask_softness = 250.0;
uniform float ellipse_y_scale = 1.6; // Schiacciamento verticale (es. 1.6x) per l'ovale orizzontale
uniform float semi_transparency_opacity : hint_range(0.0, 1.0) = 0.35; // Opacità del resto del livello sopra quando il player è sotto

// CORREZIONE: Aggiunte le parentesi quadre della dimensione [24] per combaciare con l'array inviato dal Player
uniform vec2 entity_screen_positions[24];
uniform int entity_count = 0;
uniform float entity_radius = 380.0;
uniform float entity_softness = 90.0;

void fragment() {
	// Preleva il colore originale della tile
	vec4 tex_color = texture(TEXTURE, UV);
	
	// Applica l'effetto fog miscelando con il colore della nebbia
	vec3 final_color = mix(tex_color.rgb, fog_color.rgb, fog_amount);
	
	// Calcola l'opacità di base
	float alpha = tex_color.a;
	
	if (use_mask) {
		float min_mask = 1.0;
		
		// 1. Maschera per il Player
		vec2 diff_player = FRAGCOORD.xy - player_screen_position;
		diff_player.y *= ellipse_y_scale;
		float dist_player = length(diff_player);
		float mask_player = smoothstep(mask_radius - mask_softness, mask_radius, dist_player);
		min_mask = min(min_mask, mask_player);
		
		// 2. Maschera per le altre entità/oggetti importanti sul Livello 0
		// Tagliamo il ciclo al massimo consentito per evitare overflow
		int safe_count = clamp(entity_count, 0, 24);
		for (int i = 0; i < safe_count; i++) {
			vec2 diff_ent = FRAGCOORD.xy - entity_screen_positions[i];
			diff_ent.y *= ellipse_y_scale;
			float dist_ent = length(diff_ent);
			float mask_ent = smoothstep(entity_radius - entity_softness, entity_radius, dist_ent);
			min_mask = min(min_mask, mask_ent);
		}
		
		// CORREZIONE LOGICA: Mantieni il tetto opaco (1.0) e crea i buchi trasparenti (semi_transparency_opacity)
		// dove camminano player ed entità (quando min_mask si avvicina a 0.0)
		float alpha_modifier = mix(semi_transparency_opacity, 1.0, min_mask);
		alpha *= alpha_modifier;
	}
	
	COLOR = vec4(final_color, alpha);
}
