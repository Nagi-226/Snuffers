shader_type canvas_item;

uniform float weight : hint_range(0.0, 1.0) = 1.0;
uniform float radius : hint_range(0.2, 0.48) = 0.43;
uniform float aspect = 1.7777778;
uniform float center_style = 0.0; // 0=圆圈，1=菱形，2=榴弹下坠 V 形
uniform bool conventional_optic = false;
uniform vec4 conventional_reticle_color : source_color;
uniform int conventional_style = 0; // 1=ACOG，2=Mil-Dot，3=Duplex
uniform float conventional_reticle_half_width;
uniform float conventional_reticle_aa;
uniform vec2 sig516_chevron_size;
uniform float sig516_bdc_start;
uniform float sig516_bdc_step;
uniform int sig516_bdc_count;
uniform float sig516_bdc_half_width;
uniform float sig516_bdc_width_step;
uniform float sr25_mildot_spacing;
uniform float sr25_mildot_radius;
uniform int sr25_mildot_count;
uniform float m700_duplex_inner_length;
uniform float m700_duplex_outer_half_width;

float conventional_stroke(float distance_to_line, float half_width) {
	return 1.0 - smoothstep(half_width, half_width + conventional_reticle_aa, distance_to_line);
}

float segment_distance(vec2 point, vec2 start, vec2 end) {
	vec2 segment = end - start;
	float along = clamp(dot(point - start, segment) / max(dot(segment, segment), 0.00000001), 0.0, 1.0);
	return length(point - start - segment * along);
}

void fragment() {
	vec2 p = UV - 0.5;
	p.x *= aspect;
	float d = length(p);
	float outside = smoothstep(radius, radius + 0.004, d);
	float ring = 1.0 - smoothstep(0.002, 0.006, abs(d - radius));
	float horizontal = (1.0 - smoothstep(0.001, 0.003, abs(p.y))) * step(d, radius);
	float vertical = (1.0 - smoothstep(0.001, 0.003, abs(p.x))) * step(d, radius);
	float center_ring = 1.0 - smoothstep(0.002, 0.004, abs(d - 0.028));
	float center_diamond = 1.0 - smoothstep(0.002, 0.004, abs(abs(p.x) + abs(p.y) - 0.028));
	float center_shape = mix(center_ring, center_diamond, step(0.5, center_style));
	float grenade_mode = step(1.5, center_style);
	float chevron_wings = (1.0 - smoothstep(0.001, 0.003, abs(abs(p.x) * 0.65 + p.y + 0.012))) * step(abs(p.x), 0.022) * step(-0.025, p.y) * step(p.y, 0.01);
	center_shape = mix(center_shape, chevron_wings, grenade_mode);
	horizontal *= 1.0 - grenade_mode;
	vertical *= 1.0 - grenade_mode;
	float center_dot = 1.0 - smoothstep(0.004, 0.006, d);
	float marks = max(ring, max(horizontal, max(vertical, max(center_shape, center_dot))));
	vec3 color = (conventional_optic ? conventional_reticle_color.rgb : vec3(0.40, 0.95, 1.0)) * marks;
	float alpha = max(outside, marks) * weight;
	if (conventional_optic && conventional_style > 0) {
		float reticle_marks = 0.0;
		if (conventional_style == 1) {
			float left_wing = segment_distance(p, vec2(0.0), vec2(-sig516_chevron_size.x, sig516_chevron_size.y));
			float right_wing = segment_distance(p, vec2(0.0), sig516_chevron_size);
			reticle_marks = conventional_stroke(min(left_wing, right_wing), conventional_reticle_half_width);
			if (sig516_bdc_count > 0) {
				float last_row = sig516_bdc_start + float(sig516_bdc_count - 1) * sig516_bdc_step;
				float spine = segment_distance(p, vec2(0.0, sig516_bdc_start), vec2(0.0, last_row));
				reticle_marks = max(reticle_marks, conventional_stroke(spine, conventional_reticle_half_width));
			}
			for (int index = 0; index < sig516_bdc_count; index++) {
				float row = sig516_bdc_start + float(index) * sig516_bdc_step;
				float half_width = max(sig516_bdc_half_width - float(index) * sig516_bdc_width_step, 0.0);
				float bar = segment_distance(p, vec2(-half_width, row), vec2(half_width, row));
				reticle_marks = max(reticle_marks, conventional_stroke(bar, conventional_reticle_half_width));
			}
		} else if (conventional_style == 2) {
			reticle_marks = max(conventional_stroke(abs(p.y), conventional_reticle_half_width), conventional_stroke(abs(p.x), conventional_reticle_half_width));
			for (int index = 0; index < sr25_mildot_count; index++) {
				float offset = float(index + 1) * sr25_mildot_spacing;
				float horizontal_dots = min(length(p - vec2(offset, 0.0)), length(p + vec2(offset, 0.0)));
				float vertical_dots = min(length(p - vec2(0.0, offset)), length(p + vec2(0.0, offset)));
				reticle_marks = max(reticle_marks, conventional_stroke(min(horizontal_dots, vertical_dots), sr25_mildot_radius));
			}
		} else if (conventional_style == 3) {
			float horizontal_width = mix(conventional_reticle_half_width, m700_duplex_outer_half_width, step(m700_duplex_inner_length, abs(p.x)));
			float vertical_width = mix(conventional_reticle_half_width, m700_duplex_outer_half_width, step(m700_duplex_inner_length, abs(p.y)));
			reticle_marks = max(conventional_stroke(abs(p.y), horizontal_width), conventional_stroke(abs(p.x), vertical_width));
		}
		reticle_marks *= step(d, radius);
		color = conventional_reticle_color.rgb * reticle_marks;
		alpha = max(outside, max(ring, reticle_marks)) * weight;
	}
	COLOR = vec4(color, alpha);
}
