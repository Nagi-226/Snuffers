// skyline_card.gdshader — 远景全景幕布卡（AI 生成全景贴图，第三层背景）
//
// 一圈面朝场景原点的 PlaneMesh 卡片，贴上 AI 生成的 CBD 夜景全景；
// 左/右/上边缘 UV 羽化透明，使多卡交叠处与夜空过渡自然；
// fog_disabled + unshaded：贴图自带夜景影调，发光穿透夜雾。
shader_type spatial;
render_mode fog_disabled, unshaded, cull_disabled, blend_mix, depth_prepass_alpha;

uniform sampler2D pano_tex : source_color, filter_linear_mipmap;
uniform float gain : hint_range(0.0, 4.0) = 1.15;   // 发光增益
uniform float feather : hint_range(0.0, 0.3) = 0.09; // 左右边缘羽化宽度（UV 比例）
// 场景夜空本色（builder 运行时从 WorldEnvironment 注入，保证天色单一事实源）：
// 贴图上半部分向该颜色收敛，卡顶完全等于场景天色——物理上不存在"两个夜空"分界线
uniform vec3 sky_color : source_color = vec3(0.024, 0.09, 0.18);

void fragment() {
	vec4 tex = texture(pano_tex, UV);
	// 天空色收敛：v<0.12 完全收敛为场景天色，0.12~0.42 渐进混合（塔尖仅轻微减饱和）
	vec3 col = tex.rgb;
	float converge = 1.0 - smoothstep(0.12, 0.42, UV.y);
	col = mix(col, sky_color, converge);
	float ax = smoothstep(0.0, feather, UV.x) * (1.0 - smoothstep(1.0 - feather, 1.0, UV.x));
	float ay = smoothstep(0.0, 0.15, UV.y); // 顶部 15% 透明渐隐，露出场景天空
	ALBEDO = col;
	EMISSION = col * gain;
	ALPHA = ax * ay;
}
