shader_type canvas_item;

uniform float weight : hint_range(0.0, 1.0) = 1.0;
uniform float radius : hint_range(0.2, 0.48) = 0.43;
uniform float aspect = 1.7777778;

void fragment() {
	vec2 p = UV - 0.5;
	p.x *= aspect;
	float d = length(p);
	float outside = smoothstep(radius, radius + 0.004, d);
	float rim = 1.0 - smoothstep(0.001, 0.004, abs(d - radius));
	float guide_rim = (1.0 - smoothstep(0.001, 0.003, abs(d - radius * 0.80))) * step(0.10, abs(p.x)) * step(0.10, abs(p.y));
	vec2 q = abs(p);
	float gate_x = (1.0 - smoothstep(0.001, 0.003, abs(q.x - 0.038))) * step(q.y, 0.038) * step(0.022, q.y);
	float gate_y = (1.0 - smoothstep(0.001, 0.003, abs(q.y - 0.038))) * step(q.x, 0.038) * step(0.022, q.x);
	float sight_x = (1.0 - smoothstep(0.0008, 0.002, q.y)) * step(q.x, 0.017) * step(0.006, q.x);
	float sight_y = (1.0 - smoothstep(0.0008, 0.002, q.x)) * step(q.y, 0.017) * step(0.006, q.y);
	float center_dot = 1.0 - smoothstep(0.0015, 0.003, d);
	float axis_marks = (1.0 - smoothstep(0.001, 0.003, q.y)) * step(0.10, q.x) * step(q.x, 0.26);
	axis_marks *= step(0.65, fract(q.x * 70.0));
	float marks = max(rim, max(guide_rim, max(gate_x, max(gate_y, max(sight_x, max(sight_y, max(center_dot, axis_marks)))))));
	COLOR = vec4(vec3(0.32, 0.90, 1.0) * marks, max(outside, marks) * weight);
}
