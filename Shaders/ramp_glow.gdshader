shader_type canvas_item;

// Colore del bagliore neon emesso dalla freccia
uniform vec4 glow_color : source_color = vec4(1.0, 0.5, 0.1, 1.0);

// Intensità del bagliore
uniform float glow_intensity : hint_range(0.0, 5.0) = 1.8;

// Velocità del respiro (pulsazione luminosa)
uniform float breathing_speed : hint_range(0.0, 10.0) = 2.2;

// Opacità massima dello sprite della rampa
uniform float base_opacity : hint_range(0.0, 1.0) = 0.85;

void fragment() {
	// Campiona la texture con le UV native fornite da Godot
	// Questo è sicuro al 100% con gli AtlasTexture e non mostrerà mai le tile adiacenti
	vec4 tex_color = texture(TEXTURE, UV);
	
	// Calcola l'oscillazione del respiro
	float breath = sin(TIME * breathing_speed);
	
	// Modulazione della luminosità (brilla in sincronia con il respiro)
	float brightness_factor = 1.6 + 0.5 * breath;
	
	// Modulazione dell'opacità
	float current_opacity = base_opacity + 0.1 * breath;
	
	vec4 final_color = tex_color;
	
	// Applica la luminosità e il contrasto per risaltare rispetto allo sfondo
	final_color.rgb *= brightness_factor;
	final_color.rgb = (final_color.rgb - vec3(0.5)) * 1.35 + vec3(0.5);
	
	// Incrementa la saturazione del colore arancione
	float luma = dot(final_color.rgb, vec3(0.299, 0.587, 0.114));
	final_color.rgb = mix(vec3(luma), final_color.rgb, 1.6);
	
	// Aggiunge un bagliore neon additivo sul corpo dello sprite
	if (tex_color.a > 0.0) {
		final_color.rgb += glow_color.rgb * glow_intensity * (0.5 + 0.5 * breath) * 0.25;
	}
	
	// Imposta l'opacità finale preservando fedelmente la trasparenza dello sprite
	final_color.a = tex_color.a * current_opacity;
	
	COLOR = final_color;
}
