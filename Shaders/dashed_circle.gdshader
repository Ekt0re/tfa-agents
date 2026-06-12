shader_type canvas_item;

uniform float radius = 0.40;
uniform float thickness = 0.008; // Sottile
uniform float dash_count = 36.0;
uniform float dash_speed = 1.0;
uniform float quality : hint_range(0.0, 1.0) = 1.0;

void fragment() {
    vec2 uv = UV - vec2(0.5);
    float dist = length(uv);
    
    float outer_edge = radius;
    float inner_edge = radius - thickness;
    float circle = 0.0;
    
    if (quality < 0.5) {
        circle = step(dist, outer_edge) - step(dist, inner_edge);
    } else {
        circle = smoothstep(outer_edge + 0.005, outer_edge - 0.005, dist) - smoothstep(inner_edge + 0.005, inner_edge - 0.005, dist);
    }
    
    float angle = atan(uv.y, uv.x);
    float dash_val = sin(angle * dash_count + TIME * dash_speed);
    float dash_mask = step(0.0, dash_val);
    
    // Use the vertex color (modulate / ColorRect color) to allow dynamic tinting
    COLOR = vec4(COLOR.rgb, COLOR.a * circle * dash_mask);
}
