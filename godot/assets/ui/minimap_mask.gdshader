shader_type canvas_item;
// 圆形小地图遮罩（HUD 右上角 ASI 战术探测视图，2026-10-21 机主立项）
// SubViewportContainer 全矩形采样，圆外透明（带 3% 软边）
void fragment() {
	float r = length(UV - vec2(0.5)) * 2.0;
	COLOR = texture(TEXTURE, UV);
	COLOR.a *= 1.0 - smoothstep(0.97, 1.0, r);
}
