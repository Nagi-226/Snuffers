shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

// 球面边缘与细密脉冲纹理；不使用烟尘、火焰或破片。
uniform vec4 pulse_color : source_color;
uniform float pulse_time;
uniform float strength;
uniform float core;

void fragment() {
	float rim = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 2.8);
	float lines = pow(0.5 + 0.5 * sin(UV.y * 94.2478 - pulse_time * 24.0), 5.0);
	float glow = mix(0.025 + rim * (0.85 + lines * 0.35), 0.65 + rim * 0.35, core);
	// ADD 混合的消隐必须写入RGB，不能只减ALPHA。
	ALBEDO = pulse_color.rgb * glow * strength;
	ALPHA = clamp(strength, 0.0, 1.0);
}
