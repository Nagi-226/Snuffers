// skyline_card.gdshader — 远景全景幕布卡（AI 生成全景贴图，第三层背景）
//
// 一圈面朝场景原点的 PlaneMesh 卡片，贴上 AI 生成的 CBD 夜景全景；
// 左/右/上边缘 UV 羽化透明，使多卡交叠处与夜空过渡自然；
// fog_disabled + unshaded：贴图自带夜景影调，发光穿透夜雾。
shader_type spatial;
render_mode fog_disabled, unshaded, cull_disabled, blend_mix, depth_prepass_alpha;

uniform sampler2D pano_tex : source_color, filter_linear_mipmap;
uniform float gain : hint_range(0.0, 4.0) = 1.15;   // 发光增益
uniform float feather : hint_range(0.0, 0.3) = 0.09; // 边缘羽化宽度（UV 比例）

void fragment() {
	vec4 tex = texture(pano_tex, UV);
	float ax = smoothstep(0.0, feather, UV.x) * (1.0 - smoothstep(1.0 - feather, 1.0, UV.x));
	float ay = smoothstep(0.0, feather * 1.5, UV.y); // 顶部溶入夜空
	ALBEDO = tex.rgb;
	EMISSION = tex.rgb * gain;
	ALPHA = ax * ay;
}
