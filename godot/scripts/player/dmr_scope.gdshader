shader_type canvas_item;

uniform float weight : hint_range(0.0, 1.0) = 1.0;
uniform float radius : hint_range(0.2, 0.48) = 0.43;
uniform float aspect = 1.7777778;

void fragment() {
	vec2 p = UV - 0.5;
	p.x *= aspect;
	float d = length(p);
	float outside = smoothstep(radius, radius + 0.004, d);
	float ring = 1.0 - smoothstep(0.002, 0.006, abs(d - radius));
	float horizontal = (1.0 - smoothstep(0.001, 0.003, abs(p.y))) * step(d, radius);
	float vertical = (1.0 - smoothstep(0.001, 0.003, abs(p.x))) * step(d, radius);
	float center_ring = 1.0 - smoothstep(0.002, 0.004, abs(d - 0.028));
	float center_dot = 1.0 - smoothstep(0.004, 0.006, d);
	float marks = max(ring, max(horizontal, max(vertical, max(center_ring, center_dot))));
	vec3 color = vec3(0.40, 0.95, 1.0) * marks;
	float alpha = max(outside, marks) * weight;
	COLOR = vec4(color, alpha);
}
