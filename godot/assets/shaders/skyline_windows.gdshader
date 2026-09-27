// skyline_windows.gdshader — CBD 远景塔楼程序化亮窗（夜景天际线专用）
//
// 设计要点：
// - render_mode fog_disabled：塔楼不吃场景指数雾，亮窗得以穿透夜雾
//   （雾里看远处城市灯光反而更亮的观感），墙面的暗色剪影由配色负责融进夜空。
// - 世界坐标投影分格：窗格尺寸以米计，与塔楼缩放无关；按世界法线选投影面，
//   屋顶/地面（法线朝上）不画窗。
// - instance uniform：每栋塔楼用 set_instance_shader_parameter 注入
//   seed_offset / tower_height / brightness，共享同一 ShaderMaterial。
// - 高于 beacon_min_height 的塔楼顶层画闪烁红色航空障碍灯。
shader_type spatial;
render_mode fog_disabled, diffuse_lambert, specular_disabled;

#include "res://assets/shaders/ow_noise.gdshaderinc"

uniform vec2 window_size = vec2(3.0, 3.5);      // 窗格尺寸 m（开间×层高）
uniform float lit_ratio : hint_range(0.0, 1.0) = 0.4; // 亮窗比例
uniform vec3 wall_color : source_color = vec3(0.030, 0.038, 0.055);   // 深蓝灰墙面
uniform vec3 warm_color : source_color = vec3(1.0, 0.78, 0.50);       // 暖白窗灯
uniform vec3 cold_color : source_color = vec3(0.55, 0.72, 1.0);       // 冷蓝窗灯
uniform float emission_strength : hint_range(0.0, 8.0) = 2.6;
uniform float beacon_min_height = 80.0;         // 高于此高度顶部亮红灯
uniform vec3 beacon_color : source_color = vec3(1.0, 0.08, 0.05);

instance uniform float seed_offset = 0.0;       // 每栋塔楼独立窗格种子
instance uniform float tower_height = 60.0;     // 用于顶层障碍灯判定
instance uniform float brightness = 1.0;        // 外环剪影可整体调暗

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(world_normal);
	ALBEDO = wall_color;
	EMISSION = vec3(0.0);

	if (abs(n.y) < 0.5) {
		// 侧墙：按朝向选投影平面（x 向墙用 zy，z 向墙用 xy）
		vec2 uvw = abs(n.x) > 0.5 ? world_pos.zy : world_pos.xy;
		vec2 cell = floor(uvw / window_size) + seed_offset;
		vec2 f = fract(uvw / window_size);

		// 窗洞占格内 62%×70%，四周留墙梃
		bool in_window = f.x > 0.19 && f.x < 0.81 && f.y > 0.15 && f.y < 0.85;

		if (in_window) {
			float h1 = ow_hash12(cell);
			float h2 = ow_hash12(cell + 31.7);
			if (h1 < lit_ratio) {
				vec3 win_col = mix(warm_color, cold_color, step(0.65, h2));
				float win_gain = mix(0.7, 1.3, ow_hash12(cell + 57.3)); // 每窗亮度微差
				EMISSION = win_col * emission_strength * win_gain * brightness;
			} else {
				// 灭窗：微亮的玻璃反光，避免死黑
				ALBEDO = wall_color * 1.6 + vec3(0.008, 0.012, 0.02);
			}
		}

		// 顶层航空障碍红灯（闪烁），只画在朝向外的墙上沿一格
		float top_band = tower_height - window_size.y * 0.5;
		if (tower_height >= beacon_min_height && world_pos.y > top_band && f.x > 0.44 && f.x < 0.56) {
			float blink = step(0.5, fract(TIME * 0.8 + seed_offset));
			EMISSION += beacon_color * 6.0 * blink * brightness;
		}
	}
}
