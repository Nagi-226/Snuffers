shader_type spatial;
render_mode cull_disabled;

// 铁栅栏竖条镂空（2026-09-27 巷弄周界围挡）：UV.x 沿栏长切竖条，
// 上下横档保留，其余 discard —— 真透视，看得到栏后铺路延伸与红砖长墙
uniform vec3 tint : source_color = vec3(0.30, 0.33, 0.30);
uniform float fence_length = 4.0;   // 栏长（米，builder 按段注入）
uniform float bar_period = 0.16;    // 竖条间距
uniform float bar_fill = 0.42;      // 竖条占空比
uniform float rail_low = 0.07;      // 下横档带（UV.y）
uniform float rail_high = 0.93;     // 上横档带

void fragment() {
	float u = UV.x * fence_length;
	float bar = step(fract(u / bar_period), bar_fill);
	float rail = step(UV.y, rail_low) + step(rail_high, UV.y);
	if (max(bar, rail) < 0.5) {
		discard;
	}
	ALBEDO = tint;
	METALLIC = 0.0;
	ROUGHNESS = 0.55;
}
