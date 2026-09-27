shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix;

// EDAA 能量屏蔽力场（参考《半衰期2》联合军蓝色力场，2026-09-27 机主裁决）
// 纵向流动扫描带 + 细密横线 + 两端发射柱方向边缘增亮 + 高频闪烁

uniform vec4 field_color : source_color = vec4(0.30, 0.65, 1.0, 1.0);
uniform float band_density = 6.0;      // 纵向主扫描带数
uniform float band_speed = 0.55;       // 主扫描带向上流动速度
uniform float line_density = 60.0;     // 细横线密度
uniform float flicker_speed = 9.0;     // 整体闪烁频率
uniform float base_alpha = 0.16;
uniform float band_alpha = 0.30;
uniform float edge_alpha = 0.35;       // 靠近发射柱两端的增亮

void fragment() {
	// 主扫描带：缓慢向上流动的宽亮带
	float band = pow(0.5 + 0.5 * sin(UV.y * band_density * 6.28318 + TIME * band_speed * 6.28318), 3.0);
	// 细横线：力场的"格栅感"
	float line = 0.5 + 0.5 * sin(UV.y * line_density * 6.28318 - TIME * band_speed * 12.5664);
	line = smoothstep(0.75, 1.0, line) * 0.5;
	// 高频微闪烁（能量不稳定感）
	float flicker = 0.92 + 0.08 * sin(TIME * flicker_speed) * sin(TIME * flicker_speed * 1.73 + 1.3);
	// 两端（靠近发射柱）增亮收边
	float edge = pow(abs(UV.x - 0.5) * 2.0, 6.0);

	float alpha = (base_alpha + band * band_alpha + line * 0.18 + edge * edge_alpha) * flicker;
	ALBEDO = field_color.rgb * (0.85 + band * 0.6 + edge * 0.8);
	ALPHA = clamp(alpha, 0.0, 0.9);
}
