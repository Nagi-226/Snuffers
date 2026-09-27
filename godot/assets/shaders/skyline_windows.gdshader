// skyline_windows.gdshader — CBD 远景塔楼程序化夜景立面 v2（真实照片特征复现）
//
// v2 对照真实 CBD 夜景照片（广州珠江新城类）加入的特征：
// - 整层随机熄灯（加班层/无人层），亮窗不再均匀撒点；
// - 少量竖向常亮灯柱列（幕墙竖梃灯）；
// - 裙楼高度以下商业照明：更亮、更密、更暖；
// - 顶部两层"皇冠泛光"增亮 + 女儿墙轮廓灯带（中国 CBD 标志性 LED 勾边）；
// - 部分塔楼竖向 LED 灯带；少数高塔媒体立面（整楼缓慢变色波浪）；
// - 玻璃幕墙基色带微弱夜空反射渐变，不再是纯黑盒；
// - 天线桅杆子网格（is_antenna）顶端红色航空障碍灯闪烁。
//
// - render_mode fog_disabled：灯光穿透夜雾（夜景天际线可见的前提）；
// - 世界坐标窗格投影：退台体量各段窗格连续；
// - instance uniform 逐塔楼注入 seed_offset / tower_height / brightness /
//   neon_mode / media_mode / is_antenna，共享同一 ShaderMaterial。
shader_type spatial;
render_mode fog_disabled, diffuse_lambert, specular_disabled;

#include "res://assets/shaders/ow_noise.gdshaderinc"

uniform vec2 window_size = vec2(3.0, 3.5);      // 窗格尺寸 m（开间×层高）
uniform float lit_ratio : hint_range(0.0, 1.0) = 0.4; // 亮窗比例（普通办公层）
uniform float dark_floor_ratio : hint_range(0.0, 1.0) = 0.22; // 整层熄灯概率
uniform float podium_height = 12.0;             // 裙楼商业照明高度 m
uniform float emission_strength : hint_range(0.0, 8.0) = 2.6;
uniform vec3 wall_color : source_color = vec3(0.030, 0.038, 0.055);   // 幕墙深蓝灰
uniform vec3 warm_color : source_color = vec3(1.0, 0.78, 0.50);       // 暖白窗灯
uniform vec3 cold_color : source_color = vec3(0.55, 0.72, 1.0);       // 冷蓝窗灯
uniform vec3 beacon_color : source_color = vec3(1.0, 0.08, 0.05);     // 航空障碍红

instance uniform float seed_offset = 0.0;       // 每栋塔楼独立窗格种子
instance uniform float tower_height = 60.0;     // 楼顶/桅杆顶高度（皇冠/障碍灯判定）
instance uniform float brightness = 1.0;        // 外环剪影整体调暗
instance uniform float neon_mode = 0.0;         // 0 无 1 冷蓝白 2 暖金 3 变色
instance uniform float media_mode = 0.0;        // 1 = 媒体立面
instance uniform float is_antenna = 0.0;        // 1 = 天线桅杆子网格

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// 霓虹灯带配色
vec3 neon_color(float mode, float phase) {
	if (mode > 2.5) {
		// 缓慢变色（广州 LED 媒体勾边风）
		return vec3(0.5 + 0.5 * sin(TIME * 0.5 + phase),
		            0.5 + 0.5 * sin(TIME * 0.5 + phase + 2.094),
		            0.5 + 0.5 * sin(TIME * 0.5 + phase + 4.189));
	}
	if (mode > 1.5) {
		return vec3(1.0, 0.72, 0.38); // 暖金
	}
	return vec3(0.62, 0.80, 1.0);     // 冷蓝白
}

