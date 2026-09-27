// skyline_facade.gdshader — AI 生成夜景立面贴图材质（塔楼盒体用）
//
// 机制：贴图即立面照片（albedo），按亮度阈值把亮窗/灯带提取为 EMISSION
// （夜雾里发光穿透），墙面按 wall_darken 压暗融入夜空。
// - render_mode fog_disabled：远景灯光不被指数雾吞掉（夜景天际线可见的前提）
// - instance uniform：brightness（外环调暗）、flip_x（同贴图塔楼镜像去重复感）
shader_type spatial;
render_mode fog_disabled, diffuse_lambert, specular_disabled;

uniform sampler2D facade_tex : source_color, filter_linear_mipmap;
uniform float wall_darken : hint_range(0.0, 1.0) = 0.55;  // 墙面压暗系数
uniform float emit_threshold : hint_range(0.0, 1.0) = 0.26; // 亮窗亮度阈值
uniform float emit_gain : hint_range(0.0, 6.0) = 1.7;     // 亮窗发光增益

instance uniform float brightness = 1.0;
instance uniform float flip_x = 0.0;

void fragment() {
	vec2 uv = UV;
	if (flip_x > 0.5) {
		uv.x = 1.0 - uv.x;
	}
	vec3 tex = texture(facade_tex, uv).rgb;
	float luma = dot(tex, vec3(0.299, 0.587, 0.114));
	float win = smoothstep(emit_threshold, emit_threshold + 0.28, luma);
	ALBEDO = tex * wall_darken;
	EMISSION = tex * win * emit_gain * brightness;
}
