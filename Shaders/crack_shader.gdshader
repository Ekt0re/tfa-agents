shader_type canvas_item;

uniform float damage_ratio : hint_range(0.0, 1.0) = 0.0;

uniform float crack_scale : hint_range(1.0, 20.0) = 10.0;
uniform float crack_width : hint_range(0.001, 0.05) = 0.01;
uniform float crack_strength : hint_range(0.0, 1.0) = 0.9;

vec2 hash(vec2 p){
	p = vec2(
		dot(p, vec2(127.1,311.7)),
		dot(p, vec2(269.5,183.3))
	);
	return fract(sin(p) * 43758.5453123);
}

float voronoi(vec2 uv){
	vec2 g = floor(uv);
	vec2 f = fract(uv);

	float res = 8.0;

	for(int y = -1; y <= 1; y++){
		for(int x = -1; x <= 1; x++){
			vec2 lattice = vec2(float(x), float(y));
			vec2 h = hash(g + lattice);
			vec2 r = lattice + h - f;
			float d = dot(r, r);
			res = min(res, d);
		}
	}

	return sqrt(res);
}

void fragment() {
	vec4 base = texture(TEXTURE, UV);

	float amount = smoothstep(0.05, 1.0, damage_ratio);

	vec2 uv = UV * crack_scale;

	float v1 = voronoi(uv);
	float v2 = voronoi(uv * 2.0);
	float v3 = voronoi(uv * 4.0);

	float cracks = 0.0;

	cracks += 1.0 - smoothstep(0.0, crack_width, v1);
	cracks += 1.0 - smoothstep(0.0, crack_width * 0.75, v2);
	cracks += 1.0 - smoothstep(0.0, crack_width * 0.5, v3);

	cracks = clamp(cracks, 0.0, 1.0);
	cracks *= amount;

	vec3 result = mix(
		base.rgb,
		base.rgb * (1.0 - crack_strength),
		cracks
	);

	COLOR = vec4(result, base.a);
}