void fragment() {
	vec3 n = normalize(world_normal);

	// ---- 天线桅杆：暗杆 + 顶端闪烁红灯 ----
	if (is_antenna > 0.5) {
		ALBEDO = vec3(0.02, 0.02, 0.025);
		EMISSION = vec3(0.0);
		if (world_pos.y > tower_height - 1.5) {
			float blink = step(0.5, fract(TIME * 0.8 + seed_offset));
			EMISSION = beacon_color * 8.0 * blink * brightness;
		}
	} else if (abs(n.y) >= 0.5) {
		// ---- 屋顶/底面：哑暗 ----
		ALBEDO = wall_color * 0.6;
		EMISSION = vec3(0.0);
	} else {
		// ---- 侧墙立面 ----
		vec2 uvw = abs(n.x) > 0.5 ? world_pos.zy : world_pos.xy;
		vec2 grid = uvw / window_size;
		vec2 cell = floor(grid) + seed_offset;
		vec2 f = fract(grid);

		// 幕墙基色：深蓝灰 + 微弱夜空反射（越低越暗，靠近地平线微亮）
		float h01 = clamp(world_pos.y / max(tower_height, 1.0), 0.0, 1.0);
		ALBEDO = wall_color * (0.7 + 0.6 * h01);
		EMISSION = vec3(0.0);

		// 媒体立面：整楼缓慢变色波浪打底（低饱和蓝紫系，窗户仍叠加其上更亮）
		if (media_mode > 0.5) {
			vec3 media_col = vec3(0.5 + 0.5 * sin(TIME * 0.35 + world_pos.y * 0.045 + seed_offset),
			                      0.5 + 0.5 * sin(TIME * 0.35 + world_pos.y * 0.045 + seed_offset + 2.094),
			                      0.5 + 0.5 * sin(TIME * 0.35 + world_pos.y * 0.045 + seed_offset + 4.189));
			float media_grey = dot(media_col, vec3(0.3333));
			media_col = mix(vec3(media_grey), media_col, 0.5); // 降饱和
			media_col *= vec3(0.62, 0.80, 1.15);               // 偏蓝紫 LED 基调
			EMISSION += media_col * 0.42 * brightness;
		}

		// 竖向 LED 灯带（霓虹塔楼专属，连续整条，非窗格化）
		if (neon_mode > 0.5 && mod(uvw.x - seed_offset * 7.0, 9.0) < 0.3) {
			EMISSION += neon_color(neon_mode, seed_offset) * 3.5 * brightness;
		}

		// 女儿墙顶部轮廓灯带（勾边）
		if (neon_mode > 0.5 && world_pos.y > tower_height - 0.7 && world_pos.y <= tower_height + 0.1) {
			EMISSION += neon_color(neon_mode, seed_offset + 1.3) * 5.0 * brightness;
		}

		// 窗洞占格内 62%×70%，四周留墙梃
		bool in_window = f.x > 0.19 && f.x < 0.81 && f.y > 0.15 && f.y < 0.85;
		if (in_window) {
			float h1 = ow_hash12(cell);
			float h2 = ow_hash12(cell + 31.7);

			// 亮窗概率合成：整层熄灯 / 竖向常亮列 / 裙楼商业层 / 皇冠层
			float floor_id = floor(world_pos.y / window_size.y);
			float floor_rand = ow_hash12(vec2(floor_id + 0.5, seed_offset + 3.1));
			float col_rand = ow_hash12(vec2(floor(grid.x) + 0.5, seed_offset + 13.7));
			float p = lit_ratio;
			if (floor_rand < dark_floor_ratio) { p = 0.03; }            // 整层熄灯
			if (col_rand < 0.06) { p = 1.0; }                           // 竖向灯柱列
			if (world_pos.y < podium_height) { p = 0.78; }              // 裙楼商业照明
			if (world_pos.y > tower_height - window_size.y * 2.0) {
				p = max(p, 0.88);                                       // 皇冠泛光层
			}

			if (h1 < p) {
				// 裙楼更暖（商业暖光），塔身暖冷 65/35 分
				float cold_gate = world_pos.y < podium_height ? 0.85 : 0.65;
				vec3 win_col = mix(warm_color, cold_color, step(cold_gate, h2));
				float win_gain = mix(0.7, 1.3, ow_hash12(cell + 57.3)); // 每窗亮度微差
				float crown_boost = world_pos.y > tower_height - window_size.y * 2.0 ? 1.35 : 1.0;
				EMISSION += win_col * emission_strength * win_gain * crown_boost * brightness;
			} else {
				// 灭窗：玻璃微反光，避免死黑
				ALBEDO = wall_color * 1.6 + vec3(0.008, 0.012, 0.02);
			}
		}
	}
}